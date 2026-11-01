/** @jest-environment node */
import { readFileSync } from 'node:fs';
import type {
  TrainingRevisionsPort,
  TrainingRevisionContext,
} from '@/lib/ports/training-revisions';
import type { SteeringMovementRequestsPort } from '@/lib/ports/program-steering';
import { persistSteeringRevision } from './steering-revisions';
import {
  delegatedSetupSchema,
  type ProgramSteeringRecord,
  type SteeringHealthDecision,
} from './delegation-contract';
import {
  revisionReceiptSchema,
  storedProposalSchema,
  type StoredTrainingProposal,
} from './revision-contract';
import { recommendProgram } from './delegated-planning';
import * as planning from './delegated-planning';
import * as canvas from './mesocycle-canvas';
import * as engine from './engine';
import { decideDelegatedProposal } from './delegated-revisions';
import { MemoryTrainingRecords } from './memory-records.testing';

// SWC exports use non-configurable getters; expose configurable copies for spies.
jest.mock('./delegated-planning', () => ({ ...jest.requireActual('./delegated-planning') }));
jest.mock('./mesocycle-canvas', () => ({ ...jest.requireActual('./mesocycle-canvas') }));
jest.mock('./engine', () => ({ ...jest.requireActual('./engine') }));

const now = new Date('2026-10-25T12:00:00Z');
const env = {
  LYB_HYPERTROPHY_COACH_API_ENABLED: 'true',
  LYB_DELEGATED_PROGRAMMING_ENABLED: 'true',
};
const record: ProgramSteeringRecord = {
  revisionId: '11111111-1111-4111-8111-111111111111',
  priorityFocus: { muscles: ['shoulders'], upperChest: false },
  constraintId: 'reviewed-trunk-constraint',
  actor: { kind: 'user', subject: 'owner' },
  rationale: 'Focus on shoulders within my reviewed movement constraint.',
};
const rationaleFixture = JSON.parse(
  readFileSync(
    `${process.cwd()}/../../packages/shared-lib/fixtures/program-revision-rationale.json`,
    'utf8',
  ),
) as { userUtterance: string; revision: { rationale: string } };

/** In-memory LYB-37 fixture: only this port changes the canonical setup/ledger. */
function fixture() {
  let saved = delegatedSetupSchema.parse({
    id: '22222222-2222-4222-8222-222222222222',
    consentVersion: 'hypertrophy-coach-v1',
    adultConfirmed: true,
    safetyConfirmed: true,
    sessionsPerWeek: 2,
    equipment: 'full_gym',
    startedAt: '2026-10-01T12:00:00Z',
    programRevisionId: '33333333-3333-4333-8333-333333333333',
    programPolicyVersion: 'delegated-canvas-v1',
    delegated: {
      ...recommendProgram(
        {
          goal: 'Build muscle',
          goalDate: null,
          experience: 'new',
          sessionsPerWeek: 2,
          minutesPerSession: 60,
          equipment: 'full_gym',
          excludedVariantIds: [],
          limitations: [],
          preferredVariantIds: [],
        },
        4,
      ),
      steering: {
        ...record,
        revisionId: '33333333-3333-4333-8333-333333333333',
        priorityFocus: { muscles: ['back'], upperChest: false },
        constraintId: 'prior-constraint',
      },
    },
  });
  const original = JSON.parse(JSON.stringify(saved)) as typeof saved;
  const context: TrainingRevisionContext = {
    ownerId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    generation: 1,
    profileFingerprint: 'profile',
    legacyFingerprint: 'saved-program',
    dateOfBirth: '1990-01-01',
    legacySetups: [saved],
    headRevision: saved.programRevisionId,
    evidenceFingerprint: 'current-training-evidence',
  };
  const proposals = new Map<string, StoredTrainingProposal>();
  const history: Array<{ id: string; proposal: unknown; setup: typeof saved }> = [];
  const revisions: TrainingRevisionsPort = {
    readContext: jest.fn(async (subject) => (subject === 'owner' ? { ...context } : null)),
    readProposal: jest.fn(async (subject, id) =>
      subject === 'owner' ? (proposals.get(id) ?? null) : null,
    ),
    createProposal: jest.fn(async (i) => {
      const existing = proposals.get(i.proposal.id);
      if (existing)
        return existing.requestHash === i.requestHash
          ? { kind: 'stored' as const, stored: existing }
          : { kind: 'request_conflict' as const };
      if (i.proposal.context.generation !== context.generation)
        return { kind: 'stale_context' as const };
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
        i.context.generation !== context.generation ||
        stored.proposal.baseRevision !== context.headRevision
      )
        return { kind: 'stale_context' as const };
      const receipt = revisionReceiptSchema.parse({
        version: 2,
        proposalId: i.proposalId,
        requestId: i.requestId,
        decision: i.decision,
        status: 'applied',
        actor: i.actor,
        priorState: stored.proposal.priorState,
        revisionId: i.revisionId,
        setup: i.setup,
        decidedAt: i.now,
      });
      saved = delegatedSetupSchema.parse(i.setup);
      history[history.length] = { id: i.revisionId, proposal: stored.proposal, setup: saved };
      context.legacySetups = [saved];
      context.headRevision = i.revisionId;
      context.generation++;
      context.legacyFingerprint = i.revisionId;
      stored.status = 'applied';
      stored.receipt = receipt;
      return { kind: 'decided' as const, receipt };
    }),
    storeLegacySetup: jest.fn(async () => {
      throw new Error('not the revision boundary');
    }),
    revoke: jest.fn(async () => {
      throw new Error('not a revocation');
    }),
    exportForSubject: jest.fn(async () => ({
      proposals: [...proposals.values()],
      revisions: history,
    })),
  };
  const healthPolicy = {
    evaluate: jest.fn(async (): Promise<SteeringHealthDecision> => ({ kind: 'allow' })),
  };
  const movements: SteeringMovementRequestsPort = { request: jest.fn(async () => {}) };
  const deps = { subject: 'owner', record, revisions, healthPolicy, movements, now, env };
  return {
    ...deps,
    original,
    history,
    context,
    proposals,
    saved: () => saved,
    write: () => persistSteeringRevision(deps),
  };
}

afterEach(() => jest.restoreAllMocks());

it('stores the LYB-277 user utterance verbatim in the revision, proposal reason and summary', async () => {
  const h = fixture();
  const supplied = { ...record, rationale: rationaleFixture.userUtterance };
  expect((await persistSteeringRevision({ ...h, record: supplied })).kind).toBe('decided');
  expect(h.saved().delegated.steering?.rationale).toBe(rationaleFixture.revision.rationale);
  expect(h.history[0].proposal).toMatchObject({
    reason: rationaleFixture.revision.rationale,
    summary: [rationaleFixture.revision.rationale],
    intent: { record: { rationale: rationaleFixture.revision.rationale } },
  });
});

it.each(['', ' \n\t ', 'x'.repeat(501)])(
  'rejects an invalid rationale without storing it: %j',
  async (rationale) => {
    const h = fixture();
    expect(await persistSteeringRevision({ ...h, record: { ...record, rationale } })).toEqual({
      kind: 'invalid_request',
    });
    expect(h.revisions.createProposal).not.toHaveBeenCalled();
    expect(h.history).toHaveLength(0);
  },
);

it('changes saved priority focus and constraint id through LYB-37, recording exactly one attributed revision without computing a prescription', async () => {
  const h = fixture();
  const forbidden = [
    jest.spyOn(planning, 'recommendProgram'),
    jest.spyOn(planning, 'steerProgram'),
    jest.spyOn(canvas, 'buildOperation'),
    jest.spyOn(engine, 'buildMicrocycle'),
    jest.spyOn(engine, 'progressionForExercise'),
  ];
  for (const fn of forbidden)
    fn.mockImplementation(() => {
      throw new Error('writer computed a prescription');
    });
  expect((await h.write()).kind).toBe('decided');
  expect(h.saved().delegated.steering).toEqual(record);
  expect(h.saved().delegated.temporaryPriority).toEqual({
    ...record.priorityFocus,
    expiresAfterBlock: 1,
  });
  expect(h.saved().delegated.plan).toEqual(h.original.delegated.plan);
  expect(h.saved().delegated.inputs).toEqual(h.original.delegated.inputs);
  expect(h.saved().startedAt).toBe(h.original.startedAt);
  expect(h.history).toHaveLength(1);
  expect(h.history[0]).toMatchObject({
    id: record.revisionId,
    proposal: { actor: record.actor, reason: record.rationale },
    setup: { programRevisionId: record.revisionId },
  });
  expect(h.revisions.createProposal).toHaveBeenCalledTimes(1);
  expect(h.revisions.decide).toHaveBeenCalledWith(
    expect.objectContaining({
      revisionId: record.revisionId,
      actor: record.actor,
      setup: h.saved(),
    }),
  );
  expect(h.movements.request).not.toHaveBeenCalled();
  for (const fn of forbidden) expect(fn).not.toHaveBeenCalled();
});

it('replays a revision id without appending a second revision, including after a later revision', async () => {
  const h = fixture();
  const first = await h.write();
  expect(await h.write()).toEqual(first);
  const later = {
    ...record,
    revisionId: '44444444-4444-4444-8444-444444444444',
    priorityFocus: null,
    constraintId: null,
  };
  await persistSteeringRevision({ ...h, record: later });
  expect(await h.write()).toEqual(first);
  expect(h.history).toHaveLength(2);
  expect(h.saved().delegated.steering).toEqual(later);
  expect(h.saved().delegated.temporaryPriority).toBeNull();
  expect(h.revisions.createProposal).toHaveBeenCalledTimes(2);
  expect(h.revisions.decide).toHaveBeenCalledTimes(2);
});

it('rejects changed content for the same revision id', async () => {
  const h = fixture();
  await h.write();
  expect(
    await persistSteeringRevision({ ...h, record: { ...record, rationale: 'Changed reason' } }),
  ).toEqual({ kind: 'request_conflict' });
  expect(h.history).toHaveLength(1);
});

it.each([{ maxTrunkDemand: 'low' as const }, { excludedConcerns: ['low_back_symptoms'] }])(
  'requests only the health-policy-approved LYB-113 constraint %j after persistence',
  async (constraint) => {
    const h = fixture();
    h.healthPolicy.evaluate.mockResolvedValue({
      kind: 'movement_constraint',
      constraintId: record.constraintId!,
      constraint,
    });
    jest.mocked(h.movements.request).mockImplementation(async () => {
      expect(h.history).toHaveLength(1);
    });
    await h.write();
    expect(h.movements.request).toHaveBeenCalledWith({
      subject: 'owner',
      programId: h.saved().id,
      revisionId: record.revisionId,
      constraintId: record.constraintId,
      constraints: constraint,
    });
    expect(h.saved().delegated.plan).toEqual(h.original.delegated.plan);
    expect(h.saved().delegated.inputs).toEqual(h.original.delegated.inputs);
  },
);

it('blocks health review and a mismatched policy constraint without persisting or requesting movements', async () => {
  const h = fixture();
  h.healthPolicy.evaluate.mockResolvedValueOnce({
    kind: 'review_required',
    reason: 'Review the restriction.',
  });
  expect(await h.write()).toEqual({ kind: 'review_required', reason: 'Review the restriction.' });
  h.healthPolicy.evaluate.mockResolvedValueOnce({
    kind: 'movement_constraint',
    constraintId: 'different',
    constraint: { maxTrunkDemand: 'low' },
  });
  expect(await h.write()).toEqual({ kind: 'policy_changed' });
  expect(h.revisions.createProposal).not.toHaveBeenCalled();
  expect(h.revisions.decide).not.toHaveBeenCalled();
  expect(h.movements.request).not.toHaveBeenCalled();
});

it('propagates a failed transaction and retries the same proposal without claiming persistence', async () => {
  const h = fixture();
  jest.mocked(h.revisions.decide).mockRejectedValueOnce(new Error('transaction rolled back'));
  await expect(h.write()).rejects.toThrow('transaction rolled back');
  expect(h.saved()).toEqual(h.original);
  expect(h.history).toHaveLength(0);
  expect(h.movements.request).not.toHaveBeenCalled();
  expect((await h.write()).kind).toBe('decided');
  expect(h.history).toHaveLength(1);
});

it('does not resume a pending write when its health decision or canonical evidence changed', async () => {
  const h = fixture();
  jest.mocked(h.revisions.decide).mockResolvedValueOnce({ kind: 'delayed_active_workout' });
  expect(await h.write()).toEqual({ kind: 'delayed_active_workout' });
  h.healthPolicy.evaluate.mockResolvedValue({
    kind: 'movement_constraint',
    constraintId: record.constraintId!,
    constraint: { maxTrunkDemand: 'low' },
  });
  expect(await h.write()).toEqual({ kind: 'policy_changed' });
  h.context.evidenceFingerprint = 'changed-evidence';
  expect(await h.write()).toEqual({ kind: 'stale_context' });
  expect(h.revisions.decide).toHaveBeenCalledTimes(1);
  expect(h.history).toHaveLength(0);
});

it('retries a failed LYB-113 request with its committed identity without another revision', async () => {
  const h = fixture();
  h.healthPolicy.evaluate.mockResolvedValue({
    kind: 'movement_constraint',
    constraintId: record.constraintId!,
    constraint: { maxTrunkDemand: 'low' },
  });
  jest
    .mocked(h.movements.request)
    .mockRejectedValueOnce(new Error('movement boundary unavailable'));
  await expect(h.write()).rejects.toThrow('movement boundary unavailable');
  expect((await h.write()).kind).toBe('decided');
  expect(h.history).toHaveLength(1);
  expect(h.revisions.decide).toHaveBeenCalledTimes(1);
  expect(jest.mocked(h.movements.request).mock.calls[0]).toEqual(
    jest.mocked(h.movements.request).mock.calls[1],
  );
  await persistSteeringRevision({
    ...h,
    record: { ...record, revisionId: '55555555-5555-4555-8555-555555555555' },
  });
  const count = jest.mocked(h.movements.request).mock.calls.length;
  await h.write();
  expect(h.movements.request).toHaveBeenCalledTimes(count);
});

it('cannot bypass structured health-policy admission through the conversational apply service', async () => {
  const h = fixture();
  jest.mocked(h.revisions.decide).mockResolvedValueOnce({ kind: 'delayed_active_workout' });
  await h.write();
  const proposalId = [...h.proposals.keys()][0];
  expect(
    await decideDelegatedProposal({
      ...h,
      actor: record.actor,
      records: new MemoryTrainingRecords(),
      body: { proposalId, requestId: '66666666-6666-4666-8666-666666666666', decision: 'apply' },
    }),
  ).toEqual({ kind: 'unsupported_or_invalid_intent' });
  expect(h.revisions.decide).toHaveBeenCalledTimes(1);
  expect(h.history).toHaveLength(0);
});

it('preserves a regional upper-chest focus without assigning new work', async () => {
  const h = fixture();
  const regional = { ...record, priorityFocus: { muscles: ['chest'], upperChest: true } };
  expect((await persistSteeringRevision({ ...h, record: regional })).kind).toBe('decided');
  expect(h.saved().delegated.temporaryPriority).toEqual({
    ...regional.priorityFocus,
    expiresAfterBlock: 1,
  });
  expect(h.saved().delegated.plan).toEqual(h.original.delegated.plan);
});

it('keeps admission default-off and rejects unknown fields, unauthorized actors and non-adult profiles', async () => {
  const h = fixture();
  expect(await persistSteeringRevision({ ...h, env: {} })).toEqual({ kind: 'disabled' });
  expect(await persistSteeringRevision({ ...h, record: { ...record, loadKg: 99 } })).toEqual({
    kind: 'invalid_request',
  });
  expect(
    await persistSteeringRevision({
      ...h,
      record: { ...record, actor: { kind: 'user', subject: 'other' } },
    }),
  ).toEqual({ kind: 'unauthorized_actor' });
  expect(
    await persistSteeringRevision({
      ...h,
      record: { ...record, actor: { kind: 'coach', subject: 'lyb-coach' } },
    }),
  ).toEqual({ kind: 'unauthorized_actor' });
  h.context.dateOfBirth = '2010-01-01';
  expect(await h.write()).toEqual({ kind: 'adult_profile_required' });
  expect(h.revisions.createProposal).not.toHaveBeenCalled();
});

it('keeps concurrent identical retries inside the idempotent persistence boundary', async () => {
  const h = fixture();
  expect((await Promise.all([h.write(), h.write()])).map((r) => r.kind)).toEqual([
    'decided',
    'decided',
  ]);
  expect(h.history).toHaveLength(1);
});

it('has no checkout, entitlement, send, push, or prescription-builder call in the writer', () => {
  const source = readFileSync(`${process.cwd()}/src/lib/training/steering-revisions.ts`, 'utf8');
  expect(source).not.toMatch(
    /\b(?:checkout|entitlement\w*|send\w*|push|buildMicrocycle|buildSession|buildOperation|recommendProgram|steerProgram|progressionForExercise)\s*\(/i,
  );
  expect(source).not.toMatch(
    /\b(?:fetch|loadKg|targetLoadKg|plannedFractionalVolume|weeklySets)\b/,
  );
});
