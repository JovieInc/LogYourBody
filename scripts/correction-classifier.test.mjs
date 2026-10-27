import assert from 'node:assert/strict';
import { execFile, spawnSync } from 'node:child_process';
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

test('command runner returns status without leaking failure into the next invocation', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-classifier-command-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const ledger = join(directory, 'ledger.json');
  const messages = [];
  const logger = {
    log: (message) => messages.push(message),
    error: (message) => messages.push(message),
  };
  const exitCode = process.exitCode;
  writeFileSync(ledger, '{invalid json');
  assert.equal(runClassifier([ledger], logger), 1);
  assert.match(messages.pop(), /correction-classifier:/);
  assert.equal(readFileSync(ledger, 'utf8'), '{invalid json');
  writeFileSync(ledger, JSON.stringify(fixture()));
  assert.equal(runClassifier([ledger], logger), 0);
  assert.match(messages.pop(), /classified 6 receipts/);
  assert.deepEqual(JSON.parse(readFileSync(ledger, 'utf8')), classifyLedger(fixture()));
  assert.equal(process.exitCode, exitCode);
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

test('CLI resolves Git ledger conflicts', { concurrency: 2 }, async (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-classifier-git-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const run = (...args) => runCli(args, tmpdir());
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
  const scenarios = [
    'additions',
    'ours-edit',
    'theirs-edit',
    'concurrent',
    'deleted',
    'missing-guard',
    'guard-conflict',
    'staged-marker',
    'manual-resolution',
    'manual-missing-receipt',
    'manual-invalid',
    'textconv-marker',
    'color-marker',
    'binary-marker',
    'duplicate-parent',
  ].map((scenario) => [scenario, false]);
  scenarios.push(
    ['additions', true],
    ['concurrent', true],
    ['missing-index-guard', true],
    ['guard-conflict', true],
    ['unrelated-conflict', true],
    ['staged-marker', true],
    ['manual-resolution', true],
    ['manual-missing-receipt', true],
    ['manual-invalid', true],
    ['textconv-marker', true],
    ['color-marker', true],
    ['binary-marker', true],
    ['duplicate-parent', true],
  );
  const runScenario = async ([scenario, stageMerge]) => {
    const refused = [
      'concurrent',
      'deleted',
      'missing-guard',
      'missing-index-guard',
      'guard-conflict',
      'staged-marker',
      'manual-missing-receipt',
      'manual-invalid',
      'textconv-marker',
      'color-marker',
      'binary-marker',
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
    // Exercise the real CLI once per scenario; reuse its command runner for retries.
    const run = (...args) => {
      let stdout = '';
      let stderr = '';
      const status = runClassifier(args, {
        log: (message) => {
          stdout += `${message}\n`;
        },
        error: (message) => {
          stderr += `${message}\n`;
        },
      });
      return { status, stdout, stderr };
    };
    const runCLI = (...args) =>
      new Promise((resolve) => {
        execFile(
          process.execPath,
          [script, ...args],
          { cwd: tmpdir(), encoding: 'utf8', timeout: 5_000 },
          (error, stdout, stderr) => {
            resolve({ status: error ? error.code : 0, stdout, stderr });
          },
        );
      });
    const writeLedger = (receipts) =>
      writeFileSync(ledger, `${JSON.stringify(receipts, null, 2)}\n`);
    git('init', '--initial-branch=left');
    git('config', 'user.name', 'Ledger fixture');
    git('config', 'user.email', 'fixture@example.test');
    for (const { guard } of rows.filter(({ guard }) => guard)) {
      writeFileSync(join(repository, guard.path), guard.anchor);
    }
    writeLedger(scenario === 'duplicate-parent' ? [rows[0], rows[0]] : [rows[0]]);
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
    writeLedger(
      scenario === 'deleted' ? [rows[1]] :
        scenario === 'duplicate-parent' ? [rows[1], ours, ours] : [rows[1], ours],
    );
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
    writeLedger(classifyLedger([
      ...rows.slice(2), shared, ...(scenario === 'duplicate-parent' ? [shared] : []),
    ]));
    if (scenario === 'guard-conflict') {
      writeFileSync(join(repository, rows[0].guard.path), `${rows[0].guard.anchor}\nright\n`);
    }
    if (scenario === 'unrelated-conflict') {
      writeFileSync(join(repository, 'unrelated.txt'), 'right\n');
    }
    git('commit', '-am', 'test: right receipts');
    git('switch', 'left');
    git('merge', '--no-commit', 'right');
    let before = readFileSync(ledger, 'utf8');
    assert.match(before, /<<<<<<< HEAD/);
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
        const result = await runCLI(...args);
        assert.equal(result.status, 1, 'a staged ledger cannot hide another merge conflict');
        assert.match(result.stderr, /resolve other conflicts first: unrelated.txt/);
        assert.equal(git('ls-files', '--stage'), index);
        assert.equal(readFileSync(ledger, 'utf8'), resolved);
        assert.equal(readFileSync(join(repository, 'unrelated.txt'), 'utf8'), unrelated);
      }
      return;
    }
    if (scenario === 'guard-conflict') {
      assert.match(readFileSync(join(repository, rows[0].guard.path), 'utf8'), /<<<<<<< HEAD/);
    }
    const stages = git('ls-files', '-u');
    assert.equal((await run('--check-merge', repository)).status, 1, 'the ledger must be staged');
    const parents = git('rev-parse', 'HEAD', 'MERGE_HEAD');
    const unrelated = join(repository, 'unrelated.txt');
    writeFileSync(unrelated, 'uncommitted user edit\n');
    if (scenario === 'missing-guard') {
      writeFileSync(join(repository, rows[0].guard.path), 'missing guard');
    }
    if (scenario === 'missing-index-guard') {
      writeFileSync(join(repository, rows[0].guard.path), 'missing guard');
      git('add', rows[0].guard.path);
      writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
    }
    if (scenario === 'textconv-marker') {
      // A diff driver must not conceal the actual staged merge contents.
      writeFileSync(join(repository, '.gitattributes'), `${rows[0].guard.path} diff=hidden\n`);
      git('config', 'diff.hidden.textconv', 'echo filtered-source');
      git('add', '.gitattributes');
    }
    if (scenario === 'color-marker') {
      // User presentation settings cannot hide conflict markers from the resolver.
      git('config', 'color.ui', 'always');
    }
    if (scenario === 'binary-marker') {
      // Binary attributes must not hide unresolved source in the staged diff.
      writeFileSync(join(repository, '.gitattributes'), `${rows[0].guard.path} binary\n`);
      git('add', '.gitattributes');
    }
    if (['staged-marker', 'textconv-marker', 'color-marker', 'binary-marker'].includes(scenario)) {
      writeFileSync(
        join(repository, rows[0].guard.path),
        `${rows[0].guard.anchor}\n<<<<<<< HEAD\n`,
      );
      git('add', rows[0].guard.path);
      writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
    }
    const manualReceipt = { ...rows[1], source: `${rows[1].source}#manual-resolution` };
    const expectedRows = [...rows.slice(2), scenario === 'ours-edit' ? ours : shared, rows[1]];
    if (scenario === 'manual-resolution') {
      expectedRows.push(manualReceipt);
      writeLedger(expectedRows);
    }
    if (scenario === 'manual-missing-receipt') writeLedger(rows.slice(0, -1));
    if (scenario === 'manual-invalid') writeFileSync(ledger, '{invalid json');
    before = readFileSync(ledger, 'utf8');
    const indexBefore = git('ls-files', '--stage');
    const result = await runCLI('--resolve-merge', repository, ...(stageMerge ? ['--stage'] : []));
    assert.equal(result.status, refused ? 1 : 0, `${scenario}: ${result.stderr}`);
    if (stageMerge && !refused) {
      const expected = classifyLedger(expectedRows);
      assert.deepEqual(JSON.parse(readFileSync(ledger, 'utf8')), expected);
      assert.deepEqual(
        JSON.parse(git('show', ':0:packages/shared-lib/corrections.json')),
        expected,
      );
      assert.equal(git('ls-files', '-u'), '');
      assert.equal(git('diff', '--name-only').trim(), 'unrelated.txt');
      assert.equal(readFileSync(unrelated, 'utf8'), 'uncommitted user edit\n');
      assert.equal(git('rev-parse', 'HEAD', 'MERGE_HEAD'), parents);
      const resolved = readFileSync(ledger, 'utf8');
      const index = git('ls-files', '--stage');
      const checked = await run('--check-merge', repository);
      assert.equal(checked.status, 0, checked.stderr);
      assert.equal(
        (await run('--resolve-merge', repository, '--stage')).status,
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
        ['--resolve-merge', repository],
        ['--resolve-merge', repository, '--stage'],
        ['--check-merge', repository],
      ]) {
        const retry = await run(...args);
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
      assert.equal((await run('--resolve-merge', repository, '--stage')).status, 0);
      // A clean worktree cannot hide conflict markers already staged as resolved.
      git('config', 'color.ui', 'always');
      for (const marker of ['<<<<<<< HEAD', '||||||| base', '=======', '>>>>>>> incoming']) {
        writeFileSync(join(repository, rows[0].guard.path), `${rows[0].guard.anchor}\n${marker}\n`);
        git('add', rows[0].guard.path);
        writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
        const staged = git('ls-files', '--stage');
        for (const args of [
          ['--check-merge', repository],
          ['--resolve-merge', repository, '--stage'],
        ]) {
          const rejected = await run(...args);
          assert.equal(rejected.status, 1);
          assert.match(rejected.stderr, /staged conflict markers/);
          assert.equal(git('ls-files', '--stage'), staged);
          assert.equal(readFileSync(ledger, 'utf8'), resolved);
        }
      }
      git('add', rows[0].guard.path);
      assert.equal((await run('--check-merge', repository)).status, 0);
      return;
    }
    assert.equal(git('ls-files', '-u'), stages, 'resolution does not stage files');
    if (refused) {
      assert.equal(git('ls-files', '--stage'), indexBefore, 'failed repair preserves the index');
      assert.match(
        result.stderr,
        /concurrent receipt edits|removed receipt|missing guard anchor|resolve other conflicts first|staged conflict markers|Expected property name/,
      );
      assert.equal(readFileSync(ledger, 'utf8'), before);
      if (scenario === 'binary-marker') {
        git('add', rows[0].guard.path);
        const repaired = run('--resolve-merge', repository, '--stage');
        assert.equal(repaired.status, 0, repaired.stderr);
        assert.deepEqual(
          JSON.parse(git('show', ':0:packages/shared-lib/corrections.json')),
          classifyLedger(expectedRows),
        );
        assert.equal(
          run('--check-merge', repository).status,
          0,
          'binary attributes alone must not reject resolved source',
        );
      }
    } else {
      assert.deepEqual(JSON.parse(readFileSync(ledger, 'utf8')), classifyLedger(expectedRows));
      const resolved = readFileSync(ledger, 'utf8');
      assert.equal((await run('--resolve-merge', repository)).status, 0);
      assert.equal(readFileSync(ledger, 'utf8'), resolved);
      git('add', 'packages/shared-lib/corrections.json');
      assert.equal(
        (await run('--resolve-merge', repository)).status,
        0,
        'retry verifies a ledger staged separately after resolution',
      );
      assert.equal(readFileSync(ledger, 'utf8'), resolved);
      const index = git('ls-files', '--stage');
      const checked = await run('--check-merge', repository);
      assert.equal(checked.status, 0, checked.stderr);
      assert.equal(git('ls-files', '--stage'), index, 'verification never stages files');
      assert.equal(readFileSync(ledger, 'utf8'), resolved);

      writeFileSync(ledger, `${resolved}\n`);
      for (const args of [
        ['--resolve-merge', repository],
        ['--resolve-merge', repository, '--stage'],
        ['--check-merge', repository],
      ]) {
        const retry = await run(...args);
        assert.equal(retry.status, 1, 'retry must refuse even whitespace edits without staging');
        assert.match(retry.stderr, /staged retry refuses unstaged ledger edits/);
        assert.equal(git('ls-files', '--stage'), index, 'retry never restages files');
        assert.equal(readFileSync(ledger, 'utf8'), `${resolved}\n`, 'retry preserves local edits');
      }
      writeFileSync(ledger, resolved);

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
        for (const args of [
          ['--check-merge', repository],
          ['--resolve-merge', repository],
          ['--resolve-merge', repository, '--stage'],
        ]) {
          const refused = await run(...args);
          assert.equal(refused.status, 1);
          assert.match(refused.stderr, diagnostic);
          assert.equal(git('show', ':0:packages/shared-lib/corrections.json'), staged);
          assert.equal(readFileSync(ledger, 'utf8'), resolved);
        }
      }
      git('add', 'packages/shared-lib/corrections.json');
      writeFileSync(join(repository, rows[0].guard.path), 'missing guard');
      git('add', rows[0].guard.path);
      writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
      assert.match((await run('--check-merge', repository)).stderr, /missing guard anchor/);
      git('add', rows[0].guard.path);
      assert.equal((await run('--check-merge', repository)).status, 0);
    }
    assert.equal(readFileSync(unrelated, 'utf8'), 'uncommitted user edit\n');
    assert.equal(git('rev-parse', 'HEAD', 'MERGE_HEAD'), parents);
    assert.match(git('diff', '--name-only'), /unrelated.txt/);
    if (scenario === 'additions') {
      git('commit', '-m', 'test: resolved ledger');
      git('switch', 'right');
      const nextReceipt = {
        ...rows[2],
        fingerprint: 'next-main-receipt',
        source: `${rows[2].source}#next-main`,
      };
      writeLedger(classifyLedger([nextReceipt, ...rows.slice(2), shared]));
      git('commit', '-am', 'test: next main receipt');
      git('switch', 'left');
      const nextMerge = spawnSync('git', ['merge', '--no-commit', 'right'], {
        cwd: repository,
        encoding: 'utf8',
        timeout: 5_000,
      });
      assert.ifError(nextMerge.error);
      assert.equal(
        nextMerge.status,
        0,
        `next main prepend must merge cleanly: ${nextMerge.stderr}`,
      );
      assert.deepEqual(
        JSON.parse(readFileSync(ledger, 'utf8')),
        classifyLedger([nextReceipt, ...rows.slice(2), shared, rows[1]]),
      );
      const checked = await run('--check-merge', repository);
      assert.equal(checked.status, 0, checked.stderr);
      assert.equal(readFileSync(unrelated, 'utf8'), 'uncommitted user edit\n');
    }
  };
  // Each scenario owns a separate repository; overlap CLI waits within the existing deadline.
  await Promise.all(
    scenarios.map((args) => t.test(`${args[0]} (stage=${args[1]})`, () => runScenario(args))),
  );
});
