import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { classifyLedger } from '../../../scripts/correction-classifier.mjs';
import { emitCorrectionChecks, runCorrectionChecks } from './correction-checks.mjs';

const cli = fileURLToPath(new URL('./correction-checks.mjs', import.meta.url));
const receipts = () =>
  JSON.parse(
    readFileSync(new URL('../../../scripts/fixtures/correction-classifier.json', import.meta.url)),
  );
const scanner = `
export function scan({ files, readSource }) {
  // enforce the retained invariant
  return files.filter(path => path.endsWith('.swift')).flatMap(path =>
    readSource(path).split('\\n').filter(line => line === 'forbidden import')
      .map(key => ({ path, key })));
}
`;

function fixture(t, rows = [receipts()[2]]) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-correction-checks-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  execFileSync('git', ['init', '-q'], { cwd: root });
  const put = (path, contents) => writeFileSync(join(root, path), contents);
  put('source-guard.mjs', scanner);
  put('coverage-guard.mjs', scanner);
  put('example.swift', 'forbidden import\n');
  const save = (input = rows) => put('ledger.json', JSON.stringify(classifyLedger(input)));
  save();
  const run = (...args) =>
    spawnSync(process.execPath, [cli, ...args], { cwd: root, encoding: 'utf8' });
  return { root, put, save, run, rows };
}

test('lint-level violation warns at recurrence zero and fails at recurrence one or more', (t) => {
  const f = fixture(t);
  const first = f.run('ledger.json');
  assert.equal(first.status, 0, first.stderr);
  assert.match(first.stderr, /::warning::.*source-pattern.*example.swift.*forbidden import/);
  const [warning] = JSON.parse(first.stdout).checks;
  assert.equal(warning.recurrence, 0);
  assert.equal(warning.severity, 'warning');
  assert.deepEqual(warning.findings, [{ path: 'example.swift', key: 'forbidden import' }]);

  for (const repeats of [1, 2]) {
    const repeated = Array.from({ length: repeats }, (_, index) => ({
      ...f.rows[0],
      source: `${f.rows[0].source}#repeat-${index}`,
    }));
    f.save([...f.rows, ...repeated]);
    const result = f.run('ledger.json');
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /::error::.*source-pattern.*example.swift.*forbidden import/);
    const [hard] = JSON.parse(result.stdout).checks;
    assert.deepEqual(hard, { ...warning, recurrence: repeats, severity: 'error' });
  }
});

for (const [index, level] of [
  [0, 'codebase'],
  [4, 'prose'],
  [5, 'human'],
]) {
  test(`${level} classifier output emits no new check, even on recurrence`, (t) => {
    const row = receipts()[index];
    const rows = [row, { ...row, source: `${row.source}#repeat` }];
    assert.deepEqual(emitCorrectionChecks(classifyLedger(rows)), []);
    const f = fixture(t, rows);
    const result = f.run('ledger.json');
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stderr, '');
    assert.deepEqual(JSON.parse(result.stdout), { checks: [], exitCode: 0 });
  });
}

test('both static classifier routes emit once per fingerprint without mutating input', () => {
  const rows = classifyLedger(receipts());
  const before = structuredClone(rows);
  const checks = emitCorrectionChecks([...rows, rows[2]]);
  assert.deepEqual(
    checks.map(({ ruleId }) => ruleId),
    ['ci-invariant', 'file-pattern-or-string'],
  );
  assert.ok(checks.every(({ recurrence, severity }) => recurrence === 0 && severity === 'warning'));
  assert.deepEqual(rows, before);
  assert.deepEqual(emitCorrectionChecks([]), []);
});

test('clean recurrent checks pass and mixed violations still report every check', (t) => {
  const rows = [receipts()[2], receipts()[3]];
  const f = fixture(t, [...rows, { ...rows[1], source: `${rows[1].source}#repeat` }]);
  const failing = f.run('ledger.json');
  assert.equal(failing.status, 1, failing.stderr);
  assert.match(failing.stderr, /::warning::.*source-pattern/);
  assert.match(failing.stderr, /::error::.*coverage-invariant/);
  f.put('example.swift', 'allowed import\n');
  const passing = f.run('ledger.json');
  assert.equal(passing.status, 0, passing.stderr);
  assert.equal(passing.stderr, '');
  assert.ok(JSON.parse(passing.stdout).checks.every(({ findings }) => findings.length === 0));
});

test('malformed input fails closed and existing baseline ratchets cannot be wrapped', (t) => {
  const row = classifyLedger([receipts()[2]])[0];
  for (const invalid of [
    { ...row, level: 'codebase' },
    { ...row, ruleId: 'ci-invariant' },
    { ...row, level: undefined },
    { ...row, guard: undefined },
    { ...row, guard: { ...row.guard, ratchet: { baseline: 'baseline.json' } } },
  ]) {
    assert.throws(() => emitCorrectionChecks([invalid]));
  }
  const f = fixture(t);
  f.put('ledger.json', '{invalid');
  assert.equal(f.run('ledger.json').status, 1);
  assert.match(f.run().stderr, /usage:/);
  assert.match(f.run('--unknown').stderr, /usage:/);
  assert.match(f.run('ledger.json', 'extra').stderr, /usage:/);
  assert.match(f.run('missing.json').stderr, /ENOENT/);
});

test('missing, unsafe and broken scanners fail even on the first receipt', async (t) => {
  const f = fixture(t);
  const rows = classifyLedger(f.rows);
  const run = () => runCorrectionChecks(rows, { root: f.root, report: () => {} });
  const putScanner = (contents) => {
    f.put('source-guard.mjs', `// enforce the retained invariant\n${contents}`);
  };
  for (const path of ['../outside.mjs', '/outside.mjs', 'missing.mjs', 'example.swift']) {
    await assert.rejects(
      runCorrectionChecks([{ ...rows[0], guard: { ...rows[0].guard, path } }], {
        root: f.root,
      }),
    );
  }
  f.put('source-guard.mjs', 'export function scan() { return []; }');
  await assert.rejects(run(), /missing guard anchor/);
  // Use distinct module paths so Node cannot reuse an earlier scanner import.
  for (const [index, contents, error] of [
    [0, 'export const scan = false;', /must export scan/],
    [1, 'export function scan() { throw new Error("scanner failed"); }', /scanner failed/],
    [2, 'export function scan() { return null; }', /findings must be an array/],
    [3, 'export function scan() { return [{}]; }', /invalid correction finding/],
    [
      4,
      'export function scan() { return [{ path: "../outside", key: "violation" }]; }',
      /nonlocal/,
    ],
  ]) {
    const path = `broken-${index}.mjs`;
    f.put(path, `// enforce the retained invariant\n${contents}`);
    await assert.rejects(
      runCorrectionChecks([{ ...rows[0], guard: { ...rows[0].guard, path } }], {
        root: f.root,
      }),
      error,
    );
  }
  putScanner(scanner);
  symlinkSync(join(f.root, 'source-guard.mjs'), join(f.root, 'linked.mjs'));
  await assert.rejects(
    runCorrectionChecks([{ ...rows[0], guard: { ...rows[0].guard, path: 'linked.mjs' } }], {
      root: f.root,
    }),
    /symlink/,
  );
});

test('async scanners report escaped diagnostics and ignore deleted source files', async (t) => {
  const f = fixture(t);
  f.put(
    'async.mjs',
    `// enforce the retained invariant
export async function scan({ files }) {
  if (files.includes('deleted.swift')) throw new Error('deleted file retained');
  return [{ path: 'example.swift', key: 'forbidden%import\\n::error::injected' }];
}`,
  );
  f.put('deleted.swift', '');
  execFileSync('git', ['add', 'deleted.swift'], { cwd: f.root });
  rmSync(join(f.root, 'deleted.swift'));
  const row = receipts()[2];
  const messages = [];
  const result = await runCorrectionChecks(
    classifyLedger([{ ...row, guard: { ...row.guard, path: 'async.mjs' } }]),
    { root: f.root, report: (message) => messages.push(message) },
  );
  assert.equal(result.exitCode, 0);
  assert.equal(messages.length, 1);
  assert.match(messages[0], /forbidden%25import%0A::error::injected$/);
});
