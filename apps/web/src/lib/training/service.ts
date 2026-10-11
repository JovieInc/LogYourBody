import { createHash } from 'node:crypto';
import type {
  NativeProductRecord,
  NativeProductRecordCollection,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import {
  buildMicrocycle,
  buildSession,
  createMesoBlock,
  isProgramSetup,
  validTrainingFeedback,
} from './engine';
import type { Session, SetLog, TrainingFeedback, TrainingProgramSetup } from './types';

const EPOCH = '1970-01-01T00:00:00.000Z';

export function stableTrainingUuid(...parts: string[]): string {
  const hex = createHash('sha256').update(parts.join('\0')).digest('hex').slice(0, 32).split('');
  hex[12] = '5';
  hex[16] = ((parseInt(hex[16] ?? '0', 16) & 0x3) | 0x8).toString(16);
  const value = hex.join('');
  return `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${value.slice(16, 20)}-${value.slice(20)}`;
}

export type TrainingRecordsSnapshot = {
  setup: TrainingProgramSetup | null;
  sessions: NativeProductRecord[];
  logs: SetLog[];
  feedback: TrainingFeedback[];
};

export async function pullAllTrainingRecords(
  records: NativeProductRecordsPort,
  subject: string,
  collection: NativeProductRecordCollection,
): Promise<NativeProductRecord[]> {
  const all: NativeProductRecord[] = [];
  const visited = new Set<string>();
  let cursor: { since: string; after_id: string | null } = { since: EPOCH, after_id: null };
  for (;;) {
    const page = await records.pull(subject, collection, { ...cursor, limit: 500 });
    all.push(...page.records);
    if (!page.next_cursor) return all;
    const nextKey = `${page.next_cursor.since}\0${page.next_cursor.after_id ?? ''}`;
    if (visited.has(nextKey)) throw new Error('training_records_pagination_stalled');
    visited.add(nextKey);
    cursor = page.next_cursor;
  }
}

function recordType(record: NativeProductRecord): string | null {
  return typeof record.record_type === 'string' ? record.record_type : null;
}

function active(record: NativeProductRecord): boolean {
  return record.deleted_at === null;
}

function toSetLog(record: NativeProductRecord): SetLog | null {
  if (recordType(record) !== 'set_log') return null;
  const value = record as unknown as Partial<SetLog>;
  if (
    typeof value.sessionId !== 'string' ||
    typeof value.exerciseId !== 'string' ||
    typeof value.setNumber !== 'number' ||
    typeof value.reps !== 'number' ||
    (value.loadKg !== null && typeof value.loadKg !== 'number') ||
    typeof value.rir !== 'number' ||
    typeof value.completedAt !== 'string'
  )
    return null;
  return { ...value, id: record.id } as SetLog;
}

function toTrainingFeedback(record: NativeProductRecord): TrainingFeedback | null {
  if (recordType(record) !== 'session_feedback') return null;
  const value = { ...record, id: record.id };
  if (!validTrainingFeedback(value)) return null;
  const createdAt =
    typeof record.createdAt === 'string' ? record.createdAt : record.server_updated_at;
  if (!Number.isFinite(Date.parse(createdAt))) return null;
  return { ...(value as Omit<TrainingFeedback, 'id' | 'createdAt'>), id: record.id, createdAt };
}

export async function loadTrainingRecords(
  records: NativeProductRecordsPort,
  subject: string,
): Promise<TrainingRecordsSnapshot> {
  const [sessions, sets, feedbackRows] = await Promise.all([
    pullAllTrainingRecords(records, subject, 'training_sessions'),
    pullAllTrainingRecords(records, subject, 'logged_sets'),
    pullAllTrainingRecords(records, subject, 'training_feedback'),
  ]);
  const activeFeedback = feedbackRows.filter(active);
  const setupRecord = activeFeedback
    .filter((record) => recordType(record) === 'program_setup' && isProgramSetup(record))
    .sort((a, b) => Date.parse(String(b.startedAt)) - Date.parse(String(a.startedAt)))[0];
  return {
    setup: setupRecord ? (setupRecord as unknown as TrainingProgramSetup) : null,
    sessions: sessions.filter(active).filter((record) => recordType(record) === 'workout_session'),
    logs: sets
      .filter(active)
      .map(toSetLog)
      .filter((record): record is SetLog => record !== null),
    feedback: activeFeedback
      .map(toTrainingFeedback)
      .filter((record): record is TrainingFeedback => record !== null),
  };
}

export type NextWorkoutResult =
  | { kind: 'not_enrolled' }
  | { kind: 'week_complete'; week: number; weeklyFractionalVolume: Record<string, number> }
  | {
      kind: 'workout';
      session: Session & { loggedSets: SetLog[] };
      week: number;
      weekCount: number;
      weeklyFractionalVolume: Record<string, number>;
    };

type SessionRecord = NativeProductRecord & {
  record_type?: string;
  programSetupId?: string;
  blockId?: string;
  weekNumber?: number;
  slot?: number;
  status?: string;
  prescription?: Session;
  startedAt?: string;
};

export async function getOrCreateNextWorkout(input: {
  records: NativeProductRecordsPort;
  subject: string;
  now: Date;
  /** false returns the same prescription without starting or updating a session record. */
  persist?: boolean;
}): Promise<NextWorkoutResult> {
  const persist = input.persist ?? true;
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  const setup = snapshot.setup;
  if (!setup) return { kind: 'not_enrolled' };

  const block = createMesoBlock(setup.startedAt, input.now.toISOString());
  let periodSessions = snapshot.sessions as SessionRecord[];
  const programSessionIds = new Set(
    periodSessions
      .filter((record) => record.programSetupId === setup.id)
      .map((record) => record.id),
  );
  const programLogs = snapshot.logs.filter((log) => programSessionIds.has(log.sessionId));
  const programFeedback = snapshot.feedback.filter((feedback) =>
    programSessionIds.has(feedback.sessionId),
  );
  let activeRecord: SessionRecord | undefined = periodSessions
    .filter((record) => record.programSetupId === setup.id && record.status === 'in_progress')
    .sort(
      (a, b) =>
        Date.parse(String(b.startedAt ?? b.server_updated_at)) -
        Date.parse(String(a.startedAt ?? a.server_updated_at)),
    )[0];
  const activePrescription = activeRecord?.prescription;
  if (
    persist &&
    activeRecord &&
    activePrescription &&
    !activePrescription.safetyStop &&
    activePrescription.exercises.length > 0 &&
    activePrescription.exercises.every((exercise) =>
      Array.from({ length: exercise.sets }, (_, index) => index + 1).every((setNumber) =>
        programLogs.some(
          (log) =>
            log.sessionId === activePrescription.id &&
            log.exerciseId === exercise.id &&
            log.setNumber === setNumber,
        ),
      ),
    )
  ) {
    // Recover a final set that was acknowledged before the completion write failed.
    const completed = {
      ...activeRecord,
      status: 'completed',
      completedAt: input.now.toISOString(),
    };
    const saved = await input.records.push(input.subject, 'training_sessions', [completed]);
    if (saved.rejected_ids.includes(completed.id)) throw new Error('training_completion_rejected');
    periodSessions = periodSessions.map((record) =>
      record.id === completed.id ? completed : record,
    );
    activeRecord = undefined;
  }
  const completedThisWeek = periodSessions.filter(
    (record) =>
      record.programSetupId === setup.id &&
      record.blockId === block.id &&
      record.weekNumber === block.currentWeek &&
      record.status === 'completed',
  );

  const microcycle = buildMicrocycle({
    setup,
    block,
    sessionIds: Array.from({ length: setup.sessionsPerWeek }, (_, slot) =>
      stableTrainingUuid(
        input.subject,
        setup.id,
        block.id,
        String(block.currentWeek),
        String(slot),
      ),
    ),
    logs: programLogs,
    feedback: programFeedback,
  });

  if (activeRecord?.prescription) {
    const existing = activeRecord.prescription;
    const targetRir = existing.exercises[0]?.targetRir ?? block.targetRir;
    const adjusted = buildSession({
      setup,
      block: { ...block, currentWeek: existing.week, targetRir },
      sessionId: existing.id,
      slot: existing.slot,
      logs: programLogs,
      feedback: programFeedback,
    });
    if (persist) {
      const saved = await input.records.push(input.subject, 'training_sessions', [
        {
          ...activeRecord,
          prescription: adjusted,
          status: adjusted.safetyStop ? 'paused' : 'in_progress',
        },
      ]);
      if (saved.rejected_ids.includes(adjusted.id))
        throw new Error('training_session_owner_conflict');
    }
    return {
      kind: 'workout',
      session: {
        ...adjusted,
        loggedSets: programLogs.filter((log) => log.sessionId === adjusted.id),
      },
      week: existing.week,
      weekCount: block.weekCount,
      weeklyFractionalVolume: microcycle.plannedFractionalVolume,
    };
  }

  if (completedThisWeek.length >= setup.sessionsPerWeek) {
    return {
      kind: 'week_complete',
      week: block.currentWeek,
      weeklyFractionalVolume: microcycle.plannedFractionalVolume,
    };
  }

  const slot = completedThisWeek.length;
  const session = microcycle.sessions[slot];
  if (!session)
    return {
      kind: 'week_complete',
      week: block.currentWeek,
      weeklyFractionalVolume: microcycle.plannedFractionalVolume,
    };
  const sessionRecord = {
    id: session.id,
    record_type: 'workout_session',
    programSetupId: setup.id,
    blockId: block.id,
    weekNumber: block.currentWeek,
    slot,
    status: session.safetyStop ? 'paused' : 'in_progress',
    prescription: session,
    startedAt: input.now.toISOString(),
  };
  if (persist) {
    const saved = await input.records.push(input.subject, 'training_sessions', [sessionRecord]);
    if (saved.rejected_ids.includes(session.id)) throw new Error('training_session_owner_conflict');
  }
  return {
    kind: 'workout',
    session: { ...session, loggedSets: programLogs.filter((log) => log.sessionId === session.id) },
    week: block.currentWeek,
    weekCount: block.weekCount,
    weeklyFractionalVolume: microcycle.plannedFractionalVolume,
  };
}

export async function storeProgramSetup(input: {
  records: NativeProductRecordsPort;
  subject: string;
  setup: Omit<TrainingProgramSetup, 'id' | 'consentVersion' | 'startedAt'>;
  now: Date;
  createId: () => string;
}): Promise<TrainingProgramSetup> {
  const setup: TrainingProgramSetup = {
    ...input.setup,
    id: input.createId(),
    consentVersion: 'hypertrophy-coach-v1',
    startedAt: input.now.toISOString(),
  };
  const result = await input.records.push(input.subject, 'training_feedback', [
    {
      ...setup,
      record_type: 'program_setup',
    },
  ]);
  if (result.rejected_ids.includes(setup.id)) throw new Error('training_setup_owner_conflict');
  return setup;
}

export function isWorkoutSessionRecord(record: NativeProductRecord): record is SessionRecord {
  return (
    recordType(record) === 'workout_session' &&
    typeof (record as SessionRecord).programSetupId === 'string' &&
    typeof (record as SessionRecord).status === 'string' &&
    Boolean((record as SessionRecord).prescription)
  );
}
