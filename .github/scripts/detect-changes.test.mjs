// Behavioral contract for ci.yml change detection and the CI Summary gate:
// runs detect-changes.sh against real git fixtures, then runs the gate's shell.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const detectScript = path.join(scriptDir, 'detect-changes.sh');
const ciWorkflow = fs.readFileSync(path.join(scriptDir, '../workflows/ci.yml'), 'utf8');

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

function commit(repo, files, message) {
  for (const [file, body] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(repo, file)), { recursive: true });
    fs.writeFileSync(path.join(repo, file), body);
  }
  git(repo, 'add', '-A');
  git(repo, 'commit', '-q', '-m', message);
  return git(repo, 'rev-parse', 'HEAD');
}

// origin: main -> group 1 head (an iOS PR) -> group 2 head (this change).
// The workspace is a depth-1 checkout of group 2, like actions/checkout.
function queueFixture(groupTwoFiles, { groupOneFiles = { 'apps/ios/App.swift': 'v2' } } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'detect-changes-'));
  const origin = path.join(root, 'origin');
  fs.mkdirSync(origin);
  git(origin, 'init', '-q', '-b', 'main');
  git(origin, 'config', 'uploadpack.allowAnySHA1InWant', 'true');
  const main = commit(origin, { 'apps/ios/App.swift': 'v1', 'apps/web/page.tsx': 'v1', 'package.json': '{}' }, 'main');
  const groupOne = commit(origin, groupOneFiles, 'group 1');
  const groupTwo = commit(origin, groupTwoFiles, 'group 2');
  const workspace = path.join(root, 'workspace');
  git(root, 'clone', '-q', '--depth=1', '--no-tags', `file://${origin}`, workspace);
  assert.throws(() => git(workspace, 'cat-file', '-e', `${groupOne}^{commit}`), 'fixture base must start unfetched');
  return { root, workspace, main, groupOne, groupTwo };
}

function detect(workspace, env, ghScript) {
  const output = path.join(workspace, '..', `output-${Math.random().toString(36).slice(2)}`);
  fs.writeFileSync(output, '');
  const bin = fs.mkdtempSync(path.join(os.tmpdir(), 'detect-bin-'));
  const ghCalls = path.join(bin, 'calls');
  fs.writeFileSync(path.join(bin, 'gh'), `#!/usr/bin/env bash\necho "$*" >> ${JSON.stringify(ghCalls)}\n${ghScript ?? 'exit 1'}\n`, {
    mode: 0o755,
  });
  const result = spawnSync('bash', [detectScript], {
    cwd: workspace,
    encoding: 'utf8',
    env: {
      ...gitEnv,
      PATH: `${bin}:${process.env.PATH}`,
      GITHUB_OUTPUT: output,
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      ...env,
    },
  });
  assert.equal(result.status, 0, result.stderr);
  const outputs = Object.fromEntries(
    fs
      .readFileSync(output, 'utf8')
      .trim()
      .split('\n')
      .map((line) => line.split('=')),
  );
  const calls = fs.existsSync(ghCalls) ? fs.readFileSync(ghCalls, 'utf8').trim().split('\n') : [];
  return { outputs, calls, stdout: result.stdout };
}

const mergeGroup = (fx) => ({ GITHUB_EVENT_NAME: 'merge_group', BASE_SHA: fx.groupOne, HEAD_SHA: fx.groupTwo });

// gh answers for a merge group: open post-merge-lq-red issues, then the entry's PR head
// (second parent of the group head) and whether its PR CI run passed Launch Quality.
const PR_HEAD = 'a'.repeat(40);
const groupGh = ({ hold = 0, prHeadPassed = true } = {}) => `case "$*" in
  *"issues?labels=post-merge-lq-red&state=open"*) echo ${hold} ;;
  *"repos/JovieInc/LogYourBody/commits/"*) echo ${PR_HEAD} ;;
  *"workflows/ci.yml/runs?head_sha=${PR_HEAD}&event=pull_request"*) echo 77 ;;
  *"actions/runs/77/jobs"*) echo ${prHeadPassed ? 1 : 0} ;;
  *) exit 1 ;;
esac`;
const holdIssues = (count) => groupGh({ hold: count });
const noHold = groupGh();

const surfaces = (web, iosChanged, unit, quality, deferred = 'false') => ({
  web,
  ios_changed: iosChanged,
  ios_unit: unit,
  ios_quality: quality,
  ios_quality_deferred: deferred,
});

test('large native source imports preserve detection under pipefail', () => {
  const files = { 'apps/ios/App.swift': 'v3' };
  for (let index = 0; index < 2000; index++) {
    files[`docs/import-${String(index).padStart(5, '0')}-${'a'.repeat(60)}.md`] = 'fixture';
  }
  const fx = queueFixture(files);
  try {
    const result = detect(fx.workspace, {
      ...mergeGroup(fx), GITHUB_EVENT_NAME: 'pull_request', PR_DRAFT: 'true',
    });
    assert.deepEqual(result.outputs, surfaces('false', 'true', 'false', 'false', 'true'));
  } finally {
    fs.rmSync(fx.root, { recursive: true, force: true });
  }
});

test('web-only merge group behind a queued iOS PR skips iOS', () => {
  const fx = queueFixture({ 'apps/web/page.tsx': 'v2' });
  const { outputs, calls } = detect(fx.workspace, mergeGroup(fx));
  assert.deepEqual(outputs, surfaces('true', 'false', 'false', 'false'));
  assert.deepEqual(calls, [], 'a group with no iOS change needs no hold lookup');
});

test('native merge group runs iOS Unit only while main Launch Quality is green', () => {
  const fx = queueFixture({ 'apps/ios/App.swift': 'v3' }, { groupOneFiles: { 'apps/web/page.tsx': 'v2' } });
  const { outputs, calls } = detect(fx.workspace, mergeGroup(fx), noHold);
  assert.deepEqual(outputs, surfaces('false', 'true', 'true', 'false'));
  assert.match(calls[0], /repos\/JovieInc\/LogYourBody\/issues\?labels=post-merge-lq-red&state=open/);
  assert.match(calls[1], new RegExp(`repos/JovieInc/LogYourBody/commits/${fx.groupTwo} --jq \\.parents\\[1\\]\\.sha`));
});

test('a native entry whose PR head never passed Launch Quality runs it in the group', () => {
  // Entries enqueued before Launch Quality moved to the PR head, or from a draft-era run.
  const fx = queueFixture({ 'apps/ios/App.swift': 'v3' });
  assert.deepEqual(
    detect(fx.workspace, mergeGroup(fx), groupGh({ prHeadPassed: false })).outputs,
    surfaces('false', 'true', 'true', 'true'),
  );
  const lookupFails = `case "$*" in *"issues?labels="*) echo 0 ;; *) exit 1 ;; esac`;
  assert.deepEqual(detect(fx.workspace, mergeGroup(fx), lookupFails).outputs, surfaces('false', 'true', 'true', 'true'));
});

test('the PR-head check accepts only a passing CI Summary with a passing Launch Quality job', () => {
  const script = fs.readFileSync(detectScript, 'utf8');
  const filter = script.match(/--jq '(if any\(\.jobs\[\]; \.name == "CI Summary"[\s\S]*?then 1 else 0 end)'/)[1];
  const jobs = (...list) => JSON.stringify({ jobs: list.map(([name, conclusion]) => ({ name, conclusion })) });
  const run = (payload) => execFileSync('jq', ['-r', filter], { input: payload, encoding: 'utf8' }).trim();
  const summary = ['CI Summary', 'success'];
  assert.equal(run(jobs(summary, ['iOS Launch Quality Gate / Launch Quality', 'success'])), '1');
  assert.equal(
    run(jobs(summary, ['iOS Launch Quality Gate / Launch Quality', 'skipped'], ['iOS Launch Quality Gate / Mac Route / Await the Mac', 'success'])),
    '1',
  );
  // Old regime (PR runs skipped iOS) and draft runs: Launch Quality never ran.
  assert.equal(run(jobs(summary, ['iOS Launch Quality Gate', 'skipped'])), '0');
  assert.equal(run(jobs(['CI Summary', 'failure'], ['iOS Launch Quality Gate / Launch Quality', 'success'])), '0');
});

test('a red or unknown post-merge Launch Quality holds native merge groups on Launch Quality', () => {
  const fx = queueFixture({ 'apps/ios/App.swift': 'v3' });
  assert.deepEqual(detect(fx.workspace, mergeGroup(fx), holdIssues(1)).outputs, surfaces('false', 'true', 'true', 'true'));
  assert.deepEqual(detect(fx.workspace, mergeGroup(fx), 'exit 1').outputs, surfaces('false', 'true', 'true', 'true'));
});

test('every input the iOS jobs read selects iOS; JS-only roots do not', () => {
  const native = [
    'apps/ios/LogYourBody.xcodeproj/project.pbxproj',
    'scripts/ios/launch-quality-audit.sh',
    '.github/actions/setup-ios-build/action.yml',
    '.github/actions/setup-ruby-bundler/action.yml',
    '.github/scripts/mac-lane.sh',
    '.github/scripts/detect-changes.sh',
    '.github/workflows/ci.yml',
    '.github/workflows/ios-unit.yml',
    '.github/workflows/ios-quality.yml',
    '.github/workflows/mac-lane.yml',
    '.github/workflows/mac-lane-route.yml',
  ];
  for (const file of native) {
    const fx = queueFixture({ [file]: 'changed' }, { groupOneFiles: { 'README.md': 'v2' } });
    assert.equal(detect(fx.workspace, mergeGroup(fx), noHold).outputs.ios_unit, 'true', file);
  }
  for (const file of ['package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'packages/shared-lib/index.ts', '.github/workflows/deploy.yml']) {
    const fx = queueFixture({ [file]: 'changed' });
    const { outputs } = detect(fx.workspace, mergeGroup(fx));
    assert.deepEqual(outputs, surfaces('true', 'false', 'false', 'false'), file);
  }
});

test('an unfetchable base selects every surface', () => {
  const fx = queueFixture({ 'README.md': 'v2' });
  const { outputs } = detect(fx.workspace, { ...mergeGroup(fx), BASE_SHA: 'f'.repeat(40) }, noHold);
  assert.deepEqual(outputs, surfaces('true', 'true', 'true', 'false'));
  const zero = detect(fx.workspace, { ...mergeGroup(fx), BASE_SHA: '0'.repeat(40) }, noHold);
  assert.deepEqual(zero.outputs, surfaces('true', 'true', 'true', 'false'));
  const pr = detect(fx.workspace, { ...mergeGroup(fx), GITHUB_EVENT_NAME: 'pull_request', BASE_SHA: 'f'.repeat(40) });
  assert.deepEqual(pr.outputs, surfaces('true', 'true', 'false', 'true'));
});

test('ready pull requests run Launch Quality on the PR head; drafts defer it; Unit waits for the group', () => {
  const fx = queueFixture({ 'apps/ios/App.swift': 'v3' });
  const pr = { ...mergeGroup(fx), GITHUB_EVENT_NAME: 'pull_request' };
  const ready = detect(fx.workspace, { ...pr, PR_DRAFT: 'false' });
  assert.deepEqual(ready.outputs, surfaces('false', 'true', 'false', 'true'));
  assert.deepEqual(ready.calls, []);
  const draft = detect(fx.workspace, { ...pr, PR_DRAFT: 'true' });
  assert.deepEqual(draft.outputs, surfaces('false', 'true', 'false', 'false', 'true'));
  const web = queueFixture({ 'apps/web/page.tsx': 'v2' });
  assert.deepEqual(
    detect(web.workspace, { ...mergeGroup(web), GITHUB_EVENT_NAME: 'pull_request', PR_DRAFT: 'false' }).outputs,
    surfaces('true', 'false', 'false', 'false'),
  );
});

test('main push skips iOS Unit only when the merge group for that SHA passed CI Summary', () => {
  const fx = queueFixture({ 'apps/ios/App.swift': 'v3' });
  const push = { GITHUB_EVENT_NAME: 'push', BASE_SHA: fx.main, HEAD_SHA: fx.groupTwo };
  const respond = (summary) => `case "$*" in
  *"workflows/ci.yml/runs?head_sha=${fx.groupTwo}&event=merge_group"*) echo 101 ;;
  *"actions/runs/101/jobs"*) echo ${summary} ;;
  *) exit 1 ;;
esac`;

  const verified = detect(fx.workspace, push, respond(1));
  assert.deepEqual(verified.outputs, surfaces('false', 'true', 'false', 'false'));
  assert.match(verified.calls[1], /select\(\.name == "CI Summary" and \.conclusion == "success"\)/);

  // Launch Quality for main runs post-merge (ios-post-merge-quality.yml), never in this push run.
  assert.deepEqual(detect(fx.workspace, push, respond(0)).outputs, surfaces('false', 'true', 'true', 'false'));
  assert.deepEqual(detect(fx.workspace, push, 'exit 1').outputs, surfaces('false', 'true', 'true', 'false'));
});

function jobBlock(name) {
  const start = ciWorkflow.indexOf(`\n  ${name}:\n`);
  assert.notEqual(start, -1, `ci.yml has no ${name} job`);
  const rest = ciWorkflow.slice(start + 1);
  const end = rest.slice(1).search(/\n {2}[A-Za-z0-9_-]+:\n/);
  return end === -1 ? rest : rest.slice(0, end + 1);
}

test('StoreKit evidence runs on every main push and gates native changes', () => {
  const storekit = jobBlock('ios_storekit');
  assert.match(storekit, /if: github\.event_name == 'push' \|\| \(github\.event_name == 'merge_group' && needs\.detect-changes\.outputs\.ios_changed == 'true'\)/);
  assert.match(storekit, /runs-on: macos-15/);
  assert.match(storekit, /run: bash scripts\/ios\/storekit-purchase-restore\.sh/);
  assert.match(storekit, /if: always\(\)[\s\S]*actions\/upload-artifact/);
  assert.match(jobBlock('ci-summary'), /needs: \[.*ios_storekit\]/);
});

test('ci.yml wires detection, the iOS jobs and the CI Summary dependencies', () => {
  assert.match(ciWorkflow, /pull_request:\n {4}branches: \[main, production\]\n(?: {4}#.*\n)* {4}types: \[opened, synchronize, reopened, ready_for_review\]/);
  const detection = jobBlock('detect-changes');
  assert.match(detection, /id: filter[\s\S]*PR_DRAFT: \$\{\{ github\.event\.pull_request\.draft \|\| false \}\}[\s\S]*run: bash \.github\/scripts\/detect-changes\.sh/);
  for (const output of ['ios_unit', 'ios_quality', 'ios_quality_deferred']) {
    assert.match(detection, new RegExp(`${output}: \\$\\{\\{ steps\\.filter\\.outputs\\.${output} \\}\\}`), output);
  }
  assert.match(jobBlock('ios'), /if: needs\.detect-changes\.outputs\.ios_unit == 'true'/);
  assert.match(jobBlock('ios_quality'), /if: needs\.detect-changes\.outputs\.ios_quality == 'true'/);
  assert.match(jobBlock('ci-summary'), /if: always\(\)[\s\S]*needs: \[detect-changes, mac-runner-routing-tests, js, ios, ios_quality, ios_static, ios_storekit\]/);
});

test('required CI rejects a stale repository source projection', () => {
  assert.match(ciWorkflow, /pull_request:\n {4}branches: \[main, production\]/);
  assert.match(ciWorkflow, /merge_group:\n {4}branches: \[main, production\]/);
  const detection = jobBlock('detect-changes');
  assert.doesNotMatch(detection.slice(0, detection.indexOf('\n    steps:\n')), /\n    if:/);
  const marker = '      - name: Verify repository source projection\n';
  const start = detection.indexOf(marker);
  assert.notEqual(start, -1, 'detect-changes must run the repository source projection check');
  const step = detection.slice(start + marker.length).split('\n      - ')[0];
  assert.equal(step, '        run: python3 scripts/repository_docs.py\n');
  assert.doesNotMatch(step, /continue-on-error|\bif:/);
  assert.match(jobBlock('ci-summary'), /needs\.detect-changes\.result.*!= "success"/);
  const check = spawnSync('python3', ['scripts/repository_docs.py'], {
    cwd: path.resolve(scriptDir, '../..'),
    encoding: 'utf8',
  });
  assert.equal(check.status, 0, `${check.stdout}${check.stderr}`);
});

function runSummaryGate({ web, ios, quality = ios, js, iosResult, qualityResult, event = 'pull_request', storekitResult, staticResult }) {
  const block = jobBlock('ci-summary');
  const script = block
    .slice(block.indexOf('run: |') + 'run: |'.length)
    .split('\n')
    .map((line) => line.replace(/^ {10}/, ''))
    .join('\n');
  const values = {
    'github.event_name': event,
    'needs.detect-changes.result': 'success',
    'needs.mac-runner-routing-tests.result': 'success',
    'needs.detect-changes.outputs.web': web,
    'needs.detect-changes.outputs.ios_unit': ios,
    'needs.detect-changes.outputs.ios_quality': quality,
    'needs.detect-changes.outputs.ios_quality_deferred': 'false',
    'needs.detect-changes.outputs.ios_changed': ios === 'true' || quality === 'true' ? 'true' : 'false',
    'needs.js.result': js,
    'needs.ios.result': iosResult,
    'needs.ios_quality.result': qualityResult,
    'needs.ios_static.result': staticResult ?? qualityResult,
    'needs.ios_storekit.result': storekitResult ?? (event === 'push' || (event === 'merge_group' && (ios === 'true' || quality === 'true')) ? 'success' : 'skipped'),
  };
  const rendered = script.replace(/\$\{\{\s*([^}]+?)\s*\}\}/g, (_, expr) => {
    assert.ok(expr in values, `unrendered expression ${expr}`);
    return values[expr];
  });
  const summary = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'ci-summary-')), 'summary.md');
  return spawnSync('bash', ['-e', '-c', rendered], { encoding: 'utf8', env: { ...process.env, GITHUB_STEP_SUMMARY: summary } }).status;
}

test('CI Summary passes a web-only change with iOS skipped', () => {
  assert.equal(runSummaryGate({ web: 'true', ios: 'false', js: 'success', iosResult: 'skipped', qualityResult: 'skipped' }), 0);
});

test('CI Summary rejects missing or failing StoreKit evidence on native PRs and every main commit', () => {
  const web = { web: 'true', ios: 'false', js: 'success', iosResult: 'skipped', qualityResult: 'skipped', event: 'push' };
  const native = { web: 'false', ios: 'true', js: 'skipped', iosResult: 'success', qualityResult: 'success', event: 'merge_group' };
  for (const change of [web, native]) {
    assert.equal(runSummaryGate({ ...change, storekitResult: 'success' }), 0);
    for (const storekitResult of ['skipped', 'failure', 'cancelled']) {
      assert.notEqual(runSummaryGate({ ...change, storekitResult }), 0, storekitResult);
    }
  }
});

test('CI Summary requires both iOS jobs to pass when native code changed', () => {
  const native = { web: 'false', ios: 'true', js: 'skipped' };
  assert.equal(runSummaryGate({ ...native, iosResult: 'success', qualityResult: 'success' }), 0);
  assert.notEqual(runSummaryGate({ ...native, iosResult: 'skipped', qualityResult: 'skipped' }), 0);
  assert.notEqual(runSummaryGate({ ...native, iosResult: 'success', qualityResult: 'failure' }), 0);
  assert.notEqual(runSummaryGate({ ...native, iosResult: 'cancelled', qualityResult: 'success' }), 0);
  assert.notEqual(runSummaryGate({ web: 'true', ios: 'false', js: 'success', iosResult: 'success', qualityResult: 'skipped' }), 0);
});

test('CI Summary requires exactly the iOS job each event selected', () => {
  // Pull request: Launch Quality only. Merge group: Unit only.
  const pr = { web: 'false', ios: 'false', quality: 'true', js: 'skipped' };
  assert.equal(runSummaryGate({ ...pr, iosResult: 'skipped', qualityResult: 'success' }), 0);
  assert.notEqual(runSummaryGate({ ...pr, iosResult: 'skipped', qualityResult: 'failure' }), 0);
  assert.notEqual(runSummaryGate({ ...pr, iosResult: 'skipped', qualityResult: 'skipped' }), 0);
  const group = { web: 'false', ios: 'true', quality: 'false', js: 'skipped' };
  assert.equal(runSummaryGate({ ...group, iosResult: 'success', qualityResult: 'skipped' }), 0);
  assert.notEqual(runSummaryGate({ ...group, iosResult: 'failure', qualityResult: 'skipped' }), 0);
  assert.notEqual(runSummaryGate({ ...group, iosResult: 'success', qualityResult: 'success' }), 0);
});


test('isolated reported SQL harness, contract and wrapper changes select the required JS lane', () => {
  for (const file of ['scripts/neon/test-reported-measurements.py', 'scripts/neon/test_reported_measurements_harness.py', 'packages/shared-lib/src/reported-measurements-sql.test.ts']) {
    const fx = queueFixture({ [file]: 'changed' });
    try {
      assert.deepEqual(detect(fx.workspace, mergeGroup(fx)).outputs, surfaces('true', 'false', 'false', 'false'), file);
    } finally { fs.rmSync(fx.root, { recursive: true, force: true }); }
  }
});

test('required reported SQL qualification fails through tee and records exact source evidence', () => {
  const js = ciWorkflow.split('  js:\n')[1].split('\n  ios:')[0];
  assert.match(js, /runs-on: ubuntu-24\.04/);
  const step = js.split('      - name: Verify reported measurements on disposable PostgreSQL16\n')[1].split('\n      - name:')[0];
  assert.match(step, /shell: bash/);
  assert.match(step, /timeout-minutes: 5/);
  assert.match(step, /--run --postgres-bin \/usr\/lib\/postgresql\/16\/bin/);
  assert.match(step, /git rev-parse HEAD/);
  for (const source of ['test-reported-measurements.py', '20260813130000_native_product_records.sql', 'native-product-records-adapter.ts', 'reported-measurements.ts']) assert.ok(step.includes(source));
  assert.match(js, /Upload reported measurement execution evidence\n        if: always\(\)/);
  const body = step.split('        run: |\n')[1].split('\n').map((line) => line.startsWith('          ') ? line.slice(10) : line).join('\n');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'reported-sql-ci-'));
  try {
    for (const [name, script] of Object.entries({git: 'echo fixture-head', sha256sum: 'echo fixture-hashes', python3: 'if [[ "$1" == "-c" ]]; then echo /usr; exit 0; fi; echo injected-SQL-failure; exit 42'})) {
      fs.writeFileSync(path.join(root, name), '#!/usr/bin/env bash\n' + script + '\n', {mode: 0o755});
    }
    const result = spawnSync('bash', ['-c', body], {cwd: root, encoding: 'utf8', env: {...gitEnv, PATH: `${root}:${process.env.PATH}`}});
    assert.equal(result.status, 42, result.stderr);
    assert.match(fs.readFileSync(path.join(root, 'artifacts/reported-measurements/results.log'), 'utf8'), /injected-SQL-failure/);
    assert.match(fs.readFileSync(path.join(root, 'artifacts/reported-measurements/source-revision.txt'), 'utf8'), /fixture-head/);
  } finally { fs.rmSync(root, {recursive: true, force: true}); }
});

for (const file of [
  'apps/web/db/migrations/20261014103000_training_execution_cas.sql',
  'apps/web/db/tests/verify-training-mutations.py',
  'apps/web/db/tests/test_verify_training_mutations.py',
]) {
  test(`SQL qualification runs the required JS gate for isolated change: ${file}`, () => {
    const fx = queueFixture({ [file]: 'changed' });
    try {
      assert.deepEqual(detect(fx.workspace, mergeGroup(fx)).outputs, surfaces('true', 'false', 'false', 'false'));
    } finally {
      fs.rmSync(fx.root, { recursive: true, force: true });
    }
  });
}

test('required SQL CI step propagates verifier failure through tee', () => {
  const step = ciWorkflow.match(/      - name: Verify training mutations on disposable PostgreSQL16\n([\s\S]*?)(?=\n      - name:)/)[1];
  assert.match(step, /^        shell: bash$/m, 'explicit bash enables Actions errexit and pipefail');
  const run = step.match(/        run: \|\n([\s\S]*)/)[1].replace(/^          /gm, '');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'training-sql-ci-failure-'));
  try {
    const bin = path.join(root, 'bin');
    fs.mkdirSync(bin);
    for (const [command, body] of Object.entries({
      python3: 'echo injected-SQL-verifier-failure >&2; exit 17',
      git: 'echo synthetic-source',
      sha256sum: 'echo synthetic-hash',
    })) {
      fs.writeFileSync(path.join(bin, command), '#!/bin/sh\n' + body + '\n', { mode: 0o755 });
    }
    const result = spawnSync('bash', ['--noprofile', '--norc', '-eo', 'pipefail', '-c', run], {
      cwd: root, encoding: 'utf8', env: { ...gitEnv, PATH: bin + ':' + process.env.PATH },
    });
    assert.equal(result.status, 17, result.stderr);
    assert.match(result.stderr, /injected-SQL-verifier-failure/);
    assert.ok(fs.existsSync(path.join(root, 'artifacts/training-mutations/results.log')), 'tee actually ran');
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("isolated daily-step SQL verifier changes select the required JS lane", () => {
  const fx = queueFixture({
    "scripts/neon/verify-daily-step-deletions.py": "changed",
  });
  try {
    assert.deepEqual(
      detect(fx.workspace, mergeGroup(fx)).outputs,
      surfaces("true", "false", "false", "false"),
    );
  } finally {
    fs.rmSync(fx.root, { recursive: true, force: true });
  }
});

test("daily-step SQL qualification enforces actual report and source evidence through the real CI shell", () => {
  const js = ciWorkflow.split("  js:\n")[1].split("\n  ios:")[0];
  assert.match(js, /runs-on: ubuntu-24\.04/);
  const step = js
    .split(
      "      - name: Verify daily step deletions on disposable PostgreSQL16\n",
    )[1]
    .split("\n      - name:")[0];
  assert.match(step, /shell: bash/);
  assert.match(step, /timeout-minutes: 5/);
  assert.match(step, /--run --postgres-bin \/usr\/lib\/postgresql\/16\/bin/);
  assert.match(
    js,
    /Upload reported measurement execution evidence\n        if: always\(\)/,
  );
  const body = step.split("        run: |\n")[1].replace(/^          /gm, "");
  const realPython = execFileSync("sh", ["-c", "command -v python3"], {
    encoding: "utf8",
  }).trim();
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "daily-delete-ci-"));
  const sourceFiles = [
    "scripts/neon/verify-daily-step-deletions.py",
    "apps/web/src/lib/neon/native-product-records-adapter.ts",
    "apps/web/src/lib/neon/native-account-admission.ts",
    "apps/web/db/migrations/20260714183000_create_app_users.sql",
    "apps/web/db/migrations/20260813130000_native_product_records.sql",
    "apps/web/db/migrations/20261010120000_native_account_admission.sql",
  ];
  const expectedChecks = [
    "DELETE then different-ID POST waits on actual account lock and retains unrelated fields",
    "POST then different-ID DELETE waits on actual account lock and retains unrelated fields",
    "same-ID stale replay cannot move or erase marker/date/notes/unknown JSON",
    "different-ID recorded zero and positive imports inherit the owner/day marker",
    "repeat deletion accepts equivalent offset instants and retains original marker",
    "half-open end leaves the following day unchanged",
    "foreign-ID collision cannot change anchor or authorize another owner's day deletion",
    "different owner completes while first owner's lock remains held",
    "later transaction failure rolls back marker and every daily write",
    "captured old account incarnation cannot create a deletion marker",
  ];
  try {
    for (const name of sourceFiles) {
      fs.mkdirSync(path.dirname(path.join(root, name)), { recursive: true });
      fs.writeFileSync(path.join(root, name), "synthetic source: " + name);
    }
    const bin = path.join(root, "bin");
    fs.mkdirSync(bin);
    fs.writeFileSync(
      path.join(bin, "git"),
      "#!/bin/sh\necho 0123456789abcdef0123456789abcdef01234567\n",
      { mode: 0o755 },
    );
    // Substitute only the verifier process; the exact YAML validator uses real Python.
    fs.writeFileSync(
      path.join(bin, "python3"),
      `#!/bin/sh
if [ "$1" = "-m" ] && [ "$2" = "trace" ]; then
  exec "$REAL_PYTHON" "$FIXTURE_REPORT"
fi
exec "$REAL_PYTHON" "$@"
`,
      { mode: 0o755 },
    );
    const reportScript = path.join(root, "fixture-report.py");
    fs.writeFileSync(
      reportScript,
      `import hashlib, json, os, pathlib, sys
mode = os.environ["FIXTURE_MODE"]
if mode == "sql-error":
    print("injected verifier-command failure", flush=True)
    sys.exit(42)
if mode == "missing-report": sys.exit(0)
checks = json.loads(os.environ["FIXTURE_CHECKS"])
sources = json.loads(os.environ["FIXTURE_SOURCES"])
report = {"passed": 10, "checks": checks, "liveDatabase": False,
          "lockObservations": [{"schedule": x.split(" waits on")[0], "waitEventType": "Lock", "actualHolderInBlockingPids": True} for x in checks[:2]],
          "postgresTools": {x: x + " (PostgreSQL) 16.15" for x in ["initdb", "pg_ctl", "psql"]},
          "sourceSha256": {str(pathlib.Path.cwd() / x): hashlib.sha256(pathlib.Path(x).read_bytes()).hexdigest() for x in sources[1:]}}
if mode == "dropped-check": report["checks"] = checks[:-1]
if mode == "duplicate-check": report["checks"] = checks[:-1] + checks[:1]
if mode == "missing-lock": report["lockObservations"] = report["lockObservations"][:1]
if mode == "source-mismatch": report["sourceSha256"][str(pathlib.Path.cwd() / sources[1])] = "0" * 64
if mode == "wrong-version": report["postgresTools"]["psql"] = "psql (PostgreSQL) 18.4"
if mode == "live-database": report["liveDatabase"] = True
print(json.dumps(report))
if mode == "duplicate-report": print(json.dumps(report))
`,
    );
    const modes = [
      "valid",
      "sql-error",
      "missing-report",
      "dropped-check",
      "duplicate-check",
      "missing-lock",
      "source-mismatch",
      "wrong-version",
      "live-database",
      "duplicate-report",
    ];
    for (const mode of modes) {
      fs.rmSync(path.join(root, "artifacts"), { recursive: true, force: true });
      const result = spawnSync(
        "bash",
        ["--noprofile", "--norc", "-eo", "pipefail", "-c", body],
        {
          cwd: root,
          encoding: "utf8",
          env: {
            ...gitEnv,
            PATH: bin + ":" + process.env.PATH,
            REAL_PYTHON: realPython,
            FIXTURE_REPORT: reportScript,
            FIXTURE_MODE: mode,
            FIXTURE_CHECKS: JSON.stringify(expectedChecks),
            FIXTURE_SOURCES: JSON.stringify(sourceFiles),
          },
        },
      );
      if (mode === "valid") assert.equal(result.status, 0, result.stderr);
      else if (mode === "sql-error")
        assert.equal(result.status, 42, result.stderr);
      else assert.notEqual(result.status, 0, mode);
      assert.ok(
        fs.existsSync(
          path.join(
            root,
            "artifacts/reported-measurements/daily-step-deletions/results.log",
          ),
        ),
        "tee retained evidence: " + mode,
      );
    }
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("daily-step verifier rejects execution without explicit disposable opt-in", () => {
  const verifier = path.join(
    scriptDir,
    "../../scripts/neon/verify-daily-step-deletions.py",
  );
  const result = spawnSync(
    "python3",
    [verifier, "--postgres-bin", "/unavailable"],
    { encoding: "utf8", env: gitEnv },
  );
  assert.equal(result.status, 2, result.stderr);
  assert.match(
    result.stderr,
    /Pass --run to create an isolated socket-only cluster/,
  );
});

test('CI Summary does not require StoreKit on a native pull_request (the merge group runs it)', () => {
  const pr = { web: 'false', ios: 'false', quality: 'true', js: 'skipped', iosResult: 'skipped', qualityResult: 'success', event: 'pull_request' };
  assert.equal(runSummaryGate({ ...pr, storekitResult: 'skipped' }), 0);
  assert.notEqual(runSummaryGate({ ...pr, storekitResult: 'success' }), 0);
});

test('Launch Quality static audits run on ubuntu and are gated by CI Summary', () => {
  const staticJob = jobBlock('ios_static');
  assert.match(staticJob, /if: needs\.detect-changes\.outputs\.ios_quality == 'true'/);
  assert.match(staticJob, /runs-on: ubuntu-24\.04/);
  assert.match(staticJob, /swift-actions\/setup-swift@[0-9a-f]{40}/, 'SwiftLint SourceKit rules need a real toolchain');
  assert.doesNotMatch(staticJob, /swiftlint-static/);
  assert.match(staticJob, /bash scripts\/ios\/static-quality-audit\.sh/);
  assert.match(jobBlock('ios_quality'), /static-audits: false/);
  const quality = fs.readFileSync(new URL('../workflows/ios-quality.yml', import.meta.url), 'utf8');
  assert.match(quality, /RUN_SWIFTLINT: \$\{\{ format\('\{0\}', inputs\.static-audits\) \}\}/);
  assert.match(quality, /static-audits:[\s\S]*default: true/, 'post-merge and dispatch keep the full audit');
  const ok = { web: 'false', ios: 'false', quality: 'true', js: 'skipped', iosResult: 'skipped', qualityResult: 'success', event: 'pull_request' };
  assert.equal(runSummaryGate({ ...ok, staticResult: 'success' }), 0);
  for (const staticResult of ['failure', 'cancelled', 'skipped']) {
    assert.notEqual(runSummaryGate({ ...ok, staticResult }), 0, staticResult);
  }
});

function sourceMapConflict({ sourceConflict = false } = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-map-merge-'));
  git(root, 'init', '-q', '-b', 'main');
  const source = 'first\n' + 'context\n'.repeat(10) + 'last\n';
  const output = 'docs/SOURCES.md';
  const config = {
    schemaVersion: 1,
    repository: 'example/app',
    entrypoints: ['README.md'],
    sources: [{ path: 'workflow.yml', purpose: 'Workflow' }],
    imports: [],
    output,
  };
  commit(root, {
    'README.md': 'Local instructions\n',
    'repository-docs.json': JSON.stringify(config),
    'workflow.yml': source,
  }, 'base sources');
  const generate = () => execFileSync('python3', [
    path.join(scriptDir, '../../scripts/repository_docs.py'), '--root', root, '--write',
  ], { env: gitEnv });
  const checkpoint = (contents, message) => {
    fs.writeFileSync(path.join(root, 'workflow.yml'), contents);
    generate();
    git(root, 'add', '.');
    git(root, 'commit', '-q', '-m', message);
  };
  checkpoint(source, 'base projection');
  git(root, 'checkout', '-q', '-b', 'feature');
  checkpoint(source.replace('first', 'feature'), 'feature workflow');
  git(root, 'checkout', '-q', 'main');
  checkpoint(source.replace(sourceConflict ? 'first' : 'last', 'main'), 'main workflow');
  git(root, 'checkout', '-q', 'feature');
  assert.throws(() => git(root, 'merge', '--no-commit', 'main'), 'fixture must conflict');
  const resolve = () => spawnSync('python3', [
    path.join(scriptDir, '../../scripts/resolve-repository-docs.py'), '--root', root,
  ], { env: gitEnv, encoding: 'utf8' });
  return { root, output, config, resolve };
}

test('source-map merge repair regenerates from both parents and stages only the projection', () => {
  const fx = sourceMapConflict();
  try {
    const mergedSource = fs.readFileSync(path.join(fx.root, 'workflow.yml'), 'utf8');
    assert.match(mergedSource, /^feature\n/);
    assert.match(mergedSource, /\nmain\n$/);
    fs.writeFileSync(path.join(fx.root, 'README.md'), 'Unstaged local edit\n');
    const stagedSource = git(fx.root, 'show', ':workflow.yml');
    const result = fx.resolve();
    assert.equal(result.status, 0, result.stderr);
    assert.equal(git(fx.root, 'diff', '--name-only', '--diff-filter=U'), '');
    assert.equal(git(fx.root, 'show', ':workflow.yml'), stagedSource);
    assert.equal(git(fx.root, 'show', ':README.md'), 'Local instructions');
    const projection = fs.readFileSync(path.join(fx.root, fx.output), 'utf8');
    assert.doesNotMatch(projection, /<<<<<<<|=======|>>>>>>>/);
    assert.equal(git(fx.root, 'show', `:${fx.output}`), projection.trim());
    const parity = spawnSync('python3', [
      path.join(scriptDir, '../../scripts/repository_docs.py'), '--root', fx.root,
    ], { env: gitEnv, encoding: 'utf8' });
    assert.equal(parity.status, 0, parity.stderr);
    assert.equal(fx.resolve().status, 0, 'repair is idempotent');
    assert.equal(fs.readFileSync(path.join(fx.root, fx.output), 'utf8'), projection);
  } finally {
    fs.rmSync(fx.root, { recursive: true, force: true });
  }
});

for (const failure of ['source-conflict', 'pinned-drift', 'unsafe-output']) {
  test(`source-map merge repair refuses ${failure} without changing the projection or index`, () => {
    const fx = sourceMapConflict({ sourceConflict: failure === 'source-conflict' });
    try {
      if (failure === 'pinned-drift') {
        fx.config.imports = [{
          repository: 'example/policy', revision: 'a'.repeat(40),
          path: 'policy.md', destination: 'policy.md', sha256: '0'.repeat(64),
        }];
      }
      if (failure === 'unsafe-output') fx.config.output = '../escape.md';
      fs.writeFileSync(path.join(fx.root, 'repository-docs.json'), JSON.stringify(fx.config));
      const before = fs.readFileSync(path.join(fx.root, fx.output), 'utf8');
      const index = git(fx.root, 'ls-files', '--stage');
      const result = fx.resolve();
      assert.notEqual(result.status, 0, result.stdout);
      assert.match(result.stderr, {
        'source-conflict': /resolve source conflicts first: workflow.yml/,
        'pinned-drift': /pinned copy missing or changed: policy.md/,
        'unsafe-output': /unsafe repository path/,
      }[failure]);
      assert.equal(fs.readFileSync(path.join(fx.root, fx.output), 'utf8'), before);
      assert.equal(git(fx.root, 'ls-files', '--stage'), index);
    } finally {
      fs.rmSync(fx.root, { recursive: true, force: true });
    }
  });
}
