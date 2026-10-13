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

test('web-only merge group behind a queued iOS PR skips iOS', () => {
  const fx = queueFixture({ 'apps/web/page.tsx': 'v2' });
  const { outputs } = detect(fx.workspace, mergeGroup(fx));
  assert.deepEqual(outputs, { web: 'true', ios_changed: 'false', ios: 'false' });
});

test('native merge group runs iOS', () => {
  const fx = queueFixture({ 'apps/ios/App.swift': 'v3' }, { groupOneFiles: { 'apps/web/page.tsx': 'v2' } });
  const { outputs } = detect(fx.workspace, mergeGroup(fx));
  assert.deepEqual(outputs, { web: 'false', ios_changed: 'true', ios: 'true' });
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
    assert.equal(detect(fx.workspace, mergeGroup(fx)).outputs.ios, 'true', file);
  }
  for (const file of ['package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'packages/shared-lib/index.ts', '.github/workflows/deploy.yml']) {
    const fx = queueFixture({ [file]: 'changed' });
    const { outputs } = detect(fx.workspace, mergeGroup(fx));
    assert.deepEqual(outputs, { web: 'true', ios_changed: 'false', ios: 'false' }, file);
  }
});

test('an unfetchable base selects every surface', () => {
  const fx = queueFixture({ 'README.md': 'v2' });
  const { outputs } = detect(fx.workspace, { ...mergeGroup(fx), BASE_SHA: 'f'.repeat(40) });
  assert.deepEqual(outputs, { web: 'true', ios_changed: 'true', ios: 'true' });
  const zero = detect(fx.workspace, { ...mergeGroup(fx), BASE_SHA: '0'.repeat(40) });
  assert.deepEqual(zero.outputs, { web: 'true', ios_changed: 'true', ios: 'true' });
});

test('pull requests defer iOS to the merge group', () => {
  const fx = queueFixture({ 'apps/ios/App.swift': 'v3' });
  const { outputs } = detect(fx.workspace, { ...mergeGroup(fx), GITHUB_EVENT_NAME: 'pull_request' });
  assert.deepEqual(outputs, { web: 'false', ios_changed: 'true', ios: 'false' });
});

test('main push skips iOS only when the merge group for that SHA passed CI Summary', () => {
  const fx = queueFixture({ 'apps/ios/App.swift': 'v3' });
  const push = { GITHUB_EVENT_NAME: 'push', BASE_SHA: fx.main, HEAD_SHA: fx.groupTwo };
  const respond = (summary) => `case "$*" in
  *"workflows/ci.yml/runs?head_sha=${fx.groupTwo}&event=merge_group"*) echo 101 ;;
  *"actions/runs/101/jobs"*) echo ${summary} ;;
  *) exit 1 ;;
esac`;

  const verified = detect(fx.workspace, push, respond(1));
  assert.equal(verified.outputs.ios, 'false');
  assert.match(verified.calls[1], /select\(\.name == "CI Summary" and \.conclusion == "success"\)/);

  assert.equal(detect(fx.workspace, push, respond(0)).outputs.ios, 'true');
  assert.equal(detect(fx.workspace, push, 'exit 1').outputs.ios, 'true');
});

function jobBlock(name) {
  const start = ciWorkflow.indexOf(`\n  ${name}:\n`);
  assert.notEqual(start, -1, `ci.yml has no ${name} job`);
  const rest = ciWorkflow.slice(start + 1);
  const end = rest.slice(1).search(/\n {2}[A-Za-z0-9_-]+:\n/);
  return end === -1 ? rest : rest.slice(0, end + 1);
}

test('ci.yml wires detection, the iOS jobs and the CI Summary dependencies', () => {
  assert.match(jobBlock('detect-changes'), /id: filter[\s\S]*run: bash \.github\/scripts\/detect-changes\.sh/);
  for (const job of ['ios', 'ios_quality']) {
    assert.match(jobBlock(job), /if: needs\.detect-changes\.outputs\.ios == 'true'/, job);
  }
  assert.match(jobBlock('ci-summary'), /if: always\(\)[\s\S]*needs: \[detect-changes, mac-runner-routing-tests, js, ios, ios_quality\]/);
});

function runSummaryGate({ web, ios, js, iosResult, qualityResult }) {
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
    'needs.detect-changes.outputs.ios': ios,
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
