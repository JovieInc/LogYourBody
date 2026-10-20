import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const stepScript = join(root, '.github/scripts/run-fastlane-step.sh');
const workflowPath = join(root, '.github/workflows/ios-release-loop.yml');

// The line that failed run 39477832062. It is Fastlane's upgrade note, not a
// precheck result. The same log also contained the real precheck failure below.
const UPGRADE_SIGNING_LINE =
  "* [action] clean_build_artifacts: say that cert's private key and signing request are kept (#30347)";
const IAP_API_KEY_ERROR =
  '[!] Precheck cannot check In-app purchases with the App Store Connect API Key (yet). Exclude In-app purchases from precheck, disable the precheck step in your build step, or use Apple ID login';

function workflowStep(name) {
  const workflow = readFileSync(workflowPath, 'utf8');
  const marker = `      - name: ${name}\n`;
  const start = workflow.indexOf(marker);
  assert.notEqual(start, -1, `missing step ${name}`);
  const rest = workflow.slice(start + marker.length);
  const next = rest.search(/\n      - name: |\n  [a-z0-9-]+:\n/);
  return next === -1 ? rest : rest.slice(0, next);
}

function fakeCommand(dir, body) {
  const command = join(dir, 'fake-fastlane.sh');
  writeFileSync(command, `#!/bin/sh\n${body}\n`);
  chmodSync(command, 0o755);
  return command;
}

function runStep(command) {
  const dir = mkdtempSync(join(tmpdir(), 'fastlane-step-'));
  try {
    const logFile = join(dir, 'step.log');
    const result = spawnSync('bash', [stepScript, logFile, command], { encoding: 'utf8' });
    return { ...result, log: readFileSync(logFile, 'utf8') };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('a successful fastlane run stays green when the upgrade note says signing', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fastlane-ok-'));
  try {
    const command = fakeCommand(
      dir,
      `printf '%s\\n' ${JSON.stringify(UPGRADE_SIGNING_LINE)}; exit 0`,
    );
    const result = runStep(command);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.log, /signing request are kept/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('fastlane non-zero status fails the step when the message has no scanned keyword', () => {
  const dir = mkdtempSync(join(tmpdir(), 'fastlane-fail-'));
  try {
    const command = fakeCommand(dir, `printf '%s\\n' ${JSON.stringify(IAP_API_KEY_ERROR)}; exit 1`);
    const result = runStep(command);
    assert.equal(result.status, 1);
    assert.match(result.log, /cannot check In-app purchases/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('missing arguments are a usage error', () => {
  const result = spawnSync('bash', [stepScript], { encoding: 'utf8' });
  assert.equal(result.status, 2);
  assert.match(result.stderr, /usage: run-fastlane-step\.sh/);
});

test('App Store precheck skips the API-key in-app purchase check and trusts fastlane status', () => {
  const precheck = workflowStep('Run Fastlane Precheck');
  assert.match(precheck, /run-fastlane-step\.sh/);
  assert.match(precheck, /bundle exec fastlane precheck include_in_app_purchases:false/);
  assert.match(precheck, /FASTLANE_SKIP_UPDATE_CHECK:\s+['"]1['"]/);
  assert.doesNotMatch(precheck, /grep -E/);

  const submit = workflowStep('Submit to App Store');
  assert.match(submit, /run-fastlane-step\.sh/);
  assert.match(submit, /FASTLANE_SKIP_UPDATE_CHECK:\s+['"]1['"]/);
  assert.doesNotMatch(submit, /grep -E/);
});
