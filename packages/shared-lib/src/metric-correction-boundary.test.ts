import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const source = (path: string) =>
  readFileSync(
    fileURLToPath(new URL(`../../../apps/ios/LogYourBody/${path}`, import.meta.url)),
    'utf8',
  );
const code = (path: string) => source(path).replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, '');

it('keeps retained V5 and V6 immutable and adds overlays only in V7', () => {
  const models = 'Models/LogYourBody.xcdatamodeld/';
  const v5 = source(models + 'LogYourBodyV5.xcdatamodel/contents');
  // Main's workout schema and #1561's additive dated-outcome schema must both
  // remain reproducible when composing the subsequent overlay feature.
  expect(createHash('sha256').update(v5).digest('hex')).toBe(
    'd344e8c50e13ea843757659942ef2cadf59ad204f672026c360be25b1d6475b4',
  );
  const v6 = source(models + 'LogYourBodyV6.xcdatamodel/contents');
  expect(createHash('sha256').update(v6).digest('hex')).toBe(
    '3ad6bfa15f2f50b936249e5bfc6caab6038f07b0b596c743c1f5624b62ed40a5',
  );
  let withoutOverlays = source(models + 'LogYourBodyV7.xcdatamodel/contents');
  for (const attribute of [
    '        <attribute name="isExcluded" attributeType="Boolean" defaultValueString="NO" usesScalarValueType="YES"/>\n',
    '        <attribute name="correctedValueJSON" optional="YES" attributeType="String"/>\n',
  ]) {
    expect(withoutOverlays.split(attribute)).toHaveLength(2);
    withoutOverlays = withoutOverlays.replace(attribute, '');
  }
  expect(withoutOverlays).toBe(v6);
  expect(source(models + '.xccurrentversion')).toContain('LogYourBodyV7.xcdatamodel');
});

it('quotes Xcode file-reference paths containing OpenStep punctuation (LYB-243)', () => {
  const project = readFileSync(
    fileURLToPath(
      new URL('../../../apps/ios/LogYourBody.xcodeproj/project.pbxproj', import.meta.url),
    ),
    'utf8',
  );
  const paths = [...project.matchAll(/\bpath\s*=\s*([^;]+);/g)].map((match) => match[1].trim());
  expect(paths.length).toBeGreaterThan(0);
  // OpenStep bare strings allow these token characters; '+' requires quotes.
  expect(paths.filter((path) => !/^"(?:[^"\\]|\\.)*"$|^[\w$/:.-]+$/.test(path))).toEqual([]);
});

it('keeps imported metric correction, persistence and cloud sync free of HealthKit writes (LYB-243)', () => {
  // These are the concrete production dependencies used by the service, including
  // its default sync callback. No health-writing service may enter this boundary.
  for (const path of [
    'Services/MetricCorrectionService.swift',
    'Services/CoreDataManager+Part06.swift',
    'Services/RealtimeSyncManager.swift',
    'Services/RealtimeSyncManager+Part01.swift',
    'Services/RealtimeSyncManager+Part02.swift',
  ]) {
    expect(code(path), path).not.toMatch(
      /\b(?:import\s+HealthKit|HKHealthStore|HealthKitManager|BodyMetricLoggingService|HealthSyncCoordinator|saveWeight|saveBodyFatPercentage|saveBodyMass|deleteObjects)\b/,
    );
  }
  const persistence = code('Services/CoreDataManager+Part06.swift');
  // Only the overlay and sync bookkeeping can be assigned. Adding a write to an
  // imported field (or a linked report) fails this contract in the required JS job.
  const writes = [...persistence.matchAll(/\brow\.(\w+)\s*=(?!=)/g)].map((match) => match[1]);
  expect(writes.sort()).toEqual([
    'correctedValueJSON',
    'isExcluded',
    'isSynced',
    'lastModified',
    'syncStatus',
    'updatedAt',
  ]);
  expect(persistence).not.toMatch(/\bCachedDexaResult\b/);
});
