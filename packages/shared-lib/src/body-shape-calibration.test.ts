import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';
import {
  compareModelVersions,
  corpus,
  derivedFfmi,
  displayedBucket,
  evaluate,
  families,
  ILLUSTRATIVE_BADGE,
  mapObservation,
  MODEL_VERSION,
  rmsShape,
  thresholds,
  weeklyClaimAllowed,
  wireframeClaim,
  type Observation,
} from './body-shape-calibration';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const types = readFileSync(new URL('./body-shape-calibration-types.ts', import.meta.url), 'utf8');
const corpusSource = readFileSync(
  new URL('./body-shape-calibration-corpus.ts', import.meta.url),
  'utf8',
);
const mapSource = readFileSync(new URL('./body-shape-calibration-map.ts', import.meta.url), 'utf8');
const evaluateSource = readFileSync(
  new URL('./body-shape-calibration-evaluate.ts', import.meta.url),
  'utf8',
);
const swift = readFileSync(
  `${root}/apps/ios/LogYourBody/Components/BodyShapeCalibration.swift`,
  'utf8',
);
const catalog = readFileSync(
  `${root}/apps/ios/LogYourBody/Models/DashboardDisplayMode.swift`,
  'utf8',
);
const stage = readFileSync(
  `${root}/apps/ios/LogYourBody/Components/WireframeAvatarStage.swift`,
  'utf8',
);
const project = readFileSync(`${root}/apps/ios/LogYourBody.xcodeproj/project.pbxproj`, 'utf8');
const emptyStage = readFileSync(
  `${root}/apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift`,
  'utf8',
);

it('declares promotion gates before the corpus and does not refit them', () => {
  expect(types.indexOf('export const thresholds')).toBeGreaterThan(0);
  expect(corpusSource.indexOf('export const corpus')).toBeGreaterThan(0);
  expect(evaluateSource.indexOf('export function evaluate')).toBeGreaterThan(0);
  expect(corpusSource).toContain("from './body-shape-calibration-types'");
  expect(mapSource.indexOf("['non-finite']")).toBeLessThan(
    mapSource.indexOf("['unsupported-mass']"),
  );
  expect(evaluateSource).toContain('mapObservation');
  expect(thresholds.declaredBeforeEvaluation).toBe(true);
  expect(thresholds.personalizedShapeEstimate.minConsentedOrLicensedSubjectsPerSex).toBe(30);
  expect(thresholds.calibratedCompositionAppearance.minHeldOutSubjectsPerSex).toBe(30);
  expect(thresholds.calibratedCompositionAppearance.compositionMaePercentagePoints).toBe(2);
  expect(thresholds.calibratedCompositionAppearance.evidenceClass).toBe('consented-human');
  expect(thresholds.longitudinalInterpretation.minWithinPersonWeeklyPairs).toBe(20);
  expect(thresholds.longitudinalInterpretation.weeklyIntervalDays).toEqual([5, 9]);
  expect(thresholds.longitudinalInterpretation.maxStudySpanDays).toBe(9);
  expect(thresholds.longitudinalInterpretation.crossSectionalPairsCount).toBe(false);
  const before = JSON.stringify(thresholds);
  evaluate();
  expect(JSON.stringify(thresholds)).toBe(before);
  expect(Object.isFrozen(thresholds)).toBe(true);
  expect(Object.isFrozen(families)).toBe(true);
});

it('promotes only the illustrative tier and keeps percentage claims unavailable', () => {
  const report = evaluate();
  expect(report.modelVersion).toBe(MODEL_VERSION);
  expect(report.population).toBe('synthetic-regression');
  expect(report.referenceLicense).toBe('none-bundled');
  expect(report.sampleSize.consentedHumanSubjects).toBe(0);
  expect(report.sampleSize.trainingSubjects).toBe(2);
  expect(report.sampleSize.heldOutSubjects).toBe(8);
  expect(report.sampleSize.consentedHeldOutPerSex).toEqual({ 'adult-male': 0, 'adult-female': 0 });
  expect(report.properties.heldOutDisjointFromTraining).toBe(true);
  expect(report.properties.ffmiNeverShapes).toBe(true);
  expect(report.properties.unsupportedAbstain).toBe(true);
  expect(report.tiers['illustrative-wireframe'].pass).toBe(true);
  expect(report.tiers['personalized-shape-estimate'].pass).toBe(false);
  expect(report.tiers['calibrated-composition-appearance'].pass).toBe(false);
  expect(report.tiers['longitudinal-interpretation'].pass).toBe(false);
  expect(report.allowedClaims.badge).toBe(ILLUSTRATIVE_BADGE);
  expect(report.allowedClaims.percentageOnShape).toBeNull();
  expect(report.allowedClaims.weeklyChange).toBeNull();
  expect(report.limitations.join(' ')).toContain('not a clinical mapping');
  expect(report.limitations.join(' ')).toContain('not weekly phone photos');
});

it('reports alignment, shape drift, composition, and longitudinal error separately', () => {
  const report = evaluate();
  const repeats = corpus.captures.filter((row) => row.factor === 'repeat');
  const controlled = corpus.captures.filter((row) => row.factor !== 'repeat');
  const baseline = repeats[0];
  const expectedControlledDrift =
    controlled
      .map((row) => rmsShape(row.shape, baseline.shape))
      .reduce((sum, value) => sum + value, 0) / controlled.length;
  expect(report.errors.alignment.sameDay).toBeCloseTo((0.4 + 0.45) / 2, 9);
  expect(report.errors.shapeDrift.sameDay).toBeCloseTo(
    rmsShape(repeats[0].shape, repeats[1].shape),
    9,
  );
  expect(report.errors.shapeDrift.controlled).toBeCloseTo(expectedControlledDrift, 9);
  expect(report.errors.shapeDrift.controlled).toBeGreaterThan(report.errors.shapeDrift.sameDay);
  expect(report.errors.shapeDrift.sameDay).toBeLessThan(
    thresholds.calibratedCompositionAppearance.sameDayShapeDriftMax,
  );
  expect(report.errors.shapeDrift.productPhotoReconstruction).toBe('unavailable');
  expect(report.errors.shapeDrift.byFactor).toMatchObject({
    angle: expect.any(Object),
    distance: expect.any(Object),
    mirror: expect.any(Object),
    posture: expect.any(Object),
    lighting: expect.any(Object),
    clothing: expect.any(Object),
    'phone-occlusion': expect.any(Object),
  });
  expect(report.errors.composition.photo).toBeNull();
  expect(report.errors.composition.independentAbsolutePercentagePoints).toBeGreaterThan(2);
  expect(report.errors.composition.independentAbsolutePercentagePoints).toBeCloseTo(7.18, 2);
  expect(report.errors.longitudinalChange.sameDayClass).toBe('capture-noise');
  expect(report.errors.longitudinalChange.weeklyEligiblePairs).toBe(0);
  expect(report.errors.longitudinalChange.sameDayApparentAdiposity).not.toBe(
    report.errors.composition.independentAbsolutePercentagePoints,
  );
  const exclusions = Object.fromEntries(
    report.errors.longitudinalChange.pairs.map((pair) => [pair.id, pair.exclusion]),
  );
  expect(exclusions).toEqual({
    X1: 'not-within-person',
    L1: 'study-span-exceeds-weekly-window',
    W1: 'synthetic-evidence',
    'W2-sliced-from-long-study': 'study-span-exceeds-weekly-window',
  });
});

it('keeps muscle, lean tissue, and fat-free mass distinct and abstains outside the family', () => {
  const male = corpus.observations.find((row) => row.id === 'H7');
  expect(male).toBeDefined();
  const decision = mapObservation(male as Observation);
  expect(decision.ffmiIgnored).toBe(true);
  expect(decision.muscleSource).toBe('skeletal-muscle');
  expect(decision.derivedFfmi).toBeCloseTo(derivedFfmi(64, 1.8) as number, 9);
  expect(decision.derivedFfmi).not.toBe(99);
  expect(decision.skeletalMuscleKg).toBe(32);

  const samePercent = mapObservation({
    ...(male as Observation),
    id: 'shape-a',
    subjectId: 'shape-a',
    ffmi: null,
    distribution: 'central',
  });
  const otherBuild = mapObservation({
    ...(male as Observation),
    id: 'shape-b',
    subjectId: 'shape-b',
    ffmi: null,
    heightM: 1.7,
    bodyMassKg: 100,
    fatMassKg: 20,
    fatFreeMassKg: 80,
    distribution: 'peripheral',
  });
  expect(samePercent.parameters.adiposity).not.toBe(otherBuild.parameters.adiposity);
  expect(samePercent.parameters.distribution).not.toBe(otherBuild.parameters.distribution);

  const percentOnly = mapObservation({
    ...(male as Observation),
    id: 'percent-only',
    fatMassKg: null,
    fatFreeMassKg: null,
    leanSoftTissueKg: null,
    skeletalMuscleKg: null,
    boneMineralKg: null,
    distribution: null,
    frame: null,
    ffmi: null,
  });
  expect(percentOnly.parameters.adiposity).not.toBeNull();
  expect(percentOnly.parameters.muscularity).toBeNull();
  expect(percentOnly.parameters.frame).toBeNull();

  const child = mapObservation({ ...(male as Observation), id: 'child', ageYears: 16, ffmi: null });
  expect(child.status).toBe('abstained');
  const infiniteMass = mapObservation({
    ...(male as Observation),
    id: 'infinite-mass',
    bodyMassKg: Number.POSITIVE_INFINITY,
    ffmi: null,
  });
  expect(infiniteMass.status).toBe('abstained');
  expect(infiniteMass.reasons).toContain('non-finite');
  expect(child.parameters).toEqual({
    adiposity: null,
    muscularity: null,
    frame: null,
    distribution: null,
  });
  expect(mapObservation(male as Observation)).toEqual(mapObservation(male as Observation));
});

it('quantifies a model update and refuses to call it progress', () => {
  const comparison = compareModelVersions(corpus.modelUpdate);
  expect(comparison.adiposityDelta).toBeCloseTo(-0.12, 9);
  expect(comparison.comparable).toBe(false);
  expect(comparison.apparentProgress).toBeNull();
  expect(comparison.disclosure).toContain('not body change');
  expect(
    weeklyClaimAllowed({
      longitudinalPromoted: true,
      evidenceClass: 'consented-human',
      intervalDays: 7,
      studySpanDays: 151,
      sameModel: true,
      sameDexa: true,
    }),
  ).toBe(false);
  expect(
    weeklyClaimAllowed({
      longitudinalPromoted: false,
      evidenceClass: 'consented-human',
      intervalDays: 7,
      studySpanDays: 7,
      sameModel: true,
      sameDexa: true,
    }),
  ).toBe(false);
  expect(
    displayedBucket({
      bodyFatPercentage: 16.4,
      supportedMin: 5,
      supportedMax: 45,
      buckets: [5, 8, 10, 12, 15, 18, 22, 27, 35, 45, 55],
      fallback: 18,
      compositionPromoted: false,
    }),
  ).toBe(18);
  expect(
    displayedBucket({
      bodyFatPercentage: 80,
      supportedMin: 5,
      supportedMax: 45,
      buckets: [5, 8, 10, 12, 15, 18, 22, 27, 35, 45, 55],
      fallback: 18,
      compositionPromoted: true,
    }),
  ).toBe(18);
});

it('wires the closed report into the native avatar and the LYB-64 empty-stage path', () => {
  expect(swift).toContain('"illustrative-wireframe": true');
  expect(swift).toContain('"personalized-shape-estimate": false');
  expect(swift).toContain('"calibrated-composition-appearance": false');
  expect(swift).toContain('"longitudinal-interpretation": false');
  expect(swift).toContain('6.1 * (1.8 - heightM)');
  expect(swift).toContain(ILLUSTRATIVE_BADGE);
  expect(swift).toContain('Illustrative \\(body) wireframe. Not a body-fat percentage.');
  expect(wireframeClaim('female')).toBe(
    'Illustrative female wireframe. Not a body-fat percentage.',
  );
  expect(families['adult-male'].bodyFatPercent).toEqual([5, 45]);
  expect(swift).toContain('bodyFatMin: 5, bodyFatMax: 45');
  expect(swift).toContain('bodyFatMin: 12, bodyFatMax: 55');
  expect(catalog).not.toContain('% body fat');
  expect(catalog).not.toContain('percent body fat');
  expect(catalog).toContain('BodyShapeCalibration.displayedBucket');
  expect(stage).toContain('home_wireframe_claim');
  expect(stage).toContain('BodyShapeCalibration.wireframeAccessibilityLabel');
  expect(stage).not.toContain('bodyFatPercentage');
  expect(emptyStage).toContain('func testEmptyPhotoStageOpensAttachSheetForThatDay');
  expect(project).toContain('BodyShapeCalibration.swift in Sources');
  expect(project).toContain('BodyShapeCalibrationTests.swift in Sources');
});
