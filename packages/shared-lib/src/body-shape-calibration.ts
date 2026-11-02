/**
 * Body-shape calibration for LYB-318.
 *
 * Artistic sliders and bucket pictures are not body-fat percentages.
 * A plausible shape is not week-to-week change. Thresholds are declared
 * above the corpus and are not fit to held-out rows. The bundled corpus is
 * synthetic. It checks the evaluator. It is not a consented body scan.
 *
 * Fat-free mass, lean soft tissue, and skeletal muscle stay distinct.
 * FFMI is derived lineage only and is never a shape input.
 */

export const MODEL_ID = 'lyb.body-shape-calibration';
export const MODEL_VERSION = '1.0.0';

export const ILLUSTRATIVE_BADGE = 'Illustrative, not body fat';
export const MODEL_CHANGE_DISCLOSURE = 'Shape model changed. The difference is not body change.';
export const SAME_MODEL_DISCLOSURE = 'Same shape model. Weekly change is not a supported claim.';

export type BodyFamily = 'adult-male' | 'adult-female';
export type Distribution = 'central' | 'peripheral' | 'mixed';
export type MuscleSource = 'skeletal-muscle' | 'lean-soft-tissue' | 'fat-free-mass-minus-bone';

export interface FamilyGate {
  ageYears: readonly [number, number];
  heightM: readonly [number, number];
  bodyMassKg: readonly [number, number];
  bodyFatPercent: readonly [number, number];
  fatMassIndex: readonly [number, number];
  skeletalMuscleIndex: readonly [number, number];
  leanSoftTissueIndex: readonly [number, number];
}

/** Engineering abstention limits. Not population norms, targets, or a licensed scan corpus. */
export const families: Record<BodyFamily, FamilyGate> = {
  'adult-male': {
    ageYears: [18, 80],
    heightM: [1.5, 2.1],
    bodyMassKg: [45, 180],
    bodyFatPercent: [5, 45],
    fatMassIndex: [1, 18],
    skeletalMuscleIndex: [6, 14],
    leanSoftTissueIndex: [12, 26],
  },
  'adult-female': {
    ageYears: [18, 80],
    heightM: [1.4, 2],
    bodyMassKg: [40, 160],
    bodyFatPercent: [12, 55],
    fatMassIndex: [2, 22],
    skeletalMuscleIndex: [4, 11],
    leanSoftTissueIndex: [10, 22],
  },
};

export const tolerances = {
  massBalanceKg: 0.3,
  bodyFatPercentagePoints: 0.15,
  leanBalanceKg: 0.3,
  skeletalMuscleAboveLeanKg: 0.3,
};

/**
 * Promotion gates. Declared before the corpus and before evaluate().
 * Synthetic rows cannot satisfy a consented-human gate.
 */
export const thresholds = {
  declaredBeforeEvaluation: true,
  personalizedShapeEstimate: {
    minConsentedOrLicensedSubjectsPerSex: 30,
    abstentionOnUnsupported: 1,
    ffmiUsedAsShapeInput: 0,
  },
  calibratedCompositionAppearance: {
    evidenceClass: 'consented-human' as const,
    minHeldOutSubjectsPerSex: 30,
    compositionMaePercentagePoints: 2,
    sameDayShapeDriftMax: 0.05,
    dxaDeviceSoftwareAndDateRequired: true,
  },
  longitudinalInterpretation: {
    evidenceClass: 'consented-human' as const,
    minWithinPersonWeeklyPairs: 20,
    weeklyIntervalDays: [5, 9] as const,
    /** A study longer than one week cannot be sliced into a weekly-sensitivity claim. */
    maxStudySpanDays: 9,
    crossSectionalPairsCount: false,
    identicalModelVersionRequired: true,
    longitudinalMaePercentagePoints: 1,
  },
};

export interface Observation {
  id: string;
  subjectId: string;
  observedOn: string;
  split: 'training' | 'held-out';
  family: BodyFamily | 'unspecified';
  ageYears: number;
  heightM: number | null;
  bodyMassKg: number | null;
  bodyFatPercent: number | null;
  fatMassKg: number | null;
  fatFreeMassKg: number | null;
  leanSoftTissueKg: number | null;
  skeletalMuscleKg: number | null;
  boneMineralKg: number | null;
  /** Ignored when present. Kept so callers cannot quietly feed it in. */
  ffmi: number | null;
  distribution: Distribution | null;
  frame: number | null;
  method: 'dxa' | 'self-report' | 'unavailable';
  dxaDevice: string | null;
  dxaSoftware: string | null;
  dxaStudyDate: string | null;
  modelVersion: string;
}

export interface ShapeParameters {
  adiposity: number | null;
  muscularity: number | null;
  frame: number | null;
  distribution: Distribution | null;
}

export interface ShapeDecision {
  status: 'estimated' | 'partial' | 'abstained';
  parameters: ShapeParameters;
  muscleSource: MuscleSource | null;
  skeletalMuscleKg: number | null;
  leanSoftTissueKg: number | null;
  fatFreeMassKg: number | null;
  ffmiIgnored: boolean;
  derivedFfmi: number | null;
  uncertainty: number | null;
  provenanceComplete: boolean;
  dxaComparabilityKey: string | null;
  reasons: string[];
}

export interface CaptureFixture {
  id: string;
  factor:
    | 'repeat'
    | 'angle'
    | 'distance'
    | 'mirror'
    | 'posture'
    | 'lighting'
    | 'clothing'
    | 'phone-occlusion';
  alignmentResidual: number;
  shape: { adiposity: number; muscularity: number; frame: number };
}

export interface ChangePair {
  id: string;
  kind: 'cross-sectional' | 'within-person';
  evidenceClass: 'synthetic-regression' | 'consented-human';
  intervalDays: number;
  studySpanDays: number;
  sameModel: boolean;
  sameDexa: boolean;
}

const blank = (
  partial: Partial<Observation> & Pick<Observation, 'id' | 'subjectId' | 'split' | 'family'>,
): Observation => ({
  observedOn: '2026-04-01',
  ageYears: 30,
  heightM: 1.8,
  bodyMassKg: 80,
  bodyFatPercent: 20,
  fatMassKg: 16,
  fatFreeMassKg: 64,
  leanSoftTissueKg: 60.8,
  skeletalMuscleKg: 32,
  boneMineralKg: 3.2,
  ffmi: null,
  distribution: 'mixed',
  frame: null,
  method: 'dxa',
  dxaDevice: 'synthetic-dxa',
  dxaSoftware: 'synthetic-software',
  dxaStudyDate: '2026-04-01',
  modelVersion: MODEL_VERSION,
  ...partial,
});

/** Fixed synthetic regression corpus. No photos and no personal health values. */
export const corpus = {
  population: 'synthetic-regression' as const,
  referenceLicense: 'none-bundled' as const,
  consentedOrLicensedPairedScans: 0,
  limitations: [
    'No consented or licensed paired scan and composition corpus is bundled.',
    '3DBODY.TECH 2026 abstract 2661 is male-only CGI stimulus work, not a clinical mapping.',
    '3DBODY.TECH 2026 paper 2629 uses standardized capture on a small population over months, not weekly phone photos.',
    'DXA results stay tied to source, device, software, and study date. They are not interchangeable.',
    'Synthetic fixtures exercise the evaluator. They do not validate a person.',
  ],
  observations: [
    blank({ id: 'T1', subjectId: 'T1', split: 'training', family: 'adult-male' }),
    blank({
      id: 'T2',
      subjectId: 'T2',
      split: 'training',
      family: 'adult-female',
      ageYears: 28,
      heightM: 1.65,
      bodyMassKg: 62,
      bodyFatPercent: 29,
      fatMassKg: 18,
      fatFreeMassKg: 44,
      leanSoftTissueKg: 41.5,
      skeletalMuscleKg: 20,
      boneMineralKg: 2.5,
      distribution: 'peripheral',
    }),
    blank({ id: 'H1', subjectId: 'H1', split: 'held-out', family: 'adult-male' }),
    blank({
      id: 'H2',
      subjectId: 'H2',
      split: 'held-out',
      family: 'adult-female',
      heightM: 1.62,
      bodyMassKg: 70,
      bodyFatPercent: 32,
      fatMassKg: 22.4,
      fatFreeMassKg: 47.6,
      leanSoftTissueKg: 45,
      skeletalMuscleKg: 21,
      boneMineralKg: 2.6,
    }),
    blank({
      id: 'H3',
      subjectId: 'H3',
      split: 'held-out',
      family: 'adult-male',
      bodyFatPercent: 60,
      fatMassKg: 48,
      fatFreeMassKg: 32,
      leanSoftTissueKg: 29,
      skeletalMuscleKg: 16,
      boneMineralKg: 3,
    }),
    blank({
      id: 'H4',
      subjectId: 'H4',
      split: 'held-out',
      family: 'adult-male',
      fatMassKg: null,
      fatFreeMassKg: null,
      leanSoftTissueKg: null,
      skeletalMuscleKg: null,
      boneMineralKg: null,
      distribution: null,
      frame: null,
    }),
    blank({
      id: 'H5',
      subjectId: 'H5',
      split: 'held-out',
      family: 'adult-male',
      fatMassKg: 16,
      fatFreeMassKg: 50,
    }),
    blank({
      id: 'H6',
      subjectId: 'H6',
      split: 'held-out',
      family: 'adult-male',
      ageYears: 16,
    }),
    blank({
      id: 'H7',
      subjectId: 'H7',
      split: 'held-out',
      family: 'adult-male',
      ffmi: 99,
    }),
    blank({
      id: 'H8',
      subjectId: 'H8',
      split: 'held-out',
      family: 'adult-female',
      heightM: 1.7,
      bodyMassKg: 65,
      bodyFatPercent: 30,
      fatMassKg: 19.5,
      fatFreeMassKg: 45.5,
      leanSoftTissueKg: 43,
      skeletalMuscleKg: 20,
      boneMineralKg: 2.5,
      dxaDevice: null,
      dxaSoftware: null,
      dxaStudyDate: null,
    }),
  ],
  captures: [
    {
      id: 'C-repeat-a',
      factor: 'repeat',
      alignmentResidual: 0.4,
      shape: { adiposity: 0.5, muscularity: 0.4, frame: 0.5 },
    },
    {
      id: 'C-repeat-b',
      factor: 'repeat',
      alignmentResidual: 0.45,
      shape: { adiposity: 0.505, muscularity: 0.4, frame: 0.5 },
    },
    {
      id: 'C-angle',
      factor: 'angle',
      alignmentResidual: 1.2,
      shape: { adiposity: 0.53, muscularity: 0.4, frame: 0.5 },
    },
    {
      id: 'C-distance',
      factor: 'distance',
      alignmentResidual: 0.8,
      shape: { adiposity: 0.5, muscularity: 0.44, frame: 0.5 },
    },
    {
      id: 'C-mirror',
      factor: 'mirror',
      alignmentResidual: 0.5,
      shape: { adiposity: 0.51, muscularity: 0.4, frame: 0.48 },
    },
    {
      id: 'C-posture',
      factor: 'posture',
      alignmentResidual: 2,
      shape: { adiposity: 0.62, muscularity: 0.4, frame: 0.5 },
    },
    {
      id: 'C-lighting',
      factor: 'lighting',
      alignmentResidual: 0.3,
      shape: { adiposity: 0.5, muscularity: 0.4, frame: 0.5 },
    },
    {
      id: 'C-clothing',
      factor: 'clothing',
      alignmentResidual: 1.1,
      shape: { adiposity: 0.55, muscularity: 0.47, frame: 0.5 },
    },
    {
      id: 'C-phone',
      factor: 'phone-occlusion',
      alignmentResidual: 3,
      shape: { adiposity: 0.5, muscularity: 0.4, frame: 0.7 },
    },
  ] satisfies CaptureFixture[],
  changePairs: [
    {
      id: 'X1',
      kind: 'cross-sectional',
      evidenceClass: 'synthetic-regression',
      intervalDays: 0,
      studySpanDays: 0,
      sameModel: true,
      sameDexa: true,
    },
    {
      id: 'L1',
      kind: 'within-person',
      evidenceClass: 'synthetic-regression',
      intervalDays: 151,
      studySpanDays: 151,
      sameModel: true,
      sameDexa: true,
    },
    {
      id: 'W1',
      kind: 'within-person',
      evidenceClass: 'synthetic-regression',
      intervalDays: 7,
      studySpanDays: 7,
      sameModel: true,
      sameDexa: true,
    },
    {
      id: 'W2-sliced-from-long-study',
      kind: 'within-person',
      evidenceClass: 'synthetic-regression',
      intervalDays: 7,
      studySpanDays: 151,
      sameModel: true,
      sameDexa: true,
    },
  ] satisfies ChangePair[],
  independentComposition: {
    family: 'adult-male' as const,
    adiposity: 0.2,
    bodyMassKg: 80,
    heightM: 1.8,
    referenceBodyFatPercent: 25,
  },
  modelUpdate: {
    fromVersion: MODEL_VERSION,
    toVersion: '1.1.0',
    fromAdiposity: 0.42,
    toAdiposity: 0.3,
  },
};

export function wireframeClaim(presentation: string | null | undefined) {
  const body = presentation === 'female' ? 'female' : 'male';
  return `Illustrative ${body} wireframe. Not a body-fat percentage.`;
}

export function figureClaim(sexTitle: string) {
  return `Illustrative ${sexTitle.toLowerCase()} figure. Not a body-fat percentage.`;
}

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
  const finiteFields = [
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

const mean = (values: number[]) => values.reduce((sum, value) => sum + value, 0) / values.length;

function deepFreeze<T>(value: T): T {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value as Record<string, unknown>).forEach((entry) => deepFreeze(entry));
    Object.freeze(value);
  }
  return value;
}

deepFreeze(families);
deepFreeze(tolerances);
deepFreeze(thresholds);
deepFreeze(corpus);

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
