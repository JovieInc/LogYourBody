import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  AscReader,
  STALE_WHATS_NEW_PREFIX,
  createToken,
  githubApiArguments,
  latestTestFlightUpload,
  readReadiness,
  renderSummary,
} from './app-store-readiness.mjs';

const APP = '6755209876';
const ANNUAL = 'com.logyourbody.app.pro1.annual.3daytrial';
const MONTHLY = 'com.logyourbody.app.pro1.monthly.3daytrial';
const BUILD_NUMBER = '20261016215903';
const manifest = JSON.parse(
  readFileSync(new URL('../../apps/ios/fastlane/storefront-manifest.generated.json', import.meta.url)),
);
const receipt = {
  runId: 38972403724,
  attempt: 1,
  sha: 'a'.repeat(40),
  url: 'https://github.com/JovieInc/LogYourBody/actions/runs/38972403724/attempts/1',
  version: '1.2.0',
  build: BUILD_NUMBER,
};

function resource(id, attrs, relationships) {
  return { id, attributes: attrs, ...(relationships ? { relationships } : {}) };
}

function world(mutate = () => {}) {
  const locale = manifest.locales[0];
  const meta = locale.metadata;
  const state = {
    versionState: 'PREPARE_FOR_SUBMISSION',
    bundleId: 'com.logyourbody.app',
    versions: null,
    build: resource(
      'build-1',
      {
        version: BUILD_NUMBER,
        processingState: 'VALID',
        expired: false,
        usesNonExemptEncryption: false,
        buildAudienceType: 'APP_STORE_ELIGIBLE',
      },
      {
        preReleaseVersion: { data: { id: 'pre' } },
        appEncryptionDeclaration: { data: null },
        appStoreVersion: { data: null },
      },
    ),
    included: [resource('pre', { version: '1.2.0', platform: 'IOS' })],
    selectedStatus: 404,
    selected: null,
    products: [
      resource('sub-annual', { productId: ANNUAL, state: 'READY_TO_SUBMIT' }),
      resource('sub-monthly', { productId: MONTHLY, state: 'READY_TO_SUBMIT' }),
    ],
    submissions: [],
    useFilteredSubmissions: false,
    items: {},
    whatsNew: meta.releaseNotes,
    description: meta.description,
    appInfos: [resource('info', { state: 'PREPARE_FOR_SUBMISSION' })],
  };
  mutate(state);
  const version = resource('version-120', {
    versionString: '1.2.0',
    platform: 'IOS',
    appVersionState: state.versionState,
  });
  const routes = {
    [`/v1/apps/${APP}`]: { data: resource(APP, { bundleId: state.bundleId }) },
    [`/v1/apps/${APP}/appStoreVersions`]: { data: state.versions ?? [version] },
    '/v1/builds': { data: state.build ? [state.build] : [], included: state.included },
    [`/v1/appStoreVersions/version-120/build`]: {
      status: state.selectedStatus,
      data: state.selected,
    },
    [`/v1/apps/${APP}/subscriptionGroups`]: { data: [resource('group', { referenceName: 'Pro' })] },
    '/v1/subscriptionGroups/group/subscriptions': { data: state.products },
    [state.useFilteredSubmissions ? '/v1/reviewSubmissions' : `/v1/apps/${APP}/reviewSubmissions`]: {
      data: state.submissions,
    },
    [`/v1/appStoreVersions/version-120/appStoreVersionLocalizations`]: {
      data: [
        resource('loc', {
          locale: locale.id,
          description: state.description,
          keywords: meta.keywords,
          supportUrl: meta.supportUrl,
          marketingUrl: meta.marketingUrl,
          promotionalText: meta.promotionalText,
          whatsNew: state.whatsNew,
        }),
      ],
    },
    [`/v1/apps/${APP}/appInfos`]: { data: state.appInfos },
    '/v1/appInfos/info/appInfoLocalizations': {
      data: [
        resource('app-loc', {
          locale: locale.id,
          name: meta.name,
          subtitle: meta.subtitle,
          privacyPolicyUrl: meta.privacyUrl,
        }),
      ],
    },
    ...state.items,
  };
  const asc = {
    calls: [],
    async request(path, query = {}) {
      const key = path.split('?')[0];
      asc.calls.push({ method: 'GET', path: key, query });
      const route = routes[key];
      if (!route) return { status: 404, pathname: key, body: {} };
      return { status: route.status ?? 200, pathname: key, body: route };
    },
    async get(path, query) {
      const result = await this.request(path, query);
      if (result.status !== 200) throw new Error(`ASC GET ${result.pathname} returned HTTP ${result.status}`);
      return result.body;
    },
    async all(path, query) {
      return (await this.get(path, query)).data;
    },
  };
  return { asc, manifest, evidence: async () => receipt };
}

const report = (input) => readReadiness(input);
const row = (rows, name) => rows.find((entry) => entry.check === name);

test('committed release notes are the post-#1197 text', () => {
  const notes = manifest.locales[0].metadata.releaseNotes;
  assert.equal(notes.startsWith(STALE_WHATS_NEW_PREFIX), false);
  assert.match(notes, /3-day free trial/);
  assert.match(notes, /sign-in resumed more than once/);
});

test('a processed selectable 1.2.0 build with Ready to Submit subscriptions passes', async () => {
  const rows = await report(world());
  assert.equal(rows.length, 7);
  assert.equal(rows.every((entry) => entry.pass), true);
  assert.match(row(rows, 'Version state').detail, /state=PREPARE_FOR_SUBMISSION/);
  assert.match(row(rows, 'Build processed and selectable').detail, /selectable; selected build=none/);
  assert.match(row(rows, ANNUAL).detail, /READY_TO_SUBMIT/);
  assert.match(row(rows, "What's New").detail, /post-#1197/);
});

test('an unselected build is selectable when the version relationship is empty or 404', async () => {
  for (const selectedStatus of [404, 200]) {
    const rows = await report(world((state) => {
      state.selectedStatus = selectedStatus;
      state.selected = null;
    }));
    assert.equal(row(rows, 'Build processed and selectable').pass, true, String(selectedStatus));
  }
});

test('an already selected exact build passes and a build linked elsewhere fails', async () => {
  const selected = await report(world((state) => {
    state.selectedStatus = 200;
    state.selected = resource('build-1', { version: BUILD_NUMBER });
    state.build.relationships.appStoreVersion = { data: { id: 'version-120' } };
  }));
  assert.match(row(selected, 'Build processed and selectable').detail, /already selected/);

  const linked = await report(world((state) => {
    state.build.relationships.appStoreVersion = { data: { id: 'other-version' } };
  }));
  const failed = row(linked, 'Build processed and selectable');
  assert.equal(failed.pass, false);
  assert.match(failed.action, /Tim-only T3/);
  assert.match(failed.detail, /linked version=other-version/);
});

test('processing, audience, and export compliance gate selectability', async () => {
  const processing = await report(world((state) => {
    state.build.attributes.processingState = 'PROCESSING';
  }));
  assert.equal(row(processing, 'Build processed and selectable').pass, false);

  const audience = await report(world((state) => {
    state.build.attributes.buildAudienceType = 'INTERNAL_ONLY';
  }));
  assert.equal(row(audience, 'Build processed and selectable').pass, false);

  for (const declaration of ['APPROVED', 'IN_REVIEW', undefined]) {
    const rows = await report(world((state) => {
      state.build.attributes.usesNonExemptEncryption = true;
      state.build.relationships.appEncryptionDeclaration = { data: { id: 'declaration' } };
      state.included.push(resource('declaration', { appEncryptionDeclarationState: declaration }));
    }));
    assert.equal(row(rows, 'Build processed and selectable').pass, declaration === 'APPROVED', String(declaration));
  }
});

test('Ready to Submit passes and another state passes only when attached to 1.2.0', async () => {
  const approved = await report(world((state) => {
    state.products[1].attributes.state = 'APPROVED';
  }));
  const monthly = row(approved, MONTHLY);
  assert.equal(monthly.pass, false);
  assert.match(monthly.action, /Tim-only T5/);
  assert.match(monthly.detail, /attachment to 1.2.0 not shown/);
  assert.equal(row(approved, ANNUAL).pass, true);

  const attached = await report(world((state) => {
    state.products[1].attributes.state = 'APPROVED';
    state.submissions = [resource('submission-1', { state: 'READY_FOR_REVIEW' })];
    state.items['/v1/reviewSubmissions/submission-1/items'] = {
      data: [
        { relationships: { appStoreVersion: { data: { id: 'version-120' } } } },
        { relationships: { subscription: { data: { id: 'sub-monthly' } } } },
      ],
    };
  }));
  assert.match(row(attached, MONTHLY).detail, /attached to 1.2.0/);
  assert.equal(row(attached, MONTHLY).pass, true);

  const filteredInput = world((state) => {
    state.products[1].attributes.state = 'APPROVED';
    state.useFilteredSubmissions = true;
    state.submissions = [resource('submission-1', { state: 'READY_FOR_REVIEW' })];
    state.items['/v1/reviewSubmissions/submission-1/items'] = {
      data: [
        { relationships: { appStoreVersion: { data: { id: 'version-120' } } } },
        { relationships: { subscription: { data: { id: 'sub-monthly' } } } },
      ],
    };
  });
  const filtered = await report(filteredInput);
  assert.equal(row(filtered, MONTHLY).pass, true);
  assert.equal(filteredInput.asc.calls.some((call) => call.path === '/v1/reviewSubmissions'), true);
});

test("What's New rejects the pre-#1197 sentence and metadata mismatches stay visible", async () => {
  const stale = await report(world((state) => {
    state.whatsNew = `${STALE_WHATS_NEW_PREFIX}, weight and body-fat logging.`;
  }));
  const whatsNew = row(stale, "What's New");
  assert.equal(whatsNew.pass, false);
  assert.match(whatsNew.detail, /stale pre-#1197/);
  assert.match(whatsNew.action, /Tim-only T6/);

  const metadata = await report(world((state) => {
    state.description = 'Different description';
  }));
  assert.equal(row(metadata, 'Storefront metadata').pass, false);
  assert.match(row(metadata, 'Storefront metadata').detail, /description/);
  assert.equal(row(metadata, "What's New").pass, true);
});

test('rejected and missing versions fail closed without dropping the other rows', async () => {
  const rejected = await report(world((state) => {
    state.versionState = 'REJECTED';
  }));
  assert.equal(row(rejected, 'Version state').pass, false);
  assert.match(row(rejected, 'Version state').action, /Tim-only T1/);
  assert.equal(rejected.filter((entry) => entry.pass).length >= 2, true);

  const missing = await report(world((state) => {
    state.versions = [];
  }));
  assert.match(row(missing, 'Version state').detail, /missing or ambiguous/);
  assert.match(row(missing, 'Build processed and selectable').detail, /unavailable/);
});

test('the newest upload is the newest successful TestFlight upload, not an older substitute', async () => {
  const wrong = await report({
    ...world(),
    evidence: async () => ({ ...receipt, version: '1.1.0', build: '9' }),
  });
  assert.match(row(wrong, 'Newest TestFlight upload').detail, /not 1\.2\.0/);
  assert.match(row(wrong, 'Build processed and selectable').detail, /cannot substitute/);

  const run = (id) => ({
    id,
    run_attempt: 1,
    head_sha: 'b'.repeat(40),
    head_branch: 'main',
    path: '.github/workflows/ios-release-loop.yml',
    repository: { full_name: 'JovieInc/LogYourBody' },
  });
  const uploadedJobs = [
    {
      name: 'Deploy to TestFlight / Deploy to TestFlight (alpha)',
      steps: [{ name: 'Upload to TestFlight', conclusion: 'success' }],
    },
    {
      id: 55,
      name: 'Validate Release',
      steps: [{ name: 'Extract version info', conclusion: 'success' }],
    },
  ];
  const logs = 'Version: 20261012.601\n2026-10-16T21:59:03.8785120Z 📦 Version: 1.2.0\n🔢 Build: 20261016215903\n';
  const queried = [];
  const github = async (path, raw) => {
    queried.push(path);
    if (path.includes('/workflows/')) {
      const page = path.endsWith('page=1') ? Array.from({ length: 100 }, (_, index) => run(500 - index)) : [run(7)];
      return [{ workflow_runs: page }];
    }
    if (raw) return logs;
    return [{ jobs: path.includes('/runs/7/') ? uploadedJobs : [] }];
  };
  assert.equal((await latestTestFlightUpload(github)).runId, 7);
  assert.equal(queried.some((path) => path.endsWith('page=2')), true);
  assert.equal(queried.some((path) => path.endsWith('page=3')), false);
});

test('ASC transport is GET-only and does not echo tokens or off-origin pages', async () => {
  const requests = [];
  const reader = new AscReader('private-token', async (url, options) => {
    requests.push({ url: String(url), options });
    return new Response(JSON.stringify({
      data: [{ id: String(requests.length) }],
      links: { next: requests.length === 1 ? 'https://api.appstoreconnect.apple.com/v1/apps?page=2' : null },
    }));
  });
  assert.deepEqual(await reader.all('/v1/apps'), [{ id: '1' }, { id: '2' }]);
  assert.equal(requests.every((entry) => entry.options.method === 'GET' && entry.options.redirect === 'error' && !entry.options.body), true);
  await assert.rejects(reader.get('https://other.example/key'), /origin/);
  const denied = new AscReader('private-token', async () => new Response('private-token secret body', { status: 403 }));
  await assert.rejects(denied.get('/v1/apps'), (error) => !error.message.includes('private-token') && error.message.includes('403'));
  const missing = await denied.request('/v1/appStoreVersions/version-120/build');
  assert.equal(missing.status, 403);
  const cycling = new AscReader('token', async () => new Response(JSON.stringify({ data: [], links: { next: '/v1/apps' } })));
  await assert.rejects(cycling.all('/v1/apps'), /repeated a page/);
});

test('JWT matches the release client claims and never returns key material', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const token = createToken({
    ASC_KEY_ID: 'key-id',
    ASC_ISSUER_ID: 'issuer',
    ASC_PRIVATE_KEY: pem.replaceAll('\n', '\\n'),
  }, 1_000);
  const [header, payload, signature] = token.split('.');
  assert.equal(JSON.parse(Buffer.from(header, 'base64url')).alg, 'ES256');
  const claims = JSON.parse(Buffer.from(payload, 'base64url'));
  assert.deepEqual(Object.keys(claims).sort(), ['aud', 'exp', 'iat', 'iss']);
  assert.equal(claims.aud, 'appstoreconnect-v1');
  assert.equal(claims.exp - claims.iat, 1200);
  assert.equal(claims.scope, undefined);
  assert.equal(verify('sha256', Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')), true);
  const secret = 'BEGIN PRIVATE KEY MATERIAL should-not-leak';
  assert.throws(() => createToken({ ASC_KEY_ID: 'kid', ASC_ISSUER_ID: 'iss', ASC_PRIVATE_KEY: secret }), (error) => {
    assert.equal(error.message.includes('should-not-leak'), false);
    return true;
  });
});

test('GitHub log reads allow escape sequences and the workflow stays read-only', () => {
  const args = githubApiArguments('repos/JovieInc/LogYourBody/actions/jobs/1/logs', { raw: true });
  assert.equal(args.includes('--allow-escape-sequences'), true);
  assert.equal(args.includes('--method'), true);
  assert.equal(args.includes('GET'), true);
  assert.equal(args.includes('--paginate'), false);
  const source = readFileSync(new URL('./app-store-readiness.mjs', import.meta.url), 'utf8');
  for (const method of ['POST', 'PATCH', 'PUT', 'DELETE']) {
    assert.equal(source.includes(`method: '${method}'`), false);
  }
  const workflow = readFileSync(new URL('../workflows/app-store-connect-readiness.yml', import.meta.url), 'utf8');
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /branches: \[main\]/);
  assert.match(workflow, /\.github\/workflows\/app-store-connect-readiness\.yml/);
  assert.match(workflow, /apps\/ios\/fastlane\/metadata\/\*\*/);
  assert.match(workflow, /storefront-manifest\.generated\.json/);
  assert.match(workflow, /cron: '0 16 \* \* \*'/);
  assert.match(workflow, /workflow_run:/);
  assert.match(workflow, /App Store Metadata Sync/);
  assert.doesNotMatch(workflow, /pull_request:|contents: write|actions: write|environment:/);
  assert.match(workflow, /contents: read/);
  assert.match(workflow, /actions: read/);
  assert.match(workflow, /secrets\.APP_STORE_CONNECT_API_KEY_ID/);
  assert.match(workflow, /secrets\.APP_STORE_CONNECT_API_KEY_ISSUER_ID/);
  assert.match(workflow, /secrets\.APP_STORE_CONNECT_API_KEY }}/);
  assert.equal(workflow.includes('submit_for_review'), false);
});

test('metadata sync uses deliver without a binary, submit, or screenshot upload', () => {
  const workflow = readFileSync(new URL('../workflows/app-store-metadata-sync.yml', import.meta.url), 'utf8');
  assert.match(workflow, /upload_to_app_store/);
  assert.match(workflow, /skip_binary_upload:true/);
  assert.match(workflow, /skip_screenshots:true/);
  assert.match(workflow, /submit_for_review:false/);
  assert.match(workflow, /app_version:"1\.2\.0"/);
  assert.match(workflow, /metadata_path:"fastlane\/metadata"/);
  assert.match(workflow, /release_notes\.txt/);
  assert.match(workflow, /whats_new: notes/);
  assert.match(workflow, /apps\/ios\/fastlane\/metadata\/\*\*/);
  assert.match(workflow, /contents: read/);
  assert.equal(workflow.includes('actions:'), false);
  assert.doesNotMatch(workflow, /pull_request:|contents: write|actions: write|environment:|reject_if_possible|build_number:|automatic_release|ipa:/);
});

test('the summary escapes markup and names a Tim-only item for every failure', () => {
  const summary = renderSummary([
    { check: 'Check', pass: false, detail: 'bad | state\n<script>', action: 'Tim-only T1: fix it' },
  ]);
  assert.match(summary, /FAIL/);
  assert.match(summary, /Tim-only T1/);
  assert.equal(summary.includes('<script>'), false);
  assert.equal(summary.includes('bad | state'), false);
  assert.match(summary, /#1197/);
});
