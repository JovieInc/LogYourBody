import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { runSeparation } from './jovie-separation.mjs';

const teamIdentifier = ['JOVIE', 'TEAM', 'ID'].join('_');
const teamId = ['bdc09edc', 'f91c', '4a06', 'b308', '74b4fcf093f8'].join('-');

function fixtureRepo(t) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-separation-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  execFileSync('git', ['init', '-q'], { cwd: root });
  const write = (path, text) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), text);
  };
  write(
    'apps/web/src/allowed.ts',
    "import { Button } from '@jovie/ui'; // Jovie Better Auth, JovieKit\n",
  );
  return { root, write };
}

test('rejects foreign product identifiers across LYB code, including new untracked files', (t) => {
  for (const [path, identifier] of [
    ['apps/web/src/boundary.ts', teamIdentifier],
    ['apps/ios/LogYourBody/Boundary.swift', teamId],
    ['agent/config.json', ['jovie', 'feedback-guards/v1'].join('.')],
    ['packages/shared-lib/config.json', ['jovie', 'correction-coverage/v1'].join('.')],
    ['scripts/boundary.sh', ['jovie', 'web'].join('-')],
    ['.github/workflows/boundary.yml', ['jovie', 'ios'].join('-').toUpperCase()],
    ['apps/web/src/env.ts', ['JOVIE', 'AUTH', 'UNREVIEWED'].join('_')],
  ]) {
    const { root, write } = fixtureRepo(t);
    write(path, `safe first line\n${identifier}\n`);
    assert.throws(
      () => runSeparation({ root, exceptions: {} }),
      (error) => {
        assert.match(error.message, /Jovie separation failed/);
        assert.ok(error.message.includes(`${path}:2`), error.message);
        return true;
      },
    );
  }
});

test('allows shared infrastructure and prose; skips symlinks and binary assets', (t) => {
  const { root, write } = fixtureRepo(t);
  write('docs/provenance.md', teamIdentifier);
  write('apps/web/public/asset.png', teamIdentifier);
  write('apps/web/src/identity.ts', "const issuer = 'https://jov.ie/api/auth';\n");
  write(
    'apps/web/src/shared.ts',
    [
      'AUTH_ISSUER',
      'AUTH_CLIENT_ID',
      'AUTH_REDIRECT_URI',
      'BOT_APP_ID',
      'BOT_PRIVATE_KEY',
      'MAC_RUNNER',
    ]
      .map((name) => ['JOVIE', name].join('_'))
      .join('\n'),
  );
  symlinkSync('/missing-outside-file', join(root, 'apps/web/src/link.ts'));
  assert.ok(runSeparation({ root, exceptions: {} }).scanned >= 2);
});

test('exceptions cover only a counted identifier in one file and require a reason', (t) => {
  const { root, write } = fixtureRepo(t);
  const path = '.github/scripts/lib/adapter.mjs';
  const exceptions = {
    [path]: {
      reason: 'Retained vendored adapter compatibility.',
      identifiers: { [teamIdentifier.toLowerCase()]: 1 },
    },
  };
  write(path, teamIdentifier);
  assert.doesNotThrow(() => runSeparation({ root, exceptions }));
  write(path, `${teamIdentifier}\n${teamIdentifier}`);
  assert.throws(() => runSeparation({ root, exceptions }), /Jovie separation failed/);
  write(path, `${teamIdentifier}\n${teamId}`);
  assert.throws(() => runSeparation({ root, exceptions }), /Jovie separation failed/);
  write(path, teamIdentifier);
  write('apps/web/src/copied.ts', teamIdentifier);
  assert.throws(() => runSeparation({ root, exceptions }), /copied.ts:1/);
  assert.throws(
    () => runSeparation({ root, exceptions: { [path]: { ...exceptions[path], reason: ' ' } } }),
    /exception reason/,
  );
});

test('the real CLI scans this checkout and rejects unsupported arguments', () => {
  const cli = fileURLToPath(new URL('./jovie-separation.mjs', import.meta.url));
  const success = spawnSync(process.execPath, [cli], { encoding: 'utf8' });
  assert.equal(success.status, 0, success.stderr);
  assert.match(success.stdout, /Jovie separation passed/);
  const failure = spawnSync(process.execPath, [cli, '--unknown'], { encoding: 'utf8' });
  assert.equal(failure.status, 1);
  assert.match(failure.stderr, /usage/);
});
