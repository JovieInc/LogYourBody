#!/usr/bin/env node
// Read-only signing expiry check (LYB-141, LYB-332).
// GETs distribution certificates, the App Store profiles Matchfile requires,
// and API-key auth. Never creates, revokes, rotates, or nukes signing material.
// Reports and Linear text name bundle IDs and certificate types only.

import { appendFileSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createToken } from './app-store-readiness.mjs';

const API = 'https://api.appstoreconnect.apple.com';
export const WARN_DAYS = 30;
export const ESCALATE_DAYS = 7;
export const FINGERPRINT = 'remediation:signing-expiry';
export const SOURCE_WORKFLOW = '.github/workflows/signing-expiry.yml';
export const RUNBOOK = 'docs/engineering/signing-expiry.md';
export const APP_BUNDLE_ID = 'com.logyourbody.app';
export const MATCHFILE_PATH = join(
  dirname(fileURLToPath(import.meta.url)),
  '../../apps/ios/fastlane/Matchfile',
);
export const DISTRIBUTION_TYPES = new Set(['IOS_DISTRIBUTION', 'DISTRIBUTION']);
const BUNDLE_ID = /^[A-Za-z0-9.-]{1,200}$/;
const DAY_MS = 86_400_000;
const MATERIAL =
  /certificateContent|profileContent|-----BEGIN [A-Z0-9 ]*(?:PRIVATE KEY|CERTIFICATE)-----|[A-Za-z0-9+/]{80,}={0,2}/;

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

// Matchfile app_identifier is the source of truth for the bundle IDs release
// signing must have a profile for. Fastfile.release's readonly match call can
// temporarily omit one (LYB-310); that omission must not hide a missing profile.
export function parseRequiredBundleIds(source) {
  const code = String(source ?? '')
    .split('\n')
    .filter((line) => !line.trim().startsWith('#'))
    .join('\n');
  const match = code.match(/app_identifier\s*\(\s*(\[[\s\S]*?\]|"[^"]*"|'[^']*')\s*\)/);
  if (!match) return [];
  const ids = [];
  const quoted = /"([^"]*)"|'([^']*)'/g;
  for (let found = quoted.exec(match[1]); found; found = quoted.exec(match[1])) {
    const id = (found[1] ?? found[2] ?? '').trim();
    if (BUNDLE_ID.test(id)) ids.push(id);
  }
  return [...new Set(ids)];
}

export function readRequiredBundleIds(matchfilePath = MATCHFILE_PATH, readFile = readFileSync) {
  return parseRequiredBundleIds(readFile(matchfilePath, 'utf8'));
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

function indexCertificates(body, index = new Map()) {
  const records = [
    ...(Array.isArray(body?.data) ? body.data : []),
    ...(Array.isArray(body?.included) ? body.included : []),
  ];
  for (const record of records) {
    if (record?.type && record.type !== 'certificates') continue;
    if (!record?.id || index.has(record.id)) continue;
    index.set(record.id, {
      certificateType:
        typeof record?.attributes?.certificateType === 'string'
          ? record.attributes.certificateType
          : '',
      expirationDate:
        typeof record?.attributes?.expirationDate === 'string'
          ? record.attributes.expirationDate
          : '',
    });
  }
  return index;
}

function embeddedDistributionCerts(record, index) {
  const links = record?.relationships?.certificates?.data;
  if (!Array.isArray(links)) return { certificateLink: 'unreadable', certificates: [] };
  const certificates = [];
  let unresolved = false;
  for (const link of links) {
    const id = typeof link?.id === 'string' ? link.id : '';
    const certificate = id ? index.get(id) : undefined;
    if (!certificate) {
      unresolved = true;
      continue;
    }
    if (!DISTRIBUTION_TYPES.has(certificate.certificateType)) continue;
    certificates.push({
      certificateType: certificate.certificateType,
      expirationDate: certificate.expirationDate,
    });
  }
  if (unresolved || certificates.length === 0) {
    return { certificateLink: 'unreadable', certificates: [] };
  }
  return { certificateLink: 'ok', certificates };
}

export function projectProfiles(body, requiredBundleIds = [], certificateIndex = new Map()) {
  const included = Array.isArray(body?.included) ? body.included : [];
  const index = indexCertificates(
    body,
    certificateIndex instanceof Map ? certificateIndex : new Map(),
  );
  const required = new Set(requiredBundleIds || []);
  const profiles = [];
  for (const record of Array.isArray(body?.data) ? body.data : []) {
    const profileType = record?.attributes?.profileType;
    const profileState = record?.attributes?.profileState;
    if (profileType !== 'IOS_APP_STORE') continue;
    if (profileState && profileState !== 'ACTIVE') continue;
    const identifier = bundleIdentifier(record, included);
    if (!identifier || !required.has(identifier)) continue;
    const embedded = embeddedDistributionCerts(record, index);
    profiles.push({
      bundleId: identifier,
      profileType: 'IOS_APP_STORE',
      profileState: profileState || 'ACTIVE',
      expirationDate:
        typeof record?.attributes?.expirationDate === 'string'
          ? record.attributes.expirationDate
          : '',
      certificateLink: embedded.certificateLink,
      certificates: embedded.certificates,
    });
  }
  return profiles;
}

function bodyHasBundleIdentifier(body) {
  const included = Array.isArray(body?.included) ? body.included : [];
  return (Array.isArray(body?.data) ? body.data : []).some((record) =>
    bundleIdentifier(record, included),
  );
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

export async function loadSigningAssets(client, requiredBundleIds = []) {
  const assets = {
    certificates: [],
    profiles: [],
    certificatesReadable: false,
    profilesReadable: false,
    requiredBundleIds: Array.isArray(requiredBundleIds) ? requiredBundleIds : [],
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
  const certificateIndex = indexCertificates(certificates);
  assets.certificates = projectCertificates(certificates).filter((certificate) =>
    DISTRIBUTION_TYPES.has(certificate.certificateType),
  );
  assets.certificatesReadable = true;

  const profileQueries = [
    {
      ...PROFILE_QUERY,
      include: 'bundleId,certificates',
      'fields[bundleIds]': 'identifier',
      'fields[certificates]': 'certificateType,expirationDate',
    },
    { ...PROFILE_QUERY, include: 'bundleId', 'fields[bundleIds]': 'identifier' },
    PROFILE_QUERY,
  ];
  for (const query of profileQueries) {
    try {
      const body = await client.getAll('/v1/profiles', query);
      indexCertificates(body, certificateIndex);
      const projected = projectProfiles(body, assets.requiredBundleIds, certificateIndex);
      const rawCount = Array.isArray(body?.data) ? body.data.length : 0;
      if (rawCount > 0 && projected.length === 0 && !bodyHasBundleIdentifier(body)) continue;
      assets.profiles = projected;
      assets.profilesReadable = true;
      break;
    } catch {
      assets.profilesReadable = false;
    }
  }
  return assets;
}

async function main() {
  const { buildSigningRows, deliverSigningExpiry } = await import('./signing-expiry-report.mjs');
  const forbidden = secretValues(process.env);
  const runUrl =
    process.env.RUN_URL ||
    (process.env.GITHUB_SERVER_URL && process.env.GITHUB_REPOSITORY && process.env.GITHUB_RUN_ID
      ? `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`
      : '');
  let requiredBundleIds = [];
  let requiredBundleIdsReadable = true;
  try {
    requiredBundleIds = readRequiredBundleIds();
    if (requiredBundleIds.length === 0) requiredBundleIdsReadable = false;
  } catch {
    requiredBundleIdsReadable = false;
  }
  let rows;
  try {
    const loaded = await loadSigningAssets(createSigningClient(process.env), requiredBundleIds);
    if (!requiredBundleIdsReadable) loaded.profilesReadable = false;
    rows = buildSigningRows(loaded, Date.now());
  } catch {
    rows = buildSigningRows(
      {
        certificatesReadable: false,
        profilesReadable: false,
        requiredBundleIds: [],
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
