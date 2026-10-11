#!/usr/bin/env node
// On an iOS release failure, upsert LYB remediation:asc-agreements
// when the log contains REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED.
// Does not replace the existing LYB-68 [ci] filing.

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import {
  addLinearIssueComment,
  listLinearIssueComments,
  findTeamIdByKey,
  LYB_TEAM_KEY,
  missingLinearKeyWarning,
  upsertLinearIssue,
} from './lib/linear-issue-intake.mjs';

export const ASC_LOG_FINGERPRINT = 'REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED';
export const ASC_ISSUE_FINGERPRINT = 'remediation:asc-agreements';
const COMMENT_WINDOW_MS = 24 * 60 * 60 * 1000;

export function logContainsAscAgreementsFailure(text) {
  return String(text ?? '').includes(ASC_LOG_FINGERPRINT);
}

export function planAscAgreementsIssue(logText, runUrl) {
  if (!logContainsAscAgreementsFailure(logText)) return null;
  const url = runUrl || '(run URL unavailable)';
  return {
    fingerprint: ASC_ISSUE_FINGERPRINT,
    title: `App Store Connect agreements missing or expired (${ASC_ISSUE_FINGERPRINT})`,
    description: [
      'App Store Connect returned 403 FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED during an iOS release.',
      '',
      `Latest run: ${url}`,
      '',
      'Accept the pending agreements in App Store Connect, then rerun the release.',
    ].join('\n'),
    priority: 1,
    createStateName: 'Todo',
    reopenTerminal: true,
    teamKey: LYB_TEAM_KEY,
  };
}

export function shouldAddRunComment(comments, { runUrl, nowMs, windowMs = COMMENT_WINDOW_MS }) {
  const list = Array.isArray(comments) ? comments : [];
  if (runUrl && list.some((comment) => String(comment?.body ?? '').includes(runUrl))) return false;
  const cutoff = nowMs - windowMs;
  return !list.some((comment) => {
    const created = Date.parse(comment?.createdAt ?? '');
    return (
      Number.isFinite(created) &&
      created > cutoff &&
      String(comment?.body ?? '').includes(ASC_ISSUE_FINGERPRINT)
    );
  });
}

async function filePlan(plan, { apiKey, runUrl, nowMs = Date.now() }) {
  const team = await findTeamIdByKey({ teamKey: plan.teamKey, apiKey });
  if (!team.ok) return team;
  const upserted = await upsertLinearIssue({
    ...plan,
    teamId: team.id,
    apiKey,
  });
  if (!upserted.ok) return upserted;
  console.log(`${upserted.action} ${upserted.identifier ?? ''} ${upserted.url ?? ''}`.trim());
  if (!upserted.id) return upserted;
  const listed = await listLinearIssueComments({ issueId: upserted.id, apiKey });
  const comments = listed.ok ? listed.comments : [];
  // ponytail: one comment per 24h while the outage continues; the description keeps the latest run URL.
  if (!shouldAddRunComment(comments, { runUrl, nowMs })) {
    console.log('Skipped duplicate ASC agreements comment.');
    return upserted;
  }
  const comment = await addLinearIssueComment({
    issueId: upserted.id,
    apiKey,
    body: [
      `App Store Connect agreements are blocking an iOS release (${ASC_ISSUE_FINGERPRINT}).`,
      '',
      `Run: ${runUrl}`,
    ].join('\n'),
  });
  if (!comment.ok) return comment;
  return upserted;
}

async function main() {
  const logPath = process.argv[2];
  if (!logPath) {
    console.error('usage: asc-agreements-remediation.mjs <log-file>');
    process.exit(1);
  }
  const plan = planAscAgreementsIssue(readFileSync(logPath, 'utf8'), process.env.RUN_URL || '');
  if (!plan) {
    console.log('No REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED failure in the log.');
    return;
  }
  if (process.env.DRY_RUN === 'true') {
    console.log(`dry_run: would upsert Linear issue`);
    console.log(`fingerprint: ${plan.fingerprint}`);
    console.log(`priority: ${plan.priority}`);
    console.log(`createStateName: ${plan.createStateName}`);
    console.log(`reopenTerminal: ${plan.reopenTerminal}`);
    console.log(`title: ${plan.title}`);
    console.log('description:');
    console.log(plan.description);
    return;
  }
  if (!process.env.LINEAR_API_KEY) {
    console.log(`::warning::${missingLinearKeyWarning()}`);
    return;
  }
  const result = await filePlan(plan, {
    apiKey: process.env.LINEAR_API_KEY,
    runUrl: process.env.RUN_URL || '',
  });
  if (!result.ok) {
    console.error(result.reason || 'linear_upsert_failed');
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
