import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { manifestRepo, env, resolver } from './resolve-repository-docs.test.mjs';

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

function writeRegistrations(root, sibling) {
  const audit = 'scripts/ios/launch-ui-regression-audit.py';
  const expectation = 'scripts/ios/test_launch_ui_regression_audit.py';
  const coverage = 'packages/shared-lib/src/launch-ui-regression-audit.test.ts';
  mkdirSync(dirname(join(root, audit)), { recursive: true });
  mkdirSync(dirname(join(root, coverage)), { recursive: true });
  const extraTuple = sibling
    ? `    ("${sibling}", "${sibling}.py", "check_${sibling}"),\n`
    : '';
  const extraName = sibling ? `check_${sibling}, ` : '';
  const extraCall = sibling ? `    check_${sibling}()\n` : '';
  const names = ['day', ...(sibling ? [sibling] : []), 'report'];
  writeFileSync(join(root, audit), `_AUDIT_SIBLINGS = (
    ("day", "day.py", "check_day"),
${extraTuple}    ("report", "report.py", "write_outputs"),
)
${extraName}check_day, write_outputs = [
    _load_sibling(*sibling) for sibling in _AUDIT_SIBLINGS
]


def main():
    check_day()
${extraCall}    write_outputs()
`);
  writeFileSync(join(root, expectation), `def test_siblings():
    self.assertEqual(
        [item[0] for item in AUDIT._AUDIT_SIBLINGS],
        [
${names.map((name) => `            "${name}",`).join('\n')}
        ],
    )
`);
  const inputs = ['day.py', ...(sibling ? [`${sibling}.py`] : []), 'report.py'];
  writeFileSync(join(root, coverage), `for (const input of [
${inputs.map((name) => `  '${name}',`).join('\n')}
]) {
  input
}
`);
}

function registrationMerge(t, theirsBody, oursBody) {
  const fixture = manifestRepo(t);
  writeRegistrations(fixture.root, null);
  fixture.git('add', '.');
  fixture.git('commit', '-qm', 'audit base');
  fixture.git('switch', '-qc', 'incoming');
  if (theirsBody) writeFileSync(join(fixture.root, 'scripts/ios/launch-ui-regression-audit.py'), theirsBody);
  else writeRegistrations(fixture.root, 'gesture');
  fixture.commit(
    'node --test shared.test.mjs theirs.test.mjs',
    ['$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml'],
    'incoming',
  );
  fixture.git('switch', '-q', 'feature');
  if (oursBody) writeFileSync(join(fixture.root, 'scripts/ios/launch-ui-regression-audit.py'), oursBody);
  else writeRegistrations(fixture.root, 'home');
  fixture.commit(
    'node --test shared.test.mjs ours.test.mjs',
    ['$TURBO_DEFAULT$', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs'],
    'ours',
  );
  const merge = spawnSync('git', ['merge', '--no-commit', 'incoming'], { cwd: fixture.root, env });
  assert.equal(merge.status, 1, merge.stderr?.toString());
  const run = (flag) => spawnSync('python3', [resolver, '--root', fixture.root, flag], { env, encoding: 'utf8' });
  return { ...fixture, run };
}

test('manifest union keeps both launch-audit sibling registrations', (t) => {
  const fixture = registrationMerge(t);
  const result = fixture.run('--union-manifests');
  assert.equal(result.status, 0, result.stderr);
  const audit = readFileSync(join(fixture.root, 'scripts/ios/launch-ui-regression-audit.py'), 'utf8');
  assert.match(audit, /check_home\(/);
  assert.match(audit, /check_gesture\(/);
  assert.doesNotMatch(audit, /^<<<<<<</m);
  const names = readFileSync(join(fixture.root, 'scripts/ios/test_launch_ui_regression_audit.py'), 'utf8');
  assert.match(names, /\[\n\s+"day",\n\s+"gesture",\n\s+"home",/);
  assert.doesNotMatch(names, /^<<<<<<</m);
  const coverage = readFileSync(
    join(fixture.root, 'packages/shared-lib/src/launch-ui-regression-audit.test.ts'),
    'utf8',
  );
  assert.match(coverage, /for \(const input of \[\n {2}'day\.py',\n {2}'gesture\.py',\n {2}'home\.py',\n {2}'report\.py',\n\]\)/);
  assert.deepEqual(JSON.parse(readFileSync(join(fixture.root, fixture.turbo), 'utf8')).tasks.test.inputs, [
    '$TURBO_DEFAULT$', 'theirs.mjs', 'shared.mjs', 'workflow.yml', 'workflow.yml', 'ours.mjs',
  ]);
  assert.equal(fixture.git('diff', '--name-only', '--diff-filter=U'), '');
  const index = fixture.git('ls-files', '--stage');
  assert.equal(fixture.run('--union-manifests').status, 0, 'resolved registrations stay idempotent');
  assert.equal(fixture.git('ls-files', '--stage'), index);
});

test('manifest union refuses a non-additive launch-audit conflict without staging', (t) => {
  const body = (token) => `_AUDIT_SIBLINGS = (
    ("day", "day.py", "check_day"),
    ("${token}", "${token}.py", "check_${token}"),
    ("report", "report.py", "write_outputs"),
)
check_day, check_${token}, write_outputs = [
    _load_sibling(*sibling) for sibling in _AUDIT_SIBLINGS
]


def main():
    check_day()
    check_${token}()
    return "${token}"
    write_outputs()
`;
  const fixture = registrationMerge(t, body('gesture'), body('home'));
  const audit = 'scripts/ios/launch-ui-regression-audit.py';
  const before = readFileSync(join(fixture.root, audit), 'utf8');
  const index = fixture.git('ls-files', '--stage');
  const result = fixture.run('--union-manifests');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /not additive/);
  assert.equal(readFileSync(join(fixture.root, audit), 'utf8'), before);
  assert.equal(fixture.git('ls-files', '--stage'), index);
});

