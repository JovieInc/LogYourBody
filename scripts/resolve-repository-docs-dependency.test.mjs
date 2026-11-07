import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
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
  for (const input of ['.pnpmfile.cjs', 'apps/web/.npmrc', 'patches/example.patch']) {
    test(`dependency repair ${mode} refuses ignored ${input} before invoking pnpm`, (t) => {
      const f = fixture(t, input, 'untracked');
      writeFileSync(join(f.root, '.gitignore'), `${input}\nnode_modules/\n`);
      f.git('add', '.gitignore');
      mkdirSync(join(f.root, 'node_modules/example'), { recursive: true });
      writeFileSync(join(f.root, 'node_modules/example/.npmrc'), 'vendor config\n');
      const index = f.git('ls-files', '--stage');
      const outputs = ['pnpm-lock.yaml', 'SOURCES.md'].map((name) => readFileSync(join(f.root, name)));
      const result = f.resolve(mode);
      assert.notEqual(result.status, 0, result.stdout);
      assert.match(result.stderr, /ignored dependency inputs:/);
      assert.ok(result.stderr.includes(input), result.stderr);
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

function actionPinRepo(t) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-action-pin-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  git('init', '-q', '-b', 'actions');
  git('config', 'core.hooksPath', '/dev/null');
  const workflow = '.github/workflows/security-scan.yml';
  const notes = 'notes.txt';
  mkdirSync(join(root, '.github/workflows'), { recursive: true });
  const pin = (version) => `name: scan\njobs:\n  secrets:\n    steps:\n      - uses: example/action@${version}\n`;
  writeFileSync(join(root, workflow), pin('v1.0.0'));
  writeFileSync(join(root, notes), 'reviewed notes\n');
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [
      { path: workflow, purpose: 'Security scan workflow' },
      { path: notes, purpose: 'Reviewed notes' },
    ],
    imports: [], output: 'SOURCES.md',
  }));
  execFileSync('python3', [
    fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
  ], { env });
  git('add', '.');
  git('commit', '-qm', 'fixture');
  const resolve = () => spawnSync('python3', [resolver, '--root', root], { env, encoding: 'utf8' });
  const digest = (text) => createHash('sha256').update(text).digest('hex');
  return { root, git, workflow, notes, pin, resolve, digest };
}

test('action pin repair fingerprints the staged workflow and preserves unrelated edits', (t) => {
  const f = actionPinRepo(t);
  writeFileSync(join(f.root, f.workflow), f.pin('v1.0.1'));
  f.git('add', f.workflow);
  writeFileSync(join(f.root, f.notes), 'DIRTY\n');
  const result = f.resolve();
  assert.equal(result.status, 0, result.stderr);
  const projection = f.git('show', ':SOURCES.md');
  assert.match(projection, new RegExp(f.digest(f.pin('v1.0.1'))));
  assert.match(projection, new RegExp(f.digest('reviewed notes\n')));
  assert.doesNotMatch(projection, new RegExp(f.digest('DIRTY\n')));
  assert.equal(readFileSync(join(f.root, f.notes), 'utf8'), 'DIRTY\n');
  assert.equal(f.git('show', `:${f.workflow}`), f.pin('v1.0.1'));
  const index = f.git('ls-files', '--stage');
  assert.equal(f.resolve().status, 0, 'action pin repair stays idempotent');
  assert.equal(f.git('ls-files', '--stage'), index);
});

test('action pin repair ignores an unstaged workflow pin', (t) => {
  const f = actionPinRepo(t);
  writeFileSync(join(f.root, f.workflow), f.pin('v1.0.1'));
  writeFileSync(join(f.root, f.notes), 'DIRTY\n');
  const index = f.git('ls-files', '--stage');
  const result = f.resolve();
  assert.equal(result.status, 0, result.stderr);
  const projection = f.git('show', ':SOURCES.md');
  assert.match(projection, new RegExp(f.digest(f.pin('v1.0.0'))));
  assert.doesNotMatch(projection, new RegExp(f.digest(f.pin('v1.0.1'))));
  assert.doesNotMatch(projection, new RegExp(f.digest('DIRTY\n')));
  assert.equal(readFileSync(join(f.root, f.workflow), 'utf8'), f.pin('v1.0.1'));
  assert.equal(readFileSync(join(f.root, f.notes), 'utf8'), 'DIRTY\n');
  assert.equal(f.git('show', `:${f.workflow}`), f.pin('v1.0.0'));
  assert.equal(f.git('ls-files', '--stage'), index);
});
