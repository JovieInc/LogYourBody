import { z } from 'zod';
import { catalogVariantById } from './catalog';
import { sequencingContextSchema } from './sequencing';
import { rollingScheduleSchema } from './rolling-schedule';
import { MUSCLE_GROUPS } from './types';

const WEEKDAYS = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
] as const;

const setLogSchema = z
  .object({
    id: z.string().min(1),
    sessionId: z.string().min(1),
    exerciseId: z.string().min(1),
    setNumber: z.number().int().positive(),
    reps: z.number().int().positive(),
    loadKg: z.number().finite().nonnegative().nullable(),
    rir: z.number().int().nonnegative(),
    completedAt: z.string().min(1),
  })
  .strict();

const planExerciseSchema = z
  .object({
    id: z.string().min(1),
    name: z.string().min(1),
    primaryMuscle: z.enum(MUSCLE_GROUPS),
    sets: z.number().int().positive().max(50),
    targetRir: z.number().int().min(0).max(6).optional(),
    userEdited: z.boolean().optional(),
    phase: z.enum(['warmup', 'working']).optional(),
    muscleContribution: z.record(z.string(), z.number().finite().nonnegative()).optional(),
  })
  .strict();

const planSessionSchema = z
  .object({
    id: z.string().min(1),
    day: z.enum(WEEKDAYS),
    part: z.enum(['am', 'pm', 'any']),
    exercises: z.array(planExerciseSchema).min(1),
    heartRateBpm: z.number().finite().nonnegative().optional(),
  })
  .strict();

const preferenceSchema = z
  .object({
    id: z.string().min(1),
    scope: z.enum(['durable', 'location']),
    locationId: z.string().min(1).nullable(),
    muscle: z.enum(MUSCLE_GROUPS).nullable(),
    reason: z.string().min(1).max(200),
  })
  .strict();

export const optimizerInputSchema = z
  .object({
    sessions: z.array(planSessionSchema).min(1),
    equipmentProfile: z.enum(['dumbbells', 'full_gym']),
    declaredEquipment: z.array(z.string()).optional(),
    unavailableEquipment: z.array(z.string()).optional(),
    locationId: z.string().min(1).nullable(),
    locationPermission: z.enum(['granted', 'denied', 'unknown']),
    detectedLocationId: z.string().min(1).nullable().optional(),
    stationGeography: z.enum(['colocated', 'separated', 'unknown']),
    preferences: z.array(preferenceSchema).optional(),
    priorityMuscles: z.array(z.enum(MUSCLE_GROUPS)).optional(),
    readiness: z
      .array(
        z
          .object({
            sessionId: z.string().min(1),
            reported: z.enum(['ready', 'low', 'unknown']),
          })
          .strict(),
      )
      .optional(),
    pain: z
      .array(
        z
          .object({
            exerciseId: z.string().min(1),
            jointPain: z.number().int().min(0).max(10),
            concern: z.string().min(1).optional(),
          })
          .strict(),
      )
      .optional(),
    measuredTransitionMinutes: z.number().finite().nonnegative().nullable().optional(),
    considerTimeSupersets: z.boolean().optional(),
    requestedSwaps: z
      .array(
        z
          .object({
            sessionId: z.string().min(1),
            fromExerciseId: z.string().min(1),
            toVariantId: z.string().min(1),
          })
          .strict(),
      )
      .optional(),
    logs: z.array(setLogSchema).optional(),
    targetRir: z.number().int().min(0).max(6).optional(),
    baseFingerprint: z.string().min(1).optional(),
    sequencingContext: sequencingContextSchema.optional(),
    rollingSchedule: rollingScheduleSchema.optional(),
    declineSupersets: z
      .object({
        scope: z.enum(['durable', 'location']),
        muscle: z.enum(MUSCLE_GROUPS).nullable(),
        reason: z.string().min(1).max(200),
      })
      .strict()
      .optional(),
  })
  .strict()
  .refine(
    (input) =>
      new Set(input.sessions.map((row) => row.id)).size === input.sessions.length &&
      input.sessions.every(
        (session) =>
          new Set(session.exercises.map((row) => row.id)).size === session.exercises.length,
      ),
    'ambiguous_session_or_exercise_identity',
  )
  .superRefine((input, ctx) => {
    if (!input.rollingSchedule) return;
    if (input.requestedSwaps?.length || input.pain?.length)
      ctx.addIssue({ code: 'custom', message: 'review_variant_or_pain_change_before_scheduling' });
    const ids = new Set(input.sessions.map((session) => session.id));
    const setIds = new Set<string>();
    const setKeys = new Set<string>();
    for (const log of input.logs ?? []) {
      const key = JSON.stringify([log.sessionId, log.exerciseId, log.setNumber]);
      if (setIds.has(log.id) || setKeys.has(key) || !Number.isFinite(Date.parse(log.completedAt)))
        ctx.addIssue({ code: 'custom', message: 'ambiguous_completed_set_identity' });
      setIds.add(log.id);
      setKeys.add(key);
    }
    for (const row of input.rollingSchedule.history) {
      if (row.rotationId === input.rollingSchedule.rotationId && !ids.has(row.templateId))
        ctx.addIssue({ code: 'custom', message: 'unknown_rotation_template' });
    }
    for (const session of input.sessions) {
      for (const exercise of session.exercises) {
        const variant = catalogVariantById(exercise.id);
        if (variant && variant.primaryMuscle !== exercise.primaryMuscle)
          ctx.addIssue({ code: 'custom', message: 'exercise_muscle_mismatch' });
      }
    }
  });

export type OptimizerInput = z.infer<typeof optimizerInputSchema>;
export type PlanExercise = z.infer<typeof planExerciseSchema>;
export type PlanSession = Omit<z.infer<typeof planSessionSchema>, 'heartRateBpm'>;
export type SupersetPreference = z.infer<typeof preferenceSchema>;