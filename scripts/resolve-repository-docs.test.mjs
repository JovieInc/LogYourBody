import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const resolver = fileURLToPath(new URL('./resolve-repository-docs.py', import.meta.url));
const env = {
  ...Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_'))),
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_CONFIG_GLOBAL: '/dev/null',
  GIT_AUTHOR_NAME: 'fixture',
  GIT_AUTHOR_EMAIL: 'fixture@example.invalid',
  GIT_COMMITTER_NAME: 'fixture',
  GIT_COMMITTER_EMAIL: 'fixture@example.invalid',
};
const base = '# Original\n\nOriginal behavior.\n\nValidation:\n\nRun checks.\n';
const addition = '## Approval presentation\n\nExplicit approval only.\n\n';
const ours = '# Native selection\n\n## Review\n\nKeep rollback and feature gates.\n';

function fixture(t, incoming = base.replace('Validation:', `${addition}Validation:`)) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-doc-sections-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  const path = 'docs/engineering/selection.md';
  mkdirSync(dirname(join(root, path)), { recursive: true });
  const commit = (content) => {
    writeFileSync(join(root, path), content);
    git('add', path);
    git('commit', '-qm', 'fixture');
  };
  git('init', '-q', '-b', 'feature');
  git('config', 'core.hooksPath', '/dev/null');
  commit(base);
  git('switch', '-qc', 'incoming');
  commit(incoming);
  git('switch', '-q', 'feature');
  commit(ours);
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: root, env });
  assert.equal(merge.status, 1, 'fixture must contain a real merge conflict');
  const resolve = (target = path) => spawnSync('python3', [
    resolver, '--root', root, '--merge-sections', target,
  ], { env, encoding: 'utf8' });
  return { root, git, path, resolve };
}

test('documentation merge preserves the branch and incoming standalone sections without staging', (t) => {
  const f = fixture(t);
  writeFileSync(join(f.root, f.path), 'Unrelated working edits must survive.\n');
  const index = f.git('ls-files', '--stage');
  const result = f.resolve();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, `${ours}\n${addition.trim()}\n`);
  assert.equal(f.git('ls-files', '--stage'), index);
  assert.equal(readFileSync(join(f.root, f.path), 'utf8'), 'Unrelated working edits must survive.\n');
  assert.equal(f.resolve().stdout, result.stdout, 'repeated generation uses immutable index stages');
});

for (const [name, incoming] of [
  ['incoming replacement', base.replace('Original behavior.', 'Changed behavior.') + addition],
  ['incoming deletion', base.replace('Original behavior.\n', '') + addition],
  ['unheaded addition', base + '\nUnscoped prose.\n'],
  ['duplicate branch heading', base + '\n## Review\n\nConflicting review.\n'],
  ['nested section', base + '\n### Approval\n\nDepends on previous context.\n'],
  ['conflict markers', base + '\n## Approval\n\n|| base\n'],
]) {
  test(`documentation merge refuses ${name} without changing files or index`, (t) => {
    const f = fixture(t, incoming);
    const before = readFileSync(join(f.root, f.path), 'utf8');
    const index = f.git('ls-files', '--stage');
    const result = f.resolve();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /repository-docs:/);
    assert.equal(result.stdout, '');
    assert.equal(readFileSync(join(f.root, f.path), 'utf8'), before);
    assert.equal(f.git('ls-files', '--stage'), index);
  });
}

test('documentation merge requires an active conflict and a regular documentation path', (t) => {
  const f = fixture(t);
  for (const path of ['../escape.md', 'AGENTS.md', 'apps/web/source.ts']) {
    assert.notEqual(f.resolve(path).status, 0);
  }
  const blob = f.git('rev-parse', `:3:${f.path}`).trim();
  execFileSync('git', ['update-index', '--index-info'], {
    cwd: f.root, env, input: `120000 ${blob} 3\t${f.path}\n`,
  });
  assert.notEqual(f.resolve().status, 0, 'symlink stages are not documentation');
  f.git('merge', '--abort');
  assert.notEqual(f.resolve().status, 0, 'ordinary commits cannot generate a merge');
});

for (const mode of ['--refresh-lockfile', '--verify-lockfile']) {
  for (const present of [true, false]) {
    test(`dependency repair ${mode} restores ${present ? 'existing' : 'missing'} outputs after staging fails`, (t) => {
      const root = mkdtempSync(join(tmpdir(), 'lyb-dependency-docs-'));
      t.after(() => rmSync(root, { recursive: true, force: true }));
      const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
      const output = 'SOURCES.md';
      const lockfile = join(root, 'pnpm-lock.yaml');
      const originalLock = mode === '--verify-lockfile' ? 'resolved lock\n' : 'old lock\n';
      git('init', '-q', '-b', 'dependency');
      git('config', 'core.hooksPath', '/dev/null');
      writeFileSync(join(root, 'README.md'), 'Local instructions\n');
      writeFileSync(join(root, 'package.json'), JSON.stringify({ dependencies: { glob: '11.1.0' } }));
      writeFileSync(lockfile, originalLock);
      writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
        schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
        sources: [{ path: 'package.json', purpose: 'Dependencies' }], imports: [], output,
      }));
      if (present) execFileSync('python3', [
        fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
      ], { env });
      git('add', '.');
      git('commit', '-qm', 'fixture');
      writeFileSync(join(root, 'package.json'), JSON.stringify({ dependencies: { glob: '14.0.2' } }));
      git('add', 'package.json');
      writeFileSync(join(root, 'README.md'), 'Unstaged local instructions\n');
      mkdirSync(join(root, 'bin'));
      writeFileSync(join(root, 'bin/corepack'), `#!/usr/bin/env python3
import sys
from pathlib import Path
lock = Path('pnpm-lock.yaml')
if '--no-frozen-lockfile' in sys.argv:
    lock.write_text('resolved lock\\n')
elif lock.read_text() != 'resolved lock\\n':
    print('ERR_PNPM_OUTDATED_LOCKFILE')
    sys.exit(1)
`, { mode: 0o755 });
      const resolve = () => spawnSync('python3', [resolver, '--root', root, mode], {
        env: { ...env, PATH: `${join(root, 'bin')}:${env.PATH}` }, encoding: 'utf8',
      });
      const projection = present ? readFileSync(join(root, output), 'utf8') : undefined;
      const index = git('ls-files', '--stage');
      const lock = join(root, '.git/index.lock');
      writeFileSync(lock, 'another Git writer\n');
      for (let attempt = 0; attempt < 2; attempt++) {
        const failed = resolve();
        assert.notEqual(failed.status, 0, failed.stdout);
        assert.match(failed.stderr, /index\.lock/);
        assert.equal(git('ls-files', '--stage'), index);
        assert.equal(readFileSync(lock, 'utf8'), 'another Git writer\n');
        assert.equal(readFileSync(lockfile, 'utf8'), originalLock);
        assert.equal(existsSync(join(root, output)), present);
        if (present) assert.equal(readFileSync(join(root, output), 'utf8'), projection);
      }
      rmSync(lock);
      const retry = resolve();
      assert.equal(retry.status, 0, retry.stderr);
      assert.match(git('show', `:${output}`), /"glob": "14\.0\.2"/);
      assert.equal(readFileSync(lockfile, 'utf8'), 'resolved lock\n');
      assert.equal(readFileSync(join(root, 'README.md'), 'utf8'), 'Unstaged local instructions\n');
      const repairedIndex = git('ls-files', '--stage');
      assert.equal(resolve().status, 0, 'successful repair remains idempotent');
      assert.equal(git('ls-files', '--stage'), repairedIndex);
    });
  }
}

function jsonConflict(t, base, ours, theirs, path = 'config/inputs.json') {
  const root = mkdtempSync(join(tmpdir(), 'lyb-json-union-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  mkdirSync(dirname(join(root, path)), { recursive: true });
  const commit = (content) => {
    writeFileSync(join(root, path), content);
    git('add', path);
    git('commit', '-qm', 'fixture');
  };
  git('init', '-q', '-b', 'feature');
  git('config', 'core.hooksPath', '/dev/null');
  commit(base);
  git('switch', '-qc', 'incoming');
  commit(theirs);
  git('switch', '-q', 'feature');
  commit(ours);
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: root, env });
  assert.equal(merge.status, 1, 'fixture must contain a real merge conflict');
  const resolve = () => spawnSync('python3', [
    resolver, '--root', root, '--union-json', path,
  ], { env, encoding: 'utf8' });
  return { root, git, path, resolve };
}

const jsonBase = '{\n  "items": ["a", "b"],\n  "n": 1\n}\n';
const jsonOurs = '{\n  "items": ["a", "x", "b"],\n  "n": 1,\n  "ours": true\n}\n';
const jsonTheirs = '{\n  "items": ["a", "b", "y"],\n  "nested": {"z": 1},\n  "n": 1\n}\n';

test('json union keeps branch order and incoming additions without staging', (t) => {
  const f = jsonConflict(t, jsonBase, jsonOurs, jsonTheirs);
  writeFileSync(join(f.root, f.path), 'Unrelated working edits must survive.\n');
  const index = f.git('ls-files', '--stage');
  const result = f.resolve();
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, [
    '{',
    '  "items": [',
    '    "a",',
    '    "x",',
    '    "b",',
    '    "y"',
    '  ],',
    '  "nested": {',
    '    "z": 1',
    '  },',
    '  "n": 1,',
    '  "ours": true',
    '}',
    '',
  ].join('\n'));
  assert.equal(f.git('ls-files', '--stage'), index);
  assert.equal(readFileSync(join(f.root, f.path), 'utf8'), 'Unrelated working edits must survive.\n');
  assert.equal(f.resolve().stdout, result.stdout, 'repeated generation uses immutable index stages');
});

test('json union preserves a duplicate inherited from the merge base', (t) => {
  const base = '{\n  "items": ["a", "a", "b"]\n}\n';
  const ours = '{\n  "items": ["a", "a", "x", "b"]\n}\n';
  const theirs = '{\n  "items": ["a", "a", "b", "y"]\n}\n';
  const result = jsonConflict(t, base, ours, theirs).resolve();
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout).items, ['a', 'a', 'x', 'b', 'y']);
});

for (const [name, ours, theirs, pattern] of [
  ['list deletion', jsonBase.replace('"b"', '"z"'), jsonTheirs, /list deletions or reorders/],
  ['list reorder', jsonBase.replace('["a", "b"]', '["b", "a"]'), jsonTheirs, /list deletions or reorders/],
  ['scalar replacement', jsonOurs.replace('"n": 1', '"n": 2'), jsonTheirs, /conflicting replacement/],
  ['duplicate values', jsonOurs.replace('["a", "x", "b"]', '["a", "x", "x", "b"]'), jsonTheirs, /duplicate/],
  ['conflict markers', jsonOurs, jsonTheirs.replace('\n  "n": 1\n', '\n<<<<<<< incoming\n  "n": 1\n'), /conflict markers/],
]) {
  test(`json union refuses ${name} without changing files or index`, (t) => {
    const f = jsonConflict(t, jsonBase, ours, theirs);
    const before = readFileSync(join(f.root, f.path), 'utf8');
    const index = f.git('ls-files', '--stage');
    const result = f.resolve();
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, pattern);
    assert.equal(result.stdout, '');
    assert.equal(readFileSync(join(f.root, f.path), 'utf8'), before);
    assert.equal(f.git('ls-files', '--stage'), index);
  });
}

test('json union requires an active conflict and a regular json path', (t) => {
  const f = jsonConflict(t, jsonBase, jsonOurs, jsonTheirs);
  for (const path of ['../escape.json', 'AGENTS.md', 'docs/engineering/selection.md']) {
    const result = spawnSync('python3', [resolver, '--root', f.root, '--union-json', path], { env, encoding: 'utf8' });
    assert.notEqual(result.status, 0, path);
  }
  const blob = f.git('rev-parse', `:3:${f.path}`).trim();
  execFileSync('git', ['update-index', '--index-info'], {
    cwd: f.root, env, input: `120000 ${blob} 3\t${f.path}\n`,
  });
  assert.match(f.resolve().stderr, /regular indexed files/);
  f.git('merge', '--abort');
  assert.notEqual(f.resolve().status, 0, 'ordinary commits cannot generate a merge');
});

test('projection merge fingerprints the merged source instead of either parent', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'lyb-projection-merge-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  const source = 'packages/shared-lib/turbo.json';
  const output = 'docs/REPOSITORY_SOURCES.md';
  const digest = (bytes) => createHash('sha256').update(bytes).digest('hex');
  const turbo = (ours, theirs) => `${JSON.stringify({ oursSlot: ['a', ...ours], theirsSlot: ['b', ...theirs] }, null, 2)}\n`;
  const commit = (content) => {
    mkdirSync(dirname(join(root, source)), { recursive: true });
    writeFileSync(join(root, 'README.md'), 'Local instructions\n');
    writeFileSync(join(root, 'repository-docs.json'), `${JSON.stringify({
      schemaVersion: 1,
      repository: 'example/app',
      entrypoints: ['README.md'],
      sources: [{ path: source, purpose: 'Test cache inputs' }],
      imports: [],
      output,
    })}\n`);
    writeFileSync(join(root, source), content);
    execFileSync('python3', [
      fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
    ], { env });
    git('add', '.');
    git('commit', '-qm', 'fixture');
  };
  git('init', '-q', '-b', 'feature');
  git('config', 'core.hooksPath', '/dev/null');
  commit(turbo([], []));
  git('switch', '-qc', 'incoming');
  commit(turbo([], ['expiry']));
  git('switch', '-q', 'feature');
  commit(turbo(['cert'], []));
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
  assert.equal(git('diff', '--name-only', '--diff-filter=U').trim(), output);
  const parents = ['HEAD', 'MERGE_HEAD'].map((rev) => digest(git('show', `${rev}:${source}`)));
  const result = spawnSync('python3', [resolver, '--root', root], { env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const merged = readFileSync(join(root, source));
  assert.match(merged.toString(), /cert/);
  assert.match(merged.toString(), /expiry/);
  const projection = git('show', `:${output}`);
  assert.equal(git('diff', '--name-only', '--diff-filter=U').trim(), '');
  assert.match(projection, new RegExp(digest(merged)));
  for (const parent of parents) assert.equal(projection.includes(parent), false);
  assert.equal(projection.includes('<<<<<<<'), false);
  assert.equal(spawnSync('python3', [resolver, '--root', root], { env, encoding: 'utf8' }).status, 0);
});
