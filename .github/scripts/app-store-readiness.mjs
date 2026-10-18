import { sign } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const REPOSITORY = 'JovieInc/LogYourBody';
const APP_ID = '6755209876';
const BUNDLE_ID = 'com.logyourbody.app';
const VERSION = '1.2.0';
const API = 'https://api.appstoreconnect.apple.com';
const PRODUCTS = [
  'com.logyourbody.app.pro1.annual.3daytrial',
  'com.logyourbody.app.pro1.monthly.3daytrial',
];
// release_notes.txt before #1197 (fe054800). Live or committed text that still
// starts with this sentence is the stale pre-submit What's New.
export const STALE_WHATS_NEW_PREFIX =
  'Private body-composition timeline with a single time-weighted photo scrubber';

const PASS_VERSION_STATES = new Set([
  'PREPARE_FOR_SUBMISSION',
  'READY_FOR_REVIEW',
  'WAITING_FOR_REVIEW',
  'IN_REVIEW',
  'PENDING_APPLE_RELEASE',
  'PENDING_DEVELOPER_RELEASE',
  'PROCESSING_FOR_DISTRIBUTION',
  'PROCESSING_FOR_APP_STORE',
  'READY_FOR_SALE',
  'PREORDER_READY_FOR_SALE',
]);

// A version that is or was on the store. Approved-but-unreleased states stay
// out of this set: Apple and deliver only accept What's New after a release.
export const RELEASED_VERSION_STATES = new Set([
  'READY_FOR_SALE',
  'READY_FOR_DISTRIBUTION',
  'REPLACED_WITH_NEW_VERSION',
  'DEVELOPER_REMOVED_FROM_SALE',
  'REMOVED_FROM_SALE',
]);

const METADATA_FIELDS = [
  ['description', 'version', 'description'],
  ['keywords', 'version', 'keywords'],
  ['supportUrl', 'version', 'supportUrl'],
  ['marketingUrl', 'version', 'marketingUrl'],
  ['promotionalText', 'version', 'promotionalText'],
  ['name', 'app', 'name'],
  ['subtitle', 'app', 'subtitle'],
  ['privacyUrl', 'app', 'privacyPolicyUrl'],
];

const attributes = (record) => record?.attributes ?? {};
const normalize = (value) => String(value ?? '').replaceAll('\r\n', '\n').trim();
const requireTrue = (condition, message) => {
  if (!condition) throw new Error(message);
};

// Same iss/exp/aud claims as verify-app-store-subscriptions.rb, plus iat.
// Apple's JWT has no per-request scope claim; this client only sends GET.
export function createToken(env, now = Math.floor(Date.now() / 1000)) {
  try {
    for (const name of ['ASC_KEY_ID', 'ASC_ISSUER_ID', 'ASC_PRIVATE_KEY']) {
      if (!env[name]) throw new Error('Missing credential');
    }
    const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
    const message = `${encode({ alg: 'ES256', kid: env.ASC_KEY_ID, typ: 'JWT' })}.${encode({
      iss: env.ASC_ISSUER_ID,
      iat: now,
      exp: now + 1200,
      aud: 'appstoreconnect-v1',
    })}`;
    const signature = sign('sha256', Buffer.from(message), {
      key: env.ASC_PRIVATE_KEY.replaceAll('\\n', '\n'),
      dsaEncoding: 'ieee-p1363',
    });
    return `${message}.${signature.toString('base64url')}`;
  } catch {
    throw new Error('ASC authentication unavailable: check the existing release API key secrets');
  }
}

export class AscReader {
  constructor(token, fetcher = fetch) {
    this.token = token;
    this.fetcher = fetcher;
  }

  async request(path, query = {}) {
    const url = new URL(path, API);
    if (url.origin !== API || url.username || url.password) {
      throw new Error('ASC pagination origin rejected');
    }
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, String(value));
    let response;
    try {
      response = await this.fetcher(url, {
        method: 'GET',
        redirect: 'error',
        signal: AbortSignal.timeout(30_000),
        headers: { Authorization: `Bearer ${this.token}`, Accept: 'application/json' },
      });
    } catch {
      throw new Error(`ASC GET ${url.pathname} failed (network, timeout, or redirect)`);
    }
    const text = await response.text();
    let body = {};
    if (text) {
      try {
        body = JSON.parse(text);
      } catch {
        if (response.ok) throw new Error(`ASC GET ${url.pathname} returned invalid JSON`);
      }
    }
    return { status: response.status, pathname: url.pathname, body };
  }

  async get(path, query = {}) {
    const result = await this.request(path, query);
    if (result.status !== 200) {
      throw new Error(`ASC GET ${result.pathname} returned HTTP ${result.status}`);
    }
    return result.body;
  }

  async all(path, query = {}) {
    const records = [];
    const seen = new Set();
    let next = path;
    let nextQuery = query;
    for (let page = 0; next; page += 1) {
      if (page > 20) throw new Error('ASC pagination exceeded 20 pages');
      if (seen.has(next)) throw new Error('ASC pagination repeated a page');
      seen.add(next);
      const body = await this.get(next, nextQuery);
      if (!Array.isArray(body.data)) throw new Error('ASC list response missing data');
      records.push(...body.data);
      next = body.links?.next || '';
      nextQuery = {};
    }
    return records;
  }
}

export function githubApiArguments(path, { raw = false, paginate = true } = {}) {
  return [
    'api',
    '--method',
    'GET',
    '--allow-escape-sequences',
    path,
    ...(raw || !paginate ? [] : ['--paginate', '--slurp']),
  ];
}

export function githubGet(path, raw = false, paginate = true) {
  try {
    const output = execFileSync('gh', githubApiArguments(path, { raw, paginate }), {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 120_000,
      maxBuffer: 20 * 1024 * 1024,
    });
    if (raw) return output;
    const parsed = JSON.parse(output);
    return Array.isArray(parsed) ? parsed : [parsed];
  } catch {
    throw new Error('GitHub readback unavailable (check actions:read, token, and retained job logs)');
  }
}

function stripAnsi(value) {
  return String(value).replace(/\u001b\[[0-9;]*[A-Za-z]/g, '');
}

export async function latestTestFlightUpload(github = githubGet) {
  const base = `repos/${REPOSITORY}/actions`;
  for (let page = 1; ; page += 1) {
    const pages = await github(
      `${base}/workflows/ios-release-loop.yml/runs?branch=main&per_page=100&page=${page}`,
      false,
      false,
    );
    const runs = pages.flatMap((entry) => entry.workflow_runs ?? []).sort((a, b) => b.id - a.id);
    for (const run of runs) {
      if (
        run.head_branch !== 'main' ||
        run.repository?.full_name !== REPOSITORY ||
        run.path !== '.github/workflows/ios-release-loop.yml'
      ) {
        continue;
      }
      if (
        !Number.isSafeInteger(run.id) ||
        !Number.isSafeInteger(run.run_attempt) ||
        !/^[a-f0-9]{40}$/.test(run.head_sha)
      ) {
        throw new Error('Release Loop provenance incomplete');
      }
      const jobPages = await github(`${base}/runs/${run.id}/attempts/${run.run_attempt}/jobs?per_page=100`);
      const jobs = jobPages.flatMap((entry) => entry.jobs ?? []);
      const uploaded = jobs.some(
        (job) =>
          job.name?.startsWith('Deploy to TestFlight /') &&
          job.steps?.some((step) => step.name === 'Upload to TestFlight' && step.conclusion === 'success'),
      );
      if (!uploaded) continue;
      const validation = jobs.filter(
        (job) =>
          job.name === 'Validate Release' &&
          job.steps?.some((step) => step.name === 'Extract version info' && step.conclusion === 'success'),
      );
      if (validation.length !== 1 || !Number.isSafeInteger(validation[0].id)) {
        throw new Error('Release Loop version/build receipt missing');
      }
      const logs = stripAnsi(await github(`${base}/jobs/${validation[0].id}/logs`, true));
      const versions = [
        ...new Set([...logs.matchAll(/📦 Version: (\d+\.\d+(?:\.\d+)?)\s*$/gm)].map((match) => match[1])),
      ];
      const builds = [...new Set([...logs.matchAll(/🔢 Build: (\d+)\s*$/gm)].map((match) => match[1]))];
      if (versions.length !== 1 || builds.length !== 1) {
        throw new Error('Release Loop version/build receipt missing or ambiguous');
      }
      return {
        runId: run.id,
        attempt: run.run_attempt,
        sha: run.head_sha,
        url: `https://github.com/${REPOSITORY}/actions/runs/${run.id}/attempts/${run.run_attempt}`,
        version: versions[0],
        build: builds[0],
      };
    }
    if (runs.length < 100) break;
  }
  throw new Error('No successful TestFlight upload found in retained main Release Loops');
}

function relatedIds(item) {
  const ids = [];
  for (const relationship of Object.values(item?.relationships ?? {})) {
    const data = relationship?.data;
    const resources = Array.isArray(data) ? data : data ? [data] : [];
    for (const resource of resources) {
      if (resource?.id) ids.push(String(resource.id));
    }
  }
  return ids;
}

async function listReviewSubmissions(asc) {
  const attempts = [
    [`/v1/apps/${APP_ID}/reviewSubmissions`, { limit: 20 }],
    ['/v1/reviewSubmissions', { 'filter[app]': APP_ID, limit: 20 }],
  ];
  const notes = [];
  for (const [path, query] of attempts) {
    const listed = await asc.request(path, query);
    if (listed.status === 200 && Array.isArray(listed.body?.data)) {
      return { submissions: listed.body.data, note: '' };
    }
    notes.push(`${listed.pathname} HTTP ${listed.status}`);
  }
  return { submissions: [], note: notes.join('; ') };
}

async function subscriptionsAttachedToVersion(asc, versionId) {
  if (!versionId) return { ids: new Set(), note: 'version unavailable' };
  const listed = await listReviewSubmissions(asc);
  if (listed.note) return { ids: new Set(), note: listed.note };
  const ids = new Set();
  const failures = [];
  for (const submission of listed.submissions) {
    try {
      const items = await asc.all(`/v1/reviewSubmissions/${submission.id}/items`, { limit: 200 });
      const related = new Set(items.flatMap((item) => relatedIds(item)));
      if (related.has(versionId)) {
        for (const id of related) ids.add(id);
      }
    } catch (error) {
      failures.push(error.message);
    }
  }
  return {
    ids,
    note: failures.length ? failures[0] : 'review submission items read',
  };
}

function expectedLocales(manifest) {
  requireTrue(Array.isArray(manifest?.locales) && manifest.locales.length > 0, 'Committed storefront locales missing');
  return manifest.locales;
}

async function readVersion(asc) {
  const app = await asc.get(`/v1/apps/${APP_ID}`, { 'fields[apps]': 'bundleId' });
  requireTrue(attributes(app.data).bundleId === BUNDLE_ID, 'ASC app bundle identity mismatch');
  const versions = await asc.all(`/v1/apps/${APP_ID}/appStoreVersions`, {
    'filter[platform]': 'IOS',
    'filter[versionString]': VERSION,
    'fields[appStoreVersions]': 'versionString,appVersionState,platform',
    limit: 200,
  });
  const matches = versions.filter(
    (item) => attributes(item).versionString === VERSION && attributes(item).platform === 'IOS',
  );
  requireTrue(matches.length === 1, `App Store ${VERSION} missing or ambiguous`);
  return matches[0];
}

export async function readReadiness({ asc, evidence = latestTestFlightUpload, manifest }) {
  const rows = [];
  const check = async (name, action, read) => {
    try {
      const value = await read();
      if (value && typeof value === 'object') {
        rows.push({
          check: name,
          pass: value.pass !== false,
          result: value.result,
          detail: value.detail,
          action: value.action ?? '—',
        });
        return;
      }
      rows.push({ check: name, pass: true, detail: value, action: '—' });
    } catch (error) {
      rows.push({ check: name, pass: false, detail: error.message, action });
    }
  };

  let version;
  await check('Version state', 'Tim-only T1: resolve the 1.2.0 version state in App Store Connect before Submit.', async () => {
    version = await readVersion(asc);
    const state = attributes(version).appVersionState || 'UNKNOWN';
    requireTrue(
      PASS_VERSION_STATES.has(state),
      `${VERSION} state=${state}; not a submittable or already-submitted state`,
    );
    return `${VERSION} state=${state}; version ID=${version.id}`;
  });

  let receipt;
  await check(
    'Newest TestFlight upload',
    'Tim-only T2: restore Release Loop log access or complete a 1.2.0 TestFlight upload, then rerun.',
    async () => {
      receipt = await evidence();
      requireTrue(
        receipt.version === VERSION,
        `Newest upload is ${receipt.version} (${receipt.build}), not ${VERSION}; run ${receipt.url}`,
      );
      return `Run ${receipt.runId} attempt ${receipt.attempt}; ${receipt.version} (${receipt.build}); commit ${receipt.sha}; ${receipt.url}`;
    },
  );

  await check(
    'Build processed and selectable',
    'Tim-only T3: inspect this exact build in App Store Connect and resolve processing, export compliance, or version linkage. This workflow does not select it.',
    async () => {
      requireTrue(receipt?.version === VERSION, 'No matching newest TestFlight receipt; cannot substitute an older build');
      requireTrue(version?.id, `App Store ${VERSION} unavailable; see Version state`);
      const result = await asc.get('/v1/builds', {
        'filter[app]': APP_ID,
        'filter[version]': receipt.build,
        include: 'preReleaseVersion,appEncryptionDeclaration,appStoreVersion',
        'fields[builds]':
          'version,processingState,expired,usesNonExemptEncryption,buildAudienceType,preReleaseVersion,appEncryptionDeclaration,appStoreVersion',
        'fields[preReleaseVersions]': 'version,platform',
        'fields[appEncryptionDeclarations]': 'appEncryptionDeclarationState',
        limit: 200,
      });
      requireTrue(result.data?.length === 1, `Exact uploaded build ${receipt.build} missing or ambiguous in ASC`);
      const build = result.data[0];
      const included = result.included ?? [];
      const related = (name) => included.find((item) => item.id === build.relationships?.[name]?.data?.id);
      const buildAttributes = attributes(build);
      const pre = attributes(related('preReleaseVersion'));
      const encryption = attributes(related('appEncryptionDeclaration'));
      const linkage = build.relationships?.appStoreVersion;
      requireTrue(linkage && Object.hasOwn(linkage, 'data'), 'Build App Store version association unavailable');
      const otherVersion = linkage.data?.id;
      const compliance =
        buildAttributes.usesNonExemptEncryption === false ||
        (buildAttributes.usesNonExemptEncryption === true && encryption.appEncryptionDeclarationState === 'APPROVED');
      requireTrue(
        buildAttributes.version === receipt.build &&
          buildAttributes.processingState === 'VALID' &&
          buildAttributes.expired === false &&
          pre.version === VERSION &&
          pre.platform === 'IOS' &&
          buildAttributes.buildAudienceType === 'APP_STORE_ELIGIBLE' &&
          compliance &&
          (!otherVersion || otherVersion === version.id),
        `${receipt.build}: processing=${buildAttributes.processingState || 'UNKNOWN'}, expired=${buildAttributes.expired}, version=${pre.version || 'UNKNOWN'}, platform=${pre.platform || 'UNKNOWN'}, audience=${buildAttributes.buildAudienceType || 'UNKNOWN'}, non-exempt encryption=${buildAttributes.usesNonExemptEncryption}, declaration=${encryption.appEncryptionDeclarationState || 'none'}, linked version=${otherVersion || 'none'}`,
      );
      const selected = await asc.request(`/v1/appStoreVersions/${version.id}/build`);
      if (![200, 404].includes(selected.status)) {
        throw new Error(`ASC GET /v1/appStoreVersions/${version.id}/build returned HTTP ${selected.status}`);
      }
      const selectedId = selected.status === 200 ? selected.body?.data?.id ?? null : null;
      const selectedBuild = selected.status === 200 ? attributes(selected.body?.data).version || 'none' : 'none';
      const selection = selectedId === build.id ? 'already selected' : `selectable; selected build=${selectedBuild}`;
      return `${receipt.build}: VALID, unexpired, IOS ${VERSION}, APP_STORE_ELIGIBLE, export compliance resolved; ${selection}`;
    },
  );

  let products = [];
  let productError;
  try {
    const groups = await asc.all(`/v1/apps/${APP_ID}/subscriptionGroups`, { limit: 200 });
    products = (
      await Promise.all(groups.map((group) => asc.all(`/v1/subscriptionGroups/${group.id}/subscriptions`, { limit: 200 })))
    ).flat();
  } catch (error) {
    productError = error;
  }

  let attachment = { ids: new Set(), note: 'not checked' };
  if (!productError) {
    try {
      attachment = await subscriptionsAttachedToVersion(asc, version?.id);
    } catch (error) {
      attachment = { ids: new Set(), note: error.message };
    }
  }

  for (const [index, productId] of PRODUCTS.entries()) {
    await check(
      productId,
      `Tim-only T${index + 4}: put this product in Ready to Submit, or confirm it is attached to ${VERSION}. This workflow cannot attach it.`,
      async () => {
        if (productError) throw productError;
        const matches = products.filter((item) => attributes(item).productId === productId);
        requireTrue(matches.length === 1, 'Required subscription missing or ambiguous');
        const product = matches[0];
        const state = attributes(product).state || 'UNKNOWN';
        const attached = attachment.ids.has(String(product.id));
        requireTrue(
          state === 'READY_TO_SUBMIT' || attached,
          `state=${state}; attachment to ${VERSION} not shown (${attachment.note})`,
        );
        if (attached) return `state=${state}; attached to ${VERSION}; product ID=${product.id}`;
        return `state=${state}; product ID=${product.id}; Ready to Submit before attachment`;
      },
    );
  }

  let localizations;
  const versionLocales = () => {
    requireTrue(version?.id, `App Store ${VERSION} unavailable; see Version state`);
    localizations ??= asc.all(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations`, { limit: 200 });
    return localizations;
  };

  await check(
    "What's New",
    "Tim-only T6: replace ASC What's New with the committed storefront release notes. This workflow cannot write metadata.",
    async () => {
      requireTrue(version?.id, `App Store ${VERSION} unavailable; see Version state`);
      for (const locale of expectedLocales(manifest)) {
        const expected = normalize(locale.metadata?.releaseNotes);
        requireTrue(
          expected && !expected.startsWith(STALE_WHATS_NEW_PREFIX),
          `${locale.id} committed release notes are blank or pre-#1197`,
        );
      }
      // Unfiltered by version string. readVersion asks only for 1.2.0; this
      // list is how we tell a first version from one that follows a live release.
      const versions = await asc.all(`/v1/apps/${APP_ID}/appStoreVersions`, {
        'filter[platform]': 'IOS',
        'fields[appStoreVersions]': 'versionString,appVersionState,platform',
        limit: 200,
      });
      const iosVersions = versions.filter((item) => {
        const platform = attributes(item).platform;
        return !platform || platform === 'IOS';
      });
      const priorLive = iosVersions.filter(
        (item) => item.id !== version.id && RELEASED_VERSION_STATES.has(attributes(item).appVersionState),
      );
      if (priorLive.length === 0) {
        const listed = iosVersions
          .map((item) => `${attributes(item).versionString || item.id} ${attributes(item).appVersionState || 'UNKNOWN'}`)
          .join(', ');
        return {
          result: 'N/A',
          detail: `N/A: no previously released iOS version (${listed || 'none listed'})`,
        };
      }
      const live = await versionLocales();
      const notes = [];
      for (const locale of expectedLocales(manifest)) {
        const expected = normalize(locale.metadata?.releaseNotes);
        const actual = live.find((item) => attributes(item).locale === locale.id);
        const whatsNew = normalize(attributes(actual).whatsNew);
        requireTrue(
          whatsNew === expected,
          whatsNew.startsWith(STALE_WHATS_NEW_PREFIX)
            ? `${locale.id} What's New is the stale pre-#1197 text`
            : `${locale.id} What's New missing or differs from the committed post-#1197 text`,
        );
        notes.push(`${locale.id}: ${expected}`);
      }
      return `Matches committed post-#1197 text. ${notes.join('; ')}`;
    },
  );

  await check(
    'Storefront metadata',
    'Tim-only T7: reconcile the named ASC metadata fields with the committed storefront manifest before Submit.',
    async () => {
      const live = await versionLocales();
      const infos = await asc.all(`/v1/apps/${APP_ID}/appInfos`, { limit: 200 });
      const versionState = attributes(version).appVersionState;
      const editable = infos.filter((info) => {
        const state = attributes(info).state ?? attributes(info).appStoreState;
        return state === versionState || state === 'PREPARE_FOR_SUBMISSION' || state === 'READY_FOR_REVIEW';
      });
      const chosen = editable.length === 1 ? editable : infos.length === 1 ? infos : [];
      requireTrue(chosen.length === 1, 'Editable app information missing or ambiguous');
      const appLocales = await asc.all(`/v1/appInfos/${chosen[0].id}/appInfoLocalizations`, { limit: 200 });
      const missing = [];
      for (const locale of expectedLocales(manifest)) {
        const versionLocale = attributes(live.find((item) => attributes(item).locale === locale.id));
        const appLocale = attributes(appLocales.find((item) => attributes(item).locale === locale.id));
        for (const [source, target, field] of METADATA_FIELDS) {
          const expected = normalize(locale.metadata?.[source]);
          const actual = normalize((target === 'version' ? versionLocale : appLocale)[field]);
          if (!expected || actual !== expected) missing.push(`${locale.id}.${field}`);
        }
      }
      requireTrue(missing.length === 0, `Missing or stale metadata: ${missing.join(', ')}`);
      return 'Name, subtitle, privacy URL, description, keywords, promotional text, and support/marketing URLs match the committed manifest';
    },
  );

  return rows;
}

const cell = (value) =>
  String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('|', '&#124;').replace(/[\r\n]+/g, ' ');

export function renderSummary(rows) {
  const failed = rows.some((row) => row.pass === false);
  const closing = failed
    ? 'Resolve every FAIL row using its named Tim-only item before Submit.'
    : 'No FAIL rows.';
  return (
    `## App Store ${VERSION} readiness\n\nRead-only App Store Connect snapshot. No submit, build attach, release, or metadata write.\n\n` +
    '| Check | Result | Evidence | Follow-up |\n| --- | --- | --- | --- |\n' +
    rows
      .map((row) => {
        const label = row.result || (row.pass ? 'PASS' : 'FAIL');
        return `| ${cell(row.check)} | ${label} | ${cell(row.detail)} | ${cell(row.action)} |`;
      })
      .join('\n') +
    `\n\nReadback complete. ${closing}\n\n` +
    '[#1197](https://github.com/JovieInc/LogYourBody/pull/1197) merged 2026-10-11 (fe054800d6c4db490e780a8a8620571ebdcacdd2). What\'s New is N/A when no iOS version was previously released. A prior live version is still compared with that committed text.\n\n' +
    'Scope: version state, the newest uploaded build, the two pro1 subscriptions, and storefront metadata. Screenshots, privacy declarations, agreements, and a real-device purchase/restore remain on the release checklist. A green job means the readback ran; the table is the result.\n'
  );
}

async function main() {
  const manifest = JSON.parse(
    readFileSync(new URL('../../apps/ios/fastlane/storefront-manifest.generated.json', import.meta.url)),
  );
  let asc;
  try {
    asc = new AscReader(createToken(process.env));
  } catch (error) {
    const message = error.message;
    asc = {
      async request() {
        throw new Error(message);
      },
      async get() {
        throw new Error(message);
      },
      async all() {
        throw new Error(message);
      },
    };
  }
  const rows = await readReadiness({ asc, manifest });
  const summary = renderSummary(rows);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
  console.log(summary);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    const message = 'Readiness report could not be generated. Tim-only T0: inspect workflow setup and rerun.\n';
    if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, message);
    console.error(message);
    process.exitCode = 1;
  });
}
