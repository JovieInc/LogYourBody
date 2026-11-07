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

export function wireframeClaim(presentation: string | null | undefined) {
  const body = presentation === 'female' ? 'female' : 'male';
  return `Illustrative ${body} wireframe. Not a body-fat percentage.`;
}

export function figureClaim(sexTitle: string) {
  return `Illustrative ${sexTitle.toLowerCase()} figure. Not a body-fat percentage.`;
}

export function deepFreeze<T>(value: T): T {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value as Record<string, unknown>).forEach((entry) => deepFreeze(entry));
    Object.freeze(value);
  }
  return value;
}

deepFreeze(families);
deepFreeze(tolerances);
deepFreeze(thresholds);
