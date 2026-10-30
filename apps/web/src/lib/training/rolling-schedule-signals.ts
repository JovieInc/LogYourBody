import { catalogVariantById } from './catalog';
import { exerciseDemands, OPTIMIZER_RULES } from './optimizer-rules';
import { MUSCLE_GROUPS, type MuscleGroup, type SetLog } from './types';
import type { PlanExercise } from './optimizer';
import type {
  Observation,
  RollingScheduleContext,
  RollingScheduleReview,
  ScheduledWork,
} from './rolling-schedule-schema';

export const emptyVolume = () =>
  Object.fromEntries(MUSCLE_GROUPS.map((muscle) => [muscle, 0])) as Record<MuscleGroup, number>;
export const HOUR = 3600000;
export const WEEK = 7 * 24 * HOUR;

export function contributions(
  exercise: Pick<PlanExercise, 'id' | 'primaryMuscle' | 'muscleContribution'>,
) {
  // The catalog owns compound overlap. A supplied primary-muscle label cannot erase it.
  return (
    catalogVariantById(exercise.id)?.muscleContribution ??
    exercise.muscleContribution ?? { [exercise.primaryMuscle]: 1 }
  );
}

export function affects(observation: Observation, exercise: PlanExercise): boolean {
  const demands = exerciseDemands(OPTIMIZER_RULES, exercise.id);
  switch (observation.scope) {
    case 'whole_body':
      return true;
    case 'exercise':
      return observation.exerciseId === exercise.id;
    case 'muscle':
      return !!observation.muscle && (contributions(exercise)[observation.muscle] ?? 0) > 0;
    case 'grip':
      return demands.grip !== 'none';
    case 'trunk':
      return demands.trunk?.level !== 'low';
  }
}

export function attendanceChoice(
  context: RollingScheduleContext,
  logs: SetLog[],
): RollingScheduleReview['attendanceChoice'] {
  const now = Date.parse(context.asOf);
  const weeks = Math.min(4, Math.floor((now - Date.parse(context.attendanceSince)) / WEEK));
  if (weeks < 2) return null;
  const oldest = now - weeks * WEEK;
  const counts = Array.from({ length: weeks }, (_, index) => {
    const start = oldest + index * WEEK;
    return new Set(
      context.history
        .filter((row) => {
          const at = Date.parse(row.startedAt);
          return (
            at >= start &&
            at < start + WEEK &&
            (row.outcome === 'completed' || row.outcome === 'partial') &&
            logs.some((log) => log.sessionId === row.id)
          );
        })
        .map((row) => row.visitId),
    ).size;
  });
  // A single disrupted week is not a pattern. No unreviewed one-visit program.
  const achieved = counts.at(-1)!;
  const runStart = counts.findLastIndex((count) => count !== achieved) + 1;
  const pattern = counts.slice(runStart);
  if (
    !achieved ||
    achieved >= context.requestedVisitsPerWeek ||
    pattern.length < 2 ||
    context.history.some(
      (row) => row.outcome === 'unknown' && Date.parse(row.startedAt) >= oldest + runStart * WEEK,
    )
  )
    return null;
  return {
    kind: achieved >= 2 ? 'offer_consolidation' : 'review_capacity',
    requestedVisits: context.requestedVisitsPerWeek,
    observedVisitsPerWeek: pattern,
    suggestedVisits: achieved >= 2 ? achieved : null,
    applied: false,
    reversible: true,
  };
}