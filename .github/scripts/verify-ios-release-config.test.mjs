import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { test } from 'node:test';

const script = resolve('apps/ios/Scripts/write_release_config.sh');

function runReleaseConfig(extraEnv) {
  const outputDir = mkdtempSync(join(tmpdir(), 'lyb-release-config-'));
  const result = spawnSync('bash', [script], {
    encoding: 'utf8',
    env: {
      PATH: process.env.PATH,
      HOME: process.env.HOME,
      IOS_CONFIG_OUTPUT_DIR: outputDir,
      GITHUB_STEP_SUMMARY: '',
      REVENUE_CAT_PUBLIC_KEY: 'appl_testPublicKey',
      ...extraEnv,
    },
  });
  return { result, outputDir };
}

test('release config fails when SENTRY_DSN is missing', () => {
  const { result, outputDir } = runReleaseConfig({});
  try {
    assert.notEqual(result.status, 0, 'a release without crash reporting must not build');
    assert.match(result.stderr, /SENTRY_DSN/);
  } finally {
    rmSync(outputDir, { recursive: true, force: true });
  }
});

test('release config writes SENTRY_DSN when provided', () => {
  const { result, outputDir } = runReleaseConfig({
    SENTRY_DSN: 'https://publickey@o1.example.com/2',
  });
  try {
    assert.equal(result.status, 0, result.stderr);
    const config = readFileSync(join(outputDir, 'LogYourBody', 'Config.xcconfig'), 'utf8');
    assert.match(config, /^SENTRY_DSN = https:\/\$\(\)\/publickey@o1\.example\.com\/2$/m);
  } finally {
    rmSync(outputDir, { recursive: true, force: true });
  }
});
