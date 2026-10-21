import { addLinearIssueComment, linearGraphql } from './linear-issue-intake.mjs';

// The existing LYB correction-pyramid epic is the durable owner-loop receipt.
export const COVERAGE_OWNER_ISSUE = 'LYB-203';

export async function postCoverageComment({ revision, body, apiKey, fetchImpl = fetch }) {
  if (!apiKey) return { ok: false, reason: 'missing_linear_api_key' };
  if (!/^[a-f0-9]{40}$/.test(revision)) return { ok: false, reason: 'invalid_source_revision' };
  const marker = `<!-- lyb-correction-coverage:v1:${revision} -->`;
  const request = { apiKey, fetchImpl };
  const cursors = new Set();
  let after = null;
  let issueId;
  while (true) {
    const result = await linearGraphql(
      {
        ...request,
        query: `query CorrectionCoverageOwner($id: String!, $after: String) {
        issue(id: $id) {
          id identifier team { key }
          comments(first: 100, after: $after) {
            nodes { body }
            pageInfo { hasNextPage endCursor }
          }
        }
      }`,
        variables: { id: COVERAGE_OWNER_ISSUE, after },
      },
      'linear_coverage_owner',
    );
    if (!result.ok) return { ok: false, reason: result.reason };
    const issue = result.data?.issue;
    const comments = issue?.comments;
    if (
      !issue?.id ||
      issue.identifier !== COVERAGE_OWNER_ISSUE ||
      issue.team?.key !== 'LYB' ||
      (issueId && issueId !== issue.id) ||
      !Array.isArray(comments?.nodes) ||
      typeof comments.pageInfo?.hasNextPage !== 'boolean'
    ) {
      return { ok: false, reason: 'invalid_lyb_coverage_owner' };
    }
    issueId = issue.id;
    if (comments.nodes.some((comment) => comment.body?.startsWith(marker))) {
      return { ok: true, action: 'unchanged', issue: COVERAGE_OWNER_ISSUE };
    }
    if (!comments.pageInfo.hasNextPage) break;
    after = comments.pageInfo.endCursor;
    if (!after || cursors.has(after)) return { ok: false, reason: 'incomplete_coverage_comments' };
    cursors.add(after);
  }
  const result = await addLinearIssueComment({
    ...request,
    issueId,
    body: `${marker}\n${body}\nSource: https://github.com/JovieInc/LogYourBody/commit/${revision}\n`,
  });
  return result.ok
    ? { ok: true, action: 'posted', issue: COVERAGE_OWNER_ISSUE, commentId: result.id }
    : { ok: false, reason: result.reason };
}
