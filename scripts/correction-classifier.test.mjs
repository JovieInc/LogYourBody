import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { classifyLedger, runClassifier } from './correction-classifier.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const script = fileURLToPath(new URL('./correction-classifier.mjs', import.meta.url));
function runCli(args, cwd) {
  const result = spawnSync(process.execPath, [script, ...args], {
    cwd,
    encoding: 'utf8',
    timeout: 5_000,
  });
  assert.ifError(result.error);
  return result;
}
const fixture = () =>
  JSON.parse(
    readFileSync(new URL('./fixtures/correction-classifier.json', import.meta.url), 'utf8'),
  );

test('fixture assigns one level and matching rule id for each ordered rule', () => {
  const input = fixture();
  const output = classifyLedger(input);
  assert.deepEqual(
    output.map(({ level, ruleId }) => [level, ruleId]),
    [
      ['codebase', 'type-or-schema'],
      ['codebase', 'code-prevention'],
      ['static', 'file-pattern-or-string'],
      ['static', 'ci-invariant'],
      ['prose', 'prose-guidance'],
      ['human', 'human-judgment'],
    ],
  );
  assert.deepEqual(classifyLedger(output), output);
  assert.equal(input[0].level, undefined, 'classification must not mutate its input');
  for (let index = 0; index < input.length; index++) {
    const { level, ruleId, ...retained } = output[index];
    assert.equal(typeof level, 'string');
    assert.equal(typeof ruleId, 'string');
    assert.deepEqual(retained, input[index]);
  }
});

test('reviewed feasibility wins over incidental wording and later feasible levels', () => {
  const rows = fixture();
  rows[0].correction = 'A human must review the prose and lint result.';
  rows[0].classification.human = { feasible: true, rationale: 'Human review is also possible.' };
  rows[5].correction = 'Approve schema.ts after reviewing the schema and CI output.';
  const output = classifyLedger(rows);
  assert.equal(output[0].level, 'codebase');
  assert.equal(output[5].level, 'human');
});

test('file names, globs and quoted strings route static corrections to the lint rule', () => {
  for (const correction of [
    'Reject imports in apps/web/src/page.tsx.',
    'Reject imports in **/*.swift.',
    'Reject changes in config-*.',
    'Reject the string "forbidden import".',
    'Reject the string `forbidden import`.',
    "Reject the string 'forbidden import'.",
  ]) {
    const row = { ...fixture()[3], correction };
    assert.equal(classifyLedger([row])[0].ruleId, 'file-pattern-or-string');
  }
  const row = {
    ...fixture()[3],
    correction: "Must the user's checks preserve the guard's invariant?",
  };
  assert.equal(classifyLedger([row])[0].ruleId, 'ci-invariant');
});

test('distinct receipts for a fingerprint receive consistent classification metadata', () => {
  const row = fixture()[3];
  const duplicate = {
    ...structuredClone(row),
    fingerprint: ` ${row.fingerprint.toUpperCase()} `,
    correction: 'Keep the invariant in build.yml.',
    source: `${row.source}#second`,
  };
  const output = classifyLedger([row, duplicate]);
  assert.deepEqual(
    output.map(({ ruleId }) => ruleId),
    ['file-pattern-or-string', 'file-pattern-or-string'],
  );
  assert.deepEqual(classifyLedger(output), output);
  duplicate.classification.static.rationale = 'A different reviewed rationale.';
  assert.throws(() => classifyLedger([row, duplicate]), /conflicting coverage annotations/);
});

test('existing levels may be promoted and can never be downgraded', () => {
  for (const [index, level, expected] of [
    [0, 'static', 'codebase'],
    [2, 'prose', 'static'],
    [4, 'human', 'prose'],
  ]) {
    assert.equal(classifyLedger([{ ...fixture()[index], level }])[0].level, expected);
  }
  for (const [index, level] of [
    [2, 'codebase'],
    [4, 'static'],
    [5, 'static'],
    [5, 'prose'],
  ]) {
    const row = { ...fixture()[index], level };
    assert.throws(() => classifyLedger([row]), /refusing to downgrade.*existing level/);
  }
});

test('unknown or incomplete shapes fail with an actionable location', () => {
  for (const rows of [null, {}, 'ledger']) {
    assert.throws(() => classifyLedger(rows), /ledger must be an array/);
  }
  const valid = fixture()[0];
  const cases = [
    [null, /entry 1.*object/],
    [[], /entry 1.*object/],
    [{ ...valid, typo: true }, /entry 1.*unknown field: typo/],
    [{ ...valid, correction: '' }, /entry 1.*correction/],
    [{ ...valid, source: 'http://example.com' }, /invalid_correction_source/],
    [{ ...valid, classification: undefined }, /entry 1.*classification.*object/],
    [{ ...valid, classification: {} }, /assessment required for codebase/],
    [{ ...valid, classification: { unknown: {} } }, /classification.*unknown field: unknown/],
    [{ ...valid, classification: { codebase: null } }, /codebase.*object/],
    [
      { ...valid, classification: { codebase: { feasible: 'true', rationale: 'reason' } } },
      /codebase.feasible/,
    ],
    [
      { ...valid, classification: { codebase: { feasible: true, rationale: '' } } },
      /codebase.rationale/,
    ],
    [
      {
        ...valid,
        classification: {
          ...valid.classification,
          human: { feasible: 'yes', rationale: 'Later assessment' },
        },
      },
      /human.feasible/,
    ],
    [
      { ...valid, classification: { codebase: { ...valid.classification.codebase, typo: true } } },
      /codebase.*unknown field: typo/,
    ],
    [{ ...valid, level: 'lint' }, /entry 1.*unknown level/],
    [{ ...valid, level: ['codebase'] }, /entry 1.*unknown level/],
    [{ ...valid, ruleId: 'unknown' }, /entry 1.*unknown ruleId/],
    [{ ...valid, level: 'static', ruleId: 'type-or-schema' }, /entry 1.*ruleId.*level/],
    [{ ...valid, guard: [] }, /guard.*object/],
    [{ ...valid, guard: { ...valid.guard, typo: true } }, /guard.*unknown field: typo/],
    [{ ...valid, guard: { anchor: valid.guard.anchor } }, /guard.path/],
    [
      { ...valid, guard: { ...valid.guard, ratchet: { typo: true } } },
      /ratchet.*unknown field: typo/,
    ],
    [{ ...valid, guard: { ...valid.guard, ratchet: {} } }, /ratchet.baseline/],
    [{ ...valid, proseOnlyReason: false }, /proseOnlyReason/],
  ];
  for (const [row, message] of cases) {
    assert.throws(() => classifyLedger([row]), message);
  }
  const noFeasibleLevel = fixture()[5];
  noFeasibleLevel.classification.human.feasible = false;
  assert.throws(() => classifyLedger([noFeasibleLevel]), /no enforceable correction level/);
});

test('CLI writes only after validation and preserves bytes on repeat runs and failures', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-classifier-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const ledger = join(directory, 'ledger.json');
  const run = (...args) => runCli(args, directory);
  writeFileSync(ledger, JSON.stringify(fixture()));
  assert.equal(run(ledger).status, 0);
  const classified = readFileSync(ledger, 'utf8');
  assert.deepEqual(JSON.parse(classified), classifyLedger(fixture()));
  assert.equal(run(ledger).status, 0);
  assert.equal(readFileSync(ledger, 'utf8'), classified);

  const invalid = fixture();
  invalid.push({ ...invalid[0], fingerprint: 'last-row', level: 'human', ruleId: 'unknown' });
  for (const contents of [
    JSON.stringify(invalid),
    '{invalid json',
    JSON.stringify([{ ...fixture()[2], level: 'codebase' }]),
  ]) {
    writeFileSync(ledger, contents);
    const result = run(ledger);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /correction-classifier:/);
    assert.equal(readFileSync(ledger, 'utf8'), contents);
  }
  assert.match(run('--unknown').stderr, /usage:/);
  assert.match(run(ledger, ledger).stderr, /usage:/);
  assert.match(run(join(directory, 'missing.json')).stderr, /ENOENT/);
});

test('pre-commit classifies a staged correction ledger', () => {
  const hook = readFileSync(join(root, '.husky/pre-commit'), 'utf8');
  assert.match(hook, /packages\/shared-lib\/corrections\.json/);
  assert.match(hook, /node scripts\/correction-classifier\.mjs \|\| exit \$\?/);
  assert.match(hook, /git add -- packages\/shared-lib\/corrections\.json/);
  assert.match(
    hook,
    /if git rev-parse -q --verify MERGE_HEAD >\/dev\/null; then\s+node scripts\/correction-classifier\.mjs --check-merge \. \|\| exit \$\?/,
  );
});

test('CLI merges parent ledgers without losing receipts or accepting conflicting evidence', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-classifier-merge-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const left = join(directory, 'left.json');
  const right = join(directory, 'right.json');
  const rows = fixture();
  const run = (...args) => runCli(args, directory);
  writeFileSync(left, JSON.stringify(rows.slice(0, 2)));
  // Main may already contain derived metadata absent from the older branch.
  writeFileSync(right, JSON.stringify(classifyLedger(rows.slice(1))));
  const rightBefore = readFileSync(right, 'utf8');
  const merged = run(left, '--merge', right);
  assert.equal(merged.status, 0, merged.stderr);
  assert.deepEqual(JSON.parse(readFileSync(left, 'utf8')), classifyLedger(rows));
  const before = readFileSync(left, 'utf8');
  assert.equal(run(left, '--merge', right).status, 0);
  assert.equal(readFileSync(left, 'utf8'), before);
  assert.equal(readFileSync(right, 'utf8'), rightBefore);

  const normalized = { ...rows[0], fingerprint: ` ${rows[0].fingerprint.toUpperCase()} ` };
  writeFileSync(right, JSON.stringify([normalized]));
  assert.equal(run(left, '--merge', right).status, 0);
  assert.equal(readFileSync(left, 'utf8'), before);

  for (const contents of [
    JSON.stringify([{ ...rows[0], correction: 'Conflicting parent evidence.' }]),
    JSON.stringify([{ ...rows[0], source: undefined }]),
    '{invalid json',
  ]) {
    writeFileSync(right, contents);
    const result = run(left, '--merge', right);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /correction-classifier:/);
    assert.equal(readFileSync(left, 'utf8'), before);
    assert.equal(readFileSync(right, 'utf8'), contents);
  }
  assert.match(run(left, '--merge').stderr, /usage:/);
  assert.match(run(left, '--unknown', right).stderr, /usage:/);
  assert.match(run(left, '--merge', '--unknown').stderr, /usage:/);
});

test('committed ledger is classified and the default CLI run is idempotent', () => {
  const path = join(root, 'packages/shared-lib/corrections.json');
  const before = readFileSync(path, 'utf8');
  assert.deepEqual(classifyLedger(JSON.parse(before)), JSON.parse(before));
  const result = runCli([], tmpdir());
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(path, 'utf8'), before);
});

test('repair command resolves Git ledger conflicts from three stages without staging other edits', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-classifier-git-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  // Exercise every generated scenario through the same command as the CLI, without
  // paying a Node startup for each marker. Keep real CLI smoke checks below.
  const run = (...args) => {
    try {
      return { status: 0, stdout: runClassifier(args), stderr: '' };
    } catch (error) {
      return { status: 1, stdout: '', stderr: `correction-classifier: ${error.message}` };
    }
  };
  // These argument and repository failures do not depend on a merge scenario.
  // Exercise them once instead of starting the same seven CLIs for every case.
  assert.match(run('--resolve-merge').stderr, /usage:/);
  assert.match(run('--resolve-merge', '--unknown').stderr, /usage:/);
  assert.match(run('--resolve-merge', directory, 'extra').stderr, /usage:/);
  assert.match(run('--check-merge').stderr, /usage:/);
  assert.match(run('--check-merge', '--unknown').stderr, /usage:/);
  assert.match(run('--check-merge', directory, 'extra').stderr, /usage:/);
  assert.equal(run('--resolve-merge', directory).status, 1, 'refuse a non-repository');
  const rows = fixture().slice(0, 4);
  rows.push({ ...rows[0], source: `${rows[0].source}#another-receipt` });
  const markerScenarios = [
    'staged-marker',
    'binary-marker',
    'textconv-marker',
    'external-marker',
    'color-marker',
    'single-marker',
  ];
  const markers = [
    '<<<<<<< HEAD',
    '||||||| base',
    '=======',
    '>>>>>>> incoming',
    '<< HEAD',
    '|| base',
    '==',
    '>> incoming',
  ];
  const scenarios = [
    'additions',
    'ours-edit',
    'theirs-edit',
    'concurrent',
    'deleted',
    'missing-guard',
    'guard-conflict',
    ...markerScenarios,
  ].map((scenario) => [scenario, false]);
  scenarios.push(
    ['additions', true],
    ['unstaged-guard', true],
    ['concurrent', true],
    ['missing-index-guard', true],
    ['symlink-index-guard', true],
    ['guard-conflict', true],
    ['unrelated-conflict', true],
    ...markerScenarios.map((scenario) => [scenario, true]),
  );
  for (const [scenario, stageMerge] of scenarios) {
    const scenarioMarkers =
      scenario === 'single-marker' ? ['< HEAD', '| base', '=', '> incoming'] : markers;
    const refused = [
      'concurrent',
      'deleted',
      'missing-guard',
      'missing-index-guard',
      'symlink-index-guard',
      'guard-conflict',
      ...markerScenarios,
    ].includes(scenario);
    const repository = join(directory, `repository with spaces ${scenario} ${stageMerge}`);
    const ledger = join(repository, 'packages/shared-lib/corrections.json');
    mkdirSync(join(repository, 'packages/shared-lib'), { recursive: true });
    const git = (...args) => {
      const result = spawnSync('git', args, {
        cwd: repository,
        encoding: 'utf8',
        timeout: 5_000,
      });
      assert.ifError(result.error);
      assert.equal(result.status, args[0] === 'merge' ? 1 : 0, result.stderr);
      return result.stdout;
    };
    const writeLedger = (receipts) =>
      writeFileSync(ledger, `${JSON.stringify(receipts, null, 2)}\n`);
    git('init', '--initial-branch=left');
    git('config', 'user.name', 'Ledger fixture');
    git('config', 'user.email', 'fixture@example.test');
    for (const { guard } of rows.filter(({ guard }) => guard)) {
      writeFileSync(join(repository, guard.path), guard.anchor);
    }
    writeLedger([rows[0]]);
    writeFileSync(join(repository, 'unrelated.txt'), 'committed\n');
    git('add', '.');
    git('commit', '-m', 'test: base ledger');
    if (scenario === 'additions' && !stageMerge) {
      assert.equal(run('--check-merge', repository).status, 1, 'a merge must be active');
      assert.equal(
        run('--resolve-merge', repository, '--stage').status,
        1,
        'staging requires an active merge',
      );
    }
    git('branch', 'right');
    const ours = ['ours-edit', 'concurrent'].includes(scenario)
      ? { ...rows[0], correction: 'Clarified evidence on the feature branch.' }
      : rows[0];
    writeLedger(scenario === 'deleted' ? [rows[1]] : [rows[1], ours]);
    if (scenario === 'guard-conflict') {
      writeFileSync(join(repository, rows[0].guard.path), `${rows[0].guard.anchor}\nleft\n`);
    }
    if (scenario === 'unrelated-conflict') {
      writeFileSync(join(repository, 'unrelated.txt'), 'left\n');
    }
    git('commit', '-am', 'test: left receipt');
    git('switch', 'right');
    const shared = ['theirs-edit', 'concurrent'].includes(scenario)
      ? { ...rows[0], correction: 'Clarified evidence on main.' }
      : rows[0];
    writeLedger(classifyLedger([...rows.slice(2), shared]));
    if (scenario === 'guard-conflict') {
      writeFileSync(join(repository, rows[0].guard.path), `${rows[0].guard.anchor}\nright\n`);
    }
    if (scenario === 'unrelated-conflict') {
      writeFileSync(join(repository, 'unrelated.txt'), 'right\n');
    }
    git('commit', '-am', 'test: right receipts');
    git('switch', 'left');
    git('merge', '--no-commit', 'right');
    const before = readFileSync(ledger, 'utf8');
    assert.match(before, /<<<<<<< HEAD/);
    if (scenario === 'additions' && !stageMerge) {
      const resolved = runCli(['--resolve-merge', repository], tmpdir());
      assert.equal(resolved.status, 0, resolved.stderr);
      // Restore the actual conflict before running the same case in-process.
      writeFileSync(ledger, before);
    }
    if (scenario === 'unrelated-conflict') {
      writeLedger(classifyLedger([...rows.slice(2), shared, rows[1]]));
      git('add', 'packages/shared-lib/corrections.json');
      const resolved = readFileSync(ledger, 'utf8');
      const index = git('ls-files', '--stage');
      const unrelated = readFileSync(join(repository, 'unrelated.txt'), 'utf8');
      assert.match(unrelated, /<<<<<<< HEAD/);
      for (const args of [
        ['--check-merge', repository],
        ['--resolve-merge', repository, '--stage'],
      ]) {
        const result = run(...args);
        assert.equal(result.status, 1, 'a staged ledger cannot hide another merge conflict');
        assert.match(result.stderr, /resolve other conflicts first: unrelated.txt/);
        assert.equal(git('ls-files', '--stage'), index);
        assert.equal(readFileSync(ledger, 'utf8'), resolved);
        assert.equal(readFileSync(join(repository, 'unrelated.txt'), 'utf8'), unrelated);
      }
      continue;
    }
    if (scenario === 'guard-conflict') {
      assert.match(readFileSync(join(repository, rows[0].guard.path), 'utf8'), /<<<<<<< HEAD/);
    }
    const stages = git('ls-files', '-u');
    assert.equal(run('--check-merge', repository).status, 1, 'the ledger must be staged');
    const parents = git('rev-parse', 'HEAD', 'MERGE_HEAD');
    const unrelated = join(repository, 'unrelated.txt');
    writeFileSync(unrelated, 'uncommitted user edit\n');
    if (['missing-guard', 'unstaged-guard'].includes(scenario)) {
      writeFileSync(join(repository, rows[0].guard.path), 'missing guard');
    }
    if (scenario === 'missing-index-guard') {
      writeFileSync(join(repository, rows[0].guard.path), 'missing guard');
      git('add', rows[0].guard.path);
      writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
    }
    if (scenario === 'symlink-index-guard') {
      // Matching blob text is not evidence when the staged guard is a symlink.
      const blob = git('rev-parse', `:0:${rows[0].guard.path}`).trim();
      git('update-index', '--cacheinfo', `120000,${blob},${rows[0].guard.path}`);
    }
    if (scenario === 'binary-marker') {
      // Binary attributes must not hide markers from either resolver mode.
      writeFileSync(join(repository, '.gitattributes'), `${rows[0].guard.path} -diff\n`);
      git('add', '.gitattributes');
    }
    if (scenario === 'textconv-marker') {
      // A diff driver must not conceal the actual staged merge contents.
      writeFileSync(join(repository, '.gitattributes'), `${rows[0].guard.path} diff=hidden\n`);
      git('config', 'diff.hidden.textconv', 'echo filtered-source');
      git('add', '.gitattributes');
    }
    if (scenario === 'external-marker') {
      // An external diff driver must not hide markers from either repair mode.
      git('config', 'diff.external', 'echo filtered-source');
    }
    if (scenario === 'color-marker') {
      // User presentation settings cannot hide conflict markers from the resolver.
      git('config', 'color.ui', 'always');
    }
    if (scenario === 'single-marker') {
      writeFileSync(
        join(repository, '.gitattributes'),
        `${rows[0].guard.path} conflict-marker-size=1\n`,
      );
      git('add', '.gitattributes');
    }
    if (markerScenarios.includes(scenario)) {
      // Every presentation variant must reject every marker in both repair modes.
      for (const marker of scenarioMarkers) {
        writeFileSync(join(repository, rows[0].guard.path), `${rows[0].guard.anchor}\n${marker}\n`);
        git('add', rows[0].guard.path);
        writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
        const index = git('ls-files', '--stage');
        const rejected = run('--resolve-merge', repository, ...(stageMerge ? ['--stage'] : []));
        assert.equal(rejected.status, 1, `${scenario} ${marker}: ${rejected.stderr}`);
        assert.match(rejected.stderr, /staged conflict markers/);
        assert.equal(git('ls-files', '--stage'), index, 'refused repair preserves the index');
        assert.equal(readFileSync(ledger, 'utf8'), before, 'refused repair preserves the ledger');
      }
    }
    const indexBefore = git('ls-files', '--stage');
    const result = run('--resolve-merge', repository, ...(stageMerge ? ['--stage'] : []));
    assert.equal(result.status, refused ? 1 : 0, `${scenario}: ${result.stderr}`);
    if (stageMerge && !refused) {
      const expected = classifyLedger([...rows.slice(2), shared, rows[1]]);
      assert.deepEqual(JSON.parse(readFileSync(ledger, 'utf8')), expected);
      assert.deepEqual(
        JSON.parse(git('show', ':0:packages/shared-lib/corrections.json')),
        expected,
      );
      assert.equal(git('ls-files', '-u'), '');
      if (scenario === 'unstaged-guard') {
        assert.equal(
          readFileSync(join(repository, rows[0].guard.path), 'utf8'),
          'missing guard',
          'staged resolution preserves unrelated working guard edits',
        );
        assert.ok(git('diff', '--name-only').split('\n').includes(rows[0].guard.path));
        writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
      }
      assert.equal(git('diff', '--name-only').trim(), 'unrelated.txt');
      assert.equal(readFileSync(unrelated, 'utf8'), 'uncommitted user edit\n');
      assert.equal(git('rev-parse', 'HEAD', 'MERGE_HEAD'), parents);
      const resolved = readFileSync(ledger, 'utf8');
      const index = git('ls-files', '--stage');
      for (const args of [
        ['--check-merge', repository],
        ['--resolve-merge', repository, '--stage'],
      ]) {
        const checked = runCli(args, tmpdir());
        assert.equal(checked.status, 0, checked.stderr);
      }
      const checked = run('--check-merge', repository);
      assert.equal(checked.status, 0, checked.stderr);
      assert.equal(
        run('--resolve-merge', repository, '--stage').status,
        0,
        'staged retry is read-only',
      );
      assert.equal(git('ls-files', '--stage'), index);
      assert.equal(readFileSync(ledger, 'utf8'), resolved);
      const edited = JSON.parse(resolved);
      edited.push({ ...rows[1], source: `${rows[1].source}#unstaged-receipt` });
      writeLedger(edited);
      const unstaged = readFileSync(ledger, 'utf8');
      for (const args of [
        ['--resolve-merge', repository, '--stage'],
        ['--check-merge', repository],
      ]) {
        const retry = run(...args);
        assert.equal(
          retry.status,
          1,
          'merge verification must not silently ignore unstaged receipts',
        );
        assert.match(retry.stderr, /staged retry refuses unstaged ledger edits/);
        assert.equal(git('ls-files', '--stage'), index, 'refused verification preserves the index');
        assert.equal(
          readFileSync(ledger, 'utf8'),
          unstaged,
          'refused verification preserves edits',
        );
      }
      writeFileSync(ledger, resolved);
      assert.equal(run('--resolve-merge', repository, '--stage').status, 0);
      const blob = git('rev-parse', `:0:${rows[0].guard.path}`).trim();
      git('update-index', '--cacheinfo', `120000,${blob},${rows[0].guard.path}`);
      const symlinkIndex = git('ls-files', '--stage');
      for (const args of [
        ['--check-merge', repository],
        ['--resolve-merge', repository, '--stage'],
      ]) {
        const rejected = run(...args);
        assert.equal(rejected.status, 1, 'a symlink blob cannot count as a staged guard');
        assert.match(rejected.stderr, /missing guard anchor/);
        assert.equal(git('ls-files', '--stage'), symlinkIndex);
        assert.equal(readFileSync(ledger, 'utf8'), resolved);
      }
      git('add', rows[0].guard.path);
      assert.equal(run('--check-merge', repository).status, 0);
      git('update-index', '--chmod=+x', rows[0].guard.path);
      assert.equal(run('--check-merge', repository).status, 0, 'executable guards remain valid');
      git('add', rows[0].guard.path);
      // A clean worktree cannot hide conflict markers already staged as resolved.
      git('config', 'color.ui', 'always');
      writeFileSync(join(repository, '.gitattributes'), `${rows[0].guard.path} -diff\n`);
      git('add', '.gitattributes');
      for (const marker of markers) {
        writeFileSync(join(repository, rows[0].guard.path), `${rows[0].guard.anchor}\n${marker}\n`);
        git('add', rows[0].guard.path);
        writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
        const staged = git('ls-files', '--stage');
        for (const args of [
          ['--check-merge', repository],
          ['--resolve-merge', repository, '--stage'],
        ]) {
          const rejected = run(...args);
          assert.equal(rejected.status, 1);
          assert.match(rejected.stderr, /staged conflict markers/);
          assert.equal(git('ls-files', '--stage'), staged);
          assert.equal(readFileSync(ledger, 'utf8'), resolved);
        }
      }
      git('add', rows[0].guard.path);
      assert.equal(run('--check-merge', repository).status, 0);
      continue;
    }
    assert.equal(git('ls-files', '-u'), stages, 'resolution does not stage files');
    if (refused) {
      assert.equal(git('ls-files', '--stage'), indexBefore, 'failed repair preserves the index');
      assert.match(
        result.stderr,
        /concurrent receipt edits|removed receipt|missing guard anchor|resolve other conflicts first|staged conflict markers/,
      );
      assert.equal(readFileSync(ledger, 'utf8'), before);
    } else {
      const expected = [...rows.slice(2), scenario === 'ours-edit' ? ours : shared, rows[1]];
      assert.deepEqual(JSON.parse(readFileSync(ledger, 'utf8')), classifyLedger(expected));
      const resolved = readFileSync(ledger, 'utf8');
      assert.equal(run('--resolve-merge', repository).status, 0);
      assert.equal(readFileSync(ledger, 'utf8'), resolved);
      git('add', 'packages/shared-lib/corrections.json');
      assert.equal(run('--resolve-merge', repository).status, 1, 'refuse an already staged ledger');
      assert.equal(readFileSync(ledger, 'utf8'), resolved);
      const index = git('ls-files', '--stage');
      const checked = run('--check-merge', repository);
      assert.equal(checked.status, 0, checked.stderr);
      assert.equal(git('ls-files', '--stage'), index, 'verification never stages files');
      assert.equal(readFileSync(ledger, 'utf8'), resolved);

      // A correct worktree cannot hide lost receipts or stale metadata in the index.
      for (const [contents, diagnostic] of [
        [JSON.stringify(classifyLedger(rows.slice(0, 2))), /removed rule/],
        [JSON.stringify(classifyLedger([rows[0], ...rows.slice(2)])), /removed rule/],
        [JSON.stringify(classifyLedger(rows.slice(0, -1))), /removed receipt/],
        [JSON.stringify(rows), /staged merge ledger must be classified/],
        ['{invalid json', /correction-classifier:/],
      ]) {
        writeFileSync(ledger, contents);
        git('add', 'packages/shared-lib/corrections.json');
        writeFileSync(ledger, resolved);
        const staged = git('show', ':0:packages/shared-lib/corrections.json');
        const refused = run('--check-merge', repository);
        assert.equal(refused.status, 1);
        assert.match(refused.stderr, diagnostic);
        assert.equal(git('show', ':0:packages/shared-lib/corrections.json'), staged);
        assert.equal(readFileSync(ledger, 'utf8'), resolved);
      }
      git('add', 'packages/shared-lib/corrections.json');
      writeFileSync(join(repository, rows[0].guard.path), 'missing guard');
      git('add', rows[0].guard.path);
      writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
      assert.match(run('--check-merge', repository).stderr, /missing guard anchor/);
      git('add', rows[0].guard.path);
      assert.equal(run('--check-merge', repository).status, 0);
    }
    assert.equal(readFileSync(unrelated, 'utf8'), 'uncommitted user edit\n');
    assert.equal(git('rev-parse', 'HEAD', 'MERGE_HEAD'), parents);
    assert.match(git('diff', '--name-only'), /unrelated.txt/);
    if (scenario === 'additions') {
      // Future main receipts may arrive at either end of the ledger.
      for (const placement of ['prepend', 'append']) {
        git('commit', '-m', 'test: resolved ledger');
        git('switch', 'right');
        const incoming = JSON.parse(readFileSync(ledger, 'utf8'));
        const nextReceipt = {
          ...rows[2],
          fingerprint: `next-main-${placement}`,
          source: `${rows[2].source}#next-main-${placement}`,
        };
        const next =
          placement === 'prepend' ? [nextReceipt, ...incoming] : [...incoming, nextReceipt];
        writeLedger(classifyLedger(next));
        git('commit', '-am', 'test: next main receipt');
        git('switch', 'left');
        const nextMerge = spawnSync('git', ['merge', '--no-commit', 'right'], {
          cwd: repository,
          encoding: 'utf8',
          timeout: 5_000,
        });
        assert.ifError(nextMerge.error);
        assert.equal(nextMerge.status, placement === 'prepend' ? 0 : 1, nextMerge.stderr);
        if (placement === 'append') {
          assert.match(readFileSync(ledger, 'utf8'), /<<<<<<< HEAD/);
          const repaired = run('--resolve-merge', repository, '--stage');
          assert.equal(repaired.status, 0, repaired.stderr);
        }
        assert.deepEqual(
          JSON.parse(readFileSync(ledger, 'utf8')),
          classifyLedger([...next, rows[1]]),
        );
        const checked = run('--check-merge', repository);
        assert.equal(checked.status, 0, checked.stderr);
        assert.equal(readFileSync(unrelated, 'utf8'), 'uncommitted user edit\n');
      }
    }
  }
});
