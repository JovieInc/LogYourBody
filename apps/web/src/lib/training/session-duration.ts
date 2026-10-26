import type { NextEligibleSession } from './rolling-session';
import { MUSCLE_GROUPS, type MuscleGroup, type Session } from './types';

export type SessionTiming = {
  warmUpSeconds: number;
  equipmentTransitionSeconds: number;
  exercises: Record<
    string,
    {
      /** Estimate for one complete prescribed set, including both sides if unilateral. */
      setSeconds: number;
      restSeconds: number;
      /** Exact station/setup identity; two different machines are different stations. */
      stationId: string;
    }
  >;
};

export type SetValueSignal = {
  /** Supplied by the prescribing engine; positive means the set remains productive. */
  marginalValue: number;
  fatigueLimited?: boolean;
};

export type SessionRecoveryLimit = Partial<
  Record<
    MuscleGroup,
    {
      /** Absolute session budget, including fractional compound contributions. */
      maxFractionalSets: number;
      /** Optional effort limit expressed as minimum repetitions in reserve. */
      minimumRir?: number;
    }
  >
>;

export type SessionDurationInput = {
  session: Session;
  eligibility: NextEligibleSession;
  timing: SessionTiming;
  /** One signal per candidate set, in prescription order. No signal is inferred. */
  setSignals: Record<string, readonly SetValueSignal[]>;
  priorityMuscles: readonly MuscleGroup[];
  timeCapMinutes?: number | null;
  recoveryLimit?: SessionRecoveryLimit;
  actualDurationMinutes?: number | null;
};

export type SessionDuration = {
  warmUpSeconds: number;
  setSeconds: number;
  restSeconds: number;
  transitionSeconds: number;
  totalSeconds: number;
  minutes: number;
};

export type SessionDurationReason =
  | 'marginal_benefit_retained'
  | 'marginal_value_exhausted'
  | 'fatigue_limit_reached'
  | 'recovery_limit_applied'
  | 'time_cap_applied'
  | 'priority_touches_do_not_fit'
  | 'no_productive_sets'
  | 'session_unavailable';

export type SessionDurationPlan = {
  status: 'planned' | 'abbreviated' | 'unavailable';
  session: Session | null;
  /** Duration never establishes or changes eligibility/readiness. */
  eligibility: NextEligibleSession;
  duration: SessionDuration;
  requiredDurationMinutes: number | null;
  actualDurationMinutes: number | null;
  actualMinusPlannedMinutes: number | null;
  omittedPriorityMuscles: MuscleGroup[];
  reasonCodes: SessionDurationReason[];
};

const nonnegative = (value: number) => Number.isFinite(value) && value >= 0;
const muscleIsValid = (muscle: string) => (MUSCLE_GROUPS as readonly string[]).includes(muscle);

function assertInput(input: SessionDurationInput): void {
  const { session, timing, recoveryLimit } = input;
  const validOptionalMinutes = (minutes: number | null | undefined, allowZero: boolean) =>
    minutes == null || (nonnegative(minutes) && (allowZero || minutes > 0));
  if (
    !nonnegative(timing.warmUpSeconds) ||
    !nonnegative(timing.equipmentTransitionSeconds) ||
    !validOptionalMinutes(input.timeCapMinutes, false) ||
    !validOptionalMinutes(input.actualDurationMinutes, true) ||
    input.priorityMuscles.some((muscle) => !muscleIsValid(muscle)) ||
    new Set(session.exercises.map((exercise) => exercise.id)).size !== session.exercises.length
  )
    throw new Error('session_duration_input_invalid');

  for (const exercise of session.exercises) {
    const estimate = timing.exercises[exercise.id];
    const signals = input.setSignals[exercise.id];
    if (
      !Number.isInteger(exercise.sets) ||
      exercise.sets < 1 ||
      !nonnegative(exercise.targetRir) ||
      !Number.isInteger(exercise.targetRir) ||
      exercise.targetRir > 6 ||
      !muscleIsValid(exercise.primaryMuscle) ||
      !Object.entries(exercise.muscleContribution).every(
        ([muscle, fraction]) => muscleIsValid(muscle) && nonnegative(fraction) && fraction <= 1,
      ) ||
      !estimate ||
      !nonnegative(estimate.setSeconds) ||
      estimate.setSeconds === 0 ||
      !nonnegative(estimate.restSeconds) ||
      !estimate.stationId?.trim() ||
      !signals ||
      signals.length < exercise.sets ||
      !signals.every(
        (signal) =>
          Number.isFinite(signal.marginalValue) &&
          (signal.fatigueLimited === undefined || typeof signal.fatigueLimited === 'boolean'),
      )
    )
      throw new Error('session_duration_prescription_invalid');
  }
  for (const [muscle, limit] of Object.entries(recoveryLimit ?? {})) {
    if (
      !muscleIsValid(muscle) ||
      !limit ||
      !nonnegative(limit.maxFractionalSets) ||
      (limit.minimumRir !== undefined &&
        (!Number.isInteger(limit.minimumRir) || limit.minimumRir < 0 || limit.minimumRir > 6))
    )
      throw new Error('session_duration_recovery_limit_invalid');
  }
}

/** Rest is counted between sets of the same exercise, never after its last set.
 * A station change adds transition time separately. No rounding is used to fit a cap. */
function deriveDuration(exercises: Session['exercises'], timing: SessionTiming): SessionDuration {
  let setSeconds = 0;
  let restSeconds = 0;
  let transitionSeconds = 0;
  let previousStation: string | null = null;
  for (const exercise of exercises) {
    const estimate = timing.exercises[exercise.id]!;
    setSeconds += exercise.sets * estimate.setSeconds;
    restSeconds += (exercise.sets - 1) * estimate.restSeconds;
    if (previousStation !== null && previousStation !== estimate.stationId) {
      transitionSeconds += timing.equipmentTransitionSeconds;
    }
    previousStation = estimate.stationId;
  }
  const warmUpSeconds = exercises.length ? timing.warmUpSeconds : 0;
  const totalSeconds = warmUpSeconds + setSeconds + restSeconds + transitionSeconds;
  if (!Number.isFinite(totalSeconds)) throw new Error('session_duration_estimate_invalid');
  return {
    warmUpSeconds,
    setSeconds,
    restSeconds,
    transitionSeconds,
    totalSeconds,
    minutes: totalSeconds / 60,
  };
}

function fractionalSets(exercises: Session['exercises'], muscle: MuscleGroup): number {
  return exercises.reduce(
    (sum, exercise) => sum + exercise.sets * (exercise.muscleContribution[muscle] ?? 0),
    0,
  );
}

/** Remove only a final set, preserving contiguous canonical set numbers. Ties
 * remove later exercises first; neither host locale nor object-key order ranks work. */
function removeLowestValueSet(
  exercises: Session['exercises'],
  signals: SessionDurationInput['setSignals'],
  canRemove: (exercise: Session['exercises'][number]) => boolean,
): boolean {
  let candidate = -1;
  let lowest = Infinity;
  exercises.forEach((exercise, index) => {
    const value = signals[exercise.id]![exercise.sets - 1]!.marginalValue;
    if (canRemove(exercise) && value <= lowest) {
      candidate = index;
      lowest = value;
    }
  });
  if (candidate < 0) return false;
  const exercise = exercises[candidate]!;
  exercise.sets -= 1;
  if (exercise.sets === 0) exercises.splice(candidate, 1);
  return true;
}

/** LYB-290: transform already-prescribed candidate work, never add work to fill
 * available time. Limits are absolute so reapplying them cannot compound a cut.
 * This pure module does not persist sessions, advance the queue or infer recovery. */
export function planSessionDuration(input: SessionDurationInput): SessionDurationPlan {
  assertInput(input);
  const reasons = new Set<SessionDurationReason>();
  let exercises: Session['exercises'] = [];
  if (input.session.safetyStop || input.session.executionPaused) {
    reasons.add('session_unavailable');
  } else {
    exercises = input.session.exercises.flatMap((exercise) => {
      const signals = input.setSignals[exercise.id]!;
      let sets = 0;
      for (const signal of signals.slice(0, exercise.sets)) {
        if (signal.fatigueLimited) {
          reasons.add('fatigue_limit_reached');
          break;
        }
        if (signal.marginalValue <= 0) {
          reasons.add('marginal_value_exhausted');
          break;
        }
        sets += 1;
      }
      return sets ? [{ ...exercise, sets }] : [];
    });
  }

  const limits = input.recoveryLimit ?? {};
  // Evaluate all exceeded muscles together so the order of supplied limits is irrelevant.
  for (;;) {
    const exceeded = MUSCLE_GROUPS.filter((muscle) => {
      const limit = limits[muscle];
      return limit !== undefined && fractionalSets(exercises, muscle) > limit.maxFractionalSets;
    });
    if (!exceeded.length) break;
    removeLowestValueSet(exercises, input.setSignals, (exercise) =>
      exceeded.some((muscle) => (exercise.muscleContribution[muscle] ?? 0) > 0),
    );
    reasons.add('recovery_limit_applied');
  }
  exercises = exercises.map((exercise) => {
    const targetRir = MUSCLE_GROUPS.reduce(
      (rir, muscle) =>
        (exercise.muscleContribution[muscle] ?? 0) > 0
          ? Math.max(rir, limits[muscle]?.minimumRir ?? rir)
          : rir,
      exercise.targetRir,
    );
    if (targetRir === exercise.targetRir) return exercise;
    reasons.add('recovery_limit_applied');
    return { ...exercise, targetRir, progression: 'hold', loadInstruction: null };
  });

  // A time limit preserves one direct touch per productive priority muscle in this
  // exposure. Recovery and productivity limits take precedence over that floor.
  const protectedMuscles = new Set(
    input.priorityMuscles.filter((muscle) =>
      exercises.some((exercise) => exercise.primaryMuscle === muscle),
    ),
  );
  const cap = input.timeCapMinutes;
  if (cap != null) {
    while (deriveDuration(exercises, input.timing).totalSeconds > cap * 60) {
      reasons.add('time_cap_applied');
      const removed = removeLowestValueSet(
        exercises,
        input.setSignals,
        (exercise) =>
          exercise.sets > 1 ||
          !protectedMuscles.has(exercise.primaryMuscle) ||
          exercises.some(
            (other) => other !== exercise && other.primaryMuscle === exercise.primaryMuscle,
          ),
      );
      if (!removed) {
        reasons.add('priority_touches_do_not_fit');
        exercises = [];
        break;
      }
    }
  }

  // A stored alternative must not restore sets or effort removed by these limits.
  exercises = exercises.map((exercise) => ({
    ...exercise,
    substitutions: exercise.substitutions.map((alternative) => ({
      ...alternative,
      sets: Math.min(alternative.sets, exercise.sets),
      targetRir: Math.max(alternative.targetRir, exercise.targetRir),
    })),
  }));
  const duration = deriveDuration(exercises, input.timing);
  if (exercises.length) reasons.add('marginal_benefit_retained');
  else reasons.add('no_productive_sets');
  const actual = input.actualDurationMinutes ?? null;
  return {
    status: exercises.length
      ? reasons.has('time_cap_applied')
        ? 'abbreviated'
        : 'planned'
      : 'unavailable',
    session: exercises.length ? { ...input.session, exercises } : null,
    eligibility: { ...input.eligibility },
    duration,
    requiredDurationMinutes: cap ?? null,
    actualDurationMinutes: actual,
    actualMinusPlannedMinutes: actual === null ? null : actual - duration.minutes,
    omittedPriorityMuscles: [...new Set(input.priorityMuscles)].filter(
      (muscle) => !exercises.some((exercise) => exercise.primaryMuscle === muscle),
    ),
    reasonCodes: [...reasons],
  };
}
