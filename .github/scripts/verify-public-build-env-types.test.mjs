import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { findSensitivePublicVars, run } from './verify-public-build-env-types.mjs';

const env = { VERCEL_TOKEN: 't', VERCEL_ORG_ID: 'team_x', VERCEL_PROJECT_ID: 'prj_x' };
const silent = { log() {}, error() {} };

test('flags sensitive NEXT_PUBLIC_* variables with their targets, never values', () => {
  const failures = findSensitivePublicVars([
    { key: 'NEXT_PUBLIC_SENTRY_DSN', type: 'sensitive', target: ['production'], value: 'secret-value' },
    { key: 'NEXT_PUBLIC_SENTRY_DSN', type: 'sensitive', target: ['preview'] },
    { key: 'NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY', type: 'encrypted', target: ['production'] },
    { key: 'SENTRY_AUTH_TOKEN', type: 'sensitive', target: ['production'] },
  ]);
  assert.equal(failures.length, 1);
  assert.match(failures[0], /NEXT_PUBLIC_SENTRY_DSN.*preview, production/);
  assert.doesNotMatch(failures[0], /secret-value/);
});

test('passes when every NEXT_PUBLIC_* variable is plain or encrypted', () => {
  assert.deepEqual(findSensitivePublicVars([{ key: 'NEXT_PUBLIC_A', type: 'plain', target: ['production'] }]), []);
});

test('run fails on a sensitive public var and on an API error, passes otherwise', async () => {
  const ok = async () => ({ ok: true, json: async () => ({ envs: [{ key: 'NEXT_PUBLIC_A', type: 'plain', target: ['production'] }] }) });
  const bad = async () => ({ ok: true, json: async () => ({ envs: [{ key: 'NEXT_PUBLIC_A', type: 'sensitive', target: ['production'] }] }) });
  const down = async () => ({ ok: false, status: 500 });
  assert.equal(await run({ env, fetchImpl: ok, log: silent }), 0);
  assert.equal(await run({ env, fetchImpl: bad, log: silent }), 1);
  assert.equal(await run({ env, fetchImpl: down, log: silent }), 1);
  assert.equal(await run({ env: {}, fetchImpl: ok, log: silent }), 1);
});

test('deploy runs the type guard before pulling the Vercel environment', () => {
  const workflow = readFileSync(new URL('../workflows/deploy.yml', import.meta.url), 'utf8');
  const guard = workflow.indexOf('verify-public-build-env-types.mjs');
  assert.ok(guard > 0 && guard < workflow.indexOf('vercel@latest pull'));
});
