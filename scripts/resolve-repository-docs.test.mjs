import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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
