import { z } from 'zod';
import { MUSCLE_GROUPS } from './types';
import { RECOVERY_POLICY } from './recovery';

const state = z.enum(['proposed', 'applied', 'rejected', 'reverted']);
const outcome = z.object({
  decision: z.enum(['pending', 'retain', 'revert', 'inconclusive']),
  observationIds: z.array(z.string()),
  completedSetIds: z.array(z.string()),
  rationale: z.string(),
});
const evaluation = z.object({
  action: z.enum([
    'hold',
    'propose_increase',
    'reduce',
    'respace',
    'substitute',
    'recovery_review',
    'insufficient_evidence',
  ]),
  rationale: z.string(),
  uncertainty: z.enum(['moderate', 'high']),
  evidenceIds: z.array(z.string()),
  observationIds: z.array(z.string()),
  completedSetIds: z.array(z.string()),
  comparableSessionIds: z.array(z.string()),
  change: z
    .object({
      kind: z.literal('sets'),
      from: z.number().int().positive(),
      to: z.literal(RECOVERY_POLICY.reducedSets),
    })
    .nullable(),
  parameterProposal: z
    .object({
      status: z.literal('needs_policy_review'),
      scope: z.literal('side_delt_specialization'),
      missing: z.array(z.string()),
      evidenceIds: z.array(z.string()),
    })
    .nullable(),
});

export const recoveryTargetSchema = z
  .object({
    muscle: z.enum(MUSCLE_GROUPS),
    exerciseId: z.string().min(1).max(80),
    goal: z.enum(['emphasize', 'grow', 'maintain']),
  })
  .strict();
export const createRecoveryTrialSchema = recoveryTargetSchema
  .extend({ requestId: z.string().uuid() })
  .strict();
export const decideRecoveryTrialSchema = z
  .object({
    trialId: z.string().uuid(),
    expectedRevision: z.number().int().nonnegative(),
    decision: z.enum(['apply', 'reject', 'revert', 'review']),
  })
  .strict();

export const recoveryTrialSchema = z.object({
  id: z.string().uuid(),
  record_type: z.literal('recovery_trial'),
  version: z.literal(1),
  revision: z.number().int().nonnegative(),
  policyVersion: z.literal(RECOVERY_POLICY.version),
  programSetupId: z.string(),
  programRevisionId: z.string().nullable(),
  blockId: z.string(),
  muscle: z.enum(MUSCLE_GROUPS),
  exerciseId: z.string(),
  goal: z.enum(['emphasize', 'grow', 'maintain']),
  sourceFingerprint: z.string(),
  requestHash: z.string(),
  baseline: z.array(
    z.object({
      sessionId: z.string(),
      prescription: z
        .object({
          id: z.string(),
          primaryMuscle: z.enum(MUSCLE_GROUPS),
          sets: z.number().int().positive(),
          targetReps: z.number().int().positive(),
          targetRir: z.number().int().nonnegative(),
          targetLoadKg: z.number().nonnegative().nullable(),
        })
        .passthrough(),
      completed: z.array(
        z
          .object({
            id: z.string(),
            sessionId: z.string(),
            exerciseId: z.string(),
            setNumber: z.number().int().positive(),
            reps: z.number().int().nonnegative(),
            loadKg: z.number().nonnegative().nullable(),
            rir: z.number().nonnegative(),
            completedAt: z.string(),
          })
          .passthrough(),
      ),
    }),
  ),
  inference: evaluation,
  hypothesis: z.string(),
  reviewPoint: z.literal('next_comparable_completed_exposure'),
  holdConditions: z.array(z.string()),
  revertConditions: z.array(z.string()),
  state,
  outcome,
  history: z.array(
    z.object({
      revision: z.number().int().nonnegative(),
      state,
      at: z.string().datetime(),
      outcome,
    }),
  ),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
  appliedAt: z.string().datetime().nullable(),
});
export type RecoveryTrial = z.infer<typeof recoveryTrialSchema>;

export function readRecoveryTrials(rows: Array<Record<string, unknown>>): RecoveryTrial[] {
  return rows
    .filter((row) => row.record_type === 'recovery_trial')
    .map((row) => recoveryTrialSchema.parse(row));
}
