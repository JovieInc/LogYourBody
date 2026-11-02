import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

export const resolver = fileURLToPath(new URL('./resolve-repository-docs.py', import.meta.url));
export const env = {
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

export function manifestRepo(t) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-manifest-union-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: root, env, encoding: 'utf8' });
  const pkg = 'packages/shared-lib/package.json';
  const turbo = 'packages/shared-lib/turbo.json';
  const output = 'docs/REPOSITORY_SOURCES.md';
  const writeManifests = (testScript, inputs) => {
    mkdirSync(dirname(join(root, pkg)), { recursive: true });
    writeFileSync(join(root, pkg), `${JSON.stringify({
      name: 'shared',
      scripts: { test: testScript },
    }, null, 2)}\n`);
    writeFileSync(join(root, turbo), `{
  "extends": ["//"],
  "tasks": {
    "test": {
      "outputs": ["$TURBO_EXTENDS$"],
      "inputs": [
${inputs.map((item) => `        ${JSON.stringify(item)}`).join(',\n')}
      ]
    },
    "test:mutation": {
      "cache": false
    }
  }
}
`);
  };
  const project = () => execFileSync('python3', [
    fileURLToPath(new URL('./repository_docs.py', import.meta.url)), '--root', root, '--write',
  ], { env });
  const commit = (testScript, inputs, message) => {
    writeManifests(testScript, inputs);
    project();
    git('add', '.');
    git('commit', '-qm', message);
  };
  git('init', '-q', '-b', 'feature');
  git('config', 'core.hooksPath', '/dev/null');
  mkdirSync(join(root, 'docs'), { recursive: true });
  writeFileSync(join(root, 'README.md'), 'Local instructions\n');
  writeFileSync(join(root, 'NOTES.md'), 'Shared note\n');
  writeFileSync(join(root, 'repository-docs.json'), JSON.stringify({
    schemaVersion: 1,
    repository: 'example/app',
    entrypoints: ['README.md'],
    sources: [
      { path: pkg, purpose: 'Test wiring' },
      { path: turbo, purpose: 'Cache inputs' },
    ],
    imports: [],
    output,
  }));
  commit('node --test shared.test.mjs', ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml'], 'base');
  return { root, git, pkg, turbo, output, commit };
}

function conflictingManifests(t, theirsTest, theirsInputs, oursTest = 'node --test shared.test.mjs ours.test.mjs', oursInputs = ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs']) {
  const fixture = manifestRepo(t);
  fixture.git('switch', '-qc', 'incoming');
  fixture.commit(theirsTest, theirsInputs, 'incoming');
  fixture.git('switch', '-q', 'feature');
  fixture.commit(oursTest, oursInputs, 'ours');
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: fixture.root, env });
  assert.equal(merge.status, 1, 'fixture must contain a real merge conflict');
  const run = (flag) => spawnSync('python3', [resolver, '--root', fixture.root, flag], { env, encoding: 'utf8' });
  return { ...fixture, run };
}

test('manifest union keeps both parents test inputs and inline turbo arrays', (t) => {
  const fixture = conflictingManifests(
    t,
    'node --test shared.test.mjs theirs.test.mjs',
    ['$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml'],
  );
  writeFileSync(join(fixture.root, 'NOTES.md'), 'Unstaged note\n');
  assert.notEqual(fixture.run('--staged').status, 0);
  const refused = spawnSync('python3', [resolver, '--root', fixture.root], { env, encoding: 'utf8' });
  assert.notEqual(refused.status, 0);
  assert.match(refused.stderr, /resolve source conflicts first/);
  const result = fixture.run('--union-manifests');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(
    JSON.parse(readFileSync(join(fixture.root, fixture.pkg), 'utf8')).scripts.test,
    'node --test shared.test.mjs theirs.test.mjs ours.test.mjs',
  );
  const turbo = readFileSync(join(fixture.root, fixture.turbo), 'utf8');
  assert.match(turbo, /"extends": \["\/\/"\]/);
  assert.match(turbo, /"outputs": \["\$TURBO_EXTENDS\$"\]/);
  assert.deepEqual(JSON.parse(turbo).tasks.test.inputs, [
    '$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs',
  ]);
  assert.equal(fixture.git('ls-files', '-u'), '');
  const projection = fixture.git('show', `:${fixture.output}`);
  assert.match(projection, /theirs\.test\.mjs/);
  assert.match(projection, /ours\.test\.mjs/);
  assert.equal(readFileSync(join(fixture.root, 'NOTES.md'), 'utf8'), 'Unstaged note\n');
  const index = fixture.git('ls-files', '--stage');
  assert.equal(fixture.run('--union-manifests').status, 0, 'resolved manifests stay idempotent');
  assert.equal(fixture.git('ls-files', '--stage'), index);
});

for (const [name, testScript, inputs] of [
  ['deleted test', 'node --test', ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml']],
  ['reordered input', 'node --test shared.test.mjs extra.test.mjs', ['shared.mjs', '$TURBO_DEFAULT$', 'workflow.yml', 'workflow.yml', 'theirs.mjs']],
  ['replaced script', 'node --test other.test.mjs', ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'extra.mjs']],
  ['dropped repeated input', 'node --test shared.test.mjs extra.test.mjs', ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml']],
]) {
  test(`manifest union refuses ${name} without staging`, (t) => {
    const fixture = conflictingManifests(t, testScript, inputs);
    const before = readFileSync(join(fixture.root, fixture.pkg), 'utf8');
    const index = fixture.git('ls-files', '--stage');
    const result = fixture.run('--union-manifests');
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /additive manifest union keeps every parent test input/);
    assert.equal(readFileSync(join(fixture.root, fixture.pkg), 'utf8'), before);
    assert.equal(fixture.git('ls-files', '--stage'), index);
  });
}

test('manifest union leaves a conflicted correction ledger for its resolver', (t) => {
  const fixture = manifestRepo(t);
  const ledger = 'packages/shared-lib/corrections.json';
  const writeLedger = (body) => {
    mkdirSync(dirname(join(fixture.root, ledger)), { recursive: true });
    writeFileSync(join(fixture.root, ledger), body);
  };
  writeLedger('[]\n');
  fixture.git('add', ledger);
  fixture.git('commit', '-qm', 'ledger base');
  fixture.git('switch', '-qc', 'incoming');
  writeLedger('[{"fingerprint":"theirs"}]\n');
  fixture.commit(
    'node --test shared.test.mjs theirs.test.mjs',
    ['$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml'],
    'incoming',
  );
  fixture.git('switch', '-q', 'feature');
  writeLedger('[{"fingerprint":"ours"}]\n');
  fixture.commit(
    'node --test shared.test.mjs ours.test.mjs',
    ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs'],
    'ours',
  );
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: fixture.root, env });
  assert.equal(merge.status, 1, merge.stderr?.toString());
  const beforeLedger = readFileSync(join(fixture.root, ledger), 'utf8');
  const result = spawnSync('python3', [resolver, '--root', fixture.root, '--union-manifests'], {
    env, encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fixture.git('diff', '--name-only', '--diff-filter=U').trim(), ledger);
  assert.equal(readFileSync(join(fixture.root, ledger), 'utf8'), beforeLedger);
  assert.match(beforeLedger, /^<<<<<<< /m);
  const testScript = JSON.parse(readFileSync(join(fixture.root, fixture.pkg), 'utf8')).scripts.test;
  assert.match(testScript, /ours\.test\.mjs/);
  assert.match(testScript, /theirs\.test\.mjs/);
  assert.equal(fixture.git('ls-files', '-u', '--', fixture.output).trim(), '');
});

test('manifest union refuses an unrelated conflict without staging', (t) => {
  const fixture = manifestRepo(t);
  fixture.git('switch', '-qc', 'incoming');
  writeFileSync(join(fixture.root, 'NOTES.md'), 'Incoming note\n');
  fixture.commit(
    'node --test shared.test.mjs theirs.test.mjs',
    ['$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml'],
    'incoming',
  );
  fixture.git('switch', '-q', 'feature');
  writeFileSync(join(fixture.root, 'NOTES.md'), 'Branch note\n');
  fixture.commit(
    'node --test shared.test.mjs ours.test.mjs',
    ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs'],
    'ours',
  );
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: fixture.root, env });
  assert.equal(merge.status, 1);
  const before = readFileSync(join(fixture.root, fixture.pkg), 'utf8');
  const index = fixture.git('ls-files', '--stage');
  const result = spawnSync('python3', [resolver, '--root', fixture.root, '--union-manifests'], {
    env, encoding: 'utf8',
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /unrelated conflicts/);
  assert.equal(readFileSync(join(fixture.root, fixture.pkg), 'utf8'), before);
  assert.equal(fixture.git('ls-files', '--stage'), index);
});

test('manifest union refuses a symlink stage and a commit that is not a merge', (t) => {
  const fixture = conflictingManifests(
    t,
    'node --test shared.test.mjs theirs.test.mjs',
    ['$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml'],
  );
  const blob = fixture.git('rev-parse', `:3:${fixture.pkg}`).trim();
  const before = readFileSync(join(fixture.root, fixture.pkg), 'utf8');
  execFileSync('git', ['update-index', '--index-info'], {
    cwd: fixture.root,
    env,
    input: `120000 ${blob} 3\t${fixture.pkg}\n`,
  });
  const index = fixture.git('ls-files', '--stage');
  const symlink = fixture.run('--union-manifests');
  assert.notEqual(symlink.status, 0);
  assert.match(symlink.stderr, /regular files/);
  assert.equal(readFileSync(join(fixture.root, fixture.pkg), 'utf8'), before);
  assert.equal(fixture.git('ls-files', '--stage'), index);
  fixture.git('merge', '--abort');
  const absent = fixture.run('--union-manifests');
  assert.notEqual(absent.status, 0);
  assert.match(absent.stderr, /repository-docs:/);
});
