import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { generateKeyPairSync, verify } from 'node:crypto';
import test from 'node:test';
import {
  AscReader,
  createToken,
  latestTestFlightUpload,
  readReadiness,
  renderSummary,
} from './app-store-readiness.mjs';

const manifest = JSON.parse(
  readFileSync(
    new URL('../../apps/ios/fastlane/storefront-manifest.generated.json', import.meta.url),
  ),
);
const metadata = manifest.locales[0].metadata;
const productIds = [
  'com.logyourbody.app.pro1.annual.3daytrial',
  'com.logyourbody.app.pro1.monthly.3daytrial',
];
const resource = (id, attributes = {}, relationships = {}) => ({ id, attributes, relationships });
const run = (id, overrides = {}) => ({
  id,
  run_attempt: 1,
  head_branch: 'main',
  head_sha: 'a'.repeat(40),
  path: '.github/workflows/ios-release-loop.yml',
  repository: { full_name: 'JovieInc/LogYourBody' },
  html_url: `https://github.com/JovieInc/LogYourBody/actions/runs/${id}`,
  ...overrides,
});
const uploadJob = (overrides = {}) => ({
  id: 21,
  name: 'Deploy to TestFlight / Deploy to TestFlight (alpha)',
  steps: [{ name: 'Upload to TestFlight', conclusion: 'success' }],
  ...overrides,
});
const validationJob = {
  id: 22,
  name: 'Validate Release',
  steps: [{ name: 'Extract version info', conclusion: 'success' }],
};
const logs =
  '2026-10-16T22:00:00.000Z echo "📦 Version: $VERSION"\n2026-10-16T22:00:00.000Z 📦 Version: 1.2.0\n2026-10-16T22:00:00.000Z 🔢 Build: 20261016215903\n';
const receipt = {
  runId: 1,
  attempt: 1,
  sha: 'a'.repeat(40),
  url: run(1).html_url,
  version: '1.2.0',
  build: '20261016215903',
};

function fixture() {
  const data = {
    '/v1/apps/6755209876': resource('6755209876', { bundleId: 'com.logyourbody.app' }),
    '/v1/apps/6755209876/appStoreVersions': [
      resource('version', {
        platform: 'IOS',
        versionString: '1.2.0',
        appVersionState: 'PREPARE_FOR_SUBMISSION',
      }),
    ],
    '/v1/builds': [
      resource(
        'build',
        {
          version: receipt.build,
          processingState: 'VALID',
          expired: false,
          buildAudienceType: 'APP_STORE_ELIGIBLE',
          usesNonExemptEncryption: false,
        },
        {
          preReleaseVersion: { data: { id: 'prerelease' } },
          appEncryptionDeclaration: { data: null },
          appStoreVersion: { data: null },
        },
      ),
    ],
    '/v1/appStoreVersions/version/build': null,
    '/v1/apps/6755209876/subscriptionGroups': [resource('group')],
    '/v1/subscriptionGroups/group/subscriptions': productIds.map((productId, i) =>
      resource(`sub${i}`, { productId, state: 'READY_TO_SUBMIT' }),
    ),
    '/v1/appStoreVersions/version/appStoreVersionLocalizations': [
      resource('loc', { locale: 'en-US', ...metadata, whatsNew: metadata.releaseNotes }),
    ],
    '/v1/apps/6755209876/appInfos': [resource('info', { state: 'PREPARE_FOR_SUBMISSION' })],
    '/v1/appInfos/info/appInfoLocalizations': [
      resource('info-loc', {
        locale: 'en-US',
        name: metadata.name,
        subtitle: metadata.subtitle,
        privacyPolicyUrl: metadata.privacyUrl,
      }),
    ],
  };
  const included = [resource('prerelease', { version: '1.2.0', platform: 'IOS' })];
  const calls = [];
  const asc = {
    async get(path, query) {
      calls.push([path, query]);
      if (!(path in data)) throw new Error(`Unexpected fixture path ${path}`);
      return { data: structuredClone(data[path]), included: structuredClone(included) };
    },
    async all(path, query) {
      return (await this.get(path, query)).data;
    },
  };
  return { data, included, calls, asc };
}
const report = (f, evidence = async () => receipt) =>
  readReadiness({ asc: f.asc, evidence, manifest });

test('complete live readback passes without requiring or performing a build attach', async () => {
  const f = fixture();
  const rows = await report(f);
  assert.equal(rows.length, 7);
  assert(rows.every((row) => row.pass));
  assert.match(renderSummary(rows), /Read-only/);
  assert(
    f.calls.some(
      ([path, query]) => path === '/v1/builds' && query['filter[version]'] === receipt.build,
    ),
  );
});

test('newest upload wins even when its processing/distribution job failed; non-upload runs are skipped', async () => {
  const queried = [];
  const github = async (path, raw) => {
    queried.push(path);
    if (path.includes('/workflows/'))
      return [{ workflow_runs: [run(3), run(2, { conclusion: 'failure' }), run(1)] }];
    if (path.includes('/runs/3/'))
      return [
        {
          jobs: [
            { ...uploadJob(), steps: [{ name: 'Upload to TestFlight', conclusion: 'skipped' }] },
          ],
        },
      ];
    if (path.includes('/runs/2/'))
      return [{ jobs: [uploadJob({ conclusion: 'failure' }), validationJob] }];
    if (raw) return logs;
    throw new Error('Must not fall back to an older upload');
  };
  const result = await latestTestFlightUpload(github);
  assert.equal(result.runId, 2);
  assert.equal(result.build, receipt.build);
  assert(!queried.some((path) => path.includes('/runs/1/')));
});

test('release provenance rejects wrong branch/repo/workflow and never substitutes a manually picked build', async () => {
  const github = async () => [
    {
      workflow_runs: [
        run(1, { head_branch: 'feature' }),
        run(2, { repository: { full_name: 'other/repo' } }),
        run(3, { path: '.github/workflows/other.yml' }),
      ],
    },
  ];
  await assert.rejects(latestTestFlightUpload(github), /No successful TestFlight upload/);
});

test('missing or ambiguous version/build logs fail closed at the newest upload', async () => {
  for (const invalid of [
    '',
    logs + logs.replace(receipt.build, '20261016220000'),
    logs.replace('1.2.0', '1.3.0') + logs,
  ]) {
    const github = async (path, raw) =>
      raw
        ? invalid
        : path.includes('/workflows/')
          ? [{ workflow_runs: [run(1)] }]
          : [{ jobs: [uploadJob(), validationJob] }];
    await assert.rejects(latestTestFlightUpload(github), /version\/build receipt/);
  }
});

test('pending/invalid/expired/wrong-version/wrong-platform builds cannot pass', async () => {
  const mutations = [
    (f) => {
      f.data['/v1/builds'][0].attributes.processingState = 'PROCESSING';
    },
    (f) => {
      f.data['/v1/builds'][0].attributes.processingState = 'INVALID';
    },
    (f) => {
      f.data['/v1/builds'][0].attributes.expired = true;
    },
    (f) => {
      f.included[0].attributes.version = '1.1.0';
    },
    (f) => {
      f.included[0].attributes.platform = 'MAC_OS';
    },
    (f) => {
      f.data['/v1/builds'][0].attributes.usesNonExemptEncryption = null;
    },
    (f) => {
      f.data['/v1/builds'][0].attributes.buildAudienceType = 'INTERNAL_ONLY';
    },
    (f) => {
      f.data['/v1/builds'] = [];
    },
    (f) => {
      f.data['/v1/builds'][0].relationships.appStoreVersion.data = { id: 'other-version' };
    },
  ];
  for (const mutate of mutations) {
    const f = fixture();
    mutate(f);
    const rows = await report(f);
    assert.equal(rows.find((row) => row.check === 'Build processed and selectable').pass, false);
    assert(rows.filter((row) => !row.pass).every((row) => row.action.startsWith('Tim-only')));
  }
});

test('latest upload with wrong marketing version and missing receipts do not pass an older build', async () => {
  for (const evidence of [
    async () => ({ ...receipt, version: '1.3.0' }),
    async () => {
      throw new Error('GitHub receipt unavailable');
    },
  ]) {
    const rows = await report(fixture(), evidence);
    assert.equal(rows.find((row) => row.check === 'Build processed and selectable').pass, false);
    assert.equal(rows.find((row) => row.check === "What's New").pass, true);
  }
});

test('stale pre-1197 or blank What’s New fails; a different nonblank text also fails', async () => {
  for (const whatsNew of [
    '',
    'Private body-composition timeline with a single time-weighted photo scrubber, weight and body-fat logging, optional Apple Health context, Stats, restore purchases, data export, and account deletion.',
    'Bug fixes.',
  ]) {
    const f = fixture();
    f.data['/v1/appStoreVersions/version/appStoreVersionLocalizations'][0].attributes.whatsNew =
      whatsNew;
    const rows = await report(f);
    assert.equal(rows.find((row) => row.check === "What's New").pass, false);
  }
});

test('missing or stale version/app-info metadata fails, including locales absent from ASC', async () => {
  for (const mutate of [
    (f) => {
      f.data[
        '/v1/appStoreVersions/version/appStoreVersionLocalizations'
      ][0].attributes.description = '';
    },
    (f) => {
      f.data['/v1/appStoreVersions/version/appStoreVersionLocalizations'] = [];
    },
    (f) => {
      f.data['/v1/appInfos/info/appInfoLocalizations'][0].attributes.privacyPolicyUrl = '';
    },
    (f) => {
      f.data['/v1/apps/6755209876/appInfos'] = [];
    },
  ]) {
    const f = fixture();
    mutate(f);
    assert.equal((await report(f)).find((row) => row.check === 'Storefront metadata').pass, false);
  }
});

test('both exact subscription IDs are required; approval/review alone does not prove attachment to 1.2.0', async () => {
  for (const state of [
    'MISSING_METADATA',
    'WAITING_FOR_REVIEW',
    'IN_REVIEW',
    'APPROVED',
    'DEVELOPER_ACTION_NEEDED',
  ]) {
    const f = fixture();
    f.data['/v1/subscriptionGroups/group/subscriptions'][0].attributes.state = state;
    const rows = await report(f);
    assert.equal(rows.find((row) => row.check === productIds[0]).pass, false);
    assert.match(rows.find((row) => row.check === productIds[0]).action, /attachment/);
  }
  const f = fixture();
  f.data['/v1/subscriptionGroups/group/subscriptions'].pop();
  assert.equal((await report(f)).find((row) => row.check === productIds[1]).pass, false);
});

test('missing version, rejected state, and wrong app identity fail without hiding other rows', async () => {
  for (const mutate of [
    (f) => {
      f.data['/v1/apps/6755209876/appStoreVersions'] = [];
    },
    (f) => {
      f.data['/v1/apps/6755209876/appStoreVersions'][0].attributes.appVersionState = 'REJECTED';
    },
    (f) => {
      f.data['/v1/apps/6755209876'].attributes.bundleId = 'other.app';
    },
  ]) {
    const f = fixture();
    mutate(f);
    const rows = await report(f);
    assert.equal(rows.length, 7);
    assert(rows.some((row) => !row.pass));
  }
});

test('API failures remain red and leave independent checks visible', async () => {
  const f = fixture();
  const get = f.asc.get;
  f.asc.get = async (path, query) => {
    if (path.includes('/subscriptions')) throw new Error('ASC GET returned HTTP 403');
    return get.call(f.asc, path, query);
  };
  const rows = await report(f);
  assert.equal(rows.filter((row) => row.pass).length, 5);
  assert.match(renderSummary(rows), /Tim-only/);
});

test('ASC transport sends GET only, follows pagination, and blocks off-origin links and redirects', async () => {
  const requests = [];
  const reader = new AscReader('private-token', async (url, options) => {
    requests.push({ url: String(url), options });
    return new Response(
      JSON.stringify({
        data: [{ id: requests.length }],
        links: {
          next:
            requests.length === 1 ? 'https://api.appstoreconnect.apple.com/v1/apps?page=2' : null,
        },
      }),
    );
  });
  assert.deepEqual(await reader.all('/v1/apps'), [{ id: 1 }, { id: 2 }]);
  assert(
    requests.every(
      (r) => r.options.method === 'GET' && r.options.redirect === 'error' && !r.options.body,
    ),
  );
  await assert.rejects(reader.get('https://other.example/key'), /origin/);
  await assert.rejects(reader.get('//other.example/key'), /origin/);
  const failed = new AscReader(
    'private-token',
    async () => new Response('private-token secret body', { status: 403 }),
  );
  await assert.rejects(
    failed.get('/v1/apps'),
    (error) => !error.message.includes('private-token') && error.message.includes('403'),
  );
});

test('JWT uses existing release secrets, ES256, bounded lifetime, and a GET-only scope', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const token = createToken(
    {
      ASC_KEY_ID: 'key-id',
      ASC_ISSUER_ID: 'issuer',
      ASC_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }).replaceAll('\n', '\\n'),
    },
    1000,
  );
  const [header, payload, signature] = token.split('.');
  assert.equal(JSON.parse(Buffer.from(header, 'base64url')).alg, 'ES256');
  const claims = JSON.parse(Buffer.from(payload, 'base64url'));
  assert.equal(claims.exp - claims.iat, 1200);
  assert(claims.scope.every((scope) => scope.startsWith('GET ')));
  assert(
    verify(
      'sha256',
      Buffer.from(`${header}.${payload}`),
      { key: publicKey, dsaEncoding: 'ieee-p1363' },
      Buffer.from(signature, 'base64url'),
    ),
  );
});

test('App Store audience and encryption approval are required independently of processing', async () => {
  for (const state of ['APPROVED', 'IN_REVIEW', 'REJECTED', undefined]) {
    const f = fixture();
    f.data['/v1/builds'][0].attributes.usesNonExemptEncryption = true;
    f.data['/v1/builds'][0].relationships.appEncryptionDeclaration = {
      data: { id: 'declaration' },
    };
    f.included.push(resource('declaration', { appEncryptionDeclarationState: state }));
    const row = (await report(f)).find((row) => row.check === 'Build processed and selectable');
    assert.equal(row.pass, state === 'APPROVED');
  }
});

test('already selected exact build passes and is identified separately from an unselected build', async () => {
  const f = fixture();
  f.data['/v1/appStoreVersions/version/build'] = resource('build', { version: receipt.build });
  f.data['/v1/builds'][0].relationships.appStoreVersion = { data: { id: 'version' } };
  const row = (await report(f)).find((row) => row.check === 'Build processed and selectable');
  assert(row.pass);
  assert.match(row.detail, /already selected/);
});

test('run pagination stops at the newest proven upload and ASC pagination cycles fail closed', async () => {
  const queried = [];
  const github = async (path, raw) => {
    queried.push(path);
    if (path.includes('/workflows/')) {
      return [
        {
          workflow_runs: path.endsWith('page=1')
            ? Array.from({ length: 100 }, (_, i) => run(200 - i))
            : [run(1)],
        },
      ];
    }
    if (raw) return logs;
    return [{ jobs: path.includes('/runs/1/') ? [uploadJob(), validationJob] : [] }];
  };
  assert.equal((await latestTestFlightUpload(github)).runId, 1);
  assert(queried.some((path) => path.endsWith('page=2')));
  assert(!queried.some((path) => path.endsWith('page=3')));
  const reader = new AscReader(
    'token',
    async () => new Response(JSON.stringify({ data: [], links: { next: '/v1/apps' } })),
  );
  await assert.rejects(reader.all('/v1/apps'), /repeated a page/);
});

test('summary escapes table markup and assigns a named Tim-only item to every red row', () => {
  const summary = renderSummary([
    { check: 'Check', pass: false, detail: 'bad | state\n<script>', action: 'Tim-only T1: fix it' },
  ]);
  assert.match(summary, /FAIL/);
  assert.match(summary, /Tim-only T1/);
  assert(!summary.includes('<script>'));
  assert(!summary.includes('bad | state'));
});
