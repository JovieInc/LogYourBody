import {
  families,
  MODEL_CHANGE_DISCLOSURE,
  SAME_MODEL_DISCLOSURE,
  thresholds,
  tolerances,
  type BodyFamily,
  type MuscleSource,
  type Observation,
  type ShapeDecision,
  type ShapeParameters,
} from './body-shape-calibration-types';

const inside = (value: number, bounds: readonly [number, number]) =>
  Number.isFinite(value) && value >= bounds[0] && value <= bounds[1];

const unit = (value: number, bounds: readonly [number, number]) => {
  if (!inside(value, bounds)) return null;
  return (value - bounds[0]) / (bounds[1] - bounds[0]);
};

/** Same normalized FFMI as UnitConversion.calculateFFMI. Lineage only. */
export function derivedFfmi(fatFreeMassKg: number, heightM: number) {
  if (
    !Number.isFinite(fatFreeMassKg) ||
    !Number.isFinite(heightM) ||
    fatFreeMassKg <= 0 ||
    heightM <= 0
  ) {
    return null;
  }
  return fatFreeMassKg / (heightM * heightM) + 6.1 * (1.8 - heightM);
}

export function dxaKey(
  observation: Pick<Observation, 'method' | 'dxaDevice' | 'dxaSoftware' | 'dxaStudyDate'>,
) {
  if (observation.method !== 'dxa') return null;
  const { dxaDevice, dxaSoftware, dxaStudyDate } = observation;
  if (!dxaDevice || !dxaSoftware || !dxaStudyDate) return null;
  return `${dxaDevice}|${dxaSoftware}|${dxaStudyDate}`;
}

export function mapObservation(observation: Observation): ShapeDecision {
  const reasons: string[] = [];
  const ffmiIgnored = observation.ffmi != null;
  const key = dxaKey(observation);
  const family =
    observation.family === 'adult-male' || observation.family === 'adult-female'
      ? families[observation.family]
      : null;
  const empty: ShapeParameters = {
    adiposity: null,
    muscularity: null,
    frame: null,
    distribution: null,
  };

  const finish = (
    status: ShapeDecision['status'],
    parameters: ShapeParameters,
    muscleSource: MuscleSource | null,
    extra: string[] = [],
  ): ShapeDecision => {
    const provenanceComplete = key != null;
    const distributionSpecified = parameters.distribution != null;
    const uncertainty =
      parameters.adiposity == null
        ? null
        : Math.min(1, 0.2 + (distributionSpecified ? 0 : 0.1) + (provenanceComplete ? 0 : 0.1));
    const ffm = observation.fatFreeMassKg;
    const height = observation.heightM;
    const balanced = !reasons.includes('mass-balance') && !extra.includes('mass-balance');
    return {
      status,
      parameters,
      muscleSource,
      skeletalMuscleKg: muscleSource === 'skeletal-muscle' ? observation.skeletalMuscleKg : null,
      leanSoftTissueKg: observation.leanSoftTissueKg,
      fatFreeMassKg: observation.fatFreeMassKg,
      ffmiIgnored,
      derivedFfmi: balanced && ffm != null && height != null ? derivedFfmi(ffm, height) : null,
      uncertainty,
      provenanceComplete,
      dxaComparabilityKey: key,
      reasons: [...reasons, ...extra],
    };
  };

  if (!family) return finish('abstained', empty, null, ['unsupported-family']);
  const finiteFields = [
    observation.ageYears,
    observation.heightM,
    observation.bodyMassKg,
    observation.bodyFatPercent,
    observation.fatMassKg,
    observation.fatFreeMassKg,
    observation.leanSoftTissueKg,
    observation.skeletalMuscleKg,
    observation.boneMineralKg,
    observation.frame,
    observation.ffmi,
  ];
  if (finiteFields.some((value) => value != null && !Number.isFinite(value))) {
    return finish('abstained', empty, null, ['non-finite']);
  }
  if (!inside(observation.ageYears, family.ageYears))
    return finish('abstained', empty, null, ['unsupported-age']);
  if (observation.heightM == null || !inside(observation.heightM, family.heightM)) {
    return finish('abstained', empty, null, ['unsupported-height']);
  }
  if (observation.bodyMassKg == null || !inside(observation.bodyMassKg, family.bodyMassKg)) {
    return finish('abstained', empty, null, ['unsupported-mass']);
  }
  const height = observation.heightM;
  const mass = observation.bodyMassKg;

  let fat = observation.fatMassKg;
  if (
    observation.bodyFatPercent != null &&
    !inside(observation.bodyFatPercent, family.bodyFatPercent)
  ) {
    reasons.push('unsupported-body-fat');
  }
  if (
    fat == null &&
    observation.bodyFatPercent != null &&
    !reasons.includes('unsupported-body-fat')
  ) {
    fat = mass * (observation.bodyFatPercent / 100);
  }
  if (
    fat != null &&
    observation.bodyFatPercent != null &&
    Math.abs(observation.bodyFatPercent - (fat / mass) * 100) > tolerances.bodyFatPercentagePoints
  ) {
    reasons.push('body-fat-conflict');
  }
  const ffm = observation.fatFreeMassKg;
  if (fat != null && ffm != null && Math.abs(fat + ffm - mass) > tolerances.massBalanceKg) {
    reasons.push('mass-balance');
  }
  if (
    reasons.includes('mass-balance') ||
    reasons.includes('body-fat-conflict') ||
    reasons.includes('unsupported-body-fat')
  ) {
    return finish('abstained', empty, null);
  }

  const parameters: ShapeParameters = {
    adiposity: null,
    muscularity: null,
    frame: null,
    distribution: observation.distribution,
  };
  if (fat == null) reasons.push('missing-fat');
  else {
    const adiposity = unit(fat / (height * height), family.fatMassIndex);
    parameters.adiposity = adiposity;
    if (adiposity == null) reasons.push('unsupported-fat-mass-index');
  }

  let muscleSource: MuscleSource | null = null;
  const sm = observation.skeletalMuscleKg;
  const lst = observation.leanSoftTissueKg;
  const bone = observation.boneMineralKg;
  if (
    lst != null &&
    bone != null &&
    ffm != null &&
    Math.abs(lst + bone - ffm) > tolerances.leanBalanceKg
  ) {
    reasons.push('lean-balance');
  } else if (sm != null && lst != null && sm > lst + tolerances.skeletalMuscleAboveLeanKg) {
    reasons.push('skeletal-muscle-exceeds-lean');
  } else if (sm != null) {
    const muscularity = unit(sm / (height * height), family.skeletalMuscleIndex);
    parameters.muscularity = muscularity;
    muscleSource = muscularity == null ? null : 'skeletal-muscle';
    if (muscularity == null) reasons.push('unsupported-muscle-index');
  } else if (lst != null) {
    const muscularity = unit(lst / (height * height), family.leanSoftTissueIndex);
    parameters.muscularity = muscularity;
    muscleSource = muscularity == null ? null : 'lean-soft-tissue';
    if (muscularity == null) reasons.push('unsupported-muscle-index');
  } else if (ffm != null && bone != null) {
    const derivedLean = ffm - bone;
    const muscularity = unit(derivedLean / (height * height), family.leanSoftTissueIndex);
    parameters.muscularity = muscularity;
    muscleSource = muscularity == null ? null : 'fat-free-mass-minus-bone';
    if (muscularity == null) reasons.push('unsupported-muscle-index');
  } else {
    reasons.push('missing-muscle');
  }

  if (observation.frame == null) reasons.push('missing-frame');
  else if (observation.frame < 0 || observation.frame > 1) reasons.push('unsupported-frame');
  else parameters.frame = observation.frame;

  const status =
    parameters.adiposity != null && parameters.muscularity != null && parameters.frame != null
      ? 'estimated'
      : parameters.adiposity != null || parameters.muscularity != null || parameters.frame != null
        ? 'partial'
        : 'abstained';
  return finish(status, parameters, muscleSource);
}

export function readBackBodyFatPercent(
  family: BodyFamily,
  adiposity: number,
  bodyMassKg: number,
  heightM: number,
) {
  const bounds = families[family].fatMassIndex;
  const fatMassIndex = bounds[0] + adiposity * (bounds[1] - bounds[0]);
  return ((fatMassIndex * heightM * heightM) / bodyMassKg) * 100;
}

export function rmsShape(
  left: { adiposity: number; muscularity: number; frame: number },
  right: { adiposity: number; muscularity: number; frame: number },
) {
  const deltas = [
    left.adiposity - right.adiposity,
    left.muscularity - right.muscularity,
    left.frame - right.frame,
  ];
  return Math.sqrt(deltas.reduce((sum, delta) => sum + delta * delta, 0) / 3);
}

export interface ModelComparison {
  fromVersion: string;
  toVersion: string;
  adiposityDelta: number;
  comparable: boolean;
  apparentProgress: null;
  disclosure: string;
}

export function compareModelVersions(input: {
  fromVersion: string;
  toVersion: string;
  fromAdiposity: number;
  toAdiposity: number;
}): ModelComparison {
  const adiposityDelta = input.toAdiposity - input.fromAdiposity;
  if (input.fromVersion !== input.toVersion) {
    return {
      fromVersion: input.fromVersion,
      toVersion: input.toVersion,
      adiposityDelta,
      comparable: false,
      apparentProgress: null,
      disclosure: MODEL_CHANGE_DISCLOSURE,
    };
  }
  return {
    fromVersion: input.fromVersion,
    toVersion: input.toVersion,
    adiposityDelta,
    comparable: true,
    apparentProgress: null,
    disclosure: SAME_MODEL_DISCLOSURE,
  };
}

export function weeklyClaimAllowed(input: {
  longitudinalPromoted: boolean;
  evidenceClass: string;
  intervalDays: number;
  studySpanDays: number;
  sameModel: boolean;
  sameDexa: boolean;
}) {
  const [minDays, maxDays] = thresholds.longitudinalInterpretation.weeklyIntervalDays;
  return (
    input.longitudinalPromoted &&
    input.evidenceClass === thresholds.longitudinalInterpretation.evidenceClass &&
    input.sameModel &&
    input.sameDexa &&
    input.intervalDays >= minDays &&
    input.intervalDays <= maxDays &&
    input.studySpanDays >= minDays &&
    input.studySpanDays <= thresholds.longitudinalInterpretation.maxStudySpanDays
  );
}

export function displayedBucket(input: {
  bodyFatPercentage: number | null;
  supportedMin: number;
  supportedMax: number;
  buckets: readonly number[];
  fallback: number;
  compositionPromoted: boolean;
}) {
  const value = input.bodyFatPercentage;
  if (
    !input.compositionPromoted ||
    value == null ||
    value < input.supportedMin ||
    value > input.supportedMax
  ) {
    return input.fallback;
  }
  const eligible = input.buckets.filter(
    (bucket) => bucket >= input.supportedMin && bucket <= input.supportedMax,
  );
  if (eligible.length === 0) return input.fallback;
  return eligible.reduce((best, bucket) => {
    const bestDistance = Math.abs(best - value);
    const distance = Math.abs(bucket - value);
    if (distance < bestDistance || (distance === bestDistance && bucket < best)) return bucket;
    return best;
  });
}
