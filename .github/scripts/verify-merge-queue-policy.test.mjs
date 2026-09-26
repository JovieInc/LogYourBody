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

const validTokenEnrollment = `
on:
  workflow_run:
    workflows: [Native Merge Queue Enrollment]
script: |
  github-token: \${{ secrets.MERGE_QUEUE_TOKEN }}
  const summary = checks.find((check) => check.name === 'CI Summary');
  if (pull.headRepository?.nameWithOwner !== \`\${owner}/\${repo}\`) continue;
  dequeuePullRequest(input: { id: $id })
  enqueuePullRequest(input: { pullRequestId: $id, expectedHeadOid: pull.headRefOid })
`;

const tokenPolicy = {
  ...validPolicy,
  token_enrollment: { workflow: 'token.yml', secret: 'MERGE_QUEUE_TOKEN' },
};

const validEnrollment = `
on:
  workflow_run:
    workflows: [CI]
permissions:
  pull-requests: write
script: |
  const recordOutcome = () => {};
  if (run.conclusion !== 'success') return;
  if (pull.draft) return;
  if (pull.head.sha !== run.head_sha) return;
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

test('token enrollment contract is accepted when checkout-free and off pull-request events', () => {
  assert.equal(
    verifyPolicy({
      policy: tokenPolicy,
      ciWorkflow: validCI,
      enrollmentWorkflow: validEnrollment,
      tokenEnrollmentWorkflow: validTokenEnrollment,
    }),
    true,
  );
});

test('deliberate red: token enrollment that checks out code or runs on pull requests is rejected', () => {
  assert.throws(
    () => verifyPolicy({
      policy: tokenPolicy,
      ciWorkflow: validCI,
      enrollmentWorkflow: validEnrollment,
      tokenEnrollmentWorkflow: validTokenEnrollment + '  - uses: actions/checkout@v6\n',
    }),
    /must not checkout code/,
  );
  assert.throws(
    () => verifyPolicy({
      policy: tokenPolicy,
      ciWorkflow: validCI,
      enrollmentWorkflow: validEnrollment,
      tokenEnrollmentWorkflow: validTokenEnrollment.replace('workflow_run:', 'pull_request_target:'),
    }),
    /missing required contract|must not run on pull request/,
  );
});

test('deliberate red: token enrollment without the exact-head re-proof is rejected', () => {
  assert.throws(
    () => verifyPolicy({
      policy: tokenPolicy,
      ciWorkflow: validCI,
      enrollmentWorkflow: validEnrollment,
      tokenEnrollmentWorkflow: validTokenEnrollment.replace("check.name === 'CI Summary'", "check.name === 'anything'"),
    }),
    /missing required contract/,
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

test('deliberate red: a label gate on enrollment is rejected', () => {
  assert.throws(
    () => verifyPolicy({
      policy: validPolicy,
      ciWorkflow: validCI,
      enrollmentWorkflow: `${validEnrollment}\n  if (!pull.labels.some(({ name }) => name === 'machine-certified')) return;`,
    }),
    /must not gate on PR labels/,
  );
});

test('deliberate red: a policy requiring a certification label is rejected', () => {
  assert.throws(
    () => verifyPolicy({
      policy: {
        ...validPolicy,
        auto_enrollment: { ...validPolicy.auto_enrollment, certification_label: 'machine-certified' },
      },
      ciWorkflow: validCI,
      enrollmentWorkflow: validEnrollment,
    }),
    /must not require a certification label/,
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
