import assert from 'node:assert/strict';
import test from 'node:test';
import { verifyPolicy, verifyRepository } from './verify-merge-queue-policy.mjs';

const validPolicy = {
  schema_version: 1,
  repository: 'JovieInc/LogYourBody',
  target_ref: 'refs/heads/main',
  required_status_check: 'CI Summary',
  merge_queue: { required: true, merge_method: 'MERGE' },
  auto_enrollment: {
    certification_label: 'machine-certified',
    exact_head_required: true,
    same_repository_only: true,
  },
};

const validCI = `
on:
  merge_group:
    branches: [main]
    types: [checks_requested]
concurrency:
  cancel-in-progress: \${{ github.event_name != 'merge_group' }}
env:
  BASE_SHA: \${{ github.event_name == 'merge_group' && github.event.merge_group.base_sha }}
  HEAD_SHA: \${{ github.event_name == 'merge_group' && github.event.merge_group.head_sha }}
run: |
  assert_expected_result
  [[ "\${{ needs.detect-changes.result }}" == "success" ]]
`;

const validEnrollment = `
on:
  workflow_run:
    workflows: [CI]
permissions:
  pull-requests: write
script: |
  const recordOutcome = () => {};
  if (run.conclusion !== 'success') return;
  if (pull.head.sha !== run.head_sha) return;
  const label = 'machine-certified';
  enqueuePullRequest(input: { expectedHeadOid: pull.head.sha })
`;

test('current repository satisfies the native queue contract', () => {
  assert.equal(verifyRepository(process.cwd()), true);
});

test('deliberate red: quoted branch patterns are rejected', () => {
  assert.throws(
    () => verifyPolicy({
      policy: { ...validPolicy, target_ref: 'refs/heads/"main"' },
      ciWorkflow: validCI,
      enrollmentWorkflow: validEnrollment,
    }),
    /embedded quotes/,
  );
});

test('deliberate red: CI without merge_group coverage is rejected', () => {
  assert.throws(
    () => verifyPolicy({
      policy: validPolicy,
      ciWorkflow: validCI.replace('merge_group:', 'pull_request:'),
      enrollmentWorkflow: validEnrollment,
    }),
    /CI workflow is missing required contract/,
  );
});

test('deliberate red: merge-group CI cancellation is rejected', () => {
  assert.throws(
    () => verifyPolicy({
      policy: validPolicy,
      ciWorkflow: validCI.replace(
        "cancel-in-progress: \${{ github.event_name != 'merge_group' }}",
        'cancel-in-progress: true',
      ),
      enrollmentWorkflow: validEnrollment,
    }),
    /CI workflow is missing required contract/,
  );
});

test('deliberate red: enrollment without exact-head proof is rejected', () => {
  assert.throws(
    () => verifyPolicy({
      policy: validPolicy,
      ciWorkflow: validCI,
      enrollmentWorkflow: validEnrollment.replace('pull.head.sha !== run.head_sha', 'false'),
    }),
    /auto-enrollment workflow is missing required contract/,
  );
});

test('deliberate red: privileged enrollment may not checkout code', () => {
  assert.throws(
    () => verifyPolicy({
      policy: validPolicy,
      ciWorkflow: validCI,
      enrollmentWorkflow: `${validEnrollment}\n- uses: actions/checkout@v6`,
    }),
    /must not checkout code/,
  );
});
