import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

import {
  REQUIRED_VERCEL_CHAT_RUNTIME_VARS,
  findMissingRequiredVariables,
  formatVerificationErrors,
  verifyVercelChatRuntimeEnv,
} from './verify-vercel-chat-runtime-env.mjs';

const scriptPath = fileURLToPath(new URL('./verify-vercel-chat-runtime-env.mjs', import.meta.url));

const COMPLETE_ENV = [
  'DATABASE_URL="postgres://lyb.example/db"',
  'OPENAI_API_KEY="sk-test-not-a-secret"',
  'CRON_SECRET="cron-test-not-a-secret"',
].join('\n');

function pathWithoutRg(basePath = process.env.PATH ?? '') {
  return basePath
    .split(':')
    .filter((dir) => dir.length > 0 && !existsSync(join(dir, 'rg')))
    .join(':');
}

function runChecker(envFile, extraEnv = {}) {
  return spawnSync(process.execPath, [scriptPath, envFile], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: pathWithoutRg(),
      ...extraEnv,
    },
  });
}

test('requires the authenticated chat runtime variables', () => {
  assert.deepEqual(
    [...REQUIRED_VERCEL_CHAT_RUNTIME_VARS],
    ['DATABASE_URL', 'OPENAI_API_KEY', 'CRON_SECRET'],
  );
});

test('accepts a complete Vercel production env file', () => {
  assert.deepEqual(findMissingRequiredVariables(COMPLETE_ENV), []);
  assert.equal(verifyVercelChatRuntimeEnv({ contents: COMPLETE_ENV }).ok, true);
});

test('treats commented or empty assignments as missing', () => {
  const contents = [
    '# DATABASE_URL="postgres://commented"',
    'DATABASE_URL=',
    'OPENAI_API_KEY=""',
    'CRON_SECRET="present"',
  ].join('\n');

  assert.deepEqual(findMissingRequiredVariables(contents), ['DATABASE_URL', 'OPENAI_API_KEY']);
});

test('reports every missing required variable without printing values', () => {
  const result = verifyVercelChatRuntimeEnv({
    envFile: '.vercel/.env.production.local',
    contents: 'UNRELATED="1"\n',
  });
  const errors = formatVerificationErrors(result).join('\n');

  assert.equal(result.ok, false);
  assert.match(errors, /DATABASE_URL/);
  assert.match(errors, /OPENAI_API_KEY/);
  assert.match(errors, /CRON_SECRET/);
  assert.doesNotMatch(errors, /postgres:\/\//);
  assert.doesNotMatch(errors, /sk-/);
});

test('CLI succeeds on a complete env file when rg is absent from PATH', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-vercel-env-ok-'));
  const envFile = join(dir, '.env.production.local');
  writeFileSync(envFile, COMPLETE_ENV);

  const result = runChecker(envFile);

  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stderr, '');
});

test('CLI fails closed when required variables are missing', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-vercel-env-missing-'));
  const envFile = join(dir, '.env.production.local');
  writeFileSync(envFile, 'OPENAI_API_KEY="sk-test-not-a-secret"\n');

  const result = runChecker(envFile);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Missing required Vercel production variable: DATABASE_URL/);
  assert.match(result.stderr, /Missing required Vercel production variable: CRON_SECRET/);
  assert.doesNotMatch(result.stderr, /Missing required Vercel production variable: OPENAI_API_KEY/);
});

test('CLI fails closed when the env file is missing', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-vercel-env-absent-'));
  const envFile = join(dir, '.env.production.local');

  const result = runChecker(envFile);

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Missing Vercel production env file/);
});

test('does not false-fail when a broken rg binary is first on PATH', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-rg-stub-'));
  const rgPath = join(dir, 'rg');
  writeFileSync(rgPath, '#!/bin/sh\necho "rg should not be used" >&2\nexit 127\n');
  chmodSync(rgPath, 0o755);

  const envFile = join(dir, '.env.production.local');
  writeFileSync(envFile, COMPLETE_ENV);

  const result = spawnSync(process.execPath, [scriptPath, envFile], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${dir}:${process.env.PATH ?? ''}`,
    },
  });

  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stderr, /rg should not be used/);
});
