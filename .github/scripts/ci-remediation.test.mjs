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
  CODEOWNERS_ISSUE,
  CODEOWNERS_LABEL,
  classifyCodeowners,
  codeownersFilingEnabled,
  formatCodeownersDryRun,
  planCodeownersIssue,
  shouldAddRepoComment,
} from './codeowners-check.mjs';
import { linearIssueLookupFilter, upsertLinearIssue } from './lib/linear-issue-intake.mjs';
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

test('CODEOWNERS drift is missing file or invalid owner, and stays a dry-run unless the gate is on', () => {
  assert.equal(classifyCodeowners({ status: 404, body: { message: 'Not Found' } }).kind, 'missing');
  assert.equal(
    classifyCodeowners({
      status: 200,
      body: { errors: [{ kind: 'Invalid pattern', message: 'Invalid pattern on line 1' }] },
    }).kind,
    'ok',
  );
  const invalid = classifyCodeowners({
    status: 200,
    body: {
      errors: [
        {
          kind: 'Invalid owner',
          path: '.github/CODEOWNERS',
          line: 1,
          source: '* @not-a-user',
          message: 'Invalid owner on line 1',
        },
      ],
    },
  });
  assert.equal(invalid.kind, 'invalid_owner');
  assert.equal(classifyCodeowners({ status: 500, body: {} }).kind, 'http_error');

  const missing = planCodeownersIssue({
    repo: 'JovieInc/LogYourBody',
    classification: { kind: 'missing', errors: [] },
    runUrl: 'https://github.com/JovieInc/LogYourBody/actions/runs/9',
  });
  assert.equal(missing.label, CODEOWNERS_LABEL);
  assert.equal(missing.label, 'remediation:codeowners-drift');
  assert.equal(missing.identifier, CODEOWNERS_ISSUE);
  assert.equal(missing.identifier, 'JOV-7549');
  assert.equal(missing.createStateName, 'Todo');
  assert.equal(missing.reopenTerminal, true);
  assert.match(missing.comment, /repo: JovieInc\/LogYourBody/);
  assert.match(missing.comment, /CODEOWNERS is missing/);
  assert.equal(
    planCodeownersIssue({
      repo: 'JovieInc/LogYourBody',
      classification: { kind: 'ok', errors: [] },
      runUrl: '',
    }),
    null,
  );
  const ownerPlan = planCodeownersIssue({
    repo: 'JovieInc/LogYourBody',
    classification: invalid,
    runUrl: 'https://github.com/JovieInc/LogYourBody/actions/runs/9',
  });
  assert.match(ownerPlan.description, /@not-a-user/);
  assert.equal(shouldAddRepoComment([{ body: ownerPlan.comment }], ownerPlan.comment), false);
  assert.equal(shouldAddRepoComment([{ body: 'repo: JovieInc/Other' }], ownerPlan.comment), true);

  assert.equal(codeownersFilingEnabled({}), false);
  assert.equal(codeownersFilingEnabled({ REMEDIATION_TRIGGERS_ENABLED: 'true' }), false);
  assert.equal(codeownersFilingEnabled({ LINEAR_API_KEY: 'secret' }), false);
  assert.equal(
    codeownersFilingEnabled({ REMEDIATION_TRIGGERS_ENABLED: 'true', LINEAR_API_KEY: 'secret' }),
    true,
  );
  const dryRun = formatCodeownersDryRun(missing, {
    reason: 'REMEDIATION_TRIGGERS_ENABLED is not true or LINEAR_API_KEY is unset',
  });
  assert.match(dryRun, /would upsert Linear issue/);
  assert.match(dryRun, /JOV-7549/);
  assert.match(formatCodeownersDryRun(null, { reason: 'ok' }), /No Linear issue filed/);

  const workflow = readFileSync(resolve(root, '.github/workflows/codeowners-check.yml'), 'utf8');
  assert.match(workflow, /cron: '41 16 \* \* 1'/);
  assert.match(workflow, /workflow_dispatch/);
  assert.match(workflow, /vars\.REMEDIATION_TRIGGERS_ENABLED/);
  assert.match(workflow, /secrets\.LINEAR_API_KEY/);
  assert.match(workflow, /remediation:codeowners-drift|codeowners-check\.mjs/);
  assert.doesNotMatch(workflow, /schedule:[\s\S]*schedule:/);

  assert.deepEqual(linearIssueLookupFilter({ fingerprint: 'remediation:asc-agreements' }).title, {
    contains: 'remediation:asc-agreements',
  });
  const byLabel = linearIssueLookupFilter({
    fingerprint: 'ignored',
    label: 'remediation:codeowners-drift',
  });
  assert.equal(byLabel.labels.some.name.eq, 'remediation:codeowners-drift');
  assert.equal(byLabel.title, undefined);
});

test('one Linear upsert helper matches a title fingerprint or a label', async () => {
  const calls = [];
  const fetchImpl = async (_url, init) => {
    const body = JSON.parse(init.body);
    calls.push(body);
    const query = body.query;
    if (query.includes('FindRemediationIssue')) {
      return {
        ok: true,
        text: async () =>
          JSON.stringify({
            data: {
              team: {
                states: {
                  nodes: [
                    { id: 'todo', name: 'Todo', type: 'unstarted' },
                    { id: 'backlog', name: 'Backlog', type: 'backlog' },
                  ],
                },
                labels: { nodes: [{ id: 'label-1', name: 'remediation:codeowners-drift' }] },
              },
              issues: { nodes: [] },
            },
          }),
      };
    }
    if (query.includes('RemediationIssueByIdentifier')) {
      return { ok: true, text: async () => JSON.stringify({ data: { issue: null } }) };
    }
    if (query.includes('CreateDedupedLinearIssue')) {
      return {
        ok: true,
        text: async () =>
          JSON.stringify({
            data: {
              issueCreate: {
                success: true,
                issue: { id: 'issue-1', identifier: 'JOV-1', url: 'https://example.com/issue-1' },
              },
            },
          }),
      };
    }
    return { ok: false, status: 500, text: async () => '' };
  };

  const byTitle = await upsertLinearIssue({
    fingerprint: 'remediation:asc-agreements',
    title: 'asc',
    description: 'd',
    priority: 1,
    createStateName: 'Todo',
    apiKey: 'test-key',
    fetchImpl,
  });
  assert.equal(byTitle.action, 'created');
  assert.equal(calls[0].variables.filter.title.contains, 'remediation:asc-agreements');

  calls.length = 0;
  const byLabel = await upsertLinearIssue({
    label: 'remediation:codeowners-drift',
    identifier: 'JOV-7549',
    title: 'drift',
    description: 'd',
    createStateName: 'Todo',
    reopenTerminal: true,
    apiKey: 'test-key',
    fetchImpl,
  });
  assert.equal(byLabel.action, 'created');
  assert.equal(calls[0].variables.filter.labels.some.name.eq, 'remediation:codeowners-drift');
  assert.equal(calls[1].variables.id, 'JOV-7549');
  assert.deepEqual(calls[2].variables.labelIds, ['label-1']);
  assert.equal(calls[2].variables.priority, undefined);
});

test('failed iOS release workflows are the ASC log source', () => {
  const workflow = readFileSync(resolve(root, '.github/workflows/linear-remediation.yml'), 'utf8');
  for (const name of ['iOS App Store Approved Release', 'iOS Release Loop', 'iOS TestFlight Deploy']) {
    assert.match(workflow, new RegExp(name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
  }
  assert.match(workflow, /workflow_run/);
  assert.doesNotMatch(workflow, /gh pr edit|pulls\/.*\/reviews|requestReviewers/);
});
