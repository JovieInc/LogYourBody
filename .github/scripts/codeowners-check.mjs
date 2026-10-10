#!/usr/bin/env node
// Weekly CODEOWNERS drift check. Upserts JOV-7549 on the Jovie team when the
// file is missing or an owner is invalid, matched by label
// remediation:codeowners-drift, and adds a comment for this repository.
// Live filing requires REMEDIATION_TRIGGERS_ENABLED=true and LINEAR_API_KEY.
// Otherwise the script prints the upsert and does not call Linear.

import { pathToFileURL } from 'node:url';
import {
  addLinearIssueComment,
  listLinearIssueComments,
  upsertLinearIssue,
} from './lib/linear-issue-intake.mjs';

export const CODEOWNERS_LABEL = 'remediation:codeowners-drift';
export const CODEOWNERS_ISSUE = 'JOV-7549';

export function isInvalidOwnerError(error) {
  const kind = String(error?.kind ?? '').toLowerCase();
  const message = String(error?.message ?? '').toLowerCase();
  return kind.includes('owner') || message.includes('invalid owner');
}

export function classifyCodeowners({ status, body }) {
  if (status === 404) return { kind: 'missing', errors: [] };
  if (status !== 200) return { kind: 'http_error', status, errors: [] };
  const ownerErrors = (Array.isArray(body?.errors) ? body.errors : []).filter(isInvalidOwnerError);
  if (ownerErrors.length > 0) return { kind: 'invalid_owner', errors: ownerErrors };
  return { kind: 'ok', errors: [] };
}

export function codeownersFilingEnabled(env = process.env) {
  return env.REMEDIATION_TRIGGERS_ENABLED === 'true' && Boolean(env.LINEAR_API_KEY);
}

function formatOwnerError(error) {
  const where = [error?.path, error?.line].filter((part) => part !== undefined && part !== null).join(':');
  return [where, error?.kind, error?.source].filter(Boolean).join(' ');
}

export function planCodeownersIssue({ repo, classification, runUrl }) {
  if (!classification || (classification.kind !== 'missing' && classification.kind !== 'invalid_owner')) {
    return null;
  }
  const detail =
    classification.kind === 'missing'
      ? 'CODEOWNERS is missing.'
      : [
          'CODEOWNERS has an invalid owner.',
          ...classification.errors.map((error) => `- ${formatOwnerError(error)}`),
        ].join('\n');
  const comment = [`repo: ${repo}`, CODEOWNERS_LABEL, detail, runUrl ? `Run: ${runUrl}` : '']
    .filter(Boolean)
    .join('\n');
  return {
    label: CODEOWNERS_LABEL,
    identifier: CODEOWNERS_ISSUE,
    title: `CODEOWNERS drift (${CODEOWNERS_LABEL})`,
    description: [
      `Repository: ${repo}`,
      `Linear issue: ${CODEOWNERS_ISSUE}`,
      '',
      detail,
      '',
      runUrl ? `Latest run: ${runUrl}` : '',
    ]
      .filter((line) => line !== '')
      .join('\n'),
    createStateName: 'Todo',
    reopenTerminal: true,
    comment,
  };
}

export function formatCodeownersDryRun(plan, { reason }) {
  if (!plan) return 'CODEOWNERS ok. No Linear issue filed.';
  return [
    'dry_run: would upsert Linear issue',
    `reason: ${reason}`,
    `label: ${plan.label}`,
    `identifier: ${plan.identifier}`,
    `title: ${plan.title}`,
    'description:',
    plan.description,
    'comment:',
    plan.comment,
  ].join('\n');
}

export function shouldAddRepoComment(comments, commentBody) {
  return !(Array.isArray(comments) ? comments : []).some(
    (comment) => String(comment?.body ?? '') === commentBody,
  );
}

export async function fetchCodeownersErrors(repo, { token, fetchImpl = fetch }) {
  const response = await fetchImpl(`https://api.github.com/repos/${repo}/codeowners/errors`, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${token}`,
      'X-GitHub-Api-Version': '2022-11-28',
    },
  });
  const text = await response.text();
  let body = null;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = { message: text };
    }
  }
  return { status: response.status, body };
}

async function filePlan(plan, apiKey) {
  const upserted = await upsertLinearIssue({
    label: plan.label,
    identifier: plan.identifier,
    title: plan.title,
    description: plan.description,
    createStateName: plan.createStateName,
    reopenTerminal: plan.reopenTerminal,
    apiKey,
  });
  if (!upserted.ok) return upserted;
  console.log(`${upserted.action} ${upserted.identifier ?? ''} ${upserted.url ?? ''}`.trim());
  if (!upserted.id) return upserted;
  const listed = await listLinearIssueComments({ issueId: upserted.id, apiKey });
  const comments = listed.ok ? listed.comments : [];
  if (!shouldAddRepoComment(comments, plan.comment)) {
    console.log(`Skipped duplicate CODEOWNERS comment for ${plan.comment.split('\n')[0]}.`);
    return upserted;
  }
  const comment = await addLinearIssueComment({
    issueId: upserted.id,
    apiKey,
    body: plan.comment,
  });
  if (!comment.ok) return comment;
  return upserted;
}

async function main() {
  const repo = process.env.GITHUB_REPOSITORY || 'JovieInc/LogYourBody';
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repo)) {
    console.error('invalid GITHUB_REPOSITORY');
    process.exit(1);
  }
  const token = process.env.GH_TOKEN || process.env.GITHUB_TOKEN || '';
  const loaded = await fetchCodeownersErrors(repo, { token });
  const classification = classifyCodeowners(loaded);
  if (classification.kind === 'http_error') {
    console.error(`codeowners_http_${classification.status}`);
    process.exit(1);
  }
  const plan = planCodeownersIssue({
    repo,
    classification,
    runUrl: process.env.RUN_URL || '',
  });
  const live = codeownersFilingEnabled() && process.env.DRY_RUN !== 'true';
  if (!live) {
    const reason = codeownersFilingEnabled()
      ? 'DRY_RUN'
      : 'REMEDIATION_TRIGGERS_ENABLED is not true or LINEAR_API_KEY is unset';
    console.log(formatCodeownersDryRun(plan, { reason }));
    return;
  }
  if (!plan) {
    console.log('CODEOWNERS ok. No Linear issue filed.');
    return;
  }
  const result = await filePlan(plan, process.env.LINEAR_API_KEY);
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
