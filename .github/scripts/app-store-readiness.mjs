import { sign } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const REPOSITORY = 'JovieInc/LogYourBody';
const APP_ID = '6755209876';
const VERSION = '1.2.0';
const API = 'https://api.appstoreconnect.apple.com';
const PRODUCTS = [
  'com.logyourbody.app.pro1.annual.3daytrial',
  'com.logyourbody.app.pro1.monthly.3daytrial',
];

// Same issuer/key secrets and ES256 claims as the Ruby release monitor, with
// a fresh token scoped to exactly one GET. No key file or Fastlane lane needed.
export function createToken(env, now = Math.floor(Date.now() / 1000), path = '/v1/apps') {
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
      scope: [`GET ${path}`],
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

  async get(path, query = {}) {
    const url = new URL(path, API);
    if (url.origin !== API || url.username || url.password)
      throw new Error('ASC pagination origin rejected');
    for (const [key, value] of Object.entries(query)) url.searchParams.set(key, value);
    const token =
      typeof this.token === 'function' ? this.token(url.pathname + url.search) : this.token;
    let response;
    try {
      response = await this.fetcher(url, {
        method: 'GET',
        redirect: 'error',
        signal: AbortSignal.timeout(30_000),
        headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
      });
    } catch {
      throw new Error(`ASC GET ${url.pathname} failed (network, timeout, or redirect)`);
    }
    if (!response.ok) throw new Error(`ASC GET ${url.pathname} returned HTTP ${response.status}`);
    try {
      return await response.json();
    } catch {
      throw new Error(`ASC GET ${url.pathname} returned invalid JSON`);
    }
  }

  async all(path, query = {}) {
    const records = [];
    const visited = new Set();
    while (path) {
      if (visited.has(path)) throw new Error('ASC pagination repeated a page');
      visited.add(path);
      const page = await this.get(path, query);
      if (!Array.isArray(page.data)) throw new Error('ASC list response missing data');
      records.push(...page.data);
      path = page.links?.next;
      query = {};
    }
    return records;
  }
}

export function githubGet(path, raw = false, paginate = true) {
  try {
    const output = execFileSync(
      'gh',
      ['api', '--method', 'GET', path, ...(raw || !paginate ? [] : ['--paginate', '--slurp'])],
      {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
        timeout: 120_000,
        maxBuffer: 20 * 1024 * 1024,
      },
    );
    return raw ? output : paginate ? JSON.parse(output) : [JSON.parse(output)];
  } catch {
    throw new Error(
      'GitHub readback unavailable (check actions:read, token, and retained job logs)',
    );
  }
}

export async function latestTestFlightUpload(github = githubGet) {
  const base = `repos/${REPOSITORY}/actions`;
  // Do not filter conclusion=success: an upload may succeed before processing
  // or distribution fails. Skip only runs without a successful upload step.
  for (let page = 1; ; page++) {
    const pages = await github(
      `${base}/workflows/ios-release-loop.yml/runs?branch=main&per_page=100&page=${page}`,
      false,
      false,
    );
    const runs = pages.flatMap((page) => page.workflow_runs).sort((a, b) => b.id - a.id);
    for (const run of runs) {
      if (
        run.head_branch !== 'main' ||
        run.repository?.full_name !== REPOSITORY ||
        run.path !== '.github/workflows/ios-release-loop.yml'
      )
        continue;
      if (
        !Number.isSafeInteger(run.id) ||
        !Number.isSafeInteger(run.run_attempt) ||
        !/^[a-f0-9]{40}$/.test(run.head_sha)
      ) {
        throw new Error('Release Loop provenance incomplete');
      }
      const jobPages = await github(
        `${base}/runs/${run.id}/attempts/${run.run_attempt}/jobs?per_page=100`,
      );
      const jobs = jobPages.flatMap((page) => page.jobs);
      const uploaded = jobs.some(
        (job) =>
          job.name.startsWith('Deploy to TestFlight /') &&
          job.steps?.some(
            (step) => step.name === 'Upload to TestFlight' && step.conclusion === 'success',
          ),
      );
      if (!uploaded) continue;
      const validation = jobs.filter(
        (job) =>
          job.name === 'Validate Release' &&
          job.steps?.some(
            (step) => step.name === 'Extract version info' && step.conclusion === 'success',
          ),
      );
      if (validation.length !== 1 || !Number.isSafeInteger(validation[0].id))
        throw new Error('Release Loop version/build receipt missing');
      const logs = await github(`${base}/jobs/${validation[0].id}/logs`, true);
      const versions = [
        ...new Set(
          [...logs.matchAll(/📦 Version: (\d+\.\d+(?:\.\d+)?)\s*$/gm)].map((match) => match[1]),
        ),
      ];
      const builds = [
        ...new Set([...logs.matchAll(/🔢 Build: (\d+)\s*$/gm)].map((match) => match[1])),
      ];
      if (versions.length !== 1 || builds.length !== 1)
        throw new Error('Release Loop version/build receipt missing or ambiguous');
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

const attributes = (record) => record?.attributes ?? {};
const requireTrue = (condition, message) => {
  if (!condition) throw new Error(message);
};
const normalize = (value) =>
  String(value ?? '')
    .replaceAll('\r\n', '\n')
    .trim();

export async function readReadiness({ asc, evidence = latestTestFlightUpload, manifest }) {
  const rows = [];
  const check = async (name, action, read) => {
    try {
      rows.push({ check: name, pass: true, detail: await read(), action: '—' });
    } catch (error) {
      rows.push({ check: name, pass: false, detail: error.message, action });
    }
  };
  let version, receipt;
  const versionId = () => {
    requireTrue(version, `App Store ${VERSION} unavailable; see Version state`);
    return version.id;
  };
  await check(
    'Version state',
    'Tim-only T1: resolve the version state in ASC before Submit.',
    async () => {
      const app = await asc.get(`/v1/apps/${APP_ID}`);
      requireTrue(
        attributes(app.data).bundleId === 'com.logyourbody.app',
        'ASC app bundle identity mismatch',
      );
      const versions = await asc.all(`/v1/apps/${APP_ID}/appStoreVersions`, {
        'filter[platform]': 'IOS',
        'filter[versionString]': VERSION,
        limit: 200,
      });
      const matches = versions.filter(
        (item) => attributes(item).versionString === VERSION && attributes(item).platform === 'IOS',
      );
      requireTrue(matches.length === 1, `App Store ${VERSION} missing or ambiguous`);
      version = matches[0];
      const state = attributes(version).appVersionState;
      requireTrue(
        ['PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW'].includes(state),
        `${VERSION} state=${state || 'UNKNOWN'}; not awaiting a Submit click`,
      );
      return `${VERSION} state=${state}; version ID=${version.id}`;
    },
  );
  await check(
    'Newest TestFlight upload',
    'Tim-only T2: restore Release Loop log access or complete a TestFlight upload, then rerun.',
    async () => {
      receipt = await evidence();
      requireTrue(
        receipt.version === VERSION,
        `Newest upload is ${receipt.version} (${receipt.build}), not ${VERSION}; run ${receipt.url}`,
      );
      return `Run ${receipt.runId}, attempt ${receipt.attempt}; ${receipt.version} (${receipt.build}); commit ${receipt.sha}; ${receipt.url}`;
    },
  );
  await check(
    'Build processed and selectable',
    'Tim-only T3: inspect this exact build in ASC; resolve processing/export compliance or version availability, then select it if appropriate.',
    async () => {
      requireTrue(
        receipt?.version === VERSION,
        'No matching newest TestFlight receipt; cannot substitute an older build',
      );
      const id = versionId();
      const result = await asc.get('/v1/builds', {
        'filter[app]': APP_ID,
        'filter[version]': receipt.build,
        include: 'preReleaseVersion,appEncryptionDeclaration,appStoreVersion',
        limit: 200,
      });
      requireTrue(
        result.data?.length === 1,
        `Exact uploaded build ${receipt.build} missing or ambiguous in ASC`,
      );
      const build = result.data[0];
      const included = result.included ?? [];
      const related = (name) =>
        included.find((item) => item.id === build.relationships?.[name]?.data?.id);
      const a = attributes(build),
        pre = attributes(related('preReleaseVersion')),
        encryption = attributes(related('appEncryptionDeclaration'));
      const attached = await asc.get(`/v1/appStoreVersions/${id}/build`);
      const linkage = build.relationships?.appStoreVersion;
      requireTrue(
        linkage && Object.hasOwn(linkage, 'data'),
        'Build App Store version association unavailable',
      );
      const otherVersion = linkage.data?.id;
      requireTrue(
        a.version === receipt.build &&
          a.processingState === 'VALID' &&
          a.expired === false &&
          pre.version === VERSION &&
          pre.platform === 'IOS' &&
          a.buildAudienceType === 'APP_STORE_ELIGIBLE' &&
          (a.usesNonExemptEncryption === false ||
            (a.usesNonExemptEncryption === true &&
              encryption.appEncryptionDeclarationState === 'APPROVED')) &&
          (!otherVersion || otherVersion === id),
        `${receipt.build}: processing=${a.processingState || 'UNKNOWN'}, expired=${a.expired}, version=${pre.version || 'UNKNOWN'}, platform=${pre.platform || 'UNKNOWN'}, audience=${a.buildAudienceType || 'UNKNOWN'}, non-exempt encryption=${a.usesNonExemptEncryption}, declaration=${encryption.appEncryptionDeclarationState || 'none'}, linked version=${otherVersion || 'none'}`,
      );
      return `${receipt.build}: VALID, unexpired, IOS ${VERSION}, APP_STORE_ELIGIBLE, export compliance resolved; ${attached.data?.id === build.id ? 'already selected' : `selectable; selected build=${attributes(attached.data).version || 'none'}`}`;
    },
  );
  let products, productError;
  try {
    const groups = await asc.all(`/v1/apps/${APP_ID}/subscriptionGroups`, { limit: 200 });
    products = (
      await Promise.all(
        groups.map((group) =>
          asc.all(`/v1/subscriptionGroups/${group.id}/subscriptions`, { limit: 200 }),
        ),
      )
    ).flat();
  } catch (error) {
    productError = error;
  }
  for (const [index, productId] of PRODUCTS.entries()) {
    await check(
      productId,
      `Tim-only T${index + 4}: resolve this product in ASC or verify its attachment to ${VERSION}; the public API does not expose that attachment.`,
      async () => {
        if (productError) throw productError;
        const product = products.filter((item) => attributes(item).productId === productId);
        requireTrue(product.length === 1, 'Required subscription missing or ambiguous');
        const state = attributes(product[0]).state;
        // APPROVED/IN_REVIEW alone cannot prove attachment to this version.
        requireTrue(
          state === 'READY_TO_SUBMIT',
          `state=${state || 'UNKNOWN'}; attachment to ${VERSION} unverified`,
        );
        return `state=${state}; product ID=${product[0].id}; attachment not required for this row to pass`;
      },
    );
  }
  let localizations;
  const versionLocales = () =>
    (localizations ??= asc.all(`/v1/appStoreVersions/${versionId()}/appStoreVersionLocalizations`, {
      limit: 200,
    }));
  await check(
    "What's New",
    'Tim-only T6: update ASC What’s New from the committed storefront manifest; this workflow cannot write metadata.',
    async () => {
      const live = await versionLocales();
      requireTrue(manifest.locales?.length > 0, 'Committed storefront locales missing');
      const notes = [];
      for (const locale of manifest.locales) {
        const expected = normalize(locale.metadata.releaseNotes);
        requireTrue(
          expected &&
            !expected.startsWith(
              'Private body-composition timeline with a single time-weighted photo scrubber',
            ),
          'Committed release notes are blank or pre-#1197',
        );
        const actual = live.find((item) => attributes(item).locale === locale.id);
        requireTrue(
          normalize(attributes(actual).whatsNew) === expected,
          `${locale.id} What’s New missing or differs from post-#1197 committed text`,
        );
        notes.push(`${locale.id}: ${expected}`);
      }
      return `Matches post-#1197 committed text. ${notes.join('; ')}`;
    },
  );
  await check(
    'Storefront metadata',
    'Tim-only T7: reconcile the named ASC metadata fields with the committed manifest before Submit.',
    async () => {
      const live = await versionLocales();
      const infos = await asc.all(`/v1/apps/${APP_ID}/appInfos`, { limit: 200 });
      const editable = infos.filter((info) =>
        ['PREPARE_FOR_SUBMISSION', 'READY_FOR_REVIEW'].includes(
          attributes(info).state ?? attributes(info).appStoreState,
        ),
      );
      requireTrue(editable.length === 1, 'Editable app information missing or ambiguous');
      const appLocales = await asc.all(`/v1/appInfos/${editable[0].id}/appInfoLocalizations`, {
        limit: 200,
      });
      const missing = [];
      for (const locale of manifest.locales) {
        const expected = locale.metadata;
        const v = attributes(live.find((item) => attributes(item).locale === locale.id));
        const app = attributes(appLocales.find((item) => attributes(item).locale === locale.id));
        for (const field of [
          'description',
          'keywords',
          'supportUrl',
          'marketingUrl',
          'promotionalText',
        ]) {
          if (!normalize(expected[field]) || normalize(v[field]) !== normalize(expected[field]))
            missing.push(`${locale.id}.${field}`);
        }
        for (const [field, source] of [
          ['name', 'name'],
          ['subtitle', 'subtitle'],
          ['privacyPolicyUrl', 'privacyUrl'],
        ]) {
          if (!normalize(expected[source]) || normalize(app[field]) !== normalize(expected[source]))
            missing.push(`${locale.id}.${field}`);
        }
      }
      requireTrue(missing.length === 0, `Missing or stale metadata: ${missing.join(', ')}`);
      return 'Name, subtitle, privacy URL, description, keywords, support/marketing URLs, promotional text match the committed manifest';
    },
  );
  return rows;
}

const cell = (value) =>
  String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('|', '&#124;')
    .replace(/[\r\n]+/g, ' ');
export function renderSummary(rows) {
  return (
    `## App Store ${VERSION} readiness\n\nRead-only ASC snapshot. No submit, build attach, release, or metadata writes.\n\n` +
    '| Check | Result | Evidence | Follow-up |\n| --- | --- | --- | --- |\n' +
    rows
      .map(
        (row) =>
          `| ${cell(row.check)} | ${row.pass ? 'PASS' : 'FAIL'} | ${cell(row.detail)} | ${cell(row.action)} |`,
      )
      .join('\n') +
    `\n\nReadback complete. ${rows.every((row) => row.pass) ? 'All reported checks pass.' : 'Resolve every red row using its named Tim-only item before Submit.'}\n\n` +
    '[#1197](https://github.com/JovieInc/LogYourBody/pull/1197) merged 2026-10-11 (fe054800d6c4db490e780a8a8620571ebdcacdd2). Live text is checked separately above.\n\n' +
    'Scope: API metadata and build eligibility only. Screenshots, privacy declarations, agreements, and real-device paywall purchase/restore evidence still need the release checklist. A green job means the readback ran; readiness is determined by the table.\n'
  );
}

async function main() {
  const manifest = JSON.parse(
    readFileSync(
      new URL('../../apps/ios/fastlane/storefront-manifest.generated.json', import.meta.url),
    ),
  );
  const asc = new AscReader((path) => createToken(process.env, undefined, path));
  const rows = await readReadiness({ asc, manifest });
  const summary = renderSummary(rows);
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, summary);
  console.log(summary);
  // Red rows are a completed readback with named follow-ups, not a failed job.
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    const message =
      'Readiness report could not be generated. Tim-only T0: inspect workflow setup and rerun.\n';
    if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, message);
    console.error(message);
    process.exitCode = 1;
  });
}
