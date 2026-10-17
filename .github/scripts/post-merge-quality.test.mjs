// Behavioral contract for ios-post-merge-quality.yml: the workflow wiring, the
// post-merge scope (detect-changes.sh from the last verified SHA) and the report
// script that opens, updates or closes the post-merge-lq-red hold issue.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const reportScript = path.join(scriptDir, 'post-merge-quality-report.sh');
const detectScript = path.join(scriptDir, 'detect-changes.sh');
const workflow = fs.readFileSync(path.join(scriptDir, '../workflows/ios-post-merge-quality.yml'), 'utf8');

// Fixture git must not inherit a hook's GIT_DIR/GIT_INDEX_FILE.
const gitEnv = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_')));
Object.assign(gitEnv, {
  GIT_AUTHOR_NAME: 'ci',
  GIT_AUTHOR_EMAIL: 'ci@example.com',
  GIT_COMMITTER_NAME: 'ci',
  GIT_COMMITTER_EMAIL: 'ci@example.com',
  GIT_CONFIG_NOSYSTEM: '1',
  GIT_CONFIG_GLOBAL: '/dev/null',
});

const git = (cwd, ...args) => execFileSync('git', args, { cwd, env: gitEnv, encoding: 'utf8' }).trim();

function jobBlock(name) {
  const start = workflow.indexOf(`\n  ${name}:\n`);
  assert.notEqual(start, -1, `ios-post-merge-quality.yml has no ${name} job`);
  const rest = workflow.slice(start + 1);
  const end = rest.slice(1).search(/\n {2}[A-Za-z0-9_-]+:\n/);
  return end === -1 ? rest : rest.slice(0, end + 1);
}

test('runs on main pushes, latest SHA only, retrying once before reporting', () => {
  assert.match(workflow, /on:\n {2}push:\n {4}branches: \[main\]\n {2}workflow_dispatch:/);
  assert.match(workflow, /concurrency:[\s\S]*group: ios-post-merge-quality\n {2}cancel-in-progress: true/);

  const scope = jobBlock('scope');
  assert.match(scope, /ios-post-merge-quality\.yml\/runs\?branch=main&status=success&per_page=1/);
  assert.match(scope, /BASE_SHA: \$\{\{ steps\.base\.outputs\.sha \}\}/);
  assert.match(scope, /GITHUB_EVENT_NAME: post_merge/);
  assert.match(scope, /run: bash \.github\/scripts\/detect-changes\.sh/);

  for (const name of ['quality', 'retry']) {
    const job = jobBlock(name);
    assert.match(job, /uses: \.\/\.github\/workflows\/ios-quality\.yml/, name);
    assert.match(job, /checkout-ref: \$\{\{ github\.sha \}\}/, name);
    assert.match(job, /mac-first: true/, name);
  }
  assert.match(jobBlock('quality'), /if: needs\.scope\.outputs\.ios == 'true'/);
  assert.match(jobBlock('retry'), /if: \$\{\{ !cancelled\(\) && needs\.quality\.result == 'failure' \}\}/);

  const report = jobBlock('report');
  assert.match(report, /needs: \[scope, quality, retry\]/);
  assert.match(report, /if: \$\{\{ always\(\) && needs\.scope\.outputs\.ios == 'true' \}\}/);
  assert.match(report, /issues: write/);
  assert.match(report, /QUALITY_RESULT: \$\{\{ needs\.quality\.result \}\}/);
  assert.match(report, /RETRY_RESULT: \$\{\{ needs\.retry\.result \}\}/);
  assert.match(report, /run: bash \.github\/scripts\/post-merge-quality-report\.sh/);
});

const headSha = 'abcdef1234567890'.padEnd(40, '0');
const newerSha = 'f'.repeat(40);

// gh fake: issue list and live main ref responses; every call is recorded.
function report(env, { open = '', main = headSha, mainStatus = 0 } = {}) {
  const bin = fs.mkdtempSync(path.join(os.tmpdir(), 'pmq-bin-'));
  const calls = path.join(bin, 'calls');
  const output = path.join(bin, 'output');
  fs.writeFileSync(output, '');
  const list = open === null ? 'exit 1' : `printf '%b' ${JSON.stringify(open)}`;
  fs.writeFileSync(
    path.join(bin, 'gh'),
    `#!/usr/bin/env bash
echo "$*" >> ${JSON.stringify(calls)}
case "$*" in
  *"issues?labels=post-merge-lq-red&state=open"*) ${list} ;;
  *"git/ref/heads/main"*) printf '%s\\n' "$FIXTURE_MAIN_SHA"; exit "$FIXTURE_MAIN_STATUS" ;;
esac
`,
    { mode: 0o755 },
  );
  const result = spawnSync('bash', [reportScript], {
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      HEAD_SHA: headSha,
      RUN_URL: 'https://github.com/JovieInc/LogYourBody/actions/runs/1',
      GITHUB_OUTPUT: output,
      FIXTURE_MAIN_SHA: main,
      FIXTURE_MAIN_STATUS: String(mainStatus),
      ...env,
    },
  });
  const recorded = fs.existsSync(calls) ? fs.readFileSync(calls, 'utf8').trim().split('\n') : [];
  return { status: result.status, calls: recorded, out: result.stdout + result.stderr, output: fs.readFileSync(output, 'utf8') };
}

const writes = (calls) => calls.filter((call) => /-X (POST|PATCH)|label create/.test(call));

test('a pass closes every open hold issue', () => {
  const first = report({ QUALITY_RESULT: 'success', RETRY_RESULT: 'skipped' }, { open: '7\n9' });
  assert.equal(first.status, 0);
  assert.equal(writes(first.calls).filter((call) => /issues\/(7|9) -f state=closed/.test(call)).length, 2);

  const retried = report({ QUALITY_RESULT: 'failure', RETRY_RESULT: 'success' }, { open: '7' });
  assert.equal(retried.status, 0);
  assert.ok(retried.calls.some((call) => /issues\/7 -f state=closed/.test(call)));

  const clean = report({ QUALITY_RESULT: 'success', RETRY_RESULT: 'skipped' });
  assert.equal(clean.status, 0);
  assert.deepEqual(writes(clean.calls), []);
});

test('two failures open the hold issue, or update the open one, and fail the run', () => {
  const opened = report({ QUALITY_RESULT: 'failure', RETRY_RESULT: 'failure' });
  assert.equal(opened.status, 1);
  const create = opened.calls.find((call) => /-X POST repos\/JovieInc\/LogYourBody\/issues /.test(call));
  assert.ok(create, opened.calls.join('\n'));
  assert.match(create, /labels\[\]=post-merge-lq-red/);
  assert.match(create, /abcdef123456/);

  const updated = report({ QUALITY_RESULT: 'failure', RETRY_RESULT: 'failure' }, { open: '7' });
  assert.equal(updated.status, 1);
  assert.ok(updated.calls.some((call) => /-X POST repos\/JovieInc\/LogYourBody\/issues\/7\/comments/.test(call)));
  assert.ok(!updated.calls.some((call) => /-X POST repos\/JovieInc\/LogYourBody\/issues /.test(call)));
  assert.ok(!updated.calls.some((call) => /state=closed/.test(call)));
});

test('an unfinished attempt changes nothing and is not recorded as verified', () => {
  for (const [first, retry] of [
    ['failure', 'cancelled'],
    ['failure', 'skipped'],
    ['cancelled', 'skipped'],
  ]) {
    const result = report({ QUALITY_RESULT: first, RETRY_RESULT: retry }, { open: '7' });
    assert.equal(result.status, 1, `${first}/${retry}`);
    assert.deepEqual(writes(result.calls), [], `${first}/${retry}`);
  }
});

test('a superseded cancellation succeeds without touching issues or verifying the SHA', () => {
  for (const open of ['', '7']) {
    const result = report({ QUALITY_RESULT: 'cancelled', RETRY_RESULT: 'skipped' }, { open, main: newerSha });
    assert.equal(result.status, 0, result.out);
    assert.deepEqual(result.calls, ['api repos/JovieInc/LogYourBody/git/ref/heads/main --jq .object.sha']);
    assert.match(result.out, /superseded/i);
    assert.match(result.out, /not recording abcdef123456 as verified/);
    assert.doesNotMatch(result.out, /Launch Quality passed/);
    assert.equal(result.output, '');
  }
});

test('a cancellation at the current main tip still fails closed', () => {
  const result = report({ QUALITY_RESULT: 'cancelled', RETRY_RESULT: 'skipped' });
  assert.equal(result.status, 1, result.out);
  assert.deepEqual(writes(result.calls), []);
  assert.match(result.out, /result unknown/);
});

test('a cancellation with an unreadable or malformed main ref still fails closed', () => {
  for (const lookup of [
    { main: '', mainStatus: 1 },
    { main: newerSha, mainStatus: 1 },
    { main: '' },
    { main: 'null' },
    { main: 'not-a-sha' },
    { main: newerSha.slice(0, 12) },
  ]) {
    const result = report({ QUALITY_RESULT: 'cancelled', RETRY_RESULT: 'skipped' }, { open: '7', ...lookup });
    assert.equal(result.status, 1, JSON.stringify(lookup));
    assert.deepEqual(writes(result.calls), []);
  }
});

test('supersession never excuses a failure or another unknown result', () => {
  for (const [first, retry] of [
    ['failure', 'failure'],
    ['failure', 'cancelled'],
    ['failure', 'skipped'],
    ['cancelled', 'failure'],
    ['skipped', 'skipped'],
  ]) {
    const result = report({ QUALITY_RESULT: first, RETRY_RESULT: retry }, { open: '7', main: newerSha });
    assert.equal(result.status, 1, `${first}/${retry}`);
    assert.ok(!result.calls.some((call) => call.includes('git/ref/heads/main')), 'only cancelled/skipped needs the main ref');
    if (first === 'failure' && retry === 'failure') {
      assert.ok(result.calls.some((call) => /-X POST .*issues\/7\/comments/.test(call)));
    } else {
      assert.deepEqual(writes(result.calls), []);
    }
  }
});

test('an unlistable issue state never opens a duplicate and never releases the hold', () => {
  const passed = report({ QUALITY_RESULT: 'success', RETRY_RESULT: 'skipped' }, { open: null });
  assert.equal(passed.status, 0);
  assert.deepEqual(writes(passed.calls), []);
  const failed = report({ QUALITY_RESULT: 'failure', RETRY_RESULT: 'failure' }, { open: null });
  assert.equal(failed.status, 1);
  assert.deepEqual(writes(failed.calls), []);
});

// The scope step: detect-changes.sh diffs the last verified main SHA against this one.
function scope(files, { base } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pmq-scope-'));
  const origin = path.join(root, 'origin');
  fs.mkdirSync(origin);
  git(origin, 'init', '-q', '-b', 'main');
  git(origin, 'config', 'uploadpack.allowAnySHA1InWant', 'true');
  fs.mkdirSync(path.join(origin, 'apps/ios'), { recursive: true });
  fs.writeFileSync(path.join(origin, 'apps/ios/App.swift'), 'v1');
  git(origin, 'add', '-A');
  git(origin, 'commit', '-q', '-m', 'verified');
  const verified = git(origin, 'rev-parse', 'HEAD');
  for (const [file, content] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(origin, file)), { recursive: true });
    fs.writeFileSync(path.join(origin, file), content);
  }
  git(origin, 'add', '-A');
  git(origin, 'commit', '-q', '-m', 'merged');
  const head = git(origin, 'rev-parse', 'HEAD');
  const workspace = path.join(root, 'workspace');
  git(root, 'clone', '-q', '--depth=1', '--no-tags', `file://${origin}`, workspace);
  const output = path.join(root, 'output');
  fs.writeFileSync(output, '');
  const result = spawnSync('bash', [detectScript], {
    cwd: workspace,
    encoding: 'utf8',
    env: {
      ...gitEnv,
      GITHUB_OUTPUT: output,
      GITHUB_EVENT_NAME: 'post_merge',
      BASE_SHA: base === undefined ? verified : base,
      HEAD_SHA: head,
    },
  });
  assert.equal(result.status, 0, result.stderr);
  return Object.fromEntries(
    fs
      .readFileSync(output, 'utf8')
      .trim()
      .split('\n')
      .map((line) => line.split('=')),
  ).ios_changed;
}

test('post-merge scope checks only iOS changes since the last verified SHA', () => {
  assert.equal(scope({ 'apps/ios/App.swift': 'v2' }), 'true');
  assert.equal(scope({ 'apps/web/page.tsx': 'v2' }), 'false');
  // No verified run yet, or an unfetchable one: check everything.
  assert.equal(scope({ 'apps/web/page.tsx': 'v2' }, { base: '' }), 'true');
  assert.equal(scope({ 'apps/web/page.tsx': 'v2' }, { base: 'f'.repeat(40) }), 'true');
});
