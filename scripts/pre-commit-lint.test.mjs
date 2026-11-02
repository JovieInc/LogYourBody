import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { lintArguments } from './pre-commit-lint.mjs';
import './resolve-repository-docs.test.mjs';
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
