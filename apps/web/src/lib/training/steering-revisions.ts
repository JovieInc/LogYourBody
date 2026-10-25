import { delegatedProgrammingEnabled } from '@/lib/flags/delegated-programming';
import type {
  SteeringHealthPolicyPort,
  SteeringMovementRequestsPort,
} from '@/lib/ports/program-steering';
import type { TrainingRevisionsPort } from '@/lib/ports/training-revisions';
import {
  DELEGATED_POLICY,
  delegatedProposalSchema,
  delegatedSetupSchema,
  programSteeringRecordSchema,
  steeringHealthDecisionSchema,
  type DelegatedProposal,
} from './delegation-contract';
import { canSteer, currentTrainingSetup } from './delegated-revisions';
import { profileConfirmsAdult } from './eligibility';
import { trainingRequestHash } from './revisions';
import { stableTrainingUuid } from './service';

/** Internal writer for an explicitly authorized structured record. The LYB-37
 * transaction owns all persistence, freshness, active-workout and revision races. */
export async function persistSteeringRevision(input: {
  subject: string;
  record: unknown;
  revisions: TrainingRevisionsPort;
  healthPolicy: SteeringHealthPolicyPort;
  movements: SteeringMovementRequestsPort;
  now: Date;
  env?: NodeJS.ProcessEnv;
}) {
  if (!delegatedProgrammingEnabled(input.env)) return { kind: 'disabled' as const };
  const parsed = programSteeringRecordSchema.safeParse(input.record);
  if (!parsed.success) return { kind: 'invalid_request' as const };
  const record = parsed.data;
  const context = await input.revisions.readContext(input.subject);
  if (!context) return { kind: 'owner_missing' as const };
  const prior = delegatedSetupSchema.safeParse(currentTrainingSetup(context));
  if (!prior.success) return { kind: 'delegated_program_required' as const };
  if (
    !canSteer(input.subject, record.actor, prior.data) ||
    (record.actor.kind === 'coach' && !prior.data.delegated.authority.coachDelegated)
  )
    return { kind: 'unauthorized_actor' as const };
  if (!context.ownerId || !context.evidenceFingerprint) return { kind: 'stale_context' as const };
  const token = {
    ownerId: context.ownerId,
    generation: context.generation,
    profileFingerprint: context.profileFingerprint,
    legacyFingerprint: context.legacyFingerprint,
  };
  const proposalId = stableTrainingUuid(input.subject, 'steering-proposal', record.revisionId);
  const requestHash = trainingRequestHash(record);
  const existing = await input.revisions.readProposal(input.subject, proposalId);
  if (existing && existing.requestHash !== requestHash)
    return { kind: 'request_conflict' as const };
  let proposal: DelegatedProposal | undefined;
  if (existing) {
    if (
      existing.proposal.version !== 2 ||
      existing.proposal.intent.kind !== 'record_steering' ||
      existing.proposal.context.ownerId !== context.ownerId
    )
      return { kind: 'stale_context' as const };
    proposal = existing.proposal;
    if (existing.receipt) {
      if (existing.receipt.status === 'applied' && context.headRevision === record.revisionId)
        await requestMovement(proposal);
      return { kind: 'decided' as const, receipt: existing.receipt };
    }
    if (
      trainingRequestHash(proposal.context) !== trainingRequestHash(token) ||
      proposal.baseRevision !== context.headRevision ||
      proposal.inputEvidence.fingerprint !== context.evidenceFingerprint
    )
      return { kind: 'stale_context' as const };
  }
  if (!profileConfirmsAdult(context.dateOfBirth, input.now))
    return { kind: 'adult_profile_required' as const };
  const decision = steeringHealthDecisionSchema.parse(
    await input.healthPolicy.evaluate({
      subject: input.subject,
      program: prior.data.delegated,
      record,
    }),
  );
  if (decision.kind === 'review_required')
    return { kind: 'review_required' as const, reason: decision.reason };
  if (decision.kind === 'movement_constraint' && decision.constraintId !== record.constraintId)
    return { kind: 'policy_changed' as const };
  if (proposal) {
    if (
      proposal.intent.kind !== 'record_steering' ||
      trainingRequestHash(proposal.intent.healthDecision) !== trainingRequestHash(decision)
    )
      return { kind: 'policy_changed' as const };
  } else {
    const next = {
      ...prior.data.delegated,
      steering: record,
      temporaryPriority: record.priorityFocus
        ? { ...record.priorityFocus, expiresAfterBlock: prior.data.delegated.blockNumber }
        : null,
    };
    proposal = delegatedProposalSchema.parse({
      version: 2,
      id: proposalId,
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
      intent: { kind: 'record_steering', record, healthDecision: decision },
      reason: record.rationale,
      priorState: prior.data,
      proposedState: next,
      plan: prior.data.delegated.plan,
      proposedDiff: [
        { field: 'steering', before: prior.data.delegated.steering ?? null, after: record },
        {
          field: 'temporaryPriority',
          before: prior.data.delegated.temporaryPriority,
          after: next.temporaryPriority,
        },
      ],
      policyVersion: DELEGATED_POLICY,
      validation: {
        allowed: true,
        rules: ['structured_steering', 'health_policy', 'unchanged_prescription'],
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
      assumptions: ['Structured intent is recorded without recalculating the saved prescription.'],
      summary: [record.rationale],
      reviewPoint: 'before_next_workout',
      rollbackRevision: context.headRevision,
      transition: null,
      createdAt: input.now.toISOString(),
    });
    const stored = await input.revisions.createProposal({
      subject: input.subject,
      requestId: proposalId,
      requestHash,
      proposal,
    });
    if (stored.kind !== 'stored') return stored;
    const canonical = stored.stored.proposal;
    if (
      canonical.version !== 2 ||
      canonical.intent.kind !== 'record_steering' ||
      trainingRequestHash(canonical.intent.healthDecision) !== trainingRequestHash(decision)
    )
      return { kind: 'policy_changed' as const };
    proposal = canonical;
  }
  const setup = delegatedSetupSchema.parse({
    ...prior.data,
    programRevisionId: record.revisionId,
    delegated: proposal.proposedState,
  });
  const result = await input.revisions.decide({
    subject: input.subject,
    proposalId,
    requestId: stableTrainingUuid(input.subject, 'steering-apply', record.revisionId),
    requestHash,
    decision: 'apply',
    context: token,
    now: input.now.toISOString(),
    revisionId: record.revisionId,
    setup,
    actor: record.actor,
    evidenceFingerprint: context.evidenceFingerprint,
  });
  if (result.kind === 'decided' && result.receipt.status === 'applied')
    await requestMovement(proposal);
  return result;

  async function requestMovement(p: DelegatedProposal) {
    if (
      p.intent.kind !== 'record_steering' ||
      p.intent.healthDecision.kind !== 'movement_constraint'
    )
      return;
    await input.movements.request({
      subject: input.subject,
      programId: p.programId,
      revisionId: record.revisionId,
      constraintId: p.intent.healthDecision.constraintId,
      constraints: p.intent.healthDecision.constraint,
    });
  }
}
