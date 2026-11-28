#!/usr/bin/env node

import { readFileSync } from 'node:fs';

import { scan as scanAiReviewBoundary } from './verify-ai-review-boundary.mjs';

const workflowFiles = [
  '.github/workflows/ci.yml',
  '.github/workflows/deploy.yml',
  '.github/workflows/ios-release-loop.yml',
];

const readWorkflow = file => readFileSync(file, 'utf8');
const failures = [];

const ci = readWorkflow('.github/workflows/ci.yml');
if (!ci.includes("github.ref == 'refs/heads/main'")) {
  failures.push('ci.yml must special-case refs/heads/main in its concurrency policy.');
}
if (!ci.includes('github.sha')) {
  failures.push('ci.yml must key main-branch concurrency by github.sha.');
}
if (
  !ci.includes(
    "cancel-in-progress: ${{ github.event_name != 'merge_group' && github.ref != 'refs/heads/main' }}",
  )
) {
  failures.push(
    'ci.yml must keep PR cancellation while preserving main and merge-group runs.',
  );
}
if (!ci.includes('node .github/scripts/verify-workflow-concurrency.mjs')) {
  failures.push('ci.yml must run the workflow concurrency verifier.');
}

for (const file of ['.github/workflows/deploy.yml', '.github/workflows/ios-release-loop.yml']) {
  const workflow = readWorkflow(file);
  if (!workflow.includes('cancel-in-progress: false')) {
    failures.push(`${file} must not cancel in-progress production runs.`);
  }
}

for (const file of workflowFiles) {
  const workflow = readWorkflow(file);
  if (/cancel-in-progress:\s*true\b/.test(workflow)) {
    failures.push(`${file} must not use unconditional cancel-in-progress: true.`);
  }
}

// Merge gates stay deterministic: AI reviewers (Sentry Seer, Warden, ...) stay
// advisory. Any .github file pairing a model-backed reviewer with a
// merge-blocking signal fails Detect Changes, which CI Summary requires.
for (const violation of scanAiReviewBoundary('.')) {
  failures.push(
    `${violation.file}: AI reviewer must stay advisory (matched "${violation.signal}").`
  );
}

if (failures.length) {
  console.error('Workflow concurrency policy check failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('Workflow concurrency policy check passed.');
