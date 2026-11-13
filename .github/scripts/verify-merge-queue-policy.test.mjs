import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { refreshCompanyPins, verifyCompanyGuards, verifyPolicy, verifyRepository } from './verify-merge-queue-policy.mjs';
import './merge-queue-enrollment.test.mjs';

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
  pull_request:
    branches: [main, production]
  merge_group:
    branches: [main, production]
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
  const hasExplicitHold = !Array.isArray(pull.labels)
    || pull.labels.some(label => typeof label?.name !== 'string'
      || label.name.toLowerCase() === 'hold');
  if (hasExplicitHold) {
    await recordOutcome('NOT_ELIGIBLE', 'Pull request has an explicit hold or labels are unavailable');
    return;
  }
  enqueuePullRequest(input: { expectedHeadOid: pull.head.sha })
`;

test('current repository satisfies the native queue contract', () => {
  assert.equal(verifyRepository(process.cwd()), true);
});

test('Company Guards must block detection and the required CI Summary', () => {
  const ci = fs.readFileSync('.github/workflows/ci.yml', 'utf8');
  const guards = fs.readFileSync('.github/workflows/company-guards.yml', 'utf8');
  assert.equal(verifyCompanyGuards(ci, guards), true);
  for (const changed of [
    ci.replace('    needs: company-guards\n', ''),
    ci.replace('    needs: company-guards\n', '    needs: company-guards\n    if: always()\n'),
    ci.replace('    name: Company Guards\n', '    name: Company Guards\n    if: false\n'),
    ci.replace(
      '    name: Company Guards\n',
      '    name: Company Guards\n    continue-on-error: true\n',
    ),
    ci.replace('uses: ./.github/workflows/company-guards.yml', 'uses: ./advisory.yml'),
    ci.replace('    name: CI Summary\n', '    name: CI Summary\n    continue-on-error: true\n'),
    ci.replace('    if: always()\n    needs: [detect-changes,', '    needs: [detect-changes,'),
    ci.replace('      - name: Check results\n', '      - name: Check results\n        if: false\n'),
    ci.replace(
      '      - name: Check results\n',
      '      - name: Check results\n        continue-on-error: true\n',
    ),
    ci.replaceAll('needs: [detect-changes,', 'needs: ['),
    ci.replace('\n            exit 1\n', '\n            exit 0\n'),
    ci.replace('\n            exit 1\n', '\n'),
    ci.replace(
      'needs.detect-changes.result }}" != "success"',
      'needs.detect-changes.result }}" == "success"',
    ),
  ]) {
    assert.notEqual(changed, ci, 'negative control must change the workflow');
    assert.throws(() => verifyCompanyGuards(changed, guards), /Company Guards/);
  }
  assert.throws(
    () => verifyCompanyGuards(ci, guards.replace('  workflow_call:\n', '')),
    /Company Guards/,
  );
  const mismatchedPin = guards.replace(/ci-ref: [a-f0-9]{40}/, `ci-ref: ${'0'.repeat(40)}`);
  assert.notEqual(mismatchedPin, guards, 'negative control must change the guard pin');
  assert.throws(() => verifyCompanyGuards(ci, mismatchedPin), /Company Guards/);
  assert.throws(
    () =>
      verifyCompanyGuards(
        ci,
        guards.replace('    uses: JovieInc/ci/', '    if: false\n    uses: JovieInc/ci/'),
      ),
    /Company Guards/,
  );
});

function pinFixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'lyb-company-pins-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, '.github/workflows'), { recursive: true });
  const head = 'a'.repeat(40);
  const guard = 'b'.repeat(40);
  const older = 'c'.repeat(40);
  const files = ['company-guards', 'public-app-certification'].map((name) => {
    const file = path.join(root, `.github/workflows/${name}.yml`);
    const source = fs.readFileSync(`.github/workflows/${name}.yml`, 'utf8');
    fs.writeFileSync(file, source);
    return { file, source, pin: source.match(/ci-ref: ([a-f0-9]{40})/)[1] };
  });
  const tree = {
    truncated: false,
    tree: ['canon', 'guards', '.github/workflows/company-guards.yml'].map((name) => ({
      path: name, mode: name.endsWith('.yml') ? '100644' : '040000',
      type: name.endsWith('.yml') ? 'blob' : 'tree', sha: 'd'.repeat(40),
    })),
  };
  const api = (endpoint) => {
    if (endpoint === 'commits/main') return { sha: head };
    if (endpoint === `git/trees/${head}?recursive=1` || endpoint === `git/trees/${guard}?recursive=1`) return structuredClone(tree);
    assert.match(endpoint, new RegExp(`^commits\\?sha=${head}&path=.+&per_page=1$`));
    const isWorkflow = endpoint.includes('path=.github');
    return [{ sha: isWorkflow ? older : guard,
      commit: { committer: { date: isWorkflow ? '2026-11-11T00:00:00Z' : '2026-11-12T00:00:00Z' } } }];
  };
  return { root, files, head, guard, api };
}

test('company pin refresh selects guard history while retaining newer certification code', (t) => {
  const f = pinFixture(t);
  assert.deepEqual(refreshCompanyPins(f.root, f.api), { guards: f.guard, certification: f.head });
  for (const [index, { file, source, pin }] of f.files.entries()) {
    assert.equal(fs.readFileSync(file, 'utf8'), source.replaceAll(pin, index === 0 ? f.guard : f.head));
  }
  assert.deepEqual(refreshCompanyPins(f.root, f.api), { guards: f.guard, certification: f.head });
});

test('company pin refresh refuses lost guards, incomplete trees and missing history without writing', (t) => {
  const f = pinFixture(t);
  for (const [endpoint, result] of [
    [`git/trees/${f.guard}?recursive=1`, { truncated: false, tree: [] }],
    [`git/trees/${f.head}?recursive=1`, { truncated: true, tree: [] }],
    [`git/trees/${f.head}?recursive=1`, { truncated: false,
      tree: f.api(`git/trees/${f.head}?recursive=1`).tree.map(({ path }) => ({ path })) }],
    [`commits?sha=${f.head}&path=canon&per_page=1`, []],
    ['commits/main', { sha: 'main' }],
    [`commits?sha=${f.head}&path=guards&per_page=1`, [{ sha: f.guard, commit: { committer: { date: 'invalid' } } }]],
  ]) {
    assert.throws(() => refreshCompanyPins(f.root, (request) => request === endpoint ? result : f.api(request)),
      /Company|company/);
    for (const { file, source } of f.files) assert.equal(fs.readFileSync(file, 'utf8'), source);
  }
  const changed = f.api(`git/trees/${f.guard}?recursive=1`);
  changed.tree[0].sha = 'e'.repeat(40);
  assert.throws(() => refreshCompanyPins(f.root, (request) =>
    request === `git/trees/${f.guard}?recursive=1` ? changed : f.api(request)), /omit changes/);
  for (const { file, source } of f.files) assert.equal(fs.readFileSync(file, 'utf8'), source);
});

test('company pin refresh rejects mismatched, duplicate and mutable pins before either write', (t) => {
  const f = pinFixture(t);
  const { file, source } = f.files[1];
  for (const bad of [
    source.replace(/ci-ref: [a-f0-9]{40}/, `ci-ref: ${'f'.repeat(40)}`),
    `${source}      ci-ref: ${'f'.repeat(40)}\n`,
    source.replace(/ci-ref: [a-f0-9]{40}/, 'ci-ref: main'),
  ]) {
    fs.writeFileSync(file, bad);
    assert.throws(() => refreshCompanyPins(f.root, f.api), /unique full SHAs and agree/);
    assert.equal(fs.readFileSync(f.files[0].file, 'utf8'), f.files[0].source);
    assert.equal(fs.readFileSync(file, 'utf8'), bad);
  }
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

test('deliberate red: deleting or inverting the negative hold guard is rejected', () => {
  for (const enrollmentWorkflow of [
    validEnrollment.replace("label.name.toLowerCase() === 'hold'", "label.name.toLowerCase() === 'machine-certified'"),
    validEnrollment.replace('if (hasExplicitHold)', 'if (!hasExplicitHold)'),
    validEnrollment.replace("!Array.isArray(pull.labels)", "Array.isArray(pull.labels)"),
  ]) {
    assert.throws(() => verifyPolicy({
      policy: validPolicy, ciWorkflow: validCI, enrollmentWorkflow,
    }), /must preserve explicit holds|must return before admission/);
  }
});
