import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  APP_BUNDLE_ID,
  ESCALATE_DAYS,
  FINGERPRINT,
  WARN_DAYS,
  assertPublicReport,
  assertSparseQuery,
  buildIssue,
  buildSigningRows,
  createSigningClient,
  daysUntil,
  deliverSigningExpiry,
  formatReport,
  loadSigningAssets,
  parseRequiredBundleIds,
  projectCertificates,
  projectProfiles,
  readRequiredBundleIds,
  severity,
} from './signing-expiry.mjs';

const NOW = Date.parse('2026-10-25T00:00:00Z');
const SECRET_CONTENT = 'M'.repeat(40) + 'SECRETCONTENTONLYFORTEST' + 'A'.repeat(40);
const SECRET_SERIAL = 'SERIALSHOULDNOTLEAK99';
const SECRET_KEY = 'ABCD123456';
const SECRET_PASSWORD = 'match-secret-value';

const REQUIRED_BUNDLE_IDS = ['com.logyourbody.app', 'com.logyourbody.app.rest-timer'];
const isoDays = (days) => new Date(NOW + days * 86_400_000).toISOString();

function assets({
  certDays = [200],
  profileDays = [180],
  unusedCertDays = [],
  key = { authenticated: true, expirationDate: null },
  requiredBundleIds = REQUIRED_BUNDLE_IDS,
  certificateType = 'IOS_DISTRIBUTION',
} = {}) {
  const certificates = certDays.map((days) => ({
    certificateType,
    expirationDate: isoDays(days),
  }));
  const valid = certificates.filter(
    (certificate) => daysUntil(certificate.expirationDate, NOW) >= 0,
  );
  const embedded = (valid.length > 0 ? valid : certificates).map((certificate) => ({
    ...certificate,
  }));
  return {
    certificatesReadable: true,
    profilesReadable: true,
    requiredBundleIds,
    certificates: [
      ...certificates,
      ...unusedCertDays.map((days) => ({
        certificateType,
        expirationDate: isoDays(days),
      })),
    ],
    profiles: requiredBundleIds.map((bundleId, index) => ({
      bundleId,
      profileType: 'IOS_APP_STORE',
      profileState: 'ACTIVE',
      expirationDate: isoDays(profileDays[Math.min(index, Math.max(profileDays.length - 1, 0))]),
      certificateLink: embedded.length > 0 ? 'ok' : 'unreadable',
      certificates: embedded,
    })),
    apiKey: key,
  };
}

test('days until expiry uses whole UTC days and does not echo the raw date', () => {
  assert.equal(daysUntil(isoDays(30), NOW), 30);
  assert.equal(daysUntil(isoDays(7), NOW), 7);
  assert.equal(daysUntil(isoDays(0), NOW), 0);
  assert.equal(daysUntil(isoDays(-2), NOW), -2);
  assert.equal(daysUntil(SECRET_KEY, NOW), null);
  assert.equal(daysUntil(123456, NOW), null);
});

test('required bundle ids are the Matchfile app_identifier list', () => {
  const source = readFileSync(
    new URL('../../apps/ios/fastlane/Matchfile', import.meta.url),
    'utf8',
  );
  assert.deepEqual(parseRequiredBundleIds(source), REQUIRED_BUNDLE_IDS);
  assert.deepEqual(readRequiredBundleIds(), REQUIRED_BUNDLE_IDS);
  const commented = `
    # app_identifier(["com.example.commented"])
    app_identifier([
      "com.logyourbody.app",
      "com.logyourbody.app.rest-timer"
    ])
    app_identifier("com.example.later")
  `;
  assert.deepEqual(parseRequiredBundleIds(commented), REQUIRED_BUNDLE_IDS);
  assert.deepEqual(parseRequiredBundleIds('app_identifier("com.logyourbody.app")'), [
    'com.logyourbody.app',
  ]);
  assert.deepEqual(parseRequiredBundleIds('type("development")'), []);
});

test('a missing profile for a required bundle id escalates', () => {
  const present = assets({ certDays: [400], profileDays: [180] });
  present.profiles = present.profiles.filter(
    (profile) => profile.bundleId !== 'com.logyourbody.app.rest-timer',
  );
  const rows = buildSigningRows(present, NOW);
  const report = formatReport(rows);
  assert.match(
    report,
    /^com\.logyourbody\.app IOS_APP_STORE: 180 days \(IOS_DISTRIBUTION, 400 days\)$/m,
  );
  assert.match(report, /^com\.logyourbody\.app\.rest-timer IOS_APP_STORE: missing$/m);
  assert.equal(severity(rows), 'escalate');
  const issue = buildIssue(rows, 'https://example.com/run');
  assert.equal(issue.priority, 1);
  assert.match(issue.description, /ESCALATED/);
  assert.match(issue.description, /com\.logyourbody\.app\.rest-timer IOS_APP_STORE: missing/);
  assert.doesNotMatch(issue.description, /SERIAL|certificateContent|CERTID/);
});

test('an unused distribution cert expiring soon does not warn or escalate', () => {
  const rows = buildSigningRows(
    assets({ certDays: [400], profileDays: [180], unusedCertDays: [25, -4] }),
    NOW,
  );
  const report = formatReport(rows);
  assert.match(report, /^distribution certificate IOS_DISTRIBUTION: 400 days$/m);
  assert.match(report, /^unused distribution certificate IOS_DISTRIBUTION: 25 days$/m);
  assert.doesNotMatch(report, /-4 days/);
  assert.equal(severity(rows), 'ok');
  assert.equal(buildIssue(rows, 'https://example.com/run'), null);
});

test('an in-use distribution cert expiring soon escalates', () => {
  const rows = buildSigningRows(
    assets({ certDays: [6], profileDays: [180], unusedCertDays: [400] }),
    NOW,
  );
  const report = formatReport(rows);
  assert.match(report, /^distribution certificate IOS_DISTRIBUTION: 6 days$/m);
  assert.match(report, /^unused distribution certificate IOS_DISTRIBUTION: 400 days$/m);
  assert.match(report, /IOS_APP_STORE: 180 days \(IOS_DISTRIBUTION, 6 days\)/);
  assert.equal(severity(rows), 'escalate');
  assert.equal(buildIssue(rows, 'https://example.com/run').priority, 1);
});

test('development certificates are not the distribution cert', () => {
  const fixture = assets({ certDays: [50], profileDays: [90], certificateType: 'DISTRIBUTION' });
  fixture.certificates.push({ certificateType: 'IOS_DEVELOPMENT', expirationDate: isoDays(3) });
  const rows = buildSigningRows(fixture, NOW);
  const cert = rows.find((row) => row.kind === 'distribution-certificate' && !row.unused);
  assert.equal(cert.certificateType, 'DISTRIBUTION');
  assert.equal(cert.daysRemaining, 50);
  assert.equal(
    rows.some((row) => row.certificateType === 'IOS_DEVELOPMENT'),
    false,
  );
  assert.doesNotMatch(formatReport(rows), /IOS_DEVELOPMENT/);
});

test('missing or fully expired distribution cert and profile escalate', () => {
  const missing = buildSigningRows({ ...assets(), certificates: [], profiles: [] }, NOW);
  assert.equal(severity(missing), 'escalate');
  assert.match(formatReport(missing), /distribution certificate: missing/);
  assert.match(formatReport(missing), /IOS_APP_STORE: missing/);
  const expired = buildSigningRows(assets({ certDays: [-1], profileDays: [40] }), NOW);
  const cert = expired.find((row) => row.kind === 'distribution-certificate');
  assert.equal(cert.daysRemaining, -1);
  assert.equal(cert.unused, false);
  assert.equal(severity(expired), 'escalate');
});

test('each required app store profile is named by bundle id and other bundles are dropped', () => {
  const certId = 'CERTIDSHOULDNOTLEAK99';
  const projected = projectProfiles(
    {
      data: [
        {
          attributes: {
            profileType: 'IOS_APP_STORE',
            profileState: 'ACTIVE',
            expirationDate: isoDays(10),
            profileContent: SECRET_CONTENT,
            uuid: SECRET_SERIAL,
            name: SECRET_KEY,
          },
          relationships: {
            bundleId: { data: { id: 'app' } },
            certificates: { data: [{ id: certId, type: 'certificates' }] },
          },
        },
        {
          attributes: {
            profileType: 'IOS_APP_STORE',
            profileState: 'ACTIVE',
            expirationDate: isoDays(3),
            profileContent: SECRET_CONTENT,
          },
          relationships: {
            bundleId: { data: { id: 'extension' } },
            certificates: { data: [{ id: certId, type: 'certificates' }] },
          },
        },
        {
          attributes: {
            profileType: 'IOS_APP_STORE',
            profileState: 'ACTIVE',
            expirationDate: isoDays(1),
          },
          relationships: { bundleId: { data: { id: 'other' } } },
        },
        {
          attributes: {
            profileType: 'IOS_APP_DEVELOPMENT',
            profileState: 'ACTIVE',
            expirationDate: isoDays(1),
          },
          relationships: { bundleId: { data: { id: 'app' } } },
        },
        {
          attributes: {
            profileType: 'IOS_APP_STORE',
            profileState: 'INVALID',
            expirationDate: isoDays(1),
          },
          relationships: { bundleId: { data: { id: 'app' } } },
        },
      ],
      included: [
        { type: 'bundleIds', id: 'app', attributes: { identifier: APP_BUNDLE_ID } },
        {
          type: 'bundleIds',
          id: 'extension',
          attributes: { identifier: `${APP_BUNDLE_ID}.widget` },
        },
        { type: 'bundleIds', id: 'other', attributes: { identifier: 'com.example.other' } },
        {
          type: 'certificates',
          id: certId,
          attributes: {
            certificateType: 'IOS_DISTRIBUTION',
            expirationDate: isoDays(80),
            certificateContent: SECRET_CONTENT,
            serialNumber: SECRET_SERIAL,
          },
        },
      ],
    },
    [APP_BUNDLE_ID, `${APP_BUNDLE_ID}.widget`, `${APP_BUNDLE_ID}.rest-timer`],
  );
  assert.equal(projected.length, 2);
  assert.deepEqual(Object.keys(projected[0]).sort(), [
    'bundleId',
    'certificateLink',
    'certificates',
    'expirationDate',
    'profileState',
    'profileType',
  ]);
  assert.deepEqual(projected[0].certificates, [
    { certificateType: 'IOS_DISTRIBUTION', expirationDate: isoDays(80) },
  ]);
  const rows = buildSigningRows(
    {
      ...assets({ certDays: [80] }),
      requiredBundleIds: [APP_BUNDLE_ID, `${APP_BUNDLE_ID}.widget`, `${APP_BUNDLE_ID}.rest-timer`],
      profiles: projected,
    },
    NOW,
  );
  const report = formatReport(rows);
  assert.match(
    report,
    new RegExp(`${APP_BUNDLE_ID.replaceAll('.', '\\.')} IOS_APP_STORE: 10 days`),
  );
  assert.match(
    report,
    new RegExp(`${APP_BUNDLE_ID.replaceAll('.', '\\.')}\\.widget IOS_APP_STORE: 3 days`),
  );
  assert.match(
    report,
    new RegExp(`${APP_BUNDLE_ID.replaceAll('.', '\\.')}\\.rest-timer IOS_APP_STORE: missing`),
  );
  assert.doesNotMatch(report, /app store profile 1/);
  assert.doesNotMatch(report, /com\.example\.other/);
  assert.doesNotMatch(report, new RegExp(SECRET_CONTENT));
  assert.doesNotMatch(report, new RegExp(SECRET_SERIAL));
  assert.doesNotMatch(report, new RegExp(SECRET_KEY));
  assert.doesNotMatch(report, new RegExp(certId));
  assert.equal(severity(rows), 'escalate');
});

test('certificate projection drops material, serials, and names', () => {
  const projected = projectCertificates({
    data: [
      {
        id: SECRET_KEY,
        attributes: {
          certificateType: 'IOS_DISTRIBUTION',
          expirationDate: isoDays(80),
          certificateContent: SECRET_CONTENT,
          serialNumber: SECRET_SERIAL,
          displayName: SECRET_KEY,
        },
      },
    ],
  });
  assert.deepEqual(projected, [
    { certificateType: 'IOS_DISTRIBUTION', expirationDate: isoDays(80) },
  ]);
});

test('api key with no Apple date is reported and does not warn by itself', () => {
  const rows = buildSigningRows(assets(), NOW);
  assert.match(formatReport(rows), /asc api key: no expiration date/);
  assert.equal(severity(rows), 'ok');
  assert.equal(buildIssue(rows, 'https://example.com/run'), null);
});

test('rejected api key is zero days and escalates', () => {
  const rows = buildSigningRows(
    assets({ key: { authenticated: false, expirationDate: null } }),
    NOW,
  );
  assert.match(formatReport(rows), /asc api key: unreadable/);
  assert.equal(severity(rows), 'escalate');
});

test('dated api key uses its expiration', () => {
  const rows = buildSigningRows(
    assets({ key: { authenticated: true, expirationDate: isoDays(6) } }),
    NOW,
  );
  assert.match(formatReport(rows), /asc api key: 6 days/);
  assert.equal(severity(rows), 'escalate');
});

test('under 30 files one high issue and under 7 escalates the same fingerprint', () => {
  const warn = buildSigningRows(assets({ certDays: [30], profileDays: [29] }), NOW);
  const urgent = buildSigningRows(assets({ certDays: [7], profileDays: [6] }), NOW);
  assert.equal(severity(warn), 'warn');
  assert.equal(severity(urgent), 'escalate');
  assert.equal(
    severity(buildSigningRows(assets({ certDays: [30], profileDays: [30] }), NOW)),
    'ok',
  );
  assert.equal(
    severity(buildSigningRows(assets({ certDays: [7], profileDays: [40] }), NOW)),
    'warn',
  );
  const warnIssue = buildIssue(warn, 'https://example.com/run');
  const urgentIssue = buildIssue(urgent, 'https://example.com/run');
  assert.equal(warnIssue.fingerprint, FINGERPRINT);
  assert.equal(urgentIssue.fingerprint, FINGERPRINT);
  assert.equal(warnIssue.label, FINGERPRINT);
  assert.equal(urgentIssue.label, FINGERPRINT);
  assert.equal(warnIssue.priority, 2);
  assert.equal(urgentIssue.priority, 1);
  assert.equal(warnIssue.reopenTerminal, true);
  assert.equal(urgentIssue.reopenTerminal, true);
  assert.match(urgentIssue.description, /ESCALATED/);
  assert.match(
    urgentIssue.description,
    /Source-workflow: \.github\/workflows\/signing-expiry\.yml/,
  );
  assert.match(urgentIssue.description, /NUKE-AND-REGENERATE/);
  assert.doesNotMatch(`${warnIssue.title}\n${warnIssue.description}`, /match_nuke/);
  assert.equal(WARN_DAYS, 30);
  assert.equal(ESCALATE_DAYS, 7);
});

test('report and issue text reject key ids, passwords, and certificate material', () => {
  const rows = buildSigningRows(assets({ certDays: [12], profileDays: [12] }), NOW);
  const issue = buildIssue(rows, 'https://example.com/run');
  const text = `${formatReport(rows)}\n${issue.description}`;
  assertPublicReport(text, [SECRET_KEY, SECRET_PASSWORD, SECRET_CONTENT]);
  assert.throws(() => assertPublicReport(`${text}\n${SECRET_KEY}`, [SECRET_KEY]));
  assert.throws(() => assertPublicReport(`-----BEGIN PRIVATE KEY-----\n${SECRET_CONTENT}`));
  assert.throws(() => assertPublicReport(SECRET_CONTENT));
  assert.throws(() => assertSparseQuery({ 'fields[certificates]': 'certificateContent' }));
});

test('client is GET-only, sparse, and follows same-origin pages', async () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const calls = [];
  const fetcher = async (url, options) => {
    calls.push({
      url: String(url),
      method: options.method,
      authorization: options.headers.Authorization,
    });
    const page = String(url);
    if (!page.includes('cursor=2')) {
      return new Response(
        JSON.stringify({
          data: [
            {
              attributes: {
                certificateType: 'IOS_DISTRIBUTION',
                expirationDate: isoDays(40),
                certificateContent: SECRET_CONTENT,
                serialNumber: SECRET_SERIAL,
              },
            },
          ],
          links: { next: 'https://api.appstoreconnect.apple.com/v1/certificates?cursor=2' },
        }),
        { status: 200 },
      );
    }
    return new Response(
      JSON.stringify({
        data: [
          { attributes: { certificateType: 'IOS_DISTRIBUTION', expirationDate: isoDays(15) } },
        ],
      }),
      { status: 200 },
    );
  };
  const client = createSigningClient(
    {
      ASC_KEY_ID: SECRET_KEY,
      ASC_ISSUER_ID: '57246542-96fe-1a63-e053-0824d011072a',
      ASC_PRIVATE_KEY: pem,
    },
    fetcher,
  );
  const body = await client.getAll('/v1/certificates', {
    'fields[certificates]': 'certificateType,expirationDate',
    limit: '200',
  });
  assert.equal(calls.length, 2);
  assert.deepEqual(
    calls.map((call) => call.method),
    ['GET', 'GET'],
  );
  for (const call of calls) {
    assert.match(call.authorization, /^Bearer /);
    assert.equal(call.url.includes(SECRET_KEY), false);
    assert.equal(call.url.includes('certificateContent'), false);
  }
  const projected = projectCertificates(body);
  const report = formatReport(
    buildSigningRows(
      {
        ...assets({ profileDays: [90], certDays: [15] }),
        certificates: projected,
      },
      NOW,
    ),
  );
  assert.match(report, /^distribution certificate IOS_DISTRIBUTION: 15 days$/m);
  assert.match(report, /^unused distribution certificate IOS_DISTRIBUTION: 40 days$/m);
  assert.doesNotMatch(report, new RegExp(SECRET_CONTENT));
  assert.doesNotMatch(report, new RegExp(SECRET_SERIAL));
  assert.doesNotMatch(report, new RegExp(SECRET_KEY));
});

test('asset load keeps distribution certs, retries profiles without bundle includes, and fails closed', async () => {
  const calls = [];
  const client = {
    async getAll(path, query) {
      calls.push({ path, query });
      if (path === '/v1/certificates') {
        return {
          data: [
            {
              attributes: {
                certificateType: 'IOS_DEVELOPMENT',
                expirationDate: isoDays(3),
                certificateContent: SECRET_CONTENT,
                serialNumber: SECRET_SERIAL,
              },
            },
            {
              id: 'dist-20',
              attributes: { certificateType: 'IOS_DISTRIBUTION', expirationDate: isoDays(20) },
            },
            {
              id: 'dist-50',
              attributes: { certificateType: 'DISTRIBUTION', expirationDate: isoDays(50) },
            },
          ],
        };
      }
      if (String(query.include || '').includes('certificates')) throw new Error('include rejected');
      if (!query.include) throw new Error('bundle id required');
      const bundle = (id, identifier) => ({
        type: 'bundleIds',
        id,
        attributes: { identifier },
      });
      return {
        data: REQUIRED_BUNDLE_IDS.map((identifier) => ({
          attributes: {
            profileType: 'IOS_APP_STORE',
            profileState: 'ACTIVE',
            expirationDate: isoDays(11),
            profileContent: SECRET_CONTENT,
            uuid: SECRET_SERIAL,
          },
          relationships: {
            bundleId: { data: { id: identifier, type: 'bundleIds' } },
            certificates: { data: [{ id: 'dist-20', type: 'certificates' }] },
          },
        })),
        included: REQUIRED_BUNDLE_IDS.map((identifier) => bundle(identifier, identifier)),
      };
    },
  };
  const assets = await loadSigningAssets(client, REQUIRED_BUNDLE_IDS);
  assert.deepEqual(
    calls.map((call) => call.path),
    ['/v1/certificates', '/v1/profiles', '/v1/profiles'],
  );
  assert.equal(
    String(calls[0].query['fields[certificates]']).includes('certificateContent'),
    false,
  );
  assert.equal(assets.apiKey.authenticated, true);
  assert.equal(assets.apiKey.expirationDate, null);
  assert.equal(assets.certificates.length, 2);
  assert.deepEqual(assets.requiredBundleIds, REQUIRED_BUNDLE_IDS);
  const rows = buildSigningRows(assets, NOW);
  const inUse = rows.find((row) => row.kind === 'distribution-certificate' && !row.unused);
  assert.equal(inUse.daysRemaining, 20);
  assert.equal(inUse.certificateType, 'IOS_DISTRIBUTION');
  const report = formatReport(rows);
  assert.match(
    report,
    /com\.logyourbody\.app IOS_APP_STORE: 11 days \(IOS_DISTRIBUTION, 20 days\)/,
  );
  assert.match(report, /^unused distribution certificate DISTRIBUTION: 50 days$/m);
  assert.doesNotMatch(report, new RegExp(SECRET_CONTENT));
  assert.doesNotMatch(report, new RegExp(SECRET_SERIAL));
  assert.equal(severity(rows), 'warn');

  const failed = await loadSigningAssets({
    async getAll() {
      throw new Error('unauthorized');
    },
  });
  assert.equal(failed.apiKey.authenticated, false);
  assert.equal(failed.certificatesReadable, false);
  assert.equal(severity(buildSigningRows(failed, NOW)), 'escalate');
  assert.doesNotMatch(formatReport(buildSigningRows(failed, NOW)), /unauthorized/);
});

function fakeLinear() {
  const calls = [];
  return {
    calls,
    async findTeam() {
      return { ok: true, id: 'team-lyb' };
    },
    async upsert(plan) {
      calls.push({ op: 'upsert', plan });
      return { ok: true, action: 'created', id: 'issue-1', identifier: 'LYB-900', reopened: false };
    },
    async comment(input) {
      calls.push({ op: 'comment', body: input.body });
      return { ok: true };
    },
    async resolve() {
      calls.push({ op: 'resolve' });
      return { ok: true, action: 'none' };
    },
  };
}

test('delivery files one issue under 30 days and resolves when clear', async () => {
  const linear = fakeLinear();
  const warn = await deliverSigningExpiry({
    rows: buildSigningRows(assets({ certDays: [20], profileDays: [40] }), NOW),
    runUrl: 'https://example.com/run',
    linearApiKey: 'fixture-key',
    forbidden: [SECRET_KEY, SECRET_PASSWORD],
    linear,
  });
  assert.equal(warn.exitCode, 0);
  assert.equal(linear.calls.filter((call) => call.op === 'upsert').length, 1);
  assert.equal(linear.calls[0].plan.fingerprint, FINGERPRINT);
  assert.equal(linear.calls[0].plan.priority, 2);
  assert.equal(linear.calls[0].plan.reopenTerminal, true);
  assert.equal(
    linear.calls.some((call) => call.op === 'comment'),
    true,
  );

  const clearLinear = fakeLinear();
  const clear = await deliverSigningExpiry({
    rows: buildSigningRows(assets(), NOW),
    linearApiKey: 'fixture-key',
    linear: clearLinear,
  });
  assert.equal(clear.exitCode, 0);
  assert.deepEqual(
    clearLinear.calls.map((call) => call.op),
    ['resolve'],
  );
});

test('under 7 days comments an escalation and a missing Linear key fails closed', async () => {
  const linear = fakeLinear();
  const urgent = await deliverSigningExpiry({
    rows: buildSigningRows(assets({ certDays: [2], profileDays: [40] }), NOW),
    linearApiKey: 'fixture-key',
    linear,
  });
  assert.equal(urgent.exitCode, 0);
  assert.equal(linear.calls[0].plan.priority, 1);
  assert.match(linear.calls.find((call) => call.op === 'comment').body, /^ESCALATED/);
  assert.doesNotMatch(JSON.stringify(linear.calls), new RegExp(SECRET_PASSWORD));

  const missing = await deliverSigningExpiry({
    rows: buildSigningRows(assets({ certDays: [2] }), NOW),
    linearApiKey: '',
    linear,
  });
  assert.equal(missing.exitCode, 1);
  assert.match(missing.log, /not filed/);
});

test('scheduled workflow is read-only and the nuke workflow stays manual', () => {
  const workflow = readFileSync(
    new URL('../workflows/signing-expiry.yml', import.meta.url),
    'utf8',
  );
  const nuke = readFileSync(
    new URL('../workflows/regenerate-certificates.yml', import.meta.url),
    'utf8',
  );
  const runbook = readFileSync(
    new URL('../../docs/engineering/signing-expiry.md', import.meta.url),
    'utf8',
  );
  const script = readFileSync(new URL('./signing-expiry.mjs', import.meta.url), 'utf8');
  assert.match(workflow, /schedule:/);
  assert.match(workflow, /cron:/);
  assert.match(workflow, /contents: read/);
  assert.doesNotMatch(
    workflow,
    /match_nuke|NUKE-AND-REGENERATE|MATCH_PASSWORD|readonly:\s*false|force:\s*true/,
  );
  assert.doesNotMatch(nuke, /^\s*schedule:/m);
  assert.match(nuke, /workflow_dispatch:/);
  assert.match(nuke, /NUKE-AND-REGENERATE/);
  assert.match(runbook, /readonly:false force:false/);
  assert.match(runbook, /NUKE-AND-REGENERATE/);
  assert.match(runbook, /match_nuke/);
  assert.match(runbook, /never starts this workflow/);
  assert.doesNotMatch(script, /match_nuke|match_password/);
  assert.match(script, /NUKE-AND-REGENERATE/);
  assert.match(script, /readRequiredBundleIds\(\)/);
  assert.match(script, /Matchfile/);
  assert.match(runbook, /Matchfile/);
  assert.match(runbook, /unused/);
  assert.doesNotMatch(`${workflow}\n${runbook}\n${script}`, new RegExp(SECRET_KEY));
});
