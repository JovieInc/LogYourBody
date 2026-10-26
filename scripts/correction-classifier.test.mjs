import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { classifyLedger } from './correction-classifier.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const script = fileURLToPath(new URL('./correction-classifier.mjs', import.meta.url));
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
  const run = (...args) =>
    spawnSync(process.execPath, [script, ...args], { cwd: directory, encoding: 'utf8' });
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

test('committed ledger is classified and the default CLI run is idempotent', () => {
  const path = join(root, 'packages/shared-lib/corrections.json');
  const before = readFileSync(path, 'utf8');
  assert.deepEqual(classifyLedger(JSON.parse(before)), JSON.parse(before));
  const result = spawnSync(process.execPath, [script], { cwd: tmpdir(), encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(path, 'utf8'), before);
});

test('merge CLI retains both immutable parents, classifies shared receipts and refuses conflicting evidence', (t) => {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-classifier-merge-'));
  t.after(() => rmSync(directory, { recursive: true, force: true }));
  const git = (...args) => execFileSync('git', args, { cwd: directory, encoding: 'utf8' }).trim();
  const ledger = join(directory, 'packages/shared-lib/corrections.json');
  mkdirSync(join(directory, 'packages/shared-lib'), { recursive: true });
  git('init', '-q');
  const save = (rows) => {
    writeFileSync(ledger, JSON.stringify(rows));
    git('add', '.');
    git(
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.com',
      'commit',
      '-qm',
      'fixture',
    );
    return git('rev-parse', 'HEAD');
  };
  const [shared, left, right] = fixture();
  const first = save([shared, left]);
  const second = save(classifyLedger([shared, right]));
  const unresolved = '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> main\n';
  writeFileSync(ledger, unresolved);
  const run = (...refs) =>
    spawnSync(process.execPath, [script, '--merge', ...refs], {
      cwd: directory,
      encoding: 'utf8',
    });
  const merged = run(first, second);
  assert.equal(merged.status, 0, merged.stderr);
  const contents = readFileSync(ledger, 'utf8');
  assert.deepEqual(JSON.parse(contents), classifyLedger([shared, left, right]));
  assert.equal(run(first, second).status, 0);
  assert.equal(readFileSync(ledger, 'utf8'), contents);

  const changed = save([
    { ...shared, correction: 'Different evidence requires a reviewed resolution.' },
  ]);
  for (const refs of [
    [first, changed],
    [first, 'f'.repeat(40)],
    [first, 'HEAD;echo unsafe'],
  ]) {
    writeFileSync(ledger, unresolved);
    const result = run(...refs);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /conflicting merge receipt|Command failed|invalid baseline ref/);
    assert.equal(
      readFileSync(ledger, 'utf8'),
      unresolved,
      'failed merges must preserve the ledger',
    );
  }
  assert.match(run(first).stderr, /usage:/);
});
