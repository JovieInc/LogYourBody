import { z } from 'zod';
import { MUSCLE_GROUPS, TRAINING_SESSIONS_PER_WEEK } from '@/lib/training/types';
import { CATALOG_EQUIPMENT } from '@/lib/training/catalog';
import { selectionContextSchema } from '@/lib/training/selection';

export const EnrollBodySchema = z
  .object({
    adultConfirmed: z.boolean(),
    safetyConfirmed: z.boolean(),
    sessionsPerWeek: z.literal(TRAINING_SESSIONS_PER_WEEK),
    equipment: z.enum(['dumbbells', 'full_gym']),
  })
  .strict();

export const LogSetBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    exerciseId: z.string().trim().min(1).max(64),
    setNumber: z.number().int().min(1).max(10),
    reps: z.number().int().min(1).max(50),
    loadKg: z.number().finite().min(0).max(500).nullable().optional(),
    rir: z.number().int().min(0).max(6),
  })
  .strict();

const FeedbackScoreSchema = z.number().int().min(0).max(10);
const ReadinessSchema = z.enum(['ready', 'limited', 'unknown']);
const MuscleFeedbackSchema = z
  .object({
    soreness: FeedbackScoreSchema.optional(),
    recovery: ReadinessSchema.optional(),
    pump: FeedbackScoreSchema.optional(),
    workload: z.enum(['below_expected', 'as_expected', 'above_expected']).optional(),
    performance: z.enum(['up', 'stable', 'down']).optional(),
  })
  .strict()
  .refine((value) => Object.values(value).some((item) => item !== undefined));

export const CorrectSetBodySchema = LogSetBodySchema.extend({
  correctionId: z.string().uuid(),
  expectedRevision: z.number().int().min(0),
}).strict();

export const UndoSetBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    exerciseId: z.string().trim().min(1).max(64),
    setNumber: z.number().int().min(1).max(10),
    undoId: z.string().uuid(),
    expectedRevision: z.number().int().min(0),
  })
  .strict();

export const FeedbackBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    soreness: FeedbackScoreSchema.optional(),
    pump: FeedbackScoreSchema.optional(),
    performance: z.enum(['up', 'stable', 'down']).optional(),
    jointPain: FeedbackScoreSchema.optional(),
    muscles: z.partialRecord(z.enum(MUSCLE_GROUPS), MuscleFeedbackSchema).optional(),
    targetMuscle: z.enum(MUSCLE_GROUPS).optional(),
    targetMuscleReadiness: ReadinessSchema.optional(),
    breathingReadiness: ReadinessSchema.optional(),
    generalReadiness: ReadinessSchema.optional(),
    supportingReadiness: z
      .object({
        grip: ReadinessSchema.optional(),
        trunk: ReadinessSchema.optional(),
        muscles: z.partialRecord(z.enum(MUSCLE_GROUPS), ReadinessSchema).optional(),
      })
      .strict()
      .optional(),
    trunkFatigue: FeedbackScoreSchema.optional(),
    generalExhaustion: FeedbackScoreSchema.optional(),
    targetMuscleQuality: z.enum(['poor', 'adequate', 'good']).optional(),
    stability: z.enum(['stable', 'unstable']).optional(),
    symptomFlags: z
      .array(z.enum(['pain', 'neurologic', 'other_concerning']))
      .min(1)
      .max(3)
      .optional(),
    symptomNote: z.string().trim().min(1).max(500).optional(),
    originalStatement: z.string().trim().min(1).max(1_000).optional(),
    transcriptionUncertain: z.boolean().optional(),
    interpretations: z
      .array(
        z
          .object({
            claim: z.enum([
              'goal_preference',
              'self_assessed_development',
              'performance',
              'tolerability',
              'symptom',
              'recovery',
              'pump',
              'causal_hypothesis',
              'dose_history',
            ]),
            timeframe: z.enum(['current', 'historical']),
            confidence: z.enum(['low', 'moderate', 'high']),
            corroboratesObservationIds: z
              .array(z.string().trim().min(1).max(160))
              .min(1)
              .max(20)
              .optional(),
            conflictsWithObservationIds: z
              .array(z.string().trim().min(1).max(160))
              .min(1)
              .max(20)
              .optional(),
            proposedExplanation: z.string().trim().min(1).max(500).optional(),
          })
          .strict(),
      )
      .min(1)
      .max(8)
      .optional(),
    source: z.enum(['touch', 'voice', 'text', 'import', 'unknown']).optional(),
    observedAt: z.string().datetime().optional(),
    sourceObservationId: z.string().trim().min(1).max(160).optional(),
    correctsObservationId: z.string().trim().min(1).max(160).optional(),
    context: z
      .object({
        exerciseId: z.string().trim().min(1).max(80).optional(),
        setId: z.string().trim().min(1).max(160).optional(),
        setNumber: z.number().int().min(1).max(50).optional(),
        setOrder: z.number().int().min(1).max(50).optional(),
        reps: z.number().int().min(0).max(100).optional(),
        loadKg: z.number().finite().min(0).max(500).nullable().optional(),
        rir: z.number().int().min(0).max(6).optional(),
        restSeconds: z.number().int().min(0).max(3600).optional(),
        setup: z.string().trim().min(1).max(160).optional(),
        rangeOfMotion: z.enum(['full', 'partial', 'unknown']).optional(),
        romRestriction: z.enum(['none', 'limited', 'blocked']).optional(),
        gymId: z.string().trim().min(1).max(80).optional(),
        availableEquipment: z
          .array(z.enum(CATALOG_EQUIPMENT))
          .max(CATALOG_EQUIPMENT.length)
          .optional(),
        setFormat: z.literal('straight').optional(),
      })
      .strict()
      .optional(),
  })
  .strict();

export const SwapBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    exerciseId: z.string().trim().min(1).max(64),
    toVariantId: z.string().trim().min(1).max(64).optional(),
    unavailableEquipment: z.array(z.string().trim().min(1).max(32)).max(16).optional(),
    declaredEquipment: z.array(z.string().trim().min(1).max(32)).max(16).optional(),
    excludedConcerns: z.array(z.string().trim().min(1).max(48)).max(16).optional(),
    preferTorsoSupport: z.boolean().optional(),
    maxTrunkDemand: z.enum(['low', 'moderate', 'high']).optional(),
  })
  .strict();

export const WorkoutActionBodySchema = z
  .object({
    sessionId: z.string().uuid(),
    eventId: z.string().uuid(),
    expectedRevision: z.number().int().min(0),
    action: z.discriminatedUnion('kind', [
      z
        .object({
          kind: z.literal('swap'),
          exerciseId: z.string().min(1).max(64),
          replacementExerciseId: z.string().min(1).max(64),
          selectionContext: selectionContextSchema.optional(),
        })
        .strict(),
      z.object({ kind: z.literal('restore_swap'), swapEventId: z.string().uuid() }).strict(),
      z
        .object({ kind: z.literal('equipment_unavailable'), exerciseId: z.string().min(1).max(64) })
        .strict(),
      z.object({ kind: z.literal('shorten'), minutes: z.number().int().min(5).max(180) }).strict(),
      z.object({ kind: z.literal('skip'), exerciseId: z.string().min(1).max(64) }).strict(),
      z.object({ kind: z.literal('pain'), exerciseId: z.string().min(1).max(64) }).strict(),
      z.object({ kind: z.literal('pause') }).strict(),
      z.object({ kind: z.literal('resume') }).strict(),
      z.object({ kind: z.literal('end') }).strict(),
    ]),
  })
  .strict();
