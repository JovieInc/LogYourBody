import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const requiredFragments = {
  ci: [
    /\n\s*merge_group:\s*\n\s*branches:\s*\[main\]/,
    /types:\s*\[checks_requested\]/,
    /cancel-in-progress:\s*\$\{\{ github\.event_name != 'merge_group'/,
    /github\.event_name == 'merge_group'/,
    /github\.event\.merge_group\.base_sha/,
    /github\.event\.merge_group\.head_sha/,
    /assert_expected_result/,
    /needs\.detect-changes\.result[^\n]+success/,
    /\n\s*workflow_dispatch:\s*\n/,
    /merge_group_base_sha/,
  ],
  kicker: [
    /\n\s*schedule:\s*\n/,
    /listMatchingRefs/,
    /gh-readonly-queue\/main\//,
    /listWorkflowRuns/,
    /createWorkflowDispatch/,
    /merge_group_base_sha/,
  ],
  enrollment: [
    /workflow_run:/,
    /workflows:\s*\[CI\]/,
    /pull-requests:\s*write/,
    /run\.conclusion !== 'success'/,
    /recordOutcome/,
    /pull\.head\.sha !== run\.head_sha/,
    /pull\.draft/,
    /enqueuePullRequest/,
    /expectedHeadOid:\s*pull\.head\.sha/,
  ],
};

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

export function verifyPolicy({ policy, ciWorkflow, enrollmentWorkflow, kickerWorkflow }) {
  assert(policy.schema_version === 1, 'policy schema_version must be 1');
  assert(policy.repository === 'JovieInc/LogYourBody', 'policy must remain repository-local');
  assert(
    policy.target_ref === 'refs/heads/main',
    'target_ref must be refs/heads/main with no embedded quotes',
  );
  assert(policy.required_status_check === 'CI Summary', 'required status must be CI Summary');
  assert(policy.merge_queue?.required === true, 'native merge queue must be required');
  assert(policy.merge_queue?.merge_method === 'MERGE', 'queue merge method must be MERGE');
  // PRs land on normal checks alone; certification happens post-merge (canary/dogfood), never as a PR gate.
  assert(
    policy.auto_enrollment?.certification_label === undefined,
    'auto-enrollment must not require a certification label',
  );
  assert(policy.auto_enrollment?.exact_head_required === true, 'exact-head proof is required');
  assert(policy.auto_enrollment?.same_repository_only === true, 'fork auto-enrollment is forbidden');

  for (const fragment of requiredFragments.ci) {
    assert(fragment.test(ciWorkflow), `CI workflow is missing required contract: ${fragment}`);
  }
  for (const fragment of requiredFragments.enrollment) {
    assert(
      fragment.test(enrollmentWorkflow),
      `auto-enrollment workflow is missing required contract: ${fragment}`,
    );
  }

  assert(!/labels\.some|\.labels\b/.test(enrollmentWorkflow), 'auto-enrollment must not gate on PR labels');
  assert(!/actions\/checkout@/.test(enrollmentWorkflow), 'privileged enrollment must not checkout code');
  assert(!/secrets\./.test(enrollmentWorkflow), 'auto-enrollment must not receive repository secrets');

  if (policy.merge_group_ci) {
    assert(
      policy.merge_group_ci.dispatch_input === 'merge_group_base_sha',
      'merge-group CI dispatch input must be merge_group_base_sha',
    );
    assert(typeof kickerWorkflow === 'string', 'merge-group CI kicker workflow must exist');
    for (const fragment of requiredFragments.kicker) {
      assert(fragment.test(kickerWorkflow), `merge-group CI kicker is missing required contract: ${fragment}`);
    }
    assert(!/actions\/checkout@/.test(kickerWorkflow), 'merge-group CI kicker must not checkout code');
    assert(!/secrets\./.test(kickerWorkflow), 'merge-group CI kicker must not receive repository secrets');
    assert(!/pull_request/.test(kickerWorkflow), 'merge-group CI kicker must not run on pull request events');
  }
  return true;
}

export function verifyRepository(rootDirectory) {
  const policyPath = path.join(rootDirectory, '.github/merge-queue-policy.json');
  const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8'));
  const ciWorkflow = fs.readFileSync(path.join(rootDirectory, '.github/workflows/ci.yml'), 'utf8');
  const enrollmentWorkflow = fs.readFileSync(
    path.join(rootDirectory, policy.auto_enrollment.workflow),
    'utf8',
  );
  const kickerWorkflow = policy.merge_group_ci
    ? fs.readFileSync(path.join(rootDirectory, policy.merge_group_ci.kicker_workflow), 'utf8')
    : undefined;
  return verifyPolicy({ policy, ciWorkflow, enrollmentWorkflow, kickerWorkflow });
}

const isMainModule = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (isMainModule) {
  verifyRepository(process.cwd());
  console.log('Repository-native merge queue policy verified.');
}
