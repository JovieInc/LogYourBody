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

test('deliberate red: protected branch rulesets cannot configure bypass actors', () => {
  const rulesets = [
    {
      ...liveShape[0],
      bypass_actors: [{ actor_id: 1, actor_type: 'OrganizationAdmin', bypass_mode: 'always' }],
    },
    liveShape[1],
  ];
  assert.throws(
    () => verifyRulesetTargets(rulesets),
    /protected branch rulesets allow bypass actors.*OrganizationAdmin.*mode=always/,
  );
});

test('deliberate red: unrestricted current-user bypass is rejected', () => {
  const rulesets = [
    { ...liveShape[0], current_user_can_bypass: 'always' },
    liveShape[1],
  ];
  assert.throws(
    () => verifyRulesetTargets(rulesets),
    /protected branch rulesets allow bypass actors.*current user mode=always/,
  );
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

test('~ALL covers both protected branches', () => {
  const rulesets = [
    branchRuleset(1, 'All branches', ['~ALL']),
    liveShape[1],
  ];
  assert.equal(verifyRulesetTargets(rulesets), true);
});

test('deliberate red: evaluate-only rulesets cannot cover protected branches', () => {
  assert.throws(
    () => verifyRulesetTargets([
      { ...liveShape[0], enforcement: 'evaluate' },
      liveShape[1],
    ]),
    /refs\/heads\/main is not covered by any active branch ruleset/,
  );
});

test('deliberate red: the default branch token cannot also cover production', () => {
  assert.throws(
    () => verifyRulesetTargets([
      branchRuleset(1, 'Default branch', ['~DEFAULT_BRANCH']),
    ], { defaultBranch: 'main' }),
    /refs\/heads\/production is not covered by any active branch ruleset/,
  );
});

test('default branch token plus explicit production covers both branches', () => {
  assert.equal(verifyRulesetTargets([
    branchRuleset(1, 'Default branch', ['~DEFAULT_BRANCH']),
    liveShape[1],
  ], { defaultBranch: 'main' }), true);
});

test('default branch token follows a renamed repository default', () => {
  assert.equal(verifyRulesetTargets([
    branchRuleset(1, 'Default branch', ['~DEFAULT_BRANCH']),
    liveShape[1],
  ], { protectedBranches: ['trunk', 'production'], defaultBranch: 'trunk' }), true);
});


test('only active enforcement can satisfy protected branch coverage', () => {
  for (const enforcement of [undefined, null, 'unknown']) {
    assert.throws(
      () => verifyRulesetTargets([{ ...liveShape[0], enforcement }, liveShape[1]]),
      /refs\/heads\/main is not covered/,
    );
  }
});

test('default branch token can refer to production without covering main', () => {
  assert.equal(verifyRulesetTargets([
    liveShape[0],
    branchRuleset(1, 'Default branch', ['~DEFAULT_BRANCH']),
  ], { defaultBranch: 'production' }), true);
});

test('exact and all-branch exclusions still remove coverage', () => {
  for (const exclude of [['refs/heads/production'], ['~ALL']]) {
    const ruleset = branchRuleset(1, 'All branches with exclusions', ['~ALL'], {
      conditions: { ref_name: { include: ['~ALL'], exclude } },
    });
    assert.throws(() => verifyRulesetTargets([ruleset]), /is not covered/);
  }
});

test('default branch exclusion removes only the actual default branch', () => {
  const exceptDefault = branchRuleset(1, 'Other branches', ['~ALL'], {
    conditions: { ref_name: { include: ['~ALL'], exclude: ['~DEFAULT_BRANCH'] } },
  });
  assert.equal(verifyRulesetTargets([exceptDefault, liveShape[0]], {
    defaultBranch: 'main',
  }), true);
  assert.throws(() => verifyRulesetTargets([exceptDefault], {
    defaultBranch: 'main',
  }), /refs\/heads\/main is not covered/);
});

test('default branch include and exclude require actual repository metadata', () => {
  for (const refName of [
    { include: ['~DEFAULT_BRANCH'], exclude: [] },
    { include: ['~ALL'], exclude: ['~DEFAULT_BRANCH'] },
  ]) {
    const ruleset = branchRuleset(1, 'Default-aware branches', [], {
      conditions: { ref_name: refName },
    });
    for (const defaultBranch of [undefined, null, '']) {
      assert.throws(() => verifyRulesetTargets([ruleset], { defaultBranch }),
        /requires the actual repository default branch/);
    }
  }
});
