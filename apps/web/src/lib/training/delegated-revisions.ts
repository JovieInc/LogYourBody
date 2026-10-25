import type { NativeProductRecordsPort } from '@/lib/ports/native-product-records';
import type {
  TrainingRevisionContext,
  TrainingRevisionsPort,
} from '@/lib/ports/training-revisions';
import {
  DELEGATED_POLICY,
  delegatedProposalSchema,
  delegatedSetupSchema,
  priorSetupSchema,
  steeringRequestSchema,
  type DelegatedProgram,
  type DelegatedProposal,
  type RevisionActor,
} from './delegation-contract';
import {
  interpretSteering,
  PlanningQuestion,
  recommendProgram,
  priorityLabels,
  resolvePlanningInputs,
  steerProgram,
  validateProgram,
} from './delegated-planning';
import { profileConfirmsAdult } from './eligibility';
import { CONTROLLER_POLICY } from './controller';
import { isProgramSetup } from './engine';
import { decideProposalInputSchema } from './revision-contract';
import { trainingRequestHash } from './revisions';
import {
  loadTrainingRecords,
  plannedSessionCount,
  stableTrainingUuid,
  type TrainingRecordsSnapshot,
} from './service';
import { TRAINING_CONSENT_VERSION, type TrainingProgramSetup } from './types';

type Dependencies = {
  revisions: TrainingRevisionsPort;
  records: NativeProductRecordsPort;
  subject: string;
  actor: RevisionActor;
  now: Date;
};
function token(c: TrainingRevisionContext) {
  if (!c.ownerId) throw new Error('training_owner_incarnation_required');
  return {
    ownerId: c.ownerId,
    generation: c.generation,
    profileFingerprint: c.profileFingerprint,
    legacyFingerprint: c.legacyFingerprint,
  };
}
export function currentTrainingSetup(c: TrainingRevisionContext) {
  return c.legacySetups
    .filter(isProgramSetup)
    .filter((s) => (s.programRevisionId ?? null) === c.headRevision)
    .sort((a, b) => Date.parse(b.startedAt) - Date.parse(a.startedAt))[0];
}
export function canSteer(
  subject: string,
  actor: RevisionActor,
  setup: TrainingProgramSetup | null,
): boolean {
  return actor.kind === 'user'
    ? actor.subject === subject
    : actor.kind === 'trainer'
      ? setup?.delegated?.authority.trainerSubject === actor.subject
      : actor.subject === 'lyb-coach';
}
/** Every week/slot needs an actual completed workout with logged work. Missed,
 * skipped and empty "end" receipts cannot close a block. */
export function completedBlock(
  setup: TrainingProgramSetup,
  snapshot: TrainingRecordsSnapshot,
): boolean {
  if (!setup.delegated) return false;
  const blockId = `delegated-block-${setup.delegated.blockNumber}`;
  return Array.from({ length: setup.delegated.plan.weekCount }, (_, i) => i + 1).every((week) =>
    Array.from({ length: plannedSessionCount(setup, week) }, (_, slot) => slot).every((slot) =>
      snapshot.sessions.some(
        (s) =>
          s.programSetupId === setup.id &&
          s.blockId === blockId &&
          s.weekNumber === week &&
          s.slot === slot &&
          s.status === 'completed' &&
          snapshot.logs.some((l) => l.sessionId === s.id),
      ),
    ),
  );
}
function meaningfulDiff(
  before: unknown,
  after: unknown,
  prefix = '',
): DelegatedProposal['proposedDiff'] {
  if (trainingRequestHash(before) === trainingRequestHash(after)) return [];
  if (
    before &&
    after &&
    typeof before === 'object' &&
    typeof after === 'object' &&
    !Array.isArray(before) &&
    !Array.isArray(after)
  ) {
    const a = before as Record<string, unknown>,
      b = after as Record<string, unknown>;
    return [...new Set([...Object.keys(a), ...Object.keys(b)])].flatMap((key) =>
      meaningfulDiff(a[key] ?? null, b[key] ?? null, prefix ? `${prefix}.${key}` : key),
    );
  }
  return [{ field: prefix || 'program', before: before ?? null, after: after ?? null }];
}

function signalFreshness(times: string[], now: Date) {
  const latest = Math.max(...times.map(Date.parse).filter(Number.isFinite));
  return {
    freshness: !Number.isFinite(latest)
      ? ('missing' as const)
      : latest > now.getTime() ||
          now.getTime() - latest > CONTROLLER_POLICY.staleSignalDays * 86400000
        ? ('stale' as const)
        : ('fresh' as const),
    observedAt: Number.isFinite(latest) ? new Date(latest).toISOString() : null,
  };
}

export async function createDelegatedProposal(input: Dependencies & { body: unknown }) {
  const parsed = steeringRequestSchema.safeParse(input.body);
  if (!parsed.success) return { kind: 'unsupported_or_invalid_intent' as const };
  const body = parsed.data;
  const context = await input.revisions.readContext(input.subject);
  if (!context) return { kind: 'owner_missing' as const };
  const rawSetup = currentTrainingSetup(context);
  const prior = delegatedSetupSchema.safeParse(rawSetup);
  const baselinePrior =
    !prior.success && isProgramSetup(rawSetup) ? priorSetupSchema.parse(rawSetup) : null;
  if (!canSteer(input.subject, input.actor, isProgramSetup(rawSetup) ? rawSetup : null))
    return { kind: 'unauthorized_actor' as const };
  const id = stableTrainingUuid(input.subject, 'delegated-proposal', body.requestId);
  const requestHash = trainingRequestHash({ body, actor: input.actor });
  const existing = await input.revisions.readProposal(input.subject, id);
  if (existing)
    return existing.requestHash === requestHash
      ? { kind: 'stored' as const, stored: existing }
      : { kind: 'request_conflict' as const };
  if (body.expectedGeneration !== context.generation) return { kind: 'stale_context' as const };
  if (!profileConfirmsAdult(context.dateOfBirth, input.now))
    return { kind: 'adult_profile_required' as const };
  const intent = body.intent ?? interpretSteering(body.utterance!);
  if (!intent)
    return {
      kind: 'question' as const,
      field: 'intent',
      question: 'Which exact exercise or plan constraint would you like to change?',
    };
  if (
    input.actor.kind !== 'user' &&
    ['recommend', 'authorize_trainer', 'delegate_coach', 'restore'].includes(intent.kind)
  )
    return { kind: 'unauthorized_actor' as const };
  const snapshot = await loadTrainingRecords(input.records, input.subject);
  const evidenceFingerprint = context.evidenceFingerprint;
  if (!evidenceFingerprint) throw new Error('planning_evidence_required');
  const source = body.baseProposalId
    ? await input.revisions.readProposal(input.subject, body.baseProposalId)
    : null;
  const sourceProposal = source?.proposal.version === 2 ? source.proposal : null;
  if (sourceProposal && intent.kind === 'next_block')
    return { kind: 'unsupported_or_invalid_intent' as const };
  if (
    body.baseProposalId &&
    (!sourceProposal ||
      source?.status !== 'proposed' ||
      trainingRequestHash(sourceProposal.context) !== trainingRequestHash(token(context)) ||
      sourceProposal.inputEvidence.fingerprint !== evidenceFingerprint)
  )
    return { kind: 'stale_context' as const };
  try {
    let next: DelegatedProgram;
    if (intent.kind === 'recommend') {
      if (
        prior.success ||
        ((context.headRevision || context.legacySetups.some(isProgramSetup)) && !baselinePrior)
      )
        return { kind: 'program_already_enrolled' as const };
      const inputs = resolvePlanningInputs(context.canonicalTrainingInputs, {
        ...(baselinePrior
          ? { sessionsPerWeek: baselinePrior.sessionsPerWeek, equipment: baselinePrior.equipment }
          : {}),
        ...intent.inputs,
      });
      next = recommendProgram(inputs, intent.weekCount);
    } else {
      const working =
        sourceProposal?.proposedState ?? (prior.success ? prior.data.delegated : null);
      if (!working) return { kind: 'delegated_program_required' as const };
      if (intent.kind === 'next_block' && (!prior.success || !completedBlock(prior.data, snapshot)))
        return { kind: 'block_incomplete' as const };
      if (intent.kind === 'restore') {
        if (!prior.success) return { kind: 'delegated_program_required' as const };
        const history = await input.revisions.exportForSubject(input.subject);
        const revision = history.revisions.find(
          (r) => (r as { id?: string }).id === intent.revisionId,
        ) as { setup?: unknown } | undefined;
        const restored = delegatedSetupSchema.safeParse(revision?.setup);
        if (!restored.success) return { kind: 'revision_not_found' as const };
        // Restore an allowed program, never rewind training history or authority.
        next = {
          ...restored.data.delegated,
          blockNumber: prior.data.delegated.blockNumber,
          authority: prior.data.delegated.authority,
          completedWeeks: { ...prior.data.delegated.completedWeeks },
        };
        if (next.temporaryPriority)
          next.temporaryPriority = {
            ...next.temporaryPriority,
            expiresAfterBlock: next.blockNumber,
          };
        if (
          next.inputs.equipment !== prior.data.delegated.inputs.equipment ||
          prior.data.delegated.inputs.limitations.some(
            (v) => !next.inputs.limitations.includes(v),
          ) ||
          prior.data.delegated.inputs.excludedVariantIds.some(
            (v) => !next.inputs.excludedVariantIds.includes(v),
          )
        )
          return { kind: 'policy_changed' as const };
        if (validateProgram(next)) return { kind: 'policy_changed' as const };
      } else next = steerProgram(working, intent);
    }
    if (prior.success && next.blockNumber === prior.data.delegated.blockNumber) {
      const blockId = `delegated-block-${next.blockNumber}`;
      for (let week = 1; week <= prior.data.delegated.plan.weekCount; week++) {
        const count = plannedSessionCount(prior.data, week);
        if (
          Array.from({ length: count }, (_, slot) => slot).every((slot) =>
            snapshot.sessions.some(
              (s) =>
                s.programSetupId === prior.data.id &&
                s.blockId === blockId &&
                s.weekNumber === week &&
                s.slot === slot &&
                s.status === 'completed' &&
                snapshot.logs.some((l) => l.sessionId === s.id),
            ),
          )
        )
          next.completedWeeks[String(week)] = count;
      }
    }
    if (
      input.actor.kind !== 'user' &&
      prior.success &&
      trainingRequestHash(next.authority) !== trainingRequestHash(prior.data.delegated.authority)
    )
      return { kind: 'unauthorized_actor' as const };
    if (validateProgram(next)) return { kind: 'policy_changed' as const };
    const changedContext = await input.revisions.readContext(input.subject);
    if (
      !changedContext ||
      trainingRequestHash(token(changedContext)) !== trainingRequestHash(token(context)) ||
      changedContext.evidenceFingerprint !== evidenceFingerprint
    )
      return { kind: 'stale_context' as const };
    const isCoach = intent.kind === 'recommend' || intent.kind === 'next_block';
    const actor: RevisionActor = isCoach ? { kind: 'coach', subject: 'lyb-coach' } : input.actor;
    const expiringPriority =
      intent.kind === 'next_block' ? prior.data?.delegated.temporaryPriority : null;
    const expired = expiringPriority ? priorityLabels(expiringPriority) : [];
    const beforeRows = prior.success
      ? prior.data.delegated.plan.sessions.flatMap((s) => s.exercises)
      : [];
    const setChanges = next.plan.sessions.flatMap((s) =>
      s.exercises.flatMap((e) => {
        const before = beforeRows.find((r) => r.variantId === e.variantId);
        return before && before.sets !== e.sets
          ? [`${e.name}: ${before.sets} → ${e.sets} sets on ${s.title}.`]
          : [];
      }),
    );
    const proposal = delegatedProposalSchema.parse({
      version: 2,
      id,
      programId: prior.success
        ? prior.data.id
        : (baselinePrior?.id ??
          sourceProposal?.programId ??
          stableTrainingUuid(input.subject, 'delegated-program', body.requestId)),
      ownerSubject: input.subject,
      baseRevision: context.headRevision,
      context: token(context),
      actor,
      authority:
        input.actor.kind === 'trainer'
          ? 'trainer_grant'
          : input.actor.kind === 'coach' && prior.data?.delegated.authority.coachDelegated
            ? 'coach_delegation'
            : 'user_review',
      intent,
      reason: body.reason,
      priorState: prior.success ? prior.data : baselinePrior,
      proposedState: next,
      plan: next.plan,
      proposedDiff: meaningfulDiff(prior.success ? prior.data.delegated : null, next),
      policyVersion: DELEGATED_POLICY,
      validation: {
        allowed: true,
        rules: [
          'adult_profile',
          'explicit_safety_consent',
          'catalog_eligibility',
          'time_budget',
          'bounded_canvas_policy',
          'planned_deload',
          'current_revision',
        ],
        pushback:
          intent.kind === 'prioritize'
            ? [
                'This emphasis lasts for this block. Other training stays in the plan; more priority work must fit your time budget.',
              ]
            : [],
      },
      inputEvidence: {
        fingerprint: evidenceFingerprint,
        observedAt: input.now.toISOString(),
        freshness: 'current',
        signals: {
          training: signalFreshness(
            snapshot.logs
              .filter((l) =>
                snapshot.sessions.some((s) => s.id === l.sessionId && s.status === 'completed'),
              )
              .map((l) => l.completedAt),
            input.now,
          ),
          feedback: signalFreshness(
            snapshot.feedback.map((f) => f.observedAt ?? f.createdAt),
            input.now,
          ),
        },
        evidenceIds: [
          ...new Set(next.plan.sessions.flatMap((s) => s.exercises.flatMap((e) => e.evidenceIds))),
        ],
      },
      assumptions: [
        'The reviewed canvas baseline is a conservative starting point; experience and goal do not imply a precise optimal dose.',
        'Session duration is an approximate budget of three minutes per set, not a measured duration.',
        'No nutrition or activity prescription is added. Those engines are not enabled.',
        'The final week is a planned deload. Only recorded completed training advances the block.',
      ],
      summary: [
        ...setChanges,
        prior.success
          ? `Schedule: ${prior.data.sessionsPerWeek} → ${next.inputs.sessionsPerWeek} days each week.`
          : `${next.inputs.sessionsPerWeek} training days each week for ${next.plan.weekCount} weeks.`,
        `Approximately ${Math.max(...next.plan.sessions.map((s) => s.exercises.reduce((n, e) => n + e.sets, 0) * 3))} minutes per session; the final week reduces work for a planned deload.`,
        ...(intent.kind === 'keep'
          ? [
              `Keep the exact ${next.plan.sessions.flatMap((s) => s.exercises).find((e) => e.variantId === intent.variantId)?.name ?? intent.variantId} variant and its own training history across blocks.`,
            ]
          : []),
        ...(intent.kind === 'exclude'
          ? ['This movement exclusion persists across future blocks.']
          : []),
        ...(intent.kind === 'prioritize'
          ? [`Prioritize ${priorityLabels(intent).join(', ')} for this block only.`]
          : []),
        ...(intent.kind === 'restore'
          ? [
              'Restore this allowed program without rewinding completed training or trainer permissions.',
            ]
          : []),
      ],
      reviewPoint: 'before_next_workout',
      rollbackRevision: context.headRevision,
      transition:
        intent.kind === 'next_block'
          ? {
              staying: [
                'Equipment, exclusions, known limitations, schedule and kept exercise variants',
                'Completed history remains attached to exact exercise IDs',
              ],
              changing: ['A new block starts with the reviewed baseline and planned deload'],
              why: 'All planned sessions have recorded completed work. Recovery and progression remain bounded by the engine.',
              expiring: expired,
              primaryAction: 'Start next block',
              secondaryAction: 'Review changes',
            }
          : (sourceProposal?.transition ?? null),
      createdAt: input.now.toISOString(),
    });
    return input.revisions.createProposal({
      subject: input.subject,
      requestId: body.requestId,
      requestHash,
      proposal,
    });
  } catch (error) {
    if (error instanceof PlanningQuestion)
      return {
        kind: 'question' as const,
        field: error.field,
        question: error.question,
        validation: { allowed: false, rule: error.field },
      };
    throw error;
  }
}

export async function decideDelegatedProposal(input: Dependencies & { body: unknown }) {
  const parsed = decideProposalInputSchema.safeParse(input.body);
  if (!parsed.success) return { kind: 'invalid_request' as const };
  const body = parsed.data;
  const context = await input.revisions.readContext(input.subject);
  if (!context) return { kind: 'owner_missing' as const };
  const raw = currentTrainingSetup(context);
  if (!canSteer(input.subject, input.actor, isProgramSetup(raw) ? raw : null))
    return { kind: 'unauthorized_actor' as const };
  const stored = await input.revisions.readProposal(input.subject, body.proposalId);
  if (!stored || stored.proposal.version !== 2) return { kind: 'proposal_not_found' as const };
  const p = stored.proposal;
  if (
    input.actor.kind === 'coach' &&
    (p.authority !== 'coach_delegation' ||
      !isProgramSetup(raw) ||
      !raw.delegated?.authority.coachDelegated)
  )
    return { kind: 'unauthorized_actor' as const };
  if (stored.status === 'proposed' && body.decision === 'apply') {
    if (!profileConfirmsAdult(context.dateOfBirth, input.now))
      return { kind: 'adult_profile_required' as const };
    if (
      trainingRequestHash(token(context)) !== trainingRequestHash(p.context) ||
      context.headRevision !== p.baseRevision ||
      context.evidenceFingerprint !== p.inputEvidence.fingerprint
    )
      return { kind: 'stale_context' as const };
    if (
      validateProgram(p.proposedState) ||
      trainingRequestHash(p.plan) !== trainingRequestHash(p.proposedState.plan)
    )
      return { kind: 'policy_changed' as const };
  }
  const revisionId = stableTrainingUuid(input.subject, 'training-revision', p.id);
  const restarting =
    !p.priorState?.delegated || p.proposedState.blockNumber !== p.priorState.delegated.blockNumber;
  const setup = delegatedSetupSchema.parse({
    id: p.programId,
    consentVersion: TRAINING_CONSENT_VERSION,
    adultConfirmed: true,
    safetyConfirmed: true,
    equipment: p.proposedState.inputs.equipment,
    sessionsPerWeek: p.proposedState.inputs.sessionsPerWeek,
    startedAt: restarting ? input.now.toISOString() : p.priorState!.startedAt,
    programRevisionId: revisionId,
    programPolicyVersion: DELEGATED_POLICY,
    delegated: p.proposedState,
  });
  return input.revisions.decide({
    subject: input.subject,
    proposalId: p.id,
    requestId: body.requestId,
    requestHash: trainingRequestHash({ body, actor: input.actor }),
    decision: body.decision,
    context: token(context),
    now: input.now.toISOString(),
    revisionId,
    setup,
    actor: input.actor,
    evidenceFingerprint: p.inputEvidence.fingerprint,
  });
}

export async function prepareNextBlock(input: Omit<Dependencies, 'actor'>) {
  const context = await input.revisions.readContext(input.subject);
  if (!context?.headRevision) return { kind: 'delegated_program_required' as const };
  return createDelegatedProposal({
    ...input,
    actor: { kind: 'user', subject: input.subject },
    body: {
      requestId: stableTrainingUuid(
        input.subject,
        'next-block',
        context.headRevision,
        context.evidenceFingerprint ?? '',
      ),
      expectedGeneration: context.generation,
      intent: { kind: 'next_block' },
      reason: 'Prepare the next block from completed training, feedback and durable constraints.',
    },
  });
}
