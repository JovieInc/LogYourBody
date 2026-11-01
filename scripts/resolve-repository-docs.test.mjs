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

function sourceMapFixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-source-map-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  const output = 'SOURCES.md';
  git('init', '-q', '-b', 'ours');
  git('config', 'core.hooksPath', '/dev/null');
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [
      { path: 'a.txt', purpose: 'First fingerprint' },
      { path: 'b.txt', purpose: 'Second fingerprint' },
    ],
    imports: [], output,
  }));
  writeFileSync(join(root, 'a.txt'), 'base-a\n');
  writeFileSync(join(root, 'b.txt'), 'base-b\n');
  const generate = () => execFileSync('python3', [
    fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
  ], { env });
  const commit = () => {
    git('add', '-A');
    git('commit', '-qm', 'fixture');
  };
  generate();
  commit();
  git('branch', 'theirs');
  return { root, git, output, generate, commit };
}

test('conflicted source map keeps both merged fingerprints and ignores unstaged source bytes', (t) => {
  const f = sourceMapFixture(t);
  writeFileSync(join(f.root, 'a.txt'), 'ours-a\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  writeFileSync(join(f.root, 'b.txt'), 'theirs-b\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  const merge = spawnSync('git', ['merge', '--no-commit', 'theirs'], { cwd: f.root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
  assert.match(f.git('diff', '--name-only', '--diff-filter=U'), /^SOURCES\.md$/m);
  const before = f.git('ls-files', '--stage');
  writeFileSync(join(f.root, 'a.txt'), 'DIRTY\n');
  const result = spawnSync('python3', [resolver, '--root', f.root], { env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const staged = f.git('show', ':SOURCES.md');
  const digest = (text) => createHash('sha256').update(text).digest('hex');
  assert.equal(staged.includes('<<<<<<<'), false);
  assert.match(staged, new RegExp(digest('ours-a\n')));
  assert.match(staged, new RegExp(digest('theirs-b\n')));
  assert.doesNotMatch(staged, new RegExp(digest('DIRTY\n')));
  assert.equal(f.git('show', ':a.txt'), 'ours-a\n');
  assert.equal(readFileSync(join(f.root, 'a.txt'), 'utf8'), 'DIRTY\n');
  assert.equal(f.git('ls-files', '--unmerged'), '');
  assert.notEqual(f.git('ls-files', '--stage'), before);
});

test('conflicted source map refuses an unmerged fingerprint input', (t) => {
  const f = sourceMapFixture(t);
  writeFileSync(join(f.root, 'a.txt'), 'ours-a\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  writeFileSync(join(f.root, 'a.txt'), 'theirs-a\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  const merge = spawnSync('git', ['merge', '--no-commit', 'theirs'], { cwd: f.root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
  const before = readFileSync(join(f.root, f.output), 'utf8');
  const index = f.git('ls-files', '--stage');
  const result = spawnSync('python3', [resolver, '--root', f.root], { env, encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /resolve source conflicts first: a\.txt/);
  assert.equal(readFileSync(join(f.root, f.output), 'utf8'), before);
  assert.equal(f.git('ls-files', '--stage'), index);
});

test('conflicted source map refuses unstaged pinned drift without rewriting the projection', (t) => {
  const f = sourceMapFixture(t);
  writeFileSync(join(f.root, 'a.txt'), 'ours-a\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'theirs');
  writeFileSync(join(f.root, 'b.txt'), 'theirs-b\n');
  f.generate();
  f.commit();
  f.git('switch', '-q', 'ours');
  const merge = spawnSync('git', ['merge', '--no-commit', 'theirs'], { cwd: f.root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
  const registry = JSON.parse(readFileSync(join(f.root, 'repository-docs.json'), 'utf8'));
  registry.imports = [{
    repository: 'example/policy',
    revision: 'a'.repeat(40),
    path: 'policy.md',
    destination: 'policy.md',
    sha256: '0'.repeat(64),
  }];
  writeFileSync(join(f.root, 'repository-docs.json'), JSON.stringify(registry));
  const before = readFileSync(join(f.root, f.output));
  const index = f.git('ls-files', '--stage');
  const result = spawnSync('python3', [resolver, '--root', f.root], { env, encoding: 'utf8' });
  assert.notEqual(result.status, 0, result.stdout);
  assert.match(result.stderr, /pinned copy missing or changed: policy\.md/);
  assert.deepEqual(readFileSync(join(f.root, f.output)), before);
  assert.equal(f.git('ls-files', '--stage'), index);
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

function diagnosticPinFixture(t, { workflowExtra = '', extraPath = null } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-diagnostic-pin-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  const output = 'SOURCES.md';
  const project = 'apps/ios/LogYourBody.xcodeproj/project.pbxproj';
  const workflow = '.github/workflows/ios-ui-diagnostics.yml';
  const ledger = 'packages/shared-lib/corrections.json';
  const digest = (text) => createHash('sha256').update(text).digest('hex');
  const pinFile = (pin, extra = '') =>
    `name: diagnostics\nDEPENDENCIES = {\n  '${project}': '${pin}',\n}\n${extra}`;
  const generate = () => execFileSync('python3', [
    fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
  ], { env });
  const commit = () => {
    git('add', '-A');
    git('commit', '-qm', 'fixture');
  };
  git('init', '-q', '-b', 'ours');
  git('config', 'core.hooksPath', '/dev/null');
  for (const path of [project, workflow, ledger]) mkdirSync(dirname(join(root, path)), { recursive: true });
  const baseProject = 'alpha\nkeep\nomega\n';
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [
      { path: 'a.txt', purpose: 'First fingerprint' },
      { path: 'b.txt', purpose: 'Second fingerprint' },
    ],
    imports: [], output,
  }));
  writeFileSync(join(root, 'a.txt'), 'base-a\n');
  writeFileSync(join(root, 'b.txt'), 'base-b\n');
  writeFileSync(join(root, project), baseProject);
  writeFileSync(join(root, workflow), pinFile(digest(baseProject)));
  writeFileSync(join(root, ledger), 'base ledger\n');
  generate();
  commit();
  git('branch', 'theirs');
  const oursProject = 'ALPHA\nkeep\nomega\n';
  writeFileSync(join(root, 'a.txt'), 'ours-a\n');
  writeFileSync(join(root, project), oursProject);
  writeFileSync(join(root, workflow), pinFile(digest(oursProject)));
  writeFileSync(join(root, ledger), 'ours ledger\n');
  if (extraPath) writeFileSync(join(root, extraPath), 'ours extra\n');
  generate();
  commit();
  git('switch', '-q', 'theirs');
  const theirsProject = 'alpha\nkeep\nOMEGA\n';
  writeFileSync(join(root, 'b.txt'), 'theirs-b\n');
  writeFileSync(join(root, project), theirsProject);
  writeFileSync(join(root, workflow), pinFile(digest(theirsProject), workflowExtra));
  writeFileSync(join(root, ledger), 'theirs ledger\n');
  if (extraPath) writeFileSync(join(root, extraPath), 'theirs extra\n');
  generate();
  commit();
  git('switch', '-q', 'ours');
  const merge = spawnSync('git', ['merge', '--no-commit', 'theirs'], { cwd: root, env, encoding: 'utf8' });
  assert.equal(merge.status, 1, merge.stderr);
  const mergedProject = 'ALPHA\nkeep\nOMEGA\n';
  assert.equal(git('show', `:${project}`), mergedProject);
  const expected = digest(mergedProject);
  const resolve = (args = []) => spawnSync('python3', [resolver, '--root', root, ...args], {
    env, encoding: 'utf8',
  });
  return { root, git, output, project, workflow, ledger, digest, expected, resolve, pinFile };
}

test('reviewed digest resolves a pin-only workflow conflict and keeps the ledger', (t) => {
  const f = diagnosticPinFixture(t);
  writeFileSync(join(f.root, 'a.txt'), 'DIRTY\n');
  const ledger = readFileSync(join(f.root, f.ledger));
  const ledgerStages = f.git('ls-files', '--stage', '--', f.ledger);
  const index = f.git('ls-files', '--stage');
  const refused = f.resolve();
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /resolve source conflicts first:.*ios-ui-diagnostics\.yml/);
  assert.equal(f.git('ls-files', '--stage'), index);
  assert.match(readFileSync(join(f.root, f.workflow), 'utf8'), /^<<<<<<< /m);
  const wrong = f.resolve(['--reviewed-project-sha256', 'a'.repeat(64)]);
  assert.notEqual(wrong.status, 0);
  assert.match(wrong.stderr, /does not match merged source/);
  assert.equal(f.git('ls-files', '--stage'), index);
  const result = f.resolve(['--reviewed-project-sha256', f.expected]);
  assert.equal(result.status, 0, result.stderr);
  const stagedWorkflow = f.git('show', `:${f.workflow}`);
  assert.equal(stagedWorkflow, f.pinFile(f.expected));
  assert.equal(stagedWorkflow.includes(f.expected), true);
  assert.equal(f.git('ls-files', '--unmerged', '--', f.workflow), '');
  const staged = f.git('show', `:${f.output}`);
  assert.equal(staged.includes('<<<<<<<'), false);
  assert.match(staged, new RegExp(f.digest('ours-a\n')));
  assert.match(staged, new RegExp(f.digest('theirs-b\n')));
  assert.doesNotMatch(staged, new RegExp(f.digest('DIRTY\n')));
  assert.equal(readFileSync(join(f.root, 'a.txt'), 'utf8'), 'DIRTY\n');
  assert.deepEqual(readFileSync(join(f.root, f.ledger)), ledger);
  assert.equal(f.git('ls-files', '--stage', '--', f.ledger), ledgerStages);
  assert.match(ledgerStages, /corrections\.json/);
  writeFileSync(join(f.root, 'a.txt'), 'ours-a\n');
  const again = f.resolve(['--reviewed-project-sha256', f.expected]);
  assert.equal(again.status, 0, again.stderr);
  assert.equal(f.git('show', `:${f.workflow}`), stagedWorkflow);
  assert.match(f.git('show', `:${f.output}`), new RegExp(f.digest('ours-a\n')));
  assert.equal(f.git('ls-files', '--stage', '--', f.ledger), ledgerStages);
});

test('reviewed digest refuses a wider workflow conflict without writing', (t) => {
  const f = diagnosticPinFixture(t, { workflowExtra: 'other: true\n' });
  const index = f.git('ls-files', '--stage');
  const workflow = readFileSync(join(f.root, f.workflow));
  const result = f.resolve(['--reviewed-project-sha256', f.expected]);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /not limited to the reviewed project pin/);
  assert.equal(f.git('ls-files', '--stage'), index);
  assert.deepEqual(readFileSync(join(f.root, f.workflow)), workflow);
});

test('reviewed digest refuses unrelated conflicts, a dirty project, and a manual workflow edit', (t) => {
  const blocked = diagnosticPinFixture(t, { extraPath: 'notes.txt' });
  const blockedIndex = blocked.git('ls-files', '--stage');
  const blockedResult = blocked.resolve(['--reviewed-project-sha256', blocked.expected]);
  assert.notEqual(blockedResult.status, 0);
  assert.match(blockedResult.stderr, /resolve source conflicts first: notes\.txt/);
  assert.equal(blocked.git('ls-files', '--stage'), blockedIndex);

  const dirty = diagnosticPinFixture(t);
  const dirtyIndex = dirty.git('ls-files', '--stage');
  writeFileSync(join(dirty.root, dirty.project), 'ALPHA\nkeep\nOMEGA\nDIRTY\n');
  const dirtyResult = dirty.resolve(['--reviewed-project-sha256', dirty.expected]);
  assert.notEqual(dirtyResult.status, 0);
  assert.match(dirtyResult.stderr, /stage reviewed project and workflow edits first/);
  assert.equal(dirty.git('ls-files', '--stage'), dirtyIndex);

  const manual = diagnosticPinFixture(t);
  const manualIndex = manual.git('ls-files', '--stage');
  writeFileSync(join(manual.root, manual.workflow), 'manual resolution\n');
  const manualResult = manual.resolve(['--reviewed-project-sha256', manual.expected]);
  assert.notEqual(manualResult.status, 0);
  assert.match(manualResult.stderr, /manually edited workflow/);
  assert.equal(manual.git('ls-files', '--stage'), manualIndex);
  assert.equal(readFileSync(join(manual.root, manual.workflow), 'utf8'), 'manual resolution\n');
});

test('reviewed digest still updates one clean diagnostic pin', (t) => {
  const root = mkdtempSync(join(tmpdir(), 'lyb-clean-pin-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  const project = 'apps/ios/LogYourBody.xcodeproj/project.pbxproj';
  const workflow = '.github/workflows/ios-ui-diagnostics.yml';
  const output = 'SOURCES.md';
  const digest = (text) => createHash('sha256').update(text).digest('hex');
  const pinFile = (pin) => `name: diagnostics\nDEPENDENCIES = {\n  '${project}': '${pin}',\n}\n`;
  git('init', '-q', '-b', 'main');
  git('config', 'core.hooksPath', '/dev/null');
  mkdirSync(dirname(join(root, project)), { recursive: true });
  mkdirSync(dirname(join(root, workflow)), { recursive: true });
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'a.txt'), 'alpha\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1, repository: 'example/app', entrypoints: ['README.md'],
    sources: [{ path: 'a.txt', purpose: 'Fingerprint' }], imports: [], output,
  }));
  writeFileSync(join(root, project), 'alpha\n');
  writeFileSync(join(root, workflow), pinFile(digest('alpha\n')));
  execFileSync('python3', [
    fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
  ], { env });
  git('add', '-A');
  git('commit', '-qm', 'fixture');
  writeFileSync(join(root, project), 'beta\n');
  git('add', '--', project);
  const expected = digest('beta\n');
  const result = spawnSync('python3', [
    resolver, '--root', root, '--reviewed-project-sha256', expected,
  ], { env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(git('show', `:${workflow}`), pinFile(expected));
  assert.equal(readFileSync(join(root, workflow), 'utf8'), pinFile(expected));
});
