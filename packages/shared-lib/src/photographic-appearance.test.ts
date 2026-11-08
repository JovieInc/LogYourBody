import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';
import {
  BASELINE_COVERAGE,
  BUDGET,
  FRAMING_ID,
  MODEL_ID,
  PRESENTATION_VERSION,
  RELEASE,
  RIGHTS,
  TOPOLOGY_ID,
  appearanceLabel,
  bodyFatClaim,
  coverage,
  defaultOptions,
  emptyArchive,
  estimateBytes,
  forgetAccount,
  forgetPhoto,
  lookupAppearance,
  motion,
  progressDisplay,
  project,
  promotionDecision,
  quantifyDrift,
  readForGesture,
  remember,
  replaceOriginal,
  sealedShape,
  shapeDrift,
  visibleRegion,
  weeklyChangeClaim,
  withinBudget,
  type AcceptedGeometry,
  type AppearanceAsset,
  type PhotoSample,
  type ProjectOptions,
  type PromotionEvidence,
  type Shape,
} from './photographic-appearance';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const read = (path: string) => readFileSync(`${root}/${path}`, 'utf8');

const shape: Shape = { adiposity: 0.42, muscularity: 0.31, frame: 0.58, depth: 0.47 };

function geometry(overrides: Partial<AcceptedGeometry> = {}): AcceptedGeometry {
  return {
    snapshotId: 'snapshot-1',
    accountId: 'account-a',
    bodyId: 'account-a.body',
    effectiveDate: '2026-11-01',
    captureDate: '2026-11-01',
    modelId: MODEL_ID,
    modelVersion: '1.0.0',
    topologyId: TOPOLOGY_ID,
    rigId: 'lyb.wireframe.torso.rig.v1',
    framingId: FRAMING_ID,
    shape: { ...shape },
    ...overrides,
  };
}

function tones(seed: number): number[] {
  return Array.from({ length: 8 }, (_, index) => (seed + index) / 20);
}

function sample(overrides: Partial<PhotoSample> = {}): PhotoSample {
  const photoId = overrides.photoId ?? 'photo-front';
  return {
    accountId: 'account-a',
    photoId,
    view: 'front',
    effectiveDate: '2026-11-01',
    captureDate: '2026-11-01',
    framingId: FRAMING_ID,
    quality: 'supported',
    samples: tones(2),
    sourceDigest: `digest-${photoId}`,
    ...overrides,
  };
}

function options(overrides: Partial<ProjectOptions> = {}): ProjectOptions {
  return { ...defaultOptions(), ...overrides };
}

function assetOf(result: ReturnType<typeof project>): AppearanceAsset {
  if (!result.asset) throw new Error(result.reason ?? 'missing asset');
  return result.asset;
}

it('projects observed photo samples onto the accepted mesh and leaves the shape alone', () => {
  const accepted = geometry();
  const front = sample();
  const originalTones = front.samples.slice();
  const result = project(accepted, [front], options());
  const asset = assetOf(result);
  expect(asset.interactive).toBe(true);
  expect(asset.representation).toBe('projection');
  expect(asset.gaussianLayerId).toBeNull();
  expect(asset.shape).toEqual(shape);
  expect(accepted.shape).toEqual(shape);
  expect(shapeDrift(shape, asset.shape)).toBe(0);
  expect(asset.geometryDrift).toBe(0);
  expect(asset.appearanceDrift).toBe(0);
  expect(front.samples).toEqual(originalTones);
  expect(
    asset.texels
      .filter((texel) => texel.region === 'front')
      .every((texel) => texel.provenance === 'observed'),
  ).toBe(true);
  expect(
    asset.texels
      .filter((texel) => texel.region === 'back')
      .every((texel) => texel.provenance === 'inferred' && texel.tone === null),
  ).toBe(true);
  expect(asset.splats).toEqual([]);
  expect(appearanceLabel(asset)).toBe('Observed front. Unseen surfaces stay unmarked.');
  expect(asset.claimsBodyFat).toBe(false);
  expect(asset.claimsWeeklyChange).toBe(false);
  expect(bodyFatClaim()).toBeNull();
  expect(weeklyChangeClaim()).toBeNull();
  expect(asset.modelVersion).toBe('1.0.0');
  expect(asset.presentationVersion).toBe(PRESENTATION_VERSION);
  expect(asset.captureDate).toBe('2026-11-01');
  expect(asset.framingId).toBe(FRAMING_ID);
  expect(asset.bodyId).toBe('account-a.body');
  expect(coverage(asset)).toBeGreaterThan(BASELINE_COVERAGE);
  expect(quantifyDrift([accepted], asset)).toEqual({
    matched: true,
    geometryDrift: 0,
    appearanceDrift: 0,
  });
});

it('stores a gaussian layer of the same observed samples without painting inferred cells', () => {
  const result = project(
    geometry(),
    [
      sample(),
      sample({
        photoId: 'photo-side',
        view: 'side',
        samples: tones(4),
        sourceDigest: 'digest-side',
      }),
    ],
    options({ representation: 'gaussian' }),
  );
  const asset = assetOf(result);
  expect(asset.representation).toBe('gaussian');
  expect(asset.gaussianLayerId).toBe('lyb.appearance.gaussian-layer.v1');
  expect(asset.splats.length).toBe(16);
  expect(asset.splats.every((splat) => splat.provenance === 'observed')).toBe(true);
  expect(asset.splats.some((splat) => splat.cellId.startsWith('back'))).toBe(false);
  expect(asset.inferredCount).toBe(8);
  expect(asset.shape.muscularity).toBe(shape.muscularity);
});

it('refuses a turntable, a remote rebuild, an unlicensed model, and a gesture-time project', () => {
  const accepted = geometry();
  const front = sample();
  expect(project(accepted, [front], options({ representation: 'turntable' })).reason).toBe(
    'not-interactive',
  );
  expect(project(accepted, [front], options({ remoteRequested: true })).reason).toBe(
    'remote-regeneration',
  );
  expect(project(accepted, [front], options({ gesture: true })).reason).toBe('gesture');
  expect(project(accepted, [front], options({ requestedModel: 'DiGS-Avatar' })).reason).toBe(
    'license',
  );
  expect(project(accepted, [front], options({ licenseOk: false })).reason).toBe('license');
  expect(project(accepted, [front], options({ computeAvailable: false })).reason).toBe('compute');
  expect(project(accepted, [front], options({ thermal: 'critical' })).reason).toBe('thermal');
  expect(project(accepted, [front], options({ memoryLimitBytes: 100 })).reason).toBe('budget');
  expect(project(accepted, [sample({ quality: 'poseChanged' })], options()).reason).toBe(
    'unsupported',
  );
  expect(
    project(geometry({ topologyId: 'lyb.wireframe.torso.v2' }), [front], options()).reason,
  ).toBe('model');
  expect(RIGHTS.bundledModels).toEqual([]);
  expect(RIGHTS.refusedModels).toContain('DiGS-Avatar');
  const lowEnd = project(
    accepted,
    [front],
    options({ representation: 'gaussian', lowEndDevice: true }),
  );
  expect(lowEnd.asset?.representation).toBe('projection');
  expect(lowEnd.asset?.splats).toEqual([]);
  expect(withinBudget(estimateBytes('gaussian', BUDGET.cellCount), true, null)).toBe(false);
  expect(withinBudget(estimateBytes('projection', BUDGET.cellCount), true, null)).toBe(true);
});

it('does not write synthesized samples back onto the original photo', () => {
  const original = tones(2);
  const synthesized = tones(9);
  const refusal = replaceOriginal(original, synthesized);
  expect(refusal.ok).toBe(false);
  expect(refusal.reason).toBe('original-photo');
  expect(original).toEqual(tones(2));
  const sealed = sealedShape(shape, { ...shape, muscularity: 0.95, adiposity: 0.1 });
  expect(sealed.rejectedDelta).toBeGreaterThan(0);
  expect(sealed.shape).toEqual(shape);
  expect(shape.muscularity).toBe(0.31);
});

it('scrubs a cache, rotates one viewpoint, and does not call the change body progress', () => {
  const earlier = assetOf(project(geometry(), [sample()], options()));
  const later = assetOf(
    project(
      geometry({
        snapshotId: 'snapshot-2',
        effectiveDate: '2026-11-08',
        captureDate: '2026-11-08',
        shape: { ...shape, adiposity: 0.5 },
      }),
      [
        sample({
          photoId: 'photo-later',
          effectiveDate: '2026-11-08',
          captureDate: '2026-11-08',
          samples: tones(6),
        }),
      ],
      options(),
    ),
  );
  const cache = [earlier, later];
  expect(lookupAppearance('2026-11-08', cache, TOPOLOGY_ID)?.snapshotId).toBe('snapshot-2');
  expect(lookupAppearance('2026-11-03', cache, TOPOLOGY_ID)).toBeNull();
  expect(cache).toHaveLength(2);
  const read = readForGesture(later.cacheKey, cache, false);
  expect(read.regenerated).toBe(false);
  expect(read.asset?.id).toBe(later.id);
  expect(readForGesture(later.cacheKey, cache, true)).toEqual({
    asset: null,
    regenerated: false,
    reason: 'remote-regeneration',
  });
  expect(visibleRegion(0)).toBe('front');
  expect(visibleRegion(Math.PI / 2)).toBe('side');
  expect(visibleRegion(Math.PI)).toBe('back');
  const progress = progressDisplay(earlier, later, 0);
  expect(progress.bodyFatDelta).toBeNull();
  expect(progress.weeklyChange).toBeNull();
  expect(progress.geometryChangedByAppearance).toBe(false);
  expect(progress.label).toBe('Appearance only. Not a weekly change.');
  expect(progress.before).toEqual(earlier.shape);
  expect(progress.after).toEqual(later.shape);
  expect(progressDisplay(earlier, later, Math.PI).label).toBe(
    'Viewpoint has no shared observation',
  );
  expect(motion(true)).toEqual({ duration: 0, autoSpin: false });
  expect(motion(false).autoSpin).toBe(false);
});

it('deletes derived textures with the photo and the account', () => {
  const front = sample();
  const side = sample({
    photoId: 'photo-side',
    view: 'side',
    samples: tones(4),
    sourceDigest: 'digest-side',
  });
  const saved = remember(remember(emptyArchive('account-a'), front, geometry()), side, geometry());
  expect(saved.assets).toHaveLength(1);
  expect(saved.assets[0]?.photoIds).toEqual(['photo-front', 'photo-side']);
  const original = front.samples.slice();
  const forgotten = forgetPhoto(saved, 'photo-front');
  expect(forgotten.assets).toEqual([]);
  expect(forgotten.samples.map((item) => item.photoId)).toEqual(['photo-side']);
  expect(forgetPhoto(forgotten, 'photo-side').geometries).toEqual([]);
  expect(front.samples).toEqual(original);
  expect(forgetAccount(saved).assets).toEqual([]);
  expect(forgetAccount(saved).samples).toEqual([]);
});

it('keeps promotion behind repeatability, a real coverage gain, and device evidence', () => {
  const asset = assetOf(project(geometry(), [sample()], options()));
  const base: PromotionEvidence = {
    tier: 'repeatable-on-device',
    baselineObservedCoverage: BASELINE_COVERAGE,
    observedCoverage: coverage(asset),
    geometryDrift: 0,
    introducedBodyFatClaim: false,
    introducedWeeklyChange: false,
    truthfulProgress: true,
    rightsRecorded: true,
    lowEndDeviceEvidence: 'source',
  };
  expect(promotionDecision(base).promoted).toBe(false);
  expect(promotionDecision(base).reasons).toContain('device-evidence');
  expect(promotionDecision({ ...base, lowEndDeviceEvidence: 'simulator' }).promoted).toBe(false);
  expect(promotionDecision({ ...base, observedCoverage: 0 }).reasons).toContain('improvement');
  expect(
    promotionDecision({ ...base, geometryDrift: 0.2, lowEndDeviceEvidence: 'physical-device' })
      .reasons,
  ).toContain('geometry-drift');
  expect(
    promotionDecision({
      ...base,
      introducedWeeklyChange: true,
      lowEndDeviceEvidence: 'distributed-build',
    }).reasons,
  ).toContain('false-progress');
  expect(promotionDecision({ ...base, lowEndDeviceEvidence: 'physical-device' })).toEqual({
    promoted: true,
    reasons: [],
  });
  expect(RELEASE).toEqual({
    blocksPaidR1: false,
    blocksPhotoTimeline: false,
    blocksWireframe: false,
    blocksPersonalMesh: false,
  });
});

it('wires the native stage without blocking the photo timeline or paid R1', () => {
  const model =
    read('apps/ios/LogYourBody/Components/PhotographicAppearance.swift') +
    read('apps/ios/LogYourBody/Components/PhotographicAppearanceSupport.swift');
  const stage = read('apps/ios/LogYourBody/Components/PhotographicAppearanceCanvas.swift');
  const hero = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2TimelineHero.swift');
  const surface = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2Surface.swift');
  const deletion = read('apps/ios/LogYourBody/Views/DeleteAccountView.swift');
  const sync = read('apps/ios/LogYourBody/Services/RealtimeSyncManager+Part02.swift');
  const emptyStage = read('apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift');
  const boundary = read('docs/product/paid-r1-personalized-3d-boundary.md');
  const roadmap = read('docs/product-development-roadmap.md');
  expect(model).toContain('DiGS-Avatar');
  expect(model).toContain('original-photo');
  expect(model).toContain('not-interactive');
  expect(model).toContain('photographic_appearance_v1');
  expect(stage).toContain('photographic_appearance_stage');
  expect(stage).toContain('Not a body-fat measurement');
  expect(stage).not.toContain('bodyFatPercentage');
  expect(hero).not.toContain('project(');
  expect(surface).toContain('PhotographicAppearanceStore');
  expect(deletion).toContain('PhotographicAppearanceStore.shared.forgetAccount');
  expect(sync).toContain('PhotographicAppearanceStore.shared.forget');
  expect(emptyStage).toContain('func testEmptyPhotoStageOpensAttachSheetForThatDay');
  expect(boundary).toContain('stay outside paid R1');
  expect(roadmap).toContain('only inside LYB-311');
  expect(roadmap).toContain('LYB-319');
});
