import { z } from 'zod';
import type { TrainingRevisionsPort } from '@/lib/ports/training-revisions';
import type { SwapConstraints } from './commands';
import {
  DELEGATED_POLICY,
  delegatedProposalSchema,
  delegatedSetupSchema,
  revisionActorSchema,
  type RevisionActor,
} from './delegation-contract';
import { canSteer, currentTrainingSetup } from './delegated-revisions';
import { profileConfirmsAdult } from './eligibility';
import type { StoredTrainingProposal } from './revision-contract';
import { trainingRequestHash } from './revisions';
import { MUSCLE_GROUPS } from './types';

export const programSteeringRecordSchema = z
  .object({
    revisionId: z.string().uuid(),
    priorityFocus: z
      .object({
        muscles: z.array(z.enum(MUSCLE_GROUPS)).min(1),
        upperChest: z.boolean(),
      })
      .strict()
      .refine((v) => !v.upperChest || v.muscles.includes('chest')),
    constraintId: z.string().trim().min(1).max(200).nullable(),
    actor: revisionActorSchema,
    rationale: z.string().trim().min(1).max(500),
  })
  .strict();
export type ProgramSteeringRecord = z.infer<typeof programSteeringRecordSchema>;

type MovementConstraint = Pick<SwapConstraints, 'maxTrunkDemand' | 'excludedConcerns'>;
export type SteeringHealthDecision =
  | { kind: 'allow' }
  | { kind: 'review_required' }
  | { kind: 'movement_constraint'; constraints: MovementConstraint };

/** Request-only LYB-113 boundary. Implementations deduplicate by revisionId and
 * propose through the existing substitution contract, never apply a card edit. */
export interface SteeringSubstitutionsPort {
  request(input: {
    subject: string;
    programId: string;
    revisionId: string;
    constraintId: string;
    constraints: MovementConstraint;
  }): Promise<{ kind: 'requested' } | { kind: 'review_required' }>;
}

/** Internal writer for an already reviewed record. The caller supplies its
 * rollout gate, authenticated actor and resolved health-policy decision. */
export async function persistSteeringRevision(input: {
  enabled: boolean;
  revisions: TrainingRevisionsPort;
  substitutions?: SteeringSubstitutionsPort;
  subject: string;
  actor: RevisionActor;
  record: unknown;
  healthDecision: SteeringHealthDecision;
  now: Date;
}) {
  if (!input.enabled) return { kind: 'disabled' as const };
  const parsed = programSteeringRecordSchema.safeParse(input.record);
  if (!parsed.success) return { kind: 'invalid_steering_record' as const };
  const record = parsed.data;
  if (trainingRequestHash(input.actor) !== trainingRequestHash(record.actor))
    return { kind: 'unauthorized_actor' as const };
  const context = await input.revisions.readContext(input.subject);
  if (!context) return { kind: 'owner_missing' as const };
  const prior = delegatedSetupSchema.safeParse(currentTrainingSetup(context));
  if (!prior.success) return { kind: 'delegated_program_required' as const };
  if (
    !canSteer(input.subject, input.actor, prior.data) ||
    (input.actor.kind === 'coach' && !prior.data.delegated.authority.coachDelegated)
  )
    return { kind: 'unauthorized_actor' as const };

  const requestHash = trainingRequestHash({ record, healthDecision: input.healthDecision });
  const existing = await input.revisions.readProposal(input.subject, record.revisionId);
  if (existing && existing.requestHash !== requestHash)
    return { kind: 'request_conflict' as const };
  if (!context.ownerId || !context.evidenceFingerprint) return { kind: 'stale_context' as const };
  const token = {
    ownerId: context.ownerId,
    generation: context.generation,
    profileFingerprint: context.profileFingerprint,
    legacyFingerprint: context.legacyFingerprint,
  };
  if (!existing) {
    if (!profileConfirmsAdult(context.dateOfBirth, input.now))
      return { kind: 'adult_profile_required' as const };
    const health = input.healthDecision;
    if (health.kind === 'review_required') return { kind: 'health_review_required' as const };
    if (health.kind === 'movement_constraint') {
      if (
        !record.constraintId ||
        !input.substitutions ||
        (!health.constraints.maxTrunkDemand && !health.constraints.excludedConcerns?.length)
      )
        return { kind: 'health_review_required' as const };
      const requested = await input.substitutions.request({
        subject: input.subject,
        programId: prior.data.id,
        revisionId: record.revisionId,
        constraintId: record.constraintId,
        constraints: health.constraints,
      });
      if (requested.kind !== 'requested') return { kind: 'health_review_required' as const };
    }
    const next = {
      ...prior.data.delegated,
      temporaryPriority: {
        ...record.priorityFocus,
        expiresAfterBlock: prior.data.delegated.blockNumber,
      },
      constraintId: record.constraintId,
    };
    const proposal = delegatedProposalSchema.parse({
      version: 2,
      id: record.revisionId,
      programId: prior.data.id,
      ownerSubject: input.subject,
      baseRevision: context.headRevision,
      context: token,
      actor: record.actor,
      authority:
        record.actor.kind === 'user'
          ? 'user_review'
          : record.actor.kind === 'trainer'
            ? 'trainer_grant'
            : 'coach_delegation',
      intent: { kind: 'prioritize', ...record.priorityFocus, scope: 'this_block' },
      reason: record.rationale,
      priorState: prior.data,
      proposedState: next,
      plan: next.plan,
      proposedDiff: [
        {
          field: 'temporaryPriority',
          before: prior.data.delegated.temporaryPriority,
          after: next.temporaryPriority,
        },
        {
          field: 'constraintId',
          before: prior.data.delegated.constraintId ?? null,
          after: next.constraintId,
        },
      ],
      policyVersion: DELEGATED_POLICY,
      validation: {
        allowed: true,
        rules: ['reviewed_steering_record', 'resolved_health_policy', 'current_revision'],
        pushback: [],
      },
      inputEvidence: {
        fingerprint: context.evidenceFingerprint,
        observedAt: input.now.toISOString(),
        freshness: 'current',
        evidenceIds: [
          ...new Set(next.plan.sessions.flatMap((s) => s.exercises.flatMap((e) => e.evidenceIds))),
        ],
        signals: {
          training: { freshness: 'missing', observedAt: null },
          feedback: { freshness: 'missing', observedAt: null },
        },
      },
      assumptions: ['Steering metadata only; prescriptions require the deterministic engine.'],
      summary: [],
      reviewPoint: 'before_next_workout',
      rollbackRevision: context.headRevision,
      transition: null,
      createdAt: input.now.toISOString(),
    });
    const created = await input.revisions.createProposal({
      subject: input.subject,
      requestId: record.revisionId,
      requestHash,
      proposal,
    });
    if (created.kind !== 'stored') return created;
    return apply(created.stored.proposal);
  }
  return apply(existing.proposal);

  function apply(proposal: StoredTrainingProposal['proposal']) {
    if (proposal.version !== 2) return { kind: 'request_conflict' as const };
    return input.revisions.decide({
      subject: input.subject,
      proposalId: proposal.id,
      requestId: record.revisionId,
      requestHash,
      decision: 'apply',
      context: token,
      now: input.now.toISOString(),
      revisionId: record.revisionId,
      setup: {
        ...proposal.priorState!,
        programRevisionId: record.revisionId,
        delegated: proposal.proposedState,
      },
      actor: input.actor,
      evidenceFingerprint: proposal.inputEvidence.fingerprint,
    });
  }
}
