#!/usr/bin/env node
// Pull-request gate for release signing (LYB-333).
// Reads the bundle ids Fastfile.release passes to readonly appstore match,
// then GETs App Store Connect. Fails when a required id is unregistered,
// has no active IOS_APP_STORE profile, or that profile lacks an entitlement
// the target needs. Never creates certificates or profiles, and never prints
// key ids, bundle ids, team ids, or profile bytes.

import { spawnSync } from 'node:child_process';
import { appendFileSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createToken } from './app-store-readiness.mjs';

const API = 'https://api.appstoreconnect.apple.com';
export const RUNBOOK = 'docs/engineering/signing-expiry.md';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const RELEASE_FILE = path.join(ROOT, 'apps/ios/fastlane/Fastfile.release');
const PROJECT_FILE = path.join(ROOT, 'apps/ios/LogYourBody.xcodeproj/project.pbxproj');
const RUBY_SCRIPT = fileURLToPath(new URL('./release-match-identifiers.rb', import.meta.url));
const MATERIAL =
  /certificateContent|profileContent|-----BEGIN [A-Z0-9 ]*(?:PRIVATE KEY|CERTIFICATE)-----|[A-Za-z0-9+/]{80,}={0,2}/;

const PLIST_SCRIPT = `
import json, plistlib, sys
raw = sys.stdin.buffer.read()
start = raw.find(b"<?xml")
end = raw.find(b"</plist>")
if start < 0 or end < 0:
    sys.exit(2)
try:
    doc = plistlib.loads(raw[start:end + len(b"</plist>")])
except Exception:
    sys.exit(2)
if not isinstance(doc, dict):
    sys.exit(2)
payload = doc["Entitlements"] if "Entitlements" in doc else doc
if not isinstance(payload, dict):
    sys.exit(2)

def norm(value):
    if isinstance(value, bool) or isinstance(value, str):
        return value
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return value
    raise ValueError("unsupported")

try:
    json.dump({key: norm(value) for key, value in payload.items()}, sys.stdout)
except ValueError:
    sys.exit(2)
`;

export class AscReadError extends Error {
  constructor() {
    super('ASC read failed');
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
    'GITHUB_TOKEN',
  ];
  return names
    .map((name) => env?.[name])
    .filter((value) => typeof value === 'string' && value.length >= 8);
}

export function assertPublicText(text, forbidden = []) {
  const value = String(text ?? '');
  if (MATERIAL.test(value) || forbidden.some((secret) => secret && value.includes(secret))) {
    throw new Error('release signing report withheld');
  }
}

export function credentialGate({ fork, hasSecrets }) {
  if (fork) return 'neutral';
  if (!hasSecrets) return 'missing-credentials';
  return 'run';
}

export function neutralMessage() {
  return [
    'Neutral. This fork pull request has no App Store Connect credentials.',
    'The release signing check did not read Apple and did not pass.',
    'Provisioning a new signed target is a step for Tim.',
    `Runbook: ${RUNBOOK}`,
  ].join('\n');
}

export function missingCredentialsMessage() {
  return [
    'Release signing was not read.',
    'This pull request is from this repository and App Store Connect credentials are unavailable, so the check failed closed.',
    'Provisioning a signed target is a step for Tim.',
    `Runbook: ${RUNBOOK}`,
  ].join('\n');
}

export function failureMessage(findings) {
  if (findings.length > 0 && findings.every((finding) => finding.reason === 'unreadable')) {
    return [
      'Release signing was not read.',
      'This is a provisioning step for Tim. The check could not confirm an active App Store profile for a target the readonly release lane requests.',
      `Runbook: ${RUNBOOK}`,
    ].join('\n');
  }
  const lines = [
    'Release signing is not provisioned.',
    'This is a provisioning step for Tim. Readonly match cannot create the missing bundle ID or App Store profile.',
    `Runbook: ${RUNBOOK}`,
  ];
  if (findings.some((finding) => finding.reason === 'bundle-id')) {
    lines.push('A required release target has no registered bundle ID.');
  }
  if (findings.some((finding) => finding.reason === 'profile')) {
    lines.push('A required release target has no active App Store profile.');
  }
  if (findings.some((finding) => finding.reason === 'unreadable')) {
    lines.push('A required release profile could not be read.');
  }
  const capabilities = [
    ...new Set(findings.flatMap((finding) => finding.missingCapabilities || [])),
  ].sort();
  if (capabilities.length > 0) {
    lines.push(
      `A required release profile is missing a capability the target entitlements need: ${capabilities.join(', ')}.`,
    );
  }
  return lines.join('\n');
}

export function successMessage() {
  return [
    'Release signing is provisioned for every target the readonly release lane requests.',
    'Read-only App Store Connect check. No certificate or profile was created.',
    `Runbook: ${RUNBOOK}`,
  ].join('\n');
}

const WITHHELD = [
  'Release signing report withheld.',
  'This is a provisioning step for Tim.',
  `Runbook: ${RUNBOOK}`,
].join('\n');

export function capabilityGaps(required, actual) {
  const entries = Object.entries(required || {}).filter(([, value]) => {
    if (value === true || (typeof value === 'string' && value.length > 0)) return true;
    return Array.isArray(value) && value.length > 0;
  });
  if (entries.length === 0) return [];
  if (!actual || typeof actual !== 'object' || Array.isArray(actual)) return null;
  const gaps = [];
  for (const [key, value] of entries) {
    if (value === true) {
      if (actual[key] !== true) gaps.push(key);
    } else if (typeof value === 'string' && value.length > 0) {
      if (actual[key] !== value) gaps.push(key);
    } else if (Array.isArray(value) && value.length > 0) {
      const got = Array.isArray(actual[key]) ? actual[key] : [];
      if (!value.every((item) => got.includes(item))) gaps.push(key);
    }
  }
  return gaps;
}

export function inspectReleaseSigning({ bundleIds, entitlementsByBundleId, catalog }) {
  const registered = new Set(catalog?.bundleIdentifiers || []);
  const profiles = Array.isArray(catalog?.profiles) ? catalog.profiles : [];
  const findings = [];
  for (const bundleId of bundleIds || []) {
    if (!registered.has(bundleId)) {
      findings.push({ reason: 'bundle-id' });
      continue;
    }
    const own = profiles.filter((profile) => profile?.bundleId === bundleId && profile.usable !== false);
    if (own.length === 0) {
      findings.push({ reason: 'profile' });
      continue;
    }
    const required = entitlementsByBundleId?.[bundleId] || {};
    const checks = own.map((profile) => capabilityGaps(required, profile.entitlements));
    if (checks.some((gaps) => Array.isArray(gaps) && gaps.length === 0)) continue;
    if (checks.every((gaps) => gaps === null)) {
      findings.push({ reason: 'unreadable' });
      continue;
    }
    const readable = checks.filter((gaps) => Array.isArray(gaps));
    const fewest = readable.reduce((best, gaps) => (gaps.length < best.length ? gaps : best));
    findings.push({ reason: 'capability', missingCapabilities: fewest });
  }
  return findings;
}

function matchingBrace(text, open) {
  let depth = 0;
  let quote = false;
  for (let index = open; index < text.length; index += 1) {
    const char = text[index];
    if (quote) {
      if (char === '\\') {
        index += 1;
        continue;
      }
      if (char === '"') quote = false;
      continue;
    }
    if (char === '"') {
      quote = true;
      continue;
    }
    if (char === '{') depth += 1;
    else if (char === '}') {
      depth -= 1;
      if (depth === 0) return index;
    }
  }
  throw new Error('project file unreadable');
}

export function releaseTargetsFromProject(text) {
  const targets = [];
  let cursor = 0;
  while (cursor < text.length) {
    const marker = text.indexOf('isa = XCBuildConfiguration;', cursor);
    if (marker < 0) break;
    const open = text.lastIndexOf('{', marker);
    if (open < 0) break;
    const close = matchingBrace(text, open);
    const block = text.slice(open, close + 1);
    cursor = close + 1;
    if (!/\bname = Release;/.test(block)) continue;
    const bundle = block.match(/PRODUCT_BUNDLE_IDENTIFIER = "?([^";]+)"?;/);
    if (!bundle) continue;
    const entitlements = block.match(/CODE_SIGN_ENTITLEMENTS = "?([^";]+)"?;/);
    const bundleId = bundle[1].trim();
    const entitlementsPath = entitlements ? entitlements[1].trim() : '';
    if (!bundleId || bundleId.includes('$(')) continue;
    targets.push({ bundleId, entitlementsPath });
  }
  return targets;
}

function iosPath(root, relativePath) {
  if (!relativePath || relativePath.includes('..') || path.isAbsolute(relativePath)) return '';
  const full = path.resolve(root, 'apps/ios', relativePath);
  const base = path.resolve(root, 'apps/ios');
  if (full !== base && !full.startsWith(`${base}${path.sep}`)) return '';
  return full;
}

export function parseEntitlements(buffer) {
  const result = spawnSync('python3', ['-c', PLIST_SCRIPT], {
    input: buffer,
    encoding: 'utf8',
    timeout: 10_000,
  });
  if (result.status !== 0 || !result.stdout) return null;
  try {
    const parsed = JSON.parse(result.stdout);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function loadReleaseEntitlements(root, bundleIds, projectText) {
  const text = projectText ?? readFileSync(path.join(root, 'apps/ios/LogYourBody.xcodeproj/project.pbxproj'), 'utf8');
  const pathsById = new Map();
  for (const target of releaseTargetsFromProject(text)) {
    const paths = pathsById.get(target.bundleId) || [];
    if (target.entitlementsPath) paths.push(target.entitlementsPath);
    pathsById.set(target.bundleId, paths);
  }
  const entitlementsByBundleId = {};
  for (const bundleId of bundleIds) {
    const merged = {};
    for (const relativePath of pathsById.get(bundleId) || []) {
      const full = iosPath(root, relativePath);
      if (!full) return null;
      let parsed;
      try {
        parsed = parseEntitlements(readFileSync(full));
      } catch {
        return null;
      }
      if (!parsed) return null;
      for (const [key, value] of Object.entries(parsed)) {
        if (Array.isArray(value) && Array.isArray(merged[key])) {
          merged[key] = [...new Set([...merged[key], ...value])];
        } else if (merged[key] !== true) {
          merged[key] = value;
        }
      }
    }
    entitlementsByBundleId[bundleId] = merged;
  }
  return entitlementsByBundleId;
}

export function releaseBundleIds(releaseFile, ruby = 'ruby') {
  const result = spawnSync(ruby, [RUBY_SCRIPT, releaseFile], {
    encoding: 'utf8',
    timeout: 20_000,
    env: {
      PATH: process.env.PATH || '',
      HOME: process.env.HOME || '',
      LANG: 'C',
      LC_ALL: 'C',
    },
  });
  if (result.status !== 0) throw new Error('release signing identifiers unreadable');
  let ids;
  try {
    ids = JSON.parse(result.stdout);
  } catch {
    throw new Error('release signing identifiers unreadable');
  }
  if (!Array.isArray(ids) || ids.length === 0 || ids.some((id) => typeof id !== 'string' || !id.trim())) {
    throw new Error('release signing identifiers unreadable');
  }
  return ids;
}

function nextPathFrom(link) {
  if (!link) return '';
  try {
    const url = new URL(link, API);
    if (url.origin !== API || url.username || url.password) return '';
    if (!/^\/v1\/(bundleIds|profiles)(\/|$)/.test(url.pathname)) return '';
    if (/certificateContent/i.test(`${url.pathname}${url.search}`)) throw new AscReadError();
    return `${url.pathname}${url.search}`;
  } catch (error) {
    if (error instanceof AscReadError) throw error;
    return '';
  }
}

export function createReleaseClient(env, fetcher = fetch) {
  const token = createToken(env);

  async function getOne(requestPath, query) {
    const url = new URL(requestPath, API);
    if (url.origin !== API || url.username || url.password) throw new AscReadError();
    if (!/^\/v1\/(bundleIds|profiles)(\/|$)/.test(url.pathname)) throw new AscReadError();
    for (const [key, value] of Object.entries(query || {})) {
      if (/certificateContent/i.test(`${key}=${value}`)) throw new AscReadError();
      url.searchParams.set(key, String(value));
    }
    let response;
    try {
      response = await fetcher(url, {
        method: 'GET',
        redirect: 'error',
        signal: AbortSignal.timeout(30_000),
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      });
    } catch {
      throw new AscReadError();
    }
    if (response.status !== 200) throw new AscReadError();
    const text = await response.text();
    if (!text) return { data: [] };
    try {
      const body = JSON.parse(text);
      return body && typeof body === 'object' ? body : { data: [] };
    } catch {
      throw new AscReadError();
    }
  }

  return {
    async getAll(requestPath, query) {
      const data = [];
      const included = [];
      const seen = new Set();
      let nextPath = requestPath;
      let nextQuery = query;
      for (let page = 0; page < 8 && nextPath; page += 1) {
        if (seen.has(nextPath)) throw new AscReadError();
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

function bundleIdentifier(record, included) {
  const id = record?.relationships?.bundleId?.data?.id;
  if (!id) return '';
  const match = (included || []).find((item) => item?.type === 'bundleIds' && item.id === id);
  return typeof match?.attributes?.identifier === 'string' ? match.attributes.identifier : '';
}

function profileUsable(record, nowMs) {
  const profileType = record?.attributes?.profileType;
  const profileState = record?.attributes?.profileState;
  if (profileType !== 'IOS_APP_STORE') return false;
  if (profileState && profileState !== 'ACTIVE') return false;
  const expiration = record?.attributes?.expirationDate;
  if (typeof expiration === 'string' && expiration) {
    const expiry = Date.parse(expiration);
    if (Number.isFinite(expiry) && expiry < nowMs) return false;
  }
  return true;
}

export async function readCatalog(client, nowMs = Date.now()) {
  const bundles = await client.getAll('/v1/bundleIds', {
    'fields[bundleIds]': 'identifier',
    limit: '200',
  });
  const bundleIdentifiers = [];
  for (const record of bundles.data || []) {
    const identifier = record?.attributes?.identifier;
    if (typeof identifier === 'string' && identifier) bundleIdentifiers.push(identifier);
  }
  const profilesBody = await client.getAll('/v1/profiles', {
    'filter[profileType]': 'IOS_APP_STORE',
    'filter[profileState]': 'ACTIVE',
    include: 'bundleId',
    'fields[bundleIds]': 'identifier',
    'fields[profiles]': 'profileType,profileState,expirationDate,profileContent',
    limit: '200',
  });
  const included = profilesBody.included || [];
  const profiles = [];
  for (const record of profilesBody.data || []) {
    if (!profileUsable(record, nowMs)) continue;
    const bundleId = bundleIdentifier(record, included);
    if (!bundleId) continue;
    const content = record?.attributes?.profileContent;
    profiles.push({
      bundleId,
      usable: true,
      entitlements: typeof content === 'string' && content ? parseEntitlements(Buffer.from(content, 'base64')) : null,
    });
  }
  return { bundleIdentifiers, profiles };
}

function writeOutput(conclusion) {
  if (!process.env.GITHUB_OUTPUT) return;
  appendFileSync(process.env.GITHUB_OUTPUT, `conclusion=${conclusion}\n`);
}

function publish(conclusion, text, forbidden) {
  let safe = text;
  try {
    assertPublicText(safe, forbidden);
  } catch {
    safe = WITHHELD;
    conclusion = 'failure';
  }
  writeOutput(conclusion);
  if (process.env.GITHUB_STEP_SUMMARY) {
    appendFileSync(
      process.env.GITHUB_STEP_SUMMARY,
      `## Release signing provisioned\n\n${safe}\n\n`,
    );
  }
  const line = safe.replaceAll('\n', ' ');
  if (conclusion === 'neutral') console.log(`::warning::${line}`);
  if (conclusion === 'failure') console.log(`::error::${line}`);
  console.log(safe);
  if (conclusion === 'failure') process.exitCode = 1;
}

async function main() {
  const forbidden = secretValues(process.env);
  const gate = credentialGate({
    fork: process.env.FORK === 'true',
    hasSecrets: Boolean(process.env.ASC_KEY_ID && process.env.ASC_ISSUER_ID && process.env.ASC_PRIVATE_KEY),
  });
  if (gate === 'neutral') {
    publish('neutral', neutralMessage(), forbidden);
    return;
  }
  if (gate === 'missing-credentials') {
    publish('failure', missingCredentialsMessage(), forbidden);
    return;
  }

  let bundleIds;
  try {
    bundleIds = releaseBundleIds(RELEASE_FILE);
  } catch {
    publish('failure', failureMessage([{ reason: 'unreadable' }]), forbidden);
    return;
  }
  const reportForbidden = [...forbidden, ...bundleIds];
  let entitlementsByBundleId;
  try {
    entitlementsByBundleId = loadReleaseEntitlements(ROOT, bundleIds, readFileSync(PROJECT_FILE, 'utf8'));
  } catch {
    entitlementsByBundleId = null;
  }
  if (!entitlementsByBundleId) {
    publish('failure', failureMessage([{ reason: 'unreadable' }]), reportForbidden);
    return;
  }
  let catalog;
  try {
    catalog = await readCatalog(createReleaseClient(process.env));
  } catch {
    publish('failure', failureMessage([{ reason: 'unreadable' }]), reportForbidden);
    return;
  }
  const findings = inspectReleaseSigning({ bundleIds, entitlementsByBundleId, catalog });
  if (findings.length > 0) {
    publish('failure', failureMessage(findings), reportForbidden);
    return;
  }
  publish('success', successMessage(), reportForbidden);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    try {
      publish('failure', WITHHELD, secretValues(process.env));
    } catch {
      process.exitCode = 1;
    }
  });
}
