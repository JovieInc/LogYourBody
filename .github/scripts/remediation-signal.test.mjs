import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { JOVIE_TEAM_ID, remediationKey, upsertLinearIssue } from './lib/linear-issue-intake.mjs';
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
} from './remediation-signal.mjs';
import { noteFilingSkipped } from './remediation-signal-intake.mjs';

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

  const calls = [];
  const second = await runRemediationIntake({
    env: { LINEAR_API_KEY: 'key' },
    eventName: 'workflow_dispatch',
    event: {},
    previous: 'held',
    httpStatus: '503',
    fetchImpl: async (_url, init) => {
      const body = JSON.parse(init.body);
      calls.push(body);
      if (body.query.includes('TeamByKey')) {
        return jsonResponse({ data: { teams: { nodes: [{ id: 'lyb-team', key: 'LYB' }] } } });
      }
      if (body.query.includes('FindRemediationIssue')) {
        return jsonResponse({
          data: {
            team: { states: { nodes: [{ id: 'todo', name: 'Todo', type: 'unstarted' }] }, labels: { nodes: [] } },
            issues: { nodes: [] },
          },
        });
      }
      if (body.query.includes('CreateTeamLabel')) {
        return jsonResponse({ data: { issueLabelCreate: { success: true, issueLabel: { id: 'label-syn' } } } });
      }
      if (body.query.includes('CreateDedupedLinearIssue')) {
        return jsonResponse({
          data: { issueCreate: { success: true, issue: { id: 'issue-2', identifier: 'LYB-2', url: 'https://example.com/issue-2' } } },
        });
      }
      return jsonResponse({}, false);
    },
  });
  assert.equal(second.action, 'created');
  assert.equal(second.label, 'remediation:synthetic-monitoring');
  assert.match(calls.at(-1).variables.description, /two consecutive runs/);
  assert.equal(calls.length > 0, true);
});

test('a missing Linear key is a visible skip', () => {
  const dir = mkdtempSync(join(tmpdir(), 'lyb-skip-'));
  const summary = join(dir, 'summary.md');
  const warnings = [];
  const line = noteFilingSkipped('missing_linear_api_key', {
    summaryPath: summary,
    warn: (message) => warnings.push(message),
  });
  assert.match(line, /Filing was SKIPPED/);
  assert.match(warnings[0], /::warning::Filing was SKIPPED \(LINEAR_API_KEY is missing\)/);
  assert.match(readFileSync(summary, 'utf8'), /Filing was SKIPPED/);
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
