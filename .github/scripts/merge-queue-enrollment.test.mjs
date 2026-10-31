import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const nativeWorkflow = fs.readFileSync(
  path.join(directory, '../workflows/native-merge-queue.yml'),
  'utf8',
);
const tokenWorkflow = fs.readFileSync(
  path.join(directory, '../workflows/merge-queue-token-enrollment.yml'),
  'utf8',
);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
// LYB-349: the workflow half of the budget guard ships as a git-apply patch
// (the App token cannot write .github/workflows). The budget tests assert the
// guard strictly once it lands and skip with a reason while it is pending.
const budgetGuardApplied = tokenWorkflow.includes('MIN_GRAPHQL_REMAINING');
const pendingWorkflowPatch = () =>
  !budgetGuardApplied ? 'LYB-349 workflow patch not applied yet (see PR body)' : false;
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
  const tables = [];
  const summary = {
    addHeading() {
      return this;
    },
    addTable(rows) {
      tables.push(rows);
      return this;
    },
    async write() {},
  };
  return {
    messages,
    tables,
    summary,
    info: (message) => messages.push(message),
    notice: (message) => messages.push(message),
    warning: (message) => messages.push(message),
  };
}

async function nativeScenario({
  mutate = () => {},
  enqueueError,
  queuedMutate = () => {},
  removals = [],
} = {}) {
  const run = {
    name: 'CI',
    event: 'pull_request',
    status: 'completed',
    conclusion: 'success',
    head_sha: head,
    created_at: '2026-10-10T00:00:00Z',
    repository: { full_name: repository },
    pull_requests: [{ number: 1284 }],
  };
  const pull = {
    number: 1284,
    node_id: 'PR_fixture',
    draft: false,
    state: 'open',
    labels: [],
    base: { ref: 'main', repo: { full_name: repository } },
    head: { sha: head, repo: { full_name: repository } },
  };
  const context = {
    repo: { owner: 'JovieInc', repo: 'LogYourBody' },
    eventName: 'workflow_run',
    payload: { workflow_run: run, action: 'completed', pull_request: pull },
  };
  const queued = {
    number: 1284,
    state: 'OPEN',
    isDraft: false,
    baseRefName: 'main',
    headRefOid: head,
    headRepository: { nameWithOwner: repository },
    mergeQueueEntry: { id: 'MQ_fixture', position: 1 },
  };
  mutate({ run, pull, context });
  queuedMutate(queued);
  const calls = [];
  const core = recordingCore();
  const github = {
    rest: {
      actions: {
        async listWorkflowRuns() {
          return { data: { workflow_runs: [run] } };
        },
      },
      pulls: {
        async get() {
          return { data: pull };
        },
      },
    },
    async graphql(query, variables) {
      calls.push({ query, variables });
      if (query.includes('mutation Enqueue')) {
        if (enqueueError) throw enqueueError;
        return { enqueuePullRequest: { mergeQueueEntry: queued.mergeQueueEntry } };
      }
      if (query.includes('query Removals')) {
        return { repository: { pullRequest: { timelineItems: { nodes: removals } } } };
      }
      return { repository: { pullRequest: queued } };
    },
  };
  await inlineScript(nativeWorkflow)(github, context, core);
  return { calls, core };
}

const dequeued = ({ context }) => {
  context.eventName = 'pull_request_target';
  context.payload.action = 'dequeued';
};
const removal = (reason, createdAt = '2026-10-11T00:00:00Z') => ({ reason, createdAt });

test('a dropped green head re-enters after a check timeout or a first failed group', async () => {
  for (const removals of [
    [removal('checks_timed_out')],
    [removal('checks_timed_out'), removal('checks_timed_out')],
    [removal('failed_checks', '2026-10-01T00:00:00Z'), removal('failed_checks')],
  ]) {
    const { calls, core } = await nativeScenario({ mutate: dequeued, removals });
    assert.equal(calls.length, 2);
    assert.match(calls[1].query, /mutation Enqueue/);
    assert.equal(calls[1].variables.expectedHeadOid, head);
    assert.ok(core.messages.some((message) => message.startsWith('ENQUEUED:')));
  }
});

test('a head whose merge group failed twice is poisoned and stays out', async () => {
  const { calls, core } = await nativeScenario({
    mutate: dequeued,
    removals: [removal('failed_checks'), removal('checks_timed_out'), removal('failed_checks')],
  });
  assert.equal(calls.length, 1);
  assert.ok(core.messages.some((message) => message.startsWith('POISONED:')));
});

test('manual and merge-conflict removals are never undone', async () => {
  for (const removals of [[removal('manual')], [removal('merge_conflict')], []]) {
    const { calls, core } = await nativeScenario({ mutate: dequeued, removals });
    assert.equal(calls.length, 1);
    assert.ok(core.messages.some((message) => message.startsWith('NOT_ELIGIBLE:')));
  }
});

test('a dropped head that moved or went red is not re-enqueued', async () => {
  for (const mutate of [
    (scenario) => {
      dequeued(scenario);
      scenario.pull.head.sha = 'b'.repeat(40);
    },
    (scenario) => {
      dequeued(scenario);
      scenario.run.conclusion = 'failure';
    },
  ]) {
    const { calls } = await nativeScenario({ mutate, removals: [removal('checks_timed_out')] });
    assert.equal(calls.length, 0);
  }
});

test('other pull request actions stay outside the enrollment contract', async () => {
  const { calls } = await nativeScenario({
    mutate: ({ context }) => {
      context.eventName = 'pull_request_target';
      context.payload.action = 'synchronize';
    },
  });
  assert.equal(calls.length, 0);
});

async function draftWithdrawalScenario({ mutate = () => {}, dequeueError, after } = {}) {
  const queued = {
    id: 'PR_draft', number: 1284, state: 'OPEN', isDraft: true,
    baseRefName: 'main', headRefOid: head,
    headRepository: { nameWithOwner: repository },
    mergeQueueEntry: { id: 'MQ_draft', position: 1 },
  };
  const context = {
    repo: { owner: 'JovieInc', repo: 'LogYourBody' },
    eventName: 'pull_request_target',
    payload: {
      action: 'converted_to_draft',
      pull_request: { number: 1284, draft: true, head: { sha: head } },
    },
  };
  mutate({ queued, context });
  const calls = [];
  const core = recordingCore();
  let removed = false;
  const github = {
    rest: {
      actions: { async listWorkflowRuns() { assert.fail('withdrawing a draft must not wait for CI'); } },
    },
    async graphql(query, variables) {
      calls.push({ query, variables });
      if (query.includes('mutation WithdrawDraft')) {
        if (dequeueError) throw dequeueError;
        removed = true;
        return { dequeuePullRequest: { mergeQueueEntry: queued.mergeQueueEntry } };
      }
      assert.match(query, /query DraftQueueEntry/);
      return { repository: { pullRequest: removed ? (after ?? { ...queued, mergeQueueEntry: null }) : queued } };
    },
  };
  await inlineScript(nativeWorkflow)(github, context, core);
  return { calls, core };
}

test('converting an already queued exact head to draft withdraws it and proves absence without CI', async () => {
  const { calls, core } = await draftWithdrawalScenario();
  assert.equal(calls.length, 3);
  assert.match(calls[0].query, /query DraftQueueEntry/);
  assert.match(calls[1].query, /mutation WithdrawDraft/);
  assert.deepEqual(calls[1].variables, { id: 'PR_draft' });
  assert.match(calls[2].query, /query DraftQueueEntry/);
  assert.ok(core.messages.some(message => message.startsWith('WITHDRAWN:')));
  assert.ok(!calls.some(call => /enqueuePullRequest/.test(call.query)));
});

test('draft withdrawal is idempotent when fresh queue evidence is already absent', async () => {
  const { calls, core } = await draftWithdrawalScenario({ mutate: ({ queued }) => { queued.mergeQueueEntry = null; } });
  assert.equal(calls.length, 1);
  assert.ok(core.messages.some(message => message.startsWith('WITHDRAWN:')));
});

test('missing or malformed initial queue membership cannot be claimed as a withdrawal', async () => {
  for (const mutate of [
    ({ queued }) => { delete queued.mergeQueueEntry; },
    ({ queued }) => { queued.mergeQueueEntry = undefined; },
    ({ queued }) => { queued.mergeQueueEntry = {}; },
    ({ queued }) => { queued.mergeQueueEntry = false; },
  ]) {
    await assert.rejects(draftWithdrawalScenario({ mutate }), /queue membership is unknown/);
  }
});

for (const [name, mutate] of [
  ['ready again', ({ queued }) => { queued.isDraft = false; }],
  ['merged', ({ queued }) => { queued.state = 'MERGED'; }],
  ['closed', ({ queued }) => { queued.state = 'CLOSED'; }],
  ['moved head', ({ queued }) => { queued.headRefOid = 'b'.repeat(40); }],
  ['foreign head', ({ queued }) => { queued.headRepository.nameWithOwner = 'someone/fork'; }],
  ['wrong base', ({ queued }) => { queued.baseRefName = 'release'; }],
]) {
  test(`draft event cannot withdraw a ${name} pull request`, async () => {
    const { calls, core } = await draftWithdrawalScenario({ mutate });
    assert.equal(calls.length, 1);
    assert.ok(!core.messages.some(message => message.startsWith('WITHDRAWN:')));
  });
}

test('draft withdrawal rejects invalid event identity before querying', async () => {
  for (const mutate of [
    ({ context }) => { context.repo.repo = 'Jovie'; },
    ({ context }) => { context.payload.pull_request.draft = false; },
    ({ context }) => { context.payload.pull_request.number = null; },
    ({ context }) => { context.payload.pull_request.head.sha = null; },
  ]) {
    const { calls } = await draftWithdrawalScenario({ mutate });
    assert.equal(calls.length, 0);
  }
});

test('draft withdrawal propagates a denied dequeue and never claims a verified hold', async () => {
  const error = new Error('Resource not accessible by integration');
  await assert.rejects(draftWithdrawalScenario({ dequeueError: error }), error);
});

test('draft withdrawal fails if fresh readback still has an entry or no longer proves the same draft', async () => {
  for (const after of [
    { mergeQueueEntry: { id: 'MQ_still_present' } },
    { state: 'MERGED', mergeQueueEntry: null },
    { isDraft: false, mergeQueueEntry: null },
    { headRefOid: 'b'.repeat(40), mergeQueueEntry: null },
    { headRepository: { nameWithOwner: 'someone/fork' }, mergeQueueEntry: null },
    { mergeQueueEntry: undefined },
    {},
  ]) {
    await assert.rejects(draftWithdrawalScenario({ after: {
      state: 'OPEN', isDraft: true, headRefOid: head, baseRefName: 'main',
      headRepository: { nameWithOwner: repository }, ...after,
    } }), /Could not verify draft withdrawal/);
  }
});

test('native controller subscribes to draft transitions', () => {
  assert.match(nativeWorkflow, /types: \[ready_for_review, dequeued, converted_to_draft\]/);
});

test('same-head concurrency retains pending draft withdrawals instead of replacing them with later CI', () => {
  // GitHub queue:max preserves up to 100 pending runs, with one running job:
  // With the default queue:single, CI completion replaces a pending draft event.
  const concurrency = nativeWorkflow.match(/^concurrency:\n((?:[ \t].*\n|\n)+)/m)?.[1];
  assert.ok(concurrency);
  assert.match(concurrency, /group: native-merge-queue-\$\{\{ github\.event\.workflow_run\.head_sha \|\| github\.event\.pull_request\.head\.sha \}\}/);
  assert.match(concurrency, /cancel-in-progress: false/);
  assert.match(concurrency, /queue: max/);
});

function alreadyQueuedError(type = 'UNPROCESSABLE') {
  return Object.assign(new Error('GraphQL enrollment failed'), {
    errors: [{ type, message: 'Pull request is already in the queue' }],
  });
}

test('native enrollment mutates only the exact eligible head', async () => {
  const { calls, core } = await nativeScenario();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].variables.expectedHeadOid, head);
  assert.ok(core.messages.some((message) => message.startsWith('ENQUEUED:')));
});

test('ready-for-review enrollment resolves the completed source CI', async () => {
  const { calls } = await nativeScenario({
    mutate: ({ context }) => {
      context.eventName = 'pull_request_target';
      context.payload.action = 'ready_for_review';
    },
  });
  assert.equal(calls.length, 1);
});

test('already-enqueued exact head is idempotent success with fresh queue readback', async () => {
  const { calls, core } = await nativeScenario({ enqueueError: alreadyQueuedError() });
  assert.equal(calls.length, 2);
  assert.match(calls[1].query, /mergeQueueEntry/);
  assert.ok(core.messages.some((message) => message.startsWith('ENQUEUED:')));
});

test('an already-queued error cannot certify a changed head or absent queue entry', async () => {
  for (const queuedMutate of [
    (pull) => {
      pull.headRefOid = 'b'.repeat(40);
    },
    (pull) => {
      pull.mergeQueueEntry = null;
    },
  ]) {
    await assert.rejects(
      nativeScenario({ enqueueError: alreadyQueuedError(), queuedMutate }),
      /GraphQL enrollment failed/,
    );
  }
});

test('unrelated GraphQL failures are retained', async () => {
  await assert.rejects(
    nativeScenario({ enqueueError: alreadyQueuedError('FORBIDDEN') }),
    /GraphQL enrollment failed/,
  );
});

const changesRequested =
  'Pull request 1 review requesting changes by reviewers with write access.';

function graphqlFailure(errors) {
  return Object.assign(new Error('GraphQL enrollment failed'), { errors });
}

test('GitHub review blockers leave the PR ineligible without failing enrollment', async () => {
  for (const message of [
    changesRequested,
    'Pull request 2 reviews requesting changes by reviewers with write access.',
  ]) {
    const enqueueError = graphqlFailure([{ type: 'UNPROCESSABLE', message }]);
    const { calls, core } = await nativeScenario({ enqueueError });
    assert.equal(calls.length, 1, 'Do not retry or bypass the review blocker');
    assert.equal(calls[0].variables.expectedHeadOid, head);
    assert.ok(core.messages.some((notice) => notice.startsWith('NOT_ELIGIBLE:')
      && notice.includes(message)));
    assert.ok(!core.messages.some((notice) => notice.startsWith('ENQUEUED:')));
    assert.equal(core.tables.length, 1);
    assert.equal(core.tables[0][0][1], 'NOT_ELIGIBLE');
    assert.equal(core.tables[0][2][1], head);
    assert.equal(core.tables[0][3][1], message);
  }
});

test('review blocker handling preserves permission, unexpected and mixed GraphQL failures', async () => {
  const reviewBlocker = {
    type: 'UNPROCESSABLE',
    message: changesRequested,
  };
  for (const errors of [
    [],
    undefined,
    [{ ...reviewBlocker, type: 'FORBIDDEN' }],
    [{ type: 'UNPROCESSABLE', message: 'Resource not accessible by integration' }],
    [{ type: 'UNPROCESSABLE', message: 'Unexpected review service failure' }],
    [reviewBlocker, { type: 'FORBIDDEN', message: 'Resource not accessible by integration' }],
    [reviewBlocker, { type: 'UNPROCESSABLE', message: 'Unexpected review service failure' }],
  ]) {
    const enqueueError = graphqlFailure(errors);
    await assert.rejects(nativeScenario({ enqueueError }), (error) => error === enqueueError);
  }
});

test('changes-requested and other review blocks are not eligible', async () => {
  for (const message of [
    changesRequested,
    'Pull request 2 reviews requesting changes by reviewers with write access.',
    'At least 1 approving review is required by reviewers with write access.',
    'At least 2 approving reviews are required by reviewers with write access.',
    'At least 1 approving review required by reviewers with write access.',
    `${changesRequested.slice(0, -1)} and At least 1 approving review is required by reviewers with write access.`,
  ]) {
    const { calls, core } = await nativeScenario({
      enqueueError: graphqlFailure([{ type: 'UNPROCESSABLE', message }]),
    });
    assert.equal(calls.length, 1);
    assert.match(calls[0].query, /mutation Enqueue/);
    assert.ok(
      core.messages.some(
        (entry) => entry.startsWith('NOT_ELIGIBLE:') && entry.includes('blocked by review'),
      ),
    );
  }
});

const mergeConflicts = 'Pull request has merge conflicts';
const notMergeable = 'Pull request not in mergeable state';

test('mergeability refusals record a non-failing outcome for the exact green head', async () => {
  for (const messages of [
    [mergeConflicts],
    [`${notMergeable}.`],
    [`${mergeConflicts} and ${notMergeable}`],
    [mergeConflicts, notMergeable],
    [changesRequested, `${mergeConflicts} and ${notMergeable}`],
    [`${changesRequested.slice(0, -1)} and ${mergeConflicts} and ${notMergeable}`],
  ]) {
    const enqueueError = graphqlFailure(
      messages.map((message) => ({ type: 'UNPROCESSABLE', message })),
    );
    const { calls, core } = await nativeScenario({ enqueueError });
    assert.equal(calls.length, 1, 'Do not retry or bypass the mergeability refusal');
    assert.equal(calls[0].variables.expectedHeadOid, head);
    assert.ok(core.messages.some((notice) => notice.startsWith('NOT_MERGEABLE:')
      && notice.includes('#1284') && notice.includes('rebase')));
    assert.ok(!core.messages.some((notice) => notice.startsWith('ENQUEUED:')));
    assert.equal(core.tables.length, 1);
    assert.equal(core.tables[0][0][1], 'NOT_MERGEABLE');
    assert.equal(core.tables[0][2][1], head);
    assert.equal(core.tables[0][3][1], messages.join('; '));
  }
});

test('a clean enrollment cycle succeeds after a mergeability refusal', async () => {
  const blocked = await nativeScenario({
    enqueueError: graphqlFailure([{ type: 'UNPROCESSABLE', message: notMergeable }]),
  });
  assert.equal(blocked.core.tables[0][0][1], 'NOT_MERGEABLE');

  const rebasedHead = 'b'.repeat(40);
  const { calls, core } = await nativeScenario({
    mutate: ({ run, pull }) => {
      run.head_sha = rebasedHead;
      pull.head.sha = rebasedHead;
    },
  });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].variables.expectedHeadOid, rebasedHead);
  assert.equal(core.tables[0][0][1], 'ENQUEUED');
  assert.equal(core.tables[0][2][1], rebasedHead);
});

test('mergeability handling preserves unexpected, permission and mixed failures', async () => {
  const conflict = { type: 'UNPROCESSABLE', message: mergeConflicts };
  const unknown = { type: 'UNPROCESSABLE', message: 'Unexpected enqueue service failure' };
  const forbidden = { type: 'FORBIDDEN', message: 'Resource not accessible by integration' };
  for (const errors of [
    [{ ...conflict, type: 'FORBIDDEN' }],
    [{ message: notMergeable }],
    [{ type: 'UNPROCESSABLE', message: `${notMergeable} because of a service failure` }],
    [conflict, unknown],
    [conflict, forbidden],
    [{ ...conflict, message: `${mergeConflicts} and ${unknown.message}` }],
    [{ ...conflict, message: `${mergeConflicts} and Pull request is a draft.` }],
    [...alreadyQueuedError().errors, unknown],
    [...alreadyQueuedError().errors, forbidden],
    [{ type: 'FORBIDDEN', message: changesRequested }],
    [null],
    [],
  ]) {
    const enqueueError = graphqlFailure(errors);
    await assert.rejects(
      nativeScenario({ enqueueError }),
      (error) => error === enqueueError,
    );
  }
});

test('draft and permission refusals still fail', async () => {
  for (const message of [
    'Pull request is a draft.',
    'Pull request refusing to allow a GitHub App to create or update workflow `.github/workflows/ci.yml` without `workflows` permission',
  ]) {
    await assert.rejects(
      nativeScenario({
        enqueueError: graphqlFailure([{ type: 'UNPROCESSABLE', message }]),
      }),
      /GraphQL enrollment failed/,
    );
  }
});

for (const [name, mutate] of [
  [
    'failed CI',
    ({ run }) => {
      run.conclusion = 'failure';
    },
  ],
  [
    'incomplete CI',
    ({ run }) => {
      run.status = 'in_progress';
    },
  ],
  [
    'wrong workflow',
    ({ run }) => {
      run.name = 'Security Scanning';
    },
  ],
  [
    'wrong source event',
    ({ run }) => {
      run.event = 'push';
    },
  ],
  [
    'ambiguous association',
    ({ run }) => {
      run.pull_requests.push({ number: 1285 });
    },
  ],
  [
    'stale CI',
    ({ pull }) => {
      pull.head.sha = 'b'.repeat(40);
    },
  ],
  [
    'draft',
    ({ pull }) => {
      pull.draft = true;
    },
  ],
  [
    'closed PR',
    ({ pull }) => {
      pull.state = 'closed';
    },
  ],
  [
    'wrong base',
    ({ pull }) => {
      pull.base.ref = 'production';
    },
  ],
  [
    'fork',
    ({ pull }) => {
      pull.head.repo.full_name = 'other/LogYourBody';
    },
  ],
  [
    'foreign CI repository',
    ({ run }) => {
      run.repository.full_name = 'JovieInc/Jovie';
    },
  ],
  [
    'foreign controller repository',
    ({ context, run, pull }) => {
      context.repo.repo = 'Jovie';
      run.repository.full_name = 'JovieInc/Jovie';
      pull.head.repo.full_name = 'JovieInc/Jovie';
    },
  ],
  [
    'unrelated event',
    ({ context }) => {
      context.eventName = 'push';
    },
  ],
]) {
  test(`native enrollment ignores ${name}`, async () => {
    const { calls } = await nativeScenario({ mutate });
    assert.equal(calls.length, 0);
  });
}

async function tokenScenario({ mutate = () => {}, entryMutate = () => {}, freshMutate = () => {}, enqueueError, rateLimit } = {}) {
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
  entryMutate(entry, checkRuns);
  const fresh = {
    number: 1284, state: 'open', draft: false, labels: [],
    base: { ref: 'main', repo: { full_name: repository } },
    head: { sha: head, repo: { full_name: repository } },
  };
  freshMutate(fresh);
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

test('token repair re-enqueues only a bot-owned exact source head with CI Summary success', async () => {
  const { calls } = await tokenScenario();
  assert.equal(calls.length, 3);
  assert.match(calls[1].query, /dequeuePullRequest/);
  assert.equal(calls[2].variables.expectedHeadOid, head);
});

const rateLimitFailure = () => Object.assign(
  new Error(`GraphQL: App installation 112037986 is at 5000/5000`),
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

for (const [name, entryMutate] of [
  [
    'personal enrollment',
    (entry) => {
      entry.enqueuer.login = 'timwhite';
    },
  ],
  [
    'draft',
    (entry) => {
      entry.pullRequest.isDraft = true;
    },
  ],
  [
    'wrong base',
    (entry) => {
      entry.pullRequest.baseRefName = 'production';
    },
  ],
  [
    'foreign head repository',
    (entry) => {
      entry.pullRequest.headRepository.nameWithOwner = 'JovieInc/Jovie';
    },
  ],
  [
    'closed PR',
    (entry) => {
      entry.pullRequest.state = 'CLOSED';
    },
  ],
  [
    'failed summary',
    (entry, checkRuns) => {
      checkRuns[0].conclusion = 'failure';
    },
  ],
  [
    'missing summary',
    (entry, checkRuns) => {
      checkRuns.length = 0;
    },
  ],
  [
    'summary from another commit',
    (entry, checkRuns) => {
      checkRuns[0].head_sha = 'b'.repeat(40);
    },
  ],
]) {
  test(`token repair leaves ${name} entries unchanged`, async () => {
    const { calls } = await tokenScenario({ entryMutate });
    assert.equal(calls.length, 1);
  });
}

for (const [name, mutate] of [
  [
    'foreign controller repository',
    (context) => {
      context.repo.repo = 'Jovie';
    },
  ],
  [
    'foreign workflow repository',
    (context) => {
      context.payload.workflow_run.repository.full_name = 'JovieInc/Jovie';
    },
  ],
  [
    'failed enrollment',
    (context) => {
      context.payload.workflow_run.conclusion = 'failure';
    },
  ],
  [
    'unrelated workflow',
    (context) => {
      context.payload.workflow_run.name = 'CI';
    },
  ],
  [
    'unrelated event',
    (context) => {
      context.eventName = 'push';
    },
  ],
]) {
  test(`token repair performs no API calls for ${name}`, async () => {
    const { calls } = await tokenScenario({ mutate });
    assert.equal(calls.length, 0);
  });
}

function credentialGate(environment) {
  const match = tokenWorkflow.match(/        run: \|\n([\s\S]*?)(?=\n      - |$)/);
  assert.ok(match);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'lyb-enrollment-'));
  try {
    const output = path.join(temporary, 'outputs');
    const result = spawnSync(
      'bash',
      [
        '-c',
        match[1]
          .split('\n')
          .map((line) => line.slice(10))
          .join('\n'),
      ],
      {
        encoding: 'utf8',
        env: {
          PATH: process.env.PATH,
          GITHUB_OUTPUT: output,
          GITHUB_REPOSITORY: repository,
          JOVIE_BOT_APP_ID: '',
          JOVIE_BOT_PRIVATE_KEY: '',
          MERGE_QUEUE_TOKEN: '',
          ...environment,
        },
      },
    );
    assert.equal(result.status, 0, result.stderr);
    assert.ok(
      !result.stdout.includes('fixture-pat') && !result.stdout.includes('fixture-key'),
      'Credential contents must not be logged',
    );
    return Object.fromEntries(
      fs
        .readFileSync(output, 'utf8')
        .trim()
        .split('\n')
        .map((line) => line.split('=')),
    );
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
}

test('complete App inputs take precedence over the existing PAT fallback', () => {
  assert.deepEqual(
    credentialGate({
      JOVIE_BOT_APP_ID: '2934433',
      JOVIE_BOT_PRIVATE_KEY: 'fixture-key',
      MERGE_QUEUE_TOKEN: 'fixture-pat',
    }),
    { present: 'true', mode: 'app' },
  );
});

test('existing PAT is selected when App inputs are incomplete', () => {
  for (const environment of [
    {},
    { JOVIE_BOT_APP_ID: '2934433' },
    { JOVIE_BOT_PRIVATE_KEY: 'fixture-key' },
  ]) {
    assert.deepEqual(credentialGate({ ...environment, MERGE_QUEUE_TOKEN: 'fixture-pat' }), {
      present: 'true',
      mode: 'pat',
    });
  }
});

test('missing usable credentials skip without falling back to GITHUB_TOKEN', () => {
  assert.deepEqual(credentialGate({}), { present: 'false', mode: 'none' });
});

test('credential gate refuses a copied workflow in another repository', () => {
  assert.deepEqual(
    credentialGate({ GITHUB_REPOSITORY: 'JovieInc/Jovie', MERGE_QUEUE_TOKEN: 'fixture-pat' }),
    { present: 'false', mode: 'none' },
  );
});

test('App minting stays pinned, scoped to LYB and separate from secret-free native enrollment', () => {
  assert.match(tokenWorkflow, /actions\/create-github-app-token@[a-f0-9]{40}/);
  assert.match(tokenWorkflow, /repositories: \$\{\{ github\.event\.repository\.name \}\}/);
  assert.match(
    tokenWorkflow,
    /github-token: \$\{\{ steps\.app-token\.outputs\.token \|\| secrets\.MERGE_QUEUE_TOKEN \}\}/,
  );
  assert.match(tokenWorkflow, /permission-contents: write/);
  assert.match(tokenWorkflow, /permission-pull-requests: write/);
  assert.doesNotMatch(tokenWorkflow, /actions\/checkout@|pull_request/);
  assert.doesNotMatch(nativeWorkflow, /actions\/checkout@|secrets\./);
});

for (const action of ['completed', 'ready_for_review', 'dequeued']) {
  test(`native ${action} enrollment preserves a current hold on an otherwise green head`, async () => {
    const { calls, core } = await nativeScenario({
      mutate: (scenario) => {
        if (action !== 'completed') {
          scenario.context.eventName = 'pull_request_target';
          scenario.context.payload.action = action;
        }
        scenario.context.payload.pull_request = { ...scenario.pull, labels: [] };
        scenario.pull.labels = [{ name: 'HoLd' }];
      },
      removals: [removal('checks_timed_out')],
    });
    assert.equal(calls.length, 0, 'A hold forbids queue mutation and retry');
    assert.ok(core.messages.some(message => message.includes('explicit hold')));
  });
}

test('native enrollment fails closed if current label evidence is absent or malformed', async () => {
  for (const labels of [undefined, null, {}, [null], [{}], [{ name: 1 }]]) {
    const { calls, core } = await nativeScenario({ mutate: ({ pull }) => { pull.labels = labels; } });
    assert.equal(calls.length, 0);
    assert.ok(core.messages.some(message => message.includes('labels are unavailable')));
  }
});

test('native enrollment does not require a positive certification label', async () => {
  for (const labels of [[], [{ name: 'bug' }], [{ name: 'machine-certified' }]]) {
    const { calls } = await nativeScenario({ mutate: ({ pull }) => { pull.labels = labels; } });
    assert.equal(calls.length, 1);
    assert.match(calls[0].query, /mutation Enqueue/);
  }
});

test('token enrollment re-reads current hold evidence before any queue mutation', async () => {
  const { calls, core } = await tokenScenario({ freshMutate: pull => { pull.labels = [{ name: 'hold' }]; } });
  assert.equal(calls.length, 1, 'Do not dequeue or re-enqueue a held entry');
  assert.ok(core.messages.some(message => message.includes('explicit hold')));
});

test('token enrollment rejects missing labels and a source that changed since the queue snapshot', async () => {
  for (const freshMutate of [
    pull => { delete pull.labels; },
    pull => { pull.labels = [null]; },
    pull => { pull.head.sha = 'b'.repeat(40); },
    pull => { pull.draft = true; },
    pull => { pull.state = 'closed'; },
    pull => { pull.base.ref = 'production'; },
    pull => { pull.head.repo.full_name = 'someone/fork'; },
  ]) {
    const { calls } = await tokenScenario({ freshMutate });
    assert.equal(calls.length, 1, 'A stale queue listing cannot authorize a mutation');
  }
});

test('token enrollment preserves a denied fresh source read as a real failure', async () => {
  const denial = new Error('Resource not accessible by integration');
  // Exercise the production script with a real throwing API boundary.
  const context = {
    repo: { owner: 'JovieInc', repo: 'LogYourBody' }, eventName: 'workflow_run',
    payload: { workflow_run: { name: 'Native Merge Queue Enrollment', status: 'completed', conclusion: 'success', repository: { full_name: repository } } },
  };
  const github = {
    graphql: async query => {
      assert.match(query, /query Queue/, 'No mutation may follow a failed current-source read');
      return { repository: { mergeQueue: { entries: { nodes: [{
        enqueuer: { login: 'github-actions[bot]' },
        pullRequest: { id: 'PR_fixture', number: 1284, state: 'OPEN', isDraft: false, baseRefName: 'main', headRefOid: head, headRepository: { nameWithOwner: repository } },
      }] } } } };
    },
    rest: {
      checks: { listForRef: async () => ({ data: { check_runs: [{ name: 'CI Summary', conclusion: 'success', head_sha: head }] } }) },
      pulls: { get: async () => { throw denial; } },
    },
  };
  await assert.rejects(inlineScript(tokenWorkflow)(github, context, recordingCore()), error => error === denial);
});
