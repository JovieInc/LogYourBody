import type { TrainingMutationAdmission } from '@/lib/ports/training-mutations';
import type {
  NativeProductRecord,
  NativeProductRecordsPort,
} from '@/lib/ports/native-product-records';
import { reviewExerciseSelection, selectionContextSchema } from './selection';
import {
  captureTrainingAdmission,
  requireAdmittedSetup,
  requireCurrentTrainingAdmission,
} from './mutation-admission';
import { completedTrainingSession, isEligibleExerciseSubstitution } from './engine';
import { isWorkoutSessionRecord, loadTrainingRecords, pullAllTrainingRecords } from './service';
import type {
  ExercisePrescription,
  ExerciseSelectionContext,
  Session,
  SetLog,
  WorkoutSessionEvent,
} from './types';

export type WorkoutActionInput =
  | { kind: 'equipment_unavailable'; exerciseId: string }
  | {
      kind: 'swap';
      exerciseId: string;
      replacementExerciseId: string;
      selectionContext?: ExerciseSelectionContext;
    }
  | { kind: 'restore_swap'; swapEventId: string }
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
    case 'swap': {
      if (!current || current.id !== input.action.exerciseId)
        return { kind: 'stale_current_exercise' };
      const context = input.action.selectionContext;
      const completed = sessionLogs.filter((log) => log.exerciseId === current.id);
      if (completed.length && !context) return { kind: 'no_eligible_substitution' };
      const replacementId = input.action.replacementExerciseId;
      const review =
        context && selectionContextSchema.safeParse(context).success
          ? reviewExerciseSelection(snapshot, session, current.id, context)
          : null;
      const option = review?.options.find((item) => item.variantId === replacementId);
      if (context && (!option || review?.status !== 'suggested'))
        return { kind: 'no_eligible_substitution' };
      const variant = option?.setup;
      const replacement = variant
        ? {
            ...current,
            id: variant.id,
            name: variant.name,
            muscleContribution: variant.muscleContribution,
            targetLoadKg: null,
            progression: 'hold' as const,
            targetReps: current.repRange.min,
            loadInstruction: 'Establish a comfortable starting load for this variant.',
          }
        : (current.substitutions ?? []).find(
            (candidate) =>
              candidate.id === replacementId &&
              !exercises.some((exercise) => exercise.id === candidate.id) &&
              isEligibleExerciseSubstitution({
                exercise: current,
                candidate,
                equipment: setup.equipment,
                constraints: setup.delegated?.inputs,
              }),
          );
      if (!replacement) return { kind: 'no_eligible_substitution' };
      // Preserve every completed identity; only remaining sets move to the trial.
      if (completed.some((log) => log.setNumber > completed.length))
        return { kind: 'no_eligible_substitution' };
      exercises = exercises.flatMap((exercise) =>
        exercise.id === current.id
          ? [
              ...(completed.length ? [{ ...current, sets: completed.length }] : []),
              {
                ...replacement,
                sets: current.sets - completed.length,
                substitutions: current.substitutions.filter(
                  (candidate) => candidate.id !== replacement.id,
                ),
              },
            ]
          : [exercise],
      );
      event = {
        id: input.eventId,
        kind: 'substituted',
        exerciseId: current.id,
        replacementExerciseId: replacement.id,
        createdAt: input.now.toISOString(),
        ...(context ? { selectionContext: context, previousExercise: current } : {}),
      };
      break;
    }
    case 'restore_swap': {
      const prior = (session.executionEvents ?? []).find(
        (item) => input.action.kind === 'restore_swap' && item.id === input.action.swapEventId,
      );
      if (
        !prior?.selectionContext ||
        !prior.previousExercise ||
        !prior.replacementExerciseId ||
        session.executionEvents.some((item) => item.restoresEventId === prior.id) ||
        sessionLogs.some((log) => log.exerciseId === prior.replacementExerciseId) ||
        !session.exercises.some((item) => item.id === prior.replacementExerciseId)
      )
        return { kind: 'no_eligible_substitution' };
      exercises = exercises.flatMap((exercise) =>
        exercise.id === prior.exerciseId
          ? []
          : exercise.id === prior.replacementExerciseId
            ? [prior.previousExercise!]
            : [exercise],
      );
      event = {
        id: input.eventId,
        kind: 'swap_restored',
        createdAt: input.now.toISOString(),
        exerciseId: prior.replacementExerciseId,
        replacementExerciseId: prior.exerciseId,
        restoresEventId: prior.id,
      };
      break;
    }
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
              constraints: setup.delegated?.inputs,
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
