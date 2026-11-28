import type { NativeProductRecord } from '@/lib/ports/native-product-records';
import { catalogVariantById, isEligibleVariant } from './catalog';
import { eligibleForProgram } from './delegated-planning';
import { progressionForExercise } from './engine';
import { latestSwapState, readNextPrescriptionExercise } from './swap-persistence';
import type { ExercisePrescription, Session, SetLog, TrainingProgramSetup } from './types';

/** Rebuilds one exercise slot as a reviewed variant. Sets, rep range, RIR and
 * schedule are preserved; progression is computed from the variant's own
 * logged history, never transferred from the original exercise. */
export function swappedPrescription(
  exercise: ExercisePrescription,
  variantId: string,
  logs: SetLog[],
  targetRir: number,
): ExercisePrescription | null {
  const variant = catalogVariantById(variantId);
  if (!variant || variant.primaryMuscle !== exercise.primaryMuscle) return null;
  const progression = progressionForExercise(variant.id, logs, targetRir);
  return {
    ...exercise,
    id: variant.id,
    name: variant.name,
    muscleContribution: variant.muscleContribution,
    targetReps: progression.targetReps,
    targetLoadKg: progression.targetLoadKg,
    loadInstruction: progression.loadInstruction,
    progression: progression.action,
  };
}

/** Applies one stored swap, or the exercise restored by rollback, to a built session. */
export function withPersistedSwap(
  session: Session,
  sessions: readonly NativeProductRecord[],
  setup: TrainingProgramSetup,
  logs: SetLog[],
): Session {
  const state = latestSwapState(sessions, setup.id);
  if (!state || session.safetyStop) return session;
  let changed = false;
  const exercises = session.exercises.map((exercise) => {
    const nextId = readNextPrescriptionExercise(exercise.id, state);
    if (nextId === exercise.id) return exercise;
    const variant = catalogVariantById(nextId);
    if (!variant || variant.primaryMuscle !== exercise.primaryMuscle) return exercise;
    if (setup.excludedVariantIds?.includes(nextId)) return exercise;
    if (setup.delegated && !eligibleForProgram(nextId, setup.delegated.inputs)) return exercise;
    if (
      !state.rolledBack &&
      !isEligibleVariant(variant, { available: new Set(state.confirmedEquipment) })
    )
      return exercise;
    const swapped = swappedPrescription(exercise, nextId, logs, exercise.targetRir);
    if (!swapped) return exercise;
    changed = true;
    return swapped;
  });
  return changed ? { ...session, exercises } : session;
}
