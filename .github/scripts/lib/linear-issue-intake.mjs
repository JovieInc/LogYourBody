// Vendored from JovieInc/Jovie scripts/lib/linear-issue-intake.mjs.
// One upsert helper for the remediation jobs: match an existing issue by
// title fingerprint or by label, then create or update it. Comment helpers
// sit next to it. Existing callers stay on the JOV team. Symphony intake
// passes the LYB team id from findTeamIdByKey.

const LINEAR_API = 'https://api.linear.app/graphql';
const LINEAR_REQUEST_TIMEOUT_MS = 15_000;
export const JOVIE_TEAM_ID = 'bdc09edc-f91c-4a06-b308-74b4fcf093f8';
export const LYB_TEAM_KEY = 'LYB';

const PROVENANCE_KINDS = ['origin', 'red', 'green'];
const POSITIVE_INTEGER = /^[1-9][0-9]*$/;

/** Stable event identity; display names and issue descriptions are not authority. */
export function normalizeRemediationProvenance(value) {
  if (!value || typeof value !== 'object') return null;
  const repository = typeof value.repository === 'string' ? value.repository.toLowerCase() : '';
  const workflowId = typeof value.workflowId === 'number' && !Number.isSafeInteger(value.workflowId)
    ? '' : String(value.workflowId ?? '');
  const numbers = [value.runNumber, value.runId, value.runAttempt].map((part) =>
    typeof part === 'number' && !Number.isSafeInteger(part) ? '' : String(part ?? ''),
  );
  if (!/^[a-z0-9_.-]+\/[a-z0-9_.-]+$/.test(repository) ||
      !/^(?:[1-9][0-9]*|synthetic)$/.test(workflowId) ||
      numbers.some((part) => !POSITIVE_INTEGER.test(part))) return null;
  return { repository, workflowId, runNumber: numbers[0], runId: numbers[1], runAttempt: numbers[2] };
}

/** Origin is applied atomically at creation and never rewritten or removed.
 * Red/recovery labels are append-only ordering receipts applied with state updates. */
export function remediationProvenanceLabel(value, kind = 'origin') {
  const provenance = normalizeRemediationProvenance(value);
  if (!provenance || !PROVENANCE_KINDS.includes(kind)) return null;
  return 'remediation-' + kind + ':v1:' + [
    provenance.repository, provenance.workflowId, provenance.runNumber,
    provenance.runId, provenance.runAttempt,
  ].join(':');
}

function parseProvenanceLabel(name) {
  const match = /^remediation-(origin|red|green):v1:([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$/.exec(name);
  if (!match) return null;
  const provenance = normalizeRemediationProvenance({
    repository: match[2], workflowId: match[3], runNumber: match[4],
    runId: match[5], runAttempt: match[6],
  });
  if (!provenance || remediationProvenanceLabel(provenance, match[1]) !== name) return null;
  return { ...provenance, kind: match[1] };
}

function sameSource(left, right) {
  return left.repository === right.repository && left.workflowId === right.workflowId;
}

function compareRuns(left, right) {
  for (const key of ['runNumber', 'runAttempt']) {
    if (BigInt(left[key]) < BigInt(right[key])) return -1;
    if (BigInt(left[key]) > BigInt(right[key])) return 1;
  }
  return 0;
}

function issueProvenance(issue) {
  if (issue?.labels?.pageInfo?.hasNextPage !== false) return null;
  const names = (issue.labels.nodes ?? []).map((label) => label?.name ?? '');
  const relevant = names.filter((name) => /^remediation-(origin|red|green):/.test(name));
  const records = relevant.map(parseProvenanceLabel);
  if (records.some((record) => !record)) return null;
  const origins = records.filter((record) => record.kind === 'origin');
  if (origins.length !== 1) return null;
  const origin = origins[0];
  const runIds = new Map();
  for (const record of records) {
    if (!sameSource(origin, record) || compareRuns(record, origin) < 0) return null;
    const known = runIds.get(record.runNumber);
    if (known && known !== record.runId) return null;
    runIds.set(record.runNumber, record.runId);
  }
  const latest = (kind) => records.filter((record) => record.kind === kind)
    .reduce((current, record) => !current || compareRuns(record, current) > 0 ? record : current, null);
  return { origin, records, red: latest('red') ?? origin, green: latest('green') };
}

function compatibleIssue(issue, provenance) {
  const binding = issueProvenance(issue);
  return binding && sameSource(binding.origin, provenance);
}

function selectBoundIssue(matches) {
  return matches.find((node) => !['completed', 'canceled'].includes(node.state?.type)) ??
    matches.find((node) => node.state?.type === 'completed') ?? matches[0] ?? null;
}

function signalAdmission(issue, provenance, action) {
  const binding = issueProvenance(issue);
  if (!binding || !sameSource(binding.origin, provenance)) {
    return { ok: false, reason: 'source_provenance_mismatch', action: 'source_mismatch' };
  }
  if (binding.records.some((record) =>
    record.runNumber === provenance.runNumber && record.runId !== provenance.runId)) {
    return { ok: false, reason: 'source_run_conflict', action: 'source_mismatch' };
  }
  const terminal = ['completed', 'canceled'].includes(issue.state?.type);
  const stale = action === 'green'
    ? compareRuns(provenance, binding.red) <= 0 ||
      (binding.green && compareRuns(provenance, binding.green) < 0)
    : compareRuns(provenance, binding.red) < 0 ||
      (binding.green && compareRuns(provenance, binding.green) <= 0) ||
      (terminal && compareRuns(provenance, binding.red) === 0);
  if (stale) return { ok: true, action: 'stale_signal' };
  if (issue.state?.type === 'canceled') return { ok: true, action: 'canceled_duplicate' };
  return null;
}

function provenanceLookupComplete(found) {
  return Array.isArray(found.data?.issues?.nodes) &&
    found.data.issues.pageInfo?.hasNextPage === false;
}

// Append-only receipts must remain readable after the first label page fills.
// Missing/repeated cursors or failed pages are uncertainty, never authority.
async function completeIssueLabels(issue, request) {
  let connection = issue?.labels;
  if (!Array.isArray(connection?.nodes) || typeof connection.pageInfo?.hasNextPage !== 'boolean') {
    return { ok: false, reason: 'source_provenance_inventory_incomplete' };
  }
  const nodes = [...connection.nodes];
  const cursors = new Set();
  while (connection.pageInfo.hasNextPage) {
    const after = connection.pageInfo.endCursor;
    if (!after || cursors.has(after)) return { ok: false, reason: 'source_provenance_inventory_incomplete' };
    cursors.add(after);
    const page = await linearGraphql({ ...request, query: `
      query RemediationIssueLabels($id: String!, $after: String!) {
        issue(id: $id) {
          id
          labels(first: 100, after: $after) {
            nodes { id name }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    `, variables: { id: issue.id, after } }, 'linear_provenance_labels');
    if (!page.ok) return page;
    connection = page.data?.issue?.labels;
    if (page.data?.issue?.id !== issue.id || !Array.isArray(connection?.nodes) ||
        typeof connection.pageInfo?.hasNextPage !== 'boolean') {
      return { ok: false, reason: 'source_provenance_inventory_incomplete' };
    }
    nodes.push(...connection.nodes);
  }
  return { ok: true, issue: { ...issue, labels: {
    nodes: [...new Map(nodes.map((node) => [node.id ?? node.name, node])).values()],
    pageInfo: { hasNextPage: false },
  } } };
}

async function hydrateProvenanceIssues(found, request) {
  if (!provenanceLookupComplete(found)) {
    return { ok: false, reason: 'source_provenance_inventory_incomplete' };
  }
  const nodes = [];
  for (const issue of found.data.issues.nodes) {
    const hydrated = await completeIssueLabels(issue, request);
    if (!hydrated.ok) return hydrated;
    nodes.push(hydrated.issue);
  }
  found.data.issues.nodes = nodes;
  return { ok: true };
}

// Linear has no conditional state mutation here. Every acknowledged writer
// re-reads the durable receipts after its write, corrects state to their winner,
// and verifies again. Concurrent completed calls converge; uncertain calls
// never claim success or persist their original (possibly superseded) color.
async function reconcileProvenanceState({ result, provenance, color, teamId, apiKey, fetchImpl }) {
  if (!provenance) return result;
  const request = { apiKey, fetchImpl };
  for (let round = 0; round <= 4; round += 1) {
    const fresh = await linearGraphql({ ...request, query: `
      query RemediationIssueForReconciliation($id: String!, $teamId: String!) {
        team(id: $teamId) { states { nodes { id name type } } }
        issue(id: $id) {
          id identifier url team { id } state { id name type }
          labels(first: 100) { nodes { id name } pageInfo { hasNextPage endCursor } }
        }
      }
    `, variables: { id: result.id, teamId } }, 'linear_provenance_reconcile');
    if (!fresh.ok) return fresh;
    if (fresh.data?.issue?.id !== result.id || fresh.data.issue.team?.id !== teamId) {
      return { ok: false, reason: 'source_provenance_mismatch' };
    }
    const hydrated = await completeIssueLabels(fresh.data.issue, request);
    if (!hydrated.ok) return hydrated;
    const issue = hydrated.issue;
    if (!issue.state?.id || typeof issue.state.type !== 'string') {
      return { ok: false, reason: 'source_provenance_inventory_incomplete' };
    }
    const binding = issueProvenance(issue);
    if (!binding || !sameSource(binding.origin, provenance) || binding.records.some((record) =>
      record.runNumber === provenance.runNumber && record.runId !== provenance.runId)) {
      return { ok: false, reason: 'source_provenance_mismatch' };
    }
    if (issue.state?.type === 'canceled') return { ...result, action: 'canceled_duplicate' };
    const greenWins = binding.green && compareRuns(binding.green, binding.red) > 0;
    const winner = greenWins ? binding.green : binding.red;
    const authoritative = color === (greenWins ? 'green' : 'red') && compareRuns(provenance, winner) === 0;
    const complete = issue.state?.type === 'completed';
    if (Boolean(greenWins) === complete) {
      return { ...result, ...(authoritative ? {} : { action: 'superseded' }) };
    }
    // Reserve the last read for verification, so even exhaustion cannot end
    // immediately after an unverified correction.
    if (round === 4) return { ok: false, reason: 'source_provenance_reconciliation_busy' };
    const states = fresh.data.team?.states?.nodes ?? [];
    const target = greenWins
      ? states.find((state) => state.name === 'Done') ?? states.find((state) => state.type === 'completed')
      : states.find((state) => state.name === 'Todo') ?? states.find((state) => state.type === 'unstarted');
    if (!target?.id) return { ok: false, reason: 'linear_reconciliation_state_missing' };
    const corrected = await linearGraphql({ ...request, query: `
      mutation ReconcileRemediationState($id: String!, $input: IssueUpdateInput!) {
        issueUpdate(id: $id, input: $input) { success issue { id } }
      }
    `, variables: { id: issue.id, input: { stateId: target.id } } }, 'linear_provenance_state');
    if (!corrected.ok) return corrected;
    if (!corrected.data?.issueUpdate?.success) return { ok: false, reason: 'linear_update_unsuccessful' };
  }
  return { ok: false, reason: 'source_provenance_reconciliation_busy' };
}

/** Router label. A fingerprint that already starts with the prefix is kept. */
export function remediationKey(fingerprint) {
  const name = String(fingerprint ?? '').trim();
  return name.startsWith('remediation:') ? name : `remediation:${name}`;
}

export function missingLinearKeyWarning() {
  return 'LINEAR_API_KEY is missing from LogYourBody Actions secrets. Skipping Linear upsert. Tim must add LINEAR_API_KEY.';
}

async function readResponse(response) {
  const text = await response.text();
  if (!text) return { json: null, text: '' };
  try {
    return { json: JSON.parse(text), text };
  } catch {
    return { json: null, text };
  }
}

export async function linearGraphql({ query, variables, apiKey, fetchImpl = fetch }, caller) {
  try {
    const response = await fetchImpl(LINEAR_API, {
      method: 'POST',
      headers: {
        Authorization: apiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query, variables }),
      signal: AbortSignal.timeout(LINEAR_REQUEST_TIMEOUT_MS),
    });
    const parsed = await readResponse(response);
    if (!response.ok) {
      return {
        ok: false,
        reason: `${caller}_${response.status}`,
        body: parsed.json ?? parsed.text,
      };
    }
    if (Array.isArray(parsed.json?.errors) && parsed.json.errors.length > 0) {
      return {
        ok: false,
        reason: `${caller}_graphql_error`,
        body: parsed.json.errors,
      };
    }
    return { ok: true, data: parsed.json?.data ?? null, raw: parsed.json };
  } catch (error) {
    return {
      ok: false,
      reason: `${caller}_transport`,
      body: error instanceof Error ? error.message : String(error),
    };
  }
}

/** Post a comment on a Linear issue. */
export async function addLinearIssueComment({
  issueId,
  body,
  apiKey = process.env.LINEAR_API_KEY,
  fetchImpl = fetch,
}) {
  if (!apiKey) return { ok: false, reason: 'missing_linear_api_key' };
  if (!issueId) return { ok: false, reason: 'missing_issue_id' };
  const result = await linearGraphql(
    {
      query: `
        mutation AddLinearIssueComment($id: String!, $body: String!) {
          commentCreate(input: { issueId: $id, body: $body }) {
            success
            comment { id }
          }
        }
      `,
      variables: { id: issueId, body },
      apiKey,
      fetchImpl,
    },
    'linear_comment_create',
  );
  if (!result.ok) return result;
  if (!result.data?.commentCreate?.success) {
    return {
      ok: false,
      reason: 'linear_comment_create_unsuccessful',
      body: result.raw,
    };
  }
  return { ok: true, id: result.data.commentCreate.comment?.id ?? null };
}

/** List comments on a Linear issue (body + createdAt, oldest first). */
export async function listLinearIssueComments({
  issueId,
  apiKey = process.env.LINEAR_API_KEY,
  fetchImpl = fetch,
}) {
  if (!apiKey) return { ok: false, reason: 'missing_linear_api_key' };
  if (!issueId) return { ok: false, reason: 'missing_issue_id' };
  const result = await linearGraphql(
    {
      query: `
        query ListLinearIssueComments($id: String!) {
          issue(id: $id) {
            comments(first: 100) {
              nodes { id body createdAt }
            }
          }
        }
      `,
      variables: { id: issueId },
      apiKey,
      fetchImpl,
    },
    'linear_comment_list',
  );
  if (!result.ok) return result;
  const nodes = result.data?.issue?.comments?.nodes ?? [];
  return {
    ok: true,
    comments: nodes.map((node) => ({
      id: node?.id ?? null,
      body: String(node?.body ?? ''),
      createdAt: node?.createdAt ?? null,
    })),
  };
}

// Title contains, or label name. Linear removed issueSearch.
export function linearIssueLookupFilter({ teamId = JOVIE_TEAM_ID, fingerprint = null, label = null }) {
  const filter = { team: { id: { eq: teamId } } };
  if (typeof label === 'string' && label.trim().length > 0) {
    filter.labels = { some: { name: { eq: label.trim() } } };
  } else {
    filter.title = { contains: fingerprint };
  }
  return filter;
}

export async function upsertLinearIssue({
  fingerprint = null,
  label = null,
  identifier = null,
  title,
  description,
  priority,
  // Optional state name (e.g. 'Todo') resolved from the team's workflow so a
  // newly created issue can skip the default intake state (JOV-5966).
  createStateName = null,
  // Optional label ids applied only when a new issue is created.
  createLabelIds = [],
  createLabelNames = [],
  createIssueId = null,
  reopenTerminal = false,
  provenance = null,
  teamId = JOVIE_TEAM_ID,
  apiKey = process.env.LINEAR_API_KEY,
  fetchImpl = fetch,
}) {
  if (!apiKey) {
    return { ok: false, reason: 'missing_linear_api_key' };
  }
  const sourceProvenance = provenance === null ? null : normalizeRemediationProvenance(provenance);
  if (provenance !== null && !sourceProvenance) {
    return { ok: false, reason: 'invalid_source_provenance' };
  }
  const labelName = typeof label === 'string' ? label.trim() : '';
  const titleFingerprint = typeof fingerprint === 'string' ? fingerprint.trim() : '';
  if (!labelName && !titleFingerprint && !identifier) {
    return { ok: false, reason: 'missing_fingerprint' };
  }

  const lookup =
    labelName || titleFingerprint
      ? linearIssueLookupFilter({
          teamId,
          fingerprint: titleFingerprint,
          label: labelName || null,
        })
      : null;
  const found = await linearGraphql(
    lookup
      ? {
          query: `
            query FindRemediationIssue($teamId: String!, $filter: IssueFilter!) {
              team(id: $teamId) {
                states { nodes { id name type } }
                labels { nodes { id name } }
              }
              issues(filter: $filter, first: 25) {
                pageInfo { hasNextPage }
                nodes {
                  id identifier url title description
                  state { id name type }
                  labels(first: 100) { nodes { id name } pageInfo { hasNextPage endCursor } }
                }
              }
            }
          `,
          variables: { teamId, filter: lookup },
          apiKey,
          fetchImpl,
        }
      : {
          query: `
            query RemediationTeam($teamId: String!) {
              team(id: $teamId) {
                states { nodes { id name type } }
                labels { nodes { id name } }
              }
            }
          `,
          variables: { teamId },
          apiKey,
          fetchImpl,
        },
    'linear_search',
  );
  if (!found.ok) return found;
  if (sourceProvenance && lookup) {
    const hydrated = await hydrateProvenanceIssues(found, { apiKey, fetchImpl });
    if (!hydrated.ok) return hydrated;
  }

  const teamLabels = found.data?.team?.labels?.nodes ?? [];
  const nodes = found.data?.issues?.nodes ?? [];
  const matches = labelName
    ? nodes.filter((node) =>
        (node?.labels?.nodes ?? []).some((item) => item?.name === labelName),
      )
    : nodes.filter((node) => String(node?.title ?? '').includes(titleFingerprint));
  const compatible = sourceProvenance
    ? matches.filter((node) => compatibleIssue(node, sourceProvenance))
    : matches;
  if (sourceProvenance && matches.length && !compatible.length) {
    return { ok: false, reason: 'source_provenance_mismatch', action: 'source_mismatch' };
  }
  // Prefer a live issue over terminal duplicates so the canonical survivor
  // keeps accumulating reports instead of reopening a marked dupe.
  const terminalTypes = ['completed', 'canceled'];
  let match =
    sourceProvenance ? selectBoundIssue(compatible) :
      compatible.find((node) => !terminalTypes.includes(node?.state?.type)) ?? compatible[0] ?? null;

  if (!match && identifier) {
    const byIdentifier = await linearGraphql(
      {
        query: `
          query RemediationIssueByIdentifier($id: String!) {
            issue(id: $id) {
              id identifier url title description
              team { id }
              state { id name type }
              labels(first: 100) { nodes { id name } pageInfo { hasNextPage endCursor } }
            }
          }
        `,
        variables: { id: identifier },
        apiKey,
        fetchImpl,
      },
      'linear_issue_by_identifier',
    );
    if (!byIdentifier.ok) return byIdentifier;
    let issue = byIdentifier.data?.issue ?? null;
    if (issue && sourceProvenance) {
      const hydrated = await completeIssueLabels(issue, { apiKey, fetchImpl });
      if (!hydrated.ok) return hydrated;
      issue = hydrated.issue;
    }
    if (issue && issue.team?.id === teamId) {
      if (sourceProvenance && !compatibleIssue(issue, sourceProvenance)) {
        return { ok: false, reason: 'source_provenance_mismatch', action: 'source_mismatch' };
      }
      match = issue;
    }
  }
  if (match && sourceProvenance) {
    const boundary = signalAdmission(match, sourceProvenance, 'red');
    if (boundary) {
      const binding = issueProvenance(match);
      // Repair a retry after concurrent older recovery wrote Done; an equal
      // replay with no recorded green preserves a manual completion.
      if (boundary.action === 'stale_signal' && match.state?.type === 'completed' &&
          binding.green && compareRuns(binding.red, binding.green) > 0 &&
          compareRuns(sourceProvenance, binding.red) === 0) {
        return reconcileProvenanceState({
          result: { ok: true, action: 'updated', id: match.id, identifier: match.identifier, url: match.url },
          provenance: sourceProvenance, color: 'red', teamId, apiKey, fetchImpl,
        });
      }
      return { ...boundary, id: match.id, identifier: match.identifier };
    }
  }

  const availableLabels = [...teamLabels, ...(match?.labels?.nodes ?? [])];
  const labelIdResult = labelName
    ? await ensureTeamLabelId({ label: labelName, labels: availableLabels,
      recover: Boolean(sourceProvenance), teamId, apiKey, fetchImpl })
    : { ok: true, id: null };
  if (!labelIdResult.ok) return labelIdResult;
  const receiptName = sourceProvenance
    ? remediationProvenanceLabel(sourceProvenance, match ? 'red' : 'origin') : null;
  const receiptLabel = receiptName
    ? await ensureTeamLabelId({ label: receiptName, labels: availableLabels,
      recover: true, teamId, apiKey, fetchImpl })
    : { ok: true, id: null };
  if (!receiptLabel.ok) return receiptLabel;
  const labelIds = [...createLabelIds, labelIdResult.id, receiptLabel.id].filter(Boolean);

  if (!match) {
    for (const name of createLabelNames) {
      const extra = await ensureTeamLabelId({ label: name, labels: availableLabels,
        recover: true, teamId, apiKey, fetchImpl });
      if (!extra.ok) return extra;
      labelIds.push(extra.id);
    }
    const states = found.data?.team?.states?.nodes ?? [];
    const createStateId = createStateName
      ? (states.find((state) => state?.name === createStateName)?.id ?? null)
      : null;
    if (createStateName && !createStateId) {
      return { ok: false, reason: 'linear_create_state_missing' };
    }
    const created = await linearGraphql(
      {
        query: `
          mutation CreateDedupedLinearIssue(
            $teamId: String!
            $title: String!
            $description: String!
            ${typeof priority === 'number' ? '$priority: Int' : ''}
            $stateId: String
            $labelIds: [String!]
            ${createIssueId ? '$id: String!' : ''}
          ) {
            issueCreate(input: {
              ${createIssueId ? 'id: $id' : ''}
              teamId: $teamId
              title: $title
              description: $description
              ${typeof priority === 'number' ? 'priority: $priority' : ''}
              stateId: $stateId
              labelIds: $labelIds
            }) {
              success
              issue { id identifier url }
            }
          }
        `,
        variables: {
          teamId,
          ...(createIssueId ? { id: createIssueId } : {}),
          title,
          description,
          ...(typeof priority === 'number' ? { priority } : {}),
          ...(createStateId ? { stateId: createStateId } : {}),
          ...(labelIds.length > 0 ? { labelIds } : {}),
        },
        apiKey,
        fetchImpl,
      },
      'linear_create',
    );
    if (!created.ok) return created;
    if (!created.data?.issueCreate?.success) {
      return {
        ok: false,
        reason: 'linear_create_unsuccessful',
        body: created.raw,
      };
    }
    return reconcileProvenanceState({ result: {
      ok: true,
      action: 'created',
      id: created.data.issueCreate.issue?.id ?? null,
      identifier: created.data.issueCreate.issue?.identifier ?? null,
      url: created.data.issueCreate.issue?.url ?? null,
    }, provenance: sourceProvenance, color: 'red', teamId, apiKey, fetchImpl });
  }

  const terminal = ['completed', 'canceled'].includes(match.state?.type);
  const states = found.data?.team?.states?.nodes ?? [];
  const backlogState =
    states.find((state) => state?.name === 'Backlog') ??
    states.find((state) => state?.type === 'backlog');
  const todoState =
    states.find((state) => state?.name === 'Todo') ??
    states.find((state) => state?.type === 'unstarted');
  const sourceStateId = terminal ? todoState?.id : match.state?.id;
  if (sourceProvenance && !sourceStateId) return { ok: false, reason: 'linear_red_state_missing' };
  if (!sourceProvenance && terminal && reopenTerminal && !backlogState) {
    return { ok: false, reason: 'linear_backlog_state_missing' };
  }
  const alreadyLabeled =
    !labelName || (match.labels?.nodes ?? []).some((item) => item?.name === labelName);
  const addedLabelIds = [
    ...(!alreadyLabeled && labelIdResult.id ? [labelIdResult.id] : []),
    ...(receiptLabel.id && !(match.labels?.nodes ?? []).some((item) => item?.name === receiptName)
      ? [receiptLabel.id] : []),
  ];
  // Priority is part of the upsert when the caller sets it, so an existing
  // Urgent JOV issue stays Urgent. Callers that omit it leave priority alone.
  const input = {
    description,
    ...(typeof priority === 'number' ? { priority } : {}),
    ...(addedLabelIds.length ? { addedLabelIds } : {}),
    ...(sourceProvenance ? { stateId: sourceStateId } : terminal && reopenTerminal
      ? {
          stateId: createStateName === 'Todo' && todoState ? todoState.id : backlogState.id,
        }
      : {}),
  };
  const updated = await linearGraphql(
    {
      query: `
        mutation UpdateDedupedLinearIssue($id: String!, $input: IssueUpdateInput!) {
          issueUpdate(id: $id, input: $input) {
            success
            issue { id identifier url }
          }
        }
      `,
      variables: { id: match.id, input },
      apiKey,
      fetchImpl,
    },
    'linear_update',
  );
  if (!updated.ok) return updated;
  if (!updated.data?.issueUpdate?.success) {
    return {
      ok: false,
      reason: 'linear_update_unsuccessful',
      body: updated.raw,
    };
  }
  return reconcileProvenanceState({ result: {
    ok: true,
    action: 'updated',
    reopened: terminal && reopenTerminal,
    id: match.id,
    identifier: match.identifier,
    url: match.url,
  }, provenance: sourceProvenance, color: 'red', teamId, apiKey, fetchImpl });
}

export const upsertLinearIssueByTitleFingerprint = upsertLinearIssue;

async function ensureTeamLabelId({ label, labels, recover = false, teamId = JOVIE_TEAM_ID, apiKey, fetchImpl }) {
  const existing = labels.find((item) => item?.name === label);
  if (existing?.id) return { ok: true, id: existing.id };
  const lookup = async () => {
    const matches = new Map();
    const cursors = new Set();
    let after = null;
    while (true) {
      const found = await linearGraphql({ apiKey, fetchImpl, query: `
        query RemediationTeamLabelByName($teamId: String!, $after: String) {
          team(id: $teamId) {
            labels(first: 100, after: $after) {
              nodes { id name } pageInfo { hasNextPage endCursor }
            }
          }
        }
      `, variables: { teamId, after } }, 'linear_label_lookup');
      if (!found.ok) return found;
      const connection = found.data?.team?.labels;
      if (!Array.isArray(connection?.nodes) || typeof connection.pageInfo?.hasNextPage !== 'boolean') {
        return { ok: false, reason: 'linear_label_inventory_incomplete' };
      }
      for (const item of connection.nodes) if (item.name === label && item.id) matches.set(item.id, item);
      if (matches.size > 1) return { ok: false, reason: 'linear_label_inventory_incomplete' };
      if (!connection.pageInfo.hasNextPage) return { ok: true, id: [...matches.keys()][0] ?? null };
      after = connection.pageInfo.endCursor;
      if (!after || cursors.has(after)) return { ok: false, reason: 'linear_label_inventory_incomplete' };
      cursors.add(after);
    }
  };
  if (recover) {
    const found = await lookup();
    if (!found.ok || found.id) return found;
  }
  const created = await linearGraphql(
    {
      query: `
        mutation CreateTeamLabel($name: String!, $teamId: String!) {
          issueLabelCreate(input: { name: $name, teamId: $teamId }) {
            success
            issueLabel { id }
          }
        }
      `,
      variables: { name: label, teamId },
      apiKey,
      fetchImpl,
    },
    'linear_label_create',
  );
  if (!created.ok || !created.data?.issueLabelCreate?.success) {
    // Label creation can commit before an acknowledgment is lost, or another
    // run can create it after our lookup. Recover its exact ID before retry.
    const recovered = recover ? await lookup() : null;
    if (recovered?.ok && recovered.id) return recovered;
    return created.ok ? { ok: false, reason: 'linear_label_create_unsuccessful' } : created;
  }
  const id = created.data?.issueLabelCreate?.issueLabel?.id ?? null;
  if (!created.data?.issueLabelCreate?.success || !id) {
    return { ok: false, reason: 'linear_label_create_unsuccessful', body: created.raw };
  }
  return { ok: true, id };
}

export async function findTeamIdByKey({
  teamKey = LYB_TEAM_KEY,
  apiKey = process.env.LINEAR_API_KEY,
  fetchImpl = fetch,
}) {
  if (!apiKey) return { ok: false, reason: 'missing_linear_api_key' };
  const key = String(teamKey ?? '').trim();
  if (!key) return { ok: false, reason: 'missing_team_key' };
  const result = await linearGraphql(
    {
      query: `
        query TeamByKey($key: String!) {
          teams(filter: { key: { eq: $key } }) { nodes { id key } }
        }
      `,
      variables: { key },
      apiKey,
      fetchImpl,
    },
    'linear_team_by_key',
  );
  if (!result.ok) return result;
  const id = result.data?.teams?.nodes?.[0]?.id ?? null;
  if (!id) return { ok: false, reason: 'linear_team_missing' };
  return { ok: true, id };
}

/** Bound callers require immutable origin and newer recovery receipts.
 * Legacy JOV callers retain the description-based contract. */
export async function noteFingerprintedIssueGreen({
  fingerprint,
  source,
  comment,
  provenance = null,
  teamId = JOVIE_TEAM_ID,
  apiKey = process.env.LINEAR_API_KEY,
  fetchImpl = fetch,
}) {
  if (!apiKey) return { ok: false, reason: 'missing_linear_api_key' };
  const sourceProvenance = provenance === null ? null : normalizeRemediationProvenance(provenance);
  if (provenance !== null && !sourceProvenance) {
    return { ok: false, reason: 'invalid_source_provenance' };
  }
  const labelName = remediationKey(fingerprint);
  if (!labelName || labelName === 'remediation:') {
    return { ok: false, reason: 'missing_fingerprint' };
  }
  const found = await linearGraphql(
    {
      query: `
        query FindRemediationForGreen($teamId: String!, $filter: IssueFilter!) {
          team(id: $teamId) {
            states { nodes { id name type } }
            labels { nodes { id name } }
          }
          issues(filter: $filter, first: 25) {
            pageInfo { hasNextPage }
            nodes {
              id identifier url title description
              state { id name type }
              labels(first: 100) { nodes { id name } pageInfo { hasNextPage endCursor } }
            }
          }
        }
      `,
      variables: {
        teamId,
        filter: linearIssueLookupFilter({ teamId, label: labelName }),
      },
      apiKey,
      fetchImpl,
    },
    'linear_label_search',
  );
  if (!found.ok) return found;
  if (sourceProvenance) {
    const hydrated = await hydrateProvenanceIssues(found, { apiKey, fetchImpl });
    if (!hydrated.ok) return hydrated;
  }
  const nodes = found.data?.issues?.nodes ?? [];
  const terminalTypes = ['completed', 'canceled'];
  const matches = nodes.filter((node) =>
    (node?.labels?.nodes ?? []).some((item) => item?.name === labelName),
  );
  const compatible = sourceProvenance
    ? matches.filter((node) => compatibleIssue(node, sourceProvenance))
    : matches;
  if (sourceProvenance && matches.length && !compatible.length) {
    return { ok: false, reason: 'source_provenance_mismatch', action: 'source_mismatch' };
  }
  const match =
    sourceProvenance ? selectBoundIssue(compatible) :
      compatible.find((node) => !terminalTypes.includes(node?.state?.type)) ?? compatible[0] ?? null;
  if (!match) return { ok: true, action: 'none' };
  if (sourceProvenance) {
    const boundary = signalAdmission(match, sourceProvenance, 'green');
    if (boundary) return { ...boundary, id: match.id, identifier: match.identifier };
  }
  const terminal = terminalTypes.includes(match.state?.type);
  const receiptName = sourceProvenance ? remediationProvenanceLabel(sourceProvenance, 'green') : null;
  if (terminal && (!sourceProvenance || (match.labels?.nodes ?? []).some((item) => item?.name === receiptName))) {
    return reconcileProvenanceState({
      result: { ok: true, action: 'already_closed', id: match.id, identifier: match.identifier },
      provenance: sourceProvenance, color: 'green', teamId, apiKey, fetchImpl,
    });
  }
  const sourceLine = source ? `Source-workflow: ${source}` : '';
  if (!sourceProvenance && sourceLine && !String(match.description ?? '').includes(sourceLine)) {
    return { ok: true, action: 'source_mismatch', id: match.id, identifier: match.identifier ?? null };
  }
  const states = found.data?.team?.states?.nodes ?? [];
  const done =
    states.find((state) => state?.name === 'Done') ??
    states.find((state) => state?.type === 'completed');
  if ((!terminal || sourceProvenance) && !done?.id) return { ok: false, reason: 'linear_done_state_missing' };
  const receiptLabel = receiptName
    ? await ensureTeamLabelId({
        label: receiptName,
        labels: [...(found.data?.team?.labels?.nodes ?? []), ...(match.labels?.nodes ?? [])],
        recover: true, teamId, apiKey, fetchImpl,
      })
    : { ok: true, id: null };
  if (!receiptLabel.ok) return receiptLabel;
  if (!terminal) {
    const posted = await addLinearIssueComment({
      issueId: match.id,
      body: comment || `<!-- remediation-green -->\n${sourceLine} is green.`,
      apiKey,
      fetchImpl,
    });
    if (!posted.ok) return posted;
  }
  const updated = await linearGraphql(
    {
      query: `
        mutation ResolveRemediation($id: String!, $input: IssueUpdateInput!) {
          issueUpdate(id: $id, input: $input) {
            success
            issue { id identifier url }
          }
        }
      `,
      variables: { id: match.id, input: {
        ...(!terminal || sourceProvenance ? { stateId: done.id } : {}),
        ...(receiptLabel.id ? { addedLabelIds: [receiptLabel.id] } : {}),
      } },
      apiKey,
      fetchImpl,
    },
    'linear_resolve',
  );
  if (!updated.ok) return updated;
  if (!updated.data?.issueUpdate?.success) {
    return { ok: false, reason: 'linear_update_unsuccessful', body: updated.raw };
  }
  return reconcileProvenanceState({ result: {
    ok: true,
    action: terminal ? 'already_closed' : 'resolved',
    id: match.id,
    identifier: updated.data.issueUpdate.issue?.identifier ?? match.identifier,
    url: updated.data.issueUpdate.issue?.url ?? match.url,
  }, provenance: sourceProvenance, color: 'green', teamId, apiKey, fetchImpl });
}
