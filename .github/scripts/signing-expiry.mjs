#!/usr/bin/env node
// Read-only signing expiry check (LYB-141).
// GETs distribution certificates, App Store profiles, and API-key auth.
// Never creates, revokes, rotates, or nukes signing material.
// Reports and Linear text contain only asset kind and days remaining.

import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { createToken } from './app-store-readiness.mjs';
import {
  findTeamIdByKey,
  LYB_TEAM_KEY,
  noteFingerprintedIssueGreen,
  upsertLinearIssue,
  addLinearIssueComment,
} from './lib/linear-issue-intake.mjs';

const API = 'https://api.appstoreconnect.apple.com';
export const WARN_DAYS = 30;
export const ESCALATE_DAYS = 7;
export const FINGERPRINT = 'remediation:signing-expiry';
export const SOURCE_WORKFLOW = '.github/workflows/signing-expiry.yml';
export const RUNBOOK = 'docs/engineering/signing-expiry.md';
export const APP_BUNDLE_ID = 'com.logyourbody.app';
const DISTRIBUTION_TYPES = new Set(['IOS_DISTRIBUTION', 'DISTRIBUTION']);
const DAY_MS = 86_400_000;
const MATERIAL =
  /certificateContent|profileContent|-----BEGIN [A-Z0-9 ]*(?:PRIVATE KEY|CERTIFICATE)-----|[A-Za-z0-9+/]{80,}={0,2}/;

const KIND_LABEL = {
  'distribution-certificate': 'distribution certificate',
  'app-store-profile': 'app store profile',
  'asc-api-key': 'asc api key',
};

export class AscReadError extends Error {
  constructor(status) {
    super('ASC read failed');
    this.status = Number.isInteger(status) ? status : 0;
  }
}

export function secretValues(env) {
  const names = [
    'ASC_KEY_ID',
    'ASC_ISSUER_ID',
    'ASC_PRIVATE_KEY',
    'APP_STORE_CONNECT_API_KEY_ID',
    'APP_STORE_CONNECT_API_KEY_ISSUER_ID',
    'APP_STORE_CONNECT_API_ISSUER_ID',
    'APP_STORE_CONNECT_API_KEY',
    'MATCH_PASSWORD',
    'MATCH_GIT_BASIC_AUTHORIZATION',
    'MATCH_GIT_URL',
  ];
  return names
    .map((name) => env?.[name])
    .filter((value) => typeof value === 'string' && value.length >= 8);
}

export function assertPublicReport(text, forbidden = []) {
  const value = String(text ?? '');
  if (MATERIAL.test(value) || forbidden.some((secret) => secret && value.includes(secret))) {
    throw new Error('signing expiry report withheld');
  }
}

export function daysUntil(expirationDate, nowMs) {
  if (typeof expirationDate !== 'string' || !expirationDate.trim()) return null;
  const expiry = Date.parse(expirationDate);
  if (!Number.isFinite(expiry)) return null;
  return Math.floor((expiry - nowMs) / DAY_MS);
}

export function assertSparseQuery(query) {
  for (const [key, value] of Object.entries(query || {})) {
    if (/certificateContent|profileContent|secret/i.test(`${key}=${value}`)) {
      throw new Error('refusing to request signing material');
    }
  }
}

function nextPathFrom(link) {
  if (!link) return '';
  try {
    const url = new URL(link, API);
    if (url.origin !== API || url.username || url.password) return '';
    const path = `${url.pathname}${url.search}`;
    if (/certificateContent|profileContent/i.test(path)) throw new AscReadError(0);
    return path;
  } catch (error) {
    if (error instanceof AscReadError) throw error;
    return '';
  }
}

export function createSigningClient(env, fetcher = fetch) {
  const token = createToken(env);

  async function getOne(path, query) {
    assertSparseQuery(query);
    const url = new URL(path, API);
    if (url.origin !== API || url.username || url.password) throw new AscReadError(0);
    for (const [key, value] of Object.entries(query || {}))
      url.searchParams.set(key, String(value));
    let response;
    try {
      response = await fetcher(url, {
        method: 'GET',
        redirect: 'error',
        signal: AbortSignal.timeout(30_000),
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      });
    } catch {
      throw new AscReadError(0);
    }
    if (response.status !== 200) throw new AscReadError(response.status);
    const text = await response.text();
    if (!text) return { data: [] };
    try {
      const body = JSON.parse(text);
      return body && typeof body === 'object' ? body : { data: [] };
    } catch {
      throw new AscReadError(0);
    }
  }

  return {
    async getAll(path, query) {
      const data = [];
      const included = [];
      const seen = new Set();
      let nextPath = path;
      let nextQuery = query;
      for (let page = 0; page < 5 && nextPath; page += 1) {
        if (seen.has(nextPath)) throw new AscReadError(0);
        seen.add(nextPath);
        const body = await getOne(nextPath, nextQuery);
        if (Array.isArray(body.data)) data.push(...body.data);
        if (Array.isArray(body.included)) included.push(...body.included);
        nextPath = nextPathFrom(body.links?.next);
        nextQuery = {};
      }
      return { data, included };
    },
  };
}

export function projectCertificates(body) {
  return (Array.isArray(body?.data) ? body.data : []).map((record) => ({
    certificateType:
      typeof record?.attributes?.certificateType === 'string'
        ? record.attributes.certificateType
        : '',
    expirationDate:
      typeof record?.attributes?.expirationDate === 'string'
        ? record.attributes.expirationDate
        : '',
  }));
}

function bundleIdentifier(record, included) {
  const id = record?.relationships?.bundleId?.data?.id;
  if (!id) return '';
  const match = (included || []).find((item) => item?.type === 'bundleIds' && item.id === id);
  return typeof match?.attributes?.identifier === 'string' ? match.attributes.identifier : '';
}

export function projectProfiles(body, bundleId = APP_BUNDLE_ID) {
  const included = Array.isArray(body?.included) ? body.included : [];
  const profiles = [];
  for (const record of Array.isArray(body?.data) ? body.data : []) {
    const profileType = record?.attributes?.profileType;
    const profileState = record?.attributes?.profileState;
    if (profileType !== 'IOS_APP_STORE') continue;
    if (profileState && profileState !== 'ACTIVE') continue;
    const identifier = bundleIdentifier(record, included);
    if (identifier && identifier !== bundleId && !identifier.startsWith(`${bundleId}.`)) continue;
    profiles.push({
      profileType: 'IOS_APP_STORE',
      profileState: profileState || 'ACTIVE',
      expirationDate:
        typeof record?.attributes?.expirationDate === 'string'
          ? record.attributes.expirationDate
          : '',
    });
  }
  return profiles;
}

const CERTIFICATE_QUERY = {
  'fields[certificates]': 'certificateType,expirationDate',
  limit: '200',
};

const PROFILE_QUERY = {
  'filter[profileType]': 'IOS_APP_STORE',
  'filter[profileState]': 'ACTIVE',
  'fields[profiles]': 'profileType,profileState,expirationDate',
  limit: '200',
};

export async function loadSigningAssets(client) {
  const assets = {
    certificates: [],
    profiles: [],
    certificatesReadable: false,
    profilesReadable: false,
    apiKey: { authenticated: false, expirationDate: null },
  };
  let certificates;
  try {
    certificates = await client.getAll('/v1/certificates', CERTIFICATE_QUERY);
  } catch {
    return assets;
  }
  // One successful read proves the team API key still authenticates.
  // Apple does not put an expiration date on that key.
  assets.apiKey = { authenticated: true, expirationDate: null };
  assets.certificates = projectCertificates(certificates).filter((certificate) =>
    DISTRIBUTION_TYPES.has(certificate.certificateType),
  );
  assets.certificatesReadable = true;

  const profileQueries = [
    { ...PROFILE_QUERY, include: 'bundleId', 'fields[bundleIds]': 'identifier' },
    PROFILE_QUERY,
  ];
  for (const query of profileQueries) {
    try {
      assets.profiles = projectProfiles(await client.getAll('/v1/profiles', query));
      assets.profilesReadable = true;
      break;
    } catch {
      assets.profilesReadable = false;
    }
  }
  return assets;
}

function distributionRow(certificates, nowMs) {
  const dated = (certificates || [])
    .filter((certificate) => DISTRIBUTION_TYPES.has(certificate.certificateType))
    .map((certificate) => daysUntil(certificate.expirationDate, nowMs))
    .filter((days) => days !== null);
  const valid = dated.filter((days) => days >= 0);
  // An already-expired leftover must not hide a newer valid distribution cert.
  if (valid.length > 0) {
    return {
      kind: 'distribution-certificate',
      daysRemaining: Math.min(...valid),
      status: 'ok',
      count: valid.length,
    };
  }
  if (dated.length > 0) {
    return {
      kind: 'distribution-certificate',
      daysRemaining: Math.max(...dated),
      status: 'expired',
      count: dated.length,
    };
  }
  return { kind: 'distribution-certificate', daysRemaining: 0, status: 'missing', count: 0 };
}

function profileRows(profiles, nowMs) {
  const rows = (profiles || []).map((profile) => {
    const days = daysUntil(profile.expirationDate, nowMs);
    if (days === null) {
      return { kind: 'app-store-profile', daysRemaining: 0, status: 'unreadable', count: 1 };
    }
    return {
      kind: 'app-store-profile',
      daysRemaining: days,
      status: days < 0 ? 'expired' : 'ok',
      count: 1,
    };
  });
  rows.sort((left, right) => left.daysRemaining - right.daysRemaining);
  if (rows.length === 0) {
    return [{ kind: 'app-store-profile', daysRemaining: 0, status: 'missing', count: 0 }];
  }
  return rows;
}

function apiKeyRow(apiKey, nowMs) {
  if (!apiKey?.authenticated) {
    return { kind: 'asc-api-key', daysRemaining: 0, status: 'rejected', count: 0 };
  }
  if (typeof apiKey.expirationDate === 'string' && apiKey.expirationDate) {
    const days = daysUntil(apiKey.expirationDate, nowMs);
    if (days === null)
      return { kind: 'asc-api-key', daysRemaining: 0, status: 'unreadable', count: 1 };
    return {
      kind: 'asc-api-key',
      daysRemaining: days,
      status: days < 0 ? 'expired' : 'ok',
      count: 1,
    };
  }
  return { kind: 'asc-api-key', daysRemaining: null, status: 'no-expiration', count: 1 };
}

export function buildSigningRows(assets, nowMs) {
  return [
    assets?.certificatesReadable
      ? distributionRow(assets.certificates, nowMs)
      : { kind: 'distribution-certificate', daysRemaining: 0, status: 'unreadable', count: 0 },
    ...(assets?.profilesReadable
      ? profileRows(assets.profiles, nowMs)
      : [{ kind: 'app-store-profile', daysRemaining: 0, status: 'unreadable', count: 0 }]),
    apiKeyRow(assets?.apiKey, nowMs),
  ];
}

export function severity(rows) {
  const days = (rows || [])
    .map((row) => row.daysRemaining)
    .filter((value) => typeof value === 'number');
  if (days.length === 0) return 'ok';
  const soonest = Math.min(...days);
  if (soonest < ESCALATE_DAYS) return 'escalate';
  if (soonest < WARN_DAYS) return 'warn';
  return 'ok';
}

export function formatReport(rows) {
  const countableProfiles = (rows || []).filter(
    (row) =>
      row.kind === 'app-store-profile' && row.status !== 'missing' && row.status !== 'unreadable',
  ).length;
  let profileOrdinal = 0;
  return (rows || [])
    .map((row) => {
      const label = KIND_LABEL[row.kind] || 'signing asset';
      if (row.status === 'no-expiration') return `${label}: no expiration date`;
      if (row.status === 'missing') return `${label}: missing`;
      if (row.status === 'unreadable' || row.status === 'rejected') return `${label}: unreadable`;
      if (row.kind === 'app-store-profile' && countableProfiles > 1) {
        profileOrdinal += 1;
        return `${label} ${profileOrdinal}: ${row.daysRemaining} days`;
      }
      if (row.kind === 'distribution-certificate' && row.count > 1 && row.daysRemaining >= 0) {
        return `${label}: ${row.daysRemaining} days (${row.count} valid)`;
      }
      return `${label}: ${row.daysRemaining} days`;
    })
    .join('\n');
}

function cell(value) {
  return String(value)
    .replaceAll('|', '\\|')
    .replace(/[\r\n]+/g, ' ');
}

export function renderSummary(rows, runUrl = '') {
  const level = severity(rows);
  const lines = (rows || []).map((row) => {
    const label = KIND_LABEL[row.kind] || 'signing asset';
    let days = `${row.daysRemaining} days`;
    if (row.status === 'no-expiration') days = 'no expiration date';
    else if (row.status === 'missing') days = 'missing';
    else if (row.status === 'unreadable' || row.status === 'rejected') days = 'unreadable';
    return `| ${cell(label)} | ${cell(days)} |`;
  });
  return [
    '## Signing expiry',
    '',
    'Read-only App Store Connect check. No certificate or profile was created, revoked, or nuked.',
    '',
    '| Asset | Days |',
    '| --- | --- |',
    ...lines,
    '',
    `Severity: ${level}.`,
    `Runbook: ${RUNBOOK}.`,
    runUrl ? `Run: ${runUrl}` : '',
    '',
  ]
    .filter((line) => line !== '')
    .join('\n')
    .concat('\n');
}

export function buildIssue(rows, runUrl = '') {
  const level = severity(rows);
  if (level === 'ok') return null;
  const urgent = level === 'escalate';
  const report = formatReport(rows);
  const run = runUrl || '(run URL unavailable)';
  return {
    fingerprint: FINGERPRINT,
    label: FINGERPRINT,
    title: urgent
      ? `ESCALATED: signing expiry under 7 days (${FINGERPRINT})`
      : `Signing expiry under 30 days (${FINGERPRINT})`,
    description: [
      'Signing expiry check. This run only read App Store Connect. It did not create, revoke, rotate, or nuke certificates or profiles.',
      '',
      report,
      '',
      urgent
        ? 'ESCALATED: at least one monitored asset is under 7 days, missing, or unreadable.'
        : 'At least one monitored asset is under 30 days.',
      `Renew with match before nuke. Runbook: ${RUNBOOK}.`,
      'Do not start regenerate-certificates.yml unless that refresh cannot produce a usable distribution certificate. The nuke workflow is manual and requires confirm NUKE-AND-REGENERATE.',
      '',
      `Source-workflow: ${SOURCE_WORKFLOW}`,
      `Run: ${run}`,
    ].join('\n'),
    priority: urgent ? 1 : 2,
    createStateName: 'Todo',
    reopenTerminal: true,
    teamKey: LYB_TEAM_KEY,
  };
}

const defaultLinear = {
  async findTeam(apiKey) {
    return findTeamIdByKey({ teamKey: LYB_TEAM_KEY, apiKey });
  },
  async upsert(plan) {
    return upsertLinearIssue(plan);
  },
  async comment(input) {
    return addLinearIssueComment(input);
  },
  async resolve({ apiKey, teamId }) {
    return noteFingerprintedIssueGreen({
      fingerprint: FINGERPRINT,
      source: SOURCE_WORKFLOW,
      comment: 'Signing expiry check is clear. Monitored assets are at least 30 days out.',
      teamId,
      apiKey,
    });
  },
};

export async function deliverSigningExpiry({
  rows,
  runUrl = '',
  dryRun = false,
  linearApiKey = '',
  forbidden = [],
  linear = defaultLinear,
}) {
  const report = formatReport(rows);
  const summary = renderSummary(rows, runUrl);
  const issue = buildIssue(rows, runUrl);
  const commentBody = issue?.priority === 1 ? `ESCALATED\n\n${report}` : report;
  assertPublicReport(
    `${report}\n${summary}\n${issue?.title ?? ''}\n${issue?.description ?? ''}\n${commentBody}`,
    forbidden,
  );

  if (dryRun) {
    return {
      exitCode: 0,
      report,
      summary,
      log: issue
        ? `dry_run: would upsert ${FINGERPRINT} priority ${issue.priority}`
        : `dry_run: clear ${FINGERPRINT}`,
    };
  }

  if (!issue) {
    if (!linearApiKey) return { exitCode: 0, report, summary, log: `clear ${FINGERPRINT}` };
    const team = await linear.findTeam(linearApiKey);
    if (!team.ok) {
      return {
        exitCode: 0,
        report,
        summary,
        log: `clear ${FINGERPRINT}; linear resolve skipped (${team.reason || 'linear_team_lookup_failed'})`,
      };
    }
    const resolved = await linear.resolve({ apiKey: linearApiKey, teamId: team.id });
    const action = resolved.ok
      ? resolved.action || 'resolved'
      : resolved.reason || 'linear_resolve_failed';
    return { exitCode: 0, report, summary, log: `clear ${FINGERPRINT}; ${action}` };
  }

  if (!linearApiKey) {
    return {
      exitCode: 1,
      report,
      summary,
      log: 'LINEAR_API_KEY is missing. Signing expiry was not filed.',
    };
  }
  const team = await linear.findTeam(linearApiKey);
  if (!team.ok) {
    return { exitCode: 1, report, summary, log: team.reason || 'linear_team_lookup_failed' };
  }
  const upserted = await linear.upsert({ ...issue, teamId: team.id, apiKey: linearApiKey });
  if (!upserted.ok)
    return { exitCode: 1, report, summary, log: upserted.reason || 'linear_upsert_failed' };
  if (upserted.id && (issue.priority === 1 || upserted.action === 'created' || upserted.reopened)) {
    const comment = await linear.comment({
      issueId: upserted.id,
      apiKey: linearApiKey,
      body: commentBody,
    });
    if (!comment.ok)
      return { exitCode: 1, report, summary, log: comment.reason || 'linear_comment_failed' };
  }
  const identifier = upserted.identifier || '';
  return {
    exitCode: 0,
    report,
    summary,
    log: `${upserted.action || 'upserted'} ${identifier} ${FINGERPRINT}`.trim(),
  };
}

async function main() {
  const forbidden = secretValues(process.env);
  const runUrl =
    process.env.RUN_URL ||
    (process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
      ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
      : '');
  let rows;
  try {
    rows = buildSigningRows(await loadSigningAssets(createSigningClient(process.env)), Date.now());
  } catch {
    rows = buildSigningRows(
      {
        certificatesReadable: false,
        profilesReadable: false,
        apiKey: { authenticated: false, expirationDate: null },
      },
      Date.now(),
    );
  }
  let delivery;
  try {
    delivery = await deliverSigningExpiry({
      rows,
      runUrl,
      dryRun: process.env.DRY_RUN === 'true',
      linearApiKey: process.env.LINEAR_API_KEY || '',
      forbidden,
    });
  } catch {
    console.error('signing expiry report withheld');
    process.exitCode = 1;
    return;
  }
  if (process.env.GITHUB_STEP_SUMMARY)
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, delivery.summary);
  console.log(delivery.report);
  console.log(delivery.log);
  if (delivery.exitCode !== 0) process.exitCode = delivery.exitCode;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
