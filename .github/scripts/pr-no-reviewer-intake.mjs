#!/usr/bin/env node
// Weekly: open non-draft PRs that are green, have auto-merge enabled, and
// have had no reviewer for more than 48h. Files or reopens one JOV issue
// (remediation:lyb-pr-no-reviewer / JOV-7547). Never edits pull requests.

import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import {
  addLinearIssueComment,
  missingLinearKeyWarning,
  upsertLinearIssueByTitleFingerprint,
} from './lib/linear-issue-intake.mjs';

export const NO_REVIEWER_FINGERPRINT = 'remediation:lyb-pr-no-reviewer';
export const NO_REVIEWER_WAIT_MS = 48 * 60 * 60 * 1000;

const QUERY = `
  query OpenPullRequests($owner: String!, $repo: String!, $cursor: String) {
    repository(owner: $owner, name: $repo) {
      pullRequests(
        states: OPEN
        first: 50
        after: $cursor
        orderBy: { field: CREATED_AT, direction: ASC }
      ) {
        pageInfo { hasNextPage endCursor }
        nodes {
          number
          title
          url
          state
          isDraft
          createdAt
          autoMergeRequest { enabledAt }
          reviews(first: 1) { totalCount }
          reviewRequests(first: 1) { totalCount }
          commits(last: 1) {
            nodes { commit { statusCheckRollup { state } } }
          }
        }
      }
    }
  }
`;

export function normalizePullRequest(node) {
  const rollup = node?.commits?.nodes?.[0]?.commit?.statusCheckRollup?.state ?? null;
  return {
    number: node?.number,
    title: node?.title ?? '',
    url: node?.url ?? '',
    state: String(node?.state ?? 'OPEN').toLowerCase(),
    isDraft: node?.isDraft === true,
    createdAt: node?.createdAt ?? '',
    autoMerge: node?.autoMergeRequest != null,
    green: rollup === 'SUCCESS',
    reviewCount: node?.reviews?.totalCount ?? 0,
    reviewRequestCount: node?.reviewRequests?.totalCount ?? 0,
  };
}

export function selectPrsMissingReviewer(prs, nowMs) {
  return prs.filter((pr) => {
    if (String(pr?.state ?? '').toLowerCase() !== 'open') return false;
    if (pr.isDraft) return false;
    if (!pr.autoMerge) return false;
    if (pr.green !== true) return false;
    if ((pr.reviewCount ?? 0) > 0) return false;
    if ((pr.reviewRequestCount ?? 0) > 0) return false;
    const created = Date.parse(pr.createdAt);
    if (!Number.isFinite(created)) return false;
    return nowMs - created > NO_REVIEWER_WAIT_MS;
  });
}

export function buildNoReviewerIssue(selected, runUrl) {
  const lines = selected.map((pr) => `- #${pr.number} ${pr.url} (opened ${pr.createdAt})`);
  const url = runUrl || '(run URL unavailable)';
  return {
    fingerprint: NO_REVIEWER_FINGERPRINT,
    title: `Open auto-merge PRs have no reviewer after 48h (${NO_REVIEWER_FINGERPRINT})`,
    description: [
      'These open, non-draft pull requests are green, have auto-merge enabled, and have had no reviewer for more than 48 hours.',
      'This job only files a Linear issue. It does not edit pull requests.',
      '',
      ...lines,
      '',
      `Run: ${url}`,
    ].join('\n'),
    priority: 1,
    createStateName: 'Todo',
    reopenTerminal: true,
  };
}

export function formatNoReviewerDryRun(selected, runUrl) {
  if (selected.length === 0) {
    return [
      'dry_run: would file nothing',
      `fingerprint: ${NO_REVIEWER_FINGERPRINT}`,
      'matching_prs: 0',
    ].join('\n');
  }
  const issue = buildNoReviewerIssue(selected, runUrl);
  return [
    'dry_run: would upsert Linear issue',
    `fingerprint: ${issue.fingerprint}`,
    `priority: ${issue.priority}`,
    `createStateName: ${issue.createStateName}`,
    `reopenTerminal: ${issue.reopenTerminal}`,
    `title: ${issue.title}`,
    'pull_requests:',
    ...selected.map((pr) => `- #${pr.number} ${pr.url}`),
    'description:',
    issue.description,
  ].join('\n');
}

function graphql(cursor) {
  const [owner, repo] = (process.env.GITHUB_REPOSITORY || 'JovieInc/LogYourBody').split('/');
  const args = [
    'api',
    'graphql',
    '-f',
    `query=${QUERY}`,
    '-f',
    `owner=${owner}`,
    '-f',
    `repo=${repo}`,
  ];
  if (cursor) args.push('-f', `cursor=${cursor}`);
  const out = execFileSync('gh', args, { encoding: 'utf8', timeout: 60_000, maxBuffer: 8_000_000 });
  const parsed = JSON.parse(out);
  if (Array.isArray(parsed.errors) && parsed.errors.length > 0) {
    throw new Error(parsed.errors.map((error) => error.message).join('; '));
  }
  return parsed.data.repository.pullRequests;
}

export function listOpenPullRequests() {
  const nodes = [];
  let cursor = null;
  for (let page = 0; page < 10; page += 1) {
    const connection = graphql(cursor);
    nodes.push(...(connection.nodes ?? []));
    if (!connection.pageInfo?.hasNextPage) break;
    cursor = connection.pageInfo.endCursor;
  }
  return nodes.map(normalizePullRequest);
}

async function main() {
  const runUrl =
    process.env.RUN_URL ||
    (process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
      ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
      : '');
  const selected = selectPrsMissingReviewer(listOpenPullRequests(), Date.now());
  if (process.env.DRY_RUN === 'true') {
    console.log(formatNoReviewerDryRun(selected, runUrl));
    return;
  }
  if (selected.length === 0) {
    console.log(`fingerprint: ${NO_REVIEWER_FINGERPRINT}`);
    console.log('matching_prs: 0');
    console.log('No Linear issue filed.');
    return;
  }
  const plan = buildNoReviewerIssue(selected, runUrl);
  if (!process.env.LINEAR_API_KEY) {
    console.log(`::warning::${missingLinearKeyWarning()}`);
    console.log(formatNoReviewerDryRun(selected, runUrl));
    return;
  }
  const upserted = await upsertLinearIssueByTitleFingerprint({ ...plan, apiKey: process.env.LINEAR_API_KEY });
  if (!upserted.ok) {
    console.error(upserted.reason || 'linear_upsert_failed');
    process.exit(1);
  }
  console.log(`${upserted.action} ${upserted.identifier ?? ''} ${upserted.url ?? ''}`.trim());
  if (!upserted.id) return;
  const comment = await addLinearIssueComment({
    issueId: upserted.id,
    apiKey: process.env.LINEAR_API_KEY,
    body: [
      `${selected.length} open auto-merge pull request(s) have had no reviewer for more than 48 hours.`,
      '',
      `Run: ${runUrl}`,
    ].join('\n'),
  });
  if (!comment.ok) {
    console.error(comment.reason || 'linear_comment_failed');
    process.exit(1);
  }
}

const isDirectRun = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isDirectRun) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
}
