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
  ],
  enrollment: [
    /workflow_run:/,
    /workflows:\s*\[CI\]/,
    /pull-requests:\s*write/,
    /run\.conclusion !== 'success'/,
    /recordOutcome/,
    /pull\.head\.sha !== run\.head_sha/,
    /machine-certified/,
    /enqueuePullRequest/,
    /expectedHeadOid:\s*pull\.head\.sha/,
  ],
};

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

export function verifyPolicy({ policy, ciWorkflow, enrollmentWorkflow }) {
  assert(policy.schema_version === 1, 'policy schema_version must be 1');
  assert(policy.repository === 'JovieInc/LogYourBody', 'policy must remain repository-local');
  assert(
    policy.target_ref === 'refs/heads/main',
    'target_ref must be refs/heads/main with no embedded quotes',
  );
  assert(policy.required_status_check === 'CI Summary', 'required status must be CI Summary');
  assert(policy.merge_queue?.required === true, 'native merge queue must be required');
  assert(policy.merge_queue?.merge_method === 'MERGE', 'queue merge method must be MERGE');
  assert(
    policy.auto_enrollment?.certification_label === 'machine-certified',
    'auto-enrollment must require the machine-certified label',
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

  assert(!/actions\/checkout@/.test(enrollmentWorkflow), 'privileged enrollment must not checkout code');
  assert(!/secrets\./.test(enrollmentWorkflow), 'auto-enrollment must not receive repository secrets');
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
  return verifyPolicy({ policy, ciWorkflow, enrollmentWorkflow });
}

const isMainModule = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (isMainModule) {
  verifyRepository(process.cwd());
  console.log('Repository-native merge queue policy verified.');
}
