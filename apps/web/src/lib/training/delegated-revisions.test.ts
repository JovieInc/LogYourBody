import { randomUUID } from 'node:crypto';
import {
  createDelegatedProposal,
  decideDelegatedProposal,
  prepareNextBlock,
} from './delegated-revisions';
import { recommendProgram, validateProgram } from './delegated-planning';
import {
  delegatedSetupSchema,
  type PlanningInputs,
  type RevisionActor,
} from './delegation-contract';
import { MemoryTrainingRecords } from './memory-records.testing';
import { trainingRequestHash } from './revisions';
import { revisionReceiptSchema, type StoredTrainingProposal } from './revision-contract';
import type {
  TrainingRevisionContext,
  TrainingRevisionsPort,
} from '@/lib/ports/training-revisions';
import { getOrCreateNextWorkout, loadTrainingRecords, storeProgramSetup } from './service';
import { applyWorkoutAction, logTrainingSet } from './commands';
import { buildMicrocycle, createProgramBlock } from './engine';

const now = new Date('2026-10-25T12:00:00Z');
const inputs: PlanningInputs = {
  goal: 'Build muscle',
  goalDate: null,
  experience: 'new',
  sessionsPerWeek: 2,
  minutesPerSession: 60,
  equipment: 'full_gym',
  excludedVariantIds: ['barbell_romanian_deadlift'],
  limitations: [],
  preferredVariantIds: [],
};
const user: RevisionActor = { kind: 'user', subject: 'owner' };

function harness() {
  const records = new MemoryTrainingRecords();
  const proposals = new Map<string, StoredTrainingProposal>();
  const revisionHistory: Array<{ id: string; setup: unknown }> = [];
  const context: TrainingRevisionContext = {
    ownerId: randomUUID(),
    generation: 0,
    headRevision: null,
    profileFingerprint: 'profile',
    legacyFingerprint: 'legacy',
    dateOfBirth: '1990-01-01',
    legacySetups: [],
    canonicalTrainingInputs: inputs,
  };
  async function fingerprint() {
    return trainingRequestHash(
      await Promise.all(
        ['training_sessions', 'logged_sets', 'training_feedback'].map((c) =>
          records.pull('owner', c as 'training_sessions'),
        ),
      ),
    );
  }
  // Serialize the fake's writes too. Production races are exercised against SQL separately.
  let chain = Promise.resolve();
  function exclusive<T>(fn: () => Promise<T>): Promise<T> {
    const run = chain.then(fn);
    chain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  }
  const port: TrainingRevisionsPort = {
    async readContext(subject) {
      return subject === 'owner' ? { ...context, evidenceFingerprint: await fingerprint() } : null;
    },
    async readProposal(subject, id) {
      return subject === 'owner' ? (proposals.get(id) ?? null) : null;
    },
    async createProposal(i) {
      return exclusive(async () => {
        if (i.proposal.context.generation !== context.generation) return { kind: 'stale_context' };
        const stored: StoredTrainingProposal = {
          proposal: i.proposal,
          requestHash: i.requestHash,
          status: 'proposed',
          receipt: null,
        };
        proposals.set(i.proposal.id, stored);
        return { kind: 'stored', stored };
      });
    },
    async decide(i) {
      return exclusive(async () => {
        const stored = proposals.get(i.proposalId)!;
        if (stored.receipt)
          return stored.receipt.requestId === i.requestId && stored.receipt.decision === i.decision
            ? { kind: 'decided', receipt: stored.receipt }
            : { kind: 'already_decided' };
        if (
          i.context.generation !== context.generation ||
          stored.proposal.baseRevision !== context.headRevision
        )
          return { kind: 'stale_context' };
        if (i.decision === 'apply' && i.evidenceFingerprint !== (await fingerprint()))
          return { kind: 'stale_context' };
        const snapshot = await loadTrainingRecords(records, 'owner');
        if (
          i.decision === 'apply' &&
          snapshot.sessions.some((s) => s.status === 'in_progress' || s.status === 'paused')
        )
          return { kind: 'delayed_active_workout' };
        const p = stored.proposal;
        const receipt = revisionReceiptSchema.parse({
          version: 2,
          proposalId: i.proposalId,
          requestId: i.requestId,
          decision: i.decision,
          status: i.decision === 'apply' ? 'applied' : 'rejected',
          actor: i.actor,
          priorState: p.priorState,
          revisionId: i.decision === 'apply' ? i.revisionId : null,
          setup: i.decision === 'apply' ? i.setup : null,
          decidedAt: i.now,
        });
        if (i.decision === 'apply') {
          await records.push('owner', 'training_feedback', [
            { ...i.setup, record_type: 'program_setup' },
          ]);
          context.headRevision = i.revisionId;
          context.legacySetups = [i.setup];
          context.legacyFingerprint = trainingRequestHash(i.setup);
          revisionHistory.push({ id: i.revisionId, setup: i.setup });
        }
        context.generation++;
        stored.status = receipt.status;
        stored.receipt = receipt;
        return { kind: 'decided', receipt };
      });
    },
    async storeLegacySetup() {
      throw new Error('not used');
    },
    async revoke() {
      throw new Error('not used');
    },
    async exportForSubject(subject) {
      return subject === 'owner'
        ? { proposals: [...proposals.values()], revisions: revisionHistory }
        : { proposals: [], revisions: [] };
    },
  };
  const deps = { records, revisions: port, subject: 'owner', actor: user, now };
  async function propose(intent: unknown, actor = user, baseProposalId?: string) {
    return createDelegatedProposal({
      ...deps,
      actor,
      body: {
        requestId: randomUUID(),
        expectedGeneration: context.generation,
        reason: 'User steering',
        intent,
        baseProposalId,
      },
    });
  }
  async function apply(id: string, actor = user, decision = 'apply') {
    return decideDelegatedProposal({
      ...deps,
      actor,
      body: { requestId: randomUUID(), proposalId: id, decision },
    });
  }
  async function enroll() {
    const result = await propose({
      kind: 'recommend',
      inputs: {},
      adultConfirmed: true,
      safetyConfirmed: true,
    });
    if (result.kind !== 'stored') throw new Error(result.kind);
    const accepted = await apply(result.stored.proposal.id);
    if (accepted.kind !== 'decided') throw new Error(accepted.kind);
    return accepted.receipt.setup!;
  }
  async function completeBlock() {
    const setup = delegatedSetupSchema.parse(context.legacySetups[0]);
    for (let week = 1; week <= setup.delegated.plan.weekCount; week++) {
      const day = new Date(now.getTime() + (week - 1) * 7 * 86400000);
      for (let slot = 0; slot < setup.sessionsPerWeek; slot++) {
        const next = await getOrCreateNextWorkout({ records, subject: 'owner', now: day });
        if (next.kind !== 'workout') throw new Error(next.kind);
        for (const exercise of next.session.exercises)
          for (let setNumber = 1; setNumber <= exercise.sets; setNumber++) {
            const saved = await logTrainingSet({
              records,
              subject: 'owner',
              now: day,
              set: {
                sessionId: next.session.id,
                exerciseId: exercise.id,
                setNumber,
                reps: 9,
                loadKg: 12,
                rir: 3,
              },
            });
            if (saved.kind !== 'logged') throw new Error(saved.kind);
          }
      }
    }
  }
  return {
    ...deps,
    context,
    port,
    proposals,
    revisionHistory,
    propose,
    apply,
    enroll,
    completeBlock,
  };
}

describe('LYB-130 delegated programming acceptance', () => {
  it.each([2, 3, 4, 5, 6] as const)(
    'retains reviewed delegated prescriptions across every slot of a %i-day schedule',
    async (sessionsPerWeek) => {
      const h = harness();
      h.context.canonicalTrainingInputs = { ...inputs, sessionsPerWeek };
      const setup = delegatedSetupSchema.parse(await h.enroll());
      for (const week of [1, setup.delegated.deloadWeek]) {
        const today = new Date(now.getTime() + (week - 1) * 7 * 86400000).toISOString();
        const microcycle = buildMicrocycle({
          setup,
          block: createProgramBlock(setup, today),
          sessionIds: Array.from({ length: sessionsPerWeek }, () => randomUUID()),
          logs: [],
          feedback: [],
        });
        expect(microcycle.sessions).toHaveLength(sessionsPerWeek);
        microcycle.sessions.forEach((session, slot) => {
          const planned = setup.delegated.plan.sessions[slot];
          expect(session.title).toBe(planned.title);
          expect(
            session.exercises.map((e) => ({ id: e.id, sets: e.sets, reps: e.targetReps })),
          ).toEqual(
            planned.exercises.map((e) => ({
              id: e.variantId,
              sets: week === setup.delegated.deloadWeek ? 1 : e.sets,
              reps: e.targetReps,
            })),
          );
          for (const exercise of session.exercises) {
            expect(
              exercise.substitutions.every(
                (candidate) =>
                  !inputs.excludedVariantIds.includes(candidate.id) &&
                  !planned.exercises.some((e) => e.variantId === candidate.id),
              ),
            ).toBe(true);
          }
        });
      }
    },
  );

  it('1/7/8: sparse canonical inputs yield one engine draft, apply directly, execute in workout mode and return a controller receipt', async () => {
    const h = harness();
    const setup = await h.enroll();
    expect(setup.delegated && validateProgram(setup.delegated)).toBeNull();
    expect(h.proposals.size).toBe(1);
    const workout = await getOrCreateNextWorkout({ records: h.records, subject: 'owner', now });
    if (workout.kind !== 'workout') throw new Error(workout.kind);
    expect(workout.session.exercises.map((e) => e.id)).toEqual(
      setup.delegated!.plan.sessions[0].exercises.map((e) => e.variantId),
    );
    expect(workout.decision.actor).toBe('controller');
    expect(workout.session.exercises.every((e) => e.evidenceIds.length > 0)).toBe(true);
    const constrained = await getOrCreateNextWorkout({
      records: h.records,
      subject: 'owner',
      now,
      persist: false,
      constraints: [
        {
          id: 'today',
          kind: 'time_cap',
          detail: 'Limited time today',
          expiresAt: new Date(now.getTime() + 3600000).toISOString(),
        },
      ],
    });
    expect(constrained).toMatchObject({
      kind: 'workout',
      decision: { decision: { kind: 'adjust_training', adjustment: 'shorten_session' } },
    });
    const shortened = await applyWorkoutAction({
      records: h.records,
      subject: 'owner',
      now,
      sessionId: workout.session.id,
      eventId: randomUUID(),
      expectedRevision: 0,
      action: { kind: 'shorten', minutes: 15 },
    });
    expect(shortened).toMatchObject({
      kind: 'updated',
      decision: 'shortened',
      session: { executionRevision: 1 },
    });
    expect(delegatedSetupSchema.parse(h.context.legacySetups[0]).delegated.inputs).toEqual(inputs);
  });
  it('2: asks only the consequential missing question and never persists guessed inputs', async () => {
    const h = harness();
    h.context.canonicalTrainingInputs = {
      ...inputs,
      sessionsPerWeek: undefined,
      equipment: undefined,
    };
    const result = await h.propose({
      kind: 'recommend',
      inputs: {},
      adultConfirmed: true,
      safetyConfirmed: true,
    });
    expect(result).toMatchObject({
      kind: 'question',
      field: 'sessionsPerWeek',
      question: expect.stringContaining('days'),
    });
    expect(h.proposals.size).toBe(0);
    expect(h.context.headRevision).toBeNull();
  });
  it('3/4/5/6: constraints and exact kept variant/history survive, emphasis expires, completed history prepares one next block', async () => {
    const h = harness();
    await h.enroll();
    for (const intent of [
      { kind: 'keep', variantId: 'cable_curl', scope: 'durable' },
      { kind: 'prioritize', muscles: ['biceps'], scope: 'this_block' },
    ]) {
      const p = await h.propose(intent);
      if (p.kind !== 'stored') throw new Error(p.kind);
      expect((await h.apply(p.stored.proposal.id)).kind).toBe('decided');
    }
    await h.completeBlock();
    const finished = await getOrCreateNextWorkout({
      records: h.records,
      subject: 'owner',
      now: new Date('2026-12-01'),
    });
    expect(finished.kind).toBe('block_complete');
    const next = await prepareNextBlock(h);
    if (next.kind !== 'stored' || next.stored.proposal.version !== 2) throw new Error(next.kind);
    const p = next.stored.proposal;
    expect(p.transition?.expiring).toEqual(['biceps']);
    expect(p.transition?.primaryAction).toBe('Start next block');
    expect(p.proposedState.temporaryPriority).toBeNull();
    expect(p.proposedState.inputs).toMatchObject({
      equipment: 'full_gym',
      excludedVariantIds: ['barbell_romanian_deadlift'],
      preferredVariantIds: ['cable_curl'],
    });
    expect(
      p.plan.sessions.flatMap((s) => s.exercises).some((e) => e.variantId === 'cable_curl'),
    ).toBe(true);
    expect(await prepareNextBlock(h)).toEqual(next);
    expect((await h.apply(p.id)).kind).toBe('decided');
    const workout = await getOrCreateNextWorkout({ records: h.records, subject: 'owner', now });
    if (workout.kind !== 'workout') throw new Error(workout.kind);
    let current = workout;
    let curls = current.session.exercises.find((e) => e.id === 'cable_curl');
    if (!curls) {
      for (const e of current.session.exercises)
        for (let setNumber = 1; setNumber <= e.sets; setNumber++)
          await logTrainingSet({
            records: h.records,
            subject: 'owner',
            now,
            set: {
              sessionId: current.session.id,
              exerciseId: e.id,
              setNumber,
              reps: 9,
              loadKg: 12,
              rir: 3,
            },
          });
      const second = await getOrCreateNextWorkout({ records: h.records, subject: 'owner', now });
      if (second.kind !== 'workout') throw new Error(second.kind);
      current = second;
      curls = current.session.exercises.find((e) => e.id === 'cable_curl');
    }
    expect(curls?.targetLoadKg).toBe(12);
    expect(workout.week).toBe(1);
  });
  it('missed/empty workouts do not complete a block or roll forward with the calendar', async () => {
    const h = harness();
    await h.enroll();
    const later = await getOrCreateNextWorkout({
      records: h.records,
      subject: 'owner',
      now: new Date('2027-01-01'),
    });
    expect(later).toMatchObject({ kind: 'workout', week: 1, weekCount: 4 });
    expect((await prepareNextBlock(h)).kind).toBe('block_incomplete');
  });
  it('trainer schedule steering requires a current user grant and keeps an inspectable actor/diff', async () => {
    const h = harness();
    await h.enroll();
    const trainer: RevisionActor = { kind: 'trainer', subject: 'trainer' };
    const schedule = { kind: 'schedule', count: 4, scope: 'durable' };
    expect((await h.propose(schedule, trainer)).kind).toBe('unauthorized_actor');
    const grant = await h.propose({ kind: 'authorize_trainer', trainerSubject: 'trainer' });
    if (grant.kind !== 'stored') throw new Error(grant.kind);
    await h.apply(grant.stored.proposal.id);
    const p = await h.propose(schedule, trainer);
    if (p.kind !== 'stored') throw new Error(p.kind);
    expect(p.stored.proposal).toMatchObject({
      actor: trainer,
      authority: 'trainer_grant',
      proposedDiff: expect.arrayContaining([
        expect.objectContaining({ field: 'inputs.sessionsPerWeek', before: 2, after: 4 }),
      ]),
    });
    expect((await h.apply(p.stored.proposal.id, trainer)).kind).toBe('decided');
  });
  it('concurrent proposals admit one revision, rejection writes no new plan, restore revalidates an allowed revision', async () => {
    const h = harness();
    await h.enroll();
    const original = h.context.headRevision;
    const [a, b] = await Promise.all([
      h.propose({ kind: 'schedule', count: 4, scope: 'durable' }),
      h.propose({ kind: 'keep', variantId: 'cable_curl', scope: 'durable' }),
    ]);
    if (a.kind !== 'stored' || b.kind !== 'stored') throw new Error('missing drafts');
    expect(
      (await Promise.all([h.apply(a.stored.proposal.id), h.apply(b.stored.proposal.id)]))
        .map((r) => r.kind)
        .sort(),
    ).toEqual(['decided', 'stale_context']);
    const reject = await h.propose({ kind: 'schedule', count: 3, scope: 'durable' });
    if (reject.kind !== 'stored') throw new Error(reject.kind);
    const before = h.context.headRevision;
    await h.apply(reject.stored.proposal.id, user, 'reject');
    expect(h.context.headRevision).toBe(before);
    const restore = await h.propose({ kind: 'restore', revisionId: original });
    if (restore.kind !== 'stored') throw new Error(restore.kind);
    expect((await h.apply(restore.stored.proposal.id)).kind).toBe('decided');
    expect(delegatedSetupSchema.parse(h.context.legacySetups[0]).sessionsPerWeek).toBe(2);
  });
  it('refuses stale feedback, active-workout changes, unsafe keep and uncommitted success', async () => {
    const h = harness();
    await h.enroll();
    const p = await h.propose({ kind: 'schedule', count: 4, scope: 'durable' });
    if (p.kind !== 'stored') throw new Error(p.kind);
    await getOrCreateNextWorkout({ records: h.records, subject: 'owner', now });
    expect((await h.apply(p.stored.proposal.id)).kind).toBe('stale_context');
    const held = await h.propose({ kind: 'schedule', count: 3, scope: 'durable' });
    if (held.kind !== 'stored') throw new Error(held.kind);
    expect((await h.apply(held.stored.proposal.id)).kind).toBe('delayed_active_workout');
    expect(
      (await h.propose({ kind: 'keep', variantId: 'barbell_romanian_deadlift', scope: 'durable' }))
        .kind,
    ).toBe('question');
    jest.spyOn(h.port, 'decide').mockRejectedValueOnce(new Error('transaction rolled back'));
    await expect(h.apply(held.stored.proposal.id)).rejects.toThrow('transaction rolled back');
    expect(held.stored.status).toBe('proposed');
  });
  it.each([4, 5, 6] as const)(
    'retains a %i-week lifecycle with a final deload and no unknown equipment',
    (weekCount) => {
      const program = recommendProgram({ ...inputs, equipment: 'dumbbells' }, weekCount);
      expect(validateProgram(program)).toBeNull();
      expect(program.deloadWeek).toBe(weekCount);
    },
  );
  it('steers the first unaccepted recommendation through another immutable proposal', async () => {
    const h = harness();
    const first = await h.propose({
      kind: 'recommend',
      inputs: {},
      adultConfirmed: true,
      safetyConfirmed: true,
    });
    if (first.kind !== 'stored') throw new Error(first.kind);
    const kept = await h.propose(
      { kind: 'keep', variantId: 'supported_cable_curl', scope: 'durable' },
      user,
      first.stored.proposal.id,
    );
    if (kept.kind !== 'stored' || kept.stored.proposal.version !== 2) throw new Error(kept.kind);
    expect(h.context.headRevision).toBeNull();
    expect(first.stored.status).toBe('proposed');
    expect(kept.stored.proposal.proposedState.inputs.preferredVariantIds).toEqual([
      'supported_cable_curl',
    ]);
    expect((await h.apply(kept.stored.proposal.id)).kind).toBe('decided');
    expect((await h.apply(first.stored.proposal.id)).kind).toBe('stale_context');
  });
  it('renews a temporary priority only through explicit steering of the prepared next-block draft', async () => {
    const h = harness();
    await h.enroll();
    await h.completeBlock();
    const next = await prepareNextBlock(h);
    if (next.kind !== 'stored') throw new Error(next.kind);
    const renewed = await h.propose(
      { kind: 'prioritize', muscles: ['biceps'], scope: 'this_block' },
      user,
      next.stored.proposal.id,
    );
    if (renewed.kind !== 'stored' || renewed.stored.proposal.version !== 2)
      throw new Error(renewed.kind);
    expect(renewed.stored.proposal.proposedState).toMatchObject({
      blockNumber: 2,
      temporaryPriority: { muscles: ['biceps'], expiresAfterBlock: 2 },
    });
    expect((await h.apply(renewed.stored.proposal.id)).kind).toBe('decided');
    expect(delegatedSetupSchema.parse(h.context.legacySetups[0]).delegated.blockNumber).toBe(2);
  });
  it('schedule steering preserves completed weeks instead of relabeling missed work as completion', async () => {
    const h = harness();
    await h.enroll();
    await h.completeBlock();
    const changed = await h.propose({ kind: 'schedule', count: 4, scope: 'durable' });
    if (changed.kind !== 'stored' || changed.stored.proposal.version !== 2)
      throw new Error(changed.kind);
    expect(changed.stored.proposal.priorState?.delegated?.completedWeeks).toEqual({});
    expect(changed.stored.proposal.proposedState.completedWeeks).toEqual({
      '1': 2,
      '2': 2,
      '3': 2,
      '4': 2,
    });
    await h.apply(changed.stored.proposal.id);
    expect((await prepareNextBlock(h)).kind).toBe('stored');
  });
  it('allows deliberate coach delegation while retaining a user override path', async () => {
    const h = harness();
    await h.enroll();
    const grant = await h.propose({ kind: 'delegate_coach', enabled: true });
    if (grant.kind !== 'stored') throw new Error(grant.kind);
    await h.apply(grant.stored.proposal.id);
    const coach: RevisionActor = { kind: 'coach', subject: 'lyb-coach' };
    const p = await h.propose(
      { kind: 'prioritize', muscles: ['biceps'], scope: 'this_block' },
      coach,
    );
    if (p.kind !== 'stored') throw new Error(p.kind);
    expect(p.stored.proposal.authority).toBe('coach_delegation');
    expect((await h.apply(p.stored.proposal.id, coach)).kind).toBe('decided');
    const revoke = await h.propose({ kind: 'delegate_coach', enabled: false });
    if (revoke.kind !== 'stored') throw new Error(revoke.kind);
    expect((await h.apply(revoke.stored.proposal.id)).kind).toBe('decided');
  });
  it.each([false, true])(
    'adopts an existing baseline in place (reviewed=%s), reusing known schedule/equipment',
    async (reviewed) => {
      const h = harness();
      const baseline = await storeProgramSetup({
        records: h.records,
        subject: 'owner',
        now,
        createId: randomUUID,
        setup: {
          adultConfirmed: true,
          safetyConfirmed: true,
          sessionsPerWeek: 2,
          equipment: 'dumbbells',
          ...(reviewed
            ? { programRevisionId: randomUUID(), programPolicyVersion: 'hypertrophy-baseline-v1' }
            : {}),
        },
      });
      h.context.legacySetups = [baseline];
      h.context.headRevision = baseline.programRevisionId ?? null;
      h.context.canonicalTrainingInputs = {};
      const p = await h.propose({
        kind: 'recommend',
        inputs: {
          goal: 'Build muscle',
          experience: 'returning',
          minutesPerSession: 60,
          limitations: [],
          excludedVariantIds: [],
        },
        adultConfirmed: true,
        safetyConfirmed: true,
      });
      if (p.kind !== 'stored') throw new Error(p.kind);
      expect(p.stored.proposal.priorState).toEqual(baseline);
      expect(p.stored.proposal.programId).toBe(baseline.id);
      const result = await h.apply(p.stored.proposal.id);
      expect(result.kind).toBe('decided');
      expect(
        (await h.records.pull('owner', 'training_feedback')).records.filter(
          (r) => r.record_type === 'program_setup',
        ),
      ).toHaveLength(1);
    },
  );
  it('preserves LYB-119 upper-chest intent instead of silently broadening it to all chest work', async () => {
    const h = harness();
    h.context.canonicalTrainingInputs = { ...inputs, minutesPerSession: 90 };
    await h.enroll();
    const result = await createDelegatedProposal({
      ...h,
      body: {
        requestId: randomUUID(),
        expectedGeneration: h.context.generation,
        reason: 'Regional steering',
        utterance: 'prioritize upper chest',
      },
    });
    if (result.kind !== 'stored' || result.stored.proposal.version !== 2)
      throw new Error(result.kind);
    const p = result.stored.proposal;
    expect(p.proposedState.plan.policy).toMatchObject({ upperChest: true, priorityMuscles: [] });
    expect(
      p.proposedState.plan.sessions
        .flatMap((s) => s.exercises)
        .filter((e) => e.primaryMuscle === 'chest' && !e.variantId.includes('incline'))
        .every((e) => e.priority !== 'priority'),
    ).toBe(true);
    expect(p.summary).toContain('Prioritize upper chest for this block only.');
  });
});
