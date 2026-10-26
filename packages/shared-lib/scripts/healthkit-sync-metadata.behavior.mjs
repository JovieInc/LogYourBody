import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { repairSource, scan } from './healthkit-sync-metadata.mjs';

const launchQualityFixture = `let sample = HKQuantitySample(
    type: type, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: 80),
    start: measured, end: measured,
    metadata: [HKMetadataKeyTimeZone: "America/Los_Angeles", HKMetadataKeySyncIdentifier: "weight-edit"]
)`;

function findings(source, path = 'Fixture.swift') {
  return scan({ files: [path], readSource: () => source });
}

test('the launch-quality fixture fails before repair and passes after it', () => {
  const before = findings(launchQualityFixture);
  assert.equal(before.length, 1);
  assert.match(before[0].key, /HKMetadataKeySyncIdentifier: "weight-edit"/u);
  const repaired = repairSource(launchQualityFixture);
  assert.match(repaired, /HKMetadataKeySyncVersion: NSNumber\(value: 1\)/u);
  assert.match(repaired, /as \[String: Any\]/u);
  assert.deepEqual(findings(repaired), []);
  assert.equal(repairSource(repaired), repaired);
});

test('a version already present is accepted, including a string version on our raw sample', () => {
  const raw =
    'metadata: [HKMetadataKeySyncIdentifier: "raw-reading", HKMetadataKeySyncVersion: "1"]';
  assert.deepEqual(findings(raw), []);
  assert.equal(repairSource(raw), raw);
  const numeric =
    'metadata: [HKMetadataKeySyncIdentifier: "edit", HKMetadataKeySyncVersion: NSNumber(value: 2)] as [String: Any]';
  assert.deepEqual(findings(numeric), []);
  assert.equal(repairSource(numeric), numeric);
});

test('comments, strings and subscripts are not metadata dictionaries', () => {
  const source = `
    // HKMetadataKeySyncIdentifier: "comment"
    let note = "HKMetadataKeySyncIdentifier: \\"weight-edit\\""
    let syncID = sample.metadata?[HKMetadataKeySyncIdentifier]
    return metadata[HKMetadataKeySyncIdentifier] == syncID
  `;
  assert.deepEqual(findings(source), []);
  assert.equal(repairSource(source), source);
});

test('only the dictionary that omits the version is repaired', () => {
  const source = `let bad = [HKMetadataKeySyncIdentifier: "missing"]
let good = [HKMetadataKeySyncIdentifier: "kept", HKMetadataKeySyncVersion: "1"]`;
  const found = findings(source);
  assert.equal(found.length, 1);
  assert.match(found[0].key, /"missing"/u);
  const repaired = repairSource(source);
  assert.match(
    repaired,
    /"missing", HKMetadataKeySyncVersion: NSNumber\(value: 1\)\] as \[String: Any\]/u,
  );
  assert.match(repaired, /"kept", HKMetadataKeySyncVersion: "1"\]/u);
  assert.deepEqual(findings(repaired), []);
});

test('checked-in Swift pairs every sync identifier with a sync version', () => {
  const root = fileURLToPath(new URL('../../..', import.meta.url));
  const files = execFileSync('git', ['ls-files', '-z', '--', '*.swift'], {
    cwd: root,
    encoding: 'utf8',
  })
    .split('\0')
    .filter(Boolean);
  assert.ok(files.length > 0);
  const found = scan({
    files,
    readSource: (path) => readFileSync(join(root, path), 'utf8'),
  });
  assert.deepEqual(found, []);
});
