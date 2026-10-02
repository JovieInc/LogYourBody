import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  ASC_ISSUE_FINGERPRINT,
  logContainsAscAgreementsFailure,
  planAscAgreementsIssue,
  shouldAddRunComment,
} from './asc-agreements-remediation.mjs';
import {
  NO_REVIEWER_FINGERPRINT,
  NO_REVIEWER_WAIT_MS,
  buildNoReviewerIssue,
  formatNoReviewerDryRun,
  normalizePullRequest,
  selectPrsMissingReviewer,
} from './pr-no-reviewer-intake.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const now = Date.parse('2026-10-02T00:00:00Z');
const olderThan48h = new Date(now - NO_REVIEWER_WAIT_MS - 1).toISOString();
const exactly48h = new Date(now - NO_REVIEWER_WAIT_MS).toISOString();
const newerThan48h = new Date(now - NO_REVIEWER_WAIT_MS + 60_000).toISOString();

function pr(overrides) {
  return {
    number: 1,
    title: 'example',
    url: 'https://github.com/JovieInc/LogYourBody/pull/1',
    state: 'open',
    isDraft: false,
    createdAt: olderThan48h,
    autoMerge: true,
    green: true,
    reviewCount: 0,
    reviewRequestCount: 0,
    ...overrides,
  };
}

test('log matcher accepts the App Store Connect agreements 403 and rejects other failures', () => {
  const log = [
    '##[error]App Store Connect GET /v1/apps/6755209876 returned 403: {',
    '      "status": "403",',
    '      "code": "FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED",',
  ].join('\n');
  assert.equal(logContainsAscAgreementsFailure(log), true);
  assert.equal(logContainsAscAgreementsFailure('FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED'), true);
  assert.equal(logContainsAscAgreementsFailure('some other 403'), false);
  assert.equal(logContainsAscAgreementsFailure('REQUIRED_AGREEMENTS'), false);
  assert.equal(logContainsAscAgreementsFailure(''), false);
  assert.equal(logContainsAscAgreementsFailure(null), false);

  const plan = planAscAgreementsIssue(log, 'https://github.com/JovieInc/LogYourBody/actions/runs/9');
  assert.equal(plan.fingerprint, ASC_ISSUE_FINGERPRINT);
  assert.equal(plan.fingerprint, 'remediation:asc-agreements');
  assert.equal(plan.priority, 1);
  assert.equal(plan.createStateName, 'Todo');
  assert.equal(plan.reopenTerminal, true);
  assert.match(plan.title, /remediation:asc-agreements/);
  assert.match(plan.description, /actions\/runs\/9/);
  assert.equal(planAscAgreementsIssue('build failed', 'https://example.com/no-match'), null);
});

test('reviewer selection keeps only green auto-merge PRs with no reviewer for more than 48h', () => {
  const eligible = pr({ number: 11 });
  const selected = selectPrsMissingReviewer(
    [
      eligible,
      pr({ number: 12, isDraft: true }),
      pr({ number: 13, state: 'closed' }),
      pr({ number: 14, autoMerge: false }),
      pr({ number: 15, green: false }),
      pr({ number: 16, reviewCount: 1 }),
      pr({ number: 17, reviewRequestCount: 1 }),
      pr({ number: 18, createdAt: newerThan48h }),
      pr({ number: 19, createdAt: exactly48h }),
      pr({ number: 20, createdAt: 'not-a-date' }),
    ],
    now,
  );
  assert.deepEqual(
    selected.map((item) => item.number),
    [11],
  );

  const normalized = normalizePullRequest({
    number: 11,
    title: 'ship',
    url: 'https://github.com/JovieInc/LogYourBody/pull/11',
    state: 'OPEN',
    isDraft: false,
    createdAt: olderThan48h,
    autoMergeRequest: { enabledAt: olderThan48h },
    reviews: { totalCount: 0 },
    reviewRequests: { totalCount: 0 },
    commits: { nodes: [{ commit: { statusCheckRollup: { state: 'SUCCESS' } } }] },
  });
  assert.deepEqual(selectPrsMissingReviewer([normalized], now).map((item) => item.number), [11]);
  assert.equal(
    normalizePullRequest({
      state: 'OPEN',
      commits: { nodes: [{ commit: { statusCheckRollup: { state: 'PENDING' } } }] },
    }).green,
    false,
  );

  const issue = buildNoReviewerIssue(selected, 'https://github.com/JovieInc/LogYourBody/actions/runs/4');
  assert.equal(issue.fingerprint, NO_REVIEWER_FINGERPRINT);
  assert.equal(issue.priority, 1);
  assert.equal(issue.createStateName, 'Todo');
  assert.equal(issue.reopenTerminal, true);
  assert.match(issue.description, /pull\/1/);
  assert.match(issue.description, /actions\/runs\/4/);
  const dryRun = formatNoReviewerDryRun(
    selected,
    'https://github.com/JovieInc/LogYourBody/actions/runs/4',
  );
  assert.match(dryRun, /would upsert Linear issue/);
  assert.match(dryRun, /#11/);
  assert.match(formatNoReviewerDryRun([], ''), /would file nothing/);
});

test('ASC comment is skipped when this run or a recent fingerprint comment already exists', () => {
  const runUrl = 'https://github.com/JovieInc/LogYourBody/actions/runs/9';
  assert.equal(
    shouldAddRunComment([{ body: `Run: ${runUrl}`, createdAt: '2026-10-01T00:00:00Z' }], {
      runUrl,
      nowMs: now,
    }),
    false,
  );
  assert.equal(
    shouldAddRunComment(
      [{ body: `see ${ASC_ISSUE_FINGERPRINT}`, createdAt: '2026-10-01T12:00:00Z' }],
      { runUrl, nowMs: now },
    ),
    false,
  );
  assert.equal(
    shouldAddRunComment(
      [{ body: `see ${ASC_ISSUE_FINGERPRINT}`, createdAt: '2026-09-01T00:00:00Z' }],
      { runUrl, nowMs: now },
    ),
    true,
  );
});

test('failed iOS release workflows are the ASC log source', () => {
  const workflow = readFileSync(resolve(root, '.github/workflows/linear-remediation.yml'), 'utf8');
  for (const name of ['iOS App Store Approved Release', 'iOS Release Loop', 'iOS TestFlight Deploy']) {
    assert.match(workflow, new RegExp(name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(workflow, /workflow_run/);
  assert.doesNotMatch(workflow, /gh pr edit|pulls\/.*\/reviews|requestReviewers/);
});
