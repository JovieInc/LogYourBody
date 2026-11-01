// Signing-input cases for detect-changes.sh and the CI Summary gate.
// Kept out of detect-changes.test.mjs so that baselined file does not grow.
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
const gitEnv = Object.assign(Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('GIT_'))), {
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

function queueFixture(groupTwoFiles) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'detect-signing-'));
  const origin = path.join(root, 'origin');
  fs.mkdirSync(origin);
  git(origin, 'init', '-q', '-b', 'main');
  git(origin, 'config', 'uploadpack.allowAnySHA1InWant', 'true');
  commit(origin, { 'apps/ios/App.swift': 'v1', 'apps/web/page.tsx': 'v1', 'package.json': '{}' }, 'main');
  const groupOne = commit(origin, { 'apps/ios/App.swift': 'v2' }, 'group 1');
  const groupTwo = commit(origin, groupTwoFiles, 'group 2');
  const workspace = path.join(root, 'workspace');
  git(root, 'clone', '-q', '--depth=1', '--no-tags', `file://${origin}`, workspace);
  return { root, workspace, groupOne, groupTwo };
}

function detect(workspace, env) {
  const output = path.join(workspace, '..', `output-${Math.random().toString(36).slice(2)}`);
  fs.writeFileSync(output, '');
  const result = spawnSync('bash', [detectScript], {
    cwd: workspace,
    encoding: 'utf8',
    env: { ...gitEnv, PATH: process.env.PATH, GITHUB_OUTPUT: output, GITHUB_REPOSITORY: 'JovieInc/LogYourBody', ...env },
  });
  assert.equal(result.status, 0, result.stderr);
  return Object.fromEntries(fs.readFileSync(output, 'utf8').trim().split('\n').map((line) => line.split('=')));
}

function jobBlock(name) {
  const start = ciWorkflow.indexOf(`\n  ${name}:\n`);
  assert.notEqual(start, -1, `ci.yml has no ${name} job`);
  const rest = ciWorkflow.slice(start + 1);
  const end = rest.slice(1).search(/\n {2}[A-Za-z0-9_-]+:\n/);
  return end === -1 ? rest : rest.slice(0, end + 1);
}

function runSummaryGate({ signing, signingResult, signingConclusion, fork }) {
  const block = jobBlock('ci-summary');
  const script = block.slice(block.indexOf('run: |') + 'run: |'.length).split('\n').map((line) => line.replace(/^ {10}/, '')).join('\n');
  const values = {
    'github.event_name': 'pull_request',
    'needs.detect-changes.result': 'success',
    'needs.mac-runner-routing-tests.result': 'success',
    'needs.detect-changes.outputs.web': 'false',
    'needs.detect-changes.outputs.ios_unit': 'false',
    'needs.detect-changes.outputs.ios_quality': 'false',
    'needs.detect-changes.outputs.ios_quality_deferred': 'false',
    'needs.detect-changes.outputs.ios_changed': 'false',
    'needs.js.result': 'skipped',
    'needs.ios.result': 'skipped',
    'needs.ios_quality.result': 'skipped',
    'needs.ios_static.result': 'skipped',
    'needs.ios_storekit.result': 'skipped',
    'needs.detect-changes.outputs.signing': signing,
    'needs.release-signing.result': signingResult,
    'needs.release-signing.outputs.conclusion': signingConclusion,
    'github.event.pull_request.head.repo.fork': fork,
  };
  const rendered = script.replace(/\$\{\{\s*([^}]+?)\s*\}\}/g, (_, expr) => {
    assert.ok(expr in values, `unrendered expression ${expr}`);
    return values[expr];
  });
  const summary = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'ci-summary-')), 'summary.md');
  return spawnSync('bash', ['-e', '-c', rendered], { encoding: 'utf8', env: { ...process.env, GITHUB_STEP_SUMMARY: summary } }).status;
}

test('signing inputs select the release provisioning check and other files do not', () => {
  const cases = [
    ['apps/ios/fastlane/Fastfile.release', 'true', 'true'],
    ['apps/ios/LogYourBody.xcodeproj/project.pbxproj', 'true', 'true'],
    ['apps/ios/LogYourBody/LogYourBody.entitlements', 'true', 'true'],
    ['apps/ios/App.swift', 'false', 'true'],
    ['.github/scripts/release-signing-provisioned.mjs', 'true', 'false'],
    ['.github/scripts/release-signing-project.mjs', 'true', 'false'],
  ];
  for (const [file, signing, iosChanged] of cases) {
    const fx = queueFixture({ [file]: 'changed' });
    try {
      const outputs = detect(fx.workspace, {
        GITHUB_EVENT_NAME: 'pull_request',
        PR_DRAFT: 'false',
        BASE_SHA: fx.groupOne,
        HEAD_SHA: fx.groupTwo,
      });
      assert.equal(outputs.signing, signing, file);
      assert.equal(outputs.ios_changed, iosChanged, file);
    } finally {
      fs.rmSync(fx.root, { recursive: true, force: true });
    }
  }
});

test('CI Summary requires release signing only when signing inputs change', () => {
  assert.equal(runSummaryGate({ signing: 'false', signingResult: 'skipped', signingConclusion: '', fork: 'false' }), 0);
  assert.notEqual(runSummaryGate({ signing: 'false', signingResult: 'success', signingConclusion: 'success', fork: 'false' }), 0);
  assert.equal(runSummaryGate({ signing: 'true', signingResult: 'success', signingConclusion: 'success', fork: 'false' }), 0);
  assert.notEqual(runSummaryGate({ signing: 'true', signingResult: 'success', signingConclusion: 'neutral', fork: 'false' }), 0);
  assert.notEqual(runSummaryGate({ signing: 'true', signingResult: 'failure', signingConclusion: 'failure', fork: 'false' }), 0);
  assert.notEqual(runSummaryGate({ signing: 'true', signingResult: 'skipped', signingConclusion: '', fork: 'false' }), 0);
  assert.equal(runSummaryGate({ signing: 'true', signingResult: 'success', signingConclusion: 'neutral', fork: 'true' }), 0);
  assert.notEqual(runSummaryGate({ signing: 'true', signingResult: 'success', signingConclusion: 'success', fork: 'true' }), 0);
});

test('ci.yml wires the release signing job and keeps its tests with change detection', () => {
  const detection = jobBlock('detect-changes');
  assert.match(detection, /signing: \$\{\{ steps\.filter\.outputs\.signing \}\}/);
  assert.match(detection, /node --test \.github\/scripts\/detect-changes\.test\.mjs \.github\/scripts\/detect-changes-signing\.test\.mjs/);
  const signing = jobBlock('release-signing');
  assert.match(signing, /if: needs\.detect-changes\.outputs\.signing == 'true'/);
  assert.match(signing, /node --test \.github\/scripts\/release-signing-provisioned\.test\.mjs/);
  assert.match(signing, /node \.github\/scripts\/release-signing-provisioned\.mjs/);
  assert.match(signing, /FORK: \$\{\{ github\.event\.pull_request\.head\.repo\.fork == true \}\}/);
});
