/** @jest-environment node */
import { execFileSync } from 'node:child_process';
import path from 'node:path';

jest.mock('@next/bundle-analyzer', () => () => (config: unknown) => config);
jest.mock('@sentry/nextjs/config', () => ({
  withSentryConfig: jest.fn((config: unknown) => config),
}));

describe('Sentry build configuration', () => {
  // The mock above hides the real package surface, which let a v11 upgrade ship a next.config that
  // imported withSentryConfig from the root entry (undefined at build time, production undeployed).
  it('imports withSentryConfig from a specifier the real package exports', () => {
    const fs = require('node:fs');
    const source = fs.readFileSync(path.join(__dirname, '../../../../next.config.ts'), 'utf8');
    const specifier = /import \{ withSentryConfig \} from '([^']+)'/.exec(source)?.[1];
    expect(specifier).toBeDefined();
    const actual = jest.requireActual(specifier as string);
    expect(typeof actual.withSentryConfig).toBe('function');
  });

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
      const { withSentryConfig } = require('@sentry/nextjs/config');
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
      const { withSentryConfig } = require('@sentry/nextjs/config');
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
