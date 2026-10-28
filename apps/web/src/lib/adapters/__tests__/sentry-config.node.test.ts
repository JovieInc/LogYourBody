/** @jest-environment node */
import { execFileSync } from 'node:child_process';
import path from 'node:path';

jest.mock('@next/bundle-analyzer', () => () => (config: unknown) => config);
jest.mock('@sentry/nextjs', () => ({
  withSentryConfig: jest.fn((config: unknown) => config),
}));

describe('Sentry build configuration', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = {
      ...originalEnv,
      SENTRY_AUTH_TOKEN: 'test-upload-token',
      SENTRY_ORG: 'test-org',
      SENTRY_PROJECT: 'test-project',
    };
    delete process.env.NEXT_PUBLIC_SENTRY_RELEASE;
    delete process.env.VERCEL_GIT_COMMIT_SHA;
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it.each(['commit', 'explicit', 'version'])(
    'uses the same %s release for events and sourcemaps',
    (source) => {
      if (source !== 'version') process.env.VERCEL_GIT_COMMIT_SHA = 'deployed-commit';
      if (source === 'explicit') process.env.NEXT_PUBLIC_SENTRY_RELEASE = 'explicit-release';

      const config = require('../../../../next.config').default;
      const { withSentryConfig } = require('@sentry/nextjs');
      const release =
        source === 'version'
          ? require('../../../../package.json').version
          : source === 'explicit'
            ? 'explicit-release'
            : 'deployed-commit';

      expect(config.env.NEXT_PUBLIC_SENTRY_RELEASE).toBe(release);
      expect(withSentryConfig).toHaveBeenCalledWith(
        config,
        expect.objectContaining({
          release: { name: release },
          sourcemaps: { deleteSourcemapsAfterUpload: true },
          telemetry: false,
        }),
      );
    },
  );

  it.each(['SENTRY_AUTH_TOKEN', 'SENTRY_ORG', 'SENTRY_PROJECT'])(
    'does not upload without %s',
    (key) => {
      delete process.env[key];
      require('../../../../next.config');
      const { withSentryConfig } = require('@sentry/nextjs');
      expect(withSentryConfig).not.toHaveBeenCalled();
    },
  );

  it('passes upload credentials and the commit release through the production build task', () => {
    const dryRun = execFileSync(
      'corepack',
      ['pnpm', '--silent', 'build', '--filter=logyourbody', '--dry=json'],
      {
        cwd: path.resolve(__dirname, '../../../../../..'),
        env: { ...process.env, VERCEL_GIT_COMMIT_SHA: 'deployed-commit' },
        encoding: 'utf8',
      },
    );
    const task = JSON.parse(dryRun).tasks.find(
      (item: { taskId: string }) => item.taskId === 'logyourbody#build',
    );
    const variables = task.environmentVariables.configured.map(
      (item: string) => item.split('=')[0],
    );
    expect(variables).toEqual(
      expect.arrayContaining([
        'SENTRY_AUTH_TOKEN',
        'SENTRY_ORG',
        'SENTRY_PROJECT',
        'VERCEL_GIT_COMMIT_SHA',
      ]),
    );
  });
});
