import { corpus } from './body-shape-calibration-corpus';
import {
  compareModelVersions,
  mapObservation,
  readBackBodyFatPercent,
  rmsShape,
  weeklyClaimAllowed,
} from './body-shape-calibration-map';
import {
  figureClaim,
  ILLUSTRATIVE_BADGE,
  MODEL_ID,
  MODEL_VERSION,
  thresholds,
  wireframeClaim,
} from './body-shape-calibration-types';

const mean = (values: number[]) => values.reduce((sum, value) => sum + value, 0) / values.length;

export function evaluate() {
  const decisions = corpus.observations.map((observation) => ({
    observation,
    decision: mapObservation(observation),
  }));
  const heldOut = decisions.filter((row) => row.observation.split === 'held-out');
  const trainingIds = corpus.observations
    .filter((row) => row.split === 'training')
    .map((row) => row.subjectId);
  const repeats = corpus.captures.filter((row) => row.factor === 'repeat');
  const controlled = corpus.captures.filter((row) => row.factor !== 'repeat');
  const baseline = repeats[0];
  const byFactor = Object.fromEntries(
    controlled.map((row) => [
      row.factor,
      {
        alignmentResidual: row.alignmentResidual,
        shapeDrift: rmsShape(row.shape, baseline.shape),
      },
    ]),
  );
  const independent = corpus.independentComposition;
  const readBack = readBackBodyFatPercent(
    independent.family,
    independent.adiposity,
    independent.bodyMassKg,
    independent.heightM,
  );
  const compositionError = Math.abs(readBack - independent.referenceBodyFatPercent);
  const modelUpdate = compareModelVersions(corpus.modelUpdate);
  const weekly = corpus.changePairs.map((pair) => ({
    ...pair,
    eligible: weeklyClaimAllowed({ ...pair, longitudinalPromoted: false }),
    exclusion:
      pair.kind === 'cross-sectional'
        ? 'not-within-person'
        : pair.studySpanDays > thresholds.longitudinalInterpretation.maxStudySpanDays
          ? 'study-span-exceeds-weekly-window'
          : (pair.evidenceClass as string) === thresholds.longitudinalInterpretation.evidenceClass
            ? 'interval'
            : 'synthetic-evidence',
  }));
  const consentedPerSex = { 'adult-male': 0, 'adult-female': 0 };
  const syntheticHeldOutPerSex = { 'adult-male': 0, 'adult-female': 0 };
  for (const row of heldOut) {
    if (row.observation.family === 'adult-male' || row.observation.family === 'adult-female') {
      syntheticHeldOutPerSex[row.observation.family] += 1;
    }
  }
  const properties = {
    heldOutDisjointFromTraining: heldOut.every(
      (row) => !trainingIds.includes(row.observation.subjectId),
    ),
    ffmiNeverShapes:
      decisions.every((row) => row.decision.ffmiIgnored === (row.observation.ffmi != null)) &&
      decisions
        .filter((row) => row.observation.ffmi != null)
        .every((row) => row.decision.derivedFfmi !== row.observation.ffmi),
    unsupportedAbstain: decisions
      .filter(
        (row) =>
          row.observation.ageYears < 18 ||
          row.observation.bodyFatPercent === 60 ||
          row.observation.family === 'unspecified',
      )
      .every((row) => row.decision.status === 'abstained'),
  };
  const personalizedPass =
    properties.heldOutDisjointFromTraining &&
    properties.ffmiNeverShapes &&
    properties.unsupportedAbstain &&
    corpus.consentedOrLicensedPairedScans >=
      thresholds.personalizedShapeEstimate.minConsentedOrLicensedSubjectsPerSex &&
    consentedPerSex['adult-male'] >=
      thresholds.personalizedShapeEstimate.minConsentedOrLicensedSubjectsPerSex &&
    consentedPerSex['adult-female'] >=
      thresholds.personalizedShapeEstimate.minConsentedOrLicensedSubjectsPerSex;
  const sameDayShapeDrift = rmsShape(repeats[0].shape, repeats[1].shape);
  const controlledShapeDrift = mean(Object.values(byFactor).map((row) => row.shapeDrift));
  const population: string = corpus.population;
  const calibratedPass =
    population === thresholds.calibratedCompositionAppearance.evidenceClass &&
    consentedPerSex['adult-male'] >=
      thresholds.calibratedCompositionAppearance.minHeldOutSubjectsPerSex &&
    consentedPerSex['adult-female'] >=
      thresholds.calibratedCompositionAppearance.minHeldOutSubjectsPerSex &&
    compositionError <= thresholds.calibratedCompositionAppearance.compositionMaePercentagePoints &&
    sameDayShapeDrift <= thresholds.calibratedCompositionAppearance.sameDayShapeDriftMax;
  const weeklyEligible = weekly.filter((pair) => pair.eligible).length;
  const longitudinalPass =
    weeklyEligible >= thresholds.longitudinalInterpretation.minWithinPersonWeeklyPairs;

  return {
    modelId: MODEL_ID,
    modelVersion: MODEL_VERSION,
    population: corpus.population,
    referenceLicense: corpus.referenceLicense,
    limitations: corpus.limitations,
    sampleSize: {
      observations: corpus.observations.length,
      trainingSubjects: trainingIds.length,
      heldOutSubjects: heldOut.length,
      consentedHumanSubjects: corpus.consentedOrLicensedPairedScans,
      consentedHeldOutPerSex: consentedPerSex,
      syntheticHeldOutPerSex,
      captureFixtures: corpus.captures.length,
      changePairs: corpus.changePairs.length,
    },
    properties,
    errors: {
      alignment: {
        sameDay: mean(repeats.map((row) => row.alignmentResidual)),
        controlled: mean(controlled.map((row) => row.alignmentResidual)),
      },
      shapeDrift: {
        sameDay: sameDayShapeDrift,
        controlled: controlledShapeDrift,
        byFactor,
        productPhotoReconstruction: 'unavailable' as const,
      },
      composition: {
        independentAbsolutePercentagePoints: compositionError,
        photo: null,
        promotesTier: false as const,
      },
      longitudinalChange: {
        sameDayApparentAdiposity: mean(
          controlled.map((row) => Math.abs(row.shape.adiposity - baseline.shape.adiposity)),
        ),
        sameDayClass: 'capture-noise' as const,
        weeklyEligiblePairs: weeklyEligible,
        pairs: weekly,
      },
    },
    modelUpdate,
    tiers: {
      'illustrative-wireframe': {
        pass: true,
        reason: 'Artistic wireframe. No body-fat or weekly claim.',
      },
      'personalized-shape-estimate': {
        pass: personalizedPass,
        reason: 'No consented or licensed paired reference corpus.',
      },
      'calibrated-composition-appearance': {
        pass: calibratedPass,
        reason:
          'Synthetic evidence and an independent composition error above the predeclared gate.',
      },
      'longitudinal-interpretation': {
        pass: longitudinalPass,
        reason:
          'No consented within-person weekly pairs. A five-month span is not weekly sensitivity.',
      },
    },
    allowedClaims: {
      badge: ILLUSTRATIVE_BADGE,
      wireframeMale: wireframeClaim('male'),
      wireframeFemale: wireframeClaim('female'),
      figureMale: figureClaim('Male'),
      figureFemale: figureClaim('Female'),
      percentageOnShape: null,
      weeklyChange: null,
    },
  };
}
