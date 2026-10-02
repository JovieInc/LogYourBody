// Vendored from JovieInc/Jovie scripts/lib/linear-issue-intake.mjs.
// One upsert helper for the remediation jobs: match an existing JOV issue by
// title fingerprint or by label, then create or update it. Comment helpers
// sit next to it. JOV team id is the Jovie team.

const LINEAR_API = 'https://api.linear.app/graphql';
const LINEAR_REQUEST_TIMEOUT_MS = 15_000;
export const JOVIE_TEAM_ID = 'bdc09edc-f91c-4a06-b308-74b4fcf093f8';

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

async function linearGraphql({ query, variables, apiKey, fetchImpl = fetch }, caller) {
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
  reopenTerminal = false,
  apiKey = process.env.LINEAR_API_KEY,
  fetchImpl = fetch,
}) {
  if (!apiKey) {
    return { ok: false, reason: 'missing_linear_api_key' };
  }
  const labelName = typeof label === 'string' ? label.trim() : '';
  const titleFingerprint = typeof fingerprint === 'string' ? fingerprint.trim() : '';
  if (!labelName && !titleFingerprint && !identifier) {
    return { ok: false, reason: 'missing_fingerprint' };
  }

  const lookup =
    labelName || titleFingerprint
      ? linearIssueLookupFilter({
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
                nodes {
                  id identifier url title description
                  state { id name type }
                  labels { nodes { id name } }
                }
              }
            }
          `,
          variables: { teamId: JOVIE_TEAM_ID, filter: lookup },
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
          variables: { teamId: JOVIE_TEAM_ID },
          apiKey,
          fetchImpl,
        },
    'linear_search',
  );
  if (!found.ok) return found;

  const teamLabels = found.data?.team?.labels?.nodes ?? [];
  const nodes = found.data?.issues?.nodes ?? [];
  const matches = labelName
    ? nodes.filter((node) =>
        (node?.labels?.nodes ?? []).some((item) => item?.name === labelName),
      )
    : nodes.filter((node) => String(node?.title ?? '').includes(titleFingerprint));
  // Prefer a live issue over terminal duplicates so the canonical survivor
  // keeps accumulating reports instead of reopening a marked dupe.
  const terminalTypes = ['completed', 'canceled'];
  let match =
    matches.find((node) => !terminalTypes.includes(node?.state?.type)) ?? matches[0] ?? null;

  if (!match && identifier) {
    const byIdentifier = await linearGraphql(
      {
        query: `
          query RemediationIssueByIdentifier($id: String!) {
            issue(id: $id) {
              id identifier url title description
              team { id }
              state { id name type }
              labels { nodes { id name } }
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
    const issue = byIdentifier.data?.issue ?? null;
    if (issue && issue.team?.id === JOVIE_TEAM_ID) match = issue;
  }

  const labelIdResult = labelName
    ? await ensureTeamLabelId({ label: labelName, labels: teamLabels, apiKey, fetchImpl })
    : { ok: true, id: null };
  if (!labelIdResult.ok) return labelIdResult;
  const labelIds = [...createLabelIds, labelIdResult.id].filter(Boolean);

  if (!match) {
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
            $title: String!
            $description: String!
            ${typeof priority === 'number' ? '$priority: Int' : ''}
            $stateId: String
            $labelIds: [String!]
          ) {
            issueCreate(input: {
              teamId: "${JOVIE_TEAM_ID}"
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
    return {
      ok: true,
      action: 'created',
      id: created.data.issueCreate.issue?.id ?? null,
      identifier: created.data.issueCreate.issue?.identifier ?? null,
      url: created.data.issueCreate.issue?.url ?? null,
    };
  }

  const terminal = ['completed', 'canceled'].includes(match.state?.type);
  const states = found.data?.team?.states?.nodes ?? [];
  const backlogState =
    states.find((state) => state?.name === 'Backlog') ??
    states.find((state) => state?.type === 'backlog');
  const todoState =
    states.find((state) => state?.name === 'Todo') ??
    states.find((state) => state?.type === 'unstarted');
  if (terminal && reopenTerminal && !backlogState) {
    return { ok: false, reason: 'linear_backlog_state_missing' };
  }
  const alreadyLabeled =
    !labelName || (match.labels?.nodes ?? []).some((item) => item?.name === labelName);
  // Priority is part of the upsert when the caller sets it, so an existing
  // Urgent JOV issue stays Urgent. Callers that omit it leave priority alone.
  const input = {
    description,
    ...(typeof priority === 'number' ? { priority } : {}),
    ...(!alreadyLabeled && labelIdResult.id ? { addedLabelIds: [labelIdResult.id] } : {}),
    ...(terminal && reopenTerminal
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
  return {
    ok: true,
    action: 'updated',
    reopened: terminal && reopenTerminal,
    id: match.id,
    identifier: match.identifier,
    url: match.url,
  };
}

export const upsertLinearIssueByTitleFingerprint = upsertLinearIssue;

async function ensureTeamLabelId({ label, labels, apiKey, fetchImpl }) {
  const existing = labels.find((item) => item?.name === label);
  if (existing?.id) return { ok: true, id: existing.id };
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
      variables: { name: label, teamId: JOVIE_TEAM_ID },
      apiKey,
      fetchImpl,
    },
    'linear_label_create',
  );
  if (!created.ok) return created;
  const id = created.data?.issueLabelCreate?.issueLabel?.id ?? null;
  if (!created.data?.issueLabelCreate?.success || !id) {
    return { ok: false, reason: 'linear_label_create_unsuccessful', body: created.raw };
  }
  return { ok: true, id };
}
