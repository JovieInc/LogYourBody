import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
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

for (const scenario of ['verify', 'current', 'refresh']) {
  for (const mutation of ['rewrite', 'delete']) {
    test(`dependency repair refuses frozen lockfile ${mutation} after ${scenario}`, (t) => {
      const f = fixture(t, '.pnpmfile.cjs', 'staged');
      const index = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
import sys
from pathlib import Path
lock = Path('pnpm-lock.yaml')
if '--no-frozen-lockfile' in sys.argv:
    lock.write_text('refreshed resolutions\\n')
elif ${scenario === 'refresh' ? 'True' : 'False'} and lock.read_text() == 'reviewed lockfile\\n':
    print('ERR_PNPM_OUTDATED_LOCKFILE')
    sys.exit(1)
elif ${mutation === 'delete' ? 'True' : 'False'}:
    lock.unlink()
else:
    lock.write_text('unexpected frozen resolutions\\n')
`, { mode: 0o755 });
      const result = f.resolve(scenario === 'verify' ? '--verify-lockfile' : '--refresh-lockfile');
      assert.notEqual(result.status, 0, 'a frozen lockfile mutation must fail closed');
      assert.match(result.stderr, /frozen verification changed pnpm-lock\.yaml/);
      assert.equal(f.git('ls-files', '--stage'), index);
      for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
        assert.deepEqual(readFileSync(join(f.root, name)), outputs[i], 'failed repairs restore original artifacts');
      }
    });
  }
}

for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
  for (const input of ['.pnpmfile.cjs', 'apps/web/.npmrc', 'patches/example.patch']) {
    test(`dependency repair ${mode} refuses indexed symlink ${input} before invoking pnpm`, (t) => {
      const f = fixture(t, input, 'staged');
      const external = mkdtempSync(join(tmpdir(), 'lyb-external-dependency-'));
      t.after(() => rmSync(external, { recursive: true, force: true }));
      const target = join(external, 'input');
      writeFileSync(target, 'unreviewed external input\n');
      unlinkSync(f.path);
      symlinkSync(target, f.path);
      f.git('add', input);
      const index = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      const result = f.resolve(mode);
      assert.notEqual(result.status, 0, result.stdout);
      assert.match(result.stderr, /dependency input must be a regular indexed file:/);
      assert.ok(result.stderr.includes(input), result.stderr);
      assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
      assert.equal(f.git('ls-files', '--stage'), index);
      assert.equal(readFileSync(target, 'utf8'), 'unreviewed external input\n');
      for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
        assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      }
    });
  }
  test(`dependency repair ${mode} accepts an executable indexed hook`, (t) => {
    const f = fixture(t, '.pnpmfile.cjs', 'staged');
    chmodSync(f.path, 0o755);
    f.git('add', '.pnpmfile.cjs');
    const result = f.resolve(mode);
    assert.equal(result.status, 0, result.stderr);
    assert.match(f.git('ls-files', '--stage', '.pnpmfile.cjs'), /^100755 /);
    assert.match(readFileSync(join(f.root, 'pnpm-calls'), 'utf8'), /--frozen-lockfile --offline/);
  });
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
