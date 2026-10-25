import { z } from 'zod';
import { MUSCLE_GROUPS, TRAINING_CONSENT_VERSION } from './types';

export const TRAINING_BASELINE_POLICY = 'hypertrophy-baseline-v1';
const timestamp = z.string().datetime({ offset: true });
const uuid = z.string().uuid();
const integer = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
export const revisionContextSchema = z.object({
  // Historical proposals remain exportable; new admissions require this field.
  ownerId: uuid.optional(),
  generation: integer,
  profileFingerprint: z.string().min(1),
  legacyFingerprint: z.string().min(1),
});
export type RevisionContextToken = z.infer<typeof revisionContextSchema>;

export const mesocycleLengthSchema = z.union([z.literal(4), z.literal(5), z.literal(6)]);
const prioritiesSchema = z
  .array(
    z.object({ muscle: z.enum(MUSCLE_GROUPS), reason: z.string().trim().min(1).max(500) }).strict(),
  )
  .max(10);
const constraintsSchema = z
  .array(
    z
      .object({ id: z.string().min(1).max(100), reason: z.string().trim().min(1).max(500) })
      .strict(),
  )
  .max(20);
const retainedVariantsSchema = z
  .array(
    z
      .object({
        fromExerciseId: z.string().min(1),
        toVariantId: z.string().min(1),
        reason: z.string().trim().min(1).max(500),
      })
      .strict(),
  )
  .max(30);
export const trainingCycleSchema = z
  .object({
    weekCount: mesocycleLengthSchema,
    number: z.number().int().positive(),
    priorities: prioritiesSchema,
    constraints: constraintsSchema,
    retainedVariants: retainedVariantsSchema,
    historySetupIds: z.array(uuid),
  })
  .strict();
export const cycleIntentSchema = z
  .object({
    kind: z.enum(['revise_cycle', 'repeat_cycle']),
    weekCount: mesocycleLengthSchema,
    priorities: prioritiesSchema.optional(),
    constraints: constraintsSchema.optional(),
    retainedVariants: retainedVariantsSchema.optional(),
  })
  .strict();
export const initialIntentSchema = z
  .object({
    kind: z.literal('initial_enrollment'),
    adultConfirmed: z.literal(true),
    safetyConfirmed: z.literal(true),
    sessionsPerWeek: z.union([z.literal(2), z.literal(3)]),
    equipment: z.enum(['dumbbells', 'full_gym']),
    weekCount: mesocycleLengthSchema.optional(),
  })
  .strict();
export const createProposalInputSchema = z
  .object({
    requestId: uuid,
    expectedGeneration: integer,
    intent: z.union([initialIntentSchema, cycleIntentSchema]),
    reason: z.string().trim().min(1).max(500),
  })
  .strict();
export const decideProposalInputSchema = z
  .object({
    requestId: uuid,
    proposalId: uuid,
    decision: z.enum(['apply', 'reject']),
  })
  .strict();

const exerciseCoreSchema = z.object({
  id: z.string(),
  name: z.string(),
  primaryMuscle: z.enum(MUSCLE_GROUPS),
  muscleContribution: z.record(z.string(), z.number().finite().nonnegative()),
  sets: z.number().int().positive(),
  repRange: z.object({ min: z.number().int().positive(), max: z.number().int().positive() }),
  targetReps: z.number().int().positive(),
  targetRir: z.number().int().nonnegative(),
  targetLoadKg: z.number().finite().nonnegative().nullable(),
  loadInstruction: z.string().nullable(),
  progression: z.enum(['hold', 'add_reps', 'increase_load']),
  evidenceIds: z.array(z.string()),
});
const exerciseSchema = exerciseCoreSchema.extend({
  substitutions: z.array(exerciseCoreSchema).default([]),
});
export const baselinePlanSchema = z.object({
  week: z.number().int().min(1).max(6),
  sessions: z
    .array(
      z
        .object({
          id: uuid,
          week: z.number().int().min(1).max(6),
          slot: integer,
          pattern: z.enum(['A', 'B']),
          title: z.string(),
          exercises: z.array(exerciseSchema),
          safetyStop: z.boolean(),
          explanation: z.string().nullable(),
          evidenceIds: z.array(z.string()),
        })
        .refine((session) => session.safetyStop === (session.exercises.length === 0)),
    )
    .min(2)
    .max(3),
  plannedFractionalVolume: z.record(z.string(), z.number().finite().nonnegative()),
});
export const appliedSetupSchema = z.object({
  id: uuid,
  consentVersion: z.literal(TRAINING_CONSENT_VERSION),
  adultConfirmed: z.literal(true),
  safetyConfirmed: z.literal(true),
  sessionsPerWeek: z.union([z.literal(2), z.literal(3)]),
  equipment: z.enum(['dumbbells', 'full_gym']),
  startedAt: timestamp,
  programRevisionId: uuid,
  cycle: trainingCycleSchema.optional(),
  excludedVariantIds: z.array(z.string()).optional(),
  programPolicyVersion: z.literal(TRAINING_BASELINE_POLICY),
});
export const initialProposalSchema = z
  .object({
    version: z.literal(1),
    id: uuid,
    programId: uuid,
    baseRevision: uuid.nullable(),
    context: revisionContextSchema,
    actor: z.object({ kind: z.literal('self'), subject: z.string().min(1) }),
    authority: z.literal('self_review_required'),
    intent: z.union([initialIntentSchema, cycleIntentSchema]),
    reason: z.string(),
    priorState: z.object({ setupId: uuid, revisionId: uuid.nullable() }).nullable(),
    proposedDiff: z.enum(['create_supported_baseline_program', 'revise_cycle', 'repeat_cycle']),
    lifecycleTransition: z
      .object({
        from: z.enum(['accumulation', 'planned_deload', 'reactive_deload', 'review']),
        to: z.enum(['adjustment', 'next_block']),
      })
      .optional(),
    proposedSetup: appliedSetupSchema.omit({ programRevisionId: true }).optional(),
    trainingFingerprint: z.string().optional(),
    policyVersion: z.literal(TRAINING_BASELINE_POLICY),
    assumptions: z.array(z.string()),
    inputEvidence: z.object({
      source: z.literal('canonical_profile_and_explicit_consent'),
      observedAt: timestamp,
    }),
    reviewPoint: z.enum(['before_first_workout', 'before_cycle_revision', 'before_next_block']),
    plan: baselinePlanSchema,
    createdAt: timestamp,
  })
  .strict();
export type InitialTrainingProposal = z.infer<typeof initialProposalSchema>;
export const revisionReceiptSchema = z
  .object({
    version: z.literal(1),
    proposalId: uuid,
    requestId: uuid,
    decision: z.enum(['apply', 'reject']),
    status: z.enum(['applied', 'rejected']),
    actor: z.object({ kind: z.literal('self'), subject: z.string().min(1) }),
    priorState: z.object({ setupId: uuid, revisionId: uuid.nullable() }).nullable(),
    revisionId: uuid.nullable(),
    setup: appliedSetupSchema.nullable(),
    decidedAt: timestamp,
  })
  .refine((r) =>
    r.decision === 'apply'
      ? r.status === 'applied' &&
        r.revisionId !== null &&
        r.setup?.programRevisionId === r.revisionId
      : r.status === 'rejected' && r.revisionId === null && r.setup === null,
  );
export type TrainingRevisionReceipt = z.infer<typeof revisionReceiptSchema>;
export const storedProposalSchema = z
  .object({
    proposal: initialProposalSchema,
    status: z.enum(['proposed', 'applied', 'rejected']),
    requestHash: z.string().min(1),
    receipt: revisionReceiptSchema.nullable(),
  })
  .refine((r) =>
    r.status === 'proposed'
      ? r.receipt === null
      : r.receipt?.status === r.status &&
        r.receipt.proposalId === r.proposal.id &&
        r.receipt.actor.subject === r.proposal.actor.subject &&
        (r.receipt.setup === null || r.receipt.setup.id === r.proposal.programId),
  );
export type StoredTrainingProposal = z.infer<typeof storedProposalSchema>;
