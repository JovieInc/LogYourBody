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

function manifestRepo(t) {
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
