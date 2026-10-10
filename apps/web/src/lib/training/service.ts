import type { TrainingMutationAdmission } from '@/lib/ports/training-mutations';
import {
  captureTrainingAdmission,
  requireAdmittedSetup,
  commitTrainingMutation,
} from './mutation-admission';
import type { TrainingRevisionsPort } from '@/lib/ports/training-revisions';
import { TRAINING_BASELINE_POLICY, type RevisionContextToken } from './revision-contract';
import { createHash } from 'node:crypto';
import { z } from 'zod';
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
import {
  MUSCLE_GROUPS,
  type Session,
  type SetLog,
  type TrainingFeedback,
  type TrainingProgramSetup,
} from './types';

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

const sessionPrescriptionSchema = z
  .object({
    id: z.string(),
    week: z.number().int().positive(),
    slot: z.number().int().nonnegative(),
    pattern: z.enum(['A', 'B']),
    title: z.string(),
    exercises: z.array(
      z.object({
        id: z.string(),
        name: z.string(),
        primaryMuscle: z.enum(MUSCLE_GROUPS),
        muscleContribution: z.record(z.string(), z.number().nonnegative()),
        sets: z.number().int().positive(),
        repRange: z.object({ min: z.number().int().positive(), max: z.number().int().positive() }),
        targetReps: z.number().int().positive(),
        targetRir: z.number().int().nonnegative(),
        targetLoadKg: z.number().nonnegative().nullable(),
        loadInstruction: z.string().nullable(),
        progression: z.enum(['hold', 'add_reps', 'increase_load']),
        evidenceIds: z.array(z.string()),
      }),
    ),
    safetyStop: z.boolean(),
    explanation: z.string().nullable(),
    evidenceIds: z.array(z.string()),
  })
  .refine((session) => session.safetyStop === (session.exercises.length === 0));

function isSessionPrescription(value: unknown, sessionId: string): value is Session {
  const result = sessionPrescriptionSchema.safeParse(value);
  return result.success && result.data.id === sessionId;
}

type SessionRecord = NativeProductRecord & {
  record_type?: string;
  programSetupId?: string;
  blockId?: string;
  weekNumber?: number;
  slot?: number;
  status?: string;
  prescription?: Session;
  initialPrescription?: unknown;
  startedAt?: string;
};

export async function getOrCreateNextWorkout(input: {
  records: NativeProductRecordsPort;
  subject: string;
  now: Date;
  /** false returns the same prescription without starting or updating a session record. */
  persist?: boolean;
  admission?: TrainingMutationAdmission;
}): Promise<NextWorkoutResult> {
  const persist = input.persist ?? true;
  const admission =
    input.admission ??
    (persist ? await captureTrainingAdmission(input.records, input.subject) : null);
  if (persist && !admission) return { kind: 'not_enrolled' };
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  const setup = snapshot.setup;
  if (!setup) return { kind: 'not_enrolled' };
  if (admission) requireAdmittedSetup(admission, setup);
  if (setup.programRevisionId && setup.programPolicyVersion !== TRAINING_BASELINE_POLICY)
    throw new Error('training_program_policy_requires_review');

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
    .filter(
      (record) =>
        record.programSetupId === setup.id &&
        (record.status === 'in_progress' || record.status === 'paused'),
    )
    .sort(
      (a, b) =>
        Date.parse(String(b.startedAt ?? b.server_updated_at)) -
        Date.parse(String(a.startedAt ?? a.server_updated_at)),
    )[0];
  const activePrescription = activeRecord?.prescription;
  if (activeRecord && !isSessionPrescription(activePrescription, activeRecord.id)) {
    throw new Error('training_session_invalid_prescription');
  }
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
    await commitTrainingMutation(
      input.records,
      input.subject,
      admission!,
      'session_update',
      completed,
    );
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

  // Progression for a new session uses completed workouts, never its own unfinished sets.
  const completedSessionIds = new Set(
    periodSessions.filter((record) => record.status === 'completed').map((record) => record.id),
  );
  const completedLogs = programLogs.filter((log) => completedSessionIds.has(log.sessionId));

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
    logs: completedLogs,
    feedback: programFeedback,
  });

  if (activeRecord?.prescription) {
    const existing = activeRecord.prescription;
    const retained = activeRecord.initialPrescription;
    const initial =
      isSessionPrescription(retained, existing.id) &&
      !retained.safetyStop &&
      retained.week === existing.week &&
      retained.slot === existing.slot &&
      retained.pattern === existing.pattern
        ? retained
        : !existing.safetyStop
          ? existing
          : undefined;
    // Legacy paused rows have no exercise snapshot. Recover from completed history
    // at their original start time; already-overwritten targets cannot be recovered exactly.
    const startedAt =
      typeof activeRecord.startedAt === 'string' &&
      Number.isFinite(Date.parse(activeRecord.startedAt))
        ? activeRecord.startedAt
        : input.now.toISOString();
    const originalBlock = createMesoBlock(setup.startedAt, startedAt);
    const adjusted = buildSession({
      setup,
      block: {
        ...originalBlock,
        currentWeek: existing.week,
        targetRir: initial?.exercises[0]?.targetRir ?? originalBlock.targetRir,
      },
      sessionId: existing.id,
      slot: existing.slot,
      logs: completedLogs,
      feedback: programFeedback,
    });
    if (initial && !adjusted.safetyStop) {
      // Keep the prescribed targets; only the engine's current recovery set count changes.
      adjusted.exercises = initial.exercises.map((exercise) => ({
        ...exercise,
        sets:
          adjusted.exercises.find((current) => current.id === exercise.id)?.sets ?? exercise.sets,
      }));
    }
    const initialPrescription = initial ?? (!adjusted.safetyStop ? adjusted : undefined);
    if (persist) {
      await commitTrainingMutation(input.records, input.subject, admission!, 'session_update', {
        ...activeRecord,
        prescription: adjusted,
        ...(initialPrescription ? { initialPrescription } : {}),
        status: adjusted.safetyStop ? 'paused' : 'in_progress',
      });
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
    ...(setup.programRevisionId ? { programRevisionId: setup.programRevisionId } : {}),
    blockId: block.id,
    weekNumber: block.currentWeek,
    slot,
    status: session.safetyStop ? 'paused' : 'in_progress',
    prescription: session,
    ...(!session.safetyStop ? { initialPrescription: session } : {}),
    startedAt: input.now.toISOString(),
  };
  if (persist) {
    await commitTrainingMutation(
      input.records,
      input.subject,
      admission!,
      'session_insert',
      sessionRecord,
    );
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
  revisions?: TrainingRevisionsPort;
  expectedContext?: RevisionContextToken;
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
  if (input.revisions) {
    if (!input.expectedContext) throw new Error('training_enrollment_context_required');
    const { ownerId, generation, profileFingerprint, legacyFingerprint } = input.expectedContext;
    await input.revisions.storeLegacySetup(input.subject, setup, {
      ownerId,
      generation,
      profileFingerprint,
      legacyFingerprint,
    });
    return setup;
  }
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
