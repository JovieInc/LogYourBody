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
  };
}

async function nativeScenario({ mutate = () => {}, enqueueError, queuedMutate = () => {} } = {}) {
  const run = {
    name: 'CI',
    event: 'pull_request',
    status: 'completed',
    conclusion: 'success',
    head_sha: head,
    repository: { full_name: repository },
    pull_requests: [{ number: 1284 }],
  };
  const pull = {
    number: 1284,
    node_id: 'PR_fixture',
    draft: false,
    state: 'open',
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
      return { repository: { pullRequest: queued } };
    },
  };
  await inlineScript(nativeWorkflow)(github, context, core);
  return { calls, core };
}

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

async function tokenScenario({ mutate = () => {}, entryMutate = () => {} } = {}) {
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
      commits: {
        nodes: [
          {
            commit: {
              oid: head,
              statusCheckRollup: {
                contexts: { nodes: [{ name: 'CI Summary', conclusion: 'SUCCESS' }] },
              },
            },
          },
        ],
      },
    },
  };
  mutate(context);
  entryMutate(entry);
  const calls = [];
  const core = recordingCore();
  const github = {
    async graphql(query, variables) {
      calls.push({ query, variables });
      if (query.includes('query Queue'))
        return { repository: { mergeQueue: { entries: { nodes: [entry] } } } };
      if (query.includes('mutation Dequeue'))
        return { dequeuePullRequest: { mergeQueueEntry: { id: 'MQ_fixture' } } };
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
    (entry) => {
      entry.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[0].conclusion =
        'FAILURE';
    },
  ],
  [
    'missing summary',
    (entry) => {
      entry.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes = [];
    },
  ],
  [
    'summary from another commit',
    (entry) => {
      entry.pullRequest.commits.nodes[0].commit.oid = 'b'.repeat(40);
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
