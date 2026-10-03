import assert from 'node:assert/strict';
import test from 'node:test';
import {
  findQuotedRefTargets,
  verifyRulesetTargets,
} from './verify-ruleset-targets.mjs';

const ciSummaryRule = {
  type: 'required_status_checks',
  parameters: {
    required_status_checks: [{ context: 'CI Summary', integration_id: 15368 }],
  },
};

const branchRuleset = (id, name, include, extra = {}) => ({
  id,
  name,
  target: 'branch',
  enforcement: 'active',
  conditions: { ref_name: { include, exclude: [] } },
  rules: [ciSummaryRule],
  ...extra,
});

const liveShape = [
  branchRuleset(6502188, 'Main - Protect', ['refs/heads/main']),
  branchRuleset(10470431, 'Production', ['refs/heads/production']),
];

test('current live ruleset shape satisfies the release gate contract', () => {
  assert.equal(verifyRulesetTargets(liveShape), true);
});

test('deliberate red: quoted include targets are rejected', () => {
  const rulesets = [
    branchRuleset(6502188, 'Main - Protect', ['refs/heads/"main"']),
    ...liveShape.slice(1),
  ];
  assert.throws(() => verifyRulesetTargets(rulesets), /embedded quotes/);
  assert.throws(
    () => verifyRulesetTargets(rulesets),
    /ruleset 6502188 \(Main - Protect\) include entry refs\/heads\/"main"/,
  );
});

test('deliberate red: quoted production target is rejected', () => {
  const rulesets = [
    liveShape[0],
    branchRuleset(10470431, 'Production', ['refs/heads/"production"']),
  ];
  assert.throws(() => verifyRulesetTargets(rulesets), /embedded quotes/);
});

test('deliberate red: quoted exclude targets are rejected', () => {
  const ruleset = {
    ...liveShape[0],
    conditions: { ref_name: { include: ['refs/heads/main'], exclude: ['refs/heads/"release"'] } },
  };
  assert.throws(() => verifyRulesetTargets([ruleset, liveShape[1]]), /embedded quotes/);
});

test('deliberate red: protected branch without ruleset coverage is rejected', () => {
  const rulesets = [liveShape[1]];
  assert.throws(
    () => verifyRulesetTargets(rulesets),
    /refs\/heads\/main is not covered by any active branch ruleset/,
  );
});

test('deliberate red: coverage without the CI Summary requirement is rejected', () => {
  const rulesets = [
    { ...liveShape[0], rules: [] },
    liveShape[1],
  ];
  assert.throws(
    () => verifyRulesetTargets(rulesets),
    /refs\/heads\/main has no active ruleset requiring the "CI Summary" status check/,
  );
});

test('disabled rulesets neither violate nor cover', () => {
  const disabledQuoted = {
    ...liveShape[0],
    enforcement: 'disabled',
    conditions: { ref_name: { include: ['refs/heads/"main"'], exclude: [] } },
  };
  assert.deepEqual(findQuotedRefTargets([disabledQuoted]), []);
  assert.throws(
    () => verifyRulesetTargets([disabledQuoted, liveShape[1]]),
    /refs\/heads\/main is not covered/,
  );
});

test('~ALL and ~DEFAULT_BRANCH count as coverage', () => {
  const rulesets = [
    branchRuleset(1, 'All branches', ['~ALL']),
    liveShape[1],
  ];
  assert.equal(verifyRulesetTargets(rulesets), true);
});
