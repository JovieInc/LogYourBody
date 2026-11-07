import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const workflow = readFileSync(new URL('../workflows/ci.yml', import.meta.url), 'utf8');
const staticJob = workflow.split('\n  ios_static:\n')[1].split(/\n {2}\S/)[0];

function signingStep() {
  const step = staticJob.match(/      - name: Import Swift release signing keys\n        run: \|\n((?:          .*\n)+)/);
  assert.ok(step, 'setup-swift v3 needs Swift signing keys before verifying Swiftly');
  assert.ok(step.index < staticJob.indexOf('uses: swift-actions/setup-swift@'));
  assert.doesNotMatch(staticJob, /skip-verify-signature|continue-on-error/);
  assert.match(staticJob, /swift-version: '6\.1\.2'/);
  return step[1].replace(/^          /gm, '');
}

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'swift-signing-'));
  const signer = join(root, 'signer');
  const verifier = join(root, 'verifier');
  const bin = join(root, 'bin');
  for (const dir of [signer, verifier, bin]) mkdirSync(dir, { mode: 0o700 });
  const gpg = (home, args) => spawnSync('gpg', ['--homedir', home, '--batch', ...args], { encoding: 'utf8' });
  t.after(() => {
    execFileSync('gpgconf', ['--homedir', signer, '--kill', 'gpg-agent']);
    rmSync(root, { recursive: true, force: true });
  });
  const generated = gpg(signer, ['--pinentry-mode', 'loopback', '--passphrase', '',
    '--quick-generate-key', 'Swift CI fixture <ci@example.com>', 'ed25519', 'sign', '0']);
  assert.equal(generated.status, 0, generated.stderr);
  const keys = join(root, 'keys.asc');
  assert.equal(gpg(signer, ['--armor', '--output', keys, '--export']).status, 0);
  const payload = join(root, 'swiftly.tar.gz');
  writeFileSync(payload, 'signed Swiftly fixture\n');
  assert.equal(gpg(signer, ['--detach-sign', payload]).status, 0);
  writeFileSync(join(bin, 'curl'), `#!/usr/bin/env node
const fs = require('node:fs');
const assert = require('node:assert/strict');
const args = process.argv.slice(2);
assert.ok(args.includes('https://www.swift.org/keys/all-keys.asc'));
for (const flag of ['--fail', '--location', '--compressed']) assert.ok(args.includes(flag));
if (process.env.SWIFT_TEST_DOWNLOAD_FAIL) process.exit(22);
fs.copyFileSync(process.env.SWIFT_TEST_KEYS, args[args.indexOf('--output') + 1]);
`, { mode: 0o755 });
  const prepare = (extra = {}) => spawnSync('bash', ['-c', signingStep()], {
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, GNUPGHOME: verifier,
      RUNNER_TEMP: root, SWIFT_TEST_KEYS: keys, ...extra }, encoding: 'utf8',
  });
  const verify = () => gpg(verifier, ['--verify', `${payload}.sig`, payload]);
  return { root, keys, payload, prepare, verify };
}

test('the workflow imports signing keys before setup-swift and rejects tampered downloads', (t) => {
  signingStep();
  const f = fixture(t);
  const missing = f.verify();
  assert.notEqual(missing.status, 0);
  assert.match(missing.stderr, /No public key/);
  const prepared = f.prepare();
  assert.equal(prepared.status, 0, prepared.stderr);
  assert.equal(f.verify().status, 0);
  writeFileSync(f.payload, 'tampered Swiftly fixture\n');
  assert.notEqual(f.verify().status, 0, 'signature verification must remain enforced');
});

test('a failed signing-key download fails preparation', (t) => {
  signingStep();
  const f = fixture(t);
  assert.notEqual(f.prepare({ SWIFT_TEST_DOWNLOAD_FAIL: '1' }).status, 0);
  assert.notEqual(f.verify().status, 0);
});

test('malformed signing keys fail preparation', (t) => {
  signingStep();
  const f = fixture(t);
  writeFileSync(f.keys, 'not a public key\n');
  assert.notEqual(f.prepare().status, 0);
  assert.notEqual(f.verify().status, 0);
});

function sourcekitFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'swift-sourcekit-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const bin = join(root, 'swiftly', 'bin');
  const lib = join(root, 'toolchain with spaces', 'usr', 'lib');
  mkdirSync(bin, { recursive: true });
  mkdirSync(lib, { recursive: true });
  const library = join(lib, 'libsourcekitdInProc.so');
  writeFileSync(library, 'SourceKit fixture');
  writeFileSync(join(bin, 'swift'), `#!/bin/bash
[[ "$*" == '-print-target-info' ]] || exit 2
printf '%s\\n' "$SWIFT_TEST_TARGET_INFO"
`, { mode: 0o755 });
  for (const command of ['curl', 'unzip']) {
    writeFileSync(join(bin, command), '#!/bin/bash\nexit 0\n', { mode: 0o755 });
  }
  const step = staticJob.match(/      - name: Install SwiftLint \(version pinned with setup-ios-build\)\n        run: \|\n((?:          .*\n)+)/);
  assert.ok(step, 'exercise the SwiftLint installation step from CI');
  const envFile = join(root, 'github-env');
  const run = (targetInfo = { paths: { runtimeResourcePath: join(lib, 'swift') } }) => {
    writeFileSync(envFile, '');
    return spawnSync('bash', ['-c', step[1].replace(/^          /gm, '')], {
      cwd: new URL('../../', import.meta.url), encoding: 'utf8',
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, RUNNER_TEMP: root,
        GITHUB_ENV: envFile, SWIFT_TEST_TARGET_INFO: JSON.stringify(targetInfo) },
    });
  };
  return { run, lib, library, envFile };
}

test('SwiftLint uses compiler-reported SourceKit libraries behind Swiftly shims', (t) => {
  const f = sourcekitFixture(t);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(readFileSync(f.envFile, 'utf8').split('\n').includes(`LINUX_SOURCEKIT_LIB_PATH=${f.lib}`));
});

test('missing SourceKit fails SwiftLint preparation', (t) => {
  const f = sourcekitFixture(t);
  rmSync(f.library);
  assert.notEqual(f.run().status, 0);
  assert.doesNotMatch(readFileSync(f.envFile, 'utf8'), /LINUX_SOURCEKIT_LIB_PATH=/);
});

test('invalid compiler target information fails SwiftLint preparation', (t) => {
  const f = sourcekitFixture(t);
  assert.notEqual(f.run({}).status, 0);
  assert.doesNotMatch(readFileSync(f.envFile, 'utf8'), /LINUX_SOURCEKIT_LIB_PATH=/);
});
