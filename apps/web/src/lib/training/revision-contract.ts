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

export const initialIntentSchema = z
  .object({
    kind: z.literal('initial_enrollment'),
    adultConfirmed: z.literal(true),
    safetyConfirmed: z.literal(true),
    sessionsPerWeek: z.union([z.literal(2), z.literal(3)]),
    equipment: z.enum(['dumbbells', 'full_gym']),
  })
  .strict();

const exerciseId = z.string().trim().min(1).max(64);
const pattern = z.enum(['A', 'B']);

/** Typed canvas/chat operations against the canonical weekly plan template.
 * Each op is inspectable, validated against the reviewed catalog, and applied
 * only through the revision proposal pathway — never by direct record writes. */
export const planEditOperationSchema = z.discriminatedUnion('kind', [
  z
    .object({
      kind: z.literal('move_exercise'),
      exerciseId,
      fromPattern: pattern,
      toPattern: pattern,
      toIndex: integer,
    })
    .strict(),
  z
    .object({
      kind: z.literal('reorder_exercise'),
      exerciseId,
      pattern,
      toIndex: integer,
    })
    .strict(),
  z
    .object({
      kind: z.literal('update_sets'),
      exerciseId,
      pattern,
      sets: z.number().int().min(1).max(6),
    })
    .strict(),
  z
    .object({
      kind: z.literal('swap_variant'),
      exerciseId,
      pattern,
      toVariantId: exerciseId,
    })
    .strict(),
  z
    .object({
      kind: z.literal('remove_exercise'),
      exerciseId,
      pattern,
    })
    .strict(),
]);
export type PlanEditOperation = z.infer<typeof planEditOperationSchema>;

export const planEditIntentSchema = z
  .object({
    kind: z.literal('plan_edit'),
    operations: z.array(planEditOperationSchema).min(1).max(16),
  })
  .strict();
export type PlanEditIntent = z.infer<typeof planEditIntentSchema>;

export const proposalIntentSchema = z.discriminatedUnion('kind', [
  initialIntentSchema,
  planEditIntentSchema,
]);

export const createProposalInputSchema = z
  .object({
    requestId: uuid,
    expectedGeneration: integer,
    intent: proposalIntentSchema,
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

const exerciseSchema = z.object({
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
export const baselinePlanSchema = z.object({
  week: z.literal(1),
  sessions: z
    .array(
      z.object({
        id: uuid,
        week: z.literal(1),
        slot: integer,
        pattern: z.enum(['A', 'B']),
        title: z.string(),
        exercises: z.array(exerciseSchema).min(1),
        safetyStop: z.literal(false),
        explanation: z.string().nullable(),
        evidenceIds: z.array(z.string()),
      }),
    )
    .min(2)
    .max(3),
  plannedFractionalVolume: z.record(z.string(), z.number().finite().nonnegative()),
});
export const initialProposalSchema = z
  .object({
    version: z.literal(1),
    id: uuid,
    programId: uuid,
    baseRevision: z.null(),
    context: revisionContextSchema,
    actor: z.object({ kind: z.literal('self'), subject: z.string().min(1) }),
    authority: z.literal('self_review_required'),
    intent: initialIntentSchema,
    reason: z.string(),
    priorState: z.null(),
    proposedDiff: z.literal('create_supported_baseline_program'),
    policyVersion: z.literal(TRAINING_BASELINE_POLICY),
    assumptions: z.array(z.string()),
    inputEvidence: z.object({
      source: z.literal('canonical_profile_and_explicit_consent'),
      observedAt: timestamp,
    }),
    reviewPoint: z.literal('before_first_workout'),
    plan: baselinePlanSchema,
    createdAt: timestamp,
  })
  .strict();
export type InitialTrainingProposal = z.infer<typeof initialProposalSchema>;

/** Canonical weekly layout: ordered exercise/variant ids and set counts per
 * session pattern. This is the persisted artifact a plan edit installs; the
 * engine still owns rep ranges, RIR targets and progression at read time. */
export const planLayoutEntrySchema = z
  .object({ exerciseId, sets: z.number().int().min(1).max(6) })
  .strict();
export const planLayoutSchema = z
  .object({
    A: z.array(planLayoutEntrySchema).min(1),
    B: z.array(planLayoutEntrySchema).min(1),
  })
  .strict();
export type PlanLayout = z.infer<typeof planLayoutSchema>;

export const planEditProposalSchema = z
  .object({
    version: z.literal(1),
    id: uuid,
    programId: uuid,
    baseRevision: uuid,
    context: revisionContextSchema,
    actor: z.object({ kind: z.literal('self'), subject: z.string().min(1) }),
    authority: z.literal('self_review_required'),
    intent: planEditIntentSchema,
    reason: z.string(),
    /** Hash of the reviewed layout this edit was proposed against. */
    priorState: z.string().min(1),
    proposedDiff: z
      .array(
        z
          .object({ op: planEditOperationSchema, change: z.string().min(1).max(500) })
          .strict(),
      )
      .min(1),
    policyVersion: z.literal(TRAINING_BASELINE_POLICY),
    assumptions: z.array(z.string()),
    inputEvidence: z.object({
      source: z.literal('canonical_head_revision_and_typed_operations'),
      observedAt: timestamp,
    }),
    reviewPoint: z.literal('before_next_workout'),
    layout: planLayoutSchema,
    plan: baselinePlanSchema,
    createdAt: timestamp,
  })
  .strict();
export type PlanEditProposal = z.infer<typeof planEditProposalSchema>;

export const trainingProposalSchema = z.union([
  initialProposalSchema,
  planEditProposalSchema,
]);
export type TrainingProposal = z.infer<typeof trainingProposalSchema>;

/** Immutable revision node. Initial revisions carry the enrolled setup; plan
 * edits carry the resulting layout and repeat the still-current setup. */
export const storedTrainingRevisionSchema = z
  .object({
    version: z.literal(1),
    id: uuid,
    proposal: trainingProposalSchema,
    // Older revision payloads predate these keys; absent means null.
    baseRevision: uuid.nullable().optional(),
    layout: planLayoutSchema.nullable().optional(),
    setup: z.object({
      id: uuid,
      sessionsPerWeek: z.union([z.literal(2), z.literal(3)]),
      equipment: z.enum(['dumbbells', 'full_gym']),
      startedAt: timestamp,
    }),
    activatedAt: timestamp,
  })
  .strict();
export type StoredTrainingRevision = z.infer<typeof storedTrainingRevisionSchema>;

export const appliedSetupSchema = z.object({
  id: uuid,
  consentVersion: z.literal(TRAINING_CONSENT_VERSION),
  adultConfirmed: z.literal(true),
  safetyConfirmed: z.literal(true),
  sessionsPerWeek: z.union([z.literal(2), z.literal(3)]),
  equipment: z.enum(['dumbbells', 'full_gym']),
  startedAt: timestamp,
  programRevisionId: uuid,
  programPolicyVersion: z.literal(TRAINING_BASELINE_POLICY),
});
export const revisionReceiptSchema = z
  .object({
    version: z.literal(1),
    proposalId: uuid,
    requestId: uuid,
    decision: z.enum(['apply', 'reject']),
    status: z.enum(['applied', 'rejected']),
    actor: z.object({ kind: z.literal('self'), subject: z.string().min(1) }),
    /** The revision this decision replaced: null for enrollment, the previous
     * head revision id for an applied plan edit. Always null when rejected. */
    priorState: uuid.nullable(),
    revisionId: uuid.nullable(),
    setup: appliedSetupSchema.nullable(),
    decidedAt: timestamp,
  })
  .refine((r) =>
    r.decision === 'apply'
      ? r.status === 'applied' &&
        r.revisionId !== null &&
        (r.priorState === null
          ? r.setup?.programRevisionId === r.revisionId
          : r.setup === null)
      : r.status === 'rejected' &&
        r.revisionId === null &&
        r.setup === null &&
        r.priorState === null,
  );
export type TrainingRevisionReceipt = z.infer<typeof revisionReceiptSchema>;
export const storedProposalSchema = z
  .object({
    proposal: trainingProposalSchema,
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
