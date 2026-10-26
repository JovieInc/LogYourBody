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
  projectCertificates,
  projectProfiles,
  severity,
} from './signing-expiry.mjs';

const NOW = Date.parse('2026-10-25T00:00:00Z');
const SECRET_CONTENT = 'M'.repeat(40) + 'SECRETCONTENTONLYFORTEST' + 'A'.repeat(40);
const SECRET_SERIAL = 'SERIALSHOULDNOTLEAK99';
const SECRET_KEY = 'ABCD123456';
const SECRET_PASSWORD = 'match-secret-value';

const isoDays = (days) => new Date(NOW + days * 86_400_000).toISOString();

function assets({
  certDays = [200],
  profileDays = [180],
  key = { authenticated: true, expirationDate: null },
} = {}) {
  return {
    certificatesReadable: true,
    profilesReadable: true,
    certificates: certDays.map((days) => ({
      certificateType: 'IOS_DISTRIBUTION',
      expirationDate: isoDays(days),
    })),
    profiles: profileDays.map((days) => ({
      profileType: 'IOS_APP_STORE',
      profileState: 'ACTIVE',
      expirationDate: isoDays(days),
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

test('distribution row uses the soonest valid cert and ignores expired leftovers', () => {
  const rows = buildSigningRows(
    assets({
      certDays: [-4, 40, 12],
      profileDays: [90],
    }),
    NOW,
  );
  const cert = rows.find((row) => row.kind === 'distribution-certificate');
  assert.equal(cert.daysRemaining, 12);
  assert.equal(cert.count, 2);
  assert.match(formatReport(rows), /distribution certificate: 12 days \(2 valid\)/);
});

test('development certificates are not the distribution cert', () => {
  const rows = buildSigningRows(
    {
      ...assets({ certDays: [], profileDays: [90] }),
      certificates: [
        { certificateType: 'IOS_DEVELOPMENT', expirationDate: isoDays(3) },
        { certificateType: 'DISTRIBUTION', expirationDate: isoDays(50) },
      ],
    },
    NOW,
  );
  assert.equal(rows[0].daysRemaining, 50);
});

test('missing or fully expired distribution cert and profile escalate', () => {
  const missing = buildSigningRows({ ...assets(), certificates: [], profiles: [] }, NOW);
  assert.equal(severity(missing), 'escalate');
  assert.match(formatReport(missing), /distribution certificate: missing/);
  assert.match(formatReport(missing), /app store profile: missing/);
  const expired = buildSigningRows(assets({ certDays: [-1], profileDays: [40] }), NOW);
  assert.equal(expired[0].daysRemaining, -1);
  assert.equal(severity(expired), 'escalate');
});

test('each app store profile is reported and other bundles are dropped', () => {
  const projected = projectProfiles({
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
        relationships: { bundleId: { data: { id: 'app' } } },
      },
      {
        attributes: {
          profileType: 'IOS_APP_STORE',
          profileState: 'ACTIVE',
          expirationDate: isoDays(3),
          profileContent: SECRET_CONTENT,
        },
        relationships: { bundleId: { data: { id: 'extension' } } },
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
      { type: 'bundleIds', id: 'extension', attributes: { identifier: `${APP_BUNDLE_ID}.widget` } },
      { type: 'bundleIds', id: 'other', attributes: { identifier: 'com.example.other' } },
    ],
  });
  assert.equal(projected.length, 2);
  assert.deepEqual(Object.keys(projected[0]).sort(), [
    'expirationDate',
    'profileState',
    'profileType',
  ]);
  const rows = buildSigningRows({ ...assets(), profiles: projected }, NOW);
  const report = formatReport(rows);
  assert.match(report, /app store profile 1: 3 days/);
  assert.match(report, /app store profile 2: 10 days/);
  assert.doesNotMatch(report, new RegExp(SECRET_CONTENT));
  assert.doesNotMatch(report, new RegExp(SECRET_SERIAL));
  assert.doesNotMatch(report, new RegExp(SECRET_KEY));
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
    buildSigningRows({ ...assets({ profileDays: [90] }), certificates: projected }, NOW),
  );
  assert.match(report, /distribution certificate: 15 days \(2 valid\)/);
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
            { attributes: { certificateType: 'IOS_DISTRIBUTION', expirationDate: isoDays(20) } },
            { attributes: { certificateType: 'DISTRIBUTION', expirationDate: isoDays(50) } },
          ],
        };
      }
      if (query.include) throw new Error('include rejected');
      return {
        data: [
          {
            attributes: {
              profileType: 'IOS_APP_STORE',
              profileState: 'ACTIVE',
              expirationDate: isoDays(11),
              profileContent: SECRET_CONTENT,
            },
          },
        ],
      };
    },
  };
  const assets = await loadSigningAssets(client);
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
  const rows = buildSigningRows(assets, NOW);
  assert.equal(rows.find((row) => row.kind === 'distribution-certificate').daysRemaining, 20);
  assert.match(formatReport(rows), /app store profile: 11 days/);
  assert.doesNotMatch(formatReport(rows), new RegExp(SECRET_CONTENT));

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
  assert.doesNotMatch(`${workflow}\n${runbook}\n${script}`, new RegExp(SECRET_KEY));
});
