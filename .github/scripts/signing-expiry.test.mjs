import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  APP_BUNDLE_ID,
  ESCALATE_DAYS,
  FINGERPRINT,
  WARN_DAYS,
  assertPublicReport,
  assertSparseQuery,
  daysUntil,
  parseRequiredBundleIds,
  projectCertificates,
  projectProfiles,
  readRequiredBundleIds,
} from './signing-expiry.mjs';
import { buildIssue, buildSigningRows, formatReport, severity } from './signing-expiry-report.mjs';
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

