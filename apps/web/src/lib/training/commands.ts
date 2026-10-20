import type { TrainingMutationAdmission } from '@/lib/ports/training-mutations';
import {
  captureTrainingAdmission,
  requireAdmittedSetup,
  requireCurrentTrainingAdmission,
  commitTrainingMutation,
} from './mutation-admission';
import type {
  NativeProductRecord,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import {
  isEligibleExerciseSubstitution,
  latestFeedbackPerSession,
  validTrainingFeedback,
  validateSetLog,
} from './engine';
import {
  isWorkoutSessionRecord,
  loadTrainingRecords,
  pullAllTrainingRecords,
  stableTrainingUuid,
} from './service';
import type { SetLog, TrainingFeedback } from './types';
import type { ExercisePrescription, Session, WorkoutSessionEvent } from './types';

export type LogSetInput = {
  sessionId: string;
  exerciseId: string;
  setNumber: number;
  reps: number;
  loadKg: number | null;
  rir: number;
};

export type LogSetResult =
  | {
      kind: 'logged';
      log: NativeProductRecord | (SetLog & { record_type: string });
      sessionComplete: boolean;
    }
  | { kind: 'program_not_enrolled' }
  | { kind: 'session_not_found' }
  | { kind: 'session_not_active' }
  | { kind: 'set_not_in_session' }
  | { kind: 'set_conflict' }
  | { kind: 'rejected' };

/** Stores one set against the subject's active session. Shared by the mobile API and MCP. */
export async function logTrainingSet(input: {
  records: NativeProductRecordsPort;
  subject: string;
  now: Date;
  set: LogSetInput;
  admission?: TrainingMutationAdmission;
}): Promise<LogSetResult> {
  const { records, subject, set } = input;
  const admission = input.admission ?? (await captureTrainingAdmission(records, subject));
  if (!admission) return { kind: 'program_not_enrolled' };
  const [snapshot, sessions] = await Promise.all([
    loadTrainingRecords(records, subject),
    pullAllTrainingRecords(records, subject, 'training_sessions'),
  ]);
  if (!snapshot.setup) return { kind: 'program_not_enrolled' };
  requireAdmittedSetup(admission, snapshot.setup);
  const sessionRecord = sessions.find((record) => record.id === set.sessionId);
  if (
    !sessionRecord ||
    sessionRecord.deleted_at !== null ||
    !isWorkoutSessionRecord(sessionRecord) ||
    sessionRecord.programSetupId !== snapshot.setup.id
  ) {
    return { kind: 'session_not_found' };
  }
  const session = sessionRecord.prescription;
  const logId = stableTrainingUuid(
    subject,
    sessionRecord.id,
    set.exerciseId,
    String(set.setNumber),
  );
  if (sessionRecord.status !== 'in_progress') {
    // The final write may have succeeded even when its response was interrupted.
    // A completed session permits an exact replay, never an edit or a new set.
    const prior = snapshot.logs.find((log) => log.id === logId);
    if (
      sessionRecord.status === 'completed' &&
      prior &&
      prior.sessionId === set.sessionId &&
      prior.exerciseId === set.exerciseId &&
      prior.setNumber === set.setNumber &&
      prior.reps === set.reps &&
      prior.loadKg === set.loadKg &&
      prior.rir === set.rir
    ) {
      return { kind: 'logged', log: { ...prior, record_type: 'set_log' }, sessionComplete: true };
    }
    return { kind: 'session_not_active' };
  }
  const completedAt = input.now.toISOString();
  const hasSavedIdentity = snapshot.logs.some(
    (prior) =>
      prior.id === logId &&
      prior.sessionId === set.sessionId &&
      prior.exerciseId === set.exerciseId &&
      prior.setNumber === set.setNumber,
  );
  // Recovery can reduce the effective set count after a set was already saved.
  // Let the atomic read below acknowledge that row or reject a changed payload;
  // only a genuinely new identity must fit the current prescription.
  if (
    !session ||
    (!hasSavedIdentity && !validateSetLog({ id: 'server-generated', ...set, completedAt }, session))
  )
    return { kind: 'set_not_in_session' };

  const log: SetLog & { record_type: string } = {
    id: logId,
    record_type: 'set_log',
    sessionId: session.id,
    exerciseId: set.exerciseId,
    setNumber: set.setNumber,
    reps: set.reps,
    loadKg: set.loadKg,
    rir: set.rir,
    completedAt,
    revision: 0,
    corrections: [],
  };
  const saved = await commitTrainingMutation(records, subject, admission, 'set_insert', log);
  if (!saved || saved.id !== logId || saved.deleted_at !== null || saved.record_type !== 'set_log')
    return { kind: 'rejected' };
  if (
    saved.sessionId !== set.sessionId ||
    saved.exerciseId !== set.exerciseId ||
    saved.setNumber !== set.setNumber ||
    saved.reps !== set.reps ||
    saved.loadKg !== set.loadKg ||
    saved.rir !== set.rir
  )
    return { kind: 'set_conflict' };
  const allLogs = [...snapshot.logs.filter((prior) => prior.id !== logId), saved];
  const sessionComplete = session.exercises.every((exercise) =>
    Array.from({ length: exercise.sets }, (_, index) => index + 1).every((setNumber) =>
      allLogs.some(
        (record) =>
          record.sessionId === session.id &&
          record.exerciseId === exercise.id &&
          record.setNumber === setNumber,
      ),
    ),
  );
  if (sessionComplete) {
<<<<<<< HEAD
    if (!records.updateTrainingSession) return { kind: 'rejected' };
    const completion = await records.updateTrainingSession(
      subject,
      session.id,
      session.executionRevision ?? 0,
      allLogs.filter((log) => log.sessionId === session.id).length,
      { ...sessionRecord, status: 'completed', completedAt },
    );
    if (!completion) return { kind: 'rejected' };
=======
    await commitTrainingMutation(records, subject, admission, 'session_update', {
      ...sessionRecord,
      status: 'completed',
      completedAt,
    });
>>>>>>> origin/main
  }
  return { kind: 'logged', log: saved, sessionComplete };
}

export type CorrectSetInput = LogSetInput & {
  correctionId: string;
  expectedRevision: number;
};

export type CorrectSetResult =
  | { kind: 'corrected'; log: NativeProductRecord | (SetLog & { record_type: string }) }
  | { kind: 'program_not_enrolled' }
  | { kind: 'session_not_found' }
  | { kind: 'set_not_found' }
  | { kind: 'set_not_in_session' }
  | { kind: 'set_conflict' }
  | { kind: 'rejected' };

/** Corrects one stable set identity. The prior values and correction id live in
 * the same atomic row update, so an acknowledgement can never exist without its audit trail. */
export async function correctTrainingSet(input: {
  records: NativeProductRecordsPort;
  subject: string;
  now: Date;
  set: CorrectSetInput;
}): Promise<CorrectSetResult> {
  const { records, subject, set } = input;
  const [snapshot, sessions] = await Promise.all([
    loadTrainingRecords(records, subject),
    pullAllTrainingRecords(records, subject, 'training_sessions'),
  ]);
  if (!snapshot.setup) return { kind: 'program_not_enrolled' };
  const sessionRecord = sessions.find((record) => record.id === set.sessionId);
  if (
    !sessionRecord ||
    sessionRecord.deleted_at !== null ||
    !isWorkoutSessionRecord(sessionRecord) ||
    sessionRecord.programSetupId !== snapshot.setup.id
  )
    return { kind: 'session_not_found' };
  const session = sessionRecord.prescription;
  if (!session) return { kind: 'session_not_found' };
  const exercise = session.exercises.find((item) => item.id === set.exerciseId);
  if (
    !exercise ||
    !Number.isInteger(set.setNumber) ||
    set.setNumber < 1 ||
    set.setNumber > exercise.sets ||
    !Number.isInteger(set.reps) ||
    set.reps < 1 ||
    set.reps > 50 ||
    !Number.isInteger(set.rir) ||
    set.rir < 0 ||
    set.rir > 6 ||
    (set.loadKg !== null && (!Number.isFinite(set.loadKg) || set.loadKg < 0 || set.loadKg > 500))
  )
    return { kind: 'set_not_in_session' };
  const existing = snapshot.logs.find(
    (log) =>
      log.sessionId === set.sessionId &&
      log.exerciseId === set.exerciseId &&
      log.setNumber === set.setNumber,
  );
  if (!existing) return { kind: 'set_not_found' };
  const priorCorrection = existing.corrections?.find((item) => item.id === set.correctionId);
  if (priorCorrection) {
    return existing.reps === set.reps && existing.loadKg === set.loadKg && existing.rir === set.rir
      ? { kind: 'corrected', log: { ...existing, record_type: 'set_log' } }
      : { kind: 'set_conflict' };
  }
  if ((existing.revision ?? 0) !== set.expectedRevision) return { kind: 'set_conflict' };
  if (!records.correctTrainingSet) return { kind: 'rejected' };
  const corrected: SetLog & { record_type: string } = {
    ...existing,
    record_type: 'set_log',
    reps: set.reps,
    loadKg: set.loadKg,
    rir: set.rir,
    revision: (existing.revision ?? 0) + 1,
    corrections: [
      ...(existing.corrections ?? []),
      {
        id: set.correctionId,
        correctedAt: input.now.toISOString(),
        previous: { reps: existing.reps, loadKg: existing.loadKg, rir: existing.rir },
      },
    ],
  };
  const saved = await records.correctTrainingSet(
    subject,
    existing.id,
    set.expectedRevision,
    corrected,
  );
  if (!saved) return { kind: 'set_conflict' };
  return { kind: 'corrected', log: saved };
}

export type FeedbackInput = Pick<
  TrainingFeedback,
  'sessionId' | 'soreness' | 'pump' | 'performance' | 'jointPain'
>;

export type FeedbackResult =
  | { kind: 'recorded'; feedback: TrainingFeedback & { record_type: string } }
  | { kind: 'program_not_enrolled' }
  | { kind: 'session_not_found' }
  | { kind: 'rejected' }
  | { kind: 'invalid' };

/** Stores a post-session check-in. Shared by the mobile API and MCP. */
export async function recordTrainingFeedback(input: {
  records: NativeProductRecordsPort;
  subject: string;
  now: Date;
  createId: () => string;
  feedback: FeedbackInput;
  admission?: TrainingMutationAdmission;
}): Promise<FeedbackResult> {
  const admission =
    input.admission ?? (await captureTrainingAdmission(input.records, input.subject));
  if (!admission) return { kind: 'program_not_enrolled' };
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  if (!snapshot.setup) return { kind: 'program_not_enrolled' };
  requireAdmittedSetup(admission, snapshot.setup);
  const sessionExists = snapshot.sessions.some(
    (record) =>
      record.id === input.feedback.sessionId &&
      (record as NativeProductRecord & { programSetupId?: string }).programSetupId ===
        snapshot.setup?.id,
  );
  if (!sessionExists) return { kind: 'session_not_found' };
  if (!validTrainingFeedback(input.feedback)) return { kind: 'invalid' };
  const latest = latestFeedbackPerSession(snapshot.feedback).find(
    (item) => item.sessionId === input.feedback.sessionId,
  );
  if (
    latest &&
    latest.soreness === input.feedback.soreness &&
    latest.pump === input.feedback.pump &&
    latest.performance === input.feedback.performance &&
    latest.jointPain === input.feedback.jointPain
  ) {
    // Keep the original observation time, even when another session has newer feedback.
    await requireCurrentTrainingAdmission(input.records, input.subject, admission);
    return {
      kind: 'recorded',
      feedback: {
        id: latest.id,
        record_type: 'session_feedback',
        ...input.feedback,
        createdAt: latest.createdAt,
      },
    };
  }
  const latestFeedbackTime = snapshot.feedback.reduce(
    (latest, item) => Math.max(latest, Date.parse(item.createdAt)),
    0,
  );
  const createdAt = new Date(Math.max(input.now.getTime(), latestFeedbackTime + 1)).toISOString();
  const feedback: TrainingFeedback & { record_type: string } = {
    id: input.createId(),
    record_type: 'session_feedback',
    ...input.feedback,
    createdAt,
  };
  await commitTrainingMutation(
    input.records,
    input.subject,
    admission,
    'feedback_insert',
    feedback,
  );
  return { kind: 'recorded', feedback };
}

export type WorkoutActionInput =
  | { kind: 'equipment_unavailable'; exerciseId: string }
  | { kind: 'shorten'; minutes: number }
  | { kind: 'skip'; exerciseId: string }
  | { kind: 'pain'; exerciseId: string }
  | { kind: 'pause' }
  | { kind: 'resume' }
  | { kind: 'end' };

export type WorkoutActionResult =
  | {
      kind: 'updated';
      decision: WorkoutSessionEvent['kind'];
      session: Session & { loggedSets: SetLog[] };
    }
  | { kind: 'program_not_enrolled' }
  | { kind: 'session_not_found' }
  | { kind: 'session_not_active' }
  | { kind: 'stale_revision' }
  | { kind: 'stale_current_exercise' }
  | { kind: 'no_eligible_substitution' }
  | { kind: 'rejected' };

type MutableSessionRecord = NativeProductRecord & {
  programSetupId?: string;
  status?: string;
  prescription?: Session;
  completedAt?: string;
};

function logsForSession(logs: SetLog[], sessionId: string): SetLog[] {
  return logs.filter((log) => log.sessionId === sessionId);
}

function currentExercise(session: Session, logs: SetLog[]): ExercisePrescription | undefined {
  return session.exercises.find((exercise) =>
    Array.from({ length: exercise.sets }, (_, index) => index + 1).some(
      (setNumber) =>
        !logs.some((log) => log.exerciseId === exercise.id && log.setNumber === setNumber),
    ),
  );
}

function shortenExercises(
  exercises: ExercisePrescription[],
  logs: SetLog[],
  minutes: number,
): ExercisePrescription[] {
  // Three minutes per set is a conservative bounded execution budget. Already
  // completed identities are never removed, even if the requested time is shorter.
  let remaining = Math.max(logs.length, Math.floor(minutes / 3), 1);
  const result: ExercisePrescription[] = [];
  for (const exercise of exercises) {
    const completed = logs.filter((log) => log.exerciseId === exercise.id);
    const requiredSets = completed.reduce((maximum, log) => Math.max(maximum, log.setNumber), 0);
    const sets = Math.max(requiredSets, Math.min(exercise.sets, remaining));
    if (sets > 0) result.push({ ...exercise, sets });
    remaining = Math.max(0, remaining - sets);
  }
  return result;
}

/** Applies an executable, session-scoped action to the same persisted workout
 * record used by mobile set logging and MCP. The revision and event id make
 * retries idempotent and stale current-card actions fail closed. */
export async function applyWorkoutAction(input: {
  records: NativeProductRecordsPort;
  subject: string;
  now: Date;
  sessionId: string;
  eventId: string;
  expectedRevision: number;
  action: WorkoutActionInput;
}): Promise<WorkoutActionResult> {
  const [snapshot, records] = await Promise.all([
    loadTrainingRecords(input.records, input.subject),
    pullAllTrainingRecords(input.records, input.subject, 'training_sessions'),
  ]);
  if (!snapshot.setup) return { kind: 'program_not_enrolled' };
  const record = records.find((candidate) => candidate.id === input.sessionId) as
    MutableSessionRecord | undefined;
  if (
    !record ||
    record.deleted_at !== null ||
    !isWorkoutSessionRecord(record) ||
    record.programSetupId !== snapshot.setup.id ||
    !record.prescription
  )
    return { kind: 'session_not_found' };
  const session = record.prescription;
  const sessionLogs = logsForSession(snapshot.logs, session.id);
  const priorEvent = session.executionEvents?.find((event) => event.id === input.eventId);
  if (priorEvent) {
    return {
      kind: 'updated',
      decision: priorEvent.kind,
      session: { ...session, loggedSets: sessionLogs },
    };
  }
  if (record.status !== 'in_progress' && record.status !== 'paused')
    return { kind: 'session_not_active' };
  if ((session.executionRevision ?? 0) !== input.expectedRevision)
    return { kind: 'stale_revision' };
  if (session.safetyStop && input.action.kind !== 'end') return { kind: 'session_not_active' };
  if (session.executionPaused && input.action.kind !== 'resume' && input.action.kind !== 'end')
    return { kind: 'session_not_active' };

  const current = currentExercise(session, sessionLogs);
  let exercises = session.exercises;
  let safetyStop = session.safetyStop;
  let explanation = session.explanation;
  let executionPaused = session.executionPaused ?? false;
  let status = record.status;
  let event: WorkoutSessionEvent;

  switch (input.action.kind) {
    case 'equipment_unavailable': {
      if (!current || current.id !== input.action.exerciseId)
        return { kind: 'stale_current_exercise' };
      const currentIndex = exercises.findIndex((exercise) => exercise.id === current.id);
      const hasLaterWork = exercises
        .slice(currentIndex + 1)
        .some((exercise) =>
          Array.from({ length: exercise.sets }, (_, index) => index + 1).some(
            (setNumber) =>
              !sessionLogs.some(
                (log) => log.exerciseId === exercise.id && log.setNumber === setNumber,
              ),
          ),
        );
      if (hasLaterWork) {
        exercises = [
          ...exercises.slice(0, currentIndex),
          ...exercises.slice(currentIndex + 1),
          current,
        ];
        event = {
          id: input.eventId,
          kind: 'reordered',
          exerciseId: current.id,
          createdAt: input.now.toISOString(),
        };
      } else {
        const hasCompletedCurrentSet = sessionLogs.some((log) => log.exerciseId === current.id);
        const replacement = current.substitutions?.find(
          (candidate) =>
            !exercises.some((exercise) => exercise.id === candidate.id) &&
            isEligibleExerciseSubstitution({
              exercise: current,
              candidate,
              equipment: snapshot.setup!.equipment,
            }),
        );
        if (hasCompletedCurrentSet || !replacement) return { kind: 'no_eligible_substitution' };
        const prescribedReplacement: ExercisePrescription = {
          ...replacement,
          sets: current.sets,
          substitutions: current.substitutions.filter(
            (candidate) => candidate.id !== replacement.id,
          ),
        };
        exercises = exercises.map((exercise) =>
          exercise.id === current.id ? prescribedReplacement : exercise,
        );
        event = {
          id: input.eventId,
          kind: 'substituted',
          exerciseId: current.id,
          replacementExerciseId: replacement.id,
          createdAt: input.now.toISOString(),
        };
      }
      break;
    }
    case 'shorten':
      exercises = shortenExercises(exercises, sessionLogs, input.action.minutes);
      event = {
        id: input.eventId,
        kind: 'shortened',
        minutes: input.action.minutes,
        createdAt: input.now.toISOString(),
      };
      break;
    case 'skip':
      if (!current || current.id !== input.action.exerciseId)
        return { kind: 'stale_current_exercise' };
      if (sessionLogs.some((log) => log.exerciseId === current.id))
        return { kind: 'stale_current_exercise' };
      exercises = exercises.filter((exercise) => exercise.id !== current.id);
      event = {
        id: input.eventId,
        kind: 'skipped',
        exerciseId: current.id,
        createdAt: input.now.toISOString(),
      };
      break;
    case 'pain':
      if (!current || current.id !== input.action.exerciseId)
        return { kind: 'stale_current_exercise' };
      safetyStop = true;
      executionPaused = true;
      explanation =
        'Pain was reported during this movement. Training is paused; review symptoms and seek qualified care if they persist or worsen.';
      event = {
        id: input.eventId,
        kind: 'pain',
        exerciseId: current.id,
        createdAt: input.now.toISOString(),
      };
      break;
    case 'pause':
      executionPaused = true;
      event = { id: input.eventId, kind: 'paused', createdAt: input.now.toISOString() };
      break;
    case 'resume':
      executionPaused = false;
      event = { id: input.eventId, kind: 'resumed', createdAt: input.now.toISOString() };
      break;
    case 'end':
      status = 'completed';
      event = { id: input.eventId, kind: 'ended', createdAt: input.now.toISOString() };
      break;
  }

  const updated: Session = {
    ...session,
    exercises,
    safetyStop,
    explanation,
    executionPaused,
    executionRevision: (session.executionRevision ?? 0) + 1,
    executionEvents: [...(session.executionEvents ?? []), event],
  };
  if (!input.records.updateTrainingSession) return { kind: 'rejected' };
  const saved = await input.records.updateTrainingSession(
    input.subject,
    record.id,
    input.expectedRevision,
    sessionLogs.length,
    {
      ...record,
      status,
      prescription: updated,
      ...(status === 'completed' ? { completedAt: input.now.toISOString() } : {}),
    },
  );
  if (!saved) return { kind: 'stale_revision' };
  return {
    kind: 'updated',
    decision: event.kind,
    session: { ...updated, loggedSets: sessionLogs },
  };
}
