import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { LEDGER_PATH } from './correction-coverage.mjs';
import { runRatchets } from './correction-ratchet.mjs';

const cli = fileURLToPath(new URL('./correction-ratchet.mjs', import.meta.url));
const schema = 'lyb.correction-ratchet/v1';
const finding = (key = 'legacy-value', path = 'app/old.txt') => ({ path, key });
const scanner = `
export function scan({ files, readSource }) {
  // retain every violating value and occurrence
  return files.filter(path => path.startsWith('app/') && path.endsWith('.txt'))
    .flatMap(path => readSource(path).split('\\n').filter(Boolean).map(key => ({ path, key })));
}
`;
const receipt = (fingerprint = 'preserve-invariant') => ({
  fingerprint,
  correction: 'Prevent new violations while warning on existing findings.',
  source: `https://github.com/JovieInc/LogYourBody/pull/42#${fingerprint}`,
  mechanization: 'Execute a deterministic scanner and shrink-only finding baseline in CI.',
  classification: {
    codebase: {
      feasible: false,
      rationale: 'The correction governs a repository-wide source policy.',
    },
    static: {
      feasible: true,
      rationale: 'A deterministic scanner detects the complete violation.',
    },
  },
  guard: {
    path: 'guard.mjs',
    anchor: 'retain every violating value and occurrence',
    ratchet: { baseline: 'baseline.json' },
  },
});

function fixture(t, { registered = true, findings = [finding()] } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-correction-ratchet-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const put = (path, value) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), value);
  };
  const json = (path, value) => put(path, JSON.stringify(value));
  const git = (...args) =>
    execFileSync('git', args, { cwd: root, encoding: 'utf8', stdio: 'pipe' }).trim();
  git('init', '-q');
  git('config', 'user.email', 'test@example.com');
  git('config', 'user.name', 'Test');
  git('config', 'commit.gpgsign', 'false');
  put('app/old.txt', findings.map(({ key }) => key).join('\n'));
  put('guard.mjs', scanner);
  json(LEDGER_PATH, registered ? [receipt()] : []);
  if (registered) json('baseline.json', { schema, findings });
  git('add', '.');
  git('commit', '-qm', 'fixture');
  const ref = git('rev-parse', 'HEAD');
  const warnings = [];
  const run = (args = []) =>
    runRatchets(args, { root, env: {}, warn: (line) => warnings.push(line) });
  return { root, put, json, git, ref, run, warnings };
}

test('existing findings warn and pass; clean rules become strict zero baselines', async (t) => {
  const f = fixture(t);
  const [report] = await f.run(['--base-ref', f.ref]);
  assert.equal(report.findings, 1);
  assert.match(f.warnings[0], /^::warning::LYB correction preserve-invariant: 1 existing/);
  f.put('app/old.txt', '');
  await assert.rejects(f.run(), /stale correction baseline/);
  await f.run(['--base-ref', f.ref, '--update-baselines']);
  assert.deepEqual(JSON.parse(readFileSync(join(f.root, 'baseline.json'))), {
    schema,
    findings: [],
  });
  f.git('add', '.');
  f.git('commit', '-qm', 'remove old violation');
  const cleanRef = f.git('rev-parse', 'HEAD');
  f.warnings.length = 0;
  assert.equal((await f.run(['--base-ref', cleanRef]))[0].findings, 0);
  assert.equal(f.warnings.length, 0);
  f.put('app/old.txt', 'legacy-value');
  await assert.rejects(f.run(['--base-ref', cleanRef]), /new correction violation/);
  // Restoring an old baseline cannot undo a ratchet already committed to main.
  f.json('baseline.json', { schema, findings: [finding()] });
  await assert.rejects(f.run(['--base-ref', cleanRef]), /baseline growth/);
});

test('baseline edits cannot grandfather new violations', async (t) => {
  for (const [contents, findings] of [
    ['changed-value', [finding('changed-value')]],
    ['legacy-value\nlegacy-value', [finding(), finding()]],
  ]) {
    const f = fixture(t);
    f.put('app/old.txt', contents);
    await assert.rejects(f.run(['--base-ref', f.ref]), /new correction violation/);
    f.json('baseline.json', { schema, findings });
    await assert.rejects(f.run(['--base-ref', f.ref]), /baseline growth/);
    await assert.rejects(f.run(['--base-ref', f.ref, '--update-baselines']), /baseline growth/);
  }
});

test('new files and moving a violation cannot spend an old finding allowance', async (t) => {
  const f = fixture(t);
  f.put('app/new.txt', 'legacy-value');
  await assert.rejects(f.run(), /new correction violation.*app\/new.txt/);
  f.put('app/old.txt', '');
  await assert.rejects(f.run(), /new correction violation.*app\/new.txt/);
});

test('first guard seeds only violations that exist at the immutable base revision', async (t) => {
  const f = fixture(t, { registered: false });
  f.json(LEDGER_PATH, [receipt()]);
  await assert.rejects(f.run(), /ENOENT/);
  await f.run(['--update-baselines', '--base-ref', f.ref]);
  assert.equal((await f.run(['--base-ref', f.ref]))[0].findings, 1);
  f.put('app/new.txt', 'new-value');
  f.json('baseline.json', { schema, findings: [finding(), finding('new-value', 'app/new.txt')] });
  await assert.rejects(f.run(['--base-ref', f.ref]), /baseline growth/);
  // Deleting the seed file and retrying cannot grandfather a new violation either.
  rmSync(join(f.root, 'baseline.json'));
  await assert.rejects(
    f.run(['--update-baselines', '--base-ref', f.ref]),
    /new correction violation/,
  );
  assert.throws(() => readFileSync(join(f.root, 'baseline.json')), /ENOENT/);
});

test('guard removal and baseline renaming cannot bypass the immutable comparison', async (t) => {
  const f = fixture(t);
  const row = receipt();
  delete row.guard.ratchet;
  f.json(LEDGER_PATH, [row]);
  await assert.rejects(f.run(['--base-ref', f.ref]), /removed correction ratchet/);
  f.json(LEDGER_PATH, []);
  await assert.rejects(f.run(['--base-ref', f.ref]), /removed correction ratchet/);
  row.guard.ratchet = { baseline: 'renamed.json' };
  f.json(LEDGER_PATH, [row]);
  f.json('renamed.json', { schema, findings: [finding('new-value')] });
  await assert.rejects(f.run(['--base-ref', f.ref]), /baseline growth/);
  f.json('renamed.json', { schema, findings: [finding()] });
  await f.run(['--base-ref', f.ref]);
});

test('a failed rule leaves every baseline unchanged during update', async (t) => {
  const f = fixture(t);
  const second = receipt('second-rule');
  second.guard.ratchet.baseline = 'second.json';
  f.json(LEDGER_PATH, [receipt(), second]);
  f.json('second.json', { schema, findings: [] });
  f.put('app/old.txt', '');
  const original = readFileSync(join(f.root, 'baseline.json'), 'utf8');
  // Both rules see clean source, but the second baseline is deliberately invalid.
  f.put('second.json', '{malformed');
  await assert.rejects(f.run(['--base-ref', f.ref, '--update-baselines']), /JSON/);
  assert.equal(readFileSync(join(f.root, 'baseline.json'), 'utf8'), original);
});

test('malformed or missing baseline evidence fails closed', async (t) => {
  for (const value of [
    '',
    '{broken',
    'null',
    JSON.stringify({ schema: 'other', findings: [] }),
    JSON.stringify({ schema, findings: {} }),
    JSON.stringify({ schema, findings: [{ path: '../outside', key: 'value' }] }),
    JSON.stringify({ schema, findings: [{ path: 'app/a', key: ' ' }] }),
    JSON.stringify({ schema, findings: [{ path: 'app/a', key: 'value', ignored: 'changed' }] }),
  ]) {
    const f = fixture(t);
    f.put('baseline.json', value);
    await assert.rejects(f.run(['--base-ref', f.ref]));
    await assert.rejects(f.run(['--base-ref', f.ref, '--update-baselines']));
  }
  const f = fixture(t);
  rmSync(join(f.root, 'baseline.json'));
  await assert.rejects(f.run(['--base-ref', f.ref, '--update-baselines']), /ENOENT/);
  await assert.rejects(f.run(['--base-ref', 'f'.repeat(40)]));
  await assert.rejects(f.run(['--base-ref', 'HEAD;echo unsafe']), /invalid baseline ref/);
});

test('malformed registration, duplicate baseline ownership and broken scanners fail', async (t) => {
  const f = fixture(t);
  for (const ratchet of [
    null,
    {},
    { baseline: '../outside' },
    { baseline: '/outside' },
    { baseline: 'a', ignored: true },
  ]) {
    f.json(LEDGER_PATH, [{ ...receipt(), guard: { ...receipt().guard, ratchet } }]);
    await assert.rejects(f.run(), /ratchet/);
  }
  const second = receipt('second-rule');
  f.json(LEDGER_PATH, [receipt(), second]);
  await assert.rejects(f.run(), /shared ratchet baseline/);
  f.put('guard.txt', scanner);
  f.json(LEDGER_PATH, [{ ...receipt(), guard: { ...receipt().guard, path: 'guard.txt' } }]);
  await assert.rejects(f.run(), /mjs scanner/);
  f.put(
    'broken.mjs',
    '// retain every violating value and occurrence\nexport const unrelated = true;',
  );
  f.json(LEDGER_PATH, [{ ...receipt(), guard: { ...receipt().guard, path: 'broken.mjs' } }]);
  await assert.rejects(f.run(), /must export scan/);
  f.put(
    'bad-findings.mjs',
    '// retain every violating value and occurrence\nexport const scan = () => null;',
  );
  f.json(LEDGER_PATH, [{ ...receipt(), guard: { ...receipt().guard, path: 'bad-findings.mjs' } }]);
  await assert.rejects(f.run(), /findings must be an array/);
});

test('duplicate receipts execute one rule; snapshots include untracked files and exclude deleted source', async (t) => {
  const f = fixture(t);
  f.json(LEDGER_PATH, [receipt(), { ...receipt(), source: 'https://example.com/correction/2' }]);
  assert.equal((await f.run()).length, 1);
  // Git modes for symlinks/submodules cannot become historical source files.
  symlinkSync('old.txt', join(f.root, 'app/link.txt'));
  f.git('add', 'app/link.txt');
  f.git('commit', '-qm', 'fixture symlink');
  rmSync(join(f.root, 'app/link.txt'));
  rmSync(join(f.root, 'app/old.txt'));
  await f.run(['--base-ref', f.git('rev-parse', 'HEAD'), '--update-baselines']);
  assert.equal((await f.run())[0].findings, 0);
});

test('baseline and scanner symlinks cannot escape the checkout, including dangling seed links', async (t) => {
  const f = fixture(t, { registered: false });
  f.json(LEDGER_PATH, [receipt()]);
  symlinkSync('missing.json', join(f.root, 'baseline.json'));
  await assert.rejects(f.run(['--base-ref', f.ref, '--update-baselines']), /symlink/);
  rmSync(join(f.root, 'baseline.json'));
  mkdirSync(join(f.root, 'real'));
  symlinkSync('real', join(f.root, 'linked'));
  f.json(LEDGER_PATH, [
    { ...receipt(), guard: { ...receipt().guard, ratchet: { baseline: 'linked/new.json' } } },
  ]);
  await assert.rejects(f.run(['--base-ref', f.ref, '--update-baselines']), /symlink/);
  f.json(LEDGER_PATH, [receipt()]);
  f.json('baseline.json', { schema, findings: [finding()] });
  f.git('mv', 'guard.mjs', 'real/guard.mjs');
  symlinkSync('real/guard.mjs', join(f.root, 'guard.mjs'));
  await assert.rejects(f.run(), /guard coverage/);
});

test('CLI reports failures, empty success and summary evidence without changing baselines', async (t) => {
  const f = fixture(t);
  for (const args of [
    ['--unknown'],
    ['--update-baselines'],
    ['--base-ref'],
    ['--update-baselines', '--update-baselines'],
  ]) {
    await assert.rejects(f.run(args), /usage|requires --base-ref/);
  }
  const summary = join(f.root, 'summary.md');
  await runRatchets([], { root: f.root, env: { GITHUB_STEP_SUMMARY: summary }, warn: () => {} });
  assert.match(readFileSync(summary, 'utf8'), /preserve-invariant: 1 accepted existing/);
  f.json(LEDGER_PATH, []);
  assert.deepEqual(await f.run(), []);
  const failure = spawnSync(process.execPath, [cli, '--unknown'], { encoding: 'utf8' });
  assert.equal(failure.status, 1);
  assert.match(failure.stderr, /Correction ratchet failed: usage/);
  const success = spawnSync(process.execPath, [cli], {
    encoding: 'utf8',
    env: { ...process.env, GITHUB_STEP_SUMMARY: '' },
  });
  assert.equal(success.status, 0, success.stderr);
  // The real checkout can have installed ratchets; CLI serialization must
  // preserve their reports as well as the empty fixture case above.
  assert.deepEqual(JSON.parse(success.stdout), await runRatchets([], { env: {}, warn: () => {} }));
});
