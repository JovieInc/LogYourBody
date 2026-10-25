/** @jest-environment node */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import type { NextConfig } from 'next';

const repositoryRoot = resolve(__dirname, '../../../..');

describe('Vercel Git deployment configuration', () => {
  it.each([
    ['repository root', resolve(repositoryRoot, 'vercel.json')],
    ['web project root', resolve(repositoryRoot, 'apps/web/vercel.json')],
  ])(
    '%s keeps Production on Actions, skips bot-only refs, and builds the web workspace with its dependencies',
    (scope, configPath) => {
      const config = JSON.parse(readFileSync(configPath, 'utf8'));
      const isWebProjectRoot = scope === 'web project root';
      const installCommand = isWebProjectRoot
        ? 'cd ../.. && corepack pnpm install --frozen-lockfile && cd apps/web'
        : 'corepack pnpm install --frozen-lockfile';
      const buildCommand = isWebProjectRoot
        ? 'cd ../.. && corepack pnpm turbo run build --filter=logyourbody...'
        : 'corepack pnpm turbo run build --filter=logyourbody...';

      // main ships through deploy.yml; bot-only refs never queue preview builds
      // (.github/scripts/verify-vercel-branch-exclusions.test.mjs, 2026-10-20).
      expect(config.git.deploymentEnabled).toEqual({
        main: false,
        'backup/**': false,
        'archive/**': false,
        'stash/**': false,
        'gh-readonly-queue/**': false,
      });
      expect(config.github.silent).toBe(true);
      expect(config.installCommand).toContain(installCommand);
      expect(config.buildCommand).toBe(buildCommand);
    },
  );
});

describe('Sentry build configuration', () => {
  const originalEnv = process.env;
  const withSentryConfig = jest.fn((config: NextConfig) => config);

  function loadConfig(): NextConfig {
    let config: NextConfig = {};
    jest.isolateModules(() => {
      jest.doMock('@sentry/nextjs', () => ({ withSentryConfig }));
      config = require('../../next.config').default;
    });
    return config;
  }

  beforeEach(() => {
    process.env = { ...originalEnv, VERCEL_GIT_COMMIT_SHA: 'deployed-commit' };
    delete process.env.NEXT_PUBLIC_SENTRY_RELEASE;
    delete process.env.SENTRY_AUTH_TOKEN;
    delete process.env.SENTRY_ORG;
    delete process.env.SENTRY_PROJECT;
    withSentryConfig.mockClear();
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it('uses the deployed commit for runtime events without upload credentials', () => {
    expect(loadConfig().env?.NEXT_PUBLIC_SENTRY_RELEASE).toBe('deployed-commit');
    expect(withSentryConfig).not.toHaveBeenCalled();
  });

  it.each(['SENTRY_AUTH_TOKEN', 'SENTRY_ORG', 'SENTRY_PROJECT'])(
    'does not upload sourcemaps without %s',
    (missing) => {
      Object.assign(process.env, {
        SENTRY_AUTH_TOKEN: 'test-upload-token',
        SENTRY_ORG: 'test-org',
        SENTRY_PROJECT: 'test-project',
      });
      delete process.env[missing];
      loadConfig();
      expect(withSentryConfig).not.toHaveBeenCalled();
    },
  );

  it.each([undefined, 'explicit-release'])(
    'uses the same release for sourcemaps and runtime events (override: %s)',
    (override) => {
      Object.assign(process.env, {
        SENTRY_AUTH_TOKEN: 'test-upload-token',
        SENTRY_ORG: 'test-org',
        SENTRY_PROJECT: 'test-project',
      });
      if (override) process.env.NEXT_PUBLIC_SENTRY_RELEASE = override;
      const config = loadConfig();
      expect(withSentryConfig).toHaveBeenCalledWith(
        expect.anything(),
        expect.objectContaining({
          release: { name: config.env?.NEXT_PUBLIC_SENTRY_RELEASE },
          sourcemaps: { deleteSourcemapsAfterUpload: true },
          telemetry: false,
        }),
      );
    },
  );

  it('makes upload configuration and commit identity available to the Turbo build', () => {
    const turbo = JSON.parse(readFileSync(resolve(repositoryRoot, 'turbo.json'), 'utf8'));
    expect(turbo.tasks.build.env).toEqual(
      expect.arrayContaining([
        'SENTRY_AUTH_TOKEN',
        'SENTRY_ORG',
        'SENTRY_PROJECT',
        'VERCEL_GIT_COMMIT_SHA',
      ]),
    );
  });
});
