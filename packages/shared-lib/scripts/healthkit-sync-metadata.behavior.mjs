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

test('a source that never names a sync identifier has no findings', () => {
  const bulky = `[${'"["'.repeat(4000)}]`;
  assert.equal(bulky.includes('HKMetadataKeySyncIdentifier'), false);
  assert.deepEqual(findings(bulky), []);
  assert.equal(repairSource(bulky), bulky);
});

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

test('raw HealthKit source assertions fail in either operand order', () => {
  for (const [field, raw] of [
    ['sourceBundleId', 'bundleIdentifier'],
    ['sourceName', 'name'],
  ]) {
    const normalized = `metadata.${field}`;
    const unnormalized = `sample.sourceRevision.source.${raw}`;
    for (const [left, right] of [
      [normalized, unnormalized],
      [unnormalized, normalized],
    ]) {
      const source = `XCTAssertEqual(\n    ${left},\n    ${right}, "source provenance")`;
      const found = findings(source);
      assert.equal(found.length, 1);
      assert.match(found[0].key, /normalize empty HealthKit/u);
      assert.equal(found[0].path, 'Fixture.swift');
    }
  }
});

test('normalized HealthKit assertions, literal values and source extraction are allowed', () => {
  const source = `
    let bundle = sample.sourceRevision.source.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    XCTAssertEqual(metadata.sourceBundleId, bundle.isEmpty ? nil : bundle)
    XCTAssertEqual(metadata.sourceBundleId, "com.example.scale")
    XCTAssertEqual(sample.sourceRevision.source.bundleIdentifier, "com.example.scale")
    let metadata = BodyMetricSourceMetadata(sourceBundleId: sample.sourceRevision.source.bundleIdentifier)
    // XCTAssertEqual(metadata.sourceBundleId, sample.sourceRevision.source.bundleIdentifier)
    /* XCTAssertEqual(metadata.sourceName, sample.sourceRevision.source.name) */
    let example = "XCTAssertEqual(metadata.sourceBundleId, sample.sourceRevision.source.bundleIdentifier)"
  `;
  assert.deepEqual(findings(source), []);
});

test('metric history rejects row-level sources for weight and body fat after a merge', () => {
  for (const field of ['weight', 'bodyFat']) {
    const source = `func ${field}EntriesPayload() -> MetricEntriesPayload? {
      MetricHistoryEntry(source: metricEntrySourceType(from: metric.dataSource))
    }`;
    assert.equal(findings(source).length, 1);
    assert.match(findings(source)[0].key, /per-field provenance/u);
    assert.deepEqual(
      findings(
        source.replace('metric.dataSource', `metric.measurementSource(for: .${field}).rawValue`),
      ),
      [],
    );
  }
});

test('derived history and examples can still name row-level sources', () => {
  const source = `func ffmiEntriesPayload() -> MetricEntriesPayload? {
    MetricHistoryEntry(source: metricEntrySourceType(from: metric.dataSource))
  }
  func weightEntriesPayload() -> MetricEntriesPayload? {
    // metricEntrySourceType(from: metric.dataSource)
    let example = "metricEntrySourceType(from: metric.dataSource)"
    return MetricHistoryEntry(source: metricEntrySourceType(
      from: metric.measurementSource(for: .weight).rawValue
    ))
  }`;
  assert.deepEqual(findings(source), []);
});

test('checked-in Swift preserves HealthKit metadata and per-field history sources', () => {
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
