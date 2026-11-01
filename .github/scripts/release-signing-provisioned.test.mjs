import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { generateKeyPairSync } from 'node:crypto';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  RUNBOOK,
  assertPublicText,
  capabilityGaps,
  credentialGate,
  failureMessage,
  inspectReleaseSigning,
  loadReleaseEntitlements,
  missingCredentialsMessage,
  neutralMessage,
  parseEntitlements,
  readCatalog,
  releaseBundleIds,
  releaseTargetsFromProject,
  successMessage,
  createReleaseClient,
} from './release-signing-provisioned.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const RELEASE_FILE = path.join(ROOT, 'apps/ios/fastlane/Fastfile.release');
const RUBY_SCRIPT = path.join(ROOT, '.github/scripts/release-match-identifiers.rb');
const CHECKER = path.join(ROOT, '.github/scripts/release-signing-provisioned.mjs');

const SECRET = 'M'.repeat(40) + 'SECRETCONTENTONLYFORTEST' + 'A'.repeat(40);

function assertTimRunbook(text) {
  assert.match(text, /Tim/);
  assert.match(text, new RegExp(RUNBOOK.replaceAll('.', '\\.')));
}

function assertNoIds(text, ids) {
  for (const id of ids) assert.equal(text.includes(id), false);
}

function plist(entries, { entitlementsKey = false } = {}) {
  const body = Object.entries(entries)
    .map(([key, value]) => {
      let inner = `<string>${value}</string>`;
      if (value === true) inner = '<true/>';
      else if (value === false) inner = '<false/>';
      else if (Array.isArray(value)) {
        inner = `<array>${value.map((item) => `<string>${item}</string>`).join('')}</array>`;
      }
      return `<key>${key}</key>${inner}`;
    })
    .join('');
  const dict = entitlementsKey ? `<key>Entitlements</key><dict>${body}</dict><key>Name</key><string>ignored</string>` : body;
  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict>${dict}</dict></plist>`;
  return Buffer.concat([Buffer.from('garbage-cms'), Buffer.from(xml)]);
}

test('required ids are read from the release lane, not kept in the checker', () => {
  assert.doesNotMatch(readFileSync(CHECKER, 'utf8'), /com\.logyourbody\.app/);
  assert.doesNotMatch(readFileSync(RUBY_SCRIPT, 'utf8'), /com\.logyourbody\.app/);
  const ids = releaseBundleIds(RELEASE_FILE);
  assert.ok(ids.length >= 1);
  const dirty = spawnSync('ruby', [RUBY_SCRIPT, RELEASE_FILE], {
    encoding: 'utf8',
    env: {
      ...process.env,
      MATCH_READONLY: 'false',
      APP_IDENTIFIER: 'com.example.override',
      MATCH_PASSWORD: SECRET,
    },
  });
  assert.equal(dirty.status, 0, dirty.stderr);
  assert.deepEqual(JSON.parse(dirty.stdout), ids);
  assert.equal(dirty.stdout.includes('com.example.override'), false);
  assert.equal(dirty.stdout.includes(SECRET), false);
  assert.equal(dirty.stderr.includes(SECRET), false);
});

test('a lane that omits app_identifier falls back to the Matchfile', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'lyb-333-matchfile-'));
  writeFileSync(path.join(dir, 'Matchfile'), 'app_identifier(["com.example.one", "com.example.two"])\n');
  writeFileSync(
    path.join(dir, 'Fastfile.release'),
    [
      'lane :setup_provisioning do |options|',
      '  if ENV["MATCH_GIT_URL"]',
      '    setup_app_store_connect_api',
      '    match(type: options[:type], readonly: options[:readonly])',
      '  end',
      'end',
      '',
    ].join('\n'),
  );
  assert.deepEqual(releaseBundleIds(path.join(dir, 'Fastfile.release')), ['com.example.one', 'com.example.two']);
});

test('readonly release match does not request the whole Matchfile list', () => {
  const ids = releaseBundleIds(RELEASE_FILE);
  const matchfile = readFileSync(path.join(ROOT, 'apps/ios/fastlane/Matchfile'), 'utf8');
  const listed = matchfile
    .match(/app_identifier\s*\(\s*\[([^\]]*)\]/)[1]
    .match(/"([^"]+)"/g)
    .map((quoted) => quoted.slice(1, -1));
  assert.ok(ids.every((id) => listed.includes(id)));
  assert.ok(listed.some((id) => !ids.includes(id)));
});

test('release targets keep Release entitlements and ignore Debug-only settings', () => {
  const project = readFileSync(path.join(ROOT, 'apps/ios/LogYourBody.xcodeproj/project.pbxproj'), 'utf8');
  const targets = releaseTargetsFromProject(project);
  const ids = releaseBundleIds(RELEASE_FILE);
  const entitlements = loadReleaseEntitlements(ROOT, ids, project);
  assert.equal(entitlements[ids[0]]['com.apple.developer.healthkit'], true);
  assert.ok(entitlements[ids[0]]['com.apple.security.application-groups'].includes('group.com.logyourbody.shared'));
  assert.ok(targets.some((target) => target.bundleId === ids[0] && target.entitlementsPath.endsWith('.entitlements')));
});

test('empty entitlement arrays are not required capabilities', () => {
  assert.deepEqual(capabilityGaps({ 'com.apple.developer.healthkit.access': [] }, null), []);
  assert.deepEqual(
    capabilityGaps(
      { 'com.apple.developer.healthkit': true, 'com.apple.security.application-groups': ['group.one'] },
      { 'com.apple.developer.healthkit': true, 'com.apple.security.application-groups': ['group.one', 'group.two'] },
    ),
    [],
  );
  assert.deepEqual(
    capabilityGaps({ 'com.apple.developer.healthkit': true }, { 'com.apple.developer.healthkit': false }),
    ['com.apple.developer.healthkit'],
  );
});

test('profile wildcards cover specific values and a missing capability still fails', () => {
  const domains = ['applinks:example.com', 'webcredentials:example.com'];
  assert.deepEqual(
    capabilityGaps(
      { 'com.apple.developer.associated-domains': domains },
      { 'com.apple.developer.associated-domains': ['*'] },
    ),
    [],
  );
  assert.deepEqual(
    capabilityGaps({ 'com.apple.developer.associated-domains': domains }, { 'com.apple.developer.associated-domains': '*' }),
    [],
  );
  assert.deepEqual(
    capabilityGaps(
      { 'keychain-access-groups': ['TEAMID.com.example.app', 'TEAMID.com.example.shared'] },
      { 'keychain-access-groups': ['TEAMID.*', 'com.apple.token'] },
    ),
    [],
  );
  assert.deepEqual(
    capabilityGaps(
      { 'keychain-access-groups': ['TEAMID.com.example.app'] },
      { 'keychain-access-groups': ['OTHER.*'] },
    ),
    ['keychain-access-groups'],
  );
  assert.deepEqual(
    capabilityGaps(
      { 'com.apple.developer.associated-domains': domains },
      { 'com.apple.developer.associated-domains': ['applinks:example.com'] },
    ),
    ['com.apple.developer.associated-domains'],
  );
  assert.deepEqual(
    capabilityGaps(
      { 'com.apple.developer.associated-domains': domains, 'com.apple.developer.healthkit': true },
      { 'com.apple.developer.healthkit': true },
    ),
    ['com.apple.developer.associated-domains'],
  );
  assert.deepEqual(
    capabilityGaps({ 'com.apple.developer.healthkit': true }, { 'com.apple.developer.healthkit': '*' }),
    ['com.apple.developer.healthkit'],
  );
});

test('profile bytes decode to entitlements and a secret body never leaves the client', async () => {
  const required = { 'com.apple.developer.healthkit': true, 'com.apple.security.application-groups': ['group.one'] };
  const decoded = parseEntitlements(plist(required, { entitlementsKey: true }));
  assert.equal(decoded['com.apple.developer.healthkit'], true);
  assert.deepEqual(decoded['com.apple.security.application-groups'], ['group.one']);

  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const calls = [];
  const fetcher = async (url, options) => {
    calls.push({ url: String(url), method: options.method });
    const page = String(url);
    if (page.includes('/v1/certificates')) {
      return new Response(SECRET, { status: 200 });
    }
    if (page.includes('/v1/bundleIds')) {
      return new Response(
        JSON.stringify({
          data: [{ attributes: { identifier: 'com.example.app' } }],
          links: { next: 'https://evil.example/v1/bundleIds' },
        }),
        { status: 200 },
      );
    }
    if (page.includes('cursor=2')) {
      return new Response(JSON.stringify({ data: [], included: [] }), { status: 200 });
    }
    return new Response(
      JSON.stringify({
        data: [
          {
            attributes: {
              profileType: 'IOS_APP_STORE',
              profileState: 'ACTIVE',
              expirationDate: '2099-01-01T00:00:00Z',
              profileContent: plist(required, { entitlementsKey: true }).toString('base64'),
              name: SECRET,
            },
            relationships: { bundleId: { data: { type: 'bundleIds', id: 'BID' } } },
          },
          {
            attributes: {
              profileType: 'IOS_APP_STORE',
              profileState: 'ACTIVE',
              expirationDate: '2000-01-01T00:00:00Z',
              profileContent: plist(required, { entitlementsKey: true }).toString('base64'),
            },
            relationships: { bundleId: { data: { type: 'bundleIds', id: 'BID' } } },
          },
        ],
        included: [{ type: 'bundleIds', id: 'BID', attributes: { identifier: 'com.example.app' } }],
        links: { next: 'https://api.appstoreconnect.apple.com/v1/certificates?cursor=2' },
      }),
      { status: 200 },
    );
  };
  const client = createReleaseClient(
    {
      ASC_KEY_ID: 'ABCD123456',
      ASC_ISSUER_ID: '57246542-96fe-1a63-e053-0824d011072a',
      ASC_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    },
    fetcher,
  );
  const catalog = await readCatalog(client, Date.parse('2026-11-01T00:00:00Z'));
  assert.deepEqual(catalog.bundleIdentifiers, ['com.example.app']);
  assert.equal(catalog.profiles.length, 1);
  assert.ok(
    calls.some(
      (call) =>
        call.url.includes('/v1/profiles') &&
        call.url.includes('profileContent') &&
        call.url.includes('bundleId'),
    ),
  );
  assert.equal(catalog.profiles[0].entitlements['com.apple.developer.healthkit'], true);
  assert.equal(JSON.stringify(catalog).includes(SECRET), false);
  assert.ok(calls.every((call) => call.method === 'GET'));
  assert.ok(calls.every((call) => !call.url.includes('/v1/certificates')));
  await assert.rejects(client.getAll('/v1/profiles', { 'fields[profiles]': 'certificateContent' }), (error) => {
    assert.equal(error.message, 'ASC read failed');
    return true;
  });

  const denied = createReleaseClient(
    {
      ASC_KEY_ID: 'ABCD123456',
      ASC_ISSUER_ID: '57246542-96fe-1a63-e053-0824d011072a',
      ASC_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    },
    async () => new Response(SECRET, { status: 500 }),
  );
  await assert.rejects(denied.getAll('/v1/bundleIds', {}), (error) => {
    assert.equal(error.message, 'ASC read failed');
    assert.equal(String(error).includes(SECRET), false);
    return true;
  });
});

function replayReleaseFile() {
  const current = readFileSync(RELEASE_FILE, 'utf8');
  const needle = [
    '        base_identifier = ENV["APP_IDENTIFIER"] || "com.logyourbody.app"',
    '        match_identifiers = [base_identifier]',
    '        match_identifiers << "#{base_identifier}.rest-timer" unless readonly',
    '        match_params = {',
    '          type: match_type,',
    '          app_identifier: match_identifiers,',
  ].join('\n');
  const replacement = [
    '        match_params = {',
    '          type: match_type,',
    '          app_identifier: [ENV["APP_IDENTIFIER"] || "com.logyourbody.app",',
    '                           "#{ENV["APP_IDENTIFIER"] || "com.logyourbody.app"}.rest-timer"],',
  ].join('\n');
  assert.ok(current.includes(needle), 'PR 1540 replay no longer matches Fastfile.release');
  const file = path.join(mkdtempSync(path.join(tmpdir(), 'lyb-333-')), 'Fastfile.release');
  writeFileSync(file, current.replace(needle, replacement));
  return file;
}

test("replaying PR 1540 against today's missing App Store profile fails without ids", () => {
  const currentIds = releaseBundleIds(RELEASE_FILE);
  const replayIds = releaseBundleIds(replayReleaseFile());
  const added = replayIds.filter((id) => !currentIds.includes(id));
  assert.equal(added.length, 1);
  const project = readFileSync(path.join(ROOT, 'apps/ios/LogYourBody.xcodeproj/project.pbxproj'), 'utf8');
  const entitlements = loadReleaseEntitlements(ROOT, replayIds, project);
  const provisioned = {
    bundleIdentifiers: replayIds,
    profiles: currentIds.map((id) => ({
      bundleId: id,
      usable: true,
      entitlements: entitlements[id] || {},
    })),
  };
  // Today's release source still says the added target has no App Store profile.
  const missingProfile = inspectReleaseSigning({
    bundleIds: replayIds,
    entitlementsByBundleId: entitlements,
    catalog: provisioned,
  });
  assert.ok(missingProfile.some((finding) => finding.reason === 'profile'));
  const profileText = failureMessage(missingProfile);
  assert.match(profileText, /no active App Store profile/);
  assertTimRunbook(profileText);
  assertNoIds(profileText, replayIds);
  assertPublicText(profileText, replayIds);

  const missingBundle = inspectReleaseSigning({
    bundleIds: replayIds,
    entitlementsByBundleId: entitlements,
    catalog: {
      bundleIdentifiers: currentIds,
      profiles: provisioned.profiles,
    },
  });
  assert.ok(missingBundle.some((finding) => finding.reason === 'bundle-id'));
  const bundleText = failureMessage(missingBundle);
  assert.match(bundleText, /no registered bundle ID/);
  assertNoIds(bundleText, replayIds);

  const stale = {
    bundleIdentifiers: replayIds,
    profiles: replayIds.map((id) => ({
      bundleId: id,
      usable: true,
      entitlements:
        id === currentIds[0]
          ? { ...entitlements[id], 'com.apple.developer.healthkit': false }
          : entitlements[id] || {},
    })),
  };
  const capability = inspectReleaseSigning({
    bundleIds: replayIds,
    entitlementsByBundleId: entitlements,
    catalog: stale,
  });
  const capabilityText = failureMessage(capability);
  assert.match(capabilityText, /com\.apple\.developer\.healthkit/);
  assertNoIds(capabilityText, replayIds);

  const ready = inspectReleaseSigning({
    bundleIds: replayIds,
    entitlementsByBundleId: entitlements,
    catalog: {
      bundleIdentifiers: replayIds,
      profiles: replayIds.map((id) => ({
        bundleId: id,
        usable: true,
        entitlements: entitlements[id] || {},
      })),
    },
  });
  assert.deepEqual(ready, []);
  const current = inspectReleaseSigning({
    bundleIds: currentIds,
    entitlementsByBundleId: entitlements,
    catalog: provisioned,
  });
  assert.deepEqual(current, []);
  assert.match(successMessage(), new RegExp(RUNBOOK.replaceAll('.', '\\.')));
});

test('a stripped profile include still maps through the bundle id list', async () => {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const required = { 'com.apple.developer.healthkit': true };
  const client = createReleaseClient(
    {
      ASC_KEY_ID: 'ABCD123456',
      ASC_ISSUER_ID: '57246542-96fe-1a63-e053-0824d011072a',
      ASC_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    },
    async (url) => {
      const page = String(url);
      if (page.includes('/v1/bundleIds')) {
        return new Response(
          JSON.stringify({ data: [{ id: 'BID', attributes: { identifier: 'com.example.app' } }] }),
          { status: 200 },
        );
      }
      return new Response(
        JSON.stringify({
          data: [
            {
              attributes: {
                profileType: 'IOS_APP_STORE',
                profileState: 'ACTIVE',
                expirationDate: '2099-01-01T00:00:00Z',
                profileContent: plist(required, { entitlementsKey: true }).toString('base64'),
              },
              relationships: { bundleId: { data: { type: 'bundleIds', id: 'BID' } } },
            },
          ],
          included: [],
        }),
        { status: 200 },
      );
    },
  );
  const catalog = await readCatalog(client, Date.parse('2026-11-01T00:00:00Z'));
  assert.equal(catalog.profiles[0].bundleId, 'com.example.app');
  assert.equal(catalog.profiles[0].entitlements['com.apple.developer.healthkit'], true);

  const unmapped = createReleaseClient(
    {
      ASC_KEY_ID: 'ABCD123456',
      ASC_ISSUER_ID: '57246542-96fe-1a63-e053-0824d011072a',
      ASC_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    },
    async (url) => {
      if (String(url).includes('/v1/bundleIds')) {
        return new Response(JSON.stringify({ data: [{ attributes: { identifier: 'com.example.app' } }] }), {
          status: 200,
        });
      }
      return new Response(
        JSON.stringify({
          data: [
            {
              attributes: {
                profileType: 'IOS_APP_STORE',
                profileState: 'ACTIVE',
                expirationDate: '2099-01-01T00:00:00Z',
              },
            },
          ],
        }),
        { status: 200 },
      );
    },
  );
  await assert.rejects(readCatalog(unmapped, Date.parse('2026-11-01T00:00:00Z')));
  assert.doesNotMatch(failureMessage([{ reason: 'unreadable' }]), /no active App Store profile/);
});

test('fork pulls finish neutral and same-repo pulls without credentials fail closed', () => {
  assert.equal(credentialGate({ fork: true, hasSecrets: false }), 'neutral');
  assert.equal(credentialGate({ fork: true, hasSecrets: true }), 'neutral');
  assert.equal(credentialGate({ fork: false, hasSecrets: false }), 'missing-credentials');
  assert.equal(credentialGate({ fork: false, hasSecrets: true }), 'run');
  const neutral = neutralMessage();
  assert.match(neutral, /did not pass/);
  assert.match(neutral, /Neutral/);
  assertTimRunbook(neutral);
  const missing = missingCredentialsMessage();
  assert.match(missing, /failed closed/);
  assertTimRunbook(missing);
  assert.doesNotMatch(`${neutral}\n${missing}\n${successMessage()}`, /ABCD123456|BEGIN PRIVATE KEY/);
});
