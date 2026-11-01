// Report and Linear delivery for the read-only signing expiry check.
// Asset reads stay in signing-expiry.mjs. This module does not create,
// revoke, rotate, or nuke signing material.

import {
  addLinearIssueComment,
  findTeamIdByKey,
  LYB_TEAM_KEY,
  noteFingerprintedIssueGreen,
  upsertLinearIssue,
} from './lib/linear-issue-intake.mjs';
import {
  assertPublicReport,
  daysUntil,
  DISTRIBUTION_TYPES,
  ESCALATE_DAYS,
  FINGERPRINT,
  RUNBOOK,
  SOURCE_WORKFLOW,
  WARN_DAYS,
} from './signing-expiry.mjs';

const KIND_LABEL = {
  'distribution-certificate': 'distribution certificate',
  'app-store-profile': 'app store profile',
  'asc-api-key': 'asc api key',
};

function certKey(certificate) {
  return `${certificate.certificateType}|${certificate.expirationDate}`;
}

function profileRows(assets, nowMs) {
  if (
    !assets?.profilesReadable ||
    !Array.isArray(assets.requiredBundleIds) ||
    assets.requiredBundleIds.length === 0
  ) {
    return [
      {
        kind: 'app-store-profile',
        bundleId: '',
        daysRemaining: 0,
        status: 'unreadable',
        embedded: [],
      },
    ];
  }
  return assets.requiredBundleIds.map((bundleId) => {
    const matches = (assets.profiles || []).filter((profile) => profile.bundleId === bundleId);
    if (matches.length === 0) {
      return {
        kind: 'app-store-profile',
        bundleId,
        daysRemaining: 0,
        status: 'missing',
        embedded: [],
      };
    }
    let best = null;
    let bestDays = null;
    for (const profile of matches) {
      const days = daysUntil(profile.expirationDate, nowMs);
      if (!best || (days !== null && (bestDays === null || days > bestDays))) {
        best = profile;
        bestDays = days;
      }
    }
    if (!best || bestDays === null) {
      return {
        kind: 'app-store-profile',
        bundleId,
        daysRemaining: 0,
        status: 'unreadable',
        embedded: [],
      };
    }
    const embedded = (best.certificateLink === 'ok' ? best.certificates || [] : [])
      .filter((certificate) => DISTRIBUTION_TYPES.has(certificate.certificateType))
      .map((certificate) => ({
        certificateType: certificate.certificateType,
        expirationDate: certificate.expirationDate,
        daysRemaining: daysUntil(certificate.expirationDate, nowMs),
      }));
    const linkOk =
      best.certificateLink === 'ok' &&
      embedded.length > 0 &&
      embedded.every((certificate) => certificate.daysRemaining !== null);
    return {
      kind: 'app-store-profile',
      bundleId,
      daysRemaining: bestDays,
      status: bestDays < 0 ? 'expired' : 'ok',
      embedded: linkOk ? embedded : [],
      certificateUnreadable: !linkOk,
    };
  });
}

function certificateRows(assets, profiles, nowMs) {
  if (!assets?.certificatesReadable) {
    return [
      {
        kind: 'distribution-certificate',
        certificateType: '',
        daysRemaining: 0,
        status: 'unreadable',
        unused: false,
      },
    ];
  }
  const inUse = [];
  const seenInUse = new Set();
  let linkUnreadable = false;
  for (const profile of profiles || []) {
    if (profile.status === 'missing' || profile.status === 'unreadable') continue;
    if (profile.certificateUnreadable || !profile.embedded?.length) {
      linkUnreadable = true;
      continue;
    }
    for (const certificate of profile.embedded) {
      const key = certKey(certificate);
      if (seenInUse.has(key)) continue;
      seenInUse.add(key);
      inUse.push({
        kind: 'distribution-certificate',
        certificateType: certificate.certificateType,
        daysRemaining: certificate.daysRemaining,
        status: certificate.daysRemaining < 0 ? 'expired' : 'ok',
        unused: false,
      });
    }
  }
  if (linkUnreadable) {
    inUse.unshift({
      kind: 'distribution-certificate',
      certificateType: '',
      daysRemaining: 0,
      status: 'unreadable',
      unused: false,
    });
  }
  const unused = [];
  const seenUnused = new Set();
  for (const certificate of assets.certificates || []) {
    if (!DISTRIBUTION_TYPES.has(certificate.certificateType)) continue;
    const daysRemaining = daysUntil(certificate.expirationDate, nowMs);
    // Expired leftovers that no required profile embeds do not drive the report.
    if (daysRemaining === null || daysRemaining < 0) continue;
    const key = certKey(certificate);
    if (seenInUse.has(key) || seenUnused.has(key)) continue;
    seenUnused.add(key);
    unused.push({
      kind: 'distribution-certificate',
      certificateType: certificate.certificateType,
      daysRemaining,
      status: 'ok',
      unused: true,
    });
  }
  inUse.sort((left, right) => left.daysRemaining - right.daysRemaining);
  unused.sort((left, right) => left.daysRemaining - right.daysRemaining);
  if (inUse.length === 0 && unused.length === 0) {
    return [
      {
        kind: 'distribution-certificate',
        certificateType: '',
        daysRemaining: 0,
        status: 'missing',
        unused: false,
      },
    ];
  }
  return [...inUse, ...unused];
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
  const profiles = profileRows(assets, nowMs);
  return [
    ...profiles,
    ...certificateRows(assets, profiles, nowMs),
    apiKeyRow(assets?.apiKey, nowMs),
  ];
}

export function severity(rows) {
  const days = (rows || [])
    .filter((row) => !row.unused)
    .map((row) => row.daysRemaining)
    .filter((value) => typeof value === 'number');
  if (days.length === 0) return 'ok';
  const soonest = Math.min(...days);
  if (soonest < ESCALATE_DAYS) return 'escalate';
  if (soonest < WARN_DAYS) return 'warn';
  return 'ok';
}

function describe(row) {
  if (row.kind === 'asc-api-key') {
    const label = KIND_LABEL['asc-api-key'];
    if (row.status === 'no-expiration') return `${label}: no expiration date`;
    if (row.status === 'unreadable' || row.status === 'rejected') return `${label}: unreadable`;
    return `${label}: ${row.daysRemaining} days`;
  }
  if (row.kind === 'app-store-profile') {
    const label = row.bundleId ? `${row.bundleId} IOS_APP_STORE` : 'app store profile';
    if (row.status === 'missing') return `${label}: missing`;
    if (row.status === 'unreadable') return `${label}: unreadable`;
    const certs = (row.embedded || [])
      .map((certificate) => `${certificate.certificateType}, ${certificate.daysRemaining} days`)
      .join('; ');
    const suffix = certs
      ? ` (${certs})`
      : row.certificateUnreadable
        ? ' (distribution certificate unreadable)'
        : '';
    return `${label}: ${row.daysRemaining} days${suffix}`;
  }
  const name = row.unused ? 'unused distribution certificate' : 'distribution certificate';
  const label = row.certificateType ? `${name} ${row.certificateType}` : name;
  if (row.status === 'missing') return `${label}: missing`;
  if (row.status === 'unreadable') return `${label}: unreadable`;
  return `${label}: ${row.daysRemaining} days`;
}

export function formatReport(rows) {
  return (rows || []).map((row) => describe(row)).join('\n');
}

function cell(value) {
  return String(value)
    .replaceAll('|', '\\|')
    .replace(/[\r\n]+/g, ' ');
}

export function renderSummary(rows, runUrl = '') {
  const level = severity(rows);
  const lines = (rows || []).map((row) => {
    const line = describe(row);
    const splitAt = line.indexOf(': ');
    const label = splitAt === -1 ? line : line.slice(0, splitAt);
    const days = splitAt === -1 ? '' : line.slice(splitAt + 2);
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
