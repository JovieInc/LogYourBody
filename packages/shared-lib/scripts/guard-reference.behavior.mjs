import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { LEDGER_PATH } from './correction-coverage.mjs';
import { BASELINE_PATH, runGuardReferences, SCHEMA } from './guard-reference.mjs';

const cli = fileURLToPath(new URL('./guard-reference.mjs', import.meta.url));
const repoRoot = fileURLToPath(new URL('../../..', import.meta.url));

const receipt = (fingerprint, path) => ({
  fingerprint,
  correction: 'Keep the referenced guard in the repository.',
  source: `https://github.com/JovieInc/LogYourBody/pull/42#${encodeURIComponent(fingerprint.trim())}`,
  mechanization: 'Point the ledger entry at a test, lint rule, or CI step that exists.',
  ...(path ? { guard: { path } } : {}),
});

function fixture(t, { receipts, baseline = [], files = {}, commitBaseline = true } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'lyb-guard-reference-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const put = (path, value) => {
    mkdirSync(dirname(join(root, path)), { recursive: true });
    writeFileSync(join(root, path), value);
  };
  const json = (path, value) => put(path, `${JSON.stringify(value, null, 2)}\n`);
  const git = (...args) =>
    execFileSync(
      'git',
      [
        '-c',
        'user.email=fixture@example.com',
        '-c',
        'user.name=Fixture',
        '-c',
        'commit.gpgsign=false',
        '-c',
        'core.hooksPath=/dev/null',
        ...args,
      ],
      { cwd: root, encoding: 'utf8', stdio: 'pipe' },
    ).trim();
  git('init', '-q');
  const rows = receipts ?? [receipt('kept-test', 'tests/kept.test.mjs')];
  json(LEDGER_PATH, rows);
  put('tests/kept.test.mjs', 'kept guard\n');
  for (const [path, value] of Object.entries(files)) put(path, value);
  if (commitBaseline) json(BASELINE_PATH, { schema: SCHEMA, unguarded: baseline });
  git('add', '.');
  git('commit', '-qm', 'fixture');
  const ref = git('rev-parse', 'HEAD');
  const warnings = [];
  const run = (args = ['--base-ref', ref]) =>
    runGuardReferences(args, { root, env: {}, warn: (line) => warnings.push(line) });
  return { root, put, json, git, ref, run, warnings };
}

test('deleted guard fails with the entry id and path', (t) => {
  const missing = [
    ['deleted-test', 'tests/deleted.test.mjs'],
    ['deleted-lint-rule', 'tools/lint/deleted-rule.js'],
    ['deleted-ci-step', '.github/workflows/deleted-step.yml'],
  ];
  const f = fixture(t, { receipts: missing.map(([id, path]) => receipt(id, path)) });
  let error;
  try {
    f.run();
  } catch (caught) {
    error = caught;
  }
  assert.ok(error, 'expected a missing guard to fail');
  for (const [id, path] of missing) {
    assert.match(
      error.message,
      new RegExp(`guard reference missing: ${id} ${path.replaceAll('.', '\\.')}`),
    );
  }
  const probe = spawnSync(
    process.execPath,
    [
      '--input-type=module',
      '--eval',
      `
        import { runGuardReferences } from ${JSON.stringify(pathToFileURL(cli).href)};
        try {
          runGuardReferences(['--base-ref', process.env.REF], { root: process.env.ROOT, warn() {} });
        } catch (error) {
          console.error('Guard reference check failed: ' + error.message);
          process.exit(1);
        }
      `,
    ],
    { encoding: 'utf8', env: { ...process.env, REF: f.ref, ROOT: f.root } },
  );
  assert.equal(probe.status, 1);
  assert.match(probe.stderr, /Guard reference check failed:/);
  assert.match(probe.stderr, /guard reference missing: deleted-test tests\/deleted\.test\.mjs/);
  assert.match(
    probe.stderr,
    /guard reference missing: deleted-lint-rule tools\/lint\/deleted-rule\.js/,
  );
  assert.match(
    probe.stderr,
    /guard reference missing: deleted-ci-step \.github\/workflows\/deleted-step\.yml/,
  );
});

test('existing test, lint rule and CI step paths pass', (t) => {
  const present = [
    ['kept-test', 'tests/kept.test.mjs'],
    ['kept-lint-rule', 'tools/lint/no-bare-catch.js'],
    ['kept-ci-step', '.github/scripts/kept-step.mjs'],
  ];
  const f = fixture(t, {
    receipts: present.map(([id, path]) => receipt(id, path)),
    files: {
      'tools/lint/no-bare-catch.js': 'export const rule = true;\n',
      '.github/scripts/kept-step.mjs': 'export const step = true;\n',
    },
  });
  const report = f.run();
  assert.equal(report.checked, 3);
  assert.deepEqual(report.unguarded, []);
  assert.equal(f.warnings.length, 0);
});

test('unguarded entries warn and the baseline file can only shrink', (t) => {
  const f = fixture(t, {
    receipts: [receipt('prose-only'), receipt('kept-test', 'tests/kept.test.mjs')],
    baseline: ['prose-only'],
  });
  const report = f.run();
  assert.deepEqual(report.unguarded, ['prose-only']);
  assert.match(f.warnings[0], /::warning::LYB guard reference prose-only: no guard reference/);
  f.json(LEDGER_PATH, [
    receipt('prose-only'),
    receipt('new-prose'),
    receipt('kept-test', 'tests/kept.test.mjs'),
  ]);
  f.json(BASELINE_PATH, { schema: SCHEMA, unguarded: ['new-prose', 'prose-only'] });
  assert.throws(() => f.run(), /guard reference baseline growth: new-prose/);
  f.json(LEDGER_PATH, [receipt('kept-test', 'tests/kept.test.mjs')]);
  f.json(BASELINE_PATH, { schema: SCHEMA, unguarded: [] });
  f.warnings.length = 0;
  assert.deepEqual(f.run().unguarded, []);
  assert.equal(f.warnings.length, 0);
});

test('a new baseline cannot grandfather unguarded entries', (t) => {
  const f = fixture(t, { receipts: [receipt('open-rule')], commitBaseline: false });
  f.json(BASELINE_PATH, { schema: SCHEMA, unguarded: ['open-rule'] });
  assert.throws(() => f.run(), /guard reference baseline growth: open-rule/);
  f.json(LEDGER_PATH, [receipt('kept-test', 'tests/kept.test.mjs')]);
  f.json(BASELINE_PATH, { schema: SCHEMA, unguarded: [] });
  assert.deepEqual(f.run().unguarded, []);
});

test('stale, unsorted and malformed baselines fail closed', (t) => {
  const f = fixture(t, {
    receipts: [receipt('prose-only'), receipt('kept-test', 'tests/kept.test.mjs')],
    baseline: ['prose-only'],
  });
  f.json(LEDGER_PATH, [receipt('kept-test', 'tests/kept.test.mjs')]);
  assert.throws(() => f.run(), /stale guard reference baseline: prose-only/);
  f.json(LEDGER_PATH, [receipt('prose-only'), receipt('kept-test', 'tests/kept.test.mjs')]);
  f.json(BASELINE_PATH, { schema: SCHEMA, unguarded: [] });
  assert.throws(() => f.run(), /no baseline allowance: prose-only/);
  for (const value of [
    '',
    '{broken',
    'null',
    JSON.stringify({ schema: 'other', unguarded: [] }),
    JSON.stringify({ schema: SCHEMA, unguarded: ['prose-only'], extra: true }),
    JSON.stringify({ schema: SCHEMA, unguarded: ['Prose-Only'] }),
    JSON.stringify({ schema: SCHEMA, unguarded: ['prose-only', 'prose-only'] }),
    JSON.stringify({ schema: SCHEMA, unguarded: ['prose-only', 'kept-test'] }),
    JSON.stringify({ schema: SCHEMA, unguarded: ['kept-test', 'prose-only'] }),
  ]) {
    f.put(BASELINE_PATH, value);
    assert.throws(() => f.run(), /baseline|JSON|allowance|growth|stale/);
  }
  f.json(BASELINE_PATH, { schema: SCHEMA, unguarded: ['prose-only'] });
  const summary = join(f.root, 'summary.md');
  runGuardReferences(['--base-ref', f.ref], {
    root: f.root,
    env: { GITHUB_STEP_SUMMARY: summary },
    warn() {},
  });
  assert.match(readFileSync(summary, 'utf8'), /prose-only/);
});

test('symlink, directory and nonlocal guard paths fail closed', (t) => {
  const f = fixture(t);
  symlinkSync('kept.test.mjs', join(f.root, 'tests/linked.test.mjs'));
  f.json(LEDGER_PATH, [receipt('linked-guard', 'tests/linked.test.mjs')]);
  assert.throws(() => f.run(), /guard reference missing: linked-guard tests\/linked.test.mjs/);
  mkdirSync(join(f.root, 'tests/guard-dir'));
  f.json(LEDGER_PATH, [receipt('directory-guard', 'tests/guard-dir')]);
  assert.throws(() => f.run(), /guard reference missing: directory-guard tests\/guard-dir/);
  f.json(LEDGER_PATH, [receipt('outside-guard', '../outside.test.mjs')]);
  assert.throws(() => f.run(), /nonlocal guard path: outside-guard \.\.\/outside\.test\.mjs/);
  f.json(LEDGER_PATH, [receipt('blank-guard', ' ')]);
  assert.throws(() => f.run(), /guard reference missing: blank-guard \(no path\)/);
  f.json(LEDGER_PATH, [{ ...receipt('claimed-without-path'), guard: { anchor: 'not-a-path' } }]);
  assert.throws(() => f.run(), /guard reference missing: claimed-without-path \(no path\)/);
});

test('duplicate receipts share one id and conflicting paths fail', (t) => {
  const f = fixture(t, { receipts: [receipt('open rule')], baseline: ['open-rule'] });
  f.json(LEDGER_PATH, [
    receipt('open rule'),
    { ...receipt('open-rule'), source: 'https://github.com/JovieInc/LogYourBody/pull/42#second' },
  ]);
  assert.deepEqual(f.run().unguarded, ['open-rule']);
  f.json(LEDGER_PATH, [
    receipt('open-rule', 'tests/kept.test.mjs'),
    { ...receipt('open-rule'), source: 'https://github.com/JovieInc/LogYourBody/pull/42#second' },
  ]);
  assert.throws(() => f.run(), /conflicting guard reference: open-rule/);
});

test('the repository check finishes within 30 seconds and CI runs it on the existing job', () => {
  const started = Date.now();
  const report = runGuardReferences([], { env: {}, warn() {} });
  const elapsed = Date.now() - started;
  assert.ok(elapsed < 30_000, `guard reference check took ${elapsed}ms`);
  assert.equal(report.unguarded.length, 0);
  assert.ok(report.checked > 0);
  const workflow = readFileSync(join(repoRoot, '.github/workflows/ci.yml'), 'utf8');
  assert.match(
    workflow,
    /correction-ratchet\.mjs --base-ref "\$BASE_SHA"\n\s+node packages\/shared-lib\/scripts\/guard-reference\.mjs --base-ref "\$BASE_SHA"/,
  );
  assert.match(
    workflow,
    /node --test packages\/shared-lib\/scripts\/guard-reference\.behavior\.mjs/,
  );
  const failure = spawnSync(process.execPath, [cli, '--unknown'], { encoding: 'utf8' });
  assert.equal(failure.status, 1);
  assert.match(failure.stderr, /Guard reference check failed: usage/);
  const success = spawnSync(process.execPath, [cli], {
    encoding: 'utf8',
    env: { ...process.env, GITHUB_STEP_SUMMARY: '' },
  });
  assert.equal(success.status, 0, success.stderr);
  assert.equal(JSON.parse(success.stdout).unguarded.length, 0);
});
