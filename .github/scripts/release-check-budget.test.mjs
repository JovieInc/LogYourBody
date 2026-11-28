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

function stepSection(job, name) {
  const marker = `      - name: ${name}\n`;
  assert.ok(job.includes(marker), `missing step ${name}`);
  return job.split(marker)[1].split('\n      - ')[0];
}

function assertLaunchQualityBudget(quality, audit) {
  const deadline = audit.match(/AUDIT_DEADLINE_SECONDS="\$\{AUDIT_DEADLINE_SECONDS:-(\d+)\}"/);
  assert.ok(deadline, 'missing launch-quality audit deadline');
  const watcher = source('scripts/ios/xcodebuild-command-timeout.py');
  const grace = watcher.match(/^MAX_FINALIZATION_GRACE_SECONDS = (\d+)$/m);
  assert.ok(grace, 'missing xcodebuild finalization grace');
  const launchMinutes = timeoutMinutes(
    stepSection(quality, 'Run launch quality audit'),
    'Launch audit',
  );
  const performanceMinutes = timeoutMinutes(
    stepSection(quality, 'Run performance budget audit'),
    'Performance audit',
  );
  assert.ok(
    launchMinutes * 60 >= Number(deadline[1]) + Number(grace[1]),
    'Launch audit step must enclose its deadline plus finalization grace',
  );
  // Preserve the existing 4-minute setup allowance around both audit steps.
  assert.ok(
    timeoutMinutes(quality, 'Launch Quality') >= 4 + launchMinutes + performanceMinutes,
    'Launch Quality job must enclose setup and both audit steps',
  );
}

function withTimeout(section, minutes) {
  return section.replace(/timeout-minutes:\s*\d+/, `timeout-minutes: ${minutes}`);
}

test('launch-quality budget rejects undersized enclosing caps and accepts coordinated growth', () => {
  const quality = jobSection(source('.github/workflows/ios-quality.yml'), 'quality');
  const audit = source('scripts/ios/launch-quality-audit.sh');
  const launch = stepSection(quality, 'Run launch quality audit');
  const performance = stepSection(quality, 'Run performance budget audit');
  const launchMinutes = timeoutMinutes(launch, 'Launch audit');
  const performanceMinutes = timeoutMinutes(performance, 'Performance audit');
  const deadline = audit.match(/AUDIT_DEADLINE_SECONDS:-(\d+)/)[1];
  const grace = Number(
    source('scripts/ios/xcodebuild-command-timeout.py').match(
      /^MAX_FINALIZATION_GRACE_SECONDS = (\d+)$/m,
    )[1],
  );
  assert.throws(
    () =>
      assertLaunchQualityBudget(
        withTimeout(quality, 3 + launchMinutes + performanceMinutes),
        audit,
      ),
    /job must enclose setup and both audit steps/,
  );
  assert.throws(
    () =>
      assertLaunchQualityBudget(
        quality.replace(
          launch,
          withTimeout(launch, Math.ceil((Number(deadline) + grace) / 60) - 1),
        ),
        audit,
      ),
    /step must enclose its deadline plus finalization grace/,
  );
  const longerAudit = audit.replace(
    `AUDIT_DEADLINE_SECONDS:-${deadline}`,
    `AUDIT_DEADLINE_SECONDS:-${launchMinutes * 60 - grace + 1}`,
  );
  const longerStep = quality.replace(launch, withTimeout(launch, launchMinutes + 1));
  assert.throws(
    () => assertLaunchQualityBudget(quality, longerAudit),
    /step must enclose its deadline plus finalization grace/,
  );
  assert.doesNotThrow(() =>
    assertLaunchQualityBudget(
      withTimeout(longerStep, timeoutMinutes(quality, 'Launch Quality') + 1),
      longerAudit,
    ),
  );
});

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
  assertLaunchQualityBudget(jobSection(qualityWorkflow, 'quality'), audit);

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
