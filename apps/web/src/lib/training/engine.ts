import { cycleConfigurationSchema } from './revision-contract';
import {
  MESOCYCLE_WEEKS,
  MUSCLE_GROUPS,
  type DeloadState,
  type CycleLength,
  type Equipment,
  type ExercisePattern,
  type ExercisePrescription,
  type ExerciseSubstitution,
  type Microcycle,
  type MesoBlock,
  type MuscleContribution,
  type MuscleGroup,
  type NextSetRecommendation,
  type ReadinessState,
  type Session,
  type SetLog,
  type TrainingFeedback,
  type TrainingProgramSetup,
  type VolumeLandmark,
} from './types';

const VOLUME_EVIDENCE = ['k:81c218db', 'k:248d8110', 'k:ed46b889', 'k:2aee9d0c'];
const EFFORT_EVIDENCE = ['k:1795aef0', 'k:220190f8', 'k:053f531a'];
const LOAD_EVIDENCE = ['k:88ea9e15', 'k:a6ae7fd4'];
const RECOVERY_EVIDENCE = ['k:76bf778c', 'k:b1e1dc5b', 'k:e95f2199'];
const BETWEEN_SET_OBSERVATION_MAX_AGE_MS = 30 * 60 * 1000;

export const volume_landmarks: Record<MuscleGroup, VolumeLandmark> = Object.fromEntries(
  MUSCLE_GROUPS.map((muscle) => [
    muscle,
    {
      entryRange: { min: 1, max: 3 },
      detectableChangeReference: 4,
      highVolumeCaution: 20,
      evidenceIds: VOLUME_EVIDENCE,
    },
  ]),
) as Record<MuscleGroup, VolumeLandmark>;

const emptyVolume = (): Record<MuscleGroup, number> =>
  Object.fromEntries(MUSCLE_GROUPS.map((muscle) => [muscle, 0])) as Record<MuscleGroup, number>;

type ExerciseSeed = {
  id: string;
  name: string;
  primaryMuscle: MuscleGroup;
  muscleContribution: MuscleContribution;
};

const EXERCISES: Record<Equipment, Record<ExercisePattern, ExerciseSeed[]>> = {
  dumbbells: {
    A: [
      {
        id: 'goblet_squat',
        name: 'Goblet squat',
        primaryMuscle: 'quads',
        muscleContribution: { quads: 1, glutes: 0.5 },
      },
      {
        id: 'dumbbell_floor_press',
        name: 'Dumbbell floor press',
        primaryMuscle: 'chest',
        muscleContribution: { chest: 1, triceps: 0.5, shoulders: 0.5 },
      },
      {
        id: 'one_arm_dumbbell_row',
        name: 'One-arm dumbbell row',
        primaryMuscle: 'back',
        muscleContribution: { back: 1, biceps: 0.5 },
      },
      {
        id: 'dumbbell_romanian_deadlift',
        name: 'Dumbbell Romanian deadlift',
        primaryMuscle: 'hamstrings',
        muscleContribution: { hamstrings: 1, glutes: 0.5 },
      },
      {
        id: 'dumbbell_lateral_raise',
        name: 'Dumbbell lateral raise',
        primaryMuscle: 'shoulders',
        muscleContribution: { shoulders: 1 },
      },
      {
        id: 'dumbbell_curl',
        name: 'Dumbbell curl',
        primaryMuscle: 'biceps',
        muscleContribution: { biceps: 1 },
      },
      {
        id: 'standing_calf_raise',
        name: 'Standing calf raise',
        primaryMuscle: 'calves',
        muscleContribution: { calves: 1 },
      },
      { id: 'dead_bug', name: 'Dead bug', primaryMuscle: 'core', muscleContribution: { core: 1 } },
    ],
    B: [
      {
        id: 'dumbbell_split_squat',
        name: 'Dumbbell split squat',
        primaryMuscle: 'quads',
        muscleContribution: { quads: 1, glutes: 0.5 },
      },
      {
        id: 'incline_dumbbell_press',
        name: 'Incline dumbbell press',
        primaryMuscle: 'chest',
        muscleContribution: { chest: 1, triceps: 0.5, shoulders: 0.5 },
      },
      {
        id: 'chest_supported_dumbbell_row',
        name: 'Chest-supported dumbbell row',
        primaryMuscle: 'back',
        muscleContribution: { back: 1, biceps: 0.5 },
      },
      {
        id: 'dumbbell_hip_thrust',
        name: 'Dumbbell hip thrust',
        primaryMuscle: 'glutes',
        muscleContribution: { glutes: 1, hamstrings: 0.25 },
      },
      {
        id: 'overhead_dumbbell_triceps_extension',
        name: 'Overhead dumbbell triceps extension',
        primaryMuscle: 'triceps',
        muscleContribution: { triceps: 1 },
      },
      {
        id: 'single_leg_calf_raise',
        name: 'Single-leg calf raise',
        primaryMuscle: 'calves',
        muscleContribution: { calves: 1 },
      },
      { id: 'bird_dog', name: 'Bird dog', primaryMuscle: 'core', muscleContribution: { core: 1 } },
    ],
  },
  full_gym: {
    A: [
      {
        id: 'leg_press',
        name: 'Leg press',
        primaryMuscle: 'quads',
        muscleContribution: { quads: 1, glutes: 0.5 },
      },
      {
        id: 'machine_chest_press',
        name: 'Machine chest press',
        primaryMuscle: 'chest',
        muscleContribution: { chest: 1, triceps: 0.5, shoulders: 0.5 },
      },
      {
        id: 'seated_cable_row',
        name: 'Seated cable row',
        primaryMuscle: 'back',
        muscleContribution: { back: 1, biceps: 0.5 },
      },
      {
        id: 'barbell_romanian_deadlift',
        name: 'Romanian deadlift',
        primaryMuscle: 'hamstrings',
        muscleContribution: { hamstrings: 1, glutes: 0.5 },
      },
      {
        id: 'cable_lateral_raise',
        name: 'Cable lateral raise',
        primaryMuscle: 'shoulders',
        muscleContribution: { shoulders: 1 },
      },
      {
        id: 'cable_curl',
        name: 'Cable curl',
        primaryMuscle: 'biceps',
        muscleContribution: { biceps: 1 },
      },
      {
        id: 'standing_calf_raise',
        name: 'Standing calf raise',
        primaryMuscle: 'calves',
        muscleContribution: { calves: 1 },
      },
      { id: 'dead_bug', name: 'Dead bug', primaryMuscle: 'core', muscleContribution: { core: 1 } },
    ],
    B: [
      {
        id: 'split_squat',
        name: 'Split squat',
        primaryMuscle: 'quads',
        muscleContribution: { quads: 1, glutes: 0.5 },
      },
      {
        id: 'incline_machine_press',
        name: 'Incline machine press',
        primaryMuscle: 'chest',
        muscleContribution: { chest: 1, triceps: 0.5, shoulders: 0.5 },
      },
      {
        id: 'lat_pulldown',
        name: 'Lat pulldown',
        primaryMuscle: 'back',
        muscleContribution: { back: 1, biceps: 0.5 },
      },
      {
        id: 'hip_thrust',
        name: 'Hip thrust',
        primaryMuscle: 'glutes',
        muscleContribution: { glutes: 1, hamstrings: 0.25 },
      },
      {
        id: 'cable_triceps_pressdown',
        name: 'Cable triceps pressdown',
        primaryMuscle: 'triceps',
        muscleContribution: { triceps: 1 },
      },
      {
        id: 'seated_calf_raise',
        name: 'Seated calf raise',
        primaryMuscle: 'calves',
        muscleContribution: { calves: 1 },
      },
      { id: 'bird_dog', name: 'Bird dog', primaryMuscle: 'core', muscleContribution: { core: 1 } },
    ],
  },
};

const RIR_LADDER = [4, 3, 3, 2] as const;
// Bounded engine policy, not a claim that one block length is optimal for everyone.
export const CYCLE_RIR_LADDERS: Record<CycleLength, readonly number[]> = {
  4: [4, 3, 2, 5],
  5: [4, 3, 3, 2, 5],
  6: [4, 4, 3, 3, 2, 5],
};

export function configuredMesoBlock(
  startDate: string,
  weekCount: CycleLength,
  completedSessions: number,
  sessionsPerWeek: number,
): MesoBlock {
  const currentWeek = Math.min(weekCount, Math.floor(completedSessions / sessionsPerWeek) + 1);
  return {
    id: 'block-1',
    startDate,
    weekCount,
    currentWeek,
    targetRir: CYCLE_RIR_LADDERS[weekCount][currentWeek - 1]!,
    phase:
      completedSessions >= weekCount * sessionsPerWeek
        ? 'review'
        : currentWeek === weekCount
          ? 'planned_deload'
          : currentWeek === 1
            ? 'accumulation'
            : 'adjustment',
  };
}

/** Completion of the remaining execution work is distinct from completed training. */
export function sessionWorkLogged(
  session: Session,
  logs: Array<Pick<SetLog, 'sessionId' | 'exerciseId' | 'setNumber'>>,
): boolean {
  return (
    !session.safetyStop &&
    session.exercises.length > 0 &&
    session.exercises.every((exercise) =>
      Array.from({ length: exercise.sets }, (_, i) => i + 1).every((setNumber) =>
        logs.some(
          (log) =>
            log.sessionId === session.id &&
            log.exerciseId === exercise.id &&
            log.setNumber === setNumber,
        ),
      ),
    )
  );
}

/** A terminal action, empty prescription or skipped work is never completed training. */
export function completedTrainingSession(
  session: Session,
  logs: Array<Pick<SetLog, 'sessionId' | 'exerciseId' | 'setNumber'>>,
): boolean {
  return (
    sessionWorkLogged(session, logs) &&
    !session.executionEvents?.some(
      (event) => event.kind === 'skipped' || event.kind === 'shortened',
    )
  );
}
const REP_RANGE = { min: 8, max: 12 } as const;

function eligibleSubstitutions(input: {
  seed: ExerciseSeed;
  equipment: Equipment;
  pattern: ExercisePattern;
  sets: number;
  targetRir: number;
}): ExerciseSubstitution[] {
  const pools =
    input.equipment === 'full_gym'
      ? [EXERCISES.full_gym.A, EXERCISES.full_gym.B, EXERCISES.dumbbells.A, EXERCISES.dumbbells.B]
      : [EXERCISES.dumbbells.A, EXERCISES.dumbbells.B];
  const plannedIds = new Set(EXERCISES[input.equipment][input.pattern].map((item) => item.id));
  const seen = new Set<string>();
  return pools
    .flat()
    .filter((candidate) => {
      if (
        candidate.id === input.seed.id ||
        candidate.primaryMuscle !== input.seed.primaryMuscle ||
        plannedIds.has(candidate.id) ||
        seen.has(candidate.id)
      )
        return false;
      seen.add(candidate.id);
      return true;
    })
    .map((candidate) => ({
      ...candidate,
      sets: input.sets,
      repRange: REP_RANGE,
      targetReps: REP_RANGE.min,
      targetRir: input.targetRir,
      targetLoadKg: null,
      loadInstruction: 'Choose a conservative starting load for this unfamiliar alternative.',
      progression: 'hold' as const,
      evidenceIds: EFFORT_EVIDENCE,
    }));
}

/** Re-validates a stored alternative at the execution boundary. Session data is
 * durable and may predate the current library, so presence in a persisted
 * `substitutions` array is not sufficient authorization to prescribe it. */
export function isEligibleExerciseSubstitution(input: {
  exercise: ExercisePrescription;
  candidate: ExerciseSubstitution;
  equipment: Equipment;
}): boolean {
  const allowedPools =
    input.equipment === 'full_gym'
      ? [EXERCISES.full_gym.A, EXERCISES.full_gym.B, EXERCISES.dumbbells.A, EXERCISES.dumbbells.B]
      : [EXERCISES.dumbbells.A, EXERCISES.dumbbells.B];
  const canonical = allowedPools
    .flat()
    .find(
      (seed) =>
        seed.id === input.candidate.id && seed.primaryMuscle === input.exercise.primaryMuscle,
    );
  const canonicalContributions = canonical ? Object.entries(canonical.muscleContribution) : [];
  const candidateContributions = Object.entries(input.candidate.muscleContribution);
  return Boolean(
    canonical &&
    canonical.id !== input.exercise.id &&
    canonical.name === input.candidate.name &&
    input.candidate.primaryMuscle === input.exercise.primaryMuscle &&
    canonicalContributions.length === candidateContributions.length &&
    canonicalContributions.every(
      ([muscle, contribution]) =>
        input.candidate.muscleContribution[muscle as MuscleGroup] === contribution,
    ) &&
    input.candidate.repRange.min === REP_RANGE.min &&
    input.candidate.repRange.max === REP_RANGE.max &&
    input.candidate.targetReps === REP_RANGE.min &&
    input.candidate.targetRir === input.exercise.targetRir &&
    input.candidate.targetLoadKg === null &&
    input.candidate.progression === 'hold' &&
    input.candidate.loadInstruction ===
      'Choose a conservative starting load for this unfamiliar alternative.',
  );
}

export function createMesoBlock(startDate: string, today: string): MesoBlock {
  const start = Date.parse(startDate);
  const current = Date.parse(today);
  const elapsedWeeks = Math.max(0, Math.floor((current - start) / (7 * 24 * 60 * 60 * 1000)));
  const currentWeek = (elapsedWeeks % MESOCYCLE_WEEKS) + 1;
  return {
    id: `block-${Math.floor(elapsedWeeks / MESOCYCLE_WEEKS) + 1}`,
    startDate,
    weekCount: MESOCYCLE_WEEKS,
    currentWeek,
    targetRir: RIR_LADDER[currentWeek - 1] ?? RIR_LADDER[0],
  };
}

function observationPayload(observation: TrainingFeedback) {
  return {
    soreness: observation.soreness,
    pump: observation.pump,
    performance: observation.performance,
    jointPain: observation.jointPain,
    muscles: MUSCLE_GROUPS.map((muscle) => [muscle, observation.muscles?.[muscle]]),
    targetMuscle: observation.targetMuscle,
    targetMuscleReadiness: observation.targetMuscleReadiness,
    breathingReadiness: observation.breathingReadiness,
    generalReadiness: observation.generalReadiness,
    supportingReadiness: observation.supportingReadiness
      ? {
          grip: observation.supportingReadiness.grip,
          trunk: observation.supportingReadiness.trunk,
          muscles: MUSCLE_GROUPS.map((muscle) => [
            muscle,
            observation.supportingReadiness?.muscles?.[muscle],
          ]),
        }
      : undefined,
    trunkFatigue: observation.trunkFatigue,
    generalExhaustion: observation.generalExhaustion,
    symptomFlags: observation.symptomFlags ? [...observation.symptomFlags].sort() : undefined,
    symptomNote: observation.symptomNote,
    originalStatement: observation.originalStatement,
    transcriptionUncertain: observation.transcriptionUncertain,
    interpretations: observation.interpretations,
    context: observation.context,
  };
}

export function sameTrainingFeedbackObservation(
  left: TrainingFeedback,
  right: TrainingFeedback,
): boolean {
  return JSON.stringify(observationPayload(left)) === JSON.stringify(observationPayload(right));
}

function effectiveTrainingFeedback(feedback: TrainingFeedback[]): TrainingFeedback[] {
  const corrected = new Set(
    feedback
      .map((item) => item.correctsObservationId)
      .filter((id): id is string => typeof id === 'string'),
  );
  const sourceObservations = new Set<string>();
  return [...feedback]
    .sort(
      (a, b) =>
        Date.parse(b.createdAt) - Date.parse(a.createdAt) ||
        (b.jointPain ?? 0) - (a.jointPain ?? 0) ||
        a.id.localeCompare(b.id),
    )
    .filter((item) => {
      if (corrected.has(item.id)) return false;
      if (!item.sourceObservationId) return true;
      if (sourceObservations.has(item.sourceObservationId)) return false;
      sourceObservations.add(item.sourceObservationId);
      return true;
    });
}

/** Retries, imports and later corrections from one session are one evidence unit.
 * Equal-time pain reports take precedence because their recency cannot be distinguished.
 */
export function latestFeedbackPerSession(feedback: TrainingFeedback[]): TrainingFeedback[] {
  const seen = new Set<string>();
  return effectiveTrainingFeedback(feedback).filter((item) => {
    if (seen.has(item.sessionId)) return false;
    seen.add(item.sessionId);
    return true;
  });
}

export function hasConflictingFeedbackAtSameTime(
  observation: TrainingFeedback,
  feedback: TrainingFeedback[],
): boolean {
  return feedback.some(
    (item) =>
      item.sessionId === observation.sessionId &&
      Date.parse(item.createdAt) === Date.parse(observation.createdAt) &&
      !sameTrainingFeedbackObservation(item, observation),
  );
}

type RecoverySignal = {
  soreness?: number;
  pump?: number;
  performance?: TrainingFeedback['performance'];
  recovery?: ReadinessState;
};

function recoverySignal(
  observation: TrainingFeedback,
  muscle?: MuscleGroup,
): RecoverySignal | null {
  const scoped = muscle ? observation.muscles?.[muscle] : undefined;
  const signal = {
    soreness: scoped?.soreness ?? observation.soreness,
    pump: scoped?.pump ?? observation.pump,
    performance: scoped?.performance ?? observation.performance,
    recovery: scoped?.recovery,
  };
  return Object.values(signal).some((value) => value !== undefined) ? signal : null;
}

function recoveryFeedbackPerSession(
  feedback: TrainingFeedback[],
  muscle?: MuscleGroup,
): TrainingFeedback[] {
  return latestFeedbackPerSession(
    effectiveTrainingFeedback(feedback).filter((item) => recoverySignal(item, muscle) !== null),
  );
}

function hasConflictingRecoveryAtSameTime(
  observation: TrainingFeedback,
  feedback: TrainingFeedback[],
  muscle?: MuscleGroup,
): boolean {
  const signal = recoverySignal(observation, muscle);
  return effectiveTrainingFeedback(feedback).some(
    (item) =>
      item.id !== observation.id &&
      item.sessionId === observation.sessionId &&
      Date.parse(item.createdAt) === Date.parse(observation.createdAt) &&
      JSON.stringify(recoverySignal(item, muscle)) !== JSON.stringify(signal),
  );
}

export function evaluateDeload(feedback: TrainingFeedback[], muscle?: MuscleGroup): DeloadState {
  const painFeedback = latestFeedbackPerSession(
    feedback.filter((item) => item.jointPain !== undefined || Boolean(item.symptomFlags?.length)),
  )[0];
  const ordered = recoveryFeedbackPerSession(feedback, muscle);
  const latest = ordered[0];
  if (
    painFeedback &&
    ((painFeedback.jointPain ?? 0) >= 4 || Boolean(painFeedback.symptomFlags?.length))
  ) {
    return {
      action: 'pause_session',
      explanation:
        'A pain or concerning symptom was reported. Pause the affected exercise and follow the existing symptom-safety review pathway.',
      evidenceIds: ['k:220190f8', 'k:e95f2199'],
    };
  }
  if (!latest) {
    return {
      action: 'none',
      explanation: 'No recovery feedback has been recorded; keep the starting dose steady.',
      evidenceIds: RECOVERY_EVIDENCE,
    };
  }
  if (
    ordered.slice(0, 2).some((item) => hasConflictingRecoveryAtSameTime(item, feedback, muscle))
  ) {
    return {
      action: 'none',
      explanation:
        'Conflicting check-ins were recorded at the same time for a session, so recovery feedback cannot establish a repeated decline yet.',
      evidenceIds: RECOVERY_EVIDENCE,
    };
  }
  const latestSignal = recoverySignal(latest, muscle);
  const previousSignal = ordered[1] ? recoverySignal(ordered[1], muscle) : null;
  const sustainedDecline =
    ordered.length >= 2 &&
    latestSignal?.performance === 'down' &&
    previousSignal?.performance === 'down';
  if (sustainedDecline && (latestSignal?.soreness ?? -1) >= 7) {
    return {
      action: 'reduce_volume',
      explanation:
        muscle === undefined
          ? 'Performance has declined across two sessions while soreness is high, so this session uses one set per movement. Volume is not increased automatically.'
          : `Performance for ${muscle} has declined across two sessions while its reported soreness is high, so only ${muscle} work is reduced.`,
      evidenceIds: ['k:0b3ea5bb', 'k:76bf778c', 'k:a6ae7fd4'],
    };
  }
  return {
    action: 'none',
    explanation:
      latestSignal?.pump !== undefined && latestSignal.pump <= 2
        ? 'A low pump by itself does not change the plan; keep the current dose and review performance and recovery over time.'
        : 'No repeated performance decline or high pain signal was reported; keep the current dose steady.',
    evidenceIds: RECOVERY_EVIDENCE,
  };
}

function feedbackTime(observation: TrainingFeedback): number {
  return Date.parse(observation.observedAt ?? observation.createdAt);
}

function hasBetweenSetObservation(observation: TrainingFeedback): boolean {
  return Boolean(
    observation.targetMuscleReadiness ||
    observation.breathingReadiness ||
    observation.generalReadiness ||
    observation.supportingReadiness ||
    observation.symptomFlags?.length ||
    (observation.jointPain ?? 0) > 0,
  );
}

function readinessPayload(observation: TrainingFeedback) {
  return {
    targetMuscle: observation.targetMuscle,
    targetMuscleReadiness: observation.targetMuscleReadiness,
    breathingReadiness: observation.breathingReadiness,
    generalReadiness: observation.generalReadiness,
    supportingReadiness: observation.supportingReadiness,
    jointPain: observation.jointPain,
    symptomFlags: observation.symptomFlags ? [...observation.symptomFlags].sort() : undefined,
    symptomNote: observation.symptomNote,
  };
}

function nextSetRecommendation(
  action: NextSetRecommendation['action'],
  reasons: string[],
  uncertainty: NextSetRecommendation['uncertainty'],
  observations: TrainingFeedback[],
): NextSetRecommendation {
  return {
    scope: 'between_set',
    action,
    reasons,
    uncertainty,
    observationIds: observations.map((item) => item.id),
    weeklyPlanChanged: false,
    safetyCertified: false,
  };
}

/**
 * Interprets current set-level observations only. It does not modify the weekly plan,
 * use an elapsed timer as clearance, or turn missing data into a recovered state.
 */
export function evaluateNextSetReadiness(input: {
  feedback: TrainingFeedback[];
  sessionId: string;
  now: Date;
  timerExpired?: boolean;
}): NextSetRecommendation {
  const observations = effectiveTrainingFeedback(input.feedback).filter(
    (item) => item.sessionId === input.sessionId && hasBetweenSetObservation(item),
  );
  const symptom = observations.find(
    (item) => (item.jointPain ?? 0) >= 4 || Boolean(item.symptomFlags?.length),
  );
  if (symptom) {
    return nextSetRecommendation(
      'symptom_safety',
      ['Pause the implicated movement and follow the existing symptom-safety review pathway.'],
      'low',
      [symptom],
    );
  }
  const latest = observations[0];
  if (!latest) {
    return nextSetRecommendation(
      'clarify',
      ['No current between-set readiness observation is available; missing feedback is unknown.'],
      'high',
      [],
    );
  }
  const observedAt = feedbackTime(latest);
  if (
    !Number.isFinite(observedAt) ||
    input.now.getTime() - observedAt > BETWEEN_SET_OBSERVATION_MAX_AGE_MS ||
    observedAt - input.now.getTime() > 5 * 60 * 1000
  ) {
    return nextSetRecommendation(
      'clarify',
      [
        'The available observation is stale or has an invalid time; current readiness remains unknown.',
      ],
      'high',
      [latest],
    );
  }
  const tied = observations.filter((item) => feedbackTime(item) === observedAt);
  if (
    tied.some(
      (item) =>
        item.id !== latest.id &&
        JSON.stringify(readinessPayload(item)) !== JSON.stringify(readinessPayload(latest)),
    )
  ) {
    return nextSetRecommendation(
      'clarify',
      ['Current observations conflict, so a short consequential clarification is needed.'],
      'high',
      tied,
    );
  }
  const supporting = latest.supportingReadiness;
  const supportingStates = [
    supporting?.grip,
    supporting?.trunk,
    ...MUSCLE_GROUPS.map((muscle) => supporting?.muscles?.[muscle]),
  ].filter((state): state is ReadinessState => state !== undefined);
  if (latest.generalReadiness === 'limited') {
    return nextSetRecommendation(
      'adjust_or_skip_task',
      ['General readiness to exert is limiting despite any local muscle readiness.'],
      'moderate',
      [latest],
    );
  }
  if (latest.targetMuscleReadiness === 'limited' || supportingStates.includes('limited')) {
    return nextSetRecommendation(
      'adjust_or_skip_task',
      [
        latest.targetMuscleReadiness === 'limited'
          ? 'The target muscle is not ready for the intended productive set.'
          : 'A supporting muscle, grip, or trunk limitation changes the eligible task.',
      ],
      'moderate',
      [latest],
    );
  }
  if (latest.breathingReadiness === 'limited') {
    return nextSetRecommendation(
      'extend_rest',
      [
        'Breathing remains limiting; an elapsed timer does not establish readiness for the intended set.',
      ],
      'moderate',
      [latest],
    );
  }
  if (latest.targetMuscleReadiness === 'ready') {
    const allReportedReady =
      latest.breathingReadiness === 'ready' &&
      latest.generalReadiness === 'ready' &&
      supportingStates.length > 0 &&
      supportingStates.every((state) => state === 'ready');
    return nextSetRecommendation(
      'proceed',
      [
        'The target muscle was reported ready for the intended set, with no reported limiting condition.',
      ],
      allReportedReady ? 'low' : 'moderate',
      [latest],
    );
  }
  return nextSetRecommendation(
    'clarify',
    ['The observation does not establish target-muscle readiness for the intended set.'],
    'high',
    [latest],
  );
}

export function progressionForExercise(
  exerciseId: string,
  logs: SetLog[],
  targetRir: number,
  feedback: TrainingFeedback[] = [],
  muscle?: MuscleGroup,
): {
  action: ExercisePrescription['progression'];
  targetReps: number;
  targetLoadKg: number | null;
  loadInstruction: string | null;
} {
  const exerciseLogs = logs
    .filter((log) => log.exerciseId === exerciseId)
    .sort((a, b) => Date.parse(b.completedAt) - Date.parse(a.completedAt));
  if (exerciseLogs.length < 2)
    return { action: 'hold', targetReps: REP_RANGE.min, targetLoadKg: null, loadInstruction: null };
  const lastSession = exerciseLogs[0]?.sessionId;
  const lastSets = exerciseLogs
    .filter((log) => log.sessionId === lastSession)
    .sort((a, b) => a.setNumber - b.setNumber);
  if (lastSets.length < 2)
    return { action: 'hold', targetReps: REP_RANGE.min, targetLoadKg: null, loadInstruction: null };
  const latestRecovery = muscle ? recoveryFeedbackPerSession(feedback, muscle)[0] : undefined;
  const reportedRecovery =
    muscle && latestRecovery ? recoverySignal(latestRecovery, muscle)?.recovery : undefined;
  const carriedLoad = lastSets[lastSets.length - 1]?.loadKg ?? null;
  if (reportedRecovery === 'limited') {
    return {
      action: 'hold',
      targetReps: Math.max(REP_RANGE.min, Math.min(...lastSets.map((log) => log.reps))),
      targetLoadKg: carriedLoad,
      loadInstruction: null,
    };
  }
  const allReachedTop = lastSets.every((log) => log.reps >= REP_RANGE.max && log.rir >= targetRir);
  if (allReachedTop) {
    return {
      action: 'increase_load',
      targetReps: REP_RANGE.min,
      targetLoadKg: null,
      loadInstruction:
        'Use the next available load increment, then build repetitions within the range again.',
    };
  }
  const canAddReps = lastSets.every((log) => log.rir >= targetRir);
  const targetReps = canAddReps
    ? Math.min(
        REP_RANGE.max,
        Math.max(REP_RANGE.min, Math.min(...lastSets.map((log) => log.reps)) + 1),
      )
    : Math.max(REP_RANGE.min, Math.min(...lastSets.map((log) => log.reps)));
  // Hold or add reps at the load the final set used last session. Equipment increments
  // differ, so a load increase stays an instruction rather than a number.
  return {
    action: canAddReps ? 'add_reps' : 'hold',
    targetReps,
    targetLoadKg: carriedLoad,
    loadInstruction: null,
  };
}

export function buildSession(input: {
  setup: TrainingProgramSetup;
  block: MesoBlock;
  sessionId: string;
  slot: number;
  logs: SetLog[];
  feedback: TrainingFeedback[];
}): Session {
  const pattern: ExercisePattern = input.slot % 2 === 0 ? 'A' : 'B';
  const sessionDeload = evaluateDeload(input.feedback);
  const safetyStop = sessionDeload.action === 'pause_session';
  const plannedDeload = input.block.phase === 'planned_deload';
  const targetRir = plannedDeload ? 5 : input.block.targetRir;
  const muscleDeloads = new Map(
    MUSCLE_GROUPS.map((muscle) => [muscle, evaluateDeload(input.feedback, muscle)]),
  );
  const exercises = safetyStop
    ? []
    : EXERCISES[input.setup.equipment][pattern].map((seed) => {
        const muscleDeload = muscleDeloads.get(seed.primaryMuscle);
        const sets = plannedDeload || muscleDeload?.action === 'reduce_volume' ? 1 : 2;
        const progression = progressionForExercise(
          seed.id,
          input.logs,
          targetRir,
          input.feedback,
          seed.primaryMuscle,
        );
        return {
          id: seed.id,
          name: seed.name,
          primaryMuscle: seed.primaryMuscle,
          muscleContribution: seed.muscleContribution,
          sets,
          repRange: REP_RANGE,
          targetReps: plannedDeload ? REP_RANGE.min : progression.targetReps,
          targetRir,
          targetLoadKg: plannedDeload
            ? ([...input.logs]
                .filter((log) => log.exerciseId === seed.id)
                .sort((a, b) => Date.parse(b.completedAt) - Date.parse(a.completedAt))[0]?.loadKg ??
              null)
            : progression.targetLoadKg,
          loadInstruction: plannedDeload ? null : progression.loadInstruction,
          progression: plannedDeload ? ('hold' as const) : progression.action,
          evidenceIds: progression.action === 'increase_load' ? LOAD_EVIDENCE : EFFORT_EVIDENCE,
          substitutions: eligibleSubstitutions({
            seed,
            equipment: input.setup.equipment,
            pattern,
            sets,
            targetRir,
          }),
        };
      });
  const reducedMuscles = MUSCLE_GROUPS.filter(
    (muscle) => muscleDeloads.get(muscle)?.action === 'reduce_volume',
  );
  const explanation = safetyStop
    ? sessionDeload.explanation
    : plannedDeload
      ? 'Planned final deload: half the baseline sets and more repetitions in reserve. Reactive safety checks still apply.'
      : reducedMuscles.length > 0 && sessionDeload.action !== 'reduce_volume'
        ? `Repeated muscle-specific recovery signals reduced only ${reducedMuscles.join(', ')} work; the rest of the session stays unchanged.`
        : sessionDeload.explanation;
  return {
    id: input.sessionId,
    week: input.block.currentWeek,
    slot: input.slot,
    pattern,
    title: `Full body ${pattern}`,
    exercises,
    safetyStop,
    explanation,
    evidenceIds: [
      ...new Set([
        ...VOLUME_EVIDENCE,
        ...EFFORT_EVIDENCE,
        ...sessionDeload.evidenceIds,
        ...[...muscleDeloads.values()].flatMap((decision) => decision.evidenceIds),
      ]),
    ],
    executionRevision: 0,
    executionPaused: false,
    executionEvents: [],
  };
}

export function buildMicrocycle(input: {
  setup: TrainingProgramSetup;
  block: MesoBlock;
  sessionIds: string[];
  logs: SetLog[];
  feedback: TrainingFeedback[];
}): Microcycle {
  const sessions = input.sessionIds
    .slice(0, input.setup.sessionsPerWeek)
    .map((sessionId, slot) => buildSession({ ...input, sessionId, slot }));
  const plannedFractionalVolume = emptyVolume();
  for (const session of sessions) {
    for (const exercise of session.exercises) {
      for (const [muscle, fraction] of Object.entries(exercise.muscleContribution)) {
        plannedFractionalVolume[muscle as MuscleGroup] += exercise.sets * Number(fraction);
      }
    }
  }
  return { week: input.block.currentWeek, sessions, plannedFractionalVolume };
}

export function isProgramSetup(value: unknown): value is TrainingProgramSetup {
  if (!value || typeof value !== 'object') return false;
  const setup = value as Partial<TrainingProgramSetup>;
  return (
    setup.consentVersion === 'hypertrophy-coach-v1' &&
    setup.adultConfirmed === true &&
    setup.safetyConfirmed === true &&
    (setup.sessionsPerWeek === 2 || setup.sessionsPerWeek === 3) &&
    (setup.equipment === 'dumbbells' || setup.equipment === 'full_gym') &&
    (setup.cycle === undefined || cycleConfigurationSchema.safeParse(setup.cycle).success) &&
    typeof setup.startedAt === 'string' &&
    Number.isFinite(Date.parse(setup.startedAt))
  );
}

export function validTrainingFeedback(
  value: unknown,
): value is Omit<TrainingFeedback, 'id' | 'createdAt'> {
  if (!value || typeof value !== 'object') return false;
  const feedback = value as Partial<TrainingFeedback>;
  const validScore = (score: unknown) =>
    typeof score === 'number' && Number.isInteger(score) && score >= 0 && score <= 10;
  const validOptionalScore = (score: unknown) => score === undefined || validScore(score);
  const validPerformance = (performance: unknown) =>
    performance === 'up' || performance === 'stable' || performance === 'down';
  const validReadiness = (readiness: unknown) =>
    readiness === 'ready' || readiness === 'limited' || readiness === 'unknown';
  const validOptionalString = (text: unknown, max: number) =>
    text === undefined ||
    (typeof text === 'string' && text.trim().length > 0 && text.length <= max);
  const validMuscleObservation = (observation: unknown) => {
    if (!observation || typeof observation !== 'object' || Array.isArray(observation)) return false;
    const item = observation as NonNullable<TrainingFeedback['muscles']>[MuscleGroup];
    return (
      validOptionalScore(item?.soreness) &&
      (item?.recovery === undefined || validReadiness(item.recovery)) &&
      validOptionalScore(item?.pump) &&
      (item?.workload === undefined ||
        item.workload === 'below_expected' ||
        item.workload === 'as_expected' ||
        item.workload === 'above_expected') &&
      (item?.performance === undefined || validPerformance(item.performance)) &&
      Object.values(item ?? {}).some((entry) => entry !== undefined)
    );
  };
  const muscles = feedback.muscles;
  const validMuscles =
    muscles === undefined ||
    (!Array.isArray(muscles) &&
      Object.keys(muscles).length > 0 &&
      Object.entries(muscles).every(
        ([muscle, observation]) =>
          MUSCLE_GROUPS.includes(muscle as MuscleGroup) && validMuscleObservation(observation),
      ));
  const supporting = feedback.supportingReadiness;
  const validSupporting =
    supporting === undefined ||
    (!Array.isArray(supporting) &&
      (supporting.grip === undefined || validReadiness(supporting.grip)) &&
      (supporting.trunk === undefined || validReadiness(supporting.trunk)) &&
      (supporting.muscles === undefined ||
        (!Array.isArray(supporting.muscles) &&
          Object.keys(supporting.muscles).length > 0 &&
          Object.entries(supporting.muscles).every(
            ([muscle, readiness]) =>
              MUSCLE_GROUPS.includes(muscle as MuscleGroup) && validReadiness(readiness),
          ))) &&
      (supporting.grip !== undefined ||
        supporting.trunk !== undefined ||
        supporting.muscles !== undefined));
  const context = feedback.context;
  const validContext =
    context === undefined ||
    (!Array.isArray(context) &&
      validOptionalString(context.exerciseId, 80) &&
      validOptionalString(context.setId, 160) &&
      (context.setNumber === undefined ||
        (Number.isInteger(context.setNumber) &&
          context.setNumber >= 1 &&
          context.setNumber <= 50)) &&
      (context.setOrder === undefined ||
        (Number.isInteger(context.setOrder) && context.setOrder >= 1 && context.setOrder <= 50)) &&
      (context.reps === undefined ||
        (Number.isInteger(context.reps) && context.reps >= 0 && context.reps <= 100)) &&
      (context.loadKg === undefined ||
        context.loadKg === null ||
        (Number.isFinite(context.loadKg) && context.loadKg >= 0 && context.loadKg <= 500)) &&
      (context.rir === undefined ||
        (Number.isInteger(context.rir) && context.rir >= 0 && context.rir <= 6)) &&
      (context.restSeconds === undefined ||
        (Number.isInteger(context.restSeconds) &&
          context.restSeconds >= 0 &&
          context.restSeconds <= 3600)) &&
      validOptionalString(context.setup, 160) &&
      (context.rangeOfMotion === undefined ||
        context.rangeOfMotion === 'full' ||
        context.rangeOfMotion === 'partial' ||
        context.rangeOfMotion === 'unknown') &&
      (context.setFormat === undefined || context.setFormat === 'straight'));
  const validSymptoms =
    feedback.symptomFlags === undefined ||
    (Array.isArray(feedback.symptomFlags) &&
      feedback.symptomFlags.length > 0 &&
      feedback.symptomFlags.length <= 3 &&
      feedback.symptomFlags.every(
        (flag) => flag === 'pain' || flag === 'neurologic' || flag === 'other_concerning',
      ));
  const validObservationIds = (ids: unknown) =>
    ids === undefined ||
    (Array.isArray(ids) &&
      ids.length > 0 &&
      ids.length <= 20 &&
      ids.every((id) => typeof id === 'string' && id.trim().length > 0 && id.length <= 160));
  const validClaims = new Set([
    'goal_preference',
    'self_assessed_development',
    'performance',
    'tolerability',
    'symptom',
    'recovery',
    'pump',
    'causal_hypothesis',
    'dose_history',
  ]);
  const validInterpretations =
    feedback.interpretations === undefined ||
    (Array.isArray(feedback.interpretations) &&
      feedback.interpretations.length > 0 &&
      feedback.interpretations.length <= 8 &&
      feedback.interpretations.every(
        (interpretation) =>
          validClaims.has(interpretation.claim) &&
          (interpretation.timeframe === 'current' || interpretation.timeframe === 'historical') &&
          (interpretation.confidence === 'low' ||
            interpretation.confidence === 'moderate' ||
            interpretation.confidence === 'high') &&
          validObservationIds(interpretation.corroboratesObservationIds) &&
          validObservationIds(interpretation.conflictsWithObservationIds) &&
          validOptionalString(interpretation.proposedExplanation, 500),
      ));
  const hasObservation = Boolean(
    feedback.soreness !== undefined ||
    feedback.pump !== undefined ||
    feedback.performance !== undefined ||
    feedback.jointPain !== undefined ||
    muscles !== undefined ||
    feedback.targetMuscleReadiness !== undefined ||
    feedback.breathingReadiness !== undefined ||
    feedback.generalReadiness !== undefined ||
    supporting !== undefined ||
    feedback.trunkFatigue !== undefined ||
    feedback.generalExhaustion !== undefined ||
    feedback.symptomFlags !== undefined ||
    feedback.symptomNote !== undefined ||
    feedback.originalStatement !== undefined ||
    feedback.interpretations !== undefined,
  );
  return (
    typeof feedback.sessionId === 'string' &&
    feedback.sessionId.trim().length > 0 &&
    validOptionalScore(feedback.soreness) &&
    validOptionalScore(feedback.pump) &&
    (feedback.performance === undefined || validPerformance(feedback.performance)) &&
    validOptionalScore(feedback.jointPain) &&
    validMuscles &&
    (feedback.targetMuscle === undefined || MUSCLE_GROUPS.includes(feedback.targetMuscle)) &&
    (feedback.targetMuscleReadiness === undefined ||
      validReadiness(feedback.targetMuscleReadiness)) &&
    (feedback.breathingReadiness === undefined || validReadiness(feedback.breathingReadiness)) &&
    (feedback.generalReadiness === undefined || validReadiness(feedback.generalReadiness)) &&
    validSupporting &&
    validOptionalScore(feedback.trunkFatigue) &&
    validOptionalScore(feedback.generalExhaustion) &&
    validSymptoms &&
    validOptionalString(feedback.symptomNote, 500) &&
    validOptionalString(feedback.originalStatement, 1_000) &&
    (feedback.transcriptionUncertain === undefined ||
      typeof feedback.transcriptionUncertain === 'boolean') &&
    validInterpretations &&
    (feedback.source === undefined ||
      feedback.source === 'touch' ||
      feedback.source === 'voice' ||
      feedback.source === 'text' ||
      feedback.source === 'import' ||
      feedback.source === 'unknown') &&
    (feedback.observedAt === undefined || Number.isFinite(Date.parse(feedback.observedAt))) &&
    validOptionalString(feedback.sourceObservationId, 160) &&
    validOptionalString(feedback.correctsObservationId, 160) &&
    validContext &&
    hasObservation
  );
}

export function validateSetLog(value: unknown, session: Session): value is SetLog {
  if (!value || typeof value !== 'object') return false;
  const log = value as Partial<SetLog>;
  const exercise = session.exercises.find((item) => item.id === log.exerciseId);
  return (
    !session.safetyStop &&
    typeof log.id === 'string' &&
    log.sessionId === session.id &&
    Boolean(exercise) &&
    typeof log.setNumber === 'number' &&
    Number.isInteger(log.setNumber) &&
    log.setNumber >= 1 &&
    log.setNumber <= (exercise?.sets ?? 0) &&
    typeof log.reps === 'number' &&
    Number.isInteger(log.reps) &&
    log.reps >= 1 &&
    log.reps <= 50 &&
    (log.loadKg === null ||
      (typeof log.loadKg === 'number' &&
        Number.isFinite(log.loadKg) &&
        log.loadKg >= 0 &&
        log.loadKg <= 500)) &&
    typeof log.rir === 'number' &&
    Number.isInteger(log.rir) &&
    log.rir >= 0 &&
    log.rir <= 6 &&
    typeof log.completedAt === 'string' &&
    Number.isFinite(Date.parse(log.completedAt))
  );
}
