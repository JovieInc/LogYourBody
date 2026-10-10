import type {
  NativeProductRecord,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { validTrainingFeedback, validateSetLog } from './engine';
import {
  isWorkoutSessionRecord,
  loadTrainingRecords,
  pullAllTrainingRecords,
  stableTrainingUuid,
} from './service';
import type { SetLog, TrainingFeedback } from './types';

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
}): Promise<LogSetResult> {
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
  if (!session || !validateSetLog({ id: 'server-generated', ...set, completedAt }, session))
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
  };
  if (!records.insertTrainingSet) return { kind: 'rejected' };
  const saved = await records.insertTrainingSet(subject, log);
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
    const completion = await records.push(subject, 'training_sessions', [
      { ...sessionRecord, status: 'completed', completedAt },
    ]);
    if (completion.rejected_ids.includes(session.id)) return { kind: 'rejected' };
  }
  return { kind: 'logged', log: saved, sessionComplete };
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
}): Promise<FeedbackResult> {
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  if (!snapshot.setup) return { kind: 'program_not_enrolled' };
  const sessionExists = snapshot.sessions.some(
    (record) =>
      record.id === input.feedback.sessionId &&
      (record as NativeProductRecord & { programSetupId?: string }).programSetupId ===
        snapshot.setup?.id,
  );
  if (!sessionExists) return { kind: 'session_not_found' };
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
  if (!validTrainingFeedback(feedback)) return { kind: 'invalid' };
  const saved = await input.records.push(input.subject, 'training_feedback', [feedback]);
  if (saved.rejected_ids.includes(feedback.id)) return { kind: 'rejected' };
  return { kind: 'recorded', feedback };
}
