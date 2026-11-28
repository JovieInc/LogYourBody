import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { logYourBody } from '../../packages/product-registry/src/products/logyourbody.mjs';
import { linearGraphql, LYB_TEAM_KEY } from './lib/linear-issue-intake.mjs';

const www = new URL(logYourBody.links.home);
const apex = new URL(`https://${logYourBody.identity.domain}/`);
const redirectStatuses = new Set([301, 302, 303, 307, 308]);
const failureClasses = [
  'deployment-paused',
  'http-503',
  'http-status',
  'redirect-loop',
  'redirect-contract',
  'transport',
];
const receipt = /^<!-- lyb-386-uptime: (pending|sending|sent|recovered) -->$/m;
const pacificTime = new Intl.DateTimeFormat('en-US', {
  dateStyle: 'medium',
  timeStyle: 'long',
  timeZone: 'America/Los_Angeles',
});

async function requestHomepage(url, fetchImpl) {
  try {
    const response = await fetchImpl(url.href, {
      method: 'GET',
      redirect: 'manual',
      cache: 'no-store',
      signal: AbortSignal.timeout(5_000),
    });
    await response.body?.cancel().catch(() => {});
    const location = response.headers.get('location');
    return {
      status: response.status,
      paused: response.headers.get('x-vercel-error')?.trim().toUpperCase() === 'DEPLOYMENT_PAUSED',
      target:
        location && redirectStatuses.has(response.status) ? URL.parse(location, url)?.href : null,
    };
  } catch {
    return null;
  }
}

function checkHomepage(url, response, otherUrl, otherResponse) {
  const hostname = url.hostname;
  const failed = (kind, detail) => ({ hostname, kind, detail });
  if (!response) return failed('transport', 'GET failed or timed out');
  const { status, paused, target } = response;
  if (paused) return failed('deployment-paused', `HTTP ${status}, Vercel DEPLOYMENT_PAUSED`);
  if (status === 503) return failed('http-503', 'HTTP 503');
  if (
    target === url.href ||
    (url === www && target === otherUrl.href && otherResponse?.target === url.href)
  ) {
    return failed('redirect-loop', `HTTP ${status}, redirect loop`);
  }
  if (url === www && status !== 200)
    return failed('http-status', `Expected HTTP 200, got ${status}`);
  if (url === apex && ((status !== 301 && status !== 308) || target !== www.href)) {
    return failed(
      'redirect-contract',
      `Expected HTTP 301/308 directly to ${www.href}, got ${status}`,
    );
  }
  return { hostname, kind: null };
}

export async function probeHomepages(fetchImpl) {
  const [wwwResponse, apexResponse] = await Promise.all([
    requestHomepage(www, fetchImpl),
    requestHomepage(apex, fetchImpl),
  ]);
  return [
    checkHomepage(www, wwwResponse, apex, apexResponse),
    checkHomepage(apex, apexResponse, www, wwwResponse),
  ];
}

// Use the same caller-supplied UUID format as Linear correction intake.
// The hostname and failure class keep the ID stable across runner restarts.
function incidentId(hostname, kind) {
  const bytes = createHash('sha256')
    .update(`JovieInc/LogYourBody/LYB-386/${hostname}/${kind}`)
    .digest();
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.subarray(0, 16).toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function incidentKeys(hostname) {
  return failureClasses.map((kind) => ({ id: incidentId(hostname, kind), kind }));
}

function createLinearIntake(apiKey, fetchImpl) {
  async function request(operation, query, variables) {
    const result = await linearGraphql({ query, variables, apiKey, fetchImpl }, operation);
    if (!result.ok || !result.data) throw new Error(result.reason ?? `${operation}_missing_data`);
    return result.data;
  }

  return {
    async load(ids) {
      const data = await request(
        'uptime_linear_lookup',
        `
        query FindUptimeIncidents($ids: [String!]!, $teamKey: String!) {
          teams(filter: { key: { eq: $teamKey } }) { nodes { id states { nodes { id type } } } }
          issues(first: 25, includeArchived: true, filter: { id: { in: $ids } }) {
            nodes { id identifier url description archivedAt team { id } }
          }
        }
      `,
        { ids, teamKey: LYB_TEAM_KEY },
      );
      const team = data.teams?.nodes?.[0];
      const openState = team?.states.nodes.find(({ type }) => type === 'unstarted');
      const doneState = team?.states.nodes.find(({ type }) => type === 'completed');
      if (!team || !openState || !doneState || !Array.isArray(data.issues?.nodes)) {
        throw new Error('uptime_linear_team_or_states_missing');
      }
      return {
        teamId: team.id,
        openStateId: openState.id,
        doneStateId: doneState.id,
        issues: new Map(data.issues.nodes.map((issue) => [issue.id, issue])),
      };
    },
    async create(input) {
      const data = await request(
        'uptime_linear_create',
        `
        mutation CreateUptimeIncident($input: IssueCreateInput!) {
          issueCreate(input: $input) { success issue { id identifier url description } }
        }
      `,
        { input },
      );
      const issue = data.issueCreate?.issue;
      if (!data.issueCreate?.success || issue?.id !== input.id)
        throw new Error('uptime_linear_create_unconfirmed');
      return issue;
    },
    async update(id, input) {
      const data = await request(
        'uptime_linear_update',
        `
        mutation UpdateUptimeIncident($id: String!, $input: IssueUpdateInput!) {
          issueUpdate(id: $id, input: $input) { success issue { id identifier url description } }
        }
      `,
        { id, input },
      );
      const issue = data.issueUpdate?.issue;
      if (!data.issueUpdate?.success || issue?.id !== id)
        throw new Error('uptime_linear_update_unconfirmed');
      return issue;
    },
  };
}

async function notifyFailure(linear, issue, signal, webhook, fetchImpl) {
  if (!webhook) throw new Error('uptime_slack_webhook_missing');
  const setDelivery = (state) =>
    linear.update(issue.id, {
      description: issue.description.replace(receipt, `<!-- lyb-386-uptime: ${state} -->`),
    });
  // Slack incoming webhooks have no idempotency key. Persist the claim before
  // posting so an ambiguous timeout or a runner crash cannot double-page.
  await setDelivery('sending');
  const response = await fetchImpl(webhook, {
    method: 'POST',
    redirect: 'error',
    signal: AbortSignal.timeout(5_000),
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      text: `LYB uptime: ${signal.hostname} (${signal.kind}). ${signal.detail}. ${issue.identifier} ${issue.url}`,
      mrkdwn: false,
      unfurl_links: false,
      unfurl_media: false,
    }),
  }).catch(() => null);
  if (response?.status === 200 && (await response.text().catch(() => '')) === 'ok') {
    await setDelivery('sent');
    return;
  }
  if (response && response.status >= 400 && response.status < 500 && response.status !== 408) {
    await setDelivery('pending');
    throw new Error(`uptime_slack_rejected_${response.status}`);
  }
  throw new Error('uptime_slack_delivery_uncertain');
}

async function reconcileIncident({ key, signal, state, linear, checkedAt, webhook, fetchImpl }) {
  const { id, kind } = key;
  let issue = state.issues.get(id);
  let delivery = issue?.description?.match(receipt)?.[1];
  if (issue && (issue.team.id !== state.teamId || !delivery))
    throw new Error('uptime_linear_receipt_invalid');

  if (!signal.kind && issue && delivery !== 'recovered') {
    await linear.update(id, {
      stateId: state.doneStateId,
      description: `${issue.description.replace(receipt, '<!-- lyb-386-uptime: recovered -->')}

Recovered at ${checkedAt}. The hostname met its uptime contract. Slack delivery: ${delivery}.`,
    });
    if (delivery !== 'sent')
      throw new Error(`uptime_recovered_without_confirmed_slack_${delivery}`);
    return { action: 'recovered', id, issue: issue.identifier };
  }
  if (signal.kind !== kind) return null;
  if (issue?.archivedAt) throw new Error('uptime_linear_incident_archived');

  if (!issue || delivery === 'recovered') {
    const evidence = `Unhealthy at ${checkedAt}. ${signal.detail}.`;
    const marker = '<!-- lyb-386-uptime: pending -->';
    issue = issue
      ? await linear.update(id, {
          stateId: state.openStateId,
          description: `${issue.description.replace(receipt, marker)}\n\n${evidence}`,
        })
      : await linear.create({
          id,
          teamId: state.teamId,
          stateId: state.openStateId,
          priority: 2,
          title: `Public uptime: ${signal.hostname} (${kind})`,
          description: `${marker}\n\n${evidence}\n\nProbe definition and drill: LYB-386.`,
        });
    delivery = 'pending';
  }
  if (delivery === 'sending') throw new Error('uptime_slack_delivery_uncertain');
  if (delivery === 'sent') return { action: 'already-alerted', id, issue: issue.identifier };
  await notifyFailure(linear, issue, signal, webhook, fetchImpl);
  return { action: 'alerted', id, issue: issue.identifier };
}

export async function runUptimeProbe({ apiKey, webhook, fetchImpl, now = new Date() }) {
  if (!apiKey) throw new Error('uptime_linear_api_key_missing');
  const signals = await probeHomepages(fetchImpl);
  const checks = signals.flatMap((signal) =>
    incidentKeys(signal.hostname).map((key) => ({ signal, key })),
  );
  const linear = createLinearIntake(apiKey, fetchImpl);
  const state = await linear.load(checks.map(({ key }) => key.id));
  const checkedAt = pacificTime.format(now);
  const results = [];
  const errors = [];
  for (const { key, signal } of checks) {
    try {
      const result = await reconcileIncident({
        key,
        signal,
        state,
        linear,
        checkedAt,
        webhook,
        fetchImpl,
      });
      if (result) results.push({ hostname: signal.hostname, kind: key.kind, ...result });
    } catch (error) {
      errors.push({ hostname: signal.hostname, kind: key.kind, reason: error.message });
    }
  }
  return { checkedAt, signals, results, errors };
}

const liveWorkflowRef =
  'JovieInc/LogYourBody/.github/workflows/lyb-386-uptime-probe.yml@refs/heads/main';

export function liveProbeEnabled(env) {
  return (
    env.GITHUB_ACTIONS === 'true' &&
    env.GITHUB_WORKFLOW_REF === liveWorkflowRef &&
    env.LYB_UPTIME_PROBE_ENABLED === 'true'
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!liveProbeEnabled(process.env)) {
    console.error(
      'LYB uptime live execution requires the enabled Symphony workflow on main. Use the fixture tests for drills.',
    );
    process.exitCode = 1;
  } else {
    try {
      const result = await runUptimeProbe({
        apiKey: process.env.LINEAR_API_KEY,
        webhook: process.env.SLACK_WEBHOOK_URL,
        fetchImpl: fetch,
      });
      console.log(JSON.stringify(result, null, 2));
      if (result.errors.length) process.exitCode = 1;
    } catch {
      console.error('LYB uptime probe could not load Linear incident state.');
      process.exitCode = 1;
    }
  }
}
