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
  catalogVariantById,
  isEligibleVariant,
  missingEquipment,
  resolveAvailableEquipment,
  substitutionCandidates,
  type CatalogEquipment,
  type TrunkDemandLevel,
} from './catalog';
import {
  evaluateNextSetReadiness,
  completedTrainingSession,
  sessionWorkLogged,
  isEligibleExerciseSubstitution,
  latestFeedbackPerSession,
  sameTrainingFeedbackObservation,
  validTrainingFeedback,
  validateSetLog,
} from './engine';
import {
  isWorkoutSessionRecord,
  loadTrainingRecords,
  pullAllTrainingRecords,
  stableTrainingUuid,
  swappedPrescription,
  type ExerciseSwapRecord,
} from './service';
import type {
  ExercisePrescription,
  Session,
  SetLog,
  TrainingFeedback,
  WorkoutSessionEvent,
} from './types';

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
      (sessionRecord.status === 'completed' ||
        (sessionRecord.status === 'ended' &&
          session &&
          sessionWorkLogged(session, snapshot.logs))) &&
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
  const sessionComplete = sessionWorkLogged(session, allLogs as SetLog[]);
  if (sessionComplete) {
    await commitTrainingMutation(records, subject, admission, 'session_update', {
      ...sessionRecord,
      status: completedTrainingSession(session, allLogs as SetLog[]) ? 'completed' : 'ended',
      completedAt,
    });
  }
  return { kind: 'logged', log: saved, sessionComplete };
}

export type FeedbackInput = Omit<TrainingFeedback, 'id' | 'createdAt'>;

export type FeedbackResult =
  | {
      kind: 'recorded';
      feedback: TrainingFeedback & { record_type: string };
      recommendation: ReturnType<typeof evaluateNextSetReadiness>;
    }
  | { kind: 'program_not_enrolled' }
  | { kind: 'session_not_found' }
  | { kind: 'rejected' }
  | { kind: 'invalid' };

function publicFeedbackRecord(
  feedback: TrainingFeedback,
): TrainingFeedback & { record_type: string } {
  const {
    user_id: _userId,
    deleted_at: _deletedAt,
    server_updated_at: _serverUpdatedAt,
    record_type: _recordType,
    ...observation
  } = feedback as TrainingFeedback & {
    user_id?: string;
    deleted_at?: string | null;
    server_updated_at?: string;
    record_type?: string;
  };
  return { ...observation, record_type: 'session_feedback' };
}

/** Stores session or between-set observations. Shared by native, text and voice callers. */
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
  const normalized: FeedbackInput = {
    ...input.feedback,
    source: input.feedback.source ?? 'unknown',
    observedAt: input.feedback.observedAt ?? input.now.toISOString(),
  };
  if (!validTrainingFeedback(normalized)) return { kind: 'invalid' };
  const correctionTarget = normalized.correctsObservationId
    ? snapshot.feedback.find((item) => item.id === normalized.correctsObservationId)
    : undefined;
  if (
    normalized.correctsObservationId &&
    (!correctionTarget || correctionTarget.sessionId !== normalized.sessionId)
  ) {
    return { kind: 'invalid' };
  }
  const sourceDuplicate = normalized.sourceObservationId
    ? snapshot.feedback.find((item) => item.sourceObservationId === normalized.sourceObservationId)
    : undefined;
  if (sourceDuplicate) {
    if (sourceDuplicate.sessionId !== normalized.sessionId) return { kind: 'invalid' };
    await requireCurrentTrainingAdmission(input.records, input.subject, admission);
    return {
      kind: 'recorded',
      feedback: publicFeedbackRecord(sourceDuplicate),
      recommendation: evaluateNextSetReadiness({
        feedback: snapshot.feedback,
        sessionId: normalized.sessionId,
        now: input.now,
      }),
    };
  }
  const comparable: TrainingFeedback = {
    id: 'candidate',
    createdAt: normalized.observedAt ?? input.now.toISOString(),
    ...normalized,
  };
  const exactDuplicate = normalized.correctsObservationId
    ? undefined
    : snapshot.feedback.find(
        (item) =>
          item.sessionId === normalized.sessionId &&
          sameTrainingFeedbackObservation(item, comparable),
      );
  if (exactDuplicate) {
    // Keep the original observation time, even when another session has newer feedback.
    await requireCurrentTrainingAdmission(input.records, input.subject, admission);
    return {
      kind: 'recorded',
      feedback: publicFeedbackRecord(exactDuplicate),
      recommendation: evaluateNextSetReadiness({
        feedback: snapshot.feedback,
        sessionId: normalized.sessionId,
        now: input.now,
      }),
    };
  }
  const isSessionSummary =
    normalized.context?.setId === undefined &&
    normalized.context?.setNumber === undefined &&
    normalized.targetMuscleReadiness === undefined &&
    normalized.breathingReadiness === undefined &&
    normalized.generalReadiness === undefined &&
    normalized.supportingReadiness === undefined;
  const latest = latestFeedbackPerSession(
    snapshot.feedback.filter(
      (item) =>
        item.sessionId === normalized.sessionId &&
        item.context?.setId === undefined &&
        item.context?.setNumber === undefined &&
        item.targetMuscleReadiness === undefined &&
        item.breathingReadiness === undefined &&
        item.generalReadiness === undefined &&
        item.supportingReadiness === undefined,
    ),
  ).find((item) => item.sessionId === normalized.sessionId);
  const latestFeedbackTime = snapshot.feedback.reduce(
    (latest, item) => Math.max(latest, Date.parse(item.createdAt)),
    0,
  );
  const createdAt = new Date(Math.max(input.now.getTime(), latestFeedbackTime + 1)).toISOString();
  const feedback: TrainingFeedback & { record_type: string } = {
    id: input.createId(),
    record_type: 'session_feedback',
    ...normalized,
    ...(normalized.correctsObservationId
      ? {}
      : isSessionSummary && latest
        ? { correctsObservationId: latest.id }
        : {}),
    createdAt,
  };
  await commitTrainingMutation(
    input.records,
    input.subject,
    admission,
    'feedback_insert',
    feedback,
  );
  return {
    kind: 'recorded',
    feedback,
    recommendation: evaluateNextSetReadiness({
      feedback: [...snapshot.feedback, feedback],
      sessionId: feedback.sessionId,
      now: input.now,
    }),
  };
}

export type SwapConstraints = {
  /** Session-only equipment loss; never rewrites stored setup preferences. */
  unavailableEquipment?: string[];
  /** Extra items the user explicitly confirmed are present (e.g. an EZ bar). */
  declaredEquipment?: string[];
  /** Concern tags that rule a variant out regardless of equipment. */
  excludedConcerns?: string[];
  preferTorsoSupport?: boolean;
  maxTrunkDemand?: TrunkDemandLevel;
};

export type SwapExerciseInput = SwapConstraints & {
  sessionId: string;
  exerciseId: string;
  /** Optional reviewed catalog variant to use; otherwise the best-ranked candidate. */
  toVariantId?: string;
};

export type SwapExerciseResult =
  | {
      kind: 'swapped';
      swap: ExerciseSwapRecord;
      exercise: ExercisePrescription;
      diff: string[];
    }
  | { kind: 'program_not_enrolled' }
  | { kind: 'session_not_found' }
  | { kind: 'session_not_active' }
  | { kind: 'exercise_not_found' }
  | { kind: 'variant_not_found' }
  | { kind: 'variant_ineligible'; missing: CatalogEquipment[] }
  | { kind: 'no_feasible_alternative' }
  | { kind: 'rejected' };

function swapDiff(from: ExercisePrescription, to: ExercisePrescription): string[] {
  const diff = [`name: ${from.name} -> ${to.name}`];
  const muscles = new Set([
    ...Object.keys(from.muscleContribution),
    ...Object.keys(to.muscleContribution),
  ]);
  for (const muscle of muscles) {
    const before = Number(from.muscleContribution[muscle as keyof typeof from.muscleContribution]);
    const after = Number(to.muscleContribution[muscle as keyof typeof to.muscleContribution]);
    if (before !== after) diff.push(`${muscle} contribution: ${before} -> ${after}`);
  }
  return diff;
}

/** Replaces one prescribed movement with an eligible catalog variant of the
 * same primary muscle. The swap is stored once (additive) so it persists for
 * the rest of the block; sets, rep range, RIR and schedule are untouched. */
export async function swapExercise(input: {
  records: NativeProductRecordsPort;
  subject: string;
  now: Date;
  swap: SwapExerciseInput;
  admission?: TrainingMutationAdmission;
}): Promise<SwapExerciseResult> {
  const { records, subject, swap } = input;
  const admission = input.admission ?? (await captureTrainingAdmission(records, subject));
  if (!admission) return { kind: 'program_not_enrolled' };
  const [snapshot, sessions] = await Promise.all([
    loadTrainingRecords(records, subject),
    pullAllTrainingRecords(records, subject, 'training_sessions'),
  ]);
  const setup = snapshot.setup;
  if (!setup) return { kind: 'program_not_enrolled' };
  requireAdmittedSetup(admission, setup);
  const sessionRecord = sessions.find((record) => record.id === swap.sessionId);
  if (
    !sessionRecord ||
    sessionRecord.deleted_at !== null ||
    !isWorkoutSessionRecord(sessionRecord) ||
    sessionRecord.programSetupId !== setup.id
  ) {
    return { kind: 'session_not_found' };
  }
  const prescription = sessionRecord.prescription;
  if (sessionRecord.status !== 'in_progress' || !prescription || prescription.safetyStop) {
    return { kind: 'session_not_active' };
  }
  const exercise = prescription.exercises.find((item) => item.id === swap.exerciseId);
  if (!exercise) return { kind: 'exercise_not_found' };

  const available = resolveAvailableEquipment({
    profile: setup.equipment,
    declared: [...(setup.declaredEquipment ?? []), ...(swap.declaredEquipment ?? [])],
    sessionUnavailable: swap.unavailableEquipment,
  });
  const eligibility = {
    available,
    excludedConcerns: swap.excludedConcerns,
  };

  let variant;
  if (swap.toVariantId) {
    const requested = catalogVariantById(swap.toVariantId);
    if (!requested || requested.primaryMuscle !== exercise.primaryMuscle) {
      return { kind: 'variant_not_found' };
    }
    if (
      setup.excludedVariantIds?.includes(requested.id) ||
      !isEligibleVariant(requested, eligibility)
    ) {
      return { kind: 'variant_ineligible', missing: missingEquipment(requested, available) };
    }
    variant = requested;
  } else {
    variant = substitutionCandidates({
      primaryMuscle: exercise.primaryMuscle,
      currentExerciseId: exercise.id,
      currentContribution: exercise.muscleContribution,
      available,
      excludedConcerns: swap.excludedConcerns,
      preferTorsoSupport: swap.preferTorsoSupport,
      maxTrunkDemand: swap.maxTrunkDemand,
    }).find((candidate) => !setup.excludedVariantIds?.includes(candidate.id));
    if (!variant) return { kind: 'no_feasible_alternative' };
  }

  const swapped = swappedPrescription(exercise, variant.id, snapshot.logs, exercise.targetRir);
  if (!swapped) return { kind: 'variant_not_found' };

  const programRevisionId =
    typeof sessionRecord.programRevisionId === 'string'
      ? sessionRecord.programRevisionId
      : undefined;
  const swapRecord: ExerciseSwapRecord = {
    id: stableTrainingUuid(
      subject,
      setup.id,
      String(sessionRecord.blockId ?? prescription.week),
      sessionRecord.id,
      exercise.id,
      variant.id,
    ),
    record_type: 'exercise_swap',
    programSetupId: setup.id,
    ...(programRevisionId ? { programRevisionId } : {}),
    blockId: String(sessionRecord.blockId ?? prescription.week),
    sessionId: sessionRecord.id,
    fromExerciseId: exercise.id,
    toVariantId: variant.id,
    deleted_at: null,
    server_updated_at: input.now.toISOString(),
  };
  const savedSwap = await commitTrainingMutation(
    records,
    subject,
    admission,
    'swap_insert',
    swapRecord,
  );
  if (
    !savedSwap ||
    savedSwap.id !== swapRecord.id ||
    savedSwap.deleted_at !== null ||
    savedSwap.record_type !== 'exercise_swap'
  )
    return { kind: 'rejected' };

  const updated = {
    ...prescription,
    exercises: prescription.exercises.map((item) => (item.id === exercise.id ? swapped : item)),
  };
  const savedSession = await commitTrainingMutation(records, subject, admission, 'session_update', {
    ...sessionRecord,
    prescription: updated,
  });
  if (!savedSession || savedSession.id !== sessionRecord.id || savedSession.deleted_at !== null)
    return { kind: 'rejected' };

  return {
    kind: 'swapped',
    swap: swapRecord,
    exercise: swapped,
    diff: swapDiff(exercise, swapped),
  };
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
  admission?: TrainingMutationAdmission;
}): Promise<CorrectSetResult> {
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
    if (existing.reps === set.reps && existing.loadKg === set.loadKg && existing.rir === set.rir) {
      await requireCurrentTrainingAdmission(records, subject, admission);
      return { kind: 'corrected', log: { ...existing, record_type: 'set_log' } };
    }
    return { kind: 'set_conflict' };
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
  await requireCurrentTrainingAdmission(records, subject, admission);
  const saved = await records.correctTrainingSet(
    subject,
    existing.id,
    set.expectedRevision,
    corrected,
  );
  if (!saved) return { kind: 'set_conflict' };
  return { kind: 'corrected', log: saved };
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
  admission?: TrainingMutationAdmission;
}): Promise<WorkoutActionResult> {
  const admission =
    input.admission ?? (await captureTrainingAdmission(input.records, input.subject));
  if (!admission) return { kind: 'program_not_enrolled' };
  const [snapshot, records] = await Promise.all([
    loadTrainingRecords(input.records, input.subject),
    pullAllTrainingRecords(input.records, input.subject, 'training_sessions'),
  ]);
  const setup = snapshot.setup;
  if (!setup) return { kind: 'program_not_enrolled' };
  requireAdmittedSetup(admission, setup);
  const record = records.find((candidate) => candidate.id === input.sessionId) as
    MutableSessionRecord | undefined;
  if (
    !record ||
    record.deleted_at !== null ||
    !isWorkoutSessionRecord(record) ||
    record.programSetupId !== setup.id ||
    !record.prescription
  )
    return { kind: 'session_not_found' };
  const session = record.prescription;
  const sessionLogs = logsForSession(snapshot.logs, session.id);
  const priorEvent = session.executionEvents?.find((event) => event.id === input.eventId);
  if (priorEvent) {
    await requireCurrentTrainingAdmission(input.records, input.subject, admission);
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
              equipment: setup.equipment,
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
      status = completedTrainingSession(session, sessionLogs) ? 'completed' : 'ended';
      event = { id: input.eventId, kind: 'ended', createdAt: input.now.toISOString() };
      break;
  }

  if (event.kind === 'skipped' && exercises.length === 0) status = 'ended';

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
  await requireCurrentTrainingAdmission(input.records, input.subject, admission);
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
