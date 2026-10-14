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

test('ci.yml wires detection, the iOS jobs and the CI Summary dependencies', () => {
  assert.match(ciWorkflow, /pull_request:\n {4}branches: \[main, production\]\n(?: {4}#.*\n)* {4}types: \[opened, synchronize, reopened, ready_for_review\]/);
  const detection = jobBlock('detect-changes');
  assert.match(detection, /id: filter[\s\S]*PR_DRAFT: \$\{\{ github\.event\.pull_request\.draft \|\| false \}\}[\s\S]*run: bash \.github\/scripts\/detect-changes\.sh/);
  for (const output of ['ios_unit', 'ios_quality', 'ios_quality_deferred']) {
    assert.match(detection, new RegExp(`${output}: \\$\\{\\{ steps\\.filter\\.outputs\\.${output} \\}\\}`), output);
  }
  assert.match(jobBlock('ios'), /if: needs\.detect-changes\.outputs\.ios_unit == 'true'/);
  assert.match(jobBlock('ios_quality'), /if: needs\.detect-changes\.outputs\.ios_quality == 'true'/);
  assert.match(jobBlock('ci-summary'), /if: always\(\)[\s\S]*needs: \[detect-changes, mac-runner-routing-tests, js, ios, ios_quality\]/);
});

function runSummaryGate({ web, ios, quality = ios, js, iosResult, qualityResult }) {
  const block = jobBlock('ci-summary');
  const script = block
    .slice(block.indexOf('run: |') + 'run: |'.length)
    .split('\n')
    .map((line) => line.replace(/^ {10}/, ''))
    .join('\n');
  const values = {
    'needs.detect-changes.result': 'success',
    'needs.mac-runner-routing-tests.result': 'success',
    'needs.detect-changes.outputs.web': web,
    'needs.detect-changes.outputs.ios_unit': ios,
    'needs.detect-changes.outputs.ios_quality': quality,
    'needs.detect-changes.outputs.ios_quality_deferred': 'false',
    'needs.detect-changes.outputs.ios_changed': ios,
    'needs.js.result': js,
    'needs.ios.result': iosResult,
    'needs.ios_quality.result': qualityResult,
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
