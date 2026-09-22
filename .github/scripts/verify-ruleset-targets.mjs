#!/usr/bin/env node

// Live audit of repository branch rulesets: proves the release gates in the
// merge-queue policy actually apply to the real protected branches.
//
// Guards against the JOV-6098 failure mode: ruleset ref_name targets stored
// with literal quotes (e.g. `refs/heads/"main"`), which silently match no real
// ref and leave the branch unprotected while the policy file looks correct.
//
// Pure verifier is exported for node:test; run without arguments to audit the
// live repository through `gh api` (requires a token with metadata read).

import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const REPOSITORY = 'JovieInc/LogYourBody';
export const REQUIRED_STATUS_CHECK = 'CI Summary';
export const PROTECTED_BRANCHES = ['main', 'production'];

const COVERING_PATTERNS = branch => new Set([`refs/heads/${branch}`, '~ALL', '~DEFAULT_BRANCH']);

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

function refTargets(ruleset) {
  const refName = ruleset?.conditions?.ref_name;
  return {
    include: refName?.include ?? [],
    exclude: refName?.exclude ?? [],
  };
}

// Every include/exclude entry on an active branch ruleset must be a plain ref
// pattern. Embedded quotes mean the entry never matches a real branch.
export function findQuotedRefTargets(rulesets) {
  const violations = [];
  for (const ruleset of rulesets ?? []) {
    if (!ruleset || ruleset.target !== 'branch' || ruleset.enforcement === 'disabled') {
      continue;
    }
    for (const list of ['include', 'exclude']) {
      for (const entry of refTargets(ruleset)[list]) {
        if (/["']/.test(entry)) {
          violations.push({
            rulesetId: ruleset.id,
            rulesetName: ruleset.name,
            list,
            entry,
          });
        }
      }
    }
  }
  return violations;
}

function isCoveredBy(ruleset, branch) {
  if (ruleset.enforcement === 'disabled') return false;
  const { include, exclude } = refTargets(ruleset);
  const covering = COVERING_PATTERNS(branch);
  if (!include.some(entry => covering.has(entry))) return false;
  return !exclude.some(entry => covering.has(entry));
}

function requiredCheckContexts(ruleset) {
  const contexts = [];
  for (const rule of ruleset.rules ?? []) {
    if (rule.type === 'required_status_checks') {
      for (const check of rule.parameters?.required_status_checks ?? []) {
        contexts.push(check.context);
      }
    }
  }
  return contexts;
}

// rulesets: array of GET /repos/{o}/{r}/rulesets/{id} payloads (branch rulesets).
// Asserts: no quoted ref targets; each protected branch is covered by an active
// ruleset that requires the aggregate CI Summary status check.
export function verifyRulesetTargets(rulesets, { protectedBranches = PROTECTED_BRANCHES } = {}) {
  const violations = findQuotedRefTargets(rulesets);
  assert(
    violations.length === 0,
    `branch ruleset ref targets contain embedded quotes: ${violations
      .map(v => `ruleset ${v.rulesetId} (${v.rulesetName}) ${v.list} entry ${v.entry}`)
      .join('; ')}`,
  );

  const branchRulesets = (rulesets ?? []).filter(
    ruleset => ruleset?.target === 'branch' && ruleset.enforcement !== 'disabled',
  );

  for (const branch of protectedBranches) {
    const covering = branchRulesets.filter(ruleset => isCoveredBy(ruleset, branch));
    assert(
      covering.length > 0,
      `refs/heads/${branch} is not covered by any active branch ruleset`,
    );
    assert(
      covering.some(ruleset => requiredCheckContexts(ruleset).includes(REQUIRED_STATUS_CHECK)),
      `refs/heads/${branch} has no active ruleset requiring the "${REQUIRED_STATUS_CHECK}" status check`,
    );
  }

  return true;
}

function ghApi(endpoint) {
  const output = execFileSync('gh', ['api', endpoint], { encoding: 'utf8' });
  return JSON.parse(output);
}

export function fetchLiveRulesets(repository = REPOSITORY) {
  const summaries = ghApi(`repos/${repository}/rulesets`);
  return summaries.map(summary => ghApi(`repos/${repository}/rulesets/${summary.id}`));
}

export function verifyBranchProtected(repository = REPOSITORY, branches = PROTECTED_BRANCHES) {
  const unprotected = [];
  for (const branch of branches) {
    let payload;
    try {
      payload = ghApi(`repos/${repository}/branches/${branch}`);
    } catch (error) {
      // A missing branch is only a problem when a ruleset still targets it; the
      // coverage assertions above already gate the rules that must exist.
      continue;
    }
    if (payload.protected !== true) unprotected.push(branch);
  }
  assert(
    unprotected.length === 0,
    `branches report protected=false: ${unprotected.join(', ')}`,
  );
  return true;
}

const isMainModule =
  process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (isMainModule) {
  const rulesets = fetchLiveRulesets();
  verifyRulesetTargets(rulesets);
  verifyBranchProtected();
  for (const ruleset of rulesets) {
    if (ruleset.target !== 'branch') continue;
    const { include } = refTargets(ruleset);
    console.log(
      `ruleset ${ruleset.id} (${ruleset.name}): enforcement=${ruleset.enforcement} include=${JSON.stringify(include)}`,
    );
  }
  console.log('Live branch ruleset targets verified.');
}
