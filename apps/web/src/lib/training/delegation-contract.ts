import { z } from 'zod';
import { canvasPlanSchema } from './mesocycle-canvas';
import { MUSCLE_GROUPS, TRAINING_CONSENT_VERSION } from './types';

export const DELEGATED_POLICY = 'delegated-canvas-v1';
const uuid = z.string().uuid();
const time = z.string().datetime({ offset: true });
const variants = z.array(z.string().min(1).max(100)).max(100);
export const planningInputsSchema = z
  .object({
    goal: z.string().trim().min(1).max(500),
    goalDate: time.nullable().default(null),
    experience: z.enum(['new', 'returning', 'experienced']),
    sessionsPerWeek: z.union([
      z.literal(2),
      z.literal(3),
      z.literal(4),
      z.literal(5),
      z.literal(6),
    ]),
    minutesPerSession: z.number().int().min(15).max(180),
    equipment: z.enum(['dumbbells', 'full_gym']),
    excludedVariantIds: variants,
    // These are reviewed catalog concern tags, not diagnoses inferred by chat.
    limitations: z.array(z.string().min(1).max(100)).max(20),
    preferredVariantIds: variants,
  })
  .strict();
export type PlanningInputs = z.infer<typeof planningInputsSchema>;

export const delegatedProgramSchema = z
  .object({
    inputs: planningInputsSchema,
    plan: canvasPlanSchema,
    blockNumber: z.number().int().positive(),
    // Last week is a planned deload; calendar expiry never completes this block.
    deloadWeek: z.union([z.literal(4), z.literal(5), z.literal(6)]),
    temporaryPriority: z
      .object({
        muscles: z.array(z.enum(MUSCLE_GROUPS)).min(1),
        upperChest: z.boolean().default(false),
        expiresAfterBlock: z.number().int().positive(),
      })
      .nullable(),
    // Opaque reviewed steering constraint; interpretation belongs to health policy.
    constraintId: z.string().trim().min(1).max(200).nullable().optional(),
    completedWeeks: z.record(z.string(), z.number().int().min(2).max(6)).default({}),
    authority: z
      .object({
        trainerSubject: z.string().min(1).max(200).nullable(),
        coachDelegated: z.boolean(),
      })
      .strict(),
  })
  .strict();
export type DelegatedProgram = z.infer<typeof delegatedProgramSchema>;
export const delegatedSetupSchema = z.object({
  id: uuid,
  consentVersion: z.literal(TRAINING_CONSENT_VERSION),
  adultConfirmed: z.literal(true),
  safetyConfirmed: z.literal(true),
  sessionsPerWeek: planningInputsSchema.shape.sessionsPerWeek,
  equipment: planningInputsSchema.shape.equipment,
  startedAt: time,
  programRevisionId: uuid,
  programPolicyVersion: z.literal(DELEGATED_POLICY),
  delegated: delegatedProgramSchema,
});
export const priorSetupSchema = delegatedSetupSchema.extend({
  programRevisionId: uuid.optional(),
  programPolicyVersion: z.string().optional(),
  delegated: delegatedProgramSchema.optional(),
});
export const steeringIntentSchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('recommend'),
      inputs: planningInputsSchema.partial(),
      adultConfirmed: z.literal(true),
      safetyConfirmed: z.literal(true),
      weekCount: z.union([z.literal(4), z.literal(5), z.literal(6)]).default(4),
    })
    .strict(),
  z
    .object({ kind: z.literal('keep'), variantId: z.string().min(1), scope: z.literal('durable') })
    .strict(),
  z
    .object({
      kind: z.literal('exclude'),
      variantId: z.string().min(1),
      scope: z.literal('durable'),
    })
    .strict(),
  z
    .object({
      kind: z.literal('prioritize'),
      muscles: z.array(z.enum(MUSCLE_GROUPS)).min(1),
      scope: z.literal('this_block'),
      upperChest: z.boolean().default(false),
    })
    .strict(),
  z
    .object({
      kind: z.literal('schedule'),
      count: planningInputsSchema.shape.sessionsPerWeek,
      scope: z.literal('durable'),
    })
    .strict(),
  z.object({ kind: z.literal('next_block') }).strict(),
  z.object({ kind: z.literal('restore'), revisionId: uuid }).strict(),
  z
    .object({
      kind: z.literal('authorize_trainer'),
      trainerSubject: z.string().min(1).max(200).nullable(),
    })
    .strict(),
  z.object({ kind: z.literal('delegate_coach'), enabled: z.boolean() }).strict(),
]);
export type SteeringIntent = z.infer<typeof steeringIntentSchema>;
export const steeringRequestSchema = z
  .object({
    requestId: uuid,
    expectedGeneration: z.number().int().nonnegative(),
    reason: z.string().trim().min(1).max(500),
    intent: steeringIntentSchema.optional(),
    utterance: z.string().trim().min(1).max(500).optional(),
    baseProposalId: uuid.optional(),
  })
  .strict()
  .refine((v) => Boolean(v.intent) !== Boolean(v.utterance));

export const revisionActorSchema = z
  .object({ kind: z.enum(['user', 'coach', 'trainer']), subject: z.string().min(1) })
  .strict();
export type RevisionActor = z.infer<typeof revisionActorSchema>;
export const delegatedProposalSchema = z
  .object({
    version: z.literal(2),
    id: uuid,
    programId: uuid,
    ownerSubject: z.string().min(1),
    baseRevision: uuid.nullable(),
    context: z.object({
      ownerId: uuid,
      generation: z.number().int().nonnegative(),
      profileFingerprint: z.string(),
      legacyFingerprint: z.string(),
    }),
    actor: revisionActorSchema,
    authority: z.enum(['user_review', 'trainer_grant', 'coach_delegation']),
    intent: steeringIntentSchema,
    reason: z.string(),
    priorState: priorSetupSchema.nullable(),
    proposedState: delegatedProgramSchema,
    plan: canvasPlanSchema,
    proposedDiff: z.array(z.object({ field: z.string(), before: z.unknown(), after: z.unknown() })),
    policyVersion: z.literal(DELEGATED_POLICY),
    validation: z.object({
      allowed: z.literal(true),
      rules: z.array(z.string()),
      pushback: z.array(z.string()),
    }),
    inputEvidence: z.object({
      fingerprint: z.string(),
      observedAt: time,
      freshness: z.literal('current'),
      evidenceIds: z.array(z.string()).min(1),
      signals: z.object({
        training: z.object({
          freshness: z.enum(['fresh', 'stale', 'missing']),
          observedAt: time.nullable(),
        }),
        feedback: z.object({
          freshness: z.enum(['fresh', 'stale', 'missing']),
          observedAt: time.nullable(),
        }),
      }),
    }),
    assumptions: z.array(z.string()),
    summary: z.array(z.string()),
    reviewPoint: z.literal('before_next_workout'),
    rollbackRevision: uuid.nullable(),
    transition: z
      .object({
        staying: z.array(z.string()),
        changing: z.array(z.string()),
        why: z.string(),
        expiring: z.array(z.string()),
        primaryAction: z.literal('Start next block'),
        secondaryAction: z.literal('Review changes'),
      })
      .nullable(),
    createdAt: time,
  })
  .strict();
export type DelegatedProposal = z.infer<typeof delegatedProposalSchema>;
export const delegatedReceiptSchema = z
  .object({
    version: z.literal(2),
    proposalId: uuid,
    requestId: uuid,
    decision: z.enum(['apply', 'reject']),
    status: z.enum(['applied', 'rejected']),
    actor: revisionActorSchema,
    priorState: priorSetupSchema.nullable(),
    revisionId: uuid.nullable(),
    setup: delegatedSetupSchema.nullable(),
    decidedAt: time,
  })
  .refine((v) =>
    v.decision === 'apply'
      ? v.status === 'applied' &&
        v.revisionId !== null &&
        v.setup?.programRevisionId === v.revisionId
      : v.status === 'rejected' && v.revisionId === null && v.setup === null,
  );
export type DelegatedReceipt = z.infer<typeof delegatedReceiptSchema>;
