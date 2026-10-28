import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { classifyExecution, replaceOnce, runCampaign, runCLI, validateManifest } from './run.mjs';

const target = () => ({
  id: 'fixture',
  source: 'src/policy.mjs',
  test: 'src/policy.test.mjs',
  minimumTests: 2,
  timeoutMs: 2000,
  coverage: { lines: 100, branches: 100, functions: 100 },
  mutations: [{ id: 'boundary', find: '>= 18', replace: '> 18' }],
});
const manifest = (entry = target()) => ({ schemaVersion: 1, targets: [entry] });
const summary = (overrides = {}) => ({
  type: 'summary',
  success: true,
  counts: { tests: 2, passed: 2, failed: 0, cancelled: 0, skipped: 0, todo: 0 },
  ...overrides,
});
const result = (events = [summary()], extra = {}) => ({
  status: 0,
  signal: null,
  stdout: events.map((event) => JSON.stringify(event)).join('\n'),
  ...extra,
});

test('manifest requires unique nonempty targets, semantic edits, bounded runtime and coverage floors', () => {
  assert.equal(validateManifest(manifest()).targets.length, 1);
  for (const value of [
    null,
    {},
    { schemaVersion: 2, targets: [] },
    manifest({ ...target(), source: '../escape.mjs' }),
    manifest({ ...target(), source: '/escape.mjs' }),
    manifest({ ...target(), source: 'src\\..\\escape.mjs' }),
    manifest({ ...target(), source: 'src//policy.mjs' }),
    manifest({ ...target(), source: 'src/./policy.mjs' }),
    manifest({ ...target(), source: 'policy.ts' }),
    manifest({ ...target(), test: 'src/policy.mjs' }),
    manifest({ ...target(), minimumTests: 0 }),
    manifest({ ...target(), timeoutMs: 60_001 }),
    manifest({ ...target(), coverage: { lines: 0, branches: 100, functions: 100 } }),
    manifest({ ...target(), testNamePattern: 7 }),
    manifest({ ...target(), mutations: [] }),
    { schemaVersion: 1, targets: [target(), target()] },
    manifest({ ...target(), mutations: [target().mutations[0], target().mutations[0]] }),
    manifest({ ...target(), mutations: [{ id: 'noop', find: 'a', replace: 'a' }] }),
  ])
    assert.throws(() => validateManifest(value));
});

test('source edits require exactly one anchor and preserve replacement text literally', () => {
  assert.equal(replaceOnce('value >= 18', { find: '>= 18', replace: '$&' }), 'value $&');
  for (const source of ['absent', '>= 18 >= 18']) {
    assert.throws(() => replaceOnce(source, target().mutations[0]), /exactly once/);
  }
});

test('process errors, timeouts, incomplete tests and runtime exceptions never count as killed', () => {
  // Observed in the cloud sandbox: status may be zero even when spawn returns EPERM.
  assert.equal(
    classifyExecution(result(undefined, { error: { code: 'EPERM' } }), 2).status,
    'error',
  );
  assert.equal(
    classifyExecution(result(undefined, { error: { code: 'ETIMEDOUT' } }), 2).status,
    'timeout',
  );
  assert.equal(classifyExecution(result(undefined, { signal: 'SIGKILL' }), 2).status, 'error');
  assert.equal(classifyExecution({ status: 1, stdout: 'not json' }, 2).status, 'error');
  assert.equal(classifyExecution(result([]), 2).status, 'error');
  assert.equal(classifyExecution(result(), 3).status, 'error');
  assert.equal(classifyExecution(result(), 2, 3).status, 'error');
  for (const flag of ['cancelled', 'skipped', 'todo']) {
    assert.equal(
      classifyExecution(result([summary({ counts: { ...summary().counts, [flag]: 1 } })]), 2)
        .status,
      'error',
    );
  }
  assert.equal(
    classifyExecution(result([summary({ counts: { ...summary().counts, passed: 1 } })]), 2).status,
    'error',
  );
  const failure = { type: 'failure', name: 'boundary', code: 'ERR_ASSERTION' };
  const failed = summary({ success: false, counts: { ...summary().counts, passed: 1, failed: 1 } });
  assert.equal(classifyExecution(result([failure, failed], { status: 1 }), 2).status, 'killed');
  assert.equal(
    classifyExecution(
      result([{ ...failure, code: 'ERR_TEST_FAILURE', causeCode: 'ERR_ASSERTION' }, failed], {
        status: 1,
      }),
      2,
    ).status,
    'killed',
  );
  assert.equal(
    classifyExecution(
      result([failure, { type: 'failure', failureType: 'subtestsFailed' }, failed], { status: 1 }),
      2,
    ).status,
    'killed',
  );
  assert.equal(
    classifyExecution(
      result([{ ...failure, code: 'ERR_MODULE_NOT_FOUND' }, failed], { status: 1 }),
      2,
    ).status,
    'error',
  );
  assert.equal(classifyExecution(result([failure, failed], { status: 7 }), 2).status, 'error');
  assert.equal(classifyExecution(result(), 2).status, 'passed');
});

function fixture(callback) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-mutation-behavior-'));
  try {
    const write = (path, content) => {
      mkdirSync(dirname(join(root, path)), { recursive: true });
      writeFileSync(join(root, path), content);
    };
    write('src/policy.mjs', 'export function allowed(value) { return value >= 18; }\n');
    write(
      'src/policy.test.mjs',
      `import assert from 'node:assert/strict';
import test from 'node:test';
import { allowed } from './policy.mjs';
test('admits the eligibility boundary', () => assert.equal(allowed(18), true));
test('rejects an ineligible value', () => assert.equal(allowed(17), false));
`,
    );
    callback(root, write);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('campaign executes isolated real mutants and fails on survivors, invalid code and runtime errors', () =>
  fixture((root) => {
    const before = readFileSync(join(root, 'src/policy.mjs'), 'utf8');
    const entry = target();
    entry.mutations.push(
      { id: 'equivalent-survivor', find: '>= 18', replace: '> 17' },
      { id: 'missing-anchor', find: 'not present', replace: 'changed' },
      { id: 'syntax-error', find: '>= 18', replace: '> = 18' },
      {
        id: 'runtime-error',
        find: 'return value >= 18;',
        replace: "throw new Error('runtime problem');",
      },
    );
    const report = runCampaign(root, manifest(entry));
    assert.equal(report.status, 'failed');
    assert.equal(report.killed, 1);
    assert.equal(report.planned, 5);
    assert.equal(report.executed, 5);
    assert.deepEqual(
      report.targets[0].mutations.map((mutation) => mutation.status),
      ['killed', 'survived', 'invalid', 'invalid', 'error'],
    );
    assert.equal(report.targets[0].baseline.coverage.coveredLinePercent, 100);
    assert.equal(report.targets[0].baseline.counts.tests, 2);
    assert.match(report.targets[0].hashes['src/policy.mjs'], /^[a-f0-9]{64}$/);
    assert.equal(readFileSync(join(root, 'src/policy.mjs'), 'utf8'), before);
  }));

test('a killed boundary mutant passes; baseline failures and missing source stop mutation', () =>
  fixture((root, write) => {
    const entry = { ...target(), testNamePattern: '^(admits|rejects)' };
    assert.equal(runCampaign(root, manifest(entry)).status, 'passed');
    write('src/policy.mjs', 'export function allowed(value) { return value > 18; }\n');
    const failed = runCampaign(root, manifest());
    assert.equal(failed.targets[0].status, 'baseline_failed');
    assert.equal(failed.executed, 0);
    rmSync(join(root, 'src/policy.mjs'));
    assert.equal(runCampaign(root, manifest()).targets[0].status, 'error');
  }));

test('source-text assertions cannot substitute for executing the measured production source', () =>
  fixture((root, write) => {
    write(
      'src/policy.test.mjs',
      `import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('./policy.mjs', import.meta.url), 'utf8');
test('reads boundary text', () => assert.match(source, />= 18/));
test('reads export text', () => assert.match(source, /export/));
`,
    );
    const report = runCampaign(root, manifest());
    assert.equal(report.targets[0].status, 'baseline_failed');
    assert.equal(report.targets[0].baseline.coverage, null);
    assert.equal(report.executed, 0);
  }));

test('CLI writes a reviewable receipt and overwrites stale success when setup fails', () =>
  fixture((root, write) => {
    const report = () =>
      JSON.parse(readFileSync(join(root, 'coverage/mutation/report.json'), 'utf8'));
    write('scripts/mutation/targets.json', JSON.stringify(manifest()));
    assert.equal(runCLI([], root), 0);
    assert.equal(report().status, 'passed');
    assert.equal(runCLI(['--pretend-passed'], root), 1);
    assert.equal(report().status, 'failed');
    assert.match(report().reason, /no overrides/);
    write('scripts/mutation/targets.json', '{}');
    assert.equal(runCLI([], root), 1);
    assert.equal(report().status, 'failed');
  }));

test('a real infinite mutant times out and leaves no live test process', () =>
  fixture((root, write) => {
    const pidPath = join(root, 'mutant.pid');
    write(
      'src/policy.mjs',
      "import { writeFileSync } from 'node:fs';\nexport function allowed(value) { return value >= 18; }\n",
    );
    const entry = {
      ...target(),
      timeoutMs: 1000,
      mutations: [
        {
          id: 'infinite',
          find: 'return value >= 18;',
          replace: `writeFileSync(${JSON.stringify(pidPath)}, String(process.pid)); while (true) {}`,
        },
      ],
    };
    const report = runCampaign(root, manifest(entry));
    assert.equal(report.status, 'failed');
    assert.equal(report.targets[0].mutations[0].status, 'timeout');
    const pid = Number(readFileSync(pidPath, 'utf8'));
    let alive = false;
    try {
      process.kill(pid, 0);
      alive = true;
    } catch (error) {
      assert.equal(error.code, 'ESRCH');
    }
    // Clean up a regressed forked runner before failing the assertion.
    if (alive) process.kill(pid, 'SIGKILL');
    assert.equal(alive, false, 'Timed-out mutant must be reaped, not left running');
  }));
