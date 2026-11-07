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

for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
  test(`dependency repair ${mode} refuses lockfile changes while rendering source parity`, (t) => {
    const f = fixture(t, '.npmrc', 'staged');
    const gitBinary = execFileSync('which', ['git'], { env, encoding: 'utf8' }).trim();
    const index = f.git('ls-files', '--stage');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    writeFileSync(join(f.root, 'bin/git'), `#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
result = subprocess.run([${JSON.stringify(gitBinary)}, *sys.argv[1:]])
marker = Path('changed-once')
if sys.argv[1:] == ['show', ':package.json'] and not marker.exists():
    Path('pnpm-lock.yaml').write_text('unverified resolution\\n')
    marker.touch()
sys.exit(result.returncode)
`, { mode: 0o755 });
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0, 'rendering must not authorize an unverified lockfile');
    assert.match(result.stderr, /lockfile changed during projection generation/);
    assert.equal(f.git('ls-files', '--stage'), index);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
    }
    const retry = f.resolve(mode);
    assert.equal(retry.status, 0, retry.stderr);
    assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), outputs[0]);
    assert.equal(f.git('show', ':SOURCES.md'), readFileSync(join(f.root, 'SOURCES.md'), 'utf8'));
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'repair stays idempotent after restoring the verified lockfile');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
  test(`dependency repair ${mode} refuses index changes while rendering source parity`, (t) => {
    const f = fixture(t, '.npmrc', 'staged');
    const gitBinary = execFileSync('which', ['git'], { env, encoding: 'utf8' }).trim();
    const index = f.git('ls-files', '--stage', '--', ':(exclude)package.json');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    writeFileSync(join(f.root, 'bin/git'), `#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path
result = subprocess.run([${JSON.stringify(gitBinary)}, *sys.argv[1:]])
marker = Path('changed-once')
if sys.argv[1:] == ['show', ':package.json'] and not marker.exists():
    Path('package.json').write_text('{"dependencies":{"example":"3.0.0"}}\\n')
    subprocess.run([${JSON.stringify(gitBinary)}, 'add', 'package.json'], check=True)
    marker.touch()
sys.exit(result.returncode)
`, { mode: 0o755 });
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0, 'a projection must not describe an index replaced during rendering');
    assert.match(result.stderr, /source index changed during projection generation/);
    assert.equal(f.git('show', ':package.json'), '{"dependencies":{"example":"3.0.0"}}\n');
    assert.equal(f.git('ls-files', '--stage', '--', ':(exclude)package.json'), index);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
    }
    const retry = f.resolve(mode);
    assert.equal(retry.status, 0, retry.stderr);
    assert.match(f.git('show', ':SOURCES.md'), /"example": "3\.0\.0"/);
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'repair stays idempotent after rendering the reviewed index');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
  test(`dependency repair ${mode} refuses lockfile drift during frozen verification`, (t) => {
    const f = fixture(t, '.npmrc', 'staged');
    const index = f.git('ls-files', '--stage');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
from pathlib import Path
marker = Path('changed-once')
if not marker.exists():
    Path('pnpm-lock.yaml').write_text('unverified resolution\\n')
    marker.touch()
`, { mode: 0o755 });
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0, 'a successful verifier cannot authorize changed lockfile bytes');
    assert.match(result.stderr, /dependency inputs changed during verification/);
    assert.equal(f.git('ls-files', '--stage'), index);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
    }
    const retry = f.resolve(mode);
    assert.equal(retry.status, 0, retry.stderr);
    assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), outputs[0]);
    assert.equal(f.git('show', ':SOURCES.md'), readFileSync(join(f.root, 'SOURCES.md'), 'utf8'));
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'reviewed frozen verification remains idempotent');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
  for (const state of ['staged', 'unstaged']) {
    test(`dependency repair ${mode} refuses ${state} manifest changes during verification`, (t) => {
      const f = fixture(t, '.npmrc', 'staged');
      const beforeIndex = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      writeFileSync(join(f.root, 'bin/corepack'), `#!/usr/bin/env python3
import subprocess
from pathlib import Path
marker = Path('changed-once')
if not marker.exists():
    Path('package.json').write_text('{"dependencies":{"example":"2.0.0"}}\\n')
    ${state === 'staged' ? "subprocess.run(['git', 'add', 'package.json'], check=True)" : '# Leave the concurrent edit unstaged.'}
    marker.touch()
`, { mode: 0o755 });
      const result = f.resolve(mode);
      assert.notEqual(result.status, 0, result.stdout);
      assert.match(result.stderr, /dependency inputs changed during verification/);
      assert.equal(readFileSync(join(f.root, 'package.json'), 'utf8'), '{"dependencies":{"example":"2.0.0"}}\n');
      assert.equal(f.git('show', ':package.json'), state === 'staged'
        ? '{"dependencies":{"example":"2.0.0"}}\n'
        : '{"dependencies":{"example":"1.0.0"}}\n');
      assert.equal(f.git('show', ':.npmrc'), 'local input\n');
      if (state === 'unstaged') assert.equal(f.git('ls-files', '--stage'), beforeIndex);
      for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
        assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
        assert.deepEqual(Buffer.from(f.git('show', `:${name}`)), outputs[i]);
      }
      f.git('add', 'package.json');
      const retry = f.resolve(mode);
      assert.equal(retry.status, 0, retry.stderr);
      assert.match(f.git('show', ':SOURCES.md'), /"example": "2\.0\.0"/);
      const repairedIndex = f.git('ls-files', '--stage');
      assert.equal(f.resolve(mode).status, 0, 'repair remains idempotent after reviewing the concurrent change');
      assert.equal(f.git('ls-files', '--stage'), repairedIndex);
    });
  }
  for (const input of ['.pnpmfile.cjs', 'apps/web/.npmrc', 'patches/example.patch', 'apps/local-only/package.json']) {
    test(`dependency repair ${mode} refuses ignored ${input} before invoking pnpm`, (t) => {
      const f = fixture(t, input, 'untracked');
      writeFileSync(join(f.root, '.gitignore'), `${input}\nnode_modules/\n.next/\n`);
      f.git('add', '.gitignore');
      for (const generated of ['apps/web/.next/package.json', 'apps/web/.next/types/package.json']) {
        mkdirSync(dirname(join(f.root, generated)), { recursive: true });
        writeFileSync(join(f.root, generated), '{"type":"commonjs"}\n');
      }
      mkdirSync(join(f.root, 'node_modules/example'), { recursive: true });
      writeFileSync(join(f.root, 'node_modules/example/.npmrc'), 'vendor config\n');
      writeFileSync(join(f.root, 'node_modules/example/package.json'), '{"name":"vendor"}\n');
      const index = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      const result = f.resolve(mode);
      assert.notEqual(result.status, 0, result.stdout);
      assert.match(result.stderr, /ignored dependency inputs:/);
      assert.ok(result.stderr.includes(input), result.stderr);
      assert.equal(result.stderr.includes('node_modules/'), false, result.stderr);
      assert.equal(result.stderr.includes('.next/'), false, result.stderr);
      assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
      assert.equal(f.git('ls-files', '--stage'), index);
      assert.equal(readFileSync(f.path, 'utf8'), 'local input\n');
      for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
        assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
      }
      unlinkSync(f.path);
      const retry = f.resolve(mode);
      assert.equal(retry.status, 0, retry.stderr);
      const repairedIndex = f.git('ls-files', '--stage');
      assert.equal(f.resolve(mode).status, 0, 'repair stays idempotent with ignored vendor config');
      assert.equal(f.git('ls-files', '--stage'), repairedIndex);
      assert.equal(readFileSync(join(f.root, 'apps/web/.next/package.json'), 'utf8'), '{"type":"commonjs"}\n');
    });
  }
  test(`dependency repair ${mode} requires staged projection configuration before invoking pnpm`, (t) => {
    const f = fixture(t, '.npmrc', 'staged');
    const configPath = join(f.root, 'repository-docs.json');
    const config = JSON.parse(readFileSync(configPath, 'utf8'));
    config.repository = 'reviewed/dependency-update';
    writeFileSync(configPath, JSON.stringify(config));
    const index = f.git('ls-files', '--stage');
    const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
    const result = f.resolve(mode);
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, /unstaged dependency edits: repository-docs\.json/);
    assert.equal(existsSync(join(f.root, 'pnpm-calls')), false);
    assert.equal(f.git('ls-files', '--stage'), index);
    assert.deepEqual(JSON.parse(readFileSync(configPath, 'utf8')), config);
    for (const [i, name] of ['pnpm-lock.yaml', 'SOURCES.md'].entries()) {
      assert.deepEqual(readFileSync(join(f.root, name)), outputs[i]);
    }
    f.git('add', 'repository-docs.json');
    const retry = f.resolve(mode);
    assert.equal(retry.status, 0, retry.stderr);
    assert.match(f.git('show', ':SOURCES.md'), /Repository: `reviewed\/dependency-update`/);
    assert.deepEqual(readFileSync(join(f.root, 'pnpm-lock.yaml')), outputs[0]);
    const repairedIndex = f.git('ls-files', '--stage');
    assert.equal(f.resolve(mode).status, 0, 'repair with reviewed configuration stays idempotent');
    assert.equal(f.git('ls-files', '--stage'), repairedIndex);
  });
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
