import { catalogVariantById } from './catalog';
import type { ControllerReceipt } from './controller';
import type { TrainingRecordsSnapshot } from './service';
import type { ExercisePrescription, Session, SetLog, TrainingFeedback } from './types';

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
  variantId: string;
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
  name: string;
  status: 'completed' | 'skipped' | 'planned';
  sets: ProgressSetEvidence[];
};

export type ProgressSessionEvidence = {
  sessionId: string;
  prescriptionId: string | null;
  status: 'completed' | 'in_progress' | 'paused' | 'unknown';
  exercises: ProgressExerciseEvidence[];
  events: Array<{
    id: string;
    kind: string;
    exerciseId?: string;
    replacementExerciseId?: string;
  }>;
};

export type ProgressFeedbackEvidence = {
  id: string;
  sessionId: string;
  source?: TrainingFeedback['source'];
  sourceObservationId?: string;
  correctsObservationId?: string;
  createdAt: string;
  soreness?: number;
  pump?: number;
  performance?: TrainingFeedback['performance'];
  jointPain?: number;
  trunkFatigue?: number;
  interpretations?: Array<{
    claim: string;
    timeframe: 'current' | 'historical';
    proposedExplanation?: string;
  }>;
};

export type RepeatBlockReview = {
  reuseVariantIds: string[];
  expiredPriorities: string[];
  renewedPriorities: string[];
};

export type TrainingProgressRead = TrainingProgress & {
  evidence: {
    sessions: ProgressSessionEvidence[];
    feedback: ProgressFeedbackEvidence[];
  };
  review: {
    explanations: string[];
    repeatBlock: RepeatBlockReview;
  };
  /** Engine receipt already computed for the next read. This route does not apply it. */
  decision: ControllerReceipt | null;
};

type ProposedSession = {
  pattern: Session['pattern'];
  exercises: Array<Pick<ExercisePrescription, 'id' | 'name' | 'sets' | 'progression'>>;
};

const GROWTH_CLAIM = /hypertrophy|muscle growth|grew/;
const PUMP_OR_BACK = /pump|back fatigue|trunk fatigue/;

function sessionStatus(value: unknown): ProgressSessionEvidence['status'] {
  if (value === 'completed' || value === 'in_progress' || value === 'paused') return value;
  return 'unknown';
}

function asSession(value: unknown): Session | null {
  if (!value || typeof value !== 'object') return null;
  const session = value as Partial<Session>;
  if (typeof session.id !== 'string' || !Array.isArray(session.exercises)) return null;
  return session as Session;
}

function namedExercises(value: unknown): Array<{ id: string; name: string }> {
  if (!value || typeof value !== 'object') return [];
  const exercises = (value as { exercises?: unknown }).exercises;
  if (!Array.isArray(exercises)) return [];
  return exercises.flatMap((item) => {
    if (!item || typeof item !== 'object') return [];
    const id = (item as { id?: unknown }).id;
    const name = (item as { name?: unknown }).name;
    if (typeof id !== 'string' || typeof name !== 'string') return [];
    return [{ id, name }];
  });
}

function programSessions(snapshot: TrainingRecordsSnapshot) {
  const setupId = snapshot.setup?.id;
  if (!setupId) return [];
  return snapshot.sessions.filter(
    (record) => (record as { programSetupId?: string }).programSetupId === setupId,
  );
}

/** Keeps the logged set, its correction audit, and skip events addressable. */
export function trainingProgressEvidence(snapshot: TrainingRecordsSnapshot): {
  sessions: ProgressSessionEvidence[];
  feedback: ProgressFeedbackEvidence[];
} {
  const sessions = programSessions(snapshot);
  const sessionIds = new Set(sessions.map((record) => record.id));
  const evidenceSessions = sessions
    .map((record): ProgressSessionEvidence => {
      const prescription = asSession((record as { prescription?: unknown }).prescription);
      const names = new Map<string, string>();
      for (const exercise of namedExercises(
        (record as { initialPrescription?: unknown }).initialPrescription,
      )) {
        names.set(exercise.id, exercise.name);
      }
      for (const exercise of prescription?.exercises ?? []) names.set(exercise.id, exercise.name);
      const events = (prescription?.executionEvents ?? []).map((event) => ({
        id: event.id,
        kind: event.kind,
        ...(event.exerciseId ? { exerciseId: event.exerciseId } : {}),
        ...(event.replacementExerciseId
          ? { replacementExerciseId: event.replacementExerciseId }
          : {}),
      }));
      const skipped = new Set(
        events.flatMap((event) =>
          event.kind === 'skipped' && event.exerciseId ? [event.exerciseId] : [],
        ),
      );
      const logs = snapshot.logs.filter((log) => log.sessionId === record.id);
      const ids = [
        ...(prescription?.exercises ?? []).map((exercise) => exercise.id),
        ...skipped,
        ...logs.map((log) => log.exerciseId),
      ];
      const orderedIds = [...new Set(ids)];
      const exercises = orderedIds.map((exerciseId): ProgressExerciseEvidence => {
        const sets = logs
          .filter((log) => log.exerciseId === exerciseId)
          .sort((a, b) => a.setNumber - b.setNumber)
          .map((log): ProgressSetEvidence => ({
            id: log.id,
            sessionId: log.sessionId,
            exerciseId: log.exerciseId,
            variantId: log.exerciseId,
            setNumber: log.setNumber,
            reps: log.reps,
            loadKg: log.loadKg,
            rir: log.rir,
            completedAt: log.completedAt,
            status: 'completed',
            corrections: log.corrections ?? [],
          }));
        let status: ProgressExerciseEvidence['status'] = 'planned';
        if (sets.length > 0) status = 'completed';
        else if (skipped.has(exerciseId)) status = 'skipped';
        return {
          exerciseId,
          variantId: exerciseId,
          name: names.get(exerciseId) ?? catalogVariantById(exerciseId)?.name ?? exerciseId,
          status,
          sets,
        };
      });
      return {
        sessionId: record.id,
        prescriptionId: prescription?.id ?? null,
        status: sessionStatus((record as { status?: unknown }).status),
        exercises,
        events,
      };
    })
    .sort((a, b) => {
      const left = sessions.find((record) => record.id === a.sessionId);
      const right = sessions.find((record) => record.id === b.sessionId);
      const leftAt = String(
        (left as { startedAt?: string } | undefined)?.startedAt ?? left?.server_updated_at ?? '',
      );
      const rightAt = String(
        (right as { startedAt?: string } | undefined)?.startedAt ?? right?.server_updated_at ?? '',
      );
      return time(rightAt) - time(leftAt);
    });

  const feedback = snapshot.feedback
    .filter((item) => sessionIds.has(item.sessionId))
    .sort((a, b) => time(b.createdAt) - time(a.createdAt))
    .map((item): ProgressFeedbackEvidence => ({
      id: item.id,
      sessionId: item.sessionId,
      source: item.source,
      sourceObservationId: item.sourceObservationId,
      correctsObservationId: item.correctsObservationId,
      createdAt: item.createdAt,
      soreness: item.soreness,
      pump: item.pump,
      performance: item.performance,
      jointPain: item.jointPain,
      trunkFatigue: item.trunkFatigue,
      interpretations: item.interpretations?.map((interpretation) => ({
        claim: interpretation.claim,
        timeframe: interpretation.timeframe,
        proposedExplanation: interpretation.proposedExplanation,
      })),
    }));

  return { sessions: evidenceSessions, feedback };
}

/**
 * A completed variant can be reused exactly. A goal preference carries into the
 * next block only when a current observation renews it.
 */
export function reviewRepeatBlock(
  sessions: ProgressSessionEvidence[],
  feedback: ProgressFeedbackEvidence[],
): RepeatBlockReview {
  const worked = new Map<string, string>();
  for (const session of sessions) {
    if (session.status !== 'completed') continue;
    const painful = new Set(
      session.events.flatMap((event) =>
        event.kind === 'pain' && event.exerciseId ? [event.exerciseId] : [],
      ),
    );
    for (const exercise of session.exercises) {
      if (exercise.status !== 'completed' || painful.has(exercise.variantId)) continue;
      const latest = [...exercise.sets].sort(
        (a, b) => time(b.completedAt) - time(a.completedAt),
      )[0];
      const previous = worked.get(exercise.variantId);
      if (!previous || (latest && time(latest.completedAt) > time(previous))) {
        worked.set(exercise.variantId, latest?.completedAt ?? '');
      }
    }
  }
  const priorities = new Map<string, boolean>();
  for (const item of feedback) {
    for (const interpretation of item.interpretations ?? []) {
      if (interpretation.claim !== 'goal_preference') continue;
      const label = interpretation.proposedExplanation?.trim();
      if (!label) continue;
      priorities.set(
        label,
        priorities.get(label) === true || interpretation.timeframe === 'current',
      );
    }
  }
  return {
    reuseVariantIds: [...worked.entries()]
      .sort((a, b) => time(b[1]) - time(a[1]) || a[0].localeCompare(b[0]))
      .map(([id]) => id),
    expiredPriorities: [...priorities.entries()]
      .filter(([, renewed]) => !renewed)
      .map(([label]) => label)
      .sort(),
    renewedPriorities: [...priorities.entries()]
      .filter(([, renewed]) => renewed)
      .map(([label]) => label)
      .sort(),
  };
}

function meaningfulDecision(decision: ControllerReceipt): boolean {
  if (decision.before !== decision.after) return true;
  if (decision.decision.kind !== 'hold') return true;
  return decision.decision.optionalBurdenReduction;
}

function onlyPumpOrBackFatigue(feedback: ProgressFeedbackEvidence[]): boolean {
  if (feedback.length === 0) return false;
  return feedback.every((item) => {
    const hasOtherSignal =
      item.soreness !== undefined || item.performance !== undefined || item.jointPain !== undefined;
    return (item.pump !== undefined || item.trunkFatigue !== undefined) && !hasOtherSignal;
  });
}

function infersHypertrophyFromPumpOrBackFatigue(
  line: string,
  feedback: ProgressFeedbackEvidence[],
): boolean {
  const text = line.toLowerCase();
  if (!GROWTH_CLAIM.test(text)) return false;
  return PUMP_OR_BACK.test(text) || onlyPumpOrBackFatigue(feedback);
}

/** Explains recorded results against the engine receipt. It adds no new dose. */
export function progressReviewExplanations(input: {
  decision: ControllerReceipt | null;
  proposed: ProposedSession | null;
  lastCompleted: ProposedSession | null;
  feedback: ProgressFeedbackEvidence[];
}): string[] {
  const lines: string[] = [];
  if (input.decision && meaningfulDecision(input.decision)) lines.push(input.decision.rationale);
  const priorById = new Map(
    (input.lastCompleted?.exercises ?? []).map((exercise) => [exercise.id, exercise]),
  );
  for (const exercise of input.proposed?.exercises ?? []) {
    const prior = priorById.get(exercise.id);
    if (!prior) continue;
    if (prior.sets !== exercise.sets) {
      lines.push(`${exercise.name}: set count changed from ${prior.sets} to ${exercise.sets}.`);
    }
    if (exercise.progression !== 'hold' && exercise.progression !== prior.progression) {
      const action = exercise.progression === 'add_reps' ? 'add a rep' : 'increase the load';
      lines.push(`${exercise.name}: logged sets support ${action}.`);
    }
  }
  return lines.filter((line) => !infersHypertrophyFromPumpOrBackFatigue(line, input.feedback));
}

function lastCompletedSession(snapshot: TrainingRecordsSnapshot): ProposedSession | null {
  const completed = programSessions(snapshot)
    .filter((record) => (record as { status?: string }).status === 'completed')
    .sort((a, b) => {
      const left = String((a as { startedAt?: string }).startedAt ?? a.server_updated_at);
      const right = String((b as { startedAt?: string }).startedAt ?? b.server_updated_at);
      return time(right) - time(left);
    })[0];
  const prescription = asSession(
    (completed as { prescription?: unknown } | undefined)?.prescription,
  );
  if (!prescription) return null;
  return {
    pattern: prescription.pattern,
    exercises: prescription.exercises.map((exercise) => ({
      id: exercise.id,
      name: exercise.name,
      sets: exercise.sets,
      progression: exercise.progression,
    })),
  };
}

/**
 * One history read for the mobile progress route. The summary is the same
 * function the training MCP tool uses.
 */
export function readTrainingProgress(
  snapshot: TrainingRecordsSnapshot,
  now: Date,
  context: {
    decision?: ControllerReceipt | null;
    proposed?: ProposedSession | null;
  } = {},
): TrainingProgressRead {
  const summary = summarizeTrainingProgress(snapshot, now);
  const evidence = trainingProgressEvidence(snapshot);
  const decision = context.decision ?? null;
  return {
    ...summary,
    evidence,
    review: {
      explanations: progressReviewExplanations({
        decision,
        proposed: context.proposed ?? null,
        lastCompleted: lastCompletedSession(snapshot),
        feedback: evidence.feedback,
      }),
      repeatBlock: reviewRepeatBlock(evidence.sessions, evidence.feedback),
    },
    decision,
  };
}
