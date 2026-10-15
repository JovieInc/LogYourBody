export const TRAINING_CONSENT_VERSION = 'hypertrophy-coach-v1';
export const MESOCYCLE_WEEKS = 4;

export const MUSCLE_GROUPS = [
  'chest',
  'back',
  'shoulders',
  'biceps',
  'triceps',
  'quads',
  'hamstrings',
  'glutes',
  'calves',
  'core',
] as const;

export type MuscleGroup = (typeof MUSCLE_GROUPS)[number];
export type Equipment = 'dumbbells' | 'full_gym';
export type ExercisePattern = 'A' | 'B';
export type ProgressionAction = 'hold' | 'add_reps' | 'increase_load';

export type MesoBlock = {
  id: string;
  startDate: string;
  weekCount: typeof MESOCYCLE_WEEKS;
  currentWeek: number;
  targetRir: number;
};

export type Microcycle = {
  week: number;
  sessions: Session[];
  plannedFractionalVolume: Record<MuscleGroup, number>;
};

export type MuscleContribution = Partial<Record<MuscleGroup, number>>;

export type ExercisePrescription = {
  id: string;
  name: string;
  primaryMuscle: MuscleGroup;
  muscleContribution: MuscleContribution;
  sets: number;
  repRange: { min: number; max: number };
  targetReps: number;
  targetRir: number;
  targetLoadKg: number | null;
  loadInstruction: string | null;
  progression: ProgressionAction;
  evidenceIds: string[];
  substitutions: ExerciseSubstitution[];
};

/** Engine-approved alternatives for this session. A substitution deliberately
 * carries no working load: an unfamiliar movement must be established by the user. */
export type ExerciseSubstitution = Omit<
  ExercisePrescription,
  'substitutions' | 'targetLoadKg' | 'progression'
> & {
  targetLoadKg: null;
  progression: 'hold';
};

export type WorkoutSessionEvent = {
  id: string;
  kind:
    'reordered' | 'substituted' | 'shortened' | 'skipped' | 'paused' | 'resumed' | 'ended' | 'pain';
  createdAt: string;
  exerciseId?: string;
  replacementExerciseId?: string;
  minutes?: number;
};

export type Session = {
  id: string;
  week: number;
  slot: number;
  pattern: ExercisePattern;
  title: string;
  exercises: ExercisePrescription[];
  safetyStop: boolean;
  explanation: string | null;
  evidenceIds: string[];
  executionRevision: number;
  executionPaused: boolean;
  executionEvents: WorkoutSessionEvent[];
};

export type SetLog = {
  id: string;
  sessionId: string;
  exerciseId: string;
  setNumber: number;
  reps: number;
  loadKg: number | null;
  rir: number;
  completedAt: string;
  revision?: number;
  corrections?: Array<{
    id: string;
    correctedAt: string;
    previous: Pick<SetLog, 'reps' | 'loadKg' | 'rir'>;
  }>;
};

export type DeloadState = {
  action: 'none' | 'reduce_volume' | 'pause_session';
  explanation: string;
  evidenceIds: string[];
};

export type ReadinessState = 'ready' | 'limited' | 'unknown';
export type TrainingFeedbackSource = 'touch' | 'voice' | 'text' | 'import' | 'unknown';
export type TrainingPerformance = 'up' | 'stable' | 'down';

export type MuscleFeedbackObservation = {
  soreness?: number;
  recovery?: ReadinessState;
  pump?: number;
  workload?: 'below_expected' | 'as_expected' | 'above_expected';
  performance?: TrainingPerformance;
};

export type SupportingReadinessObservation = {
  grip?: ReadinessState;
  trunk?: ReadinessState;
  muscles?: Partial<Record<MuscleGroup, ReadinessState>>;
};

export type TrainingSetContext = {
  exerciseId?: string;
  setId?: string;
  setNumber?: number;
  setOrder?: number;
  reps?: number;
  loadKg?: number | null;
  rir?: number;
  restSeconds?: number;
  setup?: string;
  rangeOfMotion?: 'full' | 'partial' | 'unknown';
  setFormat?: 'straight';
};

export type TrainingObservationInterpretation = {
  claim:
    | 'goal_preference'
    | 'self_assessed_development'
    | 'performance'
    | 'tolerability'
    | 'symptom'
    | 'recovery'
    | 'pump'
    | 'causal_hypothesis'
    | 'dose_history';
  timeframe: 'current' | 'historical';
  confidence: 'low' | 'moderate' | 'high';
  corroboratesObservationIds?: string[];
  conflictsWithObservationIds?: string[];
  proposedExplanation?: string;
};

export type NextSetRecommendation = {
  scope: 'between_set';
  action: 'proceed' | 'extend_rest' | 'adjust_or_skip_task' | 'clarify' | 'symptom_safety';
  reasons: string[];
  uncertainty: 'low' | 'moderate' | 'high';
  observationIds: string[];
  /** Immediate protection never rewrites the weekly plan or certifies safety. */
  weeklyPlanChanged: false;
  safetyCertified: false;
};

export type TrainingProgramSetup = {
  id: string;
  consentVersion: typeof TRAINING_CONSENT_VERSION;
  adultConfirmed: true;
  safetyConfirmed: true;
  sessionsPerWeek: 2 | 3;
  equipment: Equipment;
  startedAt: string;
  programRevisionId?: string;
  programPolicyVersion?: string;
};

export type TrainingFeedback = {
  id: string;
  sessionId: string;
  /** Legacy session-level fallback. Missing values are unknown. */
  soreness?: number;
  pump?: number;
  performance?: TrainingPerformance;
  jointPain?: number;
  muscles?: Partial<Record<MuscleGroup, MuscleFeedbackObservation>>;
  targetMuscle?: MuscleGroup;
  targetMuscleReadiness?: ReadinessState;
  breathingReadiness?: ReadinessState;
  generalReadiness?: ReadinessState;
  supportingReadiness?: SupportingReadinessObservation;
  trunkFatigue?: number;
  generalExhaustion?: number;
  symptomFlags?: Array<'pain' | 'neurologic' | 'other_concerning'>;
  symptomNote?: string;
  /** Original user wording is retained separately from claim-specific interpretations. */
  originalStatement?: string;
  transcriptionUncertain?: boolean;
  interpretations?: TrainingObservationInterpretation[];
  source?: TrainingFeedbackSource;
  observedAt?: string;
  /** Stable upstream identity so imports and summaries do not create corroboration. */
  sourceObservationId?: string;
  /** Append-only link to the observation this record corrects. */
  correctsObservationId?: string;
  context?: TrainingSetContext;
  createdAt: string;
};

export type VolumeLandmark = {
  entryRange: { min: number; max: number };
  detectableChangeReference: number;
  highVolumeCaution: number;
  evidenceIds: string[];
};
