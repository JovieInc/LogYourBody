import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { lintArguments } from './pre-commit-lint.mjs';
import { resolver, sourceMapFixture } from './resolve-repository-docs.test.mjs';
import './resolve-repository-docs-json.test.mjs';
import './resolve-repository-docs-dependency.test.mjs';
import './resolve-repository-docs-ledger.test.mjs';
import './resolve-repository-docs-pin.test.mjs';
import './resolve-repository-docs-project.test.mjs';
import './resolve-repository-docs-pin-union.test.mjs';
import './resolve-repository-docs-manifest.test.mjs';

const env = {
  ...Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_'))),
  GIT_AUTHOR_NAME: 'fixture',
  GIT_AUTHOR_EMAIL: 'fixture@example.com',
  GIT_COMMITTER_NAME: 'fixture',
  GIT_COMMITTER_EMAIL: 'fixture@example.com',
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_CONFIG_GLOBAL: '/dev/null',
};
const git = (cwd, ...args) => execFileSync('git', args, { cwd, env, encoding: 'utf8' }).trim();

for (const change of ['edit', 'delete', 'create']) {
  test(`staged Bundler source-map repair preserves a concurrent projection ${change}`, (t) => {
    const f = sourceMapFixture(t);
    const lockfile = 'apps/ios/Gemfile.lock';
    fs.mkdirSync(path.dirname(path.join(f.root, lockfile)), { recursive: true });
    const originalLock = 'GEM\n  specs:\n    addressable (2.9.0)\n';
    const bumpedLock = originalLock.replace('2.9.0', '2.9.1');
    fs.writeFileSync(path.join(f.root, lockfile), originalLock);
    const configPath = path.join(f.root, 'repository-docs.json');
    const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    config.sources.push({ path: lockfile, purpose: 'Bundler dependencies' });
    fs.writeFileSync(configPath, JSON.stringify(config));
    f.generate();
    f.commit();
    if (change === 'create') f.git('rm', f.output);
    fs.writeFileSync(path.join(f.root, lockfile), bumpedLock);
    f.git('add', lockfile);
    const index = f.git('ls-files', '--stage');
    const priorProjection = f.git('show', 'HEAD:SOURCES.md');
    const realGit = execFileSync('which', ['git'], { env, encoding: 'utf8' }).trim();
    fs.mkdirSync(path.join(f.root, 'bin'));
    fs.writeFileSync(path.join(f.root, 'bin/git'), `#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
result = subprocess.run([${JSON.stringify(realGit)}, *sys.argv[1:]]).returncode
if sys.argv[1:] == ['show', ':${lockfile}'] and not Path('changed-once').exists():
    output = Path('SOURCES.md')
    ${change === 'delete' ? 'output.unlink()' : "output.write_text('Concurrent projection edit\\n')"}
    Path('changed-once').touch()
sys.exit(result)
`, { mode: 0o755 });
    const repair = () => spawnSync('python3', [resolver, '--root', f.root, '--staged'], {
      env: { ...env, PATH: `${path.join(f.root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
    });
    const refused = repair();
    assert.notEqual(refused.status, 0, 'rendering must not overwrite another writer');
    assert.match(refused.stderr, /projection changed during generation/);
    assert.equal(f.git('ls-files', '--stage'), index);
    assert.equal(fs.existsSync(path.join(f.root, f.output)), change !== 'delete');
    if (change !== 'delete') {
      assert.equal(fs.readFileSync(path.join(f.root, f.output), 'utf8'), 'Concurrent projection edit\n');
    }
    f.git('add', f.output);
    const retried = repair();
    assert.equal(retried.status, 0, retried.stderr);
    assert.equal(f.git('show', `:${lockfile}`), bumpedLock);
    const projection = f.git('show', ':SOURCES.md');
    assert.notEqual(projection, priorProjection);
    assert.ok(projection.includes(createHash('sha256').update(bumpedLock).digest('hex')));
    const check = spawnSync('python3', [resolver.replace('resolve-repository-docs.py', 'repository_docs.py'),
      '--root', f.root], { env, encoding: 'utf8' });
    assert.equal(check.status, 0, check.stdout + check.stderr);
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(repair().status, 0, 'reviewed repair remains idempotent');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
}

function fixture(t, verified = true) {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'lyb-merge-lint-'));
  t.after(() => fs.rmSync(cwd, { recursive: true, force: true }));
  git(cwd, 'init', '-q', '-b', 'main');
  const commit = (file, value) => {
    fs.writeFileSync(path.join(cwd, file), value);
    git(cwd, 'add', file);
    git(cwd, 'commit', '-qm', file);
  };
  commit('native.swift', 'base\n');
  git(cwd, 'branch', 'feature');
  commit('native.swift', 'already on main\n');
  if (verified) git(cwd, 'update-ref', 'refs/remotes/origin/main', 'HEAD');
  git(cwd, 'checkout', '-q', 'feature');
  commit('package.json', '{"version":"2"}\n');
  git(cwd, 'merge', '--no-commit', '--no-ff', 'main');
  return cwd;
}

function selected(cwd) {
  const args = lintArguments(cwd);
  const at = args.indexOf('--diff');
  return git(cwd, 'diff', '--name-only', ...(at === -1 ? ['--cached'] : args[at + 1].split(' ')))
    .split('\n')
    .filter(Boolean);
}

test('main integration excludes imported Swift but retains branch and staged resolution changes', (t) => {
  const cwd = fixture(t);
  assert.deepEqual(selected(cwd), ['package.json']);
  fs.writeFileSync(path.join(cwd, 'native.swift'), 'reviewed resolution\n');
  git(cwd, 'add', 'native.swift');
  assert.deepEqual(selected(cwd), ['native.swift', 'package.json']);
  const args = lintArguments(cwd);
  assert.ok(args.includes('--stash'));
  assert.ok(args.includes('--hide-partially-staged'));
});

test('unstaged main-source edits do not enter the snapshot or get hidden by scope', (t) => {
  const cwd = fixture(t);
  fs.writeFileSync(path.join(cwd, 'native.swift'), 'local only\n');
  const index = git(cwd, 'write-tree');
  assert.deepEqual(selected(cwd), ['package.json']);
  assert.equal(git(cwd, 'write-tree'), index);
  assert.equal(fs.readFileSync(path.join(cwd, 'native.swift'), 'utf8'), 'local only\n');
});

test('unverified merges retain ordinary full staged checks', (t) => {
  const cwd = fixture(t, false);
  assert.deepEqual(lintArguments(cwd), ['exec', 'lint-staged']);
  assert.deepEqual(selected(cwd), ['native.swift']);
});

test('ordinary commits retain all staged checks', (t) => {
  const cwd = fixture(t);
  git(cwd, 'merge', '--abort');
  fs.writeFileSync(path.join(cwd, 'native.swift'), 'new native work\n');
  git(cwd, 'add', 'native.swift');
  assert.deepEqual(lintArguments(cwd), ['exec', 'lint-staged']);
  assert.deepEqual(selected(cwd), ['native.swift']);
});

test('unresolved main integration cannot invoke lint', (t) => {
  const cwd = fixture(t);
  const blob = git(cwd, 'rev-parse', ':native.swift');
  git(cwd, 'update-index', '--force-remove', 'native.swift');
  execFileSync('git', ['update-index', '--index-info'], {
    cwd,
    env,
    input: `100644 ${blob} 1\tnative.swift\n100644 ${blob} 2\tnative.swift\n`,
  });
  assert.throws(() => lintArguments(cwd), /unmerged|Cannot snapshot/);
});

test('lint failure propagates to the hook entrypoint', (t) => {
  const cwd = fixture(t);
  fs.mkdirSync(path.join(cwd, 'bin'));
  fs.writeFileSync(path.join(cwd, 'bin/pnpm'), '#!/bin/sh\nexit 23\n', { mode: 0o755 });
  const result = spawnSync(
    process.execPath,
    [fileURLToPath(new URL('./pre-commit-lint.mjs', import.meta.url))],
    {
      cwd,
      env: { ...env, PATH: `${path.join(cwd, 'bin')}:${env.PATH}` },
      encoding: 'utf8',
    },
  );
  assert.equal(result.status, 23, result.stderr);
});
