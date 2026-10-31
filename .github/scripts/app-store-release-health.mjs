import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { findTeamIdByKey, LYB_TEAM_KEY, upsertLinearIssue } from './lib/linear-issue-intake.mjs';

// Rates are fractions; maxRegression is 0.2 percentage points, not 0.2 percent.
export const POLICY = Object.freeze({
  users: 0.995,
  sessions: 0.995,
  maxRegression: 0.002,
  minUsers: 20,
  minSessions: 100,
  windowHours: 24,
});
const API = 'https://sentry.io/api/0/organizations/jovie/sessions/';
const PROJECT = 'log-your-body-ios';
const RELEASE = /^ios-\d+(?:\.\d+)+ \(\d+(?:\.\d+)*\)$/;

export function releaseName(version) {
  const name = `ios-${version?.version} (${version?.build})`;
  return RELEASE.test(name) ? name : null;
}

function metrics(body, release, start, end) {
  if (Date.parse(body?.start) !== Date.parse(start) || Date.parse(body?.end) !== Date.parse(end))
    throw new Error('Sentry returned a different observation window');
  if (
    !Array.isArray(body.groups) ||
    body.groups.length !== 1 ||
    body.groups[0]?.by?.release !== release
  )
    throw new Error('Missing or mismatched exact-build session data');
  const totals = body.groups[0].totals;
  const result = {
    release,
    users: totals?.['count_unique(user)'],
    sessions: totals?.['sum(session)'],
    crashFreeUsers: totals?.['crash_free_rate(user)'],
    crashFreeSessions: totals?.['crash_free_rate(session)'],
  };
  for (const key of ['users', 'sessions']) {
    if (!Number.isSafeInteger(result[key]) || result[key] < 0)
      throw new Error('Invalid session counts');
  }
  for (const key of ['crashFreeUsers', 'crashFreeSessions']) {
    if (
      typeof result[key] !== 'number' ||
      !Number.isFinite(result[key]) ||
      result[key] < 0 ||
      result[key] > 1
    )
      throw new Error('Missing or invalid crash-free rates');
  }
  if (result.users === 0 || result.sessions === 0 || result.users > result.sessions)
    throw new Error('No usable session population');
  return result;
}

export function evaluateHealth(current, previous, reasons = []) {
  const breaches = [];
  if (current) {
    for (const [field, threshold] of [
      ['crashFreeUsers', POLICY.users],
      ['crashFreeSessions', POLICY.sessions],
    ]) {
      if (current[field] < threshold)
        breaches.push(`${field} below ${(threshold * 100).toFixed(2)}%`);
      if (previous && previous[field] - current[field] > POLICY.maxRegression + 1e-12)
        breaches.push(`${field} regressed more than 0.20 percentage points`);
    }
  }
  const missing = [...reasons];
  for (const [label, sample] of [
    ['Candidate', current],
    ['Previous', previous],
  ]) {
    if (!sample) missing.push(`${label} health unavailable`);
    else if (sample.users < POLICY.minUsers || sample.sessions < POLICY.minSessions)
      missing.push(
        `${label} needs at least ${POLICY.minUsers} users and ${POLICY.minSessions} sessions`,
      );
  }
  // Known bad evidence wins even if another check is unavailable.
  return {
    status: breaches.length ? 'BREACHED' : missing.length ? 'UNVERIFIED' : 'HEALTHY',
    reasons: [...breaches, ...missing],
    current,
    previous,
    policy: POLICY,
  };
}

export async function checkHealth(
  input,
  { env = process.env, fetchImpl = fetch, now = Date.now() } = {},
) {
  const end = new Date(Math.floor(now / 3_600_000) * 3_600_000).toISOString();
  const start = new Date(Date.parse(end) - POLICY.windowHours * 3_600_000).toISOString();
  const reasons = [];
  const samples = await Promise.all(
    ['candidate', 'previous'].map(async (key) => {
      const release = releaseName(input[key]);
      if (!release || !env.SENTRY_AUTH_TOKEN) {
        reasons.push(
          `${key}: ${release ? 'SENTRY_AUTH_TOKEN missing' : 'ASC version/build unavailable'}`,
        );
        return null;
      }
      const url = new URL(API);
      for (const [name, value] of [
        ['project', PROJECT],
        ['environment', 'production'],
        ['query', `release:"${release}"`],
        ['groupBy', 'release'],
        ['interval', '1h'],
        ['start', start],
        ['end', end],
        ['includeSeries', '0'],
        ...[
          'sum(session)',
          'count_unique(user)',
          'crash_free_rate(user)',
          'crash_free_rate(session)',
        ].map((field) => ['field', field]),
      ])
        url.searchParams.append(name, value);
      try {
        const response = await fetchImpl(url, {
          headers: { Authorization: `Bearer ${env.SENTRY_AUTH_TOKEN}` },
          redirect: 'error',
          signal: AbortSignal.timeout(30_000),
        });
        if (response.status !== 200) throw new Error(`Sentry HTTP ${response.status}`);
        return metrics(await response.json(), release, start, end);
      } catch (error) {
        // Do not echo vendor bodies, credentials or network error details into public logs/issues.
        reasons.push(
          `${key}: ${/^Sentry HTTP \d+$/.test(error.message) ? error.message : 'Sentry health unreadable or incomplete'}`,
        );
        return null;
      }
    }),
  );
  return {
    ...evaluateHealth(...samples, reasons),
    candidate: input.candidate,
    window: { start, end },
  };
}

export function describeHealth(report) {
  const percent = (value) => `${(value * 100).toFixed(3)}%`;
  return [
    `Release health: **${report.status}**`,
    `Window: ${report.window?.start} to ${report.window?.end}; production, ${PROJECT}.`,
    'Policy: crash-free users and sessions >=99.50%; regression <=0.20 percentage points; >=20 users and >=100 sessions per version.',
    ...[
      ['Candidate', report.current],
      ['Previous', report.previous],
    ].map(([label, sample]) =>
      sample
        ? `${label}: \`${sample.release}\` — ${percent(sample.crashFreeUsers)} crash-free users (${sample.users} users), ${percent(sample.crashFreeSessions)} crash-free sessions (${sample.sessions} sessions).`
        : `${label}: UNVERIFIED (no usable exact-build health).`,
    ),
    ...report.reasons.map((reason) => `- ${reason}`),
  ].join('\n\n');
}

export async function fileRemediation(report, { env = process.env, fetchImpl = fetch } = {}) {
  if (!['BREACHED', 'UNVERIFIED'].includes(report.status)) return { ok: true, action: 'skip' };
  if (!env.LINEAR_API_KEY)
    return { ok: false, reason: 'LINEAR_API_KEY missing; remediation NOT filed' };
  const team = await findTeamIdByKey({
    teamKey: LYB_TEAM_KEY,
    apiKey: env.LINEAR_API_KEY,
    fetchImpl,
  });
  if (!team.ok) return team;
  const fingerprint = `remediation:app-store-health-${report.candidate.version}`;
  return upsertLinearIssue({
    teamId: team.id,
    apiKey: env.LINEAR_API_KEY,
    fetchImpl,
    label: fingerprint,
    title: `App Store ${report.candidate.version} release health (${fingerprint})`,
    description: [
      describeHealth(report),
      `Action: ${report.action}`,
      'Investigate Sentry crashes/telemetry, ship a qualified fix, and review health before manually resuming in App Store Connect. The monitor never resumes a paused release.',
      `Run: https://github.com/${env.GITHUB_REPOSITORY}/actions/runs/${env.GITHUB_RUN_ID}`,
    ].join('\n\n'),
    priority: report.status === 'BREACHED' ? 1 : 2,
    createStateName: 'Todo',
    reopenTerminal: true,
  });
}

async function main() {
  const input = JSON.parse(readFileSync(0, 'utf8'));
  if (process.argv[2] === '--remediate') {
    const result = await fileRemediation(input);
    console.log(
      JSON.stringify({
        ok: result.ok,
        action: result.action,
        identifier: result.identifier,
        reason: result.ok
          ? undefined
          : 'Linear remediation NOT filed; inspect credentials and intake availability',
      }),
    );
  } else {
    const report = await checkHealth(input);
    console.log(JSON.stringify({ ...report, summary: describeHealth(report) }));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    console.error('Release health helper failed; result is UNVERIFIED');
    process.exitCode = 1;
  });
}
