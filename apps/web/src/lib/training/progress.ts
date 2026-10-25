import { catalogVariantById } from './catalog';
import type { ControllerReceipt } from './controller';
import { createMesoBlock } from './engine';
import type { ExerciseSwapRecord, TrainingRecordsSnapshot } from './service';
import type {
  Session,
  SetLog,
  TemporaryTrainingPriority,
  TrainingFeedback,
  WorkoutSessionEvent,
} from './types';

type LoggedSet = Pick<SetLog, 'setNumber' | 'reps' | 'loadKg' | 'rir'>;

export type ExerciseProgress = {
  exerciseId: string;
  name: string;
  lastPerformedAt: string;
  lastSession: LoggedSet[];
  heaviestSet: (LoggedSet & { completedAt: string }) | null;
  totalSets: number;
};

export type TrainingProgress = {
  enrolled: boolean;
  completedSessions: number;
  setsLast7Days: number;
  exercises: ExerciseProgress[];
  latestCheckIn: {
    soreness?: number;
    pump?: number;
    performance?: 'up' | 'stable' | 'down';
    jointPain?: number;
    createdAt: string;
  } | null;
};

const DAY_MS = 24 * 60 * 60 * 1000;

function exerciseNames(sessions: TrainingRecordsSnapshot['sessions']): Map<string, string> {
  const names = new Map<string, string>();
  for (const record of sessions) {
    const prescription = (record as { prescription?: Session }).prescription;
    for (const exercise of prescription?.exercises ?? []) names.set(exercise.id, exercise.name);
  }
  return names;
}

const time = (value: string) => Date.parse(value);

/** Reports what the user actually logged. It never prescribes. */
export function summarizeTrainingProgress(
  snapshot: TrainingRecordsSnapshot,
  now: Date,
): TrainingProgress {
  const setup = snapshot.setup;
  if (!setup) {
    return {
      enrolled: false,
      completedSessions: 0,
      setsLast7Days: 0,
      exercises: [],
      latestCheckIn: null,
    };
  }
  const programSessions = snapshot.sessions.filter(
    (record) => (record as { programSetupId?: string }).programSetupId === setup.id,
  );
  const programSessionIds = new Set(programSessions.map((record) => record.id));
  const logs = snapshot.logs.filter((log) => programSessionIds.has(log.sessionId));
  const names = exerciseNames(programSessions);

  const byExercise = new Map<string, SetLog[]>();
  for (const log of logs) {
    byExercise.set(log.exerciseId, [...(byExercise.get(log.exerciseId) ?? []), log]);
  }

  const exercises = [...byExercise.entries()]
    .map(([exerciseId, rows]): ExerciseProgress => {
      const ordered = [...rows].sort((a, b) => time(b.completedAt) - time(a.completedAt));
      const latest = ordered[0]!;
      const lastSession = ordered
        .filter((log) => log.sessionId === latest.sessionId)
        .sort((a, b) => a.setNumber - b.setNumber)
        .map(({ setNumber, reps, loadKg, rir }) => ({ setNumber, reps, loadKg, rir }));
      const heaviest = rows
        .filter((log) => log.loadKg !== null)
        .sort((a, b) => b.loadKg! - a.loadKg! || b.reps - a.reps)[0];
      return {
        exerciseId,
        name: names.get(exerciseId) ?? catalogVariantById(exerciseId)?.name ?? exerciseId,
        lastPerformedAt: latest.completedAt,
        lastSession,
        heaviestSet: heaviest
          ? {
              setNumber: heaviest.setNumber,
              reps: heaviest.reps,
              loadKg: heaviest.loadKg,
              rir: heaviest.rir,
              completedAt: heaviest.completedAt,
            }
          : null,
        totalSets: rows.length,
      };
    })
    .sort((a, b) => time(b.lastPerformedAt) - time(a.lastPerformedAt));

  const latest = snapshot.feedback
    .filter((item) => programSessionIds.has(item.sessionId))
    .sort((a, b) => time(b.createdAt) - time(a.createdAt))[0];

  return {
    enrolled: true,
    completedSessions: programSessions.filter(
      (record) => (record as { status?: string }).status === 'completed',
    ).length,
    setsLast7Days: logs.filter((log) => now.getTime() - time(log.completedAt) <= 7 * DAY_MS).length,
    exercises,
    latestCheckIn: latest
      ? {
          soreness: latest.soreness,
          pump: latest.pump,
          performance: latest.performance,
          jointPain: latest.jointPain,
          createdAt: latest.createdAt,
        }
      : null,
  };
}

export type ProgressSetEvidence = {
  id: string;
  sessionId: string;
  exerciseId: string;
  setNumber: number;
  reps: number;
  loadKg: number | null;
  rir: number;
  completedAt: string;
  status: 'completed';
  corrections: NonNullable<SetLog['corrections']>;
};

export type ProgressExerciseEvidence = {
  exerciseId: string;
  variantId: string;
  originalExerciseId: string;
  name: string;
  status: 'completed' | 'skipped' | 'not_recorded';
  sets: ProgressSetEvidence[];
  skipEventId?: string;
};

export type ProgressSessionEvidence = {
  sessionId: string;
  prescriptionId: string;
  blockId: string | null;
  status: 'completed' | 'in_progress' | 'paused' | 'unknown';
  originalExerciseIds: string[];
  exercises: ProgressExerciseEvidence[];
};

export type ProgressFeedbackEvidence = {
  id: string;
  sessionId: string;
  source: TrainingFeedback['source'] | 'unknown';
  sourceObservationId?: string;
  correctsObservationId?: string;
  createdAt: string;
  soreness?: number;
  pump?: number;
  performance?: TrainingFeedback['performance'];
  jointPain?: number;
  trunkFatigue?: number;
  muscles?: TrainingFeedback['muscles'];
  symptomFlags?: TrainingFeedback['symptomFlags'];
};

export type ProgressConnection = {
  observationId: string;
  signal: 'result' | 'recovery' | 'tolerability';
  statement: string;
};

export type ProgressDecisionView = {
  kind: ControllerReceipt['decision']['kind'];
  changed: boolean;
  explanation: string | null;
  nextAction: string;
  before: string;
  after: string;
  evidenceIds: string[];
};

export type RepeatBlockReview = {
  reusableVariants: Array<{
    fromExerciseId: string;
    variantId: string;
    name: string;
    sessionId: string;
    blockId: string;
  }>;
  expiredPriorities: Array<{ id: string; detail: string }>;
};

export type TrainingProgressReview = {
  sessions: ProgressSessionEvidence[];
  feedback: ProgressFeedbackEvidence[];
  connections: ProgressConnection[];
  decision: ProgressDecisionView | null;
  repeatBlock: RepeatBlockReview;
};

export type TrainingProgressRead = TrainingProgress & { review: TrainingProgressReview };

const HYPERTROPHY_FROM_PUMP_OR_BACK =
  /hypertroph|muscle gain|muscle growth|built muscle|grew muscle/i;

type SubjectiveSignals = {
  pump?: number;
  trunkFatigue?: number;
  previousTrunkFatigue?: number;
  performance?: TrainingFeedback['performance'];
  soreness?: number;
  jointPain?: number;
  symptom?: boolean;
};

/** Pump and a drop in reported back fatigue are observations, not muscle growth. */
export function progressExplanation(rationale: string, signals: SubjectiveSignals): string | null {
  const lowerBackFatigue =
    signals.previousTrunkFatigue !== undefined &&
    signals.trunkFatigue !== undefined &&
    signals.trunkFatigue < signals.previousTrunkFatigue;
  const attributesGrowth =
    HYPERTROPHY_FROM_PUMP_OR_BACK.test(rationale) &&
    /pump|back fatigue|trunk fatigue/i.test(rationale);
  const onlyPumpOrBack =
    signals.performance === undefined &&
    signals.soreness === undefined &&
    signals.jointPain === undefined &&
    !signals.symptom &&
    (signals.pump !== undefined || lowerBackFatigue);
  const citesPumpOrBack = /pump|back fatigue|trunk fatigue|hypertroph/i.test(rationale);
  if (attributesGrowth || (onlyPumpOrBack && citesPumpOrBack)) return null;
  return rationale;
}

/** Prior-block swaps are reusable only when that exact variant was logged. */
export function reviewRepeatBlock(input: {
  now: Date;
  currentBlockId: string;
  swaps: Array<
    Pick<ExerciseSwapRecord, 'fromExerciseId' | 'toVariantId' | 'blockId' | 'sessionId'>
  >;
  logs: Array<Pick<SetLog, 'sessionId' | 'exerciseId'>>;
  sessionBlockIds: Map<string, string>;
  priorities: TemporaryTrainingPriority[];
}): RepeatBlockReview {
  const seen = new Set<string>();
  const reusableVariants = [];
  for (const swap of input.swaps) {
    if (swap.blockId === input.currentBlockId) continue;
    const key = `${swap.fromExerciseId}:${swap.toVariantId}`;
    if (seen.has(key)) continue;
    const worked = input.logs.some(
      (log) =>
        log.exerciseId === swap.toVariantId &&
        (log.sessionId === swap.sessionId ||
          input.sessionBlockIds.get(log.sessionId) === swap.blockId),
    );
    if (!worked) continue;
    seen.add(key);
    reusableVariants.push({
      fromExerciseId: swap.fromExerciseId,
      variantId: swap.toVariantId,
      name: catalogVariantById(swap.toVariantId)?.name ?? swap.toVariantId,
      sessionId: swap.sessionId,
      blockId: swap.blockId,
    });
  }
  const expiredPriorities = input.priorities
    .filter(
      (priority) =>
        priority.renewed !== true &&
        Number.isFinite(Date.parse(priority.expiresAt)) &&
        Date.parse(priority.expiresAt) <= input.now.getTime(),
    )
    .map((priority) => ({ id: priority.id, detail: priority.detail }));
  return { reusableVariants, expiredPriorities };
}

function readPriorities(setup: TrainingRecordsSnapshot['setup']): TemporaryTrainingPriority[] {
  if (!setup?.temporaryPriorities) return [];
  return setup.temporaryPriorities.filter(
    (priority) =>
      typeof priority.id === 'string' &&
      priority.id.length > 0 &&
      typeof priority.detail === 'string' &&
      priority.detail.length > 0 &&
      typeof priority.expiresAt === 'string' &&
      Number.isFinite(Date.parse(priority.expiresAt)) &&
      (priority.renewed === undefined || typeof priority.renewed === 'boolean'),
  );
}

function exerciseRows(value: unknown): Array<{ id: string; name: string }> {
  if (!value || typeof value !== 'object') return [];
  const exercises = (value as { exercises?: unknown }).exercises;
  if (!Array.isArray(exercises)) return [];
  return exercises.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const row = item as { id?: unknown; name?: unknown };
    if (typeof row.id !== 'string' || typeof row.name !== 'string') return [];
    return [{ id: row.id, name: row.name }];
  });
}

function executionEvents(value: unknown): WorkoutSessionEvent[] {
  if (!value || typeof value !== 'object') return [];
  const events = (value as { executionEvents?: unknown }).executionEvents;
  if (!Array.isArray(events)) return [];
  return events.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const event = item as Partial<WorkoutSessionEvent>;
    if (
      typeof event.id !== 'string' ||
      typeof event.kind !== 'string' ||
      typeof event.createdAt !== 'string'
    )
      return [];
    return [event as WorkoutSessionEvent];
  });
}

function sessionStatus(value: unknown): ProgressSessionEvidence['status'] {
  if (value === 'completed' || value === 'in_progress' || value === 'paused') return value;
  return 'unknown';
}

function setEvidence(log: SetLog): ProgressSetEvidence {
  return {
    id: log.id,
    sessionId: log.sessionId,
    exerciseId: log.exerciseId,
    setNumber: log.setNumber,
    reps: log.reps,
    loadKg: log.loadKg,
    rir: log.rir,
    completedAt: log.completedAt,
    status: 'completed',
    corrections: log.corrections ?? [],
  };
}

function feedbackEvidence(item: TrainingFeedback): ProgressFeedbackEvidence {
  return {
    id: item.id,
    sessionId: item.sessionId,
    source: item.source ?? 'unknown',
    ...(item.sourceObservationId ? { sourceObservationId: item.sourceObservationId } : {}),
    ...(item.correctsObservationId ? { correctsObservationId: item.correctsObservationId } : {}),
    createdAt: item.createdAt,
    ...(item.soreness !== undefined ? { soreness: item.soreness } : {}),
    ...(item.pump !== undefined ? { pump: item.pump } : {}),
    ...(item.performance !== undefined ? { performance: item.performance } : {}),
    ...(item.jointPain !== undefined ? { jointPain: item.jointPain } : {}),
    ...(item.trunkFatigue !== undefined ? { trunkFatigue: item.trunkFatigue } : {}),
    ...(item.muscles ? { muscles: item.muscles } : {}),
    ...(item.symptomFlags ? { symptomFlags: item.symptomFlags } : {}),
  };
}

function subjectiveSignals(feedback: TrainingFeedback[]): SubjectiveSignals {
  const ordered = [...feedback].sort((a, b) => time(b.createdAt) - time(a.createdAt));
  const latest = ordered[0];
  const previous = ordered.find((item, index) => index > 0 && item.trunkFatigue !== undefined);
  if (!latest) return {};
  return {
    pump: latest.pump,
    trunkFatigue: latest.trunkFatigue,
    previousTrunkFatigue: previous?.trunkFatigue,
    performance: latest.performance,
    soreness: latest.soreness,
    jointPain: latest.jointPain,
    symptom: (latest.symptomFlags?.length ?? 0) > 0,
  };
}

function connections(
  sets: ProgressSetEvidence[],
  feedback: ProgressFeedbackEvidence[],
): ProgressConnection[] {
  const links: ProgressConnection[] = [];
  const latestSet = [...sets].sort((a, b) => time(b.completedAt) - time(a.completedAt))[0];
  if (latestSet) {
    const load = latestSet.loadKg === null ? 'bodyweight' : `${latestSet.loadKg} kg`;
    const label = latestSet.corrections.length > 0 ? 'Corrected performance' : 'Recorded';
    links.push({
      observationId: latestSet.id,
      signal: 'result',
      statement: `${label}: ${latestSet.reps} reps at ${load}, ${latestSet.rir} reps in reserve.`,
    });
  }
  const latestFeedback = [...feedback].sort((a, b) => time(b.createdAt) - time(a.createdAt))[0];
  if (latestFeedback) {
    const recovery = [
      latestFeedback.performance ? `performance ${latestFeedback.performance}` : null,
      latestFeedback.soreness !== undefined ? `soreness ${latestFeedback.soreness}` : null,
    ].filter((part): part is string => part !== null);
    if (recovery.length) {
      links.push({
        observationId: latestFeedback.id,
        signal: 'recovery',
        statement: `Recovery check-in: ${recovery.join(', ')}.`,
      });
    }
    const tolerability = [
      latestFeedback.jointPain !== undefined ? `joint pain ${latestFeedback.jointPain}` : null,
      latestFeedback.symptomFlags?.length
        ? `symptoms ${latestFeedback.symptomFlags.join(', ')}`
        : null,
    ].filter((part): part is string => part !== null);
    if (tolerability.length) {
      links.push({
        observationId: latestFeedback.id,
        signal: 'tolerability',
        statement: `Tolerability check-in: ${tolerability.join(', ')}.`,
      });
    }
  }
  return links;
}

function presentDecision(
  decision: ControllerReceipt,
  signals: SubjectiveSignals,
): ProgressDecisionView {
  const changed = decision.decision.kind !== 'hold';
  return {
    kind: decision.decision.kind,
    changed,
    explanation: changed ? progressExplanation(decision.rationale, signals) : null,
    nextAction: decision.nextAction,
    before: decision.before,
    after: decision.after,
    evidenceIds: decision.evidenceIds,
  };
}

/**
 * History plus the evidence a progress review can cite. It reports recorded
 * work and the engine decision it was given. It does not build a prescription.
 */
export function assembleTrainingProgressRead(
  snapshot: TrainingRecordsSnapshot,
  now: Date,
  decision: ControllerReceipt | null,
): TrainingProgressRead {
  const summary = summarizeTrainingProgress(snapshot, now);
  const setup = snapshot.setup;
  if (!setup) {
    return {
      ...summary,
      review: {
        sessions: [],
        feedback: [],
        connections: [],
        decision: null,
        repeatBlock: { reusableVariants: [], expiredPriorities: [] },
      },
    };
  }
  const programSessions = snapshot.sessions.filter(
    (record) => (record as { programSetupId?: string }).programSetupId === setup.id,
  );
  const programSessionIds = new Set(programSessions.map((record) => record.id));
  const logs = snapshot.logs.filter((log) => programSessionIds.has(log.sessionId));
  const feedback = snapshot.feedback
    .filter((item) => programSessionIds.has(item.sessionId))
    .sort((a, b) => time(a.createdAt) - time(b.createdAt));
  const sessionBlockIds = new Map<string, string>();
  const sessions = programSessions.map((record): ProgressSessionEvidence => {
    const blockId = typeof record.blockId === 'string' ? record.blockId : null;
    if (blockId) sessionBlockIds.set(record.id, blockId);
    const prescription = (record as { prescription?: unknown }).prescription;
    const initial = (record as { initialPrescription?: unknown }).initialPrescription;
    const currentExercises = exerciseRows(prescription);
    const originalExercises = exerciseRows(initial);
    const originalIds = new Set(originalExercises.map((exercise) => exercise.id));
    const originalByIndex = new Map(originalExercises.map((exercise, index) => [index, exercise]));
    const names = new Map(
      [...originalExercises, ...currentExercises].map((exercise) => [exercise.id, exercise.name]),
    );
    const skipped = new Map(
      executionEvents(prescription)
        .filter((event) => event.kind === 'skipped' && typeof event.exerciseId === 'string')
        .map((event) => [event.exerciseId as string, event.id]),
    );
    const sessionLogs = logs.filter((log) => log.sessionId === record.id);
    const seen = new Set<string>();
    const exercises: ProgressExerciseEvidence[] = [];
    currentExercises.forEach((exercise, index) => {
      seen.add(exercise.id);
      const sets = sessionLogs
        .filter((log) => log.exerciseId === exercise.id)
        .sort((a, b) => a.setNumber - b.setNumber)
        .map(setEvidence);
      const skipEventId = skipped.get(exercise.id);
      exercises.push({
        exerciseId: exercise.id,
        variantId: exercise.id,
        originalExerciseId: originalIds.has(exercise.id)
          ? exercise.id
          : (originalByIndex.get(index)?.id ?? exercise.id),
        name: exercise.name,
        status: sets.length ? 'completed' : skipEventId ? 'skipped' : 'not_recorded',
        sets,
        ...(skipEventId ? { skipEventId } : {}),
      });
    });
    for (const [exerciseId, skipEventId] of skipped) {
      if (seen.has(exerciseId)) continue;
      exercises.push({
        exerciseId,
        variantId: exerciseId,
        originalExerciseId: exerciseId,
        name: names.get(exerciseId) ?? catalogVariantById(exerciseId)?.name ?? exerciseId,
        status: 'skipped',
        sets: [],
        skipEventId,
      });
    }
    for (const exerciseId of new Set(sessionLogs.map((log) => log.exerciseId))) {
      if (seen.has(exerciseId) || skipped.has(exerciseId)) continue;
      const sets = sessionLogs
        .filter((log) => log.exerciseId === exerciseId)
        .sort((a, b) => a.setNumber - b.setNumber)
        .map(setEvidence);
      exercises.push({
        exerciseId,
        variantId: exerciseId,
        originalExerciseId: exerciseId,
        name: names.get(exerciseId) ?? catalogVariantById(exerciseId)?.name ?? exerciseId,
        status: 'completed',
        sets,
      });
    }
    const prescriptionId =
      prescription &&
      typeof prescription === 'object' &&
      typeof (prescription as Session).id === 'string'
        ? (prescription as Session).id
        : record.id;
    return {
      sessionId: record.id,
      prescriptionId,
      blockId,
      status: sessionStatus((record as { status?: unknown }).status),
      originalExerciseIds: originalExercises.map((exercise) => exercise.id),
      exercises,
    };
  });
  const feedbackRows = feedback.map(feedbackEvidence);
  const setRows = sessions.flatMap((session) =>
    session.exercises.flatMap((exercise) => exercise.sets),
  );
  const signals = subjectiveSignals(feedback);
  return {
    ...summary,
    review: {
      sessions,
      feedback: feedbackRows,
      connections: connections(setRows, feedbackRows),
      decision: decision ? presentDecision(decision, signals) : null,
      repeatBlock: reviewRepeatBlock({
        now,
        currentBlockId: createMesoBlock(setup.startedAt, now.toISOString()).id,
        swaps: snapshot.swaps.filter((swap) => swap.programSetupId === setup.id),
        logs,
        sessionBlockIds,
        priorities: readPriorities(setup),
      }),
    },
  };
}
