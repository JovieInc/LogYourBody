import { z } from 'zod';
import { CATALOG_EQUIPMENT, catalogVariantById, isEligibleVariant } from './catalog';
import { CONTROLLER_POLICY } from './controller';
import { applyRecoveryTrials } from './recovery-application';
import { recoveryTrialSchema } from './recovery-contract';
import { exerciseDemands, OPTIMIZER_RULES } from './optimizer-rules';
import { rollingSessionOrder } from './rolling-session';
import { planSessionDuration } from './session-duration';
import {
  MUSCLE_GROUPS,
  MUSCLE_TARGETS,
  type MuscleGroup,
  type Session,
  type SetLog,
} from './types';
import type { PlanExercise, PlanSession } from './optimizer';

const instant = z.string().datetime({ offset: true });
const nonnegative = z.number().finite().nonnegative();
const identity = z.string().min(1).max(200);
const contribution = z.partialRecord(z.enum(MUSCLE_GROUPS), z.number().min(0).max(1));
const timeZone = z.string().refine((value) => {
  try {
    new Intl.DateTimeFormat('en', { timeZone: value });
    return true;
  } catch {
    return false;
  }
}, 'invalid_time_zone');

/** This context extends the canonical optimizer. It never creates prescriptions,
 * adds opportunities, or claims that elapsed time establishes biological recovery. */
export const rollingScheduleSchema = z
  .object({
    rotationId: identity,
    programSetupId: identity,
    blockId: identity,
    sourceFingerprint: identity.optional(),
    asOf: instant,
    attendanceSince: instant,
    requestedVisitsPerWeek: z.union([
      z.literal(2),
      z.literal(3),
      z.literal(4),
      z.literal(5),
      z.literal(6),
    ]),
    slots: z
      .array(
        z
          .object({
            id: identity,
            scheduledAt: instant,
            timeZone,
            locationId: identity.nullable(),
            groupId: identity,
            visitId: identity,
            kind: z.enum(['visit', 'continuation']),
            continueSessionId: identity.optional(),
            availableEquipment: z.array(z.enum(CATALOG_EQUIPMENT)),
            priorityTargets: z.array(z.enum(MUSCLE_TARGETS)),
            timeCapMinutes: z.number().finite().positive().optional(),
            canceled: z.boolean().optional(),
          })
          .strict(),
      )
      .max(28),
    history: z.array(
      z
        .object({
          id: identity,
          templateId: identity,
          rotationId: identity,
          groupId: identity,
          visitId: identity,
          startedAt: instant,
          endedAt: instant.nullable(),
          outcome: z.enum(['completed', 'partial', 'empty', 'unknown']),
          exercises: z.array(
            z
              .object({
                id: identity,
                primaryMuscle: z.enum(MUSCLE_GROUPS),
                muscleContribution: contribution,
                sets: z.number().int().positive(),
                targetRir: nonnegative,
              })
              .strict(),
          ),
        })
        .strict(),
    ),
    observations: z.array(
      z
        .object({
          id: identity,
          sourceObservationId: identity.optional(),
          at: instant,
          scope: z.enum(['muscle', 'whole_body', 'grip', 'trunk', 'exercise']),
          muscle: z.enum(MUSCLE_GROUPS).optional(),
          exerciseId: identity.optional(),
          state: z.enum(['ready', 'limited', 'unknown']),
          symptom: z.boolean().optional(),
        })
        .strict(),
    ),
    trials: z.array(recoveryTrialSchema),
    /** Scheduling estimates supplied by the engine, never physiological limits. */
    timing: z
      .object({
        warmUpSeconds: nonnegative,
        setSeconds: z.number().finite().positive(),
        restSeconds: nonnegative,
        transitionSeconds: nonnegative,
      })
      .strict(),
  })
  .strict()
  .superRefine((value, ctx) => {
    for (const rows of [value.slots, value.history, value.observations, value.trials]) {
      if (new Set(rows.map((row) => row.id)).size !== rows.length)
        ctx.addIssue({ code: 'custom', message: 'duplicate_schedule_identity' });
    }
    for (const slot of value.slots) {
      if ((slot.kind === 'continuation') !== (slot.continueSessionId !== undefined))
        ctx.addIssue({ code: 'custom', message: 'continuation_identity_required' });
      if (Date.parse(slot.scheduledAt) < Date.parse(value.asOf))
        ctx.addIssue({ code: 'custom', message: 'slot_before_snapshot' });
    }
    for (const row of value.history) {
      if (
        Date.parse(row.startedAt) > Date.parse(value.asOf) ||
        (row.endedAt &&
          (Date.parse(row.endedAt) < Date.parse(row.startedAt) ||
            Date.parse(row.endedAt) > Date.parse(value.asOf))) ||
        new Set(row.exercises.map((exercise) => exercise.id)).size !== row.exercises.length
      )
        ctx.addIssue({ code: 'custom', message: 'invalid_schedule_history' });
    }
  });
export type RollingScheduleContext = z.infer<typeof rollingScheduleSchema>;
type Observation = RollingScheduleContext['observations'][number];
export type ScheduledWork = {
  id: string;
  templateId: string;
  exerciseId: string;
  setNumber: number;
  targetRir: number;
};
type WorkDisposition = { work: ScheduledWork; reason: string };
export type RollingScheduleReview = {
  version: 'rolling-schedule-v1';
  authority: 'self_review_required';
  readiness: 'conditional_not_measured';
  allocations: Array<{
    slotId: string;
    scheduledAt: string;
    timeZone: string;
    locationId: string | null;
    groupId: string;
    visitId: string;
    kind: 'visit' | 'continuation';
    continuedSessionId: string | null;
    templateId: string;
    work: ScheduledWork[];
    durationMinutes: number;
    durationRationale: string;
    observationIds: string[];
    priorWork: Array<{
      setId: string;
      exerciseId: string;
      elapsedHours: number;
      reps: number;
      loadKg: number | null;
      rir: number;
    }>;
    uncertainty: string[];
  }>;
  completedSetIds: string[];
  dropped: WorkDisposition[];
  unallocated: WorkDisposition[];
  tradeoffs: Array<{
    slotId: string | null;
    kind: 'move_reduce_or_rest' | 'request_opportunity';
    reason: string;
  }>;
  trailingVolume: { days7: Record<MuscleGroup, number>; days14: Record<MuscleGroup, number> };
  attendanceChoice: null | {
    kind: 'offer_consolidation' | 'review_capacity';
    requestedVisits: number;
    observedVisitsPerWeek: number[];
    suggestedVisits: number | null;
    applied: false;
    reversible: true;
  };
};

const emptyVolume = () =>
  Object.fromEntries(MUSCLE_GROUPS.map((muscle) => [muscle, 0])) as Record<MuscleGroup, number>;
const HOUR = 3600000;
const WEEK = 7 * 24 * HOUR;

function contributions(
  exercise: Pick<PlanExercise, 'id' | 'primaryMuscle' | 'muscleContribution'>,
) {
  // The catalog owns compound overlap. A supplied primary-muscle label cannot erase it.
  return (
    catalogVariantById(exercise.id)?.muscleContribution ??
    exercise.muscleContribution ?? { [exercise.primaryMuscle]: 1 }
  );
}

function affects(observation: Observation, exercise: PlanExercise): boolean {
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

function attendanceChoice(
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

/** Allocate each remaining approved identity at most once, into user-offered
 * timestamped opportunities. A partial workout retains its original set numbers.
 * This is an optimizer proposal, not another progression or readiness engine. */
export function reviewRollingSchedule(input: {
  sessions: readonly PlanSession[];
  context: RollingScheduleContext;
  logs: readonly SetLog[];
  targetRir: number;
  excludedExerciseIds?: string[];
  excludedConcerns?: string[];
}): RollingScheduleReview {
  const { context, sessions } = input;
  const asOf = Date.parse(context.asOf);
  const histories = new Map(context.history.map((row) => [row.id, row]));
  const logs = [...new Map(input.logs.map((log) => [log.id, log])).values()]
    .filter((log) => histories.has(log.sessionId) && Date.parse(log.completedAt) <= asOf)
    .sort(
      (a, b) => Date.parse(a.completedAt) - Date.parse(b.completedAt) || a.id.localeCompare(b.id),
    );
  const result: RollingScheduleReview = {
    version: 'rolling-schedule-v1',
    authority: 'self_review_required',
    readiness: 'conditional_not_measured',
    allocations: [],
    completedSetIds: logs.map((log) => log.id),
    dropped: [],
    unallocated: [],
    tradeoffs: [],
    trailingVolume: { days7: emptyVolume(), days14: emptyVolume() },
    attendanceChoice: attendanceChoice(context, logs),
  };
  for (const log of logs) {
    const exercise = histories
      .get(log.sessionId)!
      .exercises.find((row) => row.id === log.exerciseId);
    if (!exercise) continue;
    for (const [key, days] of [
      ['days7', 7],
      ['days14', 14],
    ] as const) {
      if (asOf - Date.parse(log.completedAt) >= days * 24 * HOUR) continue;
      for (const muscle of MUSCLE_GROUPS)
        result.trailingVolume[key][muscle] += contributions(exercise)[muscle] ?? 0;
    }
  }
  const counted = context.history.filter(
    (row) => row.rotationId === context.rotationId && logs.some((log) => log.sessionId === row.id),
  );
  const last = [...counted]
    .sort((a, b) => Date.parse(a.startedAt) - Date.parse(b.startedAt) || a.id.localeCompare(b.id))
    .at(-1);
  const order = rollingSessionOrder(
    sessions.map((session) => session.id),
    last?.templateId,
  );
  const pending = new Map<string, ScheduledWork[]>();
  for (const session of sessions) {
    const work = session.exercises
      .flatMap((exercise) =>
        Array.from({ length: exercise.sets }, (_, index) => ({
          id: JSON.stringify([context.rotationId, session.id, exercise.id, index + 1]),
          templateId: session.id,
          exerciseId: exercise.id,
          setNumber: index + 1,
          targetRir: exercise.targetRir ?? input.targetRir,
        })),
      )
      .filter(
        (set) =>
          !counted.some(
            (row) =>
              row.templateId === session.id &&
              logs.some(
                (log) =>
                  log.sessionId === row.id &&
                  log.exerciseId === set.exerciseId &&
                  log.setNumber === set.setNumber,
              ),
          ),
      );
    pending.set(session.id, work);
  }
  const slots = [...context.slots].sort(
    (a, b) => Date.parse(a.scheduledAt) - Date.parse(b.scheduledAt) || a.id.localeCompare(b.id),
  );
  for (const slot of slots) {
    if (slot.canceled) continue;
    const continuation = slot.continueSessionId ? histories.get(slot.continueSessionId) : undefined;
    if (
      slot.kind === 'continuation' &&
      (!continuation ||
        continuation.outcome !== 'partial' ||
        continuation.rotationId !== context.rotationId ||
        continuation.groupId !== slot.groupId ||
        continuation.visitId !== slot.visitId)
    ) {
      result.tradeoffs.push({
        slotId: slot.id,
        kind: 'move_reduce_or_rest',
        reason: 'continuation_context_requires_review',
      });
      continue;
    }
    const visits = new Set([
      ...context.history
        .filter(
          (row) =>
            logs.some((log) => log.sessionId === row.id) &&
            Date.parse(slot.scheduledAt) - Date.parse(row.startedAt) < WEEK,
        )
        .map((row) => row.visitId),
      ...result.allocations
        .filter((row) => Date.parse(slot.scheduledAt) - Date.parse(row.scheduledAt) < WEEK)
        .map((row) => row.visitId),
    ]);
    if (slot.kind === 'visit' && visits.has(slot.visitId)) {
      result.tradeoffs.push({
        slotId: slot.id,
        kind: 'move_reduce_or_rest',
        reason: 'use_explicit_continuation_for_existing_visit',
      });
      continue;
    }
    if (slot.kind === 'visit' && visits.size >= context.requestedVisitsPerWeek) {
      result.tradeoffs.push({
        slotId: slot.id,
        kind: 'request_opportunity',
        reason: 'additional_visit_requires_review',
      });
      continue;
    }
    const fresh = context.observations.filter(
      (row) =>
        Date.parse(row.at) <= asOf &&
        asOf - Date.parse(row.at) <= CONTROLLER_POLICY.staleSignalDays * 24 * HOUR,
    );
    const observationKey = (row: Observation) =>
      JSON.stringify([row.scope, row.muscle, row.exerciseId]);
    const observations = fresh.filter(
      (row) =>
        !fresh.some(
          (other) =>
            observationKey(row) === observationKey(other) &&
            Date.parse(other.at) > Date.parse(row.at),
        ),
    );
    let allocated = false;
    const slotOrder = continuation
      ? [continuation.templateId]
      : [...order].sort((left, right) => {
          const hasPriority = (id: string) =>
            sessions
              .find((session) => session.id === id)
              ?.exercises.some(
                (exercise) =>
                  pending.get(id)?.some((set) => set.exerciseId === exercise.id) &&
                  slot.priorityTargets.some((muscle) =>
                    exerciseDemands(OPTIMIZER_RULES, exercise.id).targets.includes(muscle),
                  ),
              );
          return Number(hasPriority(right)) - Number(hasPriority(left));
        });
    for (const id of slotOrder) {
      const template = sessions.find((session) => session.id === id)!;
      if (!template) continue;
      const remaining = pending.get(id) ?? [];
      if (!remaining.length) continue;
      const baseline: Session = {
        id,
        week: 1,
        slot: sessions.indexOf(template),
        pattern: 'A',
        title: id,
        safetyStop: false,
        explanation: null,
        evidenceIds: [],
        executionRevision: 0,
        executionPaused: false,
        executionEvents: [],
        exercises: template.exercises.map((exercise) => ({
          ...exercise,
          muscleContribution: contributions(exercise),
          targetRir: exercise.targetRir ?? input.targetRir,
          targetReps: 8,
          repRange: { min: 8, max: 12 },
          targetLoadKg: null,
          loadInstruction: null,
          progression: 'hold',
          evidenceIds: [],
          substitutions: [],
        })),
      };
      const reduced = applyRecoveryTrials(baseline, context.trials, {
        setupId: context.programSetupId,
        blockId: context.blockId,
        now: new Date(context.asOf),
      });
      const dropped = remaining.filter(
        (set) =>
          set.setNumber >
          reduced.exercises.find((exercise) => exercise.id === set.exerciseId)!.sets,
      );
      for (const work of dropped)
        result.dropped.push({ work, reason: 'applied_recovery_reduction' });
      let available = remaining.filter((set) => !dropped.includes(set));
      pending.set(id, available);
      const laterPriority = slots
        .filter(
          (later) =>
            !later.canceled &&
            later.groupId === slot.groupId &&
            Date.parse(later.scheduledAt) > Date.parse(slot.scheduledAt),
        )
        .flatMap((later) => later.priorityTargets);
      available = available.filter((set) => {
        const exercise = template.exercises.find((row) => row.id === set.exerciseId)!;
        const variant = catalogVariantById(exercise.id);
        if (
          !variant ||
          exercise.phase === 'warmup' ||
          !isEligibleVariant(variant, {
            available: new Set(slot.availableEquipment),
            excludedExerciseIds: input.excludedExerciseIds,
            excludedConcerns: input.excludedConcerns,
          })
        )
          return false;
        const reviewedReduction = (row: Observation) =>
          row.scope === 'muscle' &&
          !row.symptom &&
          context.trials.some(
            (trial) =>
              trial.state === 'applied' &&
              trial.programSetupId === context.programSetupId &&
              trial.blockId === context.blockId &&
              trial.exerciseId === exercise.id &&
              trial.muscle === row.muscle &&
              trial.inference.action === 'reduce' &&
              trial.inference.change &&
              reduced.exercises.find((item) => item.id === exercise.id)!.sets <=
                trial.inference.change.to &&
              trial.appliedAt &&
              Date.parse(trial.appliedAt) <= asOf &&
              Date.parse(row.at) <= Date.parse(trial.appliedAt) &&
              trial.inference.observationIds.includes(row.sourceObservationId ?? row.id),
          );
        if (
          observations.some(
            (row) =>
              (row.state === 'limited' || row.symptom) &&
              affects(row, exercise) &&
              !reviewedReduction(row),
          )
        )
          return false;
        // Actual work in an earlier split visit can invalidate a later reservation.
        // Session grouping, rather than a date boundary, survives midnight and DST.
        if (
          !continuation &&
          logs.some((log) => {
            const history = histories.get(log.sessionId)!;
            if (history.groupId !== slot.groupId || history.visitId === slot.visitId) return false;
            const previous = history.exercises.find((row) => row.id === log.exerciseId);
            if (!previous) return true;
            const a = contributions(previous);
            const b = contributions(exercise);
            const demands = exerciseDemands(OPTIMIZER_RULES, exercise.id);
            const priorDemands = exerciseDemands(OPTIMIZER_RULES, previous.id);
            return (
              MUSCLE_GROUPS.some((muscle) => (a[muscle] ?? 0) > 0 && (b[muscle] ?? 0) > 0) ||
              (['direct', 'support'].includes(demands.grip) &&
                ['direct', 'support'].includes(priorDemands.grip))
            );
          })
        )
          return false;
        if (
          context.trials.some(
            (trial) =>
              trial.state === 'applied' &&
              trial.programSetupId === context.programSetupId &&
              trial.blockId === context.blockId &&
              trial.exerciseId === exercise.id &&
              trial.appliedAt &&
              Date.parse(trial.appliedAt) <= asOf &&
              ['respace', 'substitute', 'recovery_review'].includes(trial.inference.action),
          )
        )
          return false;
        const demands = exerciseDemands(OPTIMIZER_RULES, exercise.id);
        // Evaluate a user-offered split together; a later opportunity is not a fatigue reset.
        return !laterPriority.some(
          (muscle) =>
            demands.targets.includes(muscle) ||
            demands.assisting?.includes(muscle) ||
            (muscle === 'biceps' && (contributions(exercise).biceps ?? 0) > 0) ||
            (muscle === 'forearms' && demands.grip !== 'none'),
        );
      });
      if (!available.length) continue;
      const exercises = reduced.exercises
        .filter((exercise) => available.some((set) => set.exerciseId === exercise.id))
        .map((exercise) => ({
          ...exercise,
          sets: available.filter((set) => set.exerciseId === exercise.id).length,
        }));
      const priority = (exerciseId: string) => {
        const demands = exerciseDemands(OPTIMIZER_RULES, exerciseId);
        return slot.priorityTargets.some((muscle) => demands.targets.includes(muscle));
      };
      // Stable partition, respecting user-edited order. Global priority never overwrites slot priority.
      if (!template.exercises.some((exercise) => exercise.userEdited))
        exercises.sort((a, b) => Number(priority(b.id)) - Number(priority(a.id)));
      const timing = context.timing;
      const duration = planSessionDuration({
        session: { ...reduced, exercises },
        eligibility: {
          sessionId: 'A',
          index: 0,
          reason: 'next_after_last_completion',
          eligibleAt: slot.scheduledAt,
          eligibleNow: false,
        },
        timing: {
          warmUpSeconds: timing.warmUpSeconds,
          equipmentTransitionSeconds: timing.transitionSeconds,
          exercises: Object.fromEntries(
            exercises.map((exercise) => [
              exercise.id,
              {
                setSeconds: timing.setSeconds,
                restSeconds: timing.restSeconds,
                stationId: exercise.id,
              },
            ]),
          ),
        },
        setSignals: Object.fromEntries(
          exercises.map((exercise) => [
            exercise.id,
            Array.from({ length: exercise.sets }, () => ({
              marginalValue: priority(exercise.id) ? 2 : 1,
            })),
          ]),
        ),
        priorityMuscles: exercises
          .filter((exercise) => priority(exercise.id))
          .map((exercise) => exercise.primaryMuscle),
        timeCapMinutes: slot.timeCapMinutes,
      });
      if (!duration.session) continue;
      const work = duration.session.exercises.flatMap((exercise) =>
        available.filter((set) => set.exerciseId === exercise.id).slice(0, exercise.sets),
      );
      const priorWork = logs.map((log) => ({
        setId: log.id,
        exerciseId: log.exerciseId,
        elapsedHours: (Date.parse(slot.scheduledAt) - Date.parse(log.completedAt)) / HOUR,
        reps: log.reps,
        loadKg: log.loadKg,
        rir: log.rir,
      }));
      result.allocations.push({
        slotId: slot.id,
        scheduledAt: slot.scheduledAt,
        timeZone: slot.timeZone,
        locationId: slot.locationId,
        groupId: slot.groupId,
        visitId: slot.visitId,
        kind: slot.kind,
        continuedSessionId: slot.continueSessionId ?? null,
        templateId: id,
        work,
        durationMinutes: duration.duration.minutes,
        durationRationale:
          'Derived from retained approved sets, supplied warm-up, execution, rest and transition estimates. Extra time never adds work; set quality and recovery still require review.',
        observationIds: observations.map((row) => row.id),
        priorWork,
        uncertainty: [
          'readiness_is_dose_and_context_dependent',
          'warmup_and_symptoms_require_reassessment',
          ...(context.history.some((row) => row.outcome === 'unknown') ? ['unlogged_workout'] : []),
          ...(context.observations.length !== fresh.length ? ['stale_or_future_observation'] : []),
          ...(observations.some((row) =>
            observations.some(
              (other) => observationKey(row) === observationKey(other) && row.state !== other.state,
            ),
          )
            ? ['conflicting_observations']
            : []),
          ...(priorWork.length
            ? ['direct_and_overlapping_completed_work_requires_review']
            : ['no_completed_work']),
          ...(result.allocations.length
            ? ['earlier_proposed_work_requires_reassessment_after_completion']
            : []),
        ],
      });
      const used = new Set(work.map((set) => set.id));
      pending.set(id, available.length ? pending.get(id)!.filter((set) => !used.has(set.id)) : []);
      order.splice(order.indexOf(id), 1);
      order.push(id);
      allocated = true;
      break;
    }
    if (!allocated && [...pending.values()].some((work) => work.length))
      result.tradeoffs.push({
        slotId: slot.id,
        kind: 'move_reduce_or_rest',
        reason: 'no_feasible_work_at_this_opportunity',
      });
  }
  result.unallocated = [...pending.values()]
    .flat()
    .map((work) => ({ work, reason: 'requires_reviewed_move_reduction_or_rest' }));
  if (result.unallocated.length)
    result.tradeoffs.push({
      slotId: null,
      kind: 'request_opportunity',
      reason: 'remaining_work_is_not_catch_up_debt',
    });
  return result;
}
