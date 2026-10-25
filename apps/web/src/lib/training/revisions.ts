import { z } from 'zod';
import { createHash } from 'node:crypto';
import type {
  TrainingRevisionsPort,
  TrainingRevisionContext,
} from '@/lib/ports/training-revisions';
import { buildMicrocycle, createMesoBlock, isProgramSetup } from './engine';
import { profileConfirmsAdult } from './eligibility';
import { stableTrainingUuid, loadTrainingRecords, type TrainingRecordsSnapshot } from './service';
import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import { progressionTraining, cycleBlock } from './lifecycle';
import { catalogVariantById, isEligibleVariant, resolveAvailableEquipment } from './catalog';
import { TRAINING_CONSENT_VERSION, type TrainingProgramSetup } from './types';
import {
  baselinePlanSchema,
  createProposalInputSchema,
  decideProposalInputSchema,
  initialProposalSchema,
  cycleIntentSchema,
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
  if (proposal.proposedSetup)
    return {
      ...proposal.proposedSetup,
      startedAt:
        proposal.intent.kind === 'repeat_cycle'
          ? now.toISOString()
          : proposal.proposedSetup.startedAt,
      programRevisionId: revisionId,
    };
  return {
    id: proposal.programId,
    consentVersion: TRAINING_CONSENT_VERSION,
    adultConfirmed: true,
    safetyConfirmed: true,
    sessionsPerWeek:
      proposal.intent.kind === 'initial_enrollment' ? proposal.intent.sessionsPerWeek : 2,
    equipment:
      proposal.intent.kind === 'initial_enrollment' ? proposal.intent.equipment : 'dumbbells',
    startedAt: now.toISOString(),
    programRevisionId: revisionId,
    programPolicyVersion: TRAINING_BASELINE_POLICY,
    ...(proposal.intent.kind === 'initial_enrollment' && proposal.intent.weekCount
      ? { cycle: emptyCycle(proposal.intent.weekCount) }
      : {}),
  };
}
function baselinePlan(subject: string, setup: TrainingProgramSetup) {
  const block = setup.cycle
    ? cycleBlock(setup, [], new Date(setup.startedAt))
    : createMesoBlock(setup.startedAt, setup.startedAt);
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
  records?: NativeProductRecordsPort;
  subject: string;
  body: unknown;
  now: Date;
}) {
  const parsed = createProposalInputSchema.safeParse(input.body);
  if (!parsed.success) return { kind: 'unsupported_or_invalid_intent' as const };
  const body = parsed.data;
  const id = stableTrainingUuid(input.subject, 'initial-training-proposal', body.requestId);
  const requestHash = trainingRequestHash(body);
  const context = await input.revisions.readContext(input.subject);
  if (!context) return { kind: 'owner_missing' as const };
  const previous = await input.revisions.readProposal(input.subject, id);
  if (previous)
    return previous.requestHash === requestHash
      ? { kind: 'stored' as const, stored: previous }
      : { kind: 'request_conflict' as const };
  if (body.expectedGeneration !== context.generation) return { kind: 'stale_context' as const };
  if (body.intent.kind !== 'initial_enrollment')
    return createCycleProposal(input, body, context, id, requestHash);
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
    ...(body.intent.weekCount ? { cycle: emptyCycle(body.intent.weekCount) } : {}),
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
  records?: NativeProductRecordsPort;
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
  const setup = setupFor(proposal, input.now, revisionId);
  if (stored.status === 'proposed' && body.decision === 'apply') {
    if (!profileConfirmsAdult(context.dateOfBirth, input.now))
      return { kind: 'adult_profile_required' as const };
    if (trainingRequestHash(token(context)) !== trainingRequestHash(proposal.context))
      return { kind: 'stale_context' as const };
    if (context.headRevision !== proposal.baseRevision)
      return { kind: 'revision_conflict' as const };
    if (proposal.intent.kind !== 'initial_enrollment') {
      if (!input.records || context.trainingFingerprint !== proposal.trainingFingerprint)
        return { kind: 'stale_context' as const };
      const snapshot = await loadTrainingRecords(input.records, input.subject);
      const revised = cycleDraft(snapshot, proposal.intent, proposal.programId, proposal.createdAt);
      if (!revised || trainingRequestHash(revised) !== trainingRequestHash(proposal.proposedSetup))
        return { kind: 'stale_context' as const };
      if (
        trainingRequestHash(cyclePlan(input.subject, revised, snapshot, input.now)) !==
        trainingRequestHash(proposal.plan)
      )
        return { kind: 'policy_changed' as const };
    }
    if (
      proposal.intent.kind === 'initial_enrollment' &&
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

function emptyCycle(weekCount: 4 | 5 | 6) {
  return {
    weekCount,
    number: 1,
    priorities: [],
    constraints: [],
    retainedVariants: [],
    historySetupIds: [],
  };
}

type CycleIntent = z.infer<typeof cycleIntentSchema>;
function cycleDraft(
  snapshot: TrainingRecordsSnapshot,
  intent: CycleIntent,
  programId: string,
  createdAt: string,
) {
  const current = snapshot.setup;
  if (!current) return null;
  if (
    intent.kind === 'repeat_cycle' &&
    snapshot.sessions.some(
      (row) =>
        row.programSetupId === current.id && ['in_progress', 'paused'].includes(String(row.status)),
    )
  )
    return null;
  const block = cycleBlock(current, snapshot.sessions, new Date(createdAt));
  const repeat = intent.kind === 'repeat_cycle';
  // Review is a real boundary. Extending a deload that has already been trained
  // would reinterpret accepted training, so start a reviewed next block instead.
  if (repeat ? block.phase !== 'review' : block.phase === 'review') return null;
  if (
    !repeat &&
    snapshot.sessions.some(
      (row) =>
        row.programSetupId === current.id &&
        row.blockId === block.id &&
        Number(row.weekNumber) >= Math.min(intent.weekCount, current.cycle?.weekCount ?? 4),
    )
  )
    return null;
  const retainedVariants = intent.retainedVariants ?? current.cycle?.retainedVariants ?? [];
  if (new Set(retainedVariants.map((item) => item.fromExerciseId)).size !== retainedVariants.length)
    return null;
  const base = buildMicrocycle({
    setup: { ...current, cycle: undefined, excludedVariantIds: undefined },
    block: { ...block, currentWeek: 1 },
    sessionIds: ['a', 'b', 'c'],
    logs: [],
    feedback: [],
  });
  for (const kept of retainedVariants) {
    const seed = base.sessions
      .flatMap((session) => session.exercises)
      .find((exercise) => exercise.id === kept.fromExerciseId);
    const variant = catalogVariantById(kept.toVariantId);
    const used =
      snapshot.sessions.some(
        (row) =>
          row.programSetupId === current.id &&
          (row.prescription as { exercises?: { id: string }[] })?.exercises?.some(
            (exercise) => exercise.id === kept.toVariantId,
          ),
      ) || current.cycle?.retainedVariants.some((item) => item.toVariantId === kept.toVariantId);
    if (
      !seed ||
      !variant ||
      !used ||
      variant.primaryMuscle !== seed.primaryMuscle ||
      current.excludedVariantIds?.includes(variant.id) ||
      !isEligibleVariant(variant, {
        available: resolveAvailableEquipment({ profile: current.equipment }),
      })
    )
      return null;
  }
  return {
    id: programId,
    consentVersion: TRAINING_CONSENT_VERSION as typeof TRAINING_CONSENT_VERSION,
    adultConfirmed: true as const,
    safetyConfirmed: true as const,
    sessionsPerWeek: current.sessionsPerWeek,
    equipment: current.equipment,
    startedAt: repeat ? createdAt : current.startedAt,
    programPolicyVersion: TRAINING_BASELINE_POLICY,
    ...(current.excludedVariantIds ? { excludedVariantIds: current.excludedVariantIds } : {}),
    cycle: {
      weekCount: intent.weekCount,
      number: repeat
        ? (current.cycle?.number ?? 1) + 1
        : (current.cycle?.number ?? Number(block.id.replace('block-', ''))),
      priorities: intent.priorities ?? (repeat ? [] : (current.cycle?.priorities ?? [])),
      constraints: intent.constraints ?? (repeat ? [] : (current.cycle?.constraints ?? [])),
      retainedVariants,
      historySetupIds: repeat
        ? [...new Set([...(current.cycle?.historySetupIds ?? []), current.id])]
        : (current.cycle?.historySetupIds ?? []),
    },
  };
}

async function createCycleProposal(
  input: {
    revisions: TrainingRevisionsPort;
    records?: NativeProductRecordsPort;
    subject: string;
    now: Date;
  },
  body: z.infer<typeof createProposalInputSchema>,
  context: TrainingRevisionContext,
  id: string,
  requestHash: string,
) {
  if (!input.records || !context.trainingFingerprint || body.intent.kind === 'initial_enrollment')
    return { kind: 'unsupported_or_invalid_intent' as const };
  if (!profileConfirmsAdult(context.dateOfBirth, input.now))
    return { kind: 'adult_profile_required' as const };
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  if (!snapshot.setup || (snapshot.setup.programRevisionId ?? null) !== context.headRevision)
    return { kind: 'stale_context' as const };
  const programId =
    body.intent.kind === 'repeat_cycle'
      ? stableTrainingUuid(input.subject, 'training-cycle', body.requestId)
      : snapshot.setup.id;
  const proposedSetup = cycleDraft(snapshot, body.intent, programId, input.now.toISOString());
  if (!proposedSetup) return { kind: 'cycle_review_required' as const };
  const plan = cyclePlan(input.subject, proposedSetup, snapshot, input.now);
  const proposal = initialProposalSchema.parse({
    version: 1,
    id,
    programId,
    baseRevision: context.headRevision,
    context: token(context),
    actor: { kind: 'self', subject: input.subject },
    authority: 'self_review_required',
    intent: body.intent,
    reason: body.reason,
    priorState: { setupId: snapshot.setup.id, revisionId: context.headRevision },
    proposedDiff: body.intent.kind,
    lifecycleTransition: {
      from: cycleBlock(snapshot.setup, snapshot.sessions, input.now).phase ?? 'accumulation',
      to: body.intent.kind === 'repeat_cycle' ? 'next_block' : 'adjustment',
    },
    proposedSetup,
    trainingFingerprint: context.trainingFingerprint,
    policyVersion: TRAINING_BASELINE_POLICY,
    assumptions: [
      'Selected variants retain their own history and feedback; no history is copied.',
      'Temporary priorities and constraints expire at the block boundary unless explicitly renewed.',
      'Equipment and enduring exclusions remain in effect.',
    ],
    inputEvidence: {
      source: 'canonical_profile_and_explicit_consent',
      observedAt: input.now.toISOString(),
    },
    reviewPoint:
      body.intent.kind === 'repeat_cycle' ? 'before_next_block' : 'before_cycle_revision',
    plan,
    createdAt: input.now.toISOString(),
  });
  return input.revisions.createProposal({
    subject: input.subject,
    requestId: body.requestId,
    requestHash,
    proposal,
  });
}

function cyclePlan(
  subject: string,
  proposedSetup: TrainingProgramSetup,
  snapshot: TrainingRecordsSnapshot,
  now: Date,
) {
  const block = cycleBlock(proposedSetup, snapshot.sessions, now);
  const sourceIds = new Set([
    snapshot.setup!.id,
    ...(snapshot.setup!.cycle?.historySetupIds ?? []),
  ]);
  const completedIds = new Set(
    snapshot.sessions
      .filter((row) => sourceIds.has(String(row.programSetupId)) && progressionTraining(row))
      .map((row) => row.id),
  );
  const logs = snapshot.logs.filter((log) => completedIds.has(log.sessionId));
  const plan = buildMicrocycle({
    setup: proposedSetup,
    block,
    logs,
    feedback: snapshot.feedback,
    sessionIds: Array.from({ length: proposedSetup.sessionsPerWeek }, (_, slot) =>
      stableTrainingUuid(
        subject,
        proposedSetup.id,
        block.id,
        String(block.currentWeek),
        String(slot),
      ),
    ),
  });
  return baselinePlanSchema.parse(plan);
}
