import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { resolver, sourceMapFixture } from './resolve-repository-docs.test.mjs';

const env = Object.fromEntries(
  Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')),
);
const originalManifest = '{"dependencies":{"example":"^1.0.0"}}\n';
const originalLock = 'reviewed resolution 1.0.0\n';
const bumpedLock = 'reviewed resolution 1.0.1\n';
const fingerprint = (value) => createHash('sha256').update(value).digest('hex');

function trackedLockFixture(t) {
  const f = sourceMapFixture(t);
  const file = (name) => path.join(f.root, name);
  const lockfile = 'pnpm-lock.yaml';
  const registry = JSON.parse(fs.readFileSync(new URL('../repository-docs.json', import.meta.url), 'utf8'));
  const config = JSON.parse(fs.readFileSync(file('repository-docs.json'), 'utf8'));
  const lockSources = registry.sources.filter((item) => item.path === lockfile);
  assert.equal(lockSources.length, 1);
  config.sources.push(...lockSources);
  fs.writeFileSync(file('repository-docs.json'), JSON.stringify(config));
  fs.writeFileSync(file('package.json'), originalManifest);
  fs.writeFileSync(file(lockfile), originalLock);
  f.generate();
  f.commit();
  fs.mkdirSync(file('bin'));
  const check = () => spawnSync('python3', [resolver.replace('resolve-repository-docs.py', 'repository_docs.py'),
    '--root', f.root], { env, encoding: 'utf8' });
  const repair = (mode) => spawnSync('python3', [resolver, '--root', f.root, mode], {
    env: { ...env, PATH: `${file('bin')}:${env.PATH}` }, encoding: 'utf8',
  });
  const script = (value) => fs.writeFileSync(file('bin/corepack'), value, { mode: 0o755 });
  const state = () => ({
    index: f.git('ls-files', '--stage'),
    manifest: fs.readFileSync(file('package.json'), 'utf8'),
    lock: fs.readFileSync(file(lockfile), 'utf8'),
    projection: fs.readFileSync(file(f.output), 'utf8'),
  });
  return { ...f, file, lockfile, check, repair, script, state };
}

for (const mode of ['--verify-lockfile', '--refresh-lockfile']) {
  test(`dependency repair ${mode} detects and repairs lockfile-only source drift`, (t) => {
    const f = trackedLockFixture(t);
    fs.writeFileSync(f.file(f.lockfile), bumpedLock);
    f.git('add', f.lockfile);
    const stale = f.check();
    assert.equal(stale.status, 1, 'lockfile-only updates must invalidate source parity');
    assert.match(stale.stdout, /source projection stale/);
    const original = f.state();
    f.script('#!/bin/sh\nexit 23\n');
    assert.notEqual(f.repair(mode).status, 0, 'failed frozen verification must block source repair');
    assert.deepEqual(f.state(), original);
    f.script('#!/bin/sh\nprintf "%s\\n" "$*" >> pnpm-calls\n');
    const repaired = f.repair(mode);
    assert.equal(repaired.status, 0, repaired.stderr);
    assert.match(fs.readFileSync(f.file('pnpm-calls'), 'utf8'),
      /pnpm install --lockfile-only --ignore-scripts --frozen-lockfile --offline/);
    const repairedState = f.state();
    assert.equal(repairedState.manifest, originalManifest);
    assert.equal(repairedState.lock, bumpedLock);
    assert.ok(f.git('show', `:${f.output}`).includes(fingerprint(bumpedLock)));
    const verified = f.check();
    assert.equal(verified.status, 0, verified.stdout + verified.stderr);
    assert.equal(f.repair(mode).status, 0, 'repair remains idempotent');
    assert.deepEqual(f.state(), repairedState);
  });
}

test('dependency refresh fingerprints the frozen-verified regenerated lockfile', (t) => {
  const f = trackedLockFixture(t);
  const bumpedManifest = '{"dependencies":{"example":"^1.0.1"}}\n';
  fs.writeFileSync(f.file('package.json'), bumpedManifest);
  f.git('add', 'package.json');
  fs.writeFileSync(f.file('fail-final'), '');
  f.script(`#!/usr/bin/env python3
from pathlib import Path
import sys

lock = Path('pnpm-lock.yaml')
with Path('pnpm-calls').open('a') as log:
    log.write(' '.join(sys.argv[1:]) + '\\n')
if '--no-frozen-lockfile' in sys.argv:
    lock.write_text(${JSON.stringify(bumpedLock)})
elif lock.read_text() == ${JSON.stringify(originalLock)}:
    print('ERR_PNPM_OUTDATED_LOCKFILE')
    sys.exit(1)
elif Path('fail-final').exists():
    sys.exit(23)
`);
  const before = f.state();
  assert.notEqual(f.repair('--refresh-lockfile').status, 0);
  assert.deepEqual(f.state(), before, 'failed final frozen verification restores lock, projection, and index');
  fs.unlinkSync(f.file('fail-final'));
  fs.unlinkSync(f.file('pnpm-calls'));
  const refreshed = f.repair('--refresh-lockfile');
  assert.equal(refreshed.status, 0, refreshed.stdout + refreshed.stderr);
  const fixed = f.state();
  assert.equal(fixed.manifest, bumpedManifest);
  assert.equal(fixed.lock, bumpedLock);
  assert.equal(f.git('show', `:${f.lockfile}`), bumpedLock);
  const stagedProjection = f.git('show', `:${f.output}`);
  assert.ok(stagedProjection.includes(fingerprint(bumpedLock)), 'projection fingerprints the new staged lock');
  assert.ok(!stagedProjection.includes(fingerprint(originalLock)));
  const checked = f.check();
  assert.equal(checked.status, 0, checked.stdout + checked.stderr);
  const prefix = 'pnpm install --lockfile-only --ignore-scripts ';
  assert.deepEqual(fs.readFileSync(f.file('pnpm-calls'), 'utf8').trim().split('\n'), [
    `${prefix}--frozen-lockfile --offline`, `${prefix}--no-frozen-lockfile`, `${prefix}--frozen-lockfile --offline`,
  ]);
  assert.equal(f.repair('--refresh-lockfile').status, 0, 'repair remains idempotent');
  assert.deepEqual(f.state(), fixed);
});
