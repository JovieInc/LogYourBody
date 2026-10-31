import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

// CI run 40169457705 stayed queued until StoreKit got a macos-15 runner.
// 2026-10-25T07:54:19Z minus 2026-10-25T06:32:38Z. The four StoreKit tests
// then passed; this wait is not that result.
const MEASURED_MACOS_QUEUE_SECONDS = 4901;

// Main run 40937070309 exceeded the 45-minute job cap after the fourth
// method passed, before XCTest finalization and receipt upload completed.
// Reserve 15 more minutes for cold simulator/launch variance and receipts.
const STOREKIT_FOUR_LIFECYCLE_MINUTES = 45 + 15;

function source(path) {
  return readFileSync(path, 'utf8');
}

function jobSection(workflow, key) {
  const marker = `\n  ${key}:\n`;
  const start = workflow.indexOf(marker);
  assert.notEqual(start, -1, `missing job ${key}`);
  const rest = workflow.slice(start + 1);
  const next = rest.slice(marker.length - 1).search(/\n {2}[a-z0-9-]+:\n/);
  return next < 0 ? rest : rest.slice(0, next + marker.length);
}

function timeoutMinutes(section, label) {
  const match = section.match(/timeout-minutes:\s*(\d+)/);
  assert.ok(match, `${label} has no timeout-minutes`);
  return Number(match[1]);
}

test('enclosing release budget preserves native caps', () => {
  const release = source('.github/workflows/ios-release-loop.yml');
  const ci = source('.github/workflows/ci.yml');
  const unitWorkflow = source('.github/workflows/ios-unit.yml');
  const qualityWorkflow = source('.github/workflows/ios-quality.yml');
  const audit = source('scripts/ios/launch-quality-audit.sh');
  const shell = source('.github/scripts/validate-release-source.sh');

  assert.match(audit, /DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE="\$\{DEFAULT_TEST_EXECUTION_TIME_ALLOWANCE:-90\}"/);
  assert.match(audit, /MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE="\$\{MAXIMUM_TEST_EXECUTION_TIME_ALLOWANCE:-180\}"/);
  assert.match(audit, /XCODEBUILD_COMMAND_TIMEOUT_SECONDS="\$\{XCODEBUILD_COMMAND_TIMEOUT_SECONDS:-1020\}"/);
  assert.equal(timeoutMinutes(jobSection(qualityWorkflow, 'quality'), 'Launch Quality'), 64);

  const storekitMinutes = timeoutMinutes(jobSection(ci, 'ios_storekit'), 'StoreKit');
  assert.ok(
    storekitMinutes >= STOREKIT_FOUR_LIFECYCLE_MINUTES,
    `StoreKit cap ${storekitMinutes}m cancels the fourth lifecycle; need ${STOREKIT_FOUR_LIFECYCLE_MINUTES}m including finalization and receipts`,
  );
  const unitMinutes = timeoutMinutes(jobSection(unitWorkflow, 'unit'), 'iOS Unit');
  const minimumSeconds = (storekitMinutes + unitMinutes) * 60 + MEASURED_MACOS_QUEUE_SECONDS;
  const configured = Number(shell.match(/RELEASE_CHECK_TIMEOUT_SECONDS="\$\{RELEASE_CHECK_TIMEOUT_SECONDS:-(\d+)\}"/)[1]);
  assert.ok(configured >= minimumSeconds, `release wait ${configured}s does not enclose ${minimumSeconds}s`);

  const wait = jobSection(release, 'validate-release');
  assert.match(wait, /runs-on:\s*ubuntu-latest/);
  assert.doesNotMatch(wait, /macos-/);
  assert.match(wait, /validate-release-source\.sh/);
  assert.ok(timeoutMinutes(wait, 'Validate Release') * 60 > configured);

  const bind = jobSection(release, 'bind-release-version');
  assert.match(bind, /runs-on:\s*macos-26/);
  assert.match(bind, /xcodebuild/);
  assert.match(bind, /PINNED_VERSION/);
  assert.match(bind, /MARKETING_VERSION/);
  assert.match(bind, /verify-ios-auth-contract\.mjs/);
  assert.match(shell, /REQUIRED_CHECKS="\$\{REQUIRED_CHECKS:-CI Summary,JavaScript\/TypeScript,iOS\}"/);
});
