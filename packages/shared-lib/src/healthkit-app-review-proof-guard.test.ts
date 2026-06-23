import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

function readRepoFile(repoRelativePath: string): string {
  return readFileSync(new URL(`../../../${repoRelativePath}`, import.meta.url), 'utf8');
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function plistString(plist: string, key: string): string {
  const match = plist.match(
    new RegExp(`<key>${escapeRegExp(key)}</key>\\s*<string>([\\s\\S]*?)</string>`),
  );

  if (!match) {
    throw new Error(`Missing string plist key: ${key}`);
  }

  return match[1].trim();
}

function plistBoolean(plist: string, key: string, expectedValue: boolean): boolean {
  const tag = expectedValue ? 'true' : 'false';
  return new RegExp(`<key>${escapeRegExp(key)}</key>\\s*<${tag}\\s*/>`).test(plist);
}

function plistHasArray(plist: string, key: string): boolean {
  return new RegExp(`<key>${escapeRegExp(key)}</key>\\s*<array(?:\\s*/|>[\\s\\S]*?</array>)`).test(
    plist,
  );
}

function expectProductionUsageString(value: string): void {
  expect(value).toMatch(/^LogYourBody\b/);
  expect(value.length).toBeGreaterThanOrEqual(60);
  expect(value).not.toMatch(/\$\(|todo|tbd|fixme|placeholder|lorem|sample/i);
}

function lineForAuditIssue(source: string, issueId: string): string {
  const line = source
    .split(/\r?\n/)
    .find((candidate) => candidate.startsWith(issueId) || candidate.includes(`\`${issueId}\``));

  if (!line) {
    throw new Error(`Missing audit issue row: ${issueId}`);
  }

  return line;
}

const infoPlist = readRepoFile('apps/ios/LogYourBody/Info.plist');
const entitlementsPlist = readRepoFile('apps/ios/LogYourBody/LogYourBody.entitlements');
const xcodeProject = readRepoFile('apps/ios/LogYourBody.xcodeproj/project.pbxproj');
const issueRegister = readRepoFile('docs/audits/full-app-inventory-2026-06-23/issue-register.csv');
const executionStatus = readRepoFile(
  'docs/audits/full-app-inventory-2026-06-23/execution-status.md',
);

describe('AUD-017 HealthKit App Review proof guard', () => {
  it('keeps production HealthKit usage strings explicit and non-placeholder', () => {
    const shareUsage = plistString(infoPlist, 'NSHealthShareUsageDescription');
    const updateUsage = plistString(infoPlist, 'NSHealthUpdateUsageDescription');

    expectProductionUsageString(shareUsage);
    expectProductionUsageString(updateUsage);

    expect(shareUsage).toMatch(/read.*weight/i);
    expect(shareUsage).toMatch(/body composition/i);
    expect(shareUsage).toMatch(/sync.*profile/i);
    expect(updateUsage).toMatch(/save.*weight/i);
    expect(updateUsage).toMatch(/body fat/i);
  });

  it('keeps the HealthKit capability discoverable from signed app configuration', () => {
    expect(plistBoolean(entitlementsPlist, 'com.apple.developer.healthkit', true)).toBe(true);
    expect(
      plistBoolean(entitlementsPlist, 'com.apple.developer.healthkit.background-delivery', true),
    ).toBe(true);
    expect(plistHasArray(entitlementsPlist, 'com.apple.developer.healthkit.access')).toBe(true);

    expect(xcodeProject).toContain('INFOPLIST_FILE = LogYourBody/Info.plist;');
    expect(xcodeProject).toContain(
      'CODE_SIGN_ENTITLEMENTS = LogYourBody/LogYourBody.entitlements;',
    );
    expect(xcodeProject).toContain('HealthKit.framework in Frameworks');
  });

  it('requires allow, deny, and skip evidence before closing App Review proof', () => {
    const registerRow = lineForAuditIssue(issueRegister, 'AUD-017');
    const executionRow = lineForAuditIssue(executionStatus, 'AUD-017');
    const proofSource = `${registerRow}\n${executionRow}`.toLowerCase();

    expect(proofSource).toContain('healthkit');
    expect(proofSource).toContain('review-sensitive');
    expect(proofSource).toContain('allow');
    expect(proofSource).toContain('deny');
    expect(proofSource).toContain('skip');
    expect(proofSource).toContain('production usage strings');
    expect(proofSource).toContain('before app store submission');
  });
});
