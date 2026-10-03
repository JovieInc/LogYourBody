// Symphony router intake for non-iOS signals (JOV-7540 / LYB-94).
// Filing is on unless REMEDIATION_INTAKE_DISABLED=1. Steady greens do not
// call Linear. Linear errors are returned to the caller, which fails open.

import {
  findTeamIdByKey,
  LYB_TEAM_KEY,
  noteFingerprintedIssueGreen,
  remediationKey,
  upsertLinearIssue,
} from './lib/linear-issue-intake.mjs';

export { remediationKey };

const GREEN_MARKER = '<!-- remediation-green -->';

export function remediationIntakeDisabled(env = process.env) {
  return env.REMEDIATION_INTAKE_DISABLED === '1';
}

export function remediationTitle(fingerprint) {
  return `P0: ${fingerprint} is red (${fingerprint})`;
}

export function describeRemediation({ fingerprint, source, runUrl, detail }) {
  return [
    `Source-workflow: ${source}`,
    '',
    '## Evidence',
    detail?.trim() || 'Red run. See the linked workflow for logs.',
    '',
    '## Run',
    runUrl || '(run url unavailable)',
    '',
    `Label: ${remediationKey(fingerprint)}`,
    'Router: JOV-7540',
  ].join('\n');
}

export function decideMonitorSignal({ conclusion }) {
  if (conclusion === 'success') return { action: 'green' };
  if (conclusion === 'failure' || conclusion === 'cancelled') return { action: 'red' };
  return { action: 'skip' };
}

/** Anything other than HTTP 200 is red, matching the web release health check. */
export function decideHttpStatus(status) {
  const code = Number(status);
  if (code === 200) return { action: 'green' };
  const shown = Number.isFinite(code) ? code : 0;
  return { action: 'red', detail: `https://logyourbody.com returned HTTP ${shown}` };
}

/** Steady green skips Linear. The first green after a recorded red still resolves. */
export function gateSteadyGreen(decision, previous) {
  if (decision?.action !== 'green') return decision;
  if (previous === 'red') return decision;
  return { action: 'skip', reason: 'steady_green' };
}

export function detectorFromGithubEvent(eventName, event = {}) {
  if (eventName === 'schedule' || eventName === 'workflow_dispatch') {
    return {
      mode: 'http',
      fingerprint: 'synthetic-monitoring',
      source: 'remediation-signal.yml:synthetic',
    };
  }
  if (eventName !== 'workflow_run') return null;
  const run = event.workflow_run ?? {};
  if (run.head_branch !== 'main' || run.event !== 'push') return null;
  if (run.name === 'CI') {
    return { mode: 'monitor', fingerprint: 'red-checks', source: 'CI', conclusion: run.conclusion, runUrl: run.html_url };
  }
  if (run.name === 'Deploy') {
    return {
      mode: 'monitor',
      fingerprint: 'web-deploy',
      source: 'Deploy',
      conclusion: run.conclusion,
      runUrl: run.html_url,
    };
  }
  return null;
}

export async function applyRemediationDecision(
  decision,
  { source, runUrl, detail, apiKey, fetchImpl } = {},
) {
  if (!decision || decision.action === 'skip') return { ok: true, action: 'skip' };
  const team = await findTeamIdByKey({ teamKey: LYB_TEAM_KEY, apiKey, fetchImpl });
  if (!team.ok) return team;
  const fingerprint = decision.fingerprint;
  if (decision.action === 'red') {
    const filed = await upsertLinearIssue({
      label: remediationKey(fingerprint),
      title: remediationTitle(fingerprint),
      description: describeRemediation({
        fingerprint,
        source,
        runUrl,
        detail: decision.detail || detail,
      }),
      priority: 1,
      createStateName: 'Todo',
      reopenTerminal: true,
      teamId: team.id,
      apiKey,
      fetchImpl,
    });
    return { ...filed, fingerprint, label: remediationKey(fingerprint) };
  }
  const resolved = await noteFingerprintedIssueGreen({
    fingerprint,
    source,
    comment: `${GREEN_MARKER}\nSource-workflow: ${source} is green.\nRun: ${runUrl || '(run url unavailable)'}`,
    teamId: team.id,
    apiKey,
    fetchImpl,
  });
  return { ...resolved, fingerprint, label: remediationKey(fingerprint) };
}

export async function runRemediationIntake({
  env = process.env,
  eventName,
  event = {},
  previous = '',
  httpStatus = null,
  fetchImpl = fetch,
}) {
  if (remediationIntakeDisabled(env)) return { ok: true, action: 'disabled', state: null };
  const detector = detectorFromGithubEvent(eventName, event);
  if (!detector) return { ok: true, action: 'skip', reason: 'no_detector', state: null };
  const decision =
    detector.mode === 'http'
      ? { ...decideHttpStatus(httpStatus), fingerprint: detector.fingerprint }
      : { ...decideMonitorSignal({ conclusion: detector.conclusion }), fingerprint: detector.fingerprint };
  const gated = gateSteadyGreen(decision, previous);
  if (gated.action === 'skip') {
    return { ok: true, action: 'skip', reason: gated.reason || 'skip', fingerprint: detector.fingerprint, state: null };
  }
  const applied = await applyRemediationDecision(
    { ...gated, fingerprint: detector.fingerprint },
    {
      source: detector.source,
      runUrl: detector.runUrl || env.REMEDIATION_RUN_URL,
      detail: gated.detail,
      apiKey: env.LINEAR_API_KEY,
      fetchImpl,
    },
  );
  return {
    ...applied,
    fingerprint: detector.fingerprint,
    state: applied.ok ? gated.action : null,
  };
}
