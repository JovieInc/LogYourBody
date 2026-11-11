import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';
import {
  assess,
  compare,
  decisionRecord,
  productionPersonalBody,
  syntheticSession,
  syntheticTruth,
} from './personal-3d-engine';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const decisionPath = `${root}/apps/ios/LogYourBody/Resources/PersonalBodyEngine.json`;
const stagePath = `${root}/apps/ios/LogYourBody/Components/WireframeAvatarStage.swift`;
const enginePath = `${root}/apps/ios/LogYourBody/Components/PersonalBodyEngine.swift`;
const attachPath = `${root}/apps/ios/LogYourBody/Views/ProgressPhotoAttachSheet.swift`;
const emptyStagePath = `${root}/apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift`;
const recordPath = `${root}/docs/product/personal-3d-engine.md`;

function probe(report: ReturnType<typeof compare>, id: string) {
  const found = report.parametric.probes.find((item) => item.id === id);
  if (!found) throw new Error(`missing probe ${id}`);
  return found;
}

it('selects the on-device torso and keeps personalization out of the photo loop', () => {
  const report = compare();
  const again = compare();
  expect(assess(report)).toEqual([]);
  expect(report.parametric.probes).toEqual(again.parametric.probes);
  expect(report.selectedEngineId).toBe('lyb.personal.parametric.wireframe.v1');
  expect(report.fallbackEngineId).toBe('lyb.wireframe.torso');
  expect(report.personalizedProduction).toBe(false);
  expect(report.addsCaptureStep).toBe(false);
  expect(report.mapsToBodyFat).toBe(false);
  expect(report.mapsToDexa).toBe(false);
  expect(report.evidence).toMatchObject({
    source: 'host-cpu',
    simulator: 'not-run',
    physicalDevice: 'not-run',
    distributedBuild: 'not-run',
    vendorTimingsAreAppBenchmarks: false,
  });
  expect(report.host.platform.length).toBeGreaterThan(0);
  expect(report.host.cpuCount).toBeGreaterThan(0);
  expect(report.parametric.externalAnnyExecuted).toBe(false);
  expect(report.parametric.candidateCount).toBe(1331);
  expect(report.parametric.vertexCount).toBe(160);
  expect(report.parametric.renderedFrames).toBe(2);
  expect(report.parametric.transferredBytes).toBeGreaterThan(1000);
  expect(report.parametric.sameDayMaxVertexDelta).toBe(0);
  expect(report.parametric.timings.cold.cacheHit).toBe(false);
  expect(report.parametric.timings.warm.cacheHit).toBe(true);
  expect(report.parametric.improvedRings).toEqual([1, 2, 5, 8, 9]);
  expect(report.parametric.unchangedRings).toEqual([3, 4, 7]);
  expect(report.parametric.worseRings).toEqual([0, 6]);

  const fullFront = probe(report, 'full-front');
  const fullBoth = probe(report, 'full-front-side');
  expect(fullFront.parameters).toEqual({ adiposity: 0.6, muscularity: 0.2, frame: 0.7 });
  expect(fullBoth.parameters).toEqual(fullFront.parameters);
  expect(fullFront.parameterError).toBeCloseTo(0.05, 6);
  expect(fullFront.vertexError).toBeCloseTo(0.000414, 6);
  expect(probe(report, 'ring-1-front').vertexError).toBeGreaterThan(
    probe(report, 'ring-1-front-side').vertexError,
  );
  expect(probe(report, 'ring-6-front').vertexError).toBeLessThan(
    probe(report, 'ring-6-front-side').vertexError,
  );
  expect(probe(report, 'ring-0-front').matchCount).toBe(4);
  expect(probe(report, 'ring-0-front').vertexError).toBeCloseTo(0.002481, 6);
  expect(probe(report, 'ring-0-front').worstVertexError).toBeCloseTo(0.006425, 6);
  expect(probe(report, 'ring-0-front-side').matchCount).toBe(1);
  expect(probe(report, 'ring-0-front-side').vertexError).toBeCloseTo(0.003535, 6);
  expect(syntheticTruth).toEqual({ adiposity: 0.62, muscularity: 0.18, frame: 0.71 });

  expect(report.bodygram).toMatchObject({
    executed: false,
    measuredEndToEndMs: null,
    crossScanTopology: 'not-documented',
    directDexaOrBodyFatControl: false,
  });
  expect(report.digs).toMatchObject({
    executed: false,
    measuredEndToEndMs: null,
    crossScanTopology: 'not-a-mesh',
    directDexaOrBodyFatControl: false,
  });
  expect(report.digs.reason).toContain('0.71s');
  expect(report.outOfScope).toMatchObject({
    omniFlashOutput: 'video-audio',
    omniFlashVerifiedMeshApi: false,
    gnmPublicRelease: 'head',
    gnmPublicBody: false,
    mojuloMatchesCompilerWording: true,
    mojuloIsBodyReconstruction: false,
    meshlibResult: 'existing-mesh-boolean',
    meshlibIsReconstruction: false,
    exactRememberedDemoConfirmed: false,
  });

  expect(productionPersonalBody().reason).toBe('personalization-disabled');
  expect(productionPersonalBody({ captures: [{ bodyState: syntheticSession }] }).personalized).toBe(
    false,
  );
  expect(JSON.parse(readFileSync(decisionPath, 'utf8'))).toEqual(decisionRecord());

  const stage = readFileSync(stagePath, 'utf8');
  const engine = readFileSync(enginePath, 'utf8');
  const attach = readFileSync(attachPath, 'utf8');
  const emptyStage = readFileSync(emptyStagePath, 'utf8');
  const record = readFileSync(recordPath, 'utf8');
  expect(stage).toContain('PersonalBodyEngine.appliedIllustration');
  expect(stage).toContain('photoByteCount: 0');
  expect(stage).not.toContain('launch_timeline_add_photo');
  expect(attach).not.toContain('PersonalBodyEngine');
  expect(engine).toContain('stage: .disabled');
  expect(engine).toContain('addsCaptureStep');
  expect(emptyStage).toContain('func testEmptyPhotoStageOpensAttachSheetForThatDay');
  expect(record).toContain('rings 1, 2, 5, 8, and 9');
  expect(record).toContain(
    'Simulator, physical-device, and distributed-build journeys were not run',
  );
  expect(record).toContain('testEmptyPhotoStageOpensAttachSheetForThatDay');
});
