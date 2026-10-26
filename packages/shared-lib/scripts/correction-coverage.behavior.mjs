import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  assertLedgerMergeReady,
  assertNoRegression,
  coverageReport,
  LEDGER_PATH,
  mergeCorrectionLedgers,
  readSource,
  renderCoverage,
  runCoverage,
} from './correction-coverage.mjs';
import { runCoverageOwnerLoop } from './correction-coverage-owner.mjs';
import { postCoverageComment } from '../../../.github/scripts/lib/linear-correction-coverage.mjs';

const anchor = 'enforce the retained invariant';
const guard = { path: 'guard.mjs', anchor };
const receipt = (fingerprint, level, extra = {}) => ({
  fingerprint,
  level,
  correction: 'Keep the deterministic guard in place.',
  source: `https://github.com/JovieInc/LogYourBody/pull/42#${fingerprint.trim()}`,
  mechanization: 'Enforce the invariant with a deterministic guard.',
  ...extra,
});
const report = (receipts) => coverageReport(receipts, () => anchor);
const pyramid = ['codebase', 'static', 'prose', 'human'];
const classification = (chosen) =>
  Object.fromEntries(
    pyramid.map((level) => [
      level,
      {
        feasible: pyramid.indexOf(level) >= pyramid.indexOf(chosen),
        rationale: `Reason for ${level}`,
      },
    ]),
  );

test('classifier chooses the first feasible level and retains reasons for every lower level', () => {
  for (const level of pyramid) {
    const value = report([receipt('route', undefined, { classification: classification(level) })]);
    const [rule] = value.rules;
    assert.equal(rule.level, level);
    assert.equal(rule.rationale, `Reason for ${level}`);
    assert.deepEqual(
      rule.considered.map((item) => item.level),
      pyramid.slice(0, pyramid.indexOf(level) + 1),
    );
    assert.equal(rule.mechanized, false);
    assert.equal(value.levels[level].total, 1);
    assert.match(renderCoverage(value), new RegExp(`Reason for ${level}`));
  }
  // Wording and an attached check cannot overrule the feasibility assessment.
  const [rule] = report([
    receipt('route', undefined, {
      correction: 'Ask a human to review the prose and lint result.',
      classification: classification('codebase'),
      guard,
    }),
  ]).rules;
  assert.equal(rule.level, 'codebase');
  assert.equal(rule.mechanized, true);
});

test('classifier rejects missing assessments, unsupported fallbacks and conflicting annotations', () => {
  const valid = classification('human');
  for (const invalid of [
    null,
    [],
    {},
    { ...valid, codebase: undefined },
    { ...valid, codebase: { feasible: 'false', rationale: 'Not possible' } },
    { ...valid, codebase: { feasible: false, rationale: ' ' } },
    { ...valid, human: { feasible: false, rationale: 'No suitable reviewer' } },
    { ...valid, typo: { feasible: true, rationale: 'Unknown level' } },
  ]) {
    assert.throws(
      () => report([receipt('invalid', undefined, { classification: invalid })]),
      /classification|assessment|enforceable/,
    );
  }
  assert.throws(
    () => report([receipt('conflict', 'human', { classification: classification('static') })]),
    /lowest enforceable/,
  );
  assert.throws(
    () =>
      report([
        receipt(' Same Rule ', undefined, { classification: valid }),
        receipt('same-rule', undefined, { classification: classification('prose') }),
      ]),
    /conflicting/,
  );
  const revised = structuredClone(valid);
  revised.codebase.rationale = 'A different reason';
  assert.throws(
    () =>
      report([
        receipt('same-rule', undefined, { classification: valid }),
        receipt('same-rule', undefined, { classification: revised }),
      ]),
    /conflicting/,
  );
});

test('current ledger requires classification while historical baselines remain readable', (t) => {
  const legacy = receipt('retained', 'static', { guard });
  const { root, ref } = fixtureRepo(t, [legacy]);
  assert.throws(() => runCoverage([], { root, env: {} }), /classification required/);
  writeFileSync(
    join(root, LEDGER_PATH),
    JSON.stringify([{ ...legacy, classification: classification('static') }]),
  );
  const value = runCoverage(['--base-ref', ref], { root, env: {} });
  assert.equal(value.percent, 100);
  assert.equal(value.rules[0].rationale, 'Reason for static');
  // One unclassified receipt must fail even if an earlier receipt was classified.
  writeFileSync(
    join(root, LEDGER_PATH),
    JSON.stringify([{ ...legacy, classification: classification('static') }, legacy]),
  );
  assert.throws(() => runCoverage([], { root, env: {} }), /classification required/);
});

test('route explanations are safe to render in the owner report table', () => {
  const assessed = classification('static');
  assessed.codebase.rationale = 'Needs <owner> | code\nchange';
  assessed.static.rationale = '  Reject the invalid config  ';
  const value = report([receipt('route', undefined, { classification: assessed })]);
  assert.equal(value.rules[0].rationale, 'Reject the invalid config');
  assert.match(
    renderCoverage(value),
    /codebase \(not feasible\): Needs &lt;owner&gt; &#124; code change/,
  );
  assert.match(renderCoverage(value), /static \(feasible\): Reject the invalid config/);
});

function fixtureRepo(t, receipts) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-coverage-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const git = (args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).trim();
  mkdirSync(dirname(join(root, LEDGER_PATH)), { recursive: true });
  writeFileSync(join(root, LEDGER_PATH), JSON.stringify(receipts));
  writeFileSync(join(root, guard.path), anchor);
  git(['init', '-q']);
  git(['add', '.']);
  git([
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@example.com',
    'commit',
    '-qm',
    'fixture',
  ]);
  return { root, ref: git(['rev-parse', 'HEAD']) };
}

test('merge readiness scans large staged imports and still rejects trailing conflict markers', (t) => {
  const { root } = fixtureRepo(t, []);
  const source = join(root, 'large-source.txt');
  const content = 'already reviewed upstream source\n'.repeat(50_000);
  const stage = (suffix, prefix = content) => {
    writeFileSync(source, prefix + suffix);
    execFileSync('git', ['add', 'large-source.txt'], { cwd: root });
  };
  stage('resolved source\n');
  assert.doesNotThrow(() => assertLedgerMergeReady(root));
  for (const marker of ['<<<<<<< ours', '||||||| base', '=======', '>>>>>>>> theirs']) {
    stage(marker + '\n');
    assert.throws(() => assertLedgerMergeReady(root), /resolve staged conflict markers/);
  }
  stage('=======ordinary content\n');
  assert.doesNotThrow(() => assertLedgerMergeReady(root));

  // Position a marker across a 64KiB scanner boundary, including the diff header.
  stage('<<<<<<< ours\n', 'x\n');
  const initialDiff = execFileSync('git', ['diff', '--cached', '--no-ext-diff', '--unified=0'], {
    cwd: root,
    encoding: 'utf8',
  });
  const markerOffset = initialDiff.indexOf('+<<<<<<< ours');
  assert.ok(markerOffset > 0);
  stage('<<<<<<< ours\n', 'x'.repeat(1 + 64 * 1024 - 4 - markerOffset) + '\n');
  assert.throws(() => assertLedgerMergeReady(root), /resolve staged conflict markers/);

  // Neither a giant ordinary line nor a marker run needs unbounded retained text.
  const giantLine = 'x'.repeat(2 * 1024 * 1024) + '\n';
  stage('resolved source\n', giantLine);
  assert.doesNotThrow(() => assertLedgerMergeReady(root));
  stage('||||||| base\n', giantLine);
  assert.throws(() => assertLedgerMergeReady(root), /resolve staged conflict markers/);
});

test('ledger merge retains independent receipts and one-sided edits without mutating inputs', () => {
  const row = (id) => receipt(id, 'static', { guard, classification: classification('static') });
  const base = [row('kept')];
  const edited = { ...base[0], correction: 'Clarify the retained invariant.' };
  const ours = [row('ours'), edited];
  const theirs = [row('theirs'), base[0]];
  assert.deepEqual(
    mergeCorrectionLedgers(base, ours, theirs, () => anchor),
    [ours[0], edited, theirs[0]],
  );
  assert.deepEqual(
    mergeCorrectionLedgers(base, base, [edited], () => anchor),
    [edited],
  );
  assert.deepEqual(
    mergeCorrectionLedgers(base, [edited], [edited], () => anchor),
    [edited],
  );
  assert.equal(base[0].correction, 'Keep the deterministic guard in place.');
  const repeated = { ...base[0], source: 'https://example.com/second-receipt' };
  assert.deepEqual(
    mergeCorrectionLedgers(base, [...base, repeated], base, () => anchor),
    [base[0], repeated],
  );
});

test('ledger merge refuses deletions, divergent edits, duplicates and lost guards', () => {
  const base = [receipt('kept', 'static', { guard, classification: classification('static') })];
  const edited = { ...base[0], correction: 'An independent change.' };
  for (const [ours, theirs, error] of [
    [[], base, /removed receipt/],
    [base, [], /removed receipt/],
    [[edited], [{ ...edited, correction: 'A conflicting change.' }], /concurrent receipt edits/],
    [[...base, base[0]], base, /duplicate receipt/],
    [[{ ...base[0], guard: undefined }], base, /guard coverage/],
    [
      [
        {
          ...base[0],
          level: 'prose',
          guard: undefined,
          classification: classification('prose'),
          proseOnlyReason: 'Editorial judgment.',
        },
      ],
      base,
      /regression/,
    ],
  ]) {
    assert.throws(() => mergeCorrectionLedgers(base, ours, theirs, () => anchor), error);
  }
  assert.throws(() => mergeCorrectionLedgers({}, base, base), /array/);
  assert.throws(() => mergeCorrectionLedgers([], base, base, () => ''), /guard coverage/);
});

test('ledger merge CLI uses all three Git conflict stages and leaves refused merges untouched', (t) => {
  const row = (id) => receipt(id, 'static', { guard, classification: classification('static') });
  const { root } = fixtureRepo(t, [row('kept')]);
  const git = (args, input) => execFileSync('git', args, { cwd: root, encoding: 'utf8', input });
  const path = join(root, LEDGER_PATH);
  const marker = 'unresolved conflict';
  writeFileSync(path, marker);
  const stages = [[], [row('ours')], [row('theirs')]].map((added) => [row('kept'), ...added]);
  const stage = () => {
    git(['update-index', '--force-remove', LEDGER_PATH]);
    const entries = stages
      .map((rows, index) => {
        const hash = git(['hash-object', '-w', '--stdin'], JSON.stringify(rows)).trim();
        return `100644 ${hash} ${index + 1}\t${LEDGER_PATH}\n`;
      })
      .join('');
    git(['update-index', '--index-info'], entries);
  };
  stage();
  assert.equal(runCoverage(['--merge-ledger'], { root, env: {} }).mechanized, 3);
  assert.deepEqual(JSON.parse(readFileSync(path, 'utf8')), [
    row('kept'),
    row('theirs'),
    row('ours'),
  ]);
  assert.equal(git(['ls-files', '-u']).trim().split('\n').length, 3, 'staging remains explicit');
  const before = readFileSync(path, 'utf8');
  const blob = git(['hash-object', '-w', '--stdin'], anchor).trim();
  git(['update-index', '--force-remove', guard.path]);
  git(
    ['update-index', '--index-info'],
    [1, 2, 3].map((index) => `100644 ${blob} ${index}\t${guard.path}\n`).join(''),
  );
  writeFileSync(
    join(root, guard.path),
    `<<<<<<< ours\n${anchor}\n=======\n${anchor}\n>>>>>>> theirs\n`,
  );
  assert.throws(
    () => runCoverage(['--merge-ledger'], { root, env: {} }),
    /ledger merge: resolve other conflicts first: guard.mjs/,
  );
  assert.equal(readFileSync(path, 'utf8'), before, 'unresolved guard leaves ledger untouched');
  writeFileSync(join(root, guard.path), anchor);
  git(['add', guard.path]);
  stages[2] = [];
  stage();
  writeFileSync(path, marker);
  assert.throws(() => runCoverage(['--merge-ledger'], { root, env: {} }), /removed receipt/);
  assert.equal(readFileSync(path, 'utf8'), marker);
  git(['update-index', '--force-remove', LEDGER_PATH]);
  assert.throws(() => runCoverage(['--merge-ledger'], { root, env: {} }));
  assert.equal(readFileSync(path, 'utf8'), marker);
});

test('counts distinct rules, all four pyramid levels and unclassified receipts honestly', () => {
  const rows = [
    receipt('invariant', 'codebase', { guard }),
    receipt('invariant', 'codebase', { guard, source: 'https://example.com/second-receipt' }),
    receipt('pending', 'codebase'),
    receipt('lint', 'static', { guard }),
    receipt('copy', 'prose'),
    receipt('judgment', 'human'),
    receipt('old-receipt', undefined),
  ];
  const value = report(rows);
  assert.equal(value.total, 6);
  assert.equal(value.mechanized, 2);
  assert.equal(value.percent, 100 / 3);
  assert.deepEqual(value.levels.codebase, { mechanized: 1, total: 2, percent: 50 });
  assert.deepEqual(value.levels.static, { mechanized: 1, total: 1, percent: 100 });
  for (const level of ['prose', 'human', 'unclassified'])
    assert.equal(value.levels[level].percent, 0);
  assert.match(renderCoverage(value), /\| codebase \| 1\/2 \| 50.00% \|/);
  assert.match(renderCoverage(value), /Overall \| 2\/6 \| 33.33%/);
});

test('ledger reports lessons, guards and recurrence from chat, review, Linear and revert receipts', () => {
  const sources = [
    'https://example.com/memory/tim-correction',
    'https://github.com/JovieInc/LogYourBody/pull/42#discussion_r123',
    'https://linear.app/jovie/issue/LYB-204#comment-123',
    `https://github.com/JovieInc/LogYourBody/commit/${'a'.repeat(40)}`,
  ];
  const rows = sources.map((source) =>
    receipt(' Retain Evidence ', 'static', {
      source,
      correction: 'Keep <lesson> | evidence\nintact.',
      guard,
    }),
  );
  const value = report([...rows, { ...rows[0], fingerprint: 'retain-evidence' }]);
  const [rule] = value.rules;
  assert.equal(value.total, 1);
  assert.equal(rule.level, 'static');
  assert.deepEqual(rule.guard, guard);
  assert.deepEqual(rule.recurrence, { receiptCount: 4, repeatCount: 3 });
  assert.deepEqual(
    rule.receipts,
    rows
      .map(({ source, correction, mechanization }) => ({ source, correction, mechanization }))
      .sort((a, b) => a.source.localeCompare(b.source)),
  );
  assert.deepEqual(report([...rows].reverse()), value);
  const rendered = renderCoverage(value);
  for (const source of sources) assert.ok(rendered.includes(source));
  assert.match(rendered, /Keep &lt;lesson&gt; &#124; evidence intact\./);
  assert.match(rendered, /guard.mjs/);
  assert.match(rendered, /enforce the retained invariant/);
  assert.match(rendered, /4 receipts; 3 repeats/);
  assert.deepEqual(report([rows[0]]).rules[0].recurrence, { receiptCount: 1, repeatCount: 0 });
});

test('ledger CI retains each source against Git even when rule coverage and receipt count stay equal', (t) => {
  const first = receipt('retained', 'static', {
    guard,
    classification: classification('static'),
  });
  const second = { ...first, source: 'https://example.com/second-receipt' };
  const extra = { ...first, source: 'https://example.com/third-receipt' };
  const { root, ref } = fixtureRepo(t, [first, second]);
  for (const rows of [
    [first],
    [first, extra],
    [first, { ...second, fingerprint: 'different-rule' }],
  ]) {
    writeFileSync(join(root, LEDGER_PATH), JSON.stringify(rows));
    assert.throws(() => runCoverage(['--base-ref', ref], { root, env: {} }), /removed receipt/);
  }
  // Duplicate replays, canonical URL spelling, new receipts and guard promotions are allowed.
  const revised = [second, first, first, extra].map((row) => ({
    ...row,
    fingerprint: ' RETAINED ',
    level: 'codebase',
    classification: classification('codebase'),
    correction: 'Clarified lesson without losing the original evidence.',
    source: row.source.replace('https://example.com/', 'https://EXAMPLE.com:443/'),
  }));
  writeFileSync(join(root, LEDGER_PATH), JSON.stringify(revised));
  const value = runCoverage(['--base-ref', ref], { root, env: {} });
  assert.deepEqual(value.rules[0].recurrence, { receiptCount: 3, repeatCount: 2 });
});

test('empty ledger is N/A and proposed or absent guards earn no credit', () => {
  assert.equal(report([]).percent, null);
  assert.match(renderCoverage(report([])), /N\/A \(no rules\)/);
  assert.equal(
    coverageReport([receipt('missing', 'static', { guard })], () => {
      throw new Error('missing');
    }).mechanized,
    0,
  );
  assert.equal(
    coverageReport([receipt('missing', 'codebase', { guard })], () => 'changed source').mechanized,
    0,
  );
});

test('rejects malformed receipts, unknown levels and conflicting duplicate annotations', () => {
  assert.throws(() => report({}), /array/);
  assert.throws(() => report([receipt('bad', 'unknown')]), /level/);
  assert.throws(
    () => report([receipt('bad', 'static', { source: 'http://example.com' })]),
    /source/,
  );
  assert.throws(() => report([receipt('bad', 'prose', { guard })]), /only codebase\/static/);
  assert.throws(
    () => report([receipt('bad', 'static', { guard: { ...guard, anchor: '' } })]),
    /anchor/,
  );
  assert.throws(
    () => report([receipt('same rule', 'static'), receipt(' SAME RULE ', 'prose')]),
    /conflicting/,
  );
});

test('duplicate receipts cannot disagree on a guard violation baseline', () => {
  assert.throws(
    () =>
      report([
        receipt('same-rule', 'static', {
          guard: { ...guard, ratchet: { baseline: 'first.json' } },
        }),
        receipt('same-rule', 'static', {
          guard: { ...guard, ratchet: { baseline: 'second.json' } },
        }),
      ]),
    /conflicting coverage annotations/,
  );
});

test('rejects lost guards, rule removal and level downgrades even if aggregate coverage improves', () => {
  const baseline = report([
    receipt('retained', 'codebase', { guard }),
    receipt('pending', 'human'),
  ]);
  for (const rows of [
    [receipt('retained', 'codebase'), receipt('replacement', 'static', { guard })],
    [receipt('replacement', 'static', { guard })],
    [receipt('retained', 'static', { guard }), receipt('pending', 'human')],
  ])
    assert.throws(() => assertNoRegression(report(rows), baseline), /regression/i);
});

test('compares exact ratios overall and per level, allowing improvements and empty baselines', () => {
  const code = receipt('code', 'codebase', { guard });
  const lint = receipt('lint', 'static', { guard });
  const pending = receipt('pending', 'static');
  assert.throws(
    () => assertNoRegression(report([code, lint, pending]), report([code, lint])),
    /regression/i,
  );
  // Overall stays 2/3 while static coverage drops from 1/1 to 1/2.
  assert.throws(
    () =>
      assertNoRegression(
        report([code, lint, pending]),
        report([code, lint, receipt('old', 'human')]),
      ),
    /regression/i,
  );
  assert.doesNotThrow(() => assertNoRegression(report([code]), report([])));
  assert.doesNotThrow(() =>
    assertNoRegression(report([code, { ...pending, guard }]), report([code, pending])),
  );
  assert.doesNotThrow(() =>
    assertNoRegression(report([{ ...lint, level: 'codebase' }]), report([lint])),
  );
  assert.throws(() => assertNoRegression(report([code]), report([code, pending])), /removed rule/);
  assert.doesNotThrow(() => assertNoRegression(report([]), report([])));
});

test('CLI compares real Git snapshots; deleting a guard in head cannot lower its baseline', (t) => {
  const { root, ref } = fixtureRepo(t, [
    receipt('kept', 'static', { guard, classification: classification('static') }),
  ]);
  const summary = join(root, 'summary.md');
  assert.equal(
    runCoverage(['--base-ref', ref], { root, env: { GITHUB_STEP_SUMMARY: summary } }).percent,
    100,
  );
  assert.match(readFileSync(summary, 'utf8'), /LYB owner loop/);
  rmSync(join(root, guard.path));
  assert.throws(() => runCoverage(['--base-ref', ref], { root, env: {} }), /guard coverage/i);
  writeFileSync(join(root, guard.path), anchor);
  assert.throws(() => runCoverage(['--base-ref', 'f'.repeat(40)], { root, env: {} }));
  assert.throws(
    () => runCoverage(['--base-ref', 'HEAD;echo unsafe'], { root, env: {} }),
    /invalid baseline/,
  );
  assert.throws(() => readSource('../outside', { root }), /nonlocal/);
  assert.throws(() => runCoverage(['--unknown'], { root }), /usage/);
  const cli = fileURLToPath(new URL('./correction-coverage.mjs', import.meta.url));
  const result = spawnSync(process.execPath, [cli, '--unknown'], { encoding: 'utf8' });
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Correction coverage failed/);
  const success = spawnSync(process.execPath, [cli], {
    encoding: 'utf8',
    env: { ...process.env, GITHUB_STEP_SUMMARY: '' },
  });
  assert.equal(success.status, 0, success.stderr);
  assert.equal(JSON.parse(success.stdout).repository, 'JovieInc/LogYourBody');
});

test('CI rejects lessons without a retained guard or an explicit prose-only reason', (t) => {
  for (const row of [
    receipt('unclassified', undefined),
    receipt('pending', 'static'),
    receipt('pending-code', 'codebase'),
    receipt('unexplained', 'prose'),
    receipt('blank-reason', 'human', { proseOnlyReason: '  ' }),
    receipt('stale-anchor', 'static', { guard: { ...guard, anchor: 'a deleted guard anchor' } }),
    receipt('missing-file', 'codebase', { guard: { ...guard, path: 'missing.mjs' } }),
    receipt('mechanized-excuse', 'static', { guard, proseOnlyReason: 'Use human review.' }),
  ]) {
    const { root } = fixtureRepo(t, [
      { ...row, classification: classification(row.level ?? 'static') },
    ]);
    assert.throws(() => runCoverage([], { root, env: {} }), /guard coverage/i, row.fingerprint);
  }
});

test('CI accepts guarded lessons and justified prose/human lessons without inflating coverage', (t) => {
  const rows = [
    receipt('code', 'codebase', { guard }),
    receipt('lint', 'static', { guard }),
    receipt('judgment', 'human', { proseOnlyReason: 'Requires account-owner legal attestation.' }),
    receipt('writing', 'prose', { proseOnlyReason: 'Copy tone requires editorial judgment.' }),
  ];
  const { root } = fixtureRepo(
    t,
    rows.map(({ level, ...row }) => ({ ...row, classification: classification(level) })),
  );
  assert.equal(runCoverage([], { root, env: {} }).percent, 50);
  assert.throws(
    () => report([rows[3], { ...rows[3], proseOnlyReason: 'A different explanation.' }]),
    /conflicting/,
  );
});

const revision = 'a'.repeat(40);
const mainEnv = {
  LINEAR_API_KEY: 'fixture-key',
  GITHUB_REF: 'refs/heads/main',
  GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
  GITHUB_WORKFLOW_REF:
    'JovieInc/LogYourBody/.github/workflows/remediation-signal.yml@refs/heads/main',
  GITHUB_RUN_NUMBER: '100',
  GITHUB_RUN_ID: '1001',
  GITHUB_RUN_ATTEMPT: '1',
  REMEDIATION_RUN_URL: 'https://github.com/JovieInc/LogYourBody/actions/runs/1001',
};
const mainEvent = {
  repository: { full_name: 'JovieInc/LogYourBody' },
  workflow_run: {
    name: 'CI',
    path: '.github/workflows/ci.yml',
    workflow_id: 168687833,
    id: 1002,
    run_number: 101,
    run_attempt: 1,
    head_branch: 'main',
    event: 'push',
    conclusion: 'success',
    html_url: 'https://github.com/JovieInc/LogYourBody/actions/runs/1002',
  },
};

function ownerStore(options = {}) {
  const comments = [];
  const calls = [];
  const response = (data) => new Response(JSON.stringify({ data }));
  const fetchImpl = async (url, init) => {
    assert.equal(url, 'https://api.linear.app/graphql');
    assert.equal(init.headers.Authorization, 'fixture-key');
    const request = JSON.parse(init.body);
    calls.push(request);
    if (options.transport) throw new Error('offline');
    if (options.http) return new Response('', { status: 503 });
    if (options.graphql) return new Response(JSON.stringify({ errors: [{ message: 'fixture' }] }));
    if (request.query.includes('CorrectionCoverageOwner')) {
      assert.equal(request.variables.id, 'LYB-203');
      if (options.missing) return response({ issue: null });
      const paged = options.paginate && !request.variables.after;
      return response({
        issue: {
          id: 'lyb-owner-uuid',
          identifier: 'LYB-203',
          team: { key: options.foreign ? 'Jovie' : 'LYB' },
          comments: {
            nodes: paged ? [{ body: 'unrelated owner discussion' }] : comments,
            pageInfo: { hasNextPage: Boolean(paged || options.repeatedCursor), endCursor: 'next' },
          },
        },
      });
    }
    assert.match(request.query, /AddLinearIssueComment/);
    assert.equal(request.variables.id, 'lyb-owner-uuid');
    if (options.rejectCreate) return response({ commentCreate: { success: false } });
    comments.push({ body: request.variables.body });
    return response({ commentCreate: { success: true, comment: { id: 'new-comment' } } });
  };
  return { comments, calls, fetchImpl };
}

test('owner-loop adapter posts the complete metric to LYB only and deduplicates through all comment pages', async () => {
  const store = ownerStore({ paginate: true });
  const body = renderCoverage(
    report([receipt('code', 'codebase', { guard }), receipt('copy', 'prose')]),
  );
  const args = { revision, body, apiKey: mainEnv.LINEAR_API_KEY, fetchImpl: store.fetchImpl };
  assert.equal((await postCoverageComment(args)).action, 'posted');
  assert.equal((await postCoverageComment(args)).action, 'unchanged');
  assert.equal(store.comments.length, 1);
  assert.match(store.comments[0].body, /Overall \| 1\/2 \| 50.00%/);
  assert.match(store.comments[0].body, new RegExp(`/commit/${revision}`));
  assert.deepEqual(store.calls.map((call) => call.variables.after).filter(Boolean), [
    'next',
    'next',
  ]);
});

test('owner-loop adapter reports credentials, wrong team, incomplete reads and provider failures truthfully', async () => {
  const args = { revision, body: renderCoverage(report([])), apiKey: 'fixture-key' };
  const noNetwork = () => {
    throw new Error('unexpected network');
  };
  assert.equal(
    (await postCoverageComment({ ...args, apiKey: '', fetchImpl: noNetwork })).reason,
    'missing_linear_api_key',
  );
  assert.equal(
    (await postCoverageComment({ ...args, revision: 'invalid', fetchImpl: noNetwork })).reason,
    'invalid_source_revision',
  );
  for (const options of [
    { foreign: true },
    { missing: true },
    { repeatedCursor: true },
    { transport: true },
    { http: true },
    { graphql: true },
    { rejectCreate: true },
  ]) {
    const store = ownerStore(options);
    assert.equal((await postCoverageComment({ ...args, fetchImpl: store.fetchImpl })).ok, false);
    assert.equal(store.comments.length, 0);
  }
});

test('existing main intake posts on CI completion and scheduled/manual owner loops; PRs and foreign sources cannot post', async (t) => {
  const { root } = fixtureRepo(t, []);
  for (const eventName of ['workflow_run', 'schedule', 'workflow_dispatch']) {
    const store = ownerStore();
    const result = await runCoverageOwnerLoop({
      env: mainEnv,
      root,
      eventName,
      event: mainEvent,
      fetchImpl: store.fetchImpl,
    });
    assert.equal(result.action, 'posted', result.reason);
    assert.match(store.comments[0].body, /N\/A \(no rules\)/);
  }
  const store = ownerStore();
  for (const options of [
    { eventName: 'pull_request' },
    { env: { ...mainEnv, GITHUB_REF: 'refs/heads/feature' } },
    { event: { ...mainEvent, repository: { full_name: 'Other/Repo' } } },
    {
      event: { ...mainEvent, workflow_run: { ...mainEvent.workflow_run, head_branch: 'feature' } },
    },
    {
      event: {
        ...mainEvent,
        workflow_run: {
          ...mainEvent.workflow_run,
          name: 'Deploy',
          path: '.github/workflows/deploy.yml',
          workflow_id: 168687834,
        },
      },
    },
  ]) {
    const result = await runCoverageOwnerLoop({
      env: mainEnv,
      eventName: 'workflow_run',
      event: mainEvent,
      fetchImpl: store.fetchImpl,
      ...options,
    });
    assert.equal(result.action, 'skip');
  }
  assert.equal(
    (await runCoverageOwnerLoop({ env: { ...mainEnv, REMEDIATION_INTAKE_DISABLED: '1' } })).action,
    'disabled',
  );
  assert.equal(store.calls.length, 0);
});

test('failed owner-loop publication is visible in the job summary and never reported as posted', async (t) => {
  const { root } = fixtureRepo(t, []);
  const summary = join(root, 'summary.md');
  const result = await runCoverageOwnerLoop({
    env: { ...mainEnv, LINEAR_API_KEY: '', GITHUB_STEP_SUMMARY: summary },
    root,
    eventName: 'workflow_run',
    event: mainEvent,
  });
  assert.equal(result.ok, false);
  assert.match(readFileSync(summary, 'utf8'), /did NOT post: missing_linear_api_key/);
});

test('real CI and intake entrypoints retain coverage checking and publication wiring', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const workflow = readFileSync(join(root, '.github/workflows/ci.yml'), 'utf8');
  assert.match(
    workflow,
    /node --test packages\/shared-lib\/scripts\/correction-coverage.behavior.mjs/,
  );
  assert.match(workflow, /git fetch --no-tags --depth=1 origin "\$BASE_SHA"/);
  assert.match(workflow, /correction-coverage.mjs --base-ref "\$BASE_SHA"/);
  assert.match(
    workflow,
    /node --test packages\/shared-lib\/scripts\/correction-ratchet.behavior.mjs/,
  );
  assert.match(workflow, /correction-ratchet.mjs --base-ref "\$BASE_SHA"/);
  assert.match(workflow, /github.event.merge_group.base_sha/);
  assert.match(
    workflow,
    /node --test packages\/shared-lib\/scripts\/jovie-separation.behavior.mjs/,
  );
  assert.match(workflow, /node packages\/shared-lib\/scripts\/jovie-separation.mjs/);
  assert.match(
    readFileSync(join(root, '.github/scripts/remediation-signal-intake.mjs'), 'utf8'),
    /await runCoverageOwnerLoop\(/,
  );
});
