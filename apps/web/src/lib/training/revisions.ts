import { createHash } from 'node:crypto';
import type { z } from 'zod';
import type {
  TrainingRevisionsPort,
  TrainingRevisionContext,
} from '@/lib/ports/training-revisions';
import { buildMicrocycle, createMesoBlock, isProgramSetup } from './engine';
import { profileConfirmsAdult } from './eligibility';
import { stableTrainingUuid } from './service';
import { TRAINING_CONSENT_VERSION, type TrainingProgramSetup } from './types';
import {
  applyPlanEditOps,
  layoutForPlan,
  planForLayout,
} from './plan-edits';
import {
  baselinePlanSchema,
  createProposalInputSchema,
  decideProposalInputSchema,
  initialIntentSchema,
  initialProposalSchema,
  planEditIntentSchema,
  planEditProposalSchema,
  TRAINING_BASELINE_POLICY,
  type InitialTrainingProposal,
  type PlanEditProposal,
  type PlanLayout,
  type StoredTrainingRevision,
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
  if (!context.ownerId) throw new Error('training_owner_incarnation_required');
  return {
    ownerId: context.ownerId,
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

/** The layout a revision installs: edits store one explicitly; the initial
 * baseline revision derives it from its reviewed plan. */
function layoutForRevision(revision: StoredTrainingRevision): PlanLayout | null {
  if (revision.layout) return revision.layout;
  return layoutForPlan(revision.proposal.plan);
}

type CreateBody = z.infer<typeof createProposalInputSchema>;

async function createEnrollmentProposal(input: {
  revisions: TrainingRevisionsPort;
  subject: string;
  body: Omit<CreateBody, 'intent'> & { intent: z.infer<typeof initialIntentSchema> };
  now: Date;
  context: TrainingRevisionContext;
  requestHash: string;
  id: string;
}) {
  const { subject, body, context, id } = input;
  if (!profileConfirmsAdult(context.dateOfBirth, input.now))
    return { kind: 'adult_profile_required' as const };
  if (context.headRevision || context.legacySetups.some(isProgramSetup))
    return { kind: 'program_already_enrolled' as const };
  const programId = stableTrainingUuid(subject, 'initial-training-program', body.requestId);
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
    actor: { kind: 'self', subject },
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
    plan: baselinePlan(subject, setup),
    createdAt: input.now.toISOString(),
  });
  return input.revisions.createProposal({
    subject,
    requestId: body.requestId,
    requestHash: input.requestHash,
    proposal,
  });
}

async function createPlanEditProposal(input: {
  revisions: TrainingRevisionsPort;
  subject: string;
  body: Omit<CreateBody, 'intent'> & { intent: z.infer<typeof planEditIntentSchema> };
  now: Date;
  context: TrainingRevisionContext;
  requestHash: string;
  id: string;
}) {
  const { subject, body, context, id } = input;
  if (!profileConfirmsAdult(context.dateOfBirth, input.now))
    return { kind: 'adult_profile_required' as const };
  if (!context.headRevision) return { kind: 'program_not_enrolled' as const };
  const head = await input.revisions.readHeadRevision(subject);
  if (!head || head.id !== context.headRevision) return { kind: 'revision_conflict' as const };
  const baseLayout = layoutForRevision(head);
  if (!baseLayout) return { kind: 'edit_not_applicable' as const };
  const applied = applyPlanEditOps({
    base: baseLayout,
    operations: body.intent.operations,
    setup: head.setup,
  });
  if (applied.kind !== 'applied') return { kind: 'edit_not_applicable' as const };
  const proposal = planEditProposalSchema.parse({
    version: 1,
    id,
    programId: head.setup.id,
    baseRevision: head.id,
    context: token(context),
    actor: { kind: 'self', subject },
    authority: 'self_review_required',
    intent: body.intent,
    reason: body.reason,
    priorState: trainingRequestHash(baseLayout),
    proposedDiff: applied.diffs,
    policyVersion: TRAINING_BASELINE_POLICY,
    assumptions: [
      'Edits apply to future sessions; a session already in progress keeps its snapshot.',
      'Rep ranges, effort targets and progression remain engine-computed from logged history.',
    ],
    inputEvidence: {
      source: 'canonical_head_revision_and_typed_operations',
      observedAt: input.now.toISOString(),
    },
    reviewPoint: 'before_next_workout',
    layout: applied.layout,
    plan: planForLayout(subject, head.setup, applied.layout),
    createdAt: input.now.toISOString(),
  });
  return input.revisions.createProposal({
    subject,
    requestId: body.requestId,
    requestHash: input.requestHash,
    proposal,
  });
}

export async function createTrainingProposal(input: {
  revisions: TrainingRevisionsPort;
  subject: string;
  body: unknown;
  now: Date;
}) {
  const parsed = createProposalInputSchema.safeParse(input.body);
  if (!parsed.success) return { kind: 'unsupported_or_invalid_intent' as const };
  const body = parsed.data;
  const salt =
    body.intent.kind === 'plan_edit' ? 'training-plan-edit' : 'initial-training-proposal';
  const id = stableTrainingUuid(input.subject, salt, body.requestId);
  const requestHash = trainingRequestHash(body);
  const context = await input.revisions.readContext(input.subject);
  if (!context) return { kind: 'owner_missing' as const };
  const previous = await input.revisions.readProposal(input.subject, id);
  if (previous)
    return previous.requestHash === requestHash
      ? { kind: 'stored' as const, stored: previous }
      : { kind: 'request_conflict' as const };
  if (body.expectedGeneration !== context.generation) return { kind: 'stale_context' as const };
  const shared = {
    revisions: input.revisions,
    subject: input.subject,
    now: input.now,
    context,
    requestHash,
    id,
  };
  if (body.intent.kind === 'plan_edit')
    return createPlanEditProposal({ ...shared, body });
  return createEnrollmentProposal({ ...shared, body });
}

export async function decideTrainingProposal(input: {
  revisions: TrainingRevisionsPort;
  subject: string;
  body: unknown;
  now: Date;
}) {
  const parsed = decideProposalInputSchema.safeParse(input.body);
  if (!parsed.success) return { kind: 'invalid_request' as const };
  const body = parsed.data;
  const context = await input.revisions.readContext(input.subject);
  if (!context) return { kind: 'owner_missing' as const };
  const stored = await input.revisions.readProposal(input.subject, body.proposalId);
  if (!stored) return { kind: 'proposal_not_found' as const };
  const proposal = stored.proposal;
  const revisionId = stableTrainingUuid(input.subject, 'training-revision', proposal.id);
  const isEdit = proposal.intent.kind === 'plan_edit';
  const setup = isEdit ? null : setupFor(proposal as InitialTrainingProposal, input.now, revisionId);
  let layout: PlanLayout | null = null;
  if (stored.status === 'proposed' && body.decision === 'apply') {
    if (!profileConfirmsAdult(context.dateOfBirth, input.now))
      return { kind: 'adult_profile_required' as const };
    if (trainingRequestHash(token(context)) !== trainingRequestHash(proposal.context))
      return { kind: 'stale_context' as const };
    if (!isEdit) {
      if (context.headRevision) return { kind: 'revision_conflict' as const };
      if (
        trainingRequestHash(baselinePlan(input.subject, setup!)) !==
        trainingRequestHash(proposal.plan)
      )
        return { kind: 'policy_changed' as const };
    } else {
      const editProposal = proposal as PlanEditProposal;
      if (context.headRevision !== editProposal.baseRevision)
        return { kind: 'revision_conflict' as const };
      const head = await input.revisions.readHeadRevision(input.subject);
      const baseLayout = head ? layoutForRevision(head) : null;
      if (!head || head.id !== context.headRevision || !baseLayout)
        return { kind: 'revision_conflict' as const };
      const recomputed = applyPlanEditOps({
        base: baseLayout,
        operations: editProposal.intent.operations,
        setup: head.setup,
      });
      if (
        recomputed.kind !== 'applied' ||
        trainingRequestHash(recomputed.layout) !== trainingRequestHash(editProposal.layout) ||
        trainingRequestHash(
          planForLayout(input.subject, head.setup, recomputed.layout),
        ) !== trainingRequestHash(editProposal.plan)
      )
        return { kind: 'policy_changed' as const };
      layout = recomputed.layout;
    }
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
    baseRevision: isEdit ? (proposal as PlanEditProposal).baseRevision : null,
    setup,
    layout,
  });
}
