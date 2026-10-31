import type { TrainingMutationAdmission } from '@/lib/ports/training-mutations';
import { eligibleForProgram } from './delegated-planning';
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
import type { ExercisePrescription, SetLog, TrainingFeedback } from './types';

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
    normalized.context?.exerciseId === undefined &&
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
        item.context?.exerciseId === undefined &&
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
    excludedConcerns: [
      ...new Set([
        ...(swap.excludedConcerns ?? []),
        ...(setup.delegated?.inputs.limitations ?? []),
      ]),
    ],
  };

  let variant;
  if (swap.toVariantId) {
    const requested = catalogVariantById(swap.toVariantId);
    if (!requested || requested.primaryMuscle !== exercise.primaryMuscle) {
      return { kind: 'variant_not_found' };
    }
    if (
      setup.excludedVariantIds?.includes(requested.id) ||
      !isEligibleVariant(requested, eligibility) ||
      (setup.delegated && !eligibleForProgram(requested.id, setup.delegated.inputs))
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
      excludedConcerns: eligibility.excludedConcerns,
      preferTorsoSupport: swap.preferTorsoSupport,
      maxTrunkDemand: swap.maxTrunkDemand,
    }).find(
      (candidate) =>
        !setup.excludedVariantIds?.includes(candidate.id) &&
        (!setup.delegated || eligibleForProgram(candidate.id, setup.delegated.inputs)),
    );
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

export type UndoSetInput = {
  sessionId: string;
  exerciseId: string;
  setNumber: number;
  undoId: string;
  expectedRevision: number;
};

export type UndoSetResult =
  | { kind: 'undone'; log: NativeProductRecord | (SetLog & { record_type: string }) }
  | { kind: 'program_not_enrolled' }
  | { kind: 'session_not_found' }
  | { kind: 'set_not_found' }
  | { kind: 'set_conflict' }
  | { kind: 'undo_unavailable' }
  | { kind: 'rejected' };

type SetValues = Pick<SetLog, 'reps' | 'loadKg' | 'rir'>;

function sameSetValues(left: SetValues, right: SetValues): boolean {
  return left.reps === right.reps && left.loadKg === right.loadKg && left.rir === right.rir;
}

function restoredValuesValid(values: SetValues): boolean {
  return (
    Number.isInteger(values.reps) &&
    values.reps >= 1 &&
    values.reps <= 50 &&
    Number.isInteger(values.rir) &&
    values.rir >= 0 &&
    values.rir <= 6 &&
    (values.loadKg === null ||
      (typeof values.loadKg === 'number' &&
        Number.isFinite(values.loadKg) &&
        values.loadKg >= 0 &&
        values.loadKg <= 500))
  );
}

/** An applied undo is idempotent only while it is still the latest correction and
 * the row still holds the values that correction restored. */
function appliedUndo(existing: SetLog, undoId: string): SetLog | 'conflict' | undefined {
  const corrections = existing.corrections ?? [];
  const undoIndex = corrections.findIndex((item) => item.id === undoId);
  if (undoIndex < 0) return undefined;
  const prior = corrections[undoIndex - 1];
  if (undoIndex !== corrections.length - 1 || !prior || !sameSetValues(existing, prior.previous)) {
    return 'conflict';
  }
  return existing;
}

/** Reverses the latest correction of one stable set. The client names the undo,
 * and the server restores the previous audited values. */
export async function undoTrainingSet(input: {
  records: NativeProductRecordsPort;
  subject: string;
  now: Date;
  set: UndoSetInput;
  admission?: TrainingMutationAdmission;
}): Promise<UndoSetResult> {
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
  const existing = snapshot.logs.find(
    (log) =>
      log.sessionId === set.sessionId &&
      log.exerciseId === set.exerciseId &&
      log.setNumber === set.setNumber,
  );
  if (!existing) return { kind: 'set_not_found' };
  const already = appliedUndo(existing, set.undoId);
  if (already === 'conflict') return { kind: 'set_conflict' };
  if (already) {
    await requireCurrentTrainingAdmission(records, subject, admission);
    return { kind: 'undone', log: { ...already, record_type: 'set_log' } };
  }
  const corrections = existing.corrections ?? [];
  if (corrections.length === 0) return { kind: 'undo_unavailable' };
  if ((existing.revision ?? 0) !== set.expectedRevision) return { kind: 'set_conflict' };
  const latest = corrections[corrections.length - 1];
  if (!latest || !restoredValuesValid(latest.previous)) return { kind: 'undo_unavailable' };
  if (!records.correctTrainingSet) return { kind: 'rejected' };
  const restored = latest.previous;
  const undone: SetLog & { record_type: string } = {
    ...existing,
    record_type: 'set_log',
    reps: restored.reps,
    loadKg: restored.loadKg,
    rir: restored.rir,
    revision: (existing.revision ?? 0) + 1,
    corrections: [
      ...corrections,
      {
        id: set.undoId,
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
    undone,
  );
  if (!saved) {
    const replay = await loadTrainingRecords(records, subject);
    const current = replay.logs.find((log) => log.id === existing.id);
    const applied = current ? appliedUndo(current, set.undoId) : undefined;
    if (applied && applied !== 'conflict') {
      await requireCurrentTrainingAdmission(records, subject, admission);
      return { kind: 'undone', log: { ...applied, record_type: 'set_log' } };
    }
    return { kind: 'set_conflict' };
  }
  return { kind: 'undone', log: saved };
}

export {
  applyWorkoutAction,
  type WorkoutActionInput,
  type WorkoutActionResult,
} from './workout-actions';
