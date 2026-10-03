import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { JOVIE_TEAM_ID, remediationKey, upsertLinearIssue } from './lib/linear-issue-intake.mjs';
import {
  decideHttpStatus,
  decideMonitorSignal,
  detectorFromGithubEvent,
  gateSteadyGreen,
  remediationIntakeDisabled,
  runRemediationIntake,
} from './remediation-signal.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');

const mainRun = (name, conclusion) => ({
  workflow_run: {
    name,
    head_branch: 'main',
    event: 'push',
    conclusion,
    html_url: `https://github.com/JovieInc/LogYourBody/actions/runs/${name}`,
  },
});

function jsonResponse(payload, ok = true) {
  return { ok, status: ok ? 200 : 500, text: async () => JSON.stringify(payload) };
}

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
  const calls = [];
  const fetchImpl = async (_url, init) => {
    const body = JSON.parse(init.body);
    calls.push(body);
    if (body.query.includes('TeamByKey')) {
      return jsonResponse({ data: { teams: { nodes: [{ id: 'lyb-team', key: 'LYB' }] } } });
    }
    if (body.query.includes('FindRemediationIssue')) {
      return jsonResponse({
        data: {
          team: {
            states: { nodes: [{ id: 'todo', name: 'Todo', type: 'unstarted' }] },
            labels: { nodes: [] },
          },
          issues: { nodes: [] },
        },
      });
    }
    if (body.query.includes('CreateTeamLabel')) {
      return jsonResponse({ data: { issueLabelCreate: { success: true, issueLabel: { id: 'label-red' } } } });
    }
    if (body.query.includes('CreateDedupedLinearIssue')) {
      return jsonResponse({
        data: { issueCreate: { success: true, issue: { id: 'issue-1', identifier: 'LYB-1', url: 'https://example.com/issue-1' } } },
      });
    }
    return jsonResponse({ errors: [{ message: 'unexpected' }] }, false);
  };
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
  assert.equal(calls.at(-1).variables.teamId, 'lyb-team');
  assert.deepEqual(calls.at(-1).variables.labelIds, ['label-red']);
  assert.match(calls.at(-1).variables.description, /Source-workflow: CI/);
  assert.match(calls[1].variables.filter.labels.some.name.eq, /remediation:red-checks/);
});

test('the first green after red resolves and a Linear failure does not record state', async () => {
  const fetchImpl = async (_url, init) => {
    const body = JSON.parse(init.body);
    if (body.query.includes('TeamByKey')) {
      return jsonResponse({ data: { teams: { nodes: [{ id: 'lyb-team', key: 'LYB' }] } } });
    }
    if (body.query.includes('FindRemediationForGreen')) {
      return jsonResponse({
        data: {
          team: { states: { nodes: [{ id: 'done', name: 'Done', type: 'completed' }] } },
          issues: {
            nodes: [
              {
                id: 'issue-1',
                identifier: 'LYB-1',
                description: 'Source-workflow: CI\nred',
                state: { type: 'unstarted' },
                labels: { nodes: [{ name: 'remediation:red-checks' }] },
              },
            ],
          },
        },
      });
    }
    if (body.query.includes('commentCreate')) {
      return jsonResponse({ data: { commentCreate: { success: true, comment: { id: 'c1' } } } });
    }
    if (body.query.includes('ResolveRemediation')) {
      return jsonResponse({
        data: { issueUpdate: { success: true, issue: { id: 'issue-1', identifier: 'LYB-1', url: 'https://example.com/issue-1' } } },
      });
    }
    return jsonResponse({}, false);
  };
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
    previous: '',
    httpStatus: '500',
    fetchImpl: async () => jsonResponse({ errors: [{ message: 'down' }] }, false),
  });
  assert.equal(down.ok, false);
  assert.equal(down.state, null);
  assert.equal(down.fingerprint, 'synthetic-monitoring');
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
});
