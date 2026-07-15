import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));

describe('iOS release observability guard', () => {
  function runReleaseConfig(extraEnv: Record<string, string | undefined> = {}) {
    const outputDir = mkdtempSync(join(tmpdir(), 'lyb-release-config-'));
    const summaryPath = join(outputDir, 'github-step-summary.md');

    execFileSync('bash', ['apps/ios/Scripts/write_release_config.sh'], {
      cwd: repoRoot,
      env: {
        HOME: process.env.HOME,
        LANG: process.env.LANG,
        PATH: process.env.PATH,
        TMPDIR: process.env.TMPDIR,
        API_BASE_URL: 'https://www.logyourbody.com',
        API_EXPECTED_HOST: 'www.logyourbody.com',
        BODYSPEC_CLIENT_ID: '',
        BODYSPEC_REDIRECT_URI: '',
        AUTH_PROVIDER_ID: 'custom:jovie',
        AUTH_REDIRECT_URI: 'logyourbody://oauth',
        GITHUB_STEP_SUMMARY: summaryPath,
        IOS_CONFIG_OUTPUT_DIR: outputDir,
        REVENUE_CAT_PUBLIC_KEY: 'appl_redacted',
        SENTRY_ENVIRONMENT: 'production',
        SENTRY_TRACES_SAMPLE_RATE: '0.1',
        STATSIG_ENVIRONMENT_TIER: 'production',
        SUPABASE_ANON_KEY: 'supabase-anon-redacted',
        SUPABASE_EXPECTED_HOST: 'project.supabase.co',
        SUPABASE_URL: 'https://project.supabase.co',
        ...extraEnv,
      },
      stdio: 'pipe',
    });

    return {
      observability: readFileSync(
        join(outputDir, 'LogYourBody', 'release-observability.md'),
        'utf8',
      ),
      outputDir,
      summary: readFileSync(summaryPath, 'utf8'),
    };
  }

  function expectReleaseConfigFailure(extraEnv: Record<string, string | undefined>) {
    const outputDir = mkdtempSync(join(tmpdir(), 'lyb-release-config-'));
    const summaryPath = join(outputDir, 'github-step-summary.md');

    try {
      expect(() =>
        execFileSync('bash', ['apps/ios/Scripts/write_release_config.sh'], {
          cwd: repoRoot,
          env: {
            HOME: process.env.HOME,
            LANG: process.env.LANG,
            PATH: process.env.PATH,
            TMPDIR: process.env.TMPDIR,
            API_BASE_URL: 'https://www.logyourbody.com',
            API_EXPECTED_HOST: 'www.logyourbody.com',
            BODYSPEC_CLIENT_ID: '',
            BODYSPEC_REDIRECT_URI: '',
            AUTH_PROVIDER_ID: 'custom:jovie',
            AUTH_REDIRECT_URI: 'logyourbody://oauth',
            GITHUB_STEP_SUMMARY: summaryPath,
            IOS_CONFIG_OUTPUT_DIR: outputDir,
            REVENUE_CAT_PUBLIC_KEY: 'appl_redacted',
            SENTRY_DSN: '',
            SENTRY_ENVIRONMENT: 'production',
            SENTRY_TRACES_SAMPLE_RATE: '0.1',
            STATSIG_CLIENT_SDK_KEY: '',
            STATSIG_ENVIRONMENT_TIER: 'production',
            SUPABASE_ANON_KEY: 'supabase-anon-redacted',
            SUPABASE_EXPECTED_HOST: 'project.supabase.co',
            SUPABASE_URL: 'https://project.supabase.co',
            ...extraEnv,
          },
          stdio: 'pipe',
        }),
      ).toThrow();
    } finally {
      rmSync(outputDir, { force: true, recursive: true });
    }
  }

  it('emits redacted Sentry and Statsig configuration status without secret values', () => {
    const sentryDsn = 'https://public@example.ingest.sentry.io/123';
    const statsigKey = 'client-prod-secret';
    const result = runReleaseConfig({
      SENTRY_DSN: sentryDsn,
      STATSIG_CLIENT_SDK_KEY: statsigKey,
    });

    try {
      for (const source of [result.observability, result.summary]) {
        expect(source).toContain('Sentry configured: true');
        expect(source).toContain('Statsig configured: true');
        expect(source).toContain('Sentry traces sample rate valid: true');
        expect(source).toContain('Provider smoke proof required: true');
        expect(source).toContain('Values redacted: true');
        expect(source).not.toContain(sentryDsn);
        expect(source).not.toContain(statsigKey);
      }
    } finally {
      rmSync(result.outputDir, { force: true, recursive: true });
    }
  });

  it('records false booleans when optional observability providers are absent', () => {
    const result = runReleaseConfig({
      SENTRY_DSN: '',
      STATSIG_CLIENT_SDK_KEY: '',
    });

    try {
      for (const source of [result.observability, result.summary]) {
        expect(source).toContain('Sentry configured: false');
        expect(source).toContain('Statsig configured: false');
        expect(source).toContain('Sentry traces sample rate valid: true');
        expect(source).toContain('Provider smoke proof required: false');
        expect(source).toContain('Values redacted: true');
      }
    } finally {
      rmSync(result.outputDir, { force: true, recursive: true });
    }
  });

  it.each(['-0.01', '1.01', 'not-a-number'])(
    'fails closed when SENTRY_TRACES_SAMPLE_RATE is %s',
    (sampleRate) => {
      expectReleaseConfigFailure({
        SENTRY_TRACES_SAMPLE_RATE: sampleRate,
      });
    },
  );
});
