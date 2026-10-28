import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';

const source = (path: string) =>
  readFileSync(
    fileURLToPath(new URL(`../../../apps/ios/LogYourBody/${path}`, import.meta.url)),
    'utf8',
  );
const code = (path: string) => source(path).replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, '');

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
