// LYB-349: budget-guard coverage for the Merge Queue Token Enrollment
// workflow. Lives in its own file because the shared company-guards 500-line
// ratchet baselines .github/scripts/merge-queue-enrollment.test.mjs at 952
// lines and baselined files may not grow. These tests execute the production
// inline script and self-skip with a reason until the workflow half of the
// fix (a git-apply patch, see PR body of the LYB-349 PR) is applied.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const tokenWorkflow = fs.readFileSync(
  path.join(directory, '../workflows/merge-queue-token-enrollment.yml'),
  'utf8',
);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
const head = 'a'.repeat(40);
const repository = 'JovieInc/LogYourBody';

function inlineScript(workflow) {
  const match = workflow.match(/          script: \|\n([\s\S]*)/);
  assert.ok(match, 'Execute the production inline script without checking out privileged code');
  return new AsyncFunction(
    'github',
    'context',
    'core',
    match[1]
      .split('\n')
      .map((line) => line.slice(12))
      .join('\n'),
  );
}

function recordingCore() {
  const messages = [];
  return {
    messages,
    info: (message) => messages.push(message),
    notice: (message) => messages.push(message),
    warning: (message) => messages.push(message),
  };
}

async function tokenScenario({ mutate = () => {}, enqueueError, rateLimit } = {}) {
  const context = {
    repo: { owner: 'JovieInc', repo: 'LogYourBody' },
    eventName: 'workflow_run',
    payload: {
      workflow_run: {
        name: 'Native Merge Queue Enrollment',
        status: 'completed',
        conclusion: 'success',
        repository: { full_name: repository },
      },
    },
  };
  const entry = {
    enqueuer: { login: 'github-actions[bot]' },
    pullRequest: {
      id: 'PR_fixture',
      number: 1284,
      state: 'OPEN',
      isDraft: false,
      baseRefName: 'main',
      headRefOid: head,
      headRepository: { nameWithOwner: repository },
    },
  };
  const checkRuns = [
    {
      name: 'CI Summary',
      conclusion: 'success',
      head_sha: head,
      completed_at: '2026-01-01T00:00:00Z',
    },
  ];
  mutate(context);
  const fresh = {
    number: 1284, state: 'open', draft: false, labels: [],
    base: { ref: 'main', repo: { full_name: repository } },
    head: { sha: head, repo: { full_name: repository } },
  };
  const calls = [];
  const core = recordingCore();
  const github = {
    rest: {
      ...(rateLimit
        ? {
            rateLimit: {
              async get() {
                if (rateLimit === 'unavailable') throw new Error('rate limit endpoint is down');
                return {
                  data: {
                    resources: {
                      graphql: {
                        remaining: rateLimit.remaining,
                        limit: rateLimit.limit ?? 5000,
                        resetAt: rateLimit.resetAt ?? '2026-10-31T10:00:00Z',
                      },
                    },
                  },
                };
              },
            },
          }
        : {}),
      pulls: { async get() { return { data: fresh }; } },
      checks: {
        async listForRef() {
          return { data: { check_runs: checkRuns } };
        },
      },
    },
    async graphql(query, variables) {
      calls.push({ query, variables });
      if (query.includes('query Queue'))
        return { repository: { mergeQueue: { entries: { nodes: [entry] } } } };
      if (query.includes('mutation Dequeue'))
        return { dequeuePullRequest: { mergeQueueEntry: { id: 'MQ_fixture' } } };
      if (enqueueError) throw enqueueError;
      return { enqueuePullRequest: { mergeQueueEntry: { id: 'MQ_fixture', position: 1 } } };
    },
  };
  await inlineScript(tokenWorkflow)(github, context, core);
  return { calls, core };
}

// The workflow half ships as a git-apply patch (the App token cannot write
// .github/workflows). The budget tests assert the guard strictly once it
// lands and skip with a reason while it is pending.
const budgetGuardApplied = tokenWorkflow.includes('MIN_GRAPHQL_REMAINING');
const pendingWorkflowPatch = () =>
  !budgetGuardApplied ? 'LYB-349 workflow patch not applied yet (see PR body)' : false;

const rateLimitFailure = () => Object.assign(
  new Error('GraphQL: App installation 112037986 is at 5000/5000'),
  { errors: [{ type: 'RATE_LIMIT' }] },
);

test('a healthy shared GraphQL budget proceeds with the normal re-enqueue', { skip: pendingWorkflowPatch() }, async () => {
  const { calls, core } = await tokenScenario({ rateLimit: { remaining: 4000 } });
  assert.equal(calls.length, 3);
  assert.ok(core.messages.some((message) => message.startsWith('RE-ENQUEUED:')));
});

test('an exhausted shared GraphQL budget exits neutral before querying the queue', { skip: pendingWorkflowPatch() }, async () => {
  const { calls, core } = await tokenScenario({ rateLimit: { remaining: 100 } });
  assert.equal(calls.length, 0, 'No queue query or mutation may run on a nearly dry bucket');
  assert.ok(core.messages.some((message) => message.startsWith('SKIPPED: shared GraphQL budget is low')));
  assert.ok(core.messages.some((message) => message.includes('retried on the next enrollment completion')));
});

for (const [name, rateLimit] of [
  ['a failed budget sample', 'unavailable'],
  ['an absent budget endpoint', null],
]) {
  test(`${name} falls back to the normal query path`, { skip: pendingWorkflowPatch() }, async () => {
    const { calls, core } = await tokenScenario({ rateLimit });
    assert.equal(calls.length, 3);
    assert.ok(core.messages.some((message) => message.startsWith('RE-ENQUEUED:')));
  });
}

test('a mid-sweep rate limit defers the rest of the sweep without failing', { skip: pendingWorkflowPatch() }, async () => {
  const { calls, core } = await tokenScenario({ enqueueError: rateLimitFailure(), rateLimit: { remaining: 4000 } });
  assert.equal(calls.length, 3, 'The dequeue lands, the enqueue hits the budget wall, and the sweep stops there');
  assert.match(calls[1].query, /mutation Dequeue/);
  assert.match(calls[2].query, /mutation Enqueue/);
  assert.ok(core.messages.some((message) => message.startsWith('DEFERRED:') && message.includes('#1284')));
  assert.ok(!core.messages.some((message) => message.startsWith('RE-ENQUEUED:')));
});

test('non-rate-limit mutation failures still fail the token repair', { skip: pendingWorkflowPatch() }, async () => {
  await assert.rejects(
    tokenScenario({ enqueueError: new Error('Resource not accessible by integration'), rateLimit: { remaining: 4000 } }),
    /Resource not accessible by integration/,
  );
});
