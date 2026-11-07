import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const resolver = fileURLToPath(new URL('./resolve-repository-docs.py', import.meta.url));
const env = {
  ...Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_'))),
  GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null',
  GIT_AUTHOR_NAME: 'fixture', GIT_AUTHOR_EMAIL: 'fixture@example.invalid',
  GIT_COMMITTER_NAME: 'fixture', GIT_COMMITTER_EMAIL: 'fixture@example.invalid',
};

function fixture(t, input, state) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-dependency-inputs-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  git('init', '-q', '-b', 'dependency');
  git('config', 'core.hooksPath', '/dev/null');
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'package.json'), '{"dependencies":{"example":"1.0.0"}}\n');
  writeFileSync(join(root, 'pnpm-lock.yaml'), 'reviewed lockfile\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [{ path: 'package.json', purpose: 'Dependencies' }], imports: [], output: 'SOURCES.md',
  }));
  execFileSync('python3', [fileURLToPath(new URL('./repository_docs.py', import.meta.url)),
    '--root', root, '--write'], { env });
  const path = join(root, input);
  mkdirSync(dirname(path), { recursive: true });
  if (state !== 'untracked') writeFileSync(path, 'reviewed input\n');
  git('add', '.');
  git('commit', '-qm', 'fixture');
  writeFileSync(path, 'local input\n');
  if (state === 'staged') git('add', input);
  mkdirSync(join(root, 'bin'));
  writeFileSync(join(root, 'bin/corepack'), '#!/bin/sh\necho "$*" >> pnpm-calls\n', { mode: 0o755 });
  const resolve = (mode) => spawnSync('python3', [resolver, '--root', root, mode], {
    env: { ...env, PATH: `${join(root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
  });
  return { root, git, path, resolve };
}

for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
  for (const input of ['.pnpmfile.cjs', 'apps/web/.npmrc', 'patches/example.patch']) {
    for (const state of ['untracked', 'unstaged']) {
      test(`dependency repair ${mode} refuses ${state} ${input} before invoking pnpm`, (t) => {
        const f = fixture(t, input, state);
        const index = f.git('ls-files', '--stage');
        const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
        const result = f.resolve(mode);
        assert.notEqual(result.status, 0, result.stdout);
        assert.match(result.stderr, new RegExp(`${state} dependency (?:inputs|edits):`));
        assert.ok(result.stderr.includes(input), result.stderr);
        assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
        assert.equal(f.git('ls-files', '--stage'), index);
        assert.equal(readFileSync(f.path, 'utf8'), 'local input\n');
        for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
          assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
        }
      });
    }
    test(`dependency repair ${mode} accepts staged ${input} and preserves unrelated edits`, (t) => {
      const f = fixture(t, input, 'staged');
      writeFileSync(join(f.root, 'notes.txt'), 'unrelated local notes\n');
      const result = f.resolve(mode);
      assert.equal(result.status, 0, result.stderr);
      assert.match(readFileSync(join(f.root, 'pnpm-calls'), 'utf8'), /pnpm install .*--frozen-lockfile --offline/);
      assert.equal(f.git('show', `:${input}`), 'local input\n');
      assert.equal(readFileSync(join(f.root, 'notes.txt'), 'utf8'), 'unrelated local notes\n');
      assert.equal(f.git('show', ':SOURCES.md'), readFileSync(join(f.root, 'SOURCES.md'), 'utf8'));
    });
  }
}

function manifest(script, dependencies) {
  return `${JSON.stringify({
    name: 'fixture', scripts: { test: script }, devDependencies: dependencies,
  }, null, 2)}\n`;
}

function conflictedDependency(t, ours, theirs) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-dependency-merge-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  const base = manifest('base', { turbo: '^2.11.9', typescript: '^5.9.3' });
  git('init', '-q', '-b', 'ours');
  git('config', 'core.hooksPath', '/dev/null');
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'package.json'), base);
  writeFileSync(join(root, 'pnpm-lock.yaml'), 'old lock\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [{ path: 'package.json', purpose: 'Dependencies' }], imports: [], output: 'SOURCES.md',
  }));
  execFileSync('python3', [fileURLToPath(new URL('./repository_docs.py', import.meta.url)),
    '--root', root, '--write'], { env });
  git('add', '.');
  git('commit', '-qm', 'base');
  git('branch', 'theirs');
  writeFileSync(join(root, 'package.json'), ours);
  git('commit', '-qam', 'bump');
  git('switch', '-q', 'theirs');
  writeFileSync(join(root, 'package.json'), theirs);
  git('commit', '-qam', 'add');
  git('switch', '-q', 'ours');
  const merge = spawnSync('git', ['merge', '--no-commit', 'theirs'], { cwd: root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
  assert.match(git('diff', '--name-only', '--diff-filter=U'), /^package\.json$/m);
  mkdirSync(join(root, 'bin'));
  writeFileSync(join(root, 'bin/corepack'), `#!/usr/bin/env python3
import sys
from pathlib import Path
log, lock = Path('pnpm-calls'), Path('pnpm-lock.yaml')
log.write_text((log.read_text() if log.exists() else '') + ' '.join(sys.argv[1:]) + '\\n')
if '--no-frozen-lockfile' in sys.argv:
    lock.write_text('resolved lock\\n')
elif lock.read_text() != 'resolved lock\\n':
    print('ERR_PNPM_OUTDATED_LOCKFILE')
    raise SystemExit(1)
`, { mode: 0o755 });
  const resolve = (mode) => spawnSync('python3', [resolver, '--root', root, mode], {
    env: { ...env, PATH: `${join(root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
  });
  return { root, git, resolve };
}

test('refresh-lockfile unions an adjacent dependency addition with the bumped range', (t) => {
  const f = conflictedDependency(
    t,
    manifest('base', { turbo: '^2.11.10', typescript: '^5.9.3' }),
    manifest('main', { rollup: '^4.65.0', turbo: '^2.11.9', typescript: '^5.9.3' }),
  );
  writeFileSync(join(f.root, 'notes.txt'), 'unrelated local notes\n');
  const result = f.resolve('--refresh-lockfile');
  assert.equal(result.status, 0, result.stderr);
  const merged = JSON.parse(f.git('show', ':package.json'));
  assert.equal(merged.scripts.test, 'main');
  assert.deepEqual(merged.devDependencies, {
    rollup: '^4.65.0', turbo: '^2.11.10', typescript: '^5.9.3',
  });
  assert.match(readFileSync(join(f.root, 'package.json'), 'utf8'), /"rollup": "\^4\.65\.0",\n {4}"turbo": "\^2\.11\.10"/);
  assert.equal(f.git('show', ':pnpm-lock.yaml'), 'resolved lock\n');
  assert.equal(f.git('ls-files', '--unmerged'), '');
  assert.doesNotMatch(readFileSync(join(f.root, 'package.json'), 'utf8'), /<<<<<<<|=======|>>>>>>>/);
  assert.equal(readFileSync(join(f.root, 'notes.txt'), 'utf8'), 'unrelated local notes\n');
  assert.match(readFileSync(join(f.root, 'pnpm-calls'), 'utf8'), /--no-frozen-lockfile/);
  assert.equal(f.resolve('--refresh-lockfile').status, 0, 'retry is idempotent');
});

test('refresh-lockfile refuses incompatible dependency ranges before invoking pnpm', (t) => {
  const f = conflictedDependency(
    t,
    manifest('base', { turbo: '^2.11.10', typescript: '^5.9.3' }),
    manifest('base', { turbo: '^3.0.0', typescript: '^5.9.3' }),
  );
  const index = f.git('ls-files', '--stage');
  const before = readFileSync(join(f.root, 'package.json'), 'utf8');
  const result = f.resolve('--refresh-lockfile');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /incompatible devDependencies\.turbo/);
  assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
  assert.equal(readFileSync(join(f.root, 'package.json'), 'utf8'), before);
  assert.equal(f.git('ls-files', '--stage'), index);
});

test('verify-lockfile does not rewrite a conflicted dependency manifest', (t) => {
  const f = conflictedDependency(
    t,
    manifest('base', { turbo: '^2.11.10', typescript: '^5.9.3' }),
    manifest('main', { rollup: '^4.65.0', turbo: '^2.11.9', typescript: '^5.9.3' }),
  );
  const before = readFileSync(join(f.root, 'package.json'), 'utf8');
  const result = f.resolve('--verify-lockfile');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /resolve source conflicts first: package\.json/);
  assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
  assert.equal(readFileSync(join(f.root, 'package.json'), 'utf8'), before);
});
