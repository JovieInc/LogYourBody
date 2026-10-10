import {
  createInitialTrainingProposal,
  decideInitialTrainingProposal,
  trainingRequestHash,
} from './revisions';
import { decisionBody, proposalBody, revisionHarness } from './revisions.testing';
import { getOrCreateNextWorkout, storeProgramSetup } from './service';
import { TRAINING_CONSENT_VERSION } from './types';
import { storedProposalSchema } from './revision-contract';

const now = new Date('2026-10-10T12:00:00Z');
async function proposed(h = revisionHarness()) {
  const result = await createInitialTrainingProposal({
    revisions: h.port,
    subject: 'owner',
    body: proposalBody,
    now,
  });
  if (result.kind !== 'stored') throw new Error(result.kind);
  return { ...h, stored: result.stored, id: result.stored.proposal.id };
}
describe('reviewed initial training enrollment', () => {
  it('creates only a proposal and returns exact persisted readback without enrolling', async () => {
    const h = await proposed();
    expect(await h.port.readProposal('owner', h.id)).toEqual(h.stored);
    expect(h.stored.proposal).toMatchObject({
      baseRevision: null,
      actor: { kind: 'self', subject: 'owner' },
      authority: 'self_review_required',
      reviewPoint: 'before_first_workout',
    });
    expect(h.stored.proposal.plan.sessions).toHaveLength(2);
    expect((await h.records.pull('owner', 'training_feedback')).records).toHaveLength(0);
    expect(h.context.headRevision).toBeNull();
  });
  it.each([
    { ...proposalBody, intent: { ...proposalBody.intent, kind: 'edit_program' } },
    { ...proposalBody, intent: { ...proposalBody.intent, musclePriority: 'arms' } },
    { ...proposalBody, actor: { kind: 'trainer', subject: 'other' } },
    { ...proposalBody, intent: { ...proposalBody.intent, adultConfirmed: false } },
    { ...proposalBody, intent: { ...proposalBody.intent, sessionsPerWeek: 4 } },
  ])('fails closed for unsupported authority/intent/constraints without a write', async (body) => {
    const h = revisionHarness();
    expect(
      await createInitialTrainingProposal({ revisions: h.port, subject: 'owner', body, now }),
    ).toEqual({ kind: 'unsupported_or_invalid_intent' });
    expect(h.port.createProposal).not.toHaveBeenCalled();
  });
  it('returns original create retry and conflicts on changed reason with the same identity', async () => {
    const h = await proposed();
    expect(
      await createInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: proposalBody,
        now: new Date('2026-11-11'),
      }),
    ).toEqual({ kind: 'stored', stored: h.stored });
    expect(
      await createInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: { ...proposalBody, reason: 'changed' },
        now,
      }),
    ).toEqual({ kind: 'request_conflict' });
    expect(h.port.createProposal).toHaveBeenCalledTimes(1);
  });
  it('requires the canonical adult profile and current consent generation', async () => {
    const h = revisionHarness();
    h.context.dateOfBirth = '2020-01-01';
    expect(
      await createInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: proposalBody,
        now,
      }),
    ).toEqual({ kind: 'adult_profile_required' });
    h.context.dateOfBirth = '1990-01-01';
    h.context.generation = 1;
    expect(
      await createInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: proposalBody,
        now,
      }),
    ).toEqual({ kind: 'stale_context' });
    expect(h.port.createProposal).not.toHaveBeenCalled();
  });
  it('preserves existing active versus old-consent legacy classification', async () => {
    const setup = {
      id: 'legacy',
      consentVersion: TRAINING_CONSENT_VERSION,
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment: 'dumbbells',
      startedAt: '2020-01-01',
    };
    const h = revisionHarness();
    h.context.legacySetups = [setup];
    expect(
      await createInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: proposalBody,
        now,
      }),
    ).toEqual({ kind: 'program_already_enrolled' });
    h.context.legacySetups = [{ ...setup, consentVersion: 'outdated' }];
    expect(
      (
        await createInitialTrainingProposal({
          revisions: h.port,
          subject: 'owner',
          body: proposalBody,
          now,
        })
      ).kind,
    ).toBe('stored');
  });
  it('apply days later preserves the reviewed numeric baseline and binds new workout records to the revision', async () => {
    const h = await proposed();
    const later = new Date('2026-11-10T12:00:00Z');
    const result = await decideInitialTrainingProposal({
      revisions: h.port,
      subject: 'owner',
      body: decisionBody(h.id),
      now: later,
    });
    if (result.kind !== 'decided') throw new Error(result.kind);
    expect(result.receipt.status).toBe('applied');
    expect(result.receipt.setup?.startedAt).toBe(later.toISOString());
    const next = await getOrCreateNextWorkout({ records: h.records, subject: 'owner', now: later });
    if (next.kind !== 'workout') throw new Error(next.kind);
    expect(next.session.exercises).toEqual(h.stored.proposal.plan.sessions[0].exercises);
    const rows = (await h.records.pull('owner', 'training_sessions')).records;
    expect(rows[0]?.programRevisionId).toBe(result.receipt.revisionId);
    expect(await h.port.readProposal('owner', h.id)).toMatchObject({
      status: 'applied',
      receipt: result.receipt,
    });
    const retry = await decideInitialTrainingProposal({
      revisions: h.port,
      subject: 'owner',
      body: decisionBody(h.id),
      now: new Date('2026-12-10'),
    });
    expect(retry).toEqual(result);
  });
  it('reject produces no applied copy or setup and cannot later apply', async () => {
    const h = await proposed();
    const rejected = await decideInitialTrainingProposal({
      revisions: h.port,
      subject: 'owner',
      body: decisionBody(h.id, 'reject'),
      now,
    });
    expect(rejected).toMatchObject({
      kind: 'decided',
      receipt: { status: 'rejected', decision: 'reject', setup: null, revisionId: null },
    });
    expect((await h.records.pull('owner', 'training_feedback')).records).toHaveLength(0);
    expect(
      await decideInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: decisionBody(h.id),
        now,
      }),
    ).toEqual({ kind: 'already_decided' });
  });
  it('does not admit stale canonical input or silently changed policy output', async () => {
    const h = await proposed();
    h.context.profileFingerprint = 'edited-profile';
    expect(
      await decideInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: decisionBody(h.id),
        now,
      }),
    ).toEqual({ kind: 'stale_context' });
    h.context.profileFingerprint = 'profile-v1';
    h.stored.proposal.plan.sessions[0].exercises[0].targetReps += 1;
    expect(
      await decideInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: decisionBody(h.id),
        now,
      }),
    ).toEqual({ kind: 'policy_changed' });
    expect(h.port.decide).not.toHaveBeenCalled();
  });
  it('propagates durable commit failure instead of claiming acceptance', async () => {
    const h = await proposed();
    jest.mocked(h.port.decide).mockRejectedValueOnce(new Error('transaction rolled back'));
    await expect(
      decideInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: decisionBody(h.id),
        now,
      }),
    ).rejects.toThrow('transaction rolled back');
    expect(h.stored.status).toBe('proposed');
    expect(h.context.headRevision).toBeNull();
  });
  it('routes existing enrollment through required production atomic admission without fallback on failure', async () => {
    const h = await proposed();
    const setup = {
      id: h.id,
      consentVersion: TRAINING_CONSENT_VERSION,
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2 as const,
      equipment: 'dumbbells' as const,
      startedAt: now.toISOString(),
    };
    jest.mocked(h.port.storeLegacySetup).mockRejectedValueOnce(new Error('migration unavailable'));
    await expect(
      storeProgramSetup({
        records: h.records,
        revisions: h.port,
        expectedContext: h.context,
        subject: 'owner',
        setup,
        now,
        createId: () => h.id,
      }),
    ).rejects.toThrow('migration unavailable');
    expect((await h.records.pull('owner', 'training_feedback')).records).toHaveLength(0);
  });
  it('hashes object key order consistently without equating changed bodies', () => {
    expect(trainingRequestHash({ b: 2, a: 1 })).toBe(trainingRequestHash({ a: 1, b: 2 }));
    expect(trainingRequestHash({ a: 1, b: 2 })).not.toBe(trainingRequestHash({ a: 1, b: 3 }));
  });
});

describe('historical training proposal incarnation', () => {
  it('keeps an old proposal exportable while refusing a new apply', async () => {
    const h = await proposed();
    delete h.stored.proposal.context.ownerId;
    expect(storedProposalSchema.parse(h.stored)).toEqual(h.stored);
    expect(await h.port.exportForSubject('owner')).toMatchObject({ proposals: [h.stored] });
    expect(
      await decideInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: decisionBody(h.id),
        now,
      }),
    ).toEqual({ kind: 'stale_context' });
    expect(h.port.decide).not.toHaveBeenCalled();
  });
  it('does not create a new proposal from a context missing owner incarnation', async () => {
    const h = revisionHarness();
    delete h.context.ownerId;
    await expect(
      createInitialTrainingProposal({
        revisions: h.port,
        subject: 'owner',
        body: proposalBody,
        now,
      }),
    ).rejects.toThrow('training_owner_incarnation_required');
    expect(h.port.createProposal).not.toHaveBeenCalled();
  });
});

it('reject cannot adopt a new owner context after a held old proposal read', async () => {
  const h = await proposed();
  let enter!: () => void;
  let release!: () => void;
  const entered = new Promise<void>((r) => {
    enter = r;
  });
  const gate = new Promise<void>((r) => {
    release = r;
  });
  jest.mocked(h.port.readProposal).mockImplementationOnce(async () => {
    enter();
    await gate;
    return h.stored;
  });
  const decide = h.port.decide;
  const originalDecide = jest.mocked(decide).getMockImplementation()!;
  jest.mocked(decide).mockImplementation(async (input) => {
    if (input.context.ownerId !== h.context.ownerId) return { kind: 'stale_context' };
    return originalDecide(input);
  });
  const pending = decideInitialTrainingProposal({
    revisions: h.port,
    subject: 'owner',
    body: decisionBody(h.id, 'reject'),
    now,
  });
  await entered;
  h.context.ownerId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  const replacement = storedProposalSchema.parse(JSON.parse(JSON.stringify(h.stored)));
  replacement.proposal.context.ownerId = h.context.ownerId;
  h.proposals.set(h.id, replacement);
  release();
  expect(await pending).toEqual({ kind: 'stale_context' });
  expect(h.proposals.get(h.id)?.status).toBe('proposed');
});

it('proposal creation retains its pre-read account context when a missing proposal read is held', async () => {
  const h = revisionHarness();
  let enter!: () => void;
  let release!: () => void;
  const entered = new Promise<void>((r) => {
    enter = r;
  });
  const gate = new Promise<void>((r) => {
    release = r;
  });
  jest.mocked(h.port.readProposal).mockImplementationOnce(async () => {
    enter();
    await gate;
    return null;
  });
  const create = jest.mocked(h.port.createProposal).getMockImplementation()!;
  jest.mocked(h.port.createProposal).mockImplementation(async (input) => {
    if (input.proposal.context.ownerId !== h.context.ownerId) return { kind: 'stale_context' };
    return create(input);
  });
  const pending = createInitialTrainingProposal({
    revisions: h.port,
    subject: 'owner',
    body: proposalBody,
    now,
  });
  await entered;
  h.context.ownerId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  release();
  expect(await pending).toEqual({ kind: 'stale_context' });
  expect(h.proposals.size).toBe(0);
});
