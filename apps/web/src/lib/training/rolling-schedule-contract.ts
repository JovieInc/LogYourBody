import { z } from 'zod';
import { CATALOG_EQUIPMENT } from './catalog';
import { recoveryTrialSchema } from './recovery-contract';
import { MUSCLE_GROUPS, MUSCLE_TARGETS, type MuscleGroup } from './types';

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
export type Observation = RollingScheduleContext['observations'][number];
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
