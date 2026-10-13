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
import { latestFeedbackPerSession, validTrainingFeedback, validateSetLog } from './engine';
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
    await commitTrainingMutation(records, subject, admission, 'session_update', {
      ...sessionRecord,
      status: 'completed',
      completedAt,
    });
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
    declared: swap.declaredEquipment,
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
    if (!isEligibleVariant(requested, eligibility)) {
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
    })[0];
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
