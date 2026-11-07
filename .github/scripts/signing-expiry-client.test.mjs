import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  FINGERPRINT,
  createSigningClient,
  loadSigningAssets,
  projectCertificates,
} from './signing-expiry.mjs';
import {
  buildSigningRows,
  deliverSigningExpiry,
  formatReport,
  severity,
} from './signing-expiry-report.mjs';
import {
  NOW,
  REQUIRED_BUNDLE_IDS,
  SECRET_CONTENT,
  SECRET_KEY,
  SECRET_PASSWORD,
  SECRET_SERIAL,
  assets,
  isoDays,
} from './signing-expiry-fixtures.mjs';

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
  const reportModule = readFileSync(new URL('./signing-expiry-report.mjs', import.meta.url), 'utf8');
  const signingSource = `${script}\n${reportModule}`;
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
  assert.doesNotMatch(signingSource, /match_nuke|match_password/);
  assert.match(reportModule, /NUKE-AND-REGENERATE/);
  assert.match(script, /readRequiredBundleIds\(\)/);
  assert.match(script, /Matchfile/);
  assert.match(runbook, /Matchfile/);
  assert.match(runbook, /unused/);
  assert.doesNotMatch(`${workflow}\n${runbook}\n${signingSource}`, new RegExp(SECRET_KEY));
});
