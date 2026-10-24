import assert from 'node:assert/strict';
import { logYourBody } from '../../packages/product-registry/src/products/logyourbody.mjs';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { JOVIE_TEAM_ID, remediationKey, remediationProvenanceLabel, upsertLinearIssue } from './lib/linear-issue-intake.mjs';
import {
  applySyntheticGuard,
  classifyProbeStatuses,
  decideHttpStatus,
  decideMonitorSignal,
  detectorFromGithubEvent,
  gateSteadyGreen,
  probeHomepage,
  remediationIntakeDisabled,
  requestHomepage,
  runRemediationIntake,
  skippedFilingMessage,
} from './remediation-signal.mjs';
import { noteFilingSkipped } from './remediation-signal-intake.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

test('ordinary CI cannot close a release origin after its description is changed to CI', async () => {
  const mutations = [];
  const release = {
    id: 'release-issue', identifier: 'LYB-152', description: 'Source-workflow: CI\nmutated',
    state: { type: 'unstarted' },
    labels: { nodes: [
      { name: 'remediation:red-checks' },
      { name: 'remediation-origin:v1:jovieinc/logyourbody:175434524:100:1001:1' },
      { name: 'remediation-red:v1:jovieinc/logyourbody:175434524:100:1001:1' },
    ], pageInfo: { hasNextPage: false } },
  };
  const result = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key', GITHUB_REPOSITORY: 'JovieInc/LogYourBody' },
    eventName: 'workflow_run', previous: 'red',
    event: { repository: { full_name: 'JovieInc/LogYourBody' }, workflow_run: {
      name: 'CI', workflow_id: 168687833, id: 1002, run_number: 101, run_attempt: 1,
      path: '.github/workflows/ci.yml',
      head_branch: 'main', event: 'push', conclusion: 'success',
      html_url: 'https://github.com/JovieInc/LogYourBody/actions/runs/1002',
    } },
    fetchImpl: async (_url, init) => {
      const body = JSON.parse(init.body);
      if (body.query.includes('TeamByKey')) return jsonResponse({ data: { teams: { nodes: [{ id: 'lyb-team', key: 'LYB' }] } } });
      if (body.query.includes('FindRemediationForGreen')) return jsonResponse({ data: {
        team: { states: { nodes: [{ id: 'done', name: 'Done', type: 'completed' }] } },
        issues: { nodes: [release], pageInfo: { hasNextPage: false } },
      } });
      mutations.push(body);
      if (body.query.includes('commentCreate')) return jsonResponse({ data: { commentCreate: { success: true, comment: { id: 'c1' } } } });
      if (body.query.includes('ResolveRemediation')) return jsonResponse({ data: { issueUpdate: { success: true, issue: { id: release.id } } } });
      return jsonResponse({}, false);
    },
  });
  assert.equal(result.state, null);
  assert.equal(result.reason, 'source_provenance_mismatch');
  assert.deepEqual(mutations, []);
});

const mainRun = (name, conclusion, overrides = {}) => ({
  repository: { full_name: 'JovieInc/LogYourBody' },
  workflow_run: {
    name,
    workflow_id: name === 'CI' ? 168687833 : 168687834,
    path: name === 'CI' ? '.github/workflows/ci.yml' : '.github/workflows/deploy.yml',
    id: conclusion === 'failure' ? 1001 : 1002,
    run_number: conclusion === 'failure' ? 100 : 101,
    run_attempt: 1,
    head_branch: 'main',
    event: 'push',
    conclusion,
    html_url: 'https://github.com/JovieInc/LogYourBody/actions/runs/' + (overrides.id ?? (conclusion === 'failure' ? 1001 : 1002)),
    ...overrides,
  },
});

const syntheticEnv = {
  LINEAR_API_KEY: 'key', GITHUB_REPOSITORY: 'JovieInc/LogYourBody',
  GITHUB_WORKFLOW_REF: 'JovieInc/LogYourBody/.github/workflows/remediation-signal.yml@refs/heads/main',
  GITHUB_RUN_NUMBER: '100', GITHUB_RUN_ID: '1001', GITHUB_RUN_ATTEMPT: '1',
  REMEDIATION_RUN_URL: 'https://github.com/JovieInc/LogYourBody/actions/runs/1001',
};

function jsonResponse(payload, ok = true) {
  const serialized = JSON.stringify(payload);
  return { ok, status: ok ? 200 : 500, text: async () => serialized };
}

const ciOrigin = {
  repository: 'JovieInc/LogYourBody', workflowId: '168687833',
  runNumber: '100', runId: '1001', runAttempt: '1',
};

function boundIssue(id, { origin = ciOrigin, state = 'unstarted', description = 'Source-workflow: CI' } = {}) {
  return {
    id, identifier: 'LYB-' + id, description,
    state: { id: state === 'unstarted' ? 'todo' : state === 'completed' ? 'done' : state, type: state },
    labels: { nodes: [
      { name: 'remediation:red-checks' },
      { name: remediationProvenanceLabel(origin) },
      { name: 'unrelated-owner-label' },
    ], pageInfo: { hasNextPage: false } },
  };
}

/** Stateful GraphQL fixture: issue state and label additions commit together. */
function linearStore(initial = []) {
  const issues = structuredClone(initial);
  const labels = new Map();
  const calls = [];
  const failures = {};
  const hooks = {};
  const states = [
    { id: 'todo', name: 'Todo', type: 'unstarted' },
    { id: 'backlog', name: 'Backlog', type: 'backlog' },
    { id: 'done', name: 'Done', type: 'completed' },
  ];
  const label = (name) => {
    if (!labels.has(name)) labels.set(name, { id: 'label-' + labels.size, name });
    return labels.get(name);
  };
  for (const issue of issues) issue.labels.nodes = issue.labels.nodes.map((node) => label(node.name));
  const labelPage = (issue, after = 0) => {
    const start = Number(after);
    const nodes = issue.labels.nodes.slice(start, start + 100);
    return { nodes, pageInfo: {
      hasNextPage: issue.labels.pageInfo.hasNextPage || start + 100 < issue.labels.nodes.length,
      endCursor: start + 100 < issue.labels.nodes.length ? String(start + 100) : null,
    } };
  };
  const snapshot = (issue) => structuredClone({ ...issue, team: { id: 'lyb-team' }, labels: labelPage(issue) });
  const fetchImpl = async (_url, init) => {
    const body = JSON.parse(init.body);
    const { query, variables } = body;
    calls.push(body);
    await hooks.before?.(body);
    if (query.includes('TeamByKey')) return jsonResponse({ data: { teams: { nodes: [{ id: 'lyb-team', key: 'LYB' }] } } });
    if (query.includes('FindRemediation')) return jsonResponse({ data: {
      team: { states: { nodes: states }, labels: { nodes: [...labels.values()].slice(0, 50) } },
      issues: { nodes: issues.map(snapshot), pageInfo: { hasNextPage: failures.incompleteIssues === true } },
    } });
    if (query.includes('RemediationTeamLabelByName')) {
      if (failures.labelLookup) return jsonResponse({}, false);
      const start = Number(variables.after ?? 0);
      const all = [...labels.values()];
      return jsonResponse({ data: { team: { labels: {
        nodes: all.slice(start, start + 100),
        pageInfo: { hasNextPage: start + 100 < all.length,
          endCursor: start + 100 < all.length ? String(start + 100) : null },
      } } } });
    }
    if (query.includes('RemediationIssueLabels')) {
      if (failures.labelPage) return jsonResponse({}, false);
      const issue = issues.find((node) => node.id === variables.id);
      return jsonResponse({ data: { issue: { id: issue.id, labels: labelPage(issue, variables.after) } } });
    }
    if (query.includes('RemediationIssueForReconciliation')) {
      if (failures.reconcileRead) return jsonResponse({}, false);
      const issue = issues.find((node) => node.id === variables.id);
      const response = jsonResponse({ data: { issue: snapshot(issue), team: { states: { nodes: states } } } });
      await hooks.afterRead?.(body);
      return response;
    }
    if (query.includes('CreateTeamLabel')) {
      const created = label(variables.name);
      if (failures.label) {
        failures.label = false;
        return jsonResponse({ errors: [{ message: 'lost label acknowledgment' }] }, false);
      }
      return jsonResponse({ data: { issueLabelCreate: { success: true, issueLabel: created } } });
    }
    if (query.includes('CreateDedupedLinearIssue')) {
      const created = {
        id: 'issue-' + (issues.length + 1), identifier: 'LYB-' + (issues.length + 1),
        description: variables.description,
        state: states.find((state) => state.id === variables.stateId),
        labels: { nodes: variables.labelIds.map((id) => [...labels.values()].find((node) => node.id === id)),
          pageInfo: { hasNextPage: false } },
      };
      issues.push(created);
      if (failures.create) {
        failures.create = false;
        return jsonResponse({ errors: [{ message: 'lost create acknowledgment' }] }, false);
      }
      return jsonResponse({ data: { issueCreate: { success: true, issue: created } } });
    }
    if (query.includes('commentCreate')) {
      if (failures.comment) {
        failures.comment = false;
        return jsonResponse({ errors: [{ message: 'comment unavailable' }] }, false);
      }
      return jsonResponse({ data: { commentCreate: { success: true, comment: { id: 'comment' } } } });
    }
    if (query.includes('UpdateDedupedLinearIssue') || query.includes('ResolveRemediation') ||
        query.includes('ReconcileRemediationState')) {
      if (failures.update) {
        failures.update = false;
        return jsonResponse({ errors: [{ message: 'update unavailable' }] }, false);
      }
      const issue = issues.find((node) => node.id === variables.id);
      const input = variables.input;
      if (input.description !== undefined) issue.description = input.description;
      if (input.stateId) issue.state = states.find((state) => state.id === input.stateId);
      for (const id of input.addedLabelIds ?? []) {
        const added = [...labels.values()].find((node) => node.id === id);
        assert.ok(added, 'only acknowledged label IDs can be committed');
        if (!issue.labels.nodes.some((node) => node.id === id)) issue.labels.nodes.push(added);
      }
      await hooks.afterWrite?.(body);
      if (failures.updateAck) {
        failures.updateAck = false;
        return jsonResponse({ errors: [{ message: 'committed update lost acknowledgment' }] }, false);
      }
      return jsonResponse({ data: { issueUpdate: { success: true, issue } } });
    }
    throw new Error('Unexpected fixture operation: ' + query);
  };
  return { issues, labels, calls, failures, hooks, fetchImpl, label };
}

function intakeCi(store, conclusion, number, id, attempt = 1, overrides = {}) {
  return runRemediationIntake({
    env: { LINEAR_API_KEY: 'key', GITHUB_REPOSITORY: 'JovieInc/LogYourBody' },
    eventName: 'workflow_run', previous: 'red', fetchImpl: store.fetchImpl,
    event: mainRun('CI', conclusion, { run_number: number, id, run_attempt: attempt, ...overrides }),
  });
}

function writes(store) {
  return store.calls.filter((body) => body.query.includes('mutation '));
}

test('CI origin is atomic, immutable across new reds, and recovery ignores description edits', async () => {
  const store = linearStore();
  assert.equal((await intakeCi(store, 'failure', 100, 1001)).state, 'red');
  const issue = store.issues[0];
  const origin = 'remediation-origin:v1:jovieinc/logyourbody:168687833:100:1001:1';
  assert.ok(issue.labels.nodes.some((node) => node.name === origin));
  assert.equal(store.issues.length, 1);
  assert.equal((await intakeCi(store, 'failure', 102, 1003)).state, 'red');
  assert.deepEqual(issue.labels.nodes.filter((node) => node.name.startsWith('remediation-origin:')).map((node) => node.name), [origin]);
  issue.description = 'Source-workflow: iOS Release Loop\nhuman-edited notes';
  assert.equal((await intakeCi(store, 'success', 103, 1004)).state, 'green');
  assert.equal(issue.state.type, 'completed');
  assert.equal(issue.description, 'Source-workflow: iOS Release Loop\nhuman-edited notes');
  const recovery = writes(store).find((body) => body.query.includes('ResolveRemediation'));
  assert.equal(recovery.variables.input.stateId, 'done');
  assert.deepEqual(recovery.variables.input.addedLabelIds.map((id) => [...store.labels.values()].find((node) => node.id === id).name),
    ['remediation-green:v1:jovieinc/logyourbody:168687833:103:1004:1']);
});

test('a red CI event cannot overwrite, reopen, or replace a release-bound issue', async () => {
  for (const state of ['unstarted', 'completed']) {
    const issue = boundIssue('release', { origin: { ...ciOrigin, workflowId: '175434524' }, state });
    const store = linearStore([issue]);
    const result = await intakeCi(store, 'failure', 101, 1002);
    assert.equal(result.reason, 'source_provenance_mismatch');
    assert.equal(result.state, null);
    assert.equal(store.issues.length, 1);
    assert.deepEqual(writes(store), []);
    assert.equal(store.issues[0].description, issue.description);
    assert.equal(store.issues[0].state.type, state);
  }
});

test('legacy, partial, ambiguous and foreign origins never gain authority from CI prose', async () => {
  const legacy = boundIssue('legacy');
  legacy.labels.nodes = [{ name: 'remediation:red-checks' }];
  const partial = boundIssue('partial');
  partial.labels.nodes[1].name = 'remediation-origin:v1:jovieinc/logyourbody:168687833:100';
  const ambiguous = boundIssue('ambiguous');
  ambiguous.labels.nodes.push({ name: remediationProvenanceLabel({ ...ciOrigin, workflowId: '175434524' }) });
  const foreign = boundIssue('foreign', { origin: { ...ciOrigin, repository: 'JovieInc/Other' } });
  const malformed = boundIssue('malformed');
  malformed.labels.nodes[1].name = 'remediation-origin:v1:jovieinc/logyourbody:168687833:100x:1001:1';
  for (const fixture of [legacy, partial, ambiguous, foreign, malformed]) {
    const store = linearStore([fixture]);
    for (const conclusion of ['failure', 'success']) {
      const result = await intakeCi(store, conclusion, 101, 1002);
      assert.equal(result.state, null);
      assert.equal(result.reason, 'source_provenance_mismatch');
    }
    assert.deepEqual(writes(store), []);
    assert.equal(store.issues.length, 1);
  }
});

test('newer red watermarks reject older greens and exact completed-attempt replay', async () => {
  const store = linearStore();
  await intakeCi(store, 'failure', 100, 1001);
  await intakeCi(store, 'failure', 102, 1003);
  const before = writes(store).length;
  for (const [conclusion, number, id] of [['success', 101, 1002], ['success', 102, 1003], ['failure', 100, 1001]]) {
    const result = await intakeCi(store, conclusion, number, id);
    assert.equal(result.action, 'stale_signal');
    assert.equal(result.state, null);
  }
  assert.equal(writes(store).length, before);
  assert.equal(store.issues[0].state.type, 'unstarted');
  assert.equal((await intakeCi(store, 'success', 103, 1004)).state, 'green');
});

test('recovery fences delayed reds, replay cannot reopen, and a genuinely later failure can', async () => {
  const store = linearStore();
  await intakeCi(store, 'failure', 100, 1001);
  await intakeCi(store, 'success', 103, 1004);
  const before = writes(store).length;
  for (const [number, id] of [[100, 1001], [101, 1002], [103, 1004]]) {
    const result = await intakeCi(store, 'failure', number, id);
    assert.equal(result.state, null);
    assert.equal(result.action, 'stale_signal');
  }
  assert.equal(writes(store).length, before);
  assert.equal(store.issues[0].state.type, 'completed');
  assert.equal((await intakeCi(store, 'failure', 104, 1005)).state, 'red');
  assert.equal(store.issues[0].state.type, 'unstarted');
  assert.equal(store.issues.length, 1);
  assert.equal((await intakeCi(store, 'success', 105, 1006)).state, 'green');
});

test('later attempts recover the exact same run; a conflicting run ID never does', async () => {
  const store = linearStore();
  await intakeCi(store, 'failure', 100, 1001);
  const before = writes(store).length;
  const conflict = await intakeCi(store, 'success', 100, 9001, 2);
  assert.equal(conflict.reason, 'source_run_conflict');
  assert.equal(conflict.state, null);
  assert.equal(writes(store).length, before);
  assert.equal((await intakeCi(store, 'success', 100, 1001, 2)).state, 'green');
  assert.equal(store.issues[0].state.type, 'completed');
  assert.equal((await intakeCi(store, 'failure', 100, 1001, 1)).state, null);
  assert.equal((await intakeCi(store, 'failure', 100, 1001, 3)).state, 'red');
  assert.equal((await intakeCi(store, 'success', 100, 1001, 4)).state, 'green');
});

test('compatible live survivor wins over foreign and canceled duplicates', async () => {
  const foreign = boundIssue('release', { origin: { ...ciOrigin, workflowId: '175434524' } });
  const canceled = boundIssue('dupe', { state: 'canceled' });
  const live = boundIssue('survivor');
  const store = linearStore([foreign, canceled, live]);
  const result = await intakeCi(store, 'success', 101, 1002);
  assert.equal(result.id, 'survivor');
  assert.equal(store.issues[0].state.type, 'unstarted');
  assert.equal(store.issues[1].state.type, 'canceled');
  assert.equal(store.issues[2].state.type, 'completed');
  assert.equal((await intakeCi(store, 'failure', 102, 1003)).id, 'survivor');
  assert.equal(store.issues[1].state.type, 'canceled');
  assert.ok(store.issues[2].labels.nodes.some((node) => node.name === 'unrelated-owner-label'));
});

test('API failures and lost acknowledgments preserve retryability without duplicate issues', async () => {
  for (const kind of ['create']) {
    const store = linearStore();
    store.failures[kind] = true;
    const failed = await intakeCi(store, 'failure', 100, 1001);
    assert.equal(failed.ok, false);
    assert.equal(failed.state, null);
    assert.equal((await intakeCi(store, 'failure', 100, 1001)).state, 'red');
    assert.equal(store.issues.length, 1);
    assert.equal(store.issues[0].labels.nodes.filter((node) => node.name.startsWith('remediation-origin:')).length, 1);
  }
  for (const kind of ['comment', 'update']) {
    const store = linearStore();
    await intakeCi(store, 'failure', 100, 1001);
    store.failures[kind] = true;
    const failed = await intakeCi(store, 'success', 101, 1002);
    assert.equal(failed.ok, false);
    assert.equal(failed.state, null);
    assert.equal(store.issues[0].state.type, 'unstarted');
    assert.equal(store.issues[0].labels.nodes.some((node) => node.name.startsWith('remediation-green:')), false);
    assert.equal((await intakeCi(store, 'success', 101, 1002)).state, 'green');
    assert.equal(store.issues[0].state.type, 'completed');
    assert.equal(store.issues.length, 1);
  }
});

test('missing event identity, mismatched workflow paths and run URLs cannot mutate Linear', async () => {
  for (const override of [
    { workflow_id: undefined }, { run_number: '100x' }, { run_attempt: 0 },
    { path: '.github/workflows/ios-release-loop.yml' },
    { html_url: 'https://github.com/JovieInc/Other/actions/runs/1002' },
    { html_url: 'https://github.com/JovieInc/LogYourBody/actions/runs/9999' },
    { repository: { full_name: 'JovieInc/Other' } },
  ]) {
    const store = linearStore([boundIssue('original')]);
    const result = await intakeCi(store, 'success', 101, 1002, 1, override);
    assert.equal(result.state, null);
    assert.equal(result.reason, 'invalid_source_provenance');
    assert.deepEqual(writes(store), []);
  }
});

test('workflow webhook metadata supplies path and must agree with the stable workflow ID', async () => {
  const store = linearStore();
  const event = mainRun('CI', 'failure', { path: undefined });
  event.workflow = { id: 168687833, path: '.github/workflows/ci.yml' };
  const options = { env: { LINEAR_API_KEY: 'key', GITHUB_REPOSITORY: 'JovieInc/LogYourBody' },
    eventName: 'workflow_run', previous: 'red', event, fetchImpl: store.fetchImpl };
  assert.equal((await runRemediationIntake(options)).state, 'red');
  for (const workflow of [
    { id: 175434524, path: '.github/workflows/ci.yml' },
    { id: 168687833, path: '.github/workflows/ios-release-loop.yml' },
  ]) {
    const before = writes(store).length;
    assert.equal((await runRemediationIntake({ ...options, event: {
      ...mainRun('CI', 'success'), workflow,
    } })).reason, 'invalid_source_provenance');
    assert.equal(writes(store).length, before);
  }
});

test('truncated issue or label inventories fail closed before comment or mutation', async () => {
  for (const target of ['issues', 'labels']) {
    const store = linearStore([boundIssue('original')]);
    if (target === 'issues') store.failures.incompleteIssues = true;
    else store.issues[0].labels.pageInfo.hasNextPage = true;
    for (const conclusion of ['failure', 'success']) {
      const result = await intakeCi(store, conclusion, 101, 1002);
      assert.equal(result.state, null);
      assert.equal(result.ok, false);
    }
    assert.deepEqual(writes(store), []);
    assert.equal(store.issues.length, 1);
  }
});

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

test('concurrent stale snapshots converge after older green or red writes last', async () => {
  for (const scenario of [
    { delayed: 'success', older: 101, other: 'failure', newer: 102, color: 'red', type: 'unstarted' },
    { delayed: 'failure', older: 101, other: 'success', newer: 102, color: 'green', type: 'completed' },
    { delayed: 'failure', older: 102, other: 'success', newer: 101, color: 'red', type: 'unstarted' },
  ]) {
    const store = linearStore();
    await intakeCi(store, 'failure', 100, 1001);
    const entered = deferred();
    const resume = deferred();
    let paused = false;
    store.hooks.before = async ({ query }) => {
      const targeted = scenario.delayed === 'success' ? 'ResolveRemediation' : 'UpdateDedupedLinearIssue';
      if (!paused && query.includes(targeted)) {
        paused = true;
        entered.resolve();
        await resume.promise;
      }
    };
    const delayed = intakeCi(store, scenario.delayed, scenario.older, scenario.older + 901);
    await entered.promise;
    const other = await intakeCi(store, scenario.other, scenario.newer, scenario.newer + 901);
    resume.resolve();
    const result = await delayed;
    assert.equal(store.issues[0].state.type, scenario.type);
    assert.equal(result.state, scenario.older < scenario.newer ? null : scenario.color);
    if (scenario.older < scenario.newer) assert.equal(result.action, 'superseded');
    assert.equal(other.state, scenario.other === 'success' ? 'green' : 'red');
  }
});

test('a state correction also re-reads when another receipt commits after its snapshot', async () => {
  const store = linearStore();
  await intakeCi(store, 'failure', 100, 1001);
  const greenEntered = deferred();
  const resumeGreen = deferred();
  let paused = false;
  store.hooks.before = async ({ query }) => {
    if (!paused && query.includes('ResolveRemediation')) {
      paused = true;
      greenEntered.resolve();
      await resumeGreen.promise;
    }
  };
  const green = intakeCi(store, 'success', 101, 1002);
  await greenEntered.promise;
  await intakeCi(store, 'failure', 102, 1003);
  store.hooks.afterRead = async () => {
    store.hooks.afterRead = null;
    await intakeCi(store, 'success', 103, 1004);
  };
  resumeGreen.resolve();
  const superseded = await green;
  assert.equal(superseded.state, null);
  assert.equal(superseded.action, 'superseded');
  assert.equal(store.issues[0].state.type, 'completed');
  assert.equal(writes(store).filter((body) => body.query.includes('ReconcileRemediationState')).length, 2);
});

test('committed red and green updates with lost responses recover on exact retry', async () => {
  for (const conclusion of ['failure', 'success']) {
    const store = linearStore();
    await intakeCi(store, 'failure', 100, 1001);
    store.failures.updateAck = true;
    const uncertain = await intakeCi(store, conclusion, 101, 1002);
    assert.equal(uncertain.ok, false);
    assert.equal(uncertain.state, null);
    assert.equal((await intakeCi(store, conclusion, 101, 1002)).state, conclusion === 'success' ? 'green' : 'red');
    assert.equal(store.issues.length, 1);
    assert.equal(store.issues[0].labels.nodes.filter((node) => node.name.endsWith(':101:1002:1')).length, 1);
  }
});

test('equal red replay preserves manual Done without green, but repairs older-green inconsistency', async () => {
  const manual = linearStore();
  await intakeCi(manual, 'failure', 100, 1001);
  await intakeCi(manual, 'failure', 102, 1003);
  manual.issues[0].state = { id: 'done', type: 'completed' };
  const before = writes(manual).length;
  assert.equal((await intakeCi(manual, 'failure', 102, 1003)).action, 'stale_signal');
  assert.equal(writes(manual).length, before);
  assert.equal(manual.issues[0].state.type, 'completed');

  const raced = linearStore();
  await intakeCi(raced, 'failure', 100, 1001);
  await intakeCi(raced, 'success', 101, 1002);
  await intakeCi(raced, 'failure', 102, 1003);
  raced.issues[0].state = { id: 'done', type: 'completed' };
  assert.equal((await intakeCi(raced, 'failure', 102, 1003)).state, 'red');
  assert.equal(raced.issues[0].state.type, 'unstarted');
});

test('complete label pagination preserves later recovery and fails closed on page errors', async () => {
  for (const fail of [false, true]) {
    const issue = boundIssue('long-history');
    for (let number = 101; number <= 220; number += 1) {
      issue.labels.nodes.push({ name: remediationProvenanceLabel({ ...ciOrigin,
        runNumber: String(number), runId: String(number + 901) }, 'red') });
    }
    const store = linearStore([issue]);
    store.failures.labelPage = fail;
    const result = await intakeCi(store, 'success', 221, 1122);
    assert.equal(result.state, fail ? null : 'green');
    assert.equal(store.issues[0].state.type, fail ? 'unstarted' : 'completed');
    assert.ok(store.calls.some((body) => body.query.includes('RemediationIssueLabels')));
    if (fail) assert.deepEqual(writes(store), []);
  }
});

test('exact-name label recovery finds orphan receipts beyond the default team page', async () => {
  const store = linearStore();
  for (let index = 0; index < 160; index += 1) store.label('unrelated-' + index);
  store.failures.label = true;
  assert.equal((await intakeCi(store, 'failure', 100, 1001)).state, 'red');
  store.failures.update = true;
  assert.equal((await intakeCi(store, 'success', 101, 1002)).state, null);
  const creates = writes(store).filter((body) => body.query.includes('CreateTeamLabel')).length;
  assert.equal((await intakeCi(store, 'success', 101, 1002)).state, 'green');
  assert.equal(writes(store).filter((body) => body.query.includes('CreateTeamLabel')).length, creates);
});

test('missing red state and unavailable final verification never record continuity', async () => {
  const missing = linearStore([boundIssue('missing-state')]);
  delete missing.issues[0].state.id;
  assert.equal((await intakeCi(missing, 'failure', 101, 1002)).reason, 'linear_red_state_missing');
  assert.equal(missing.issues[0].state.type, 'unstarted');
  assert.equal(writes(missing).some((body) => body.query.includes('issueUpdate')), false);
  const unavailable = linearStore();
  await intakeCi(unavailable, 'failure', 100, 1001);
  unavailable.failures.reconcileRead = true;
  const result = await intakeCi(unavailable, 'success', 101, 1002);
  assert.equal(result.ok, false);
  assert.equal(result.state, null);
  unavailable.failures.reconcileRead = false;
  assert.equal((await intakeCi(unavailable, 'success', 101, 1002)).state, 'green');
});

test('bounded exhaustion verifies the last correction and never records continuity', async () => {
  const store = linearStore();
  await intakeCi(store, 'failure', 100, 1001);
  store.hooks.afterWrite = async () => {
    // Another actor changes state after each acknowledged write.
    store.issues[0].state = { id: 'done', type: 'completed' };
  };
  const result = await intakeCi(store, 'failure', 101, 1002);
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'source_provenance_reconciliation_busy');
  assert.equal(result.state, null);
  assert.match(store.calls.at(-1).query, /RemediationIssueForReconciliation/);
});

test('kill switch is exact and unset files', () => {
  assert.equal(remediationIntakeDisabled({}), false);
  assert.equal(remediationIntakeDisabled({ REMEDIATION_INTAKE_DISABLED: '' }), false);
  assert.equal(remediationIntakeDisabled({ REMEDIATION_INTAKE_DISABLED: 'true' }), false);
  assert.equal(remediationIntakeDisabled({ REMEDIATION_INTAKE_DISABLED: '1' }), true);
  assert.equal(remediationKey('red-checks'), 'remediation:red-checks');
  assert.equal(remediationKey('remediation:synthetic-monitoring'), 'remediation:synthetic-monitoring');
});

test('only main-branch pushes and the nightly probe are detectors', () => {
  assert.equal(detectorFromGithubEvent('pull_request', {}), null);
  assert.equal(
    detectorFromGithubEvent('workflow_run', {
      workflow_run: { name: 'CI', head_branch: 'feat', event: 'pull_request', conclusion: 'failure' },
    }),
    null,
  );
  assert.equal(detectorFromGithubEvent('workflow_run', mainRun('CI', 'failure')).fingerprint, 'red-checks');
  assert.equal(detectorFromGithubEvent('workflow_run', mainRun('Deploy', 'failure')).fingerprint, 'web-deploy');
  assert.equal(detectorFromGithubEvent('workflow_run', mainRun('iOS Release Loop', 'failure')), null);
  assert.equal(detectorFromGithubEvent('schedule', {}).fingerprint, 'synthetic-monitoring');
  assert.equal(decideMonitorSignal({ conclusion: 'success' }).action, 'green');
  assert.equal(decideMonitorSignal({ conclusion: 'skipped' }).action, 'skip');
  assert.equal(decideHttpStatus(200).action, 'green');
  assert.equal(decideHttpStatus(503).action, 'red');
  assert.equal(gateSteadyGreen({ action: 'green' }, 'green').reason, 'steady_green');
  assert.equal(gateSteadyGreen({ action: 'green' }, 'red').action, 'green');
  assert.equal(gateSteadyGreen({ action: 'red' }, 'green').action, 'red');
});

test('steady green and the kill switch do not call Linear', async () => {
  const fetchImpl = async () => {
    throw new Error('linear called');
  };
  const steady = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'workflow_run',
    event: mainRun('CI', 'success'),
    previous: 'green',
    fetchImpl,
  });
  assert.equal(steady.action, 'skip');
  assert.equal(steady.reason, 'steady_green');
  const disabled = await runRemediationIntake({
    env: { REMEDIATION_INTAKE_DISABLED: '1', LINEAR_API_KEY: 'key' },
    eventName: 'workflow_run',
    event: mainRun('CI', 'failure'),
    fetchImpl,
  });
  assert.equal(disabled.action, 'disabled');
});

test('a red main CI check files remediation:red-checks on the LYB team', async () => {
  const store = linearStore();
  const { calls, fetchImpl } = store;
  const result = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'workflow_run',
    event: mainRun('CI', 'failure'),
    previous: '',
    fetchImpl,
  });
  assert.equal(result.ok, true);
  assert.equal(result.action, 'created');
  assert.equal(result.state, 'red');
  assert.equal(result.label, 'remediation:red-checks');
  assert.equal(calls[0].variables.key, 'LYB');
  const create = calls.find((body) => body.query.includes('CreateDedupedLinearIssue'));
  assert.equal(create.variables.teamId, 'lyb-team');
  assert.deepEqual(create.variables.labelIds.map((id) => [...store.labels.values()].find((node) => node.id === id).name),
    ['remediation:red-checks', 'remediation-origin:v1:jovieinc/logyourbody:168687833:100:1001:1']);
  assert.match(create.variables.description, /Source-workflow: CI/);
  assert.match(calls[1].variables.filter.labels.some.name.eq, /remediation:red-checks/);
});

test('a production smoke failure files web-deploy in Linear and later smoke recovery resolves it', async () => {
  const { runWebProductionSmoke } = await import('./web-production-smoke.mjs');
  const store = linearStore();
  const results = await runWebProductionSmoke({
    deploymentUrl: 'https://deployment.example.com', sleep: async () => {},
    fetchImpl: async (url) => {
      const path = new URL(url).pathname;
      if (path === '/api/waitlist') return Response.json({ success: true }, { status: 202 });
      const canonical = new URL(path === '/download/ios' ? '/' : path, logYourBody.links.home);
      const html = `<title>LogYourBody</title><link rel="canonical" href="${canonical.href}">`;
      return new Response(html, { status: path === '/support' ? 500 : 200 });
    },
  });
  assert.equal(results.filter((result) => !result.ok).length, 2);
  const conclusion = results.some((result) => !result.ok) ? 'failure' : 'success';
  const red = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' }, eventName: 'workflow_run',
    event: mainRun('Deploy', conclusion), fetchImpl: store.fetchImpl,
  });
  assert.equal(red.action, 'created');
  assert.equal(red.state, 'red');
  assert.equal(red.label, 'remediation:web-deploy');
  const create = store.calls.find((body) => body.query.includes('CreateDedupedLinearIssue'));
  assert.equal(create.variables.teamId, 'lyb-team');
  assert.match(create.variables.description, /Source-workflow: Deploy/);
  assert.match(create.variables.description, /actions\/runs\/1001/);

  const repeated = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' }, eventName: 'workflow_run', previous: 'red',
    event: mainRun('Deploy', 'failure', { id: 1002, run_number: 101 }), fetchImpl: store.fetchImpl,
  });
  assert.equal(repeated.action, 'updated');
  assert.equal(store.issues.length, 1, 'repeat smoke failures must deduplicate');
  const recovered = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' }, eventName: 'workflow_run', previous: 'red',
    event: mainRun('Deploy', 'success', { id: 1003, run_number: 102 }), fetchImpl: store.fetchImpl,
  });
  assert.equal(recovered.action, 'resolved');
  assert.equal(recovered.state, 'green');
});

test('the first green after red resolves and a Linear failure does not record state', async () => {
  const { fetchImpl } = linearStore([boundIssue('issue-1')]);
  const resolved = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'workflow_run',
    event: mainRun('CI', 'success'),
    previous: 'red',
    fetchImpl,
  });
  assert.equal(resolved.action, 'resolved');
  assert.equal(resolved.state, 'green');

  const down = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'schedule',
    event: {},
    previous: 'held',
    httpStatus: '500',
    fetchImpl: async () => jsonResponse({ errors: [{ message: 'down' }] }, false),
  });
  assert.equal(down.ok, false);
  assert.equal(down.state, null);
  assert.equal(down.fingerprint, 'synthetic-monitoring');
});

test('the homepage probe follows redirects and stops on the first 200', async () => {
  let init;
  const status = await requestHomepage(async (_url, options) => {
    init = options;
    return { status: 200 };
  });
  assert.equal(status, 200);
  assert.equal(init.redirect, 'follow');
  assert.equal(init.method, 'GET');
  const failed = await requestHomepage(async () => {
    throw new Error('network');
  });
  assert.equal(failed, 0);
});

test('a homepage blip does not file, and two confirmed reds do', async () => {
  let sleeps = 0;
  const recovered = await probeHomepage({
    request: (() => {
      const codes = [503, 503, 200];
      return async () => codes.shift();
    })(),
    sleep: async () => {
      sleeps += 1;
    },
  });
  assert.equal(recovered.action, 'green');
  assert.equal(recovered.attempts, 3);
  assert.equal(sleeps, 2);
  assert.equal(classifyProbeStatuses([500, 500, 500]).action, 'red');

  const fetchImpl = async () => {
    throw new Error('linear called');
  };
  const first = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'schedule',
    event: {},
    previous: '',
    httpStatus: '503',
    fetchImpl,
  });
  assert.equal(first.action, 'hold');
  assert.equal(first.state, 'held');
  assert.equal(applySyntheticGuard({ action: 'red', fingerprint: 'synthetic-monitoring' }, 'green').persist, 'held');

  const recoveredNight = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'schedule',
    event: {},
    previous: 'held',
    httpStatus: '200',
    fetchImpl,
  });
  assert.equal(recoveredNight.action, 'skip');
  assert.equal(recoveredNight.reason, 'recovered_before_filing');
  assert.equal(recoveredNight.state, 'green');

  const store = linearStore();
  const { calls } = store;
  const second = await runRemediationIntake({
    env: syntheticEnv,
    eventName: 'workflow_dispatch',
    event: {},
    previous: 'held',
    httpStatus: '503',
    fetchImpl: store.fetchImpl,
  });
  assert.equal(second.action, 'created');
  assert.equal(second.label, 'remediation:synthetic-monitoring');
  assert.match(calls.find((body) => body.query.includes('CreateDedupedLinearIssue')).variables.description, /two consecutive runs/);
  assert.equal(calls.length > 0, true);
});

function assertVisibleSkip(reason, detail) {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-skip-'));
  const summary = join(dir, 'summary.md');
  const warnings = [];
  const line = noteFilingSkipped(reason, {
    summaryPath: summary,
    warn: (message) => warnings.push(message),
  });
  const expected = `Remediation intake did NOT file: ${detail} (LYB-99)`;
  assert.equal(line, expected);
  assert.equal(skippedFilingMessage(reason), expected);
  assert.equal(warnings[0], `::warning::${expected}`);
  assert.equal(readFileSync(summary, 'utf8'), `${expected}\n`);
}

test('missing key, missing LYB team, and Linear API errors do not file', async () => {
  const missing = await runRemediationIntake({
    env: {},
    eventName: 'workflow_run',
    event: mainRun('CI', 'failure'),
    previous: '',
    fetchImpl: async () => {
      throw new Error('linear called');
    },
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, 'missing_linear_api_key');
  assert.equal(missing.state, null);
  assertVisibleSkip('missing_linear_api_key', 'LINEAR_API_KEY missing');

  const noTeam = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'workflow_run',
    event: mainRun('Deploy', 'failure'),
    previous: '',
    fetchImpl: async () => jsonResponse({ data: { teams: { nodes: [] } } }),
  });
  assert.equal(noTeam.ok, false);
  assert.equal(noTeam.reason, 'linear_team_missing');
  assert.equal(noTeam.state, null);
  assertVisibleSkip('linear_team_missing', 'LYB team not found');

  const apiDown = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'workflow_run',
    event: mainRun('CI', 'failure'),
    previous: 'red',
    fetchImpl: async () => jsonResponse({ errors: [{ message: 'down' }] }, false),
  });
  assert.equal(apiDown.ok, false);
  assert.equal(apiDown.state, null);
  assert.equal(apiDown.reason, 'linear_team_by_key_500');
  assertVisibleSkip('linear_team_by_key_500', 'Linear API error: linear_team_by_key_500');

  const graphqlDown = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'workflow_run',
    event: mainRun('CI', 'failure'),
    previous: '',
    fetchImpl: async () => jsonResponse({ errors: [{ message: 'down' }] }),
  });
  assert.equal(graphqlDown.ok, false);
  assert.equal(graphqlDown.reason, 'linear_team_by_key_graphql_error');
  assertVisibleSkip(
    'linear_team_by_key_graphql_error',
    'Linear API error: linear_team_by_key_graphql_error',
  );
});

test('a missing Linear key warns, records the summary, and exits 0', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-intake-'));
  const summary = join(dir, 'summary.md');
  const eventPath = join(dir, 'event.json');
  writeFileSync(eventPath, JSON.stringify(mainRun('CI', 'failure')));
  const intake = resolve(root, '.github/scripts/remediation-signal-intake.mjs');
  const result = spawnSync(process.execPath, [intake], {
    env: {
      ...process.env,
      LINEAR_API_KEY: '',
      GITHUB_EVENT_NAME: 'workflow_run',
      GITHUB_EVENT_PATH: eventPath,
      GITHUB_STEP_SUMMARY: summary,
      REMEDIATION_INTAKE_DISABLED: '',
    },
    encoding: 'utf8',
  });
  assert.equal(result.status, 0);
  const expected = 'Remediation intake did NOT file: LINEAR_API_KEY missing (LYB-99)';
  assert.match(result.stderr, new RegExp(`::warning::${expected.replace(/[()]/g, '\\$&')}`));
  assert.match(readFileSync(summary, 'utf8'), /Remediation intake did NOT file: LINEAR_API_KEY missing \(LYB-99\)/);
});

test('existing JOV callers keep the default team and the workflow stays off iOS', async () => {
  const calls = [];
  const fetchImpl = async (_url, init) => {
    const body = JSON.parse(init.body);
    calls.push(body);
    if (body.query.includes('FindRemediationIssue')) {
      return jsonResponse({
        data: {
          team: { states: { nodes: [{ id: 'todo', name: 'Todo', type: 'unstarted' }] }, labels: { nodes: [] } },
          issues: { nodes: [] },
        },
      });
    }
    if (body.query.includes('CreateDedupedLinearIssue')) {
      return jsonResponse({
        data: { issueCreate: { success: true, issue: { id: 'i', identifier: 'JOV-1', url: 'u' } } },
      });
    }
    return jsonResponse({}, false);
  };
  await upsertLinearIssue({
    fingerprint: 'remediation:asc-agreements',
    title: 'asc',
    description: 'd',
    apiKey: 'key',
    fetchImpl,
  });
  assert.equal(calls[0].variables.teamId, JOVIE_TEAM_ID);
  assert.equal(calls.at(-1).variables.teamId, JOVIE_TEAM_ID);

  const workflow = readFileSync(resolve(root, '.github/workflows/remediation-signal.yml'), 'utf8');
  assert.match(workflow, /workflows:\n\s+- CI\n\s+- Deploy\n/);
  assert.doesNotMatch(workflow, /- iOS/);
  assert.match(workflow, /no cron and no re-run/);
  assert.match(workflow, /REMEDIATION_INTAKE_DISABLED/);
  assert.doesNotMatch(workflow, /REMEDIATION_TRIGGERS_ENABLED/);
  assert.match(workflow, /remediation:synthetic-monitoring/);
  assert.match(workflow, /remediation-continuity-state-/);
  assert.match(workflow, /upload-artifact@v4/);
  assert.match(workflow, /retention-days: 90/);
  assert.doesNotMatch(workflow, /actions\/cache/);
});
