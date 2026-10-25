import type { RecoveryTrial } from './recovery-contract';
import type { Session } from './types';
import { RECOVERY_POLICY } from './recovery';

/** Only a reviewed, applied, current-block reduction affects a future exposure.
 * No new slots, visits, loads, reps, exercise variants, or other muscle goals. */
export function applyRecoveryTrials(
  session: Session,
  trials: RecoveryTrial[],
  context: {
    setupId: string;
    blockId: string;
    now: Date;
  },
): Session {
  if (session.safetyStop) return session;
  const active = trials.filter(
    (trial) =>
      trial.state === 'applied' &&
      trial.programSetupId === context.setupId &&
      trial.blockId === context.blockId &&
      trial.policyVersion === RECOVERY_POLICY.version &&
      trial.appliedAt &&
      Date.parse(trial.appliedAt) <= context.now.getTime(),
  );
  const exercises = session.exercises.map((exercise) => {
    const trial = active.find(
      (item) => item.exerciseId === exercise.id && item.muscle === exercise.primaryMuscle,
    );
    const change = trial?.inference.change;
    if (
      !trial ||
      trial.inference.action !== 'reduce' ||
      !change ||
      change.to !== RECOVERY_POLICY.reducedSets ||
      change.to >= change.from
    )
      return exercise;
    return {
      ...exercise,
      sets: Math.min(exercise.sets, change.to),
      substitutions: exercise.substitutions.map((item) => ({
        ...item,
        sets: Math.min(item.sets, change.to),
      })),
    };
  });
  const changed = exercises.some((exercise, index) => exercise !== session.exercises[index]);
  return changed
    ? {
        ...session,
        exercises,
        explanation:
          'Applied recovery trial: use the reviewed reduced work. Review the next comparable exposure; pause and review adverse symptoms.',
        evidenceIds: [...new Set([...session.evidenceIds, ...RECOVERY_POLICY.evidenceIds])],
      }
    : session;
}
