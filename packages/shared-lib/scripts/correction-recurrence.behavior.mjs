import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  CORRECTION_LEDGER,
  planCorrectionIssues,
  runCorrectionRecurrence,
} from './correction-recurrence.mjs';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const receipt = (number, fingerprint = 'keep-test-gates') => ({
  fingerprint,
  correction: 'Preserve required tests when fixing a failing check.',
  source: `https://github.com/JovieInc/LogYourBody/pull/42#discussion_r${number}`,
  mechanization: 'Add a policy check rejecting removal of the required test command.',
});
const event = {
  repository: { full_name: 'JovieInc/LogYourBody' },
  workflow_run: {
    name: 'CI',
    path: '.github/workflows/ci.yml',
    workflow_id: 168687833,
    id: 1002,
    run_number: 101,
    run_attempt: 1,
    head_branch: 'main',
    event: 'push',
    conclusion: 'success',
    html_url: 'https://github.com/JovieInc/LogYourBody/actions/runs/1002',
  },
};

function linearStore(options = {}) {
  const issues = new Map();
  const labels = new Map();
  const calls = [];
  const states = [
    { id: 'todo', name: 'Todo', type: 'unstarted' },
    { id: 'done', name: 'Done', type: 'completed' },
  ];
  const response = (data) => new Response(JSON.stringify({ data }));
  const fetchImpl = async (url, init) => {
    assert.equal(url, 'https://api.linear.app/graphql');
    const { query, variables } = JSON.parse(init.body);
    calls.push({ query, variables });
    if (options.transport) throw new Error('offline fixture');
    if (query.includes('TeamByKey')) {
      assert.equal(variables.key, 'LYB');
      return response({ teams: { nodes: options.missingTeam ? [] : [{ id: 'lyb-team' }] } });
    }
    assert.equal(
      variables.teamId ?? (query.includes('UpdateDeduped') ? 'lyb-team' : null),
      'lyb-team',
    );
    if (query.includes('FindRemediationIssue')) {
      const found = [...issues.values()].filter((issue) =>
        issue.labels.nodes.some((label) => label.name === variables.filter.labels.some.name.eq),
      );
      return response({
        team: {
          states: { nodes: options.missingTodo ? [] : states },
          labels: { nodes: [...labels.values()] },
        },
        issues: { nodes: structuredClone(found), pageInfo: { hasNextPage: false } },
      });
    }
    if (query.includes('RemediationTeamLabelByName')) {
      return response({
        team: { labels: { nodes: [...labels.values()], pageInfo: { hasNextPage: false } } },
      });
    }
    if (query.includes('CreateTeamLabel')) {
      if (options.labelFailure) return response({ issueLabelCreate: { success: false } });
      if (!labels.has(variables.name))
        labels.set(variables.name, { id: `label-${labels.size}`, name: variables.name });
      return response({
        issueLabelCreate: { success: true, issueLabel: labels.get(variables.name) },
      });
    }
    if (query.includes('CreateDedupedLinearIssue')) {
      assert.match(query, /id: \$id/);
      assert.match(
        variables.id,
        /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/,
      );
      if (issues.has(variables.id)) return new Response('', { status: 409 });
      const issue = {
        ...variables,
        identifier: `LYB-${issues.size + 1}`,
        url: 'https://example.com/LYB-1',
        state: states.find((state) => state.id === variables.stateId),
        labels: {
          nodes: [...labels.values()].filter((label) => variables.labelIds.includes(label.id)),
        },
      };
      issues.set(issue.id, issue);
      if (options.lostCreateReply) {
        options.lostCreateReply = false;
        throw new Error('committed create, lost reply');
      }
      return response({ issueCreate: { success: true, issue } });
    }
    if (query.includes('UpdateDedupedLinearIssue')) {
      if (options.updateFailure) return response({ issueUpdate: { success: false } });
      const issue = issues.get(variables.id);
      Object.assign(issue, variables.input);
      return response({ issueUpdate: { success: true, issue } });
    }
    throw new Error('Unexpected fixture query');
  };
  return { issues, labels, calls, fetchImpl, options };
}

const intake = (store, receipts, overrides = {}) =>
  runCorrectionRecurrence({
    env: { GITHUB_REPOSITORY: 'JovieInc/LogYourBody', LINEAR_API_KEY: 'fixture-key' },
    eventName: 'workflow_run',
    event,
    receipts,
    fetchImpl: store.fetchImpl,
    ...overrides,
  });

test('only two distinct correction receipts for the same normalized fingerprint trigger an issue', () => {
  assert.doesNotThrow(() =>
    planCorrectionIssues(JSON.parse(readFileSync(CORRECTION_LEDGER, 'utf8'))),
  );
  for (const receipts of [
    [],
    [receipt(1)],
    [receipt(1), receipt(1)],
    [receipt(1), receipt(2, 'different')],
  ]) {
    assert.deepEqual(planCorrectionIssues(receipts), []);
  }
  const [plan] = planCorrectionIssues([receipt(1, ' KEEP TEST GATES '), receipt(1), receipt(2)]);
  assert.equal(plan.createStateName, 'Todo');
  assert.deepEqual(plan.createLabelNames, ['agent-ready']);
  assert.match(plan.title, /keep-test-gates/);
  assert.match(plan.description, /2 distinct receipts/);
  assert.match(plan.description, /discussion_r1/);
  assert.match(plan.description, /discussion_r2/);
  assert.match(plan.description, /Proposed guard: Add a policy check/);
  assert.match(plan.description, /fails without the guard and passes with it/);
  assert.equal(
    planCorrectionIssues([receipt(1), receipt(2), receipt(3, 'other'), receipt(4, 'other')]).length,
    2,
  );
  assert.equal(planCorrectionIssues([receipt(3), receipt(2), receipt(1)])[0].label, plan.label);
  assert.equal(planCorrectionIssues([receipt(3), receipt(2)])[0].createIssueId, plan.createIssueId);
  assert.notEqual(
    planCorrectionIssues([receipt(1, 'other'), receipt(2, 'other')])[0].createIssueId,
    plan.createIssueId,
  );
});

test('invalid or incomplete receipts are rejected before any filing', async () => {
  const credentialedSource = new URL('https://example.com');
  credentialedSource.username = 'fixture-user';
  credentialedSource.password = 'fixture-password';
  for (const receipts of [
    {},
    [null],
    [{ ...receipt(1), fingerprint: '' }],
    [{ ...receipt(1), source: 'not-a-url' }],
    [{ ...receipt(1), source: 'http://example.com' }],
    [{ ...receipt(1), source: credentialedSource.href }],
    [{ ...receipt(1), correction: ' ' }],
    [{ ...receipt(1), mechanization: '' }],
  ]) {
    const store = linearStore();
    assert.equal((await intake(store, receipts)).ok, false);
    assert.equal(store.calls.length, 0);
  }
});

test('the second correction creates a LYB agent-ready Todo; retries and further corrections reuse it', async () => {
  const store = linearStore();
  assert.equal((await intake(store, [receipt(1)])).reason, 'no_recurrence');
  assert.equal(store.calls.length, 0);
  const created = await intake(store, [receipt(1), receipt(2)]);
  assert.equal(created.issues[0].action, 'created');
  const issue = [...store.issues.values()][0];
  assert.equal(issue.state.id, 'todo');
  assert.equal(issue.teamId, 'lyb-team');
  assert.equal(
    issue.labels.nodes.some((label) => label.name === 'agent-ready'),
    true,
  );
  assert.equal(
    issue.labels.nodes.some((label) => label.name.startsWith('remediation:correction-')),
    true,
  );
  assert.equal((await intake(store, [receipt(1), receipt(2)])).issues[0].action, 'updated');
  assert.equal((await intake(store, [receipt(1), receipt(2), receipt(3)])).ok, true);
  assert.match(issue.description, /3 distinct receipts/);
  assert.equal(store.issues.size, 1);
  assert.equal(
    store.calls.filter(({ query }) => query.includes('CreateDedupedLinearIssue')).length,
    1,
  );
  // Replaying retained evidence must respect a completed mechanization task.
  issue.state = { id: 'done', type: 'completed' };
  assert.equal((await intake(store, [receipt(1), receipt(2), receipt(3)])).ok, true);
  assert.equal(issue.state.id, 'done');
});

test('overlapping runs and a lost create acknowledgment cannot duplicate the mechanization issue', async () => {
  for (const lostCreateReply of [false, true]) {
    const store = linearStore({ lostCreateReply });
    const results = await Promise.all([
      intake(store, [receipt(1), receipt(2)]),
      intake(store, [receipt(1), receipt(2)]),
    ]);
    assert.equal(
      results.every((result) => result.ok),
      true,
      JSON.stringify(results),
    );
    assert.equal(store.issues.size, 1);
    const ids = store.calls
      .filter(({ query }) => query.includes('CreateDedupedLinearIssue'))
      .map(({ variables }) => variables.id);
    assert.equal(new Set(ids).size, 1);
  }
});

test('the kill switch and unverified events cannot read the ledger or call Linear', async () => {
  const store = linearStore();
  const base = { ledgerPath: '/missing-ledger', receipts: undefined };
  const disabled = await intake(store, [], { ...base, env: { REMEDIATION_INTAKE_DISABLED: '1' } });
  assert.equal(disabled.action, 'disabled');
  for (const overrides of [
    { eventName: 'pull_request' },
    { event: { ...event, workflow_run: { ...event.workflow_run, head_branch: 'feature' } } },
    { event: { ...event, workflow_run: { ...event.workflow_run, event: 'pull_request' } } },
    {
      event: {
        ...event,
        workflow_run: { ...event.workflow_run, path: '.github/workflows/other.yml' },
      },
    },
    { env: { GITHUB_REPOSITORY: 'other/repo', LINEAR_API_KEY: 'fixture-key' } },
  ]) {
    assert.equal((await intake(store, [], { ...base, ...overrides })).action, 'skip');
  }
  assert.equal(store.calls.length, 0);
});

test('missing credentials, LYB team, Todo state, and API failures remain explicit and retryable', async () => {
  const receipts = [receipt(1), receipt(2)];
  assert.equal(
    (await intake(linearStore(), receipts, { env: {} })).reason,
    'missing_linear_api_key',
  );
  for (const [options, reason] of [
    [{ missingTeam: true }, 'linear_team_missing'],
    [{ missingTodo: true }, 'linear_create_state_missing'],
    [{ transport: true }, 'linear_team_by_key_transport'],
    [{ labelFailure: true }, 'linear_label_create_unsuccessful'],
  ]) {
    const store = linearStore(options);
    const result = await intake(store, receipts);
    assert.equal(result.reason, reason);
    assert.equal(result.ok, false);
    assert.equal(store.issues.size, 0);
    for (const key of Object.keys(options)) options[key] = false;
    assert.equal((await intake(store, receipts)).ok, true);
  }
  const store = linearStore();
  await intake(store, receipts);
  store.options.updateFailure = true;
  assert.equal((await intake(store, receipts)).ok, false);
  store.options.updateFailure = false;
  assert.equal((await intake(store, receipts)).ok, true);
  assert.equal(store.issues.size, 1);
});

test('the nightly main probe also admits recurrence without a failed build', async () => {
  const store = linearStore();
  const result = await intake(store, [receipt(1), receipt(2)], {
    eventName: 'schedule',
    event: {},
    env: {
      LINEAR_API_KEY: 'fixture-key',
      GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
      GITHUB_WORKFLOW_REF:
        'JovieInc/LogYourBody/.github/workflows/remediation-signal.yml@refs/heads/main',
      GITHUB_RUN_NUMBER: '101',
      GITHUB_RUN_ID: '1002',
      GITHUB_RUN_ATTEMPT: '1',
      REMEDIATION_RUN_URL: 'https://github.com/JovieInc/LogYourBody/actions/runs/1002',
    },
  });
  assert.equal(result.ok, true);
  assert.equal(store.issues.size, 1);
});

test('the real intake CLI files an agent-ready issue and reports malformed ledgers', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-corrections-cli-'));
  try {
    const ledger = join(dir, 'corrections.json');
    const eventPath = join(dir, 'event.json');
    const preload = join(dir, 'fixture.mjs');
    writeFileSync(eventPath, JSON.stringify(event));
    writeFileSync(
      preload,
      `
      import assert from 'node:assert/strict';
      const store = (${linearStore.toString()})();
      globalThis.fetch = store.fetchImpl;
      process.on('exit', () => {
        for (const issue of store.issues.values()) {
          assert.equal(issue.state.id, 'todo');
          assert.ok(issue.labels.nodes.some(label => label.name === 'agent-ready'));
          assert.match(issue.description, /discussion_r1/);
          assert.match(issue.description, /discussion_r2/);
          console.log('fixture-created:' + issue.identifier);
        }
      });
    `,
    );
    for (const malformed of [false, true]) {
      writeFileSync(ledger, malformed ? '{broken json' : JSON.stringify([receipt(1), receipt(2)]));
      const result = spawnSync(
        process.execPath,
        ['--import', preload, '.github/scripts/remediation-signal-intake.mjs'],
        {
          cwd: root,
          encoding: 'utf8',
          timeout: 10_000,
          env: {
            GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
            LINEAR_API_KEY: 'fixture-key',
            GITHUB_EVENT_NAME: 'workflow_run',
            GITHUB_EVENT_PATH: eventPath,
            CORRECTION_LEDGER_PATH: ledger,
          },
        },
      );
      assert.ifError(result.error);
      assert.equal(result.status, 0, result.stderr);
      if (malformed) {
        assert.match(
          result.stderr,
          /Correction recurrence did NOT file: correction_ledger_invalid/,
        );
        assert.doesNotMatch(result.stdout, /fixture-created/);
      } else {
        assert.equal(result.stderr, '');
        assert.match(result.stdout, /fixture-created:LYB-1/);
      }
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('the existing main intake attempts mandatory recurrence filing even on steady green', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-corrections-'));
  try {
    const ledger = join(dir, 'corrections.json');
    const eventPath = join(dir, 'event.json');
    const summary = join(dir, 'summary.md');
    writeFileSync(ledger, JSON.stringify([receipt(1), receipt(2)]));
    writeFileSync(eventPath, JSON.stringify(event));
    const result = spawnSync(process.execPath, ['.github/scripts/remediation-signal-intake.mjs'], {
      cwd: root,
      encoding: 'utf8',
      timeout: 10_000,
      env: {
        GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
        GITHUB_EVENT_NAME: 'workflow_run',
        GITHUB_EVENT_PATH: eventPath,
        GITHUB_STEP_SUMMARY: summary,
        CORRECTION_LEDGER_PATH: ledger,
        LINEAR_API_KEY: '',
      },
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stderr, /Correction recurrence did NOT file: missing_linear_api_key/);
    assert.match(readFileSync(summary, 'utf8'), /Correction recurrence did NOT file/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
