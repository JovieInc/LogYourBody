import { createHash } from 'node:crypto';
import type {
  TrainingRevisionsPort,
  TrainingRevisionContext,
} from '@/lib/ports/training-revisions';
import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import { catalogVariantById, isEligibleVariant, resolveAvailableEquipment } from './catalog';
import { cycleBlock, completedCycleSessions } from './cycle-lifecycle';
import { buildMicrocycle, isProgramSetup, CYCLE_RIR_LADDERS } from './engine';
import { profileConfirmsAdult } from './eligibility';
import {
  stableTrainingUuid,
  loadTrainingRecords,
  applyConfiguredVariants,
  type TrainingRecordsSnapshot,
} from './service';
import { TRAINING_CONSENT_VERSION, type TrainingProgramSetup } from './types';
import {
  baselinePlanSchema,
  createProposalInputSchema,
  decideProposalInputSchema,
  initialProposalSchema,
  TRAINING_BASELINE_POLICY,
  TRAINING_CYCLE_POLICY,
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
        proposal.intent.kind === 'revise_cycle'
          ? proposal.proposedSetup.startedAt
          : now.toISOString(),
      programRevisionId: revisionId,
      programPolicyVersion: proposal.policyVersion,
    };
  if (proposal.intent.kind !== 'initial_enrollment')
    throw new Error('training_cycle_setup_missing');
  return {
    ...(proposal.intent.weekCount ? { cycle: emptyCycle(proposal.intent.weekCount) } : {}),
    id: proposal.programId,
    consentVersion: TRAINING_CONSENT_VERSION,
    adultConfirmed: true,
    safetyConfirmed: true,
    sessionsPerWeek: proposal.intent.sessionsPerWeek,
    equipment: proposal.intent.equipment,
    ...(proposal.intent.declaredEquipment
      ? { declaredEquipment: proposal.intent.declaredEquipment }
      : {}),
    ...(proposal.intent.excludedVariantIds
      ? { excludedVariantIds: proposal.intent.excludedVariantIds }
      : {}),
    startedAt: now.toISOString(),
    programRevisionId: revisionId,
    programPolicyVersion: proposal.policyVersion,
  };
}
function emptyCycle(weekCount: 4 | 5 | 6) {
  return {
    weekCount,
    temporaryPriorities: [],
    temporaryConstraints: [],
    retainedVariants: [],
    historyProgramIds: [],
  };
}
function baselinePlan(
  subject: string,
  setup: TrainingProgramSetup,
  snapshot?: TrainingRecordsSnapshot,
) {
  const block = cycleBlock(
    setup,
    snapshot?.sessions ?? [],
    snapshot?.logs ?? [],
    new Date(setup.startedAt),
  );
  const plan = buildMicrocycle({
    setup,
    block,
    logs: snapshot?.logs ?? [],
    feedback: snapshot?.feedback ?? [],
    sessionIds: Array.from({ length: setup.sessionsPerWeek }, (_, slot) =>
      stableTrainingUuid(subject, setup.id, block.id, String(block.currentWeek), String(slot)),
    ),
  });
  return baselinePlanSchema.parse({
    ...plan,
    sessions: plan.sessions.map((session) =>
      applyConfiguredVariants(session, setup, snapshot?.logs ?? []),
    ),
  });
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
  if (!profileConfirmsAdult(context.dateOfBirth, input.now))
    return { kind: 'adult_profile_required' as const };
  if (body.intent.kind !== 'initial_enrollment') {
    if (!input.records) return { kind: 'unsupported_or_invalid_intent' as const };
    const snapshot = await loadTrainingRecords(input.records, input.subject);
    const prepared = prepareCycleProposal(input.subject, body, context, snapshot, input.now, id);
    if ('kind' in prepared) return prepared;
    return input.revisions.createProposal({
      subject: input.subject,
      requestId: body.requestId,
      requestHash,
      proposal: prepared.proposal,
    });
  }
  if (context.headRevision || context.legacySetups.some(isProgramSetup))
    return { kind: 'program_already_enrolled' as const };
  const programId = stableTrainingUuid(input.subject, 'initial-training-program', body.requestId);
  const setup: TrainingProgramSetup = {
    ...(body.intent.weekCount ? { cycle: emptyCycle(body.intent.weekCount) } : {}),
    id: programId,
    consentVersion: TRAINING_CONSENT_VERSION,
    adultConfirmed: true,
    safetyConfirmed: true,
    sessionsPerWeek: body.intent.sessionsPerWeek,
    equipment: body.intent.equipment,
    ...(body.intent.declaredEquipment ? { declaredEquipment: body.intent.declaredEquipment } : {}),
    ...(body.intent.excludedVariantIds
      ? { excludedVariantIds: body.intent.excludedVariantIds }
      : {}),
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
    policyVersion: setup.cycle ? TRAINING_CYCLE_POLICY : TRAINING_BASELINE_POLICY,
    assumptions: [
      'This is the existing two- or three-day baseline, not a personalized response to additional goals or constraints.',
      'The program starts when you apply it.',
    ],
    inputEvidence: {
      source: 'canonical_profile_and_explicit_consent',
      observedAt: input.now.toISOString(),
    },
    reviewPoint: 'before_first_workout',
    ...(setup.cycle ? { schedule: cycleSchedule(setup.cycle.weekCount) } : {}),
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
  if (proposal.version !== 1) return { kind: 'unsupported_or_invalid_intent' as const };
  const revisionId = stableTrainingUuid(input.subject, 'training-revision', proposal.id);
  const setup = setupFor(proposal, input.now, revisionId);
  if (stored.status === 'proposed' && body.decision === 'apply') {
    if (!profileConfirmsAdult(context.dateOfBirth, input.now))
      return { kind: 'adult_profile_required' as const };
    if (trainingRequestHash(token(context)) !== trainingRequestHash(proposal.context))
      return { kind: 'stale_context' as const };
    if (context.headRevision !== proposal.baseRevision)
      return { kind: 'revision_conflict' as const };
    let snapshot: TrainingRecordsSnapshot | undefined;
    if (proposal.intent.kind !== 'initial_enrollment') {
      if (!input.records || !proposal.priorState) return { kind: 'stale_context' as const };
      if (context.trainingFingerprint !== proposal.priorState.trainingFingerprint)
        return { kind: 'stale_context' as const };
      snapshot = await loadTrainingRecords(input.records, input.subject);
      if (
        proposal.intent.kind === 'repeat_cycle' &&
        snapshot.sessions.some(
          (row) =>
            row.programSetupId === proposal.priorState!.setup.id &&
            (row.status === 'in_progress' || row.status === 'paused'),
        )
      )
        return { kind: 'active_session_requires_review' as const };
      snapshot = historySnapshot(snapshot, setup);
    }
    if (
      setup.cycle &&
      trainingRequestHash(cycleSchedule(setup.cycle.weekCount)) !==
        trainingRequestHash(proposal.schedule)
    )
      return { kind: 'policy_changed' as const };
    if (
      trainingRequestHash(baselinePlan(input.subject, setup, snapshot)) !==
      trainingRequestHash(proposal.plan)
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

function historySnapshot(
  snapshot: TrainingRecordsSnapshot,
  setup: TrainingProgramSetup,
): TrainingRecordsSnapshot {
  const ids = new Set([setup.id, ...(setup.cycle?.historyProgramIds ?? [])]);
  const sessions = snapshot.sessions.filter((row) => ids.has(String(row.programSetupId)));
  const completedIds = new Set(
    sessions.filter((row) => row.status === 'completed').map((row) => row.id),
  );
  const sessionIds = new Set(sessions.map((row) => row.id));
  return {
    ...snapshot,
    logs: snapshot.logs.filter((log) => completedIds.has(log.sessionId)),
    feedback: snapshot.feedback.filter((item) => sessionIds.has(item.sessionId)),
  };
}

function prepareCycleProposal(
  subject: string,
  body: ReturnType<typeof createProposalInputSchema.parse>,
  context: TrainingRevisionContext,
  snapshot: TrainingRecordsSnapshot,
  now: Date,
  id: string,
):
  | { proposal: InitialTrainingProposal }
  | {
      kind:
        | 'program_not_enrolled'
        | 'active_session_requires_review'
        | 'deload_boundary_requires_review'
        | 'cycle_review_required'
        | 'invalid_reuse_selection';
    } {
  const intent = body.intent;
  if (intent.kind === 'initial_enrollment') throw new Error('training_cycle_intent_required');
  const current = snapshot.setup;
  if (!current || current.delegated || !context.trainingFingerprint)
    return { kind: 'program_not_enrolled' as const };
  const active = snapshot.sessions.filter(
    (row) =>
      row.programSetupId === current.id &&
      (row.status === 'in_progress' || row.status === 'paused'),
  );
  if (intent.kind === 'repeat_cycle' && active.length)
    return { kind: 'active_session_requires_review' as const };
  if (
    intent.kind === 'revise_cycle' &&
    active.some(
      (row) => Number(row.weekNumber) >= Math.min(intent.weekCount, current.cycle?.weekCount ?? 4),
    )
  )
    return { kind: 'deload_boundary_requires_review' as const };
  const completed = completedCycleSessions(current, snapshot.sessions, snapshot.logs).length;
  const currentBlock = cycleBlock(current, snapshot.sessions, snapshot.logs, now);
  if (intent.kind === 'repeat_cycle' && currentBlock.phase !== 'review')
    return { kind: 'cycle_review_required' as const };
  if (
    intent.kind === 'revise_cycle' &&
    current.cycle &&
    intent.weekCount !== current.cycle.weekCount &&
    (completed > (intent.weekCount - 1) * current.sessionsPerWeek ||
      completed > (current.cycle.weekCount - 1) * current.sessionsPerWeek)
  )
    return { kind: 'deload_boundary_requires_review' as const };
  const repeat = intent.kind === 'repeat_cycle';
  const retainedVariants = repeat ? intent.keepVariants : (current.cycle?.retainedVariants ?? []);
  const available = resolveAvailableEquipment({
    profile: current.equipment,
    declared: current.declaredEquipment,
  });
  // Keep only variants actually used in this block. A reuse request is not a swap authoring API.
  const used = new Set(
    snapshot.sessions
      .filter((row) => row.programSetupId === current.id)
      .flatMap((row) =>
        ((row.prescription as { exercises?: { id: string }[] })?.exercises ?? []).map(
          (exercise) => exercise.id,
        ),
      ),
  );
  const baseline = baselinePlan(subject, {
    ...current,
    cycle: undefined,
    excludedVariantIds: undefined,
  }).sessions.flatMap((session) => session.exercises);
  if (
    new Set(retainedVariants.map((item) => item.fromExerciseId)).size !== retainedVariants.length ||
    retainedVariants.some((selection) => {
      const original = baseline.find((exercise) => exercise.id === selection.fromExerciseId);
      const variant = catalogVariantById(selection.toVariantId);
      return (
        !original ||
        !variant ||
        variant.primaryMuscle !== original.primaryMuscle ||
        (repeat && !used.has(variant.id)) ||
        current.excludedVariantIds?.includes(variant.id) ||
        !isEligibleVariant(variant, { available })
      );
    })
  )
    return { kind: 'invalid_reuse_selection' as const };
  const setup: TrainingProgramSetup = {
    ...current,
    id: repeat ? stableTrainingUuid(subject, 'next-training-cycle', body.requestId) : current.id,
    startedAt: repeat ? now.toISOString() : current.startedAt,
    cycle: {
      weekCount: intent.weekCount,
      retainedVariants,
      blockId: repeat ? 'block-1' : (current.cycle?.blockId ?? currentBlock.id),
      temporaryPriorities:
        !repeat || intent.renewPriorities ? (current.cycle?.temporaryPriorities ?? []) : [],
      temporaryConstraints:
        !repeat || intent.renewConstraints ? (current.cycle?.temporaryConstraints ?? []) : [],
      historyProgramIds: repeat
        ? [...new Set([...(current.cycle?.historyProgramIds ?? []), current.id])]
        : (current.cycle?.historyProgramIds ?? []),
    },
  };
  const proposal = initialProposalSchema.parse({
    version: 1,
    id,
    programId: setup.id,
    baseRevision: context.headRevision,
    context: token(context),
    actor: { kind: 'self', subject },
    authority: 'self_review_required',
    intent,
    reason: body.reason,
    priorState: { setup: current, trainingFingerprint: context.trainingFingerprint },
    lifecyclePhase: repeat ? 'next_block' : 'adjustment',
    proposedDiff: intent.kind,
    proposedSetup: setup,
    schedule: cycleSchedule(intent.weekCount),
    policyVersion: TRAINING_CYCLE_POLICY,
    assumptions: [
      repeat
        ? 'Temporary priorities and constraints expire unless explicitly renewed.'
        : 'Completed training and saved history are preserved; the final week remains a deload.',
      'Equipment and enduring exclusions remain in force.',
      ...(!repeat
        ? [
            'An unfinished workout keeps its saved targets; the revised schedule applies to future sessions.',
          ]
        : []),
      ...retainedVariants.map(
        (item) =>
          `${catalogVariantById(item.toVariantId)?.name ?? item.toVariantId}: ${item.reason}`,
      ),
    ],
    inputEvidence: {
      source: 'canonical_profile_and_explicit_consent',
      observedAt: now.toISOString(),
    },
    reviewPoint: repeat ? 'before_next_block' : 'before_cycle_revision',
    plan: baselinePlan(subject, setup, historySnapshot(snapshot, setup)),
    createdAt: now.toISOString(),
  });
  return { proposal };
}

function cycleSchedule(length: 4 | 5 | 6) {
  return CYCLE_RIR_LADDERS[length].map((targetRir, index) => ({
    week: index + 1,
    targetRir,
    deload: index === length - 1,
    setsPerExercise: index === length - 1 ? 1 : 2,
  }));
}
