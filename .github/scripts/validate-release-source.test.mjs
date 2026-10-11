import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { selectReleaseRun, validateReleaseRun } from './validate-release-checks.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const sha = '472dd68fb9b3bd9c46cf54a5fa43fc2236dda5a0';
const repository = 'JovieInc/LogYourBody';
const required = 'CI Summary,JavaScript/TypeScript,iOS';
const run = (overrides = {}) => ({
  id: 36812547213, run_attempt: 1, head_sha: sha, head_branch: 'main',
  path: '.github/workflows/ci.yml', repository: { full_name: repository },
  event: 'push', created_at: '2026-10-01T03:53:07Z', status: 'completed',
  conclusion: 'success', ...overrides,
});
const queue = run({ id: 36810330781, event: 'merge_group',
  head_branch: 'gh-readonly-queue/main/pr-1173-85f05134529c700fdbc74dcee5b026f3329359e0',
  created_at: '2026-10-01T03:24:05Z' });
const pages = (...runs) => [{ workflow_runs: runs }];
const jobs = (selected = run()) => [{ jobs: required.split(',').map((name, index) => ({
  id: 110210600000 + index, name, run_id: selected.id, run_attempt: selected.run_attempt,
  head_sha: selected.head_sha, status: 'completed', conclusion: 'success',
})) }];
const selected = (runs, event = 'workflow_dispatch') => selectReleaseRun(runs, sha, repository, event);

test('main run dominates complete same-source queue proof, including pending or failed main', () => {
  for (const override of [{ status: 'in_progress', conclusion: null }, { conclusion: 'failure' }]) {
    const current = run(override);
    assert.equal(selected(pages(queue, current)).id, current.id);
    assert.notEqual(validateReleaseRun(current, jobs(), required).status, 'passed');
  }
});
test('complete same-run push and whole queue reuse pass; missing runs remain pending', () => {
  for (const current of [run(), queue]) {
    assert.equal(selected({ workflow_runs: [current] }).id, current.id);
    assert.equal(validateReleaseRun(current, jobs(current), required).status, 'passed');
  }
  assert.equal(selected(pages()), null);
  assert.equal(selected(pages(queue), 'push'), null);
  assert.equal(selected(pages(run()), 'push').event, 'push');
  assert.throws(() => selected(pages(run()), 'pull_request'));
  assert.equal(validateReleaseRun(null, [], required).status, 'pending');
});
test('newest main creation and latest attempt win, rather than newest job completion', () => {
  const older = run({ id: 1, created_at: '2026-09-01T00:00:00Z' });
  assert.equal(selected(pages(run(), older, queue)).id, run().id);
  assert.equal(selected(pages(run(), run({ run_attempt: 2 }))).run_attempt, 2);
  assert.equal(selected(pages(run({ id: 2 }), run({ id: 3 }))).id, 3);
});
test('wrong source/repository/workflow/event/branch cannot become release proof', () => {
  for (const override of [
    { head_sha: 'a'.repeat(40) }, { repository: { full_name: 'other/repo' } },
    { path: '.github/workflows/deploy.yml' }, { event: 'pull_request' },
    { head_branch: 'feature' }, { event: 'merge_group', head_branch: 'feature' },
  ]) assert.equal(selected(pages(run(override))), null);
});
test('malformed run metadata and source fail closed', () => {
  for (const value of [null, [], {}, [{}]]) assert.throws(() => selected(value));
  for (const invalid of [undefined, 'not-a-sha', 'z'.repeat(40), sha + '\n']) {
    assert.throws(() => selectReleaseRun(pages(run()), invalid, repository, 'push'));
  }
  for (const override of [{ id: -1 }, { id: 1.5 }, { run_attempt: 0 }, { created_at: '' }]) {
    assert.throws(() => selected(pages(run(override))));
  }
});
test('incomplete same-source provenance cannot conceal a newer push and enable queue fallback', () => {
  for (const field of ['repository', 'path', 'event', 'head_branch']) {
    for (const value of [undefined, null, '', 42, ' ', 'main\n']) {
      const current = run({ [field]: field === 'repository' ? { full_name: value } : value });
      assert.throws(() => selected(pages(queue, current)), /provenance/);
    }
  }
  for (const override of [{ repository: { full_name: 'invalid' } }, { path: 'invalid' },
    { event: ' push ' }, { head_branch: 'bad branch' }]) {
    assert.throws(() => selected(pages(queue, run(override))), /provenance/);
  }
  for (const current of [null, run({ head_sha: '' }), run({ head_sha: 42 }), run({ head_sha: 'z'.repeat(40) }), run({ head_sha: sha + '\n' })]) {
    assert.throws(() => selected(pages(queue, current)), /source metadata/);
  }
});
test('run failure or cancellation cannot be replaced by successful required jobs', () => {
  for (const conclusion of ['failure', 'cancelled', 'skipped', null]) {
    assert.equal(validateReleaseRun(run({ conclusion }), jobs(), required).status, 'failed');
  }
});
test('all required jobs must come from the selected source, run and latest attempt', () => {
  for (const override of [{ run_id: queue.id }, { head_sha: 'a'.repeat(40) }, { run_attempt: 2 }]) {
    const fixture = jobs(); Object.assign(fixture[0].jobs[0], override);
    assert.throws(() => validateReleaseRun(run(), fixture, required));
  }
  assert.throws(() => validateReleaseRun(run(), {}, required));
});
test('missing/ambiguous/failed/incomplete required jobs and skipped summary reject', () => {
  for (const mutate of [
    (list) => list.pop(), (list) => list.push({ ...list[0] }),
    (list) => { list[0].conclusion = 'failure'; },
    (list) => { list[0].status = 'in_progress'; },
    (list) => { list[0].conclusion = 'skipped'; },
  ]) {
    const fixture = jobs(); mutate(fixture[0].jobs);
    assert.equal(validateReleaseRun(run(), fixture, required).status, 'failed');
  }
  assert.throws(() => validateReleaseRun(run(), jobs(), 'iOS'));
});
test('unchanged optional surface skips and paginated jobs preserve existing contract', () => {
  const fixture = jobs(); fixture[0].jobs[1].conclusion = 'skipped';
  const split = [{ jobs: fixture[0].jobs.slice(0, 1) }, { jobs: fixture[0].jobs.slice(1) }];
  assert.equal(validateReleaseRun(run(), split, ' CI Summary, JavaScript/TypeScript, iOS, ').status, 'passed');
});

// Reconstructed04:12:43 snapshot from actual run/check timestamps retained privately.
// Current main Summary did not exist yet; only the earlier queue Summary was green.
const mixed = {
  runs: pages(queue, run({ status: 'in_progress', conclusion: null })),
  jobs: jobs(),
  checks: [
    ['CI Summary', 'completed', 'success', '2026-10-01T03:52:37Z', '110210430723'],
    ['JavaScript/TypeScript', 'completed', 'success', '2026-10-01T03:56:50Z', '110210606956'],
    ['iOS', 'completed', 'success', '2026-10-01T04:12:28Z', '110210606981'],
  ],
};
function realShell(fixture, extra = {}) {
  const directory = mkdtempSync(join(tmpdir(), 'lyb-release-source-'));
  const fixturePath = join(directory, 'api.json');
  writeFileSync(fixturePath, JSON.stringify(fixture));
  const gh = join(directory, 'gh');
  writeFileSync(gh, `#!/usr/bin/env node
const fs = require('node:fs');
const d = JSON.parse(fs.readFileSync(process.env.LYB_TEST_API_FIXTURE, 'utf8'));
const endpoint = process.argv[3];
const failure = process.env.LYB_TEST_GH_FAIL;
if (failure === 'true' || (failure === 'runs' && endpoint.includes('/workflows/')) ||
    (failure === 'jobs' && endpoint.includes('/jobs?'))) process.exit(1);
if (endpoint.endsWith('/status')) console.log('pending');
else if (endpoint.includes('/check-runs')) console.log(d.checks.map(r => r.join('\\t')).join('\\n'));
else if (endpoint.includes('/workflows/ci.yml/runs')) console.log(JSON.stringify(d.runs));
else if (endpoint.includes('/jobs?')) console.log(JSON.stringify(d.jobs));
else process.exit(1);
`);
  chmodSync(gh, 0o755);
  try {
    return spawnSync('bash', [process.env.LYB_RELEASE_VALIDATOR_UNDER_TEST || '.github/scripts/validate-release-source.sh'], {
      cwd: root, encoding: 'utf8', timeout: 10000,
      env: { ...process.env, PATH: `${directory}:${process.env.PATH}`,
        LYB_TEST_API_FIXTURE: fixturePath, GITHUB_REPOSITORY: repository,
        GITHUB_SHA: sha, GITHUB_REF_NAME: 'main', GITHUB_EVENT_NAME: 'push',
        RELEASE_CHECK_TIMEOUT_SECONDS: '0', ...extra },
    });
  } finally { rmSync(directory, { recursive: true, force: true }); }
}
test('real shell rejects reconstructed actual mixed-run acceptance', () => {
  const result = realShell(mixed);
  assert.equal(result.error, undefined);
  assert.notEqual(result.status, 0, result.stdout);
});
test('real shell rejects malformed newer push provenance before queue fallback', () => {
  for (const field of ['repository', 'head_branch', 'path', 'event']) {
    const current = run({ status: 'in_progress', conclusion: null });
    delete current[field];
    const result = realShell({ runs: pages(queue, current), jobs: jobs(queue), checks: mixed.checks },
      { GITHUB_EVENT_NAME: 'workflow_dispatch' });
    assert.equal(result.error, undefined);
    assert.notEqual(result.status, 0, result.stdout);
    assert.match(result.stderr, /Missing or invalid exact-source CI provenance/);
  }
});
test('real shell waits on newer main failure and does not borrow queue success', () => {
  const result = realShell({ ...mixed, runs: pages(queue, run({ conclusion: 'failure' })) });
  assert.notEqual(result.status, 0);
  assert.match(result.stdout, /concluded failure/);
});
test('real shell accepts complete push and complete same-source queue alone', () => {
  for (const current of [run(), queue]) {
    const result = realShell({ runs: pages(current), jobs: jobs(current), checks: mixed.checks },
      { GITHUB_EVENT_NAME: current.event === 'push' ? 'push' : 'workflow_dispatch' });
    assert.equal(result.error, undefined);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Release source validation passed/);
  }
});
test('real shell rejects absent runs, malformed JSON metadata, API failure and nonmain source', () => {
  for (const fixture of [{ ...mixed, runs: pages() }, { ...mixed, runs: {} }]) {
    assert.notEqual(realShell(fixture).status, 0);
  }
  for (const failure of ['true', 'runs', 'jobs']) {
    const result = realShell({ runs: pages(run()), jobs: jobs(), checks: mixed.checks },
      { LYB_TEST_GH_FAIL: failure });
    assert.notEqual(result.status, 0);
    if (failure !== 'true') assert.match(result.stderr, /Unable to read/);
  }
  assert.notEqual(realShell({ ...mixed, runs: pages(run()), jobs: {} }).status, 0);
  assert.notEqual(realShell({ ...mixed, runs: pages(queue), jobs: jobs(queue) }).status, 0);
  assert.notEqual(realShell(mixed, { GITHUB_REF_NAME: 'feature' }).status, 0);
});
