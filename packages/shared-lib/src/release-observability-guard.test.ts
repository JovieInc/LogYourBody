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
        CLERK_FRONTEND_API: 'https://clerk.logyourbody.com',
        CLERK_PUBLISHABLE_KEY: 'pk_live_redacted',
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
        expect(source).toContain('Values redacted: true');
      }
    } finally {
      rmSync(result.outputDir, { force: true, recursive: true });
    }
  });
});
