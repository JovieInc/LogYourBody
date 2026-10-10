import { createHash } from 'node:crypto';
import type {
  TrainingRevisionsPort,
  TrainingRevisionContext,
} from '@/lib/ports/training-revisions';
import { buildMicrocycle, createMesoBlock, isProgramSetup } from './engine';
import { profileConfirmsAdult } from './eligibility';
import { stableTrainingUuid } from './service';
import { TRAINING_CONSENT_VERSION, type TrainingProgramSetup } from './types';
import {
  baselinePlanSchema,
  createProposalInputSchema,
  decideProposalInputSchema,
  initialProposalSchema,
  TRAINING_BASELINE_POLICY,
  type InitialTrainingProposal,
} from './revision-contract';

export function trainingRequestHash(value: unknown): string {
  function canonical(item: unknown): unknown {
    if (Array.isArray(item)) return item.map(canonical);
    if (item && typeof item === 'object')
      return Object.fromEntries(
        Object.entries(item)
          .sort(([a], [b]) => a.localeCompare(b))
          .map(([key, val]) => [key, canonical(val)]),
      );
    return item;
  }
  return createHash('sha256')
    .update(JSON.stringify(canonical(value)))
    .digest('hex');
}
function token(context: TrainingRevisionContext) {
  return {
    generation: context.generation,
    profileFingerprint: context.profileFingerprint,
    legacyFingerprint: context.legacyFingerprint,
  };
}
function setupFor(
  proposal: InitialTrainingProposal,
  now: Date,
  revisionId: string,
): TrainingProgramSetup & { programRevisionId: string } {
  return {
    id: proposal.programId,
    consentVersion: TRAINING_CONSENT_VERSION,
    adultConfirmed: true,
    safetyConfirmed: true,
    sessionsPerWeek: proposal.intent.sessionsPerWeek,
    equipment: proposal.intent.equipment,
    startedAt: now.toISOString(),
    programRevisionId: revisionId,
    programPolicyVersion: TRAINING_BASELINE_POLICY,
  };
}
function baselinePlan(subject: string, setup: TrainingProgramSetup) {
  const block = createMesoBlock(setup.startedAt, setup.startedAt);
  return baselinePlanSchema.parse(
    buildMicrocycle({
      setup,
      block,
      logs: [],
      feedback: [],
      sessionIds: Array.from({ length: setup.sessionsPerWeek }, (_, slot) =>
        stableTrainingUuid(subject, setup.id, block.id, '1', String(slot)),
      ),
    }),
  );
}

export async function createInitialTrainingProposal(input: {
  revisions: TrainingRevisionsPort;
  subject: string;
  body: unknown;
  now: Date;
}) {
  const parsed = createProposalInputSchema.safeParse(input.body);
  if (!parsed.success) return { kind: 'unsupported_or_invalid_intent' as const };
  const body = parsed.data;
  const id = stableTrainingUuid(input.subject, 'initial-training-proposal', body.requestId);
  const requestHash = trainingRequestHash(body);
  const previous = await input.revisions.readProposal(input.subject, id);
  if (previous)
    return previous.requestHash === requestHash
      ? { kind: 'stored' as const, stored: previous }
      : { kind: 'request_conflict' as const };
  const context = await input.revisions.readContext(input.subject);
  if (!context) return { kind: 'owner_missing' as const };
  if (body.expectedGeneration !== context.generation) return { kind: 'stale_context' as const };
  if (!profileConfirmsAdult(context.dateOfBirth, input.now))
    return { kind: 'adult_profile_required' as const };
  if (context.headRevision || context.legacySetups.some(isProgramSetup))
    return { kind: 'program_already_enrolled' as const };
  const programId = stableTrainingUuid(input.subject, 'initial-training-program', body.requestId);
  const setup: TrainingProgramSetup = {
    id: programId,
    consentVersion: TRAINING_CONSENT_VERSION,
    adultConfirmed: true,
    safetyConfirmed: true,
    sessionsPerWeek: body.intent.sessionsPerWeek,
    equipment: body.intent.equipment,
    startedAt: input.now.toISOString(),
  };
  const proposal = initialProposalSchema.parse({
    version: 1,
    id,
    programId,
    baseRevision: null,
    context: token(context),
    actor: { kind: 'self', subject: input.subject },
    authority: 'self_review_required',
    intent: body.intent,
    reason: body.reason,
    priorState: null,
    proposedDiff: 'create_supported_baseline_program',
    policyVersion: TRAINING_BASELINE_POLICY,
    assumptions: [
      'This is the existing two- or three-day baseline, not a personalized response to additional goals or constraints.',
      'The program starts when you apply it.',
    ],
    inputEvidence: {
      source: 'canonical_profile_and_explicit_consent',
      observedAt: input.now.toISOString(),
    },
    reviewPoint: 'before_first_workout',
    plan: baselinePlan(input.subject, setup),
    createdAt: input.now.toISOString(),
  });
  return input.revisions.createProposal({
    subject: input.subject,
    requestId: body.requestId,
    requestHash,
    proposal,
  });
}

export async function decideInitialTrainingProposal(input: {
  revisions: TrainingRevisionsPort;
  subject: string;
  body: unknown;
  now: Date;
}) {
  const parsed = decideProposalInputSchema.safeParse(input.body);
  if (!parsed.success) return { kind: 'invalid_request' as const };
  const body = parsed.data;
  const stored = await input.revisions.readProposal(input.subject, body.proposalId);
  if (!stored) return { kind: 'proposal_not_found' as const };
  const proposal = stored.proposal;
  const revisionId = stableTrainingUuid(input.subject, 'training-revision', proposal.id);
  const setup = setupFor(proposal, input.now, revisionId);
  const context = await input.revisions.readContext(input.subject);
  if (!context) return { kind: 'owner_missing' as const };
  if (stored.status === 'proposed' && body.decision === 'apply') {
    if (!profileConfirmsAdult(context.dateOfBirth, input.now))
      return { kind: 'adult_profile_required' as const };
    if (trainingRequestHash(token(context)) !== trainingRequestHash(proposal.context))
      return { kind: 'stale_context' as const };
    if (context.headRevision) return { kind: 'revision_conflict' as const };
    if (
      trainingRequestHash(baselinePlan(input.subject, setup)) !== trainingRequestHash(proposal.plan)
    )
      return { kind: 'policy_changed' as const };
  }
  return input.revisions.decide({
    subject: input.subject,
    proposalId: proposal.id,
    requestId: body.requestId,
    requestHash: trainingRequestHash(body),
    decision: body.decision,
    context: token(context),
    now: input.now.toISOString(),
    revisionId,
    setup,
  });
}
