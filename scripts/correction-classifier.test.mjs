import assert from 'node:assert/strict';
import { execFile, execFileSync, spawnSync } from 'node:child_process';
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readlinkSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
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

test('ordinary CLI classification and file merges reject duplicate receipt identities without writes', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-classifier-duplicates-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const duplicated = join(directory, 'duplicated.json');
  const valid = join(directory, 'valid.json');
  const row = fixture()[0];
  const validBefore = JSON.stringify([row]);
  writeFileSync(valid, validBefore);
  for (const duplicate of [
    { ...row },
    { ...row, fingerprint: ` ${row.fingerprint.toUpperCase()} ` },
    { ...row, correction: 'Conflicting text under the same receipt identity.' },
  ]) {
    const before = JSON.stringify([row, duplicate]);
    writeFileSync(duplicated, before);
    for (const args of [
      [duplicated],
      [duplicated, '--merge', valid],
      [valid, '--merge', duplicated],
    ]) {
      const result = runCli(args, directory);
      assert.equal(result.status, 1, 'every input ledger must have unique receipt identities');
      assert.match(result.stderr, /duplicate receipt/);
      assert.equal(readFileSync(duplicated, 'utf8'), before);
      assert.equal(readFileSync(valid, 'utf8'), validBefore);
    }
  }
  writeFileSync(duplicated, validBefore);
  assert.equal(runCli([duplicated], directory).status, 0, 'a corrected ledger is retryable');
  assert.deepEqual(JSON.parse(readFileSync(duplicated, 'utf8')), classifyLedger([row]));
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
  rows[3].guard.path = 'coverage guard 🧪.mjs';
  rows.push({ ...rows[0], source: `${rows[0].source}#another-receipt` });
  const markerScenarios = [
    'staged-marker',
    'binary-marker',
    'nul-marker',
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
    'manual-resolution',
    'manual-missing-receipt',
    'manual-invalid',
    'cherry-pick',
    'duplicate-parent',
    'short-ledger-markers',
    'minimum-ledger-markers',
  ].map((scenario) => [scenario, false]);
  scenarios.push(
    ['additions', true],
    ['unstaged-guard', true],
    ['concurrent', true],
    ['missing-index-guard', true],
    ['missing-index-source', true],
    ['symlink-index-guard', true],
    ['symlink-index-blob', true],
    ['unstaged-symlink-guard', true],
    ['guard-conflict', true],
    ['unrelated-conflict', true],
    ...markerScenarios.map((scenario) => [scenario, true]),
    ...[
      'manual-resolution',
      'manual-missing-receipt',
      'manual-invalid',
      'cherry-pick',
      'duplicate-parent',
      'short-ledger-markers',
      'minimum-ledger-markers',
    ].map((scenario) => [scenario, true]),
  );
  const runScenario = async ([scenario, stageMerge]) => {
    const scenarioMarkers =
      scenario === 'single-marker' ? ['< HEAD', '| base', '=', '> incoming'] : markers;
    const refused = [
      'concurrent',
      'deleted',
      'missing-guard',
      'missing-index-guard',
      'missing-index-source',
      'symlink-index-guard',
      'symlink-index-blob',
      'guard-conflict',
      ...markerScenarios,
      'manual-missing-receipt',
      'manual-invalid',
      'cherry-pick',
    ].includes(scenario);
    const repository = join(directory, `repository with spaces ${scenario} ${stageMerge}`);
    const ledger = join(repository, 'packages/shared-lib/corrections.json');
    mkdirSync(join(repository, 'packages/shared-lib'), { recursive: true });
    const git = async (...args) => {
      const result = await new Promise((resolve, reject) => {
        execFile(
          'git',
          args,
          {
            cwd: repository,
            encoding: 'utf8',
            timeout: 5_000,
          },
          (error, stdout, stderr) => {
            if (error && typeof error.code !== 'number') reject(error);
            else resolve({ status: error?.code ?? 0, stdout, stderr });
          },
        );
      });
      assert.equal(
        result.status,
        ['merge', 'cherry-pick'].includes(args[0]) ? 1 : 0,
        result.stderr,
      );
      return result.stdout;
    };
    // Exercise the real CLI once per scenario; reuse its command runner for retries.
    const commands = [];
    const run = (...args) => {
      let stdout = '';
      let stderr = '';
      const status = runClassifier(
        args,
        {
          log: (message) => {
            stdout += `${message}\n`;
          },
          error: (message) => {
            stderr += `${message}\n`;
          },
        },
        (command, args, options) => {
          commands.push(args);
          return execFileSync(command, args, options);
        },
      );
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
    await git('init', '--initial-branch=left');
    await git('config', 'user.name', 'Ledger fixture');
    await git('config', 'user.email', 'fixture@example.test');
    if (['short-ledger-markers', 'minimum-ledger-markers'].includes(scenario)) {
      const markerSize = scenario === 'minimum-ledger-markers' ? 1 : 2;
      writeFileSync(
        join(repository, '.gitattributes'),
        `packages/shared-lib/corrections.json conflict-marker-size=${markerSize}\n`,
      );
    }
    for (const { guard } of rows.filter(({ guard }) => guard)) {
      writeFileSync(join(repository, guard.path), guard.anchor);
    }
    // Batch responses use byte lengths, even for Unicode paths and binary contents.
    writeFileSync(
      join(repository, rows[3].guard.path),
      `${rows[3].guard.anchor}\né中\n\0trailer\n`,
    );
    if (scenario === 'additions' && stageMerge) {
      // The real ledger's combined guard snapshots exceed execFileSync's 1 MiB default.
      writeFileSync(
        join(repository, rows[3].guard.path),
        `${rows[3].guard.anchor}\n${'é'.repeat(200_000)}`,
      );
    }
    writeLedger(scenario === 'duplicate-parent' ? [rows[0], rows[0]] : [rows[0]]);
    writeFileSync(join(repository, 'unrelated.txt'), 'committed\n');
    await git('add', '.');
    await git('commit', '-m', 'test: base ledger');
    if (scenario === 'additions' && !stageMerge) {
      assert.equal(run('--check-merge', repository).status, 1, 'a merge must be active');
      assert.equal(
        run('--resolve-merge', repository, '--stage').status,
        1,
        'staging requires an active merge',
      );
    }
    await git('branch', 'right');
    const ours = ['ours-edit', 'concurrent'].includes(scenario)
      ? { ...rows[0], correction: 'Clarified evidence on the feature branch.' }
      : rows[0];
    writeLedger(
      scenario === 'deleted'
        ? [rows[1]]
        : scenario === 'duplicate-parent'
          ? [rows[1], ours, ours]
          : [rows[1], ours],
    );
    if (scenario === 'guard-conflict') {
      writeFileSync(join(repository, rows[0].guard.path), `${rows[0].guard.anchor}\nleft\n`);
    }
    if (scenario === 'unrelated-conflict') {
      writeFileSync(join(repository, 'unrelated.txt'), 'left\n');
    }
    await git('commit', '-am', 'test: left receipt');
    await git('switch', 'right');
    const shared = ['theirs-edit', 'concurrent'].includes(scenario)
      ? { ...rows[0], correction: 'Clarified evidence on main.' }
      : rows[0];
    writeLedger(
      classifyLedger([
        ...rows.slice(2),
        shared,
        ...(scenario === 'duplicate-parent' ? [shared] : []),
      ]),
    );
    if (scenario === 'guard-conflict') {
      writeFileSync(join(repository, rows[0].guard.path), `${rows[0].guard.anchor}\nright\n`);
    }
    if (scenario === 'unrelated-conflict') {
      writeFileSync(join(repository, 'unrelated.txt'), 'right\n');
    }
    await git('commit', '-am', 'test: right receipts');
    await git('switch', 'left');
    await git(scenario === 'cherry-pick' ? 'cherry-pick' : 'merge', '--no-commit', 'right');
    let before = readFileSync(ledger, 'utf8');
    assert.match(before, /^<+ HEAD/m);
    if (scenario === 'additions' && !stageMerge) {
      const resolved = runCli(['--resolve-merge', repository], tmpdir());
      assert.equal(resolved.status, 0, resolved.stderr);
      // Restore the actual conflict before running the same case in-process.
      writeFileSync(ledger, before);
    }
    if (scenario === 'unrelated-conflict') {
      writeLedger(classifyLedger([...rows.slice(2), shared, rows[1]]));
      await git('add', 'packages/shared-lib/corrections.json');
      const resolved = readFileSync(ledger, 'utf8');
      const index = await git('ls-files', '--stage');
      const unrelated = readFileSync(join(repository, 'unrelated.txt'), 'utf8');
      assert.match(unrelated, /<<<<<<< HEAD/);
      for (const args of [
        ['--check-merge', repository],
        ['--resolve-merge', repository, '--stage'],
      ]) {
        const result = await runCLI(...args);
        assert.equal(result.status, 1, 'a staged ledger cannot hide another merge conflict');
        assert.match(result.stderr, /resolve other conflicts first: unrelated.txt/);
        assert.equal(await git('ls-files', '--stage'), index);
        assert.equal(readFileSync(ledger, 'utf8'), resolved);
        assert.equal(readFileSync(join(repository, 'unrelated.txt'), 'utf8'), unrelated);
      }
      return;
    }
    if (scenario === 'guard-conflict') {
      assert.match(readFileSync(join(repository, rows[0].guard.path), 'utf8'), /<<<<<<< HEAD/);
    }
    const stages = await git('ls-files', '-u');
    assert.equal((await run('--check-merge', repository)).status, 1, 'the ledger must be staged');
    const operationHead = scenario === 'cherry-pick' ? 'right' : 'MERGE_HEAD';
    const parents = await git('rev-parse', 'HEAD', operationHead);
    const unrelated = join(repository, 'unrelated.txt');
    writeFileSync(unrelated, 'uncommitted user edit\n');
    if (['missing-guard', 'unstaged-guard'].includes(scenario)) {
      writeFileSync(join(repository, rows[0].guard.path), 'missing guard');
    }
    if (scenario === 'missing-index-guard') {
      writeFileSync(join(repository, rows[0].guard.path), 'missing guard');
      await git('add', rows[0].guard.path);
      writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
    }
    if (scenario === 'missing-index-source') {
      await git('rm', rows[0].guard.path);
      writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
    }
    if (scenario === 'symlink-index-guard') {
      const path = join(repository, rows[0].guard.path);
      rmSync(path);
      // A symlink target can contain the anchor without supplying executable guard source.
      symlinkSync(rows[0].guard.anchor, path);
      await git('add', rows[0].guard.path);
      rmSync(path);
      writeFileSync(path, rows[0].guard.anchor);
    }
    if (scenario === 'symlink-index-blob') {
      // Matching blob text is not evidence when the staged guard is a symlink.
      const blob = (await git('rev-parse', `:0:${rows[0].guard.path}`)).trim();
      await git('update-index', '--cacheinfo', `120000,${blob},${rows[0].guard.path}`);
    }
    if (scenario === 'unstaged-symlink-guard') {
      // A staged repair must ignore the unrelated working file's type as well as its text.
      const path = join(repository, rows[0].guard.path);
      rmSync(path);
      symlinkSync('unrelated.txt', path);
    }
    if (scenario === 'binary-marker') {
      // Binary attributes must not hide markers from either resolver mode.
      writeFileSync(join(repository, '.gitattributes'), `${rows[0].guard.path} -diff\n`);
      await git('add', '.gitattributes');
    }
    if (scenario === 'textconv-marker') {
      // A diff driver must not conceal the actual staged merge contents.
      writeFileSync(join(repository, '.gitattributes'), `${rows[0].guard.path} diff=hidden\n`);
      await git('config', 'diff.hidden.textconv', 'echo filtered-source');
      await git('add', '.gitattributes');
    }
    if (scenario === 'external-marker') {
      // An external diff driver must not hide markers from either repair mode.
      await git('config', 'diff.external', 'echo filtered-source');
    }
    if (scenario === 'color-marker') {
      // User presentation settings cannot hide conflict markers from the resolver.
      await git('config', 'color.ui', 'always');
    }
    if (scenario === 'single-marker') {
      writeFileSync(
        join(repository, '.gitattributes'),
        `${rows[0].guard.path} conflict-marker-size=1\n`,
      );
      await git('add', '.gitattributes');
    }
    if (markerScenarios.includes(scenario)) {
      // Every presentation variant must reject every marker in both repair modes.
      for (const marker of scenarioMarkers) {
        const prefix = scenario === 'nul-marker' ? '\0' : '';
        writeFileSync(
          join(repository, rows[0].guard.path),
          `${prefix}${rows[0].guard.anchor}\n${marker}\n`,
        );
        await git('add', rows[0].guard.path);
        writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
        const index = await git('ls-files', '--stage');
        const rejected = run('--resolve-merge', repository, ...(stageMerge ? ['--stage'] : []));
        assert.equal(rejected.status, 1, `${scenario} ${marker}: ${rejected.stderr}`);
        assert.match(rejected.stderr, /staged conflict markers/);
        assert.equal(await git('ls-files', '--stage'), index, 'refused repair preserves the index');
        assert.equal(readFileSync(ledger, 'utf8'), before, 'refused repair preserves the ledger');
      }
    }
    const manualReceipt = { ...rows[1], source: `${rows[1].source}#manual-resolution` };
    const expectedRows = [...rows.slice(2), scenario === 'ours-edit' ? ours : shared, rows[1]];
    if (scenario === 'manual-resolution') {
      expectedRows.push(manualReceipt);
      const index = await git('ls-files', '--stage');
      for (const receipts of [expectedRows, classifyLedger(expectedRows)]) {
        writeLedger(receipts);
        const manual = readFileSync(ledger, 'utf8');
        const refused = await runCLI(
          '--resolve-merge',
          repository,
          ...(stageMerge ? ['--stage'] : []),
        );
        assert.equal(refused.status, 1, 'manual receipts require explicit staging');
        assert.match(refused.stderr, /manually resolved ledger/);
        assert.equal(readFileSync(ledger, 'utf8'), manual, 'manual receipts remain untouched');
        assert.equal(await git('ls-files', '--stage'), index);
      }
      await git('add', 'packages/shared-lib/corrections.json');
      const staged = await git('ls-files', '--stage');
      for (const args of [
        ['--resolve-merge', repository],
        ['--resolve-merge', repository, '--stage'],
        ['--check-merge', repository],
      ]) {
        const verified = run(...args);
        assert.equal(verified.status, 0, verified.stderr);
        assert.deepEqual(JSON.parse(readFileSync(ledger, 'utf8')), classifyLedger(expectedRows));
        assert.equal(await git('ls-files', '--stage'), staged);
        assert.equal(readFileSync(unrelated, 'utf8'), 'uncommitted user edit\n');
        assert.equal(await git('rev-parse', 'HEAD', 'MERGE_HEAD'), parents);
      }
      return;
    }
    if (scenario === 'manual-missing-receipt') writeLedger(rows.slice(0, -1));
    if (scenario === 'manual-invalid') writeFileSync(ledger, '{invalid json');
    before = readFileSync(ledger, 'utf8');
    const indexBefore = await git('ls-files', '--stage');
    if (scenario === 'additions' && stageMerge) {
      // A failed Git staging write must leave the conflict intact for a safe retry.
      const lock = join(repository, (await git('rev-parse', '--git-path', 'index.lock')).trim());
      writeFileSync(lock, 'another Git writer\n');
      try {
        for (const attempt of [run, runCLI]) {
          const failed = await attempt('--resolve-merge', repository, '--stage');
          assert.equal(failed.status, 1, 'a locked index must refuse staging');
          assert.match(failed.stderr, /index\.lock/);
          assert.equal(await git('ls-files', '--stage'), indexBefore);
          assert.equal(
            readFileSync(ledger, 'utf8'),
            before,
            'failed staging restores ledger bytes',
          );
        }
      } finally {
        rmSync(lock);
      }
    }
    const result = await runCLI('--resolve-merge', repository, ...(stageMerge ? ['--stage'] : []));
    assert.equal(result.status, refused ? 1 : 0, `${scenario}: ${result.stderr}`);
    if (stageMerge && !refused) {
      const expected = classifyLedger(expectedRows);
      assert.deepEqual(JSON.parse(readFileSync(ledger, 'utf8')), expected);
      assert.deepEqual(
        JSON.parse(await git('show', ':0:packages/shared-lib/corrections.json')),
        expected,
      );
      assert.equal(await git('ls-files', '-u'), '');
      if (scenario === 'unstaged-symlink-guard') {
        const path = join(repository, rows[0].guard.path);
        assert.equal(readlinkSync(path), 'unrelated.txt', 'repair preserves the working symlink');
        rmSync(path);
        writeFileSync(path, rows[0].guard.anchor);
      }
      if (scenario === 'unstaged-guard') {
        assert.equal(
          readFileSync(join(repository, rows[0].guard.path), 'utf8'),
          'missing guard',
          'staged resolution preserves unrelated working guard edits',
        );
        assert.ok((await git('diff', '--name-only')).split('\n').includes(rows[0].guard.path));
        writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
      }
      assert.equal((await git('diff', '--name-only')).trim(), 'unrelated.txt');
      assert.equal(readFileSync(unrelated, 'utf8'), 'uncommitted user edit\n');
      assert.equal(await git('rev-parse', 'HEAD', 'MERGE_HEAD'), parents);
      const resolved = readFileSync(ledger, 'utf8');
      const index = await git('ls-files', '--stage');
      if (scenario === 'additions') {
        const path = join(repository, rows[0].guard.path);
        rmSync(path);
        symlinkSync(rows[0].guard.anchor, path);
        await git('add', rows[0].guard.path);
        rmSync(path);
        writeFileSync(path, rows[0].guard.anchor);
        const symlinkIndex = await git('ls-files', '--stage');
        for (const args of [
          ['--check-merge', repository],
          ['--resolve-merge', repository],
          ['--resolve-merge', repository, '--stage'],
        ]) {
          const rejected = run(...args);
          assert.equal(rejected.status, 1, 'a symlink cannot establish staged guard coverage');
          assert.match(rejected.stderr, /missing guard anchor/);
          assert.equal(await git('ls-files', '--stage'), symlinkIndex);
          assert.equal(readFileSync(ledger, 'utf8'), resolved);
          assert.equal(readFileSync(path, 'utf8'), rows[0].guard.anchor);
        }
        await git('add', rows[0].guard.path);
        assert.equal(run('--check-merge', repository).status, 0);
        assert.equal(await git('ls-files', '--stage'), index);
        for (const args of [
          ['--check-merge', repository],
          ['--resolve-merge', repository, '--stage'],
        ]) {
          const checked = await runCLI(...args);
          assert.equal(checked.status, 0, checked.stderr);
        }
      }
      const checked = await run('--check-merge', repository);
      assert.equal(checked.status, 0, checked.stderr);
      if (scenario === 'additions') {
        const commands = [];
        const status = runClassifier(
          ['--check-merge', repository],
          {
            log() {},
            error: (message) => assert.fail(message),
          },
          (command, args, options) => {
            commands.push(args);
            return execFileSync(command, args, options);
          },
        );
        assert.equal(status, 0);
        assert.equal(
          commands.filter((args) => args.includes('rev-parse')).length,
          1,
          'resolve the repository and both merge parents in one Git call',
        );
        assert.equal(
          commands.filter((args) => args.includes('ls-files')).length,
          1,
          'read index stages and regular-file modes once per verification',
        );
        assert.equal(
          commands.filter((args) => args.includes('cat-file')).length,
          2,
          'batch the ledgers, then all staged and immutable parent guards',
        );
        assert.equal(commands.length, 4, 'verification must retain a fixed Git process budget');
        assert.equal(
          commands.filter((args) => args.includes('show')).length,
          0,
          'verification must not start Git once per ledger',
        );
        assert.equal(
          commands.filter(
            (args) =>
              args.includes('show') &&
              rows.some(({ guard }) => args.at(-1).endsWith(`:${guard.path}`)),
          ).length,
          0,
          'verification must not start Git once per guard',
        );
      }
      assert.equal(
        (await run('--resolve-merge', repository, '--stage')).status,
        0,
        'staged retry is read-only',
      );
      assert.equal(await git('ls-files', '--stage'), index);
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
        assert.equal(
          await git('ls-files', '--stage'),
          index,
          'refused verification preserves the index',
        );
        assert.equal(
          readFileSync(ledger, 'utf8'),
          unstaged,
          'refused verification preserves edits',
        );
      }
      writeFileSync(ledger, resolved);
      assert.equal((await run('--resolve-merge', repository, '--stage')).status, 0);
      const blob = (await git('rev-parse', `:0:${rows[0].guard.path}`)).trim();
      await git('update-index', '--cacheinfo', `120000,${blob},${rows[0].guard.path}`);
      const symlinkIndex = await git('ls-files', '--stage');
      for (const args of [
        ['--check-merge', repository],
        ['--resolve-merge', repository, '--stage'],
      ]) {
        const rejected = run(...args);
        assert.equal(rejected.status, 1, 'a symlink blob cannot count as a staged guard');
        assert.match(rejected.stderr, /missing guard anchor/);
        assert.equal(await git('ls-files', '--stage'), symlinkIndex);
        assert.equal(readFileSync(ledger, 'utf8'), resolved);
      }
      await git('add', rows[0].guard.path);
      assert.equal(run('--check-merge', repository).status, 0);
      await git('update-index', '--chmod=+x', rows[0].guard.path);
      assert.equal(run('--check-merge', repository).status, 0, 'executable guards remain valid');
      await git('add', rows[0].guard.path);
      if (scenario === 'additions') {
        // Removing a guard between retries must fail on the index, even with a valid working file.
        await git('update-index', '--force-remove', '--', rows[0].guard.path);
        const missingIndex = await git('ls-files', '--stage');
        for (const args of [
          ['--check-merge', repository],
          ['--resolve-merge', repository],
          ['--resolve-merge', repository, '--stage'],
        ]) {
          const rejected = run(...args);
          assert.equal(rejected.status, 1, 'a working file cannot replace a missing indexed guard');
          assert.match(rejected.stderr, /missing guard anchor/);
          assert.equal(await git('ls-files', '--stage'), missingIndex);
          assert.equal(readFileSync(ledger, 'utf8'), resolved);
          assert.equal(
            readFileSync(join(repository, rows[0].guard.path), 'utf8'),
            rows[0].guard.anchor,
          );
        }
        await git('add', rows[0].guard.path);
        assert.equal(run('--check-merge', repository).status, 0);
      }
      const ledgerPath = 'packages/shared-lib/corrections.json';
      const ledgerBlob = (await git('rev-parse', `:0:${ledgerPath}`)).trim();
      await git('update-index', '--cacheinfo', `120000,${ledgerBlob},${ledgerPath}`);
      const symlinkLedgerIndex = await git('ls-files', '--stage');
      for (const args of [
        ['--check-merge', repository],
        ['--resolve-merge', repository],
        ['--resolve-merge', repository, '--stage'],
      ]) {
        const rejected = run(...args);
        assert.equal(rejected.status, 1, 'a staged ledger must be a regular file');
        assert.match(rejected.stderr, /staged source must be a regular file/);
        assert.equal(await git('ls-files', '--stage'), symlinkLedgerIndex);
        assert.equal(readFileSync(ledger, 'utf8'), resolved);
      }
      await git('add', ledgerPath);
      assert.equal(run('--check-merge', repository).status, 0);
      if (scenario === 'additions') {
        await git('update-index', '--chmod=+x', ledgerPath);
        assert.equal(
          run('--resolve-merge', repository).status,
          0,
          'executable ledgers remain valid',
        );
        await git('add', ledgerPath);
      }
      // A clean worktree cannot hide conflict markers already staged as resolved.
      await git('config', 'color.ui', 'always');
      await git('config', 'diff.conceal.textconv', 'echo hidden-by-textconv');
      for (const [attribute, marker] of [
        ...scenarioMarkers.map((marker) => ['-diff', marker]),
        ['', '<<<<<<< HEAD'],
        ['', '||||||| base'],
        ['', '======='],
        ...['<<<<<<<', '|||||||', '=======', '>>>>>>>'].map((marker) => ['', `${marker}\r`]),
        ['-diff', `${'='.repeat(12)}\r`],
        ['', '>>>>>>> incoming'],
        ['-diff', '<<<<<<< HEAD'],
        ['diff=conceal', '<<<<<<< HEAD'],
        ['conflict-marker-size=1', '< HEAD'],
        ['conflict-marker-size=3', '||| base'],
        ['conflict-marker-size=3', '==='],
        ['conflict-marker-size=6', '>>>>>> incoming'],
      ]) {
        writeFileSync(join(repository, '.gitattributes'), `${rows[0].guard.path} ${attribute}\n`);
        await git('add', '.gitattributes');
        writeFileSync(join(repository, rows[0].guard.path), `${rows[0].guard.anchor}\n${marker}\n`);
        await git('add', rows[0].guard.path);
        writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
        const staged = await git('ls-files', '--stage');
        for (const args of [
          ['--check-merge', repository],
          ['--resolve-merge', repository, '--stage'],
        ]) {
          const rejected = await run(...args);
          assert.equal(rejected.status, 1);
          assert.match(rejected.stderr, /staged conflict markers/);
          assert.equal(await git('ls-files', '--stage'), staged);
          assert.equal(readFileSync(ledger, 'utf8'), resolved);
        }
      }
      await git('add', rows[0].guard.path);
      assert.equal(run('--check-merge', repository).status, 0);
      writeFileSync(
        join(repository, rows[0].guard.path),
        `${rows[0].guard.anchor}\nvalid source with trailing whitespace  \n`,
      );
      await git('add', rows[0].guard.path);
      assert.equal(
        run('--check-merge', repository).status,
        0,
        'marker checks do not add a whitespace policy',
      );
      return;
    }
    assert.equal(await git('ls-files', '-u'), stages, 'resolution does not stage files');
    if (refused) {
      assert.equal(
        await git('ls-files', '--stage'),
        indexBefore,
        'failed repair preserves the index',
      );
      assert.match(
        result.stderr,
        /concurrent receipt edits|removed receipt|missing guard anchor|resolve other conflicts first|staged conflict markers|Expected property name|MERGE_HEAD|manually resolved ledger/,
      );
      assert.equal(readFileSync(ledger, 'utf8'), before);
      if (scenario === 'binary-marker') {
        await git('add', rows[0].guard.path);
        const repaired = run('--resolve-merge', repository, '--stage');
        assert.equal(repaired.status, 0, repaired.stderr);
        assert.deepEqual(
          JSON.parse(await git('show', ':0:packages/shared-lib/corrections.json')),
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
      await git('add', 'packages/shared-lib/corrections.json');
      assert.equal(
        (await run('--resolve-merge', repository)).status,
        0,
        'retry verifies a ledger staged separately after resolution',
      );
      assert.equal(readFileSync(ledger, 'utf8'), resolved);
      const index = await git('ls-files', '--stage');
      const checked = await run('--check-merge', repository);
      assert.equal(checked.status, 0, checked.stderr);
      assert.equal(await git('ls-files', '--stage'), index, 'verification never stages files');
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
        assert.equal(await git('ls-files', '--stage'), index, 'retry never restages files');
        assert.equal(readFileSync(ledger, 'utf8'), `${resolved}\n`, 'retry preserves local edits');
      }
      writeFileSync(ledger, resolved);

      // A correct worktree cannot hide lost receipts or stale metadata in the index.
      for (const [contents, diagnostic] of [
        [JSON.stringify(classifyLedger(rows.slice(0, 2))), /removed rule/],
        [JSON.stringify(classifyLedger([rows[0], ...rows.slice(2)])), /removed rule/],
        [JSON.stringify(classifyLedger(rows.slice(0, -1))), /removed receipt/],
        [JSON.stringify(rows), /staged merge ledger must be classified/],
        [JSON.stringify(classifyLedger([...rows, rows[0]])), /duplicate receipt/],
        ['{invalid json', /correction-classifier:/],
      ]) {
        writeFileSync(ledger, contents);
        await git('add', 'packages/shared-lib/corrections.json');
        writeFileSync(ledger, resolved);
        const staged = await git('show', ':0:packages/shared-lib/corrections.json');
        for (const args of [
          ['--check-merge', repository],
          ['--resolve-merge', repository],
          ['--resolve-merge', repository, '--stage'],
        ]) {
          const refused = await run(...args);
          assert.equal(refused.status, 1);
          assert.match(refused.stderr, diagnostic);
          assert.equal(await git('show', ':0:packages/shared-lib/corrections.json'), staged);
          assert.equal(readFileSync(ledger, 'utf8'), resolved);
        }
      }
      await git('add', 'packages/shared-lib/corrections.json');
      writeFileSync(join(repository, rows[0].guard.path), 'missing guard');
      await git('add', rows[0].guard.path);
      writeFileSync(join(repository, rows[0].guard.path), rows[0].guard.anchor);
      assert.match((await run('--check-merge', repository)).stderr, /missing guard anchor/);
      await git('add', rows[0].guard.path);
      assert.equal((await run('--check-merge', repository)).status, 0);
    }
    assert.equal(readFileSync(unrelated, 'utf8'), 'uncommitted user edit\n');
    assert.equal(await git('rev-parse', 'HEAD', operationHead), parents);
    assert.match(await git('diff', '--name-only'), /unrelated.txt/);
    if (scenario === 'additions') {
      // Future main receipts may arrive at either end of the ledger.
      for (const placement of ['prepend', 'append']) {
        await git('commit', '-m', 'test: resolved ledger');
        await git('switch', 'right');
        const incoming = JSON.parse(readFileSync(ledger, 'utf8'));
        const nextReceipt = {
          ...rows[2],
          fingerprint: `next-main-${placement}`,
          source: `${rows[2].source}#next-main-${placement}`,
        };
        const next =
          placement === 'prepend' ? [nextReceipt, ...incoming] : [...incoming, nextReceipt];
        writeLedger(classifyLedger(next));
        await git('commit', '-am', 'test: next main receipt');
        await git('switch', 'left');
        const nextMerge = spawnSync('git', ['merge', '--no-commit', 'right'], {
          cwd: repository,
          encoding: 'utf8',
          timeout: 5_000,
        });
        assert.ifError(nextMerge.error);
        assert.equal(nextMerge.status, placement === 'prepend' ? 0 : 1, nextMerge.stderr);
        if (placement === 'append') {
          assert.match(readFileSync(ledger, 'utf8'), /<<<<<<< HEAD/);
          commands.length = 0;
          const repaired = run('--resolve-merge', repository, '--stage');
          assert.equal(repaired.status, 0, repaired.stderr);
          assert.equal(
            commands.filter(
              (args) =>
                args.includes('show') &&
                rows.some(({ guard }) => args.at(-1).endsWith(`:${guard.path}`)),
            ).length,
            0,
            'staged conflict resolution must batch guard reads, including repeated receipts',
          );
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
  };
  // Each scenario owns a separate repository; overlap real Git and CLI I/O within the deadline.
  await Promise.all(
    scenarios.map((args) => t.test(`${args[0]} (stage=${args[1]})`, () => runScenario(args))),
  );
});
