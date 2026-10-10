import {
  MESOCYCLE_WEEKS,
  MUSCLE_GROUPS,
  type DeloadState,
  type Equipment,
  type ExercisePattern,
  type ExercisePrescription,
  type Microcycle,
  type MesoBlock,
  type MuscleContribution,
  type MuscleGroup,
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
const REP_RANGE = { min: 8, max: 12 } as const;

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

export function evaluateDeload(feedback: TrainingFeedback[]): DeloadState {
  const ordered = [...feedback].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
  const latest = ordered[0];
  if (!latest) {
    return {
      action: 'none',
      explanation: 'No recovery feedback has been recorded; keep the starting dose steady.',
      evidenceIds: RECOVERY_EVIDENCE,
    };
  }
  if (latest.jointPain >= 4) {
    return {
      action: 'pause_session',
      explanation:
        'Pain was reported at a high level. Pause the affected exercise and consider qualified clinical guidance if it persists or worsens.',
      evidenceIds: ['k:220190f8', 'k:e95f2199'],
    };
  }
  const sustainedDecline =
    ordered.length >= 2 && ordered[0]?.performance === 'down' && ordered[1]?.performance === 'down';
  if (sustainedDecline && latest.soreness >= 7) {
    return {
      action: 'reduce_volume',
      explanation:
        'Performance has declined across two check-ins while soreness is high, so this session uses one set per movement. Volume is not increased automatically.',
      evidenceIds: ['k:0b3ea5bb', 'k:76bf778c', 'k:a6ae7fd4'],
    };
  }
  return {
    action: 'none',
    explanation:
      latest.pump <= 2
        ? 'A low pump by itself does not change the plan; keep the current dose and review performance and recovery over time.'
        : 'No repeated performance decline or high pain signal was reported; keep the current dose steady.',
    evidenceIds: RECOVERY_EVIDENCE,
  };
}

function progressionForExercise(
  exerciseId: string,
  logs: SetLog[],
  targetRir: number,
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
  const carriedLoad = lastSets[lastSets.length - 1]?.loadKg ?? null;
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
  const deload = evaluateDeload(input.feedback);
  const safetyStop = deload.action === 'pause_session';
  const baseSets = deload.action === 'reduce_volume' ? 1 : 2;
  const targetRir = input.block.targetRir;
  const exercises = safetyStop
    ? []
    : EXERCISES[input.setup.equipment][pattern].map((seed) => {
        const progression = progressionForExercise(seed.id, input.logs, targetRir);
        return {
          id: seed.id,
          name: seed.name,
          primaryMuscle: seed.primaryMuscle,
          muscleContribution: seed.muscleContribution,
          sets: baseSets,
          repRange: REP_RANGE,
          targetReps: progression.targetReps,
          targetRir,
          targetLoadKg: progression.targetLoadKg,
          loadInstruction: progression.loadInstruction,
          progression: progression.action,
          evidenceIds: progression.action === 'increase_load' ? LOAD_EVIDENCE : EFFORT_EVIDENCE,
        };
      });
  return {
    id: input.sessionId,
    week: input.block.currentWeek,
    slot: input.slot,
    pattern,
    title: `Full body ${pattern}`,
    exercises,
    safetyStop,
    explanation: deload.explanation,
    evidenceIds: [...new Set([...VOLUME_EVIDENCE, ...EFFORT_EVIDENCE, ...deload.evidenceIds])],
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
  return (
    typeof feedback.sessionId === 'string' &&
    validScore(feedback.soreness) &&
    validScore(feedback.pump) &&
    validScore(feedback.jointPain) &&
    (feedback.performance === 'up' ||
      feedback.performance === 'stable' ||
      feedback.performance === 'down')
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
