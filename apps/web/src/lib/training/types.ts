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
  targetLoadKg: null;
  loadInstruction: string | null;
  progression: ProgressionAction;
  evidenceIds: string[];
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
};

export type DeloadState = {
  action: 'none' | 'reduce_volume' | 'pause_session';
  explanation: string;
  evidenceIds: string[];
};

export type TrainingProgramSetup = {
  id: string;
  consentVersion: typeof TRAINING_CONSENT_VERSION;
  adultConfirmed: true;
  safetyConfirmed: true;
  sessionsPerWeek: 2 | 3;
  equipment: Equipment;
  startedAt: string;
};

export type TrainingFeedback = {
  id: string;
  sessionId: string;
  soreness: number;
  pump: number;
  performance: 'up' | 'stable' | 'down';
  jointPain: number;
  createdAt: string;
};

export type VolumeLandmark = {
  entryRange: { min: number; max: number };
  detectableChangeReference: number;
  highVolumeCaution: number;
  evidenceIds: string[];
};
