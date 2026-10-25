import type {
  TrainingRevisionContext,
  TrainingRevisionsPort,
} from '@/lib/ports/training-revisions';
import { delegatedSetupSchema } from './delegation-contract';
import {
  revisionReceiptSchema,
  storedProposalSchema,
  type StoredTrainingProposal,
} from './revision-contract';
import {
  persistSteeringRevision,
  type ProgramSteeringRecord,
  type SteeringHealthDecision,
  type SteeringSubstitutionsPort,
} from './steering-revision';
import { recommendProgram, steerProgram, validateProgram } from './delegated-planning';
import { buildMicrocycle, buildSession, progressionForExercise } from './engine';

// A metadata writer must work even when every planner entry point is unavailable.
jest.mock('./delegated-planning', () => ({
  ...jest.requireActual('./delegated-planning'),
  recommendProgram: jest.fn(() => {
    throw new Error('writer_called_planner');
  }),
  steerProgram: jest.fn(() => {
    throw new Error('writer_called_planner');
  }),
  validateProgram: jest.fn(() => {
    throw new Error('writer_computed_volume');
  }),
}));
jest.mock('./engine', () => ({
  ...jest.requireActual('./engine'),
  buildMicrocycle: jest.fn(() => {
    throw new Error('writer_computed_volume');
  }),
  buildSession: jest.fn(() => {
    throw new Error('writer_computed_prescription');
  }),
  progressionForExercise: jest.fn(() => {
    throw new Error('writer_computed_load');
  }),
}));

const actor = { kind: 'user', subject: 'owner' } as const;
const record: ProgramSteeringRecord = {
  revisionId: '22222222-2222-4222-8222-222222222222',
  priorityFocus: { muscles: ['biceps'], upperChest: false },
  constraintId: 'reviewed-low-trunk-demand',
  actor,
  rationale: 'Prioritize biceps this block and retain the reviewed movement constraint.',
};
const now = new Date('2026-10-25T12:00:00Z');

function fixture() {
  const setup = delegatedSetupSchema.parse({
    id: '11111111-1111-4111-8111-111111111111',
    consentVersion: 'hypertrophy-coach-v1',
    adultConfirmed: true,
    safetyConfirmed: true,
    equipment: 'full_gym',
    sessionsPerWeek: 2,
    startedAt: '2026-10-20T12:00:00Z',
    programRevisionId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    programPolicyVersion: 'delegated-canvas-v1',
    delegated: {
      inputs: {
        goal: 'Build muscle',
        goalDate: null,
        experience: 'new',
        sessionsPerWeek: 2,
        minutesPerSession: 60,
        equipment: 'full_gym',
        excludedVariantIds: ['barbell_romanian_deadlift'],
        limitations: [],
        preferredVariantIds: [],
      },
      plan: {
        id: 'canvas-plan',
        revision: 1,
        weekCount: 4,
        equipment: 'full_gym',
        declaredEquipment: [],
        goal: 'Build muscle',
        policy: { priorityMuscles: [], upperChest: false, maintenanceMuscles: [] },
        sessions: ['monday', 'thursday'].map((day) => ({
          id: `session:${day}`,
          day,
          slot: 'single',
          title: day,
          exercises: [
            {
              instanceId: `curl:${day}`,
              variantId: 'dumbbell_curl',
              name: 'Dumbbell curl',
              primaryMuscle: 'biceps',
              sets: 2,
              repRange: { min: 8, max: 12 },
              targetReps: 10,
              targetRir: 3,
              priority: 'standard',
              emphasis: null,
              evidenceIds: ['fixture-evidence'],
            },
          ],
        })),
      },
      blockNumber: 1,
      deloadWeek: 4,
      temporaryPriority: { muscles: ['chest'], upperChest: false, expiresAfterBlock: 1 },
      constraintId: 'prior-constraint',
      completedWeeks: { '1': 2 },
      authority: { trainerSubject: null, coachDelegated: false },
    },
  });
  let savedProgram = setup;
  let history: Array<{
    id: string;
    proposal: StoredTrainingProposal['proposal'];
    setup: typeof setup;
  }> = [];
  const proposals = new Map<string, StoredTrainingProposal>();
  const context: TrainingRevisionContext = {
    ownerId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    generation: 0,
    profileFingerprint: 'profile',
    legacyFingerprint: 'saved-program',
    dateOfBirth: '1990-01-01',
    legacySetups: [setup],
    headRevision: setup.programRevisionId,
    evidenceFingerprint: 'fixture-training-evidence',
  };
  const revisions: TrainingRevisionsPort = {
    readContext: jest.fn(async () => ({ ...context })),
    readProposal: jest.fn(async (_subject, id) => proposals.get(id) ?? null),
    createProposal: jest.fn(async (i) => {
      const previous = proposals.get(i.proposal.id);
      if (previous)
        return previous.requestHash === i.requestHash
          ? { kind: 'stored' as const, stored: previous }
          : { kind: 'request_conflict' as const };
      const stored = storedProposalSchema.parse({
        proposal: i.proposal,
        requestHash: i.requestHash,
        status: 'proposed',
        receipt: null,
      });
      proposals.set(i.proposal.id, stored);
      return { kind: 'stored' as const, stored };
    }),
    decide: jest.fn(async (i) => {
      const stored = proposals.get(i.proposalId)!;
      if (stored.receipt) return { kind: 'decided' as const, receipt: stored.receipt };
      if (
        stored.proposal.baseRevision !== context.headRevision ||
        stored.proposal.context.generation !== context.generation
      )
        return { kind: 'stale_context' as const };
      const next = delegatedSetupSchema.parse(i.setup);
      const receipt = revisionReceiptSchema.parse({
        version: 2,
        proposalId: i.proposalId,
        requestId: i.requestId,
        decision: 'apply',
        status: 'applied',
        actor: i.actor,
        priorState: stored.proposal.priorState,
        revisionId: i.revisionId,
        setup: next,
        decidedAt: i.now,
      });
      savedProgram = next;
      history = [...history, { id: i.revisionId, proposal: stored.proposal, setup: next }];
      context.headRevision = i.revisionId;
      context.legacySetups = [next];
      context.generation += 1;
      stored.receipt = receipt;
      stored.status = 'applied';
      return { kind: 'decided' as const, receipt };
    }),
    storeLegacySetup: jest.fn(),
    revoke: jest.fn(),
    exportForSubject: jest.fn(),
  };
  const substitutions: SteeringSubstitutionsPort = {
    request: jest.fn(async () => ({ kind: 'requested' })),
  };
  const deps = {
    enabled: true,
    revisions,
    substitutions,
    subject: 'owner',
    actor,
    record,
    healthDecision: { kind: 'allow' } as SteeringHealthDecision,
    now,
  };
  return {
    deps,
    setup,
    context,
    revisions,
    substitutions,
    history: () => history,
    saved: () => savedProgram,
  };
}

describe('saved-program steering revision (LYB-278)', () => {
  it('delegates one focus/constraint revision, actor and rationale to the LYB-37 boundary', async () => {
    const h = fixture();
    const before = JSON.stringify(h.setup);
    const result = await persistSteeringRevision(h.deps);
    expect(result.kind).toBe('decided');
    expect(h.saved().delegated.temporaryPriority).toEqual({
      ...record.priorityFocus,
      expiresAfterBlock: 1,
    });
    expect(h.saved().delegated.constraintId).toBe(record.constraintId);
    expect(h.saved().programRevisionId).toBe(record.revisionId);
    expect(h.history()).toHaveLength(1);
    expect(h.history()[0]).toMatchObject({
      id: record.revisionId,
      proposal: { actor, reason: record.rationale },
    });
    expect(h.revisions.createProposal).toHaveBeenCalledTimes(1);
    expect(h.revisions.decide).toHaveBeenCalledWith(
      expect.objectContaining({
        subject: 'owner',
        actor,
        revisionId: record.revisionId,
        evidenceFingerprint: 'fixture-training-evidence',
      }),
    );
    expect(JSON.stringify(h.setup)).toBe(before);
    expect(h.saved().delegated.plan).toEqual(h.setup.delegated.plan);
    expect(h.saved().delegated.inputs).toEqual(h.setup.delegated.inputs);
    expect(h.saved().delegated.completedWeeks).toEqual({ '1': 2 });
    expect(recommendProgram).not.toHaveBeenCalled();
    expect(steerProgram).not.toHaveBeenCalled();
    expect(validateProgram).not.toHaveBeenCalled();
    expect(buildMicrocycle).not.toHaveBeenCalled();
    expect(buildSession).not.toHaveBeenCalled();
    expect(progressionForExercise).not.toHaveBeenCalled();
    expect(h.substitutions.request).not.toHaveBeenCalled();
  });

  it('replays the same revision ID without appending a second revision', async () => {
    const h = fixture();
    const first = await persistSteeringRevision(h.deps);
    expect(await persistSteeringRevision(h.deps)).toEqual(first);
    expect(h.history()).toHaveLength(1);
    expect(h.revisions.createProposal).toHaveBeenCalledTimes(1);
    expect(
      await persistSteeringRevision({ ...h.deps, record: { ...record, rationale: 'Changed' } }),
    ).toEqual({ kind: 'request_conflict' });
    expect(h.history()).toHaveLength(1);
  });

  it.each([{ maxTrunkDemand: 'low' as const }, { excludedConcerns: ['shoulder_irritation'] }])(
    'requests only policy-directed constraints through LYB-113: %j',
    async (constraints) => {
      const h = fixture();
      const deps = {
        ...h.deps,
        healthDecision: { kind: 'movement_constraint' as const, constraints },
      };
      expect((await persistSteeringRevision(deps)).kind).toBe('decided');
      expect(h.substitutions.request).toHaveBeenCalledWith({
        subject: 'owner',
        programId: h.setup.id,
        revisionId: record.revisionId,
        constraintId: record.constraintId,
        constraints,
      });
      await persistSteeringRevision(deps);
      expect(h.substitutions.request).toHaveBeenCalledTimes(1);
      expect(h.saved().delegated.plan).toEqual(h.setup.delegated.plan);
    },
  );

  it('fails closed on unresolved health policy or an unavailable/rejected substitution request', async () => {
    const h = fixture();
    expect(
      await persistSteeringRevision({ ...h.deps, healthDecision: { kind: 'review_required' } }),
    ).toEqual({ kind: 'health_review_required' });
    const constrained = {
      ...h.deps,
      healthDecision: {
        kind: 'movement_constraint' as const,
        constraints: { maxTrunkDemand: 'low' as const },
      },
    };
    expect(await persistSteeringRevision({ ...constrained, substitutions: undefined })).toEqual({
      kind: 'health_review_required',
    });
    expect(
      await persistSteeringRevision({
        ...constrained,
        healthDecision: { kind: 'movement_constraint', constraints: {} },
      }),
    ).toEqual({ kind: 'health_review_required' });
    expect(
      await persistSteeringRevision({ ...constrained, record: { ...record, constraintId: null } }),
    ).toEqual({ kind: 'health_review_required' });
    jest.mocked(h.substitutions.request).mockResolvedValue({ kind: 'review_required' });
    expect(await persistSteeringRevision(constrained)).toEqual({ kind: 'health_review_required' });
    expect(h.revisions.createProposal).not.toHaveBeenCalled();
    expect(h.history()).toHaveLength(0);
  });

  it('can clear a reviewed constraint without requesting a movement change', async () => {
    const h = fixture();
    expect(
      (await persistSteeringRevision({ ...h.deps, record: { ...record, constraintId: null } }))
        .kind,
    ).toBe('decided');
    expect(h.saved().delegated.constraintId).toBeNull();
    expect(h.substitutions.request).not.toHaveBeenCalled();
  });

  it('does not apply when proposal persistence refuses the captured context', async () => {
    const h = fixture();
    jest.mocked(h.revisions.createProposal).mockResolvedValueOnce({ kind: 'stale_context' });
    expect(await persistSteeringRevision(h.deps)).toEqual({ kind: 'stale_context' });
    expect(h.revisions.decide).not.toHaveBeenCalled();
    expect(h.history()).toHaveLength(0);
  });

  it('requires the current saved program, adult profile and complete persistence context', async () => {
    const h = fixture();
    h.context.dateOfBirth = '2010-01-01';
    expect(await persistSteeringRevision(h.deps)).toEqual({ kind: 'adult_profile_required' });
    h.context.evidenceFingerprint = undefined;
    expect(await persistSteeringRevision(h.deps)).toEqual({ kind: 'stale_context' });
    h.context.legacySetups = [];
    expect(await persistSteeringRevision(h.deps)).toEqual({ kind: 'delegated_program_required' });
    jest.mocked(h.revisions.readContext).mockResolvedValueOnce(null);
    expect(await persistSteeringRevision(h.deps)).toEqual({ kind: 'owner_missing' });
    expect(h.revisions.createProposal).not.toHaveBeenCalled();
  });

  it('does not claim a revision when persistence refuses or fails', async () => {
    const h = fixture();
    jest.mocked(h.revisions.decide).mockResolvedValueOnce({ kind: 'delayed_active_workout' });
    expect(await persistSteeringRevision(h.deps)).toEqual({ kind: 'delayed_active_workout' });
    expect(h.history()).toHaveLength(0);
    expect(h.saved()).toEqual(h.setup);
    jest.mocked(h.revisions.decide).mockRejectedValueOnce(new Error('storage_unavailable'));
    await expect(persistSteeringRevision(h.deps)).rejects.toThrow('storage_unavailable');
    expect(h.history()).toHaveLength(0);
    expect((await persistSteeringRevision(h.deps)).kind).toBe('decided');
    expect(h.history()).toHaveLength(1);
  });

  it('retains conflict checks on a pending revision instead of overwriting newer state', async () => {
    const h = fixture();
    jest.mocked(h.revisions.decide).mockResolvedValueOnce({ kind: 'delayed_active_workout' });
    await persistSteeringRevision(h.deps);
    h.context.generation += 1;
    expect(await persistSteeringRevision(h.deps)).toEqual({ kind: 'stale_context' });
    expect(h.history()).toHaveLength(0);
  });

  it('requires rollout, authenticated authority and a strictly structured record', async () => {
    const h = fixture();
    expect(await persistSteeringRevision({ ...h.deps, enabled: false })).toEqual({
      kind: 'disabled',
    });
    expect(h.revisions.readContext).not.toHaveBeenCalled();
    expect(
      await persistSteeringRevision({ ...h.deps, record: { ...record, targetLoadKg: 50 } }),
    ).toEqual({ kind: 'invalid_steering_record' });
    expect(
      await persistSteeringRevision({
        ...h.deps,
        record: { ...record, actor: { kind: 'trainer', subject: 'other' } },
      }),
    ).toEqual({ kind: 'unauthorized_actor' });
    expect(
      await persistSteeringRevision({
        ...h.deps,
        actor: { kind: 'coach', subject: 'lyb-coach' },
        record: { ...record, actor: { kind: 'coach', subject: 'lyb-coach' } },
      }),
    ).toEqual({ kind: 'unauthorized_actor' });
    expect(h.history()).toHaveLength(0);
  });
});
