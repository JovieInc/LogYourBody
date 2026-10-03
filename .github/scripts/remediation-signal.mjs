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

export const HOMEPAGE_PROBE_ATTEMPTS = 3;
export const HOMEPAGE_PROBE_BACKOFF_MS = [0, 2_000, 5_000];
export const HOMEPAGE_URL = 'https://logyourbody.com';

export function classifyProbeStatuses(statuses) {
  const codes = (Array.isArray(statuses) ? statuses : []).map((status) => Number(status));
  if (codes.some((code) => code === 200)) return { action: 'green', attempts: codes.length };
  const last = codes.at(-1);
  const shown = Number.isFinite(last) ? last : 0;
  return {
    action: 'red',
    attempts: codes.length,
    detail: `${HOMEPAGE_URL} returned HTTP ${shown} on ${codes.length} attempts`,
  };
}

/** Stop on the first 200. A single blip that recovers inside the run is green. */
export async function probeHomepage({
  attempts = HOMEPAGE_PROBE_ATTEMPTS,
  backoffMs = HOMEPAGE_PROBE_BACKOFF_MS,
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  request,
} = {}) {
  const statuses = [];
  const limit = Math.max(1, attempts);
  for (let index = 0; index < limit; index += 1) {
    const wait = backoffMs[index] ?? 0;
    if (index > 0 && wait > 0) await sleep(wait);
    statuses.push(await request());
    if (Number(statuses.at(-1)) === 200) break;
  }
  return classifyProbeStatuses(statuses);
}

/** Follow redirects. Apex 307s to www; a final 200 is up. */
export async function requestHomepage(fetchImpl = fetch) {
  try {
    const response = await fetchImpl(HOMEPAGE_URL, {
      method: 'GET',
      redirect: 'follow',
      signal: AbortSignal.timeout(20_000),
    });
    return response.status;
  } catch {
    return 0;
  }
}

/**
 * Homepage filing waits for two consecutive confirmed reds.
 * `held` is a red that did not file. Recovery from `held` does not call Linear.
 */
export function applySyntheticGuard(decision, previous) {
  if (decision?.fingerprint !== 'synthetic-monitoring') return { decision, persist: null };
  if (decision.action === 'red' && previous !== 'red' && previous !== 'held') {
    return {
      decision: { action: 'hold', reason: 'need_second_red', fingerprint: decision.fingerprint },
      persist: 'held',
    };
  }
  if (decision.action === 'green' && previous === 'held') {
    return {
      decision: { action: 'skip', reason: 'recovered_before_filing', fingerprint: decision.fingerprint },
      persist: 'green',
    };
  }
  if (decision.action === 'red') {
    return {
      decision: {
        ...decision,
        detail: `${decision.detail || 'Homepage probe failed.'} Confirmed on two consecutive runs.`,
      },
      persist: null,
    };
  }
  return { decision, persist: null };
}

export function skippedFilingMessage(reason) {
  const detail = reason === 'missing_linear_api_key' ? 'LINEAR_API_KEY is missing' : reason || 'linear_error';
  return `Filing was SKIPPED (${detail}).`;
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
  request = null,
  sleep,
}) {
  if (remediationIntakeDisabled(env)) return { ok: true, action: 'disabled', state: null };
  const detector = detectorFromGithubEvent(eventName, event);
  if (!detector) return { ok: true, action: 'skip', reason: 'no_detector', state: null };
  let decision;
  if (detector.mode === 'http') {
    const probed =
      httpStatus === null || httpStatus === undefined || httpStatus === ''
        ? await probeHomepage({ request: request ?? (() => requestHomepage(fetchImpl)), sleep })
        : decideHttpStatus(httpStatus);
    decision = { ...probed, fingerprint: detector.fingerprint };
  } else {
    decision = { ...decideMonitorSignal({ conclusion: detector.conclusion }), fingerprint: detector.fingerprint };
  }
  const guarded = applySyntheticGuard(decision, previous);
  if (guarded.persist) {
    return {
      ok: true,
      action: guarded.decision.action,
      reason: guarded.decision.reason,
      fingerprint: detector.fingerprint,
      state: guarded.persist,
    };
  }
  decision = guarded.decision;
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
