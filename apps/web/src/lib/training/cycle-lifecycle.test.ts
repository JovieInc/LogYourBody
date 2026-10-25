import { buildSession, configuredMesoBlock } from './engine';
import { cycleBlock } from './cycle-lifecycle';
import {
  applyWorkoutAction,
  logTrainingSet,
  swapExercise,
  recordTrainingFeedback,
} from './commands';
import { getOrCreateNextWorkout } from './service';
import { createInitialTrainingProposal, decideInitialTrainingProposal } from './revisions';
import { decisionBody, proposalBody, revisionHarness } from './revisions.testing';
import type { CycleLength, Session, TrainingProgramSetup } from './types';

const now = new Date('2026-10-10T12:00:00.000Z');
const setup: TrainingProgramSetup = {
  id: '33333333-3333-4333-8333-333333333333',
  consentVersion: 'hypertrophy-coach-v1',
  adultConfirmed: true,
  safetyConfirmed: true,
  sessionsPerWeek: 2,
  equipment: 'dumbbells',
  startedAt: now.toISOString(),
};

describe('configured engine cycles', () => {
  it.each([4, 5, 6] as CycleLength[])(
    'prescribes the %i-week RIR ladder and a reduced final deload',
    (length) => {
      const sessions = Array.from({ length }, (_, week) =>
        buildSession({
          setup,
          block: configuredMesoBlock(setup.startedAt, length, week * 2, 2),
          sessionId: `week-${week}`,
          slot: 0,
          logs: [],
          feedback: [],
        }),
      );
      expect(sessions.map((session) => session.exercises[0].targetRir)).toEqual(
        { 4: [4, 3, 2, 5], 5: [4, 3, 3, 2, 5], 6: [4, 4, 3, 3, 2, 5] }[length],
      );
      expect(
        sessions
          .slice(0, -1)
          .every((session) => session.exercises.every((exercise) => exercise.sets === 2)),
      ).toBe(true);
      expect(
        sessions
          .at(-1)
          ?.exercises.every(
            (exercise) =>
              exercise.sets === 1 && exercise.targetRir === 5 && exercise.progression === 'hold',
          ),
      ).toBe(true);
      expect(configuredMesoBlock(setup.startedAt, length, length * 2, 2).phase).toBe('review');
    },
  );
  it('planned final deload reduces work even without adverse feedback', () => {
    const session = buildSession({
      setup,
      sessionId: 'deload',
      slot: 0,
      logs: [],
      feedback: [],
      block: {
        id: 'block-1',
        startDate: setup.startedAt,
        weekCount: 4,
        currentWeek: 4,
        targetRir: 5,
        phase: 'planned_deload',
      },
    });
    expect(session.exercises[0].sets).toBe(1);
    expect(session.exercises[0].targetRir).toBe(5);
  });
  it('preserves reactive pain protection during planned deload', () => {
    const session = buildSession({
      setup,
      sessionId: 'pain',
      slot: 0,
      logs: [],
      block: configuredMesoBlock(setup.startedAt, 6, 10, 2),
      feedback: [{ id: 'pain', sessionId: 'prior', jointPain: 8, createdAt: now.toISOString() }],
    });
    expect(session.safetyStop).toBe(true);
    expect(session.exercises).toEqual([]);
  });
});

async function enrolled(
  length: CycleLength = 4,
  equipment: 'dumbbells' | 'full_gym' = 'dumbbells',
  declaredEquipment: string[] = [],
) {
  const h = revisionHarness();
  const created = await createInitialTrainingProposal({
    revisions: h.port,
    subject: 'owner',
    now,
    body: {
      ...proposalBody,
      intent: { ...proposalBody.intent, weekCount: length, equipment, declaredEquipment },
    },
  });
  if (created.kind !== 'stored') throw new Error(created.kind);
  const applied = await decideInitialTrainingProposal({
    revisions: h.port,
    subject: 'owner',
    now,
    body: decisionBody(created.stored.proposal.id),
  });
  if (applied.kind !== 'decided' || !applied.receipt.setup) throw new Error(applied.kind);
  h.context.trainingFingerprint = 'training-v1';
  return { ...h, setup: applied.receipt.setup };
}
async function next(h: Awaited<ReturnType<typeof enrolled>>, date = now) {
  const result = await getOrCreateNextWorkout({ records: h.records, subject: 'owner', now: date });
  if (result.kind !== 'workout') throw new Error(result.kind);
  return result;
}
async function complete(h: Awaited<ReturnType<typeof enrolled>>, session: Session, loadKg = 20) {
  for (const exercise of session.exercises)
    for (let setNumber = 1; setNumber <= exercise.sets; setNumber++) {
      expect(
        (
          await logTrainingSet({
            records: h.records,
            subject: 'owner',
            now,
            set: {
              sessionId: session.id,
              exerciseId: exercise.id,
              setNumber,
              reps: 10,
              loadKg,
              rir: session.exercises[0].targetRir,
            },
          })
        ).kind,
      ).toBe('logged');
    }
}
async function propose(
  h: Awaited<ReturnType<typeof enrolled>>,
  kind: 'revise_cycle' | 'repeat_cycle',
  length: CycleLength,
  extra = {},
) {
  return createInitialTrainingProposal({
    records: h.records,
    revisions: h.port,
    subject: 'owner',
    now,
    body: {
      ...proposalBody,
      requestId: `44444444-4444-4444-8444-44444444444${length}`,
      intent: { kind, weekCount: length, ...extra },
    },
  });
}
async function apply(h: Awaited<ReturnType<typeof enrolled>>, id: string) {
  return decideInitialTrainingProposal({
    records: h.records,
    revisions: h.port,
    subject: 'owner',
    now,
    body: { ...decisionBody(id), requestId: '55555555-5555-4555-8555-555555555555' },
  });
}

describe('cycle service and reviewed reuse', () => {
  it('does not turn missed weeks into completed training or replace an active incomplete session at calendar rollover', async () => {
    const h = await enrolled(6);
    const first = await next(h);
    const exercise = first.session.exercises[0];
    await logTrainingSet({
      records: h.records,
      subject: 'owner',
      now,
      set: {
        sessionId: first.session.id,
        exerciseId: exercise.id,
        setNumber: 1,
        reps: 10,
        loadKg: 20,
        rir: 4,
      },
    });
    const later = await next(h, new Date('2027-02-01'));
    expect(later.session.id).toBe(first.session.id);
    expect(later.session.exercises).toEqual(first.session.exercises);
    expect(later.week).toBe(1);
    expect(later.session.loggedSets).toHaveLength(1);
    expect(cycleBlock(h.setup, [], [], new Date('2028-01-01')).phase).toBe('accumulation');
  });
  it('ended incomplete and skipped work never advance the cycle or overwrite the ended attempt', async () => {
    const h = await enrolled();
    const first = await next(h);
    const skipped = await applyWorkoutAction({
      records: h.records,
      subject: 'owner',
      now,
      sessionId: first.session.id,
      eventId: 'skip',
      expectedRevision: 0,
      action: { kind: 'skip', exerciseId: first.session.exercises[0].id },
    });
    if (skipped.kind !== 'updated') throw new Error(skipped.kind);
    await complete(h, skipped.session);
    const replacement = await next(h);
    expect(replacement.week).toBe(1);
    expect(replacement.session.slot).toBe(0);
    expect(replacement.session.id).not.toBe(first.session.id);
    await applyWorkoutAction({
      records: h.records,
      subject: 'owner',
      now,
      sessionId: replacement.session.id,
      eventId: 'end',
      expectedRevision: 0,
      action: { kind: 'end' },
    });
    const third = await next(h);
    expect(third.session.id).not.toBe(replacement.session.id);
    expect(third.week).toBe(1);
    const rows = (await h.records.pull('owner', 'training_sessions')).records;
    expect(rows.find((row) => row.id === first.session.id)?.status).toBe('ended');
    expect(rows.find((row) => row.id === replacement.session.id)?.status).toBe('ended');
  });
  it('skipping every exercise leaves a terminal attempt that can be reopened safely', async () => {
    const h = await enrolled();
    const original = await next(h);
    for (const [index, exercise] of original.session.exercises.entries()) {
      expect(
        (
          await applyWorkoutAction({
            records: h.records,
            subject: 'owner',
            now,
            sessionId: original.session.id,
            eventId: `skip-${index}`,
            expectedRevision: index,
            action: { kind: 'skip', exerciseId: exercise.id },
          })
        ).kind,
      ).toBe('updated');
    }
    const replacement = await next(h);
    expect(replacement.week).toBe(1);
    expect(replacement.session.id).not.toBe(original.session.id);
    expect(
      (await h.records.pull('owner', 'training_sessions')).records.find(
        (row) => row.id === original.session.id,
      )?.status,
    ).toBe('ended');
  });
  it('recovers and acknowledges a skipped attempt whose final execution write was interrupted', async () => {
    const h = await enrolled();
    const original = await next(h);
    const skipped = await applyWorkoutAction({
      records: h.records,
      subject: 'owner',
      now,
      sessionId: original.session.id,
      eventId: 'skip',
      expectedRevision: 0,
      action: { kind: 'skip', exerciseId: original.session.exercises[0].id },
    });
    if (skipped.kind !== 'updated') throw new Error(skipped.kind);
    await complete(h, skipped.session);
    const sessionRows = (await h.records.pull('owner', 'training_sessions')).records;
    const saved = sessionRows.find((row) => row.id === original.session.id)!;
    await h.records.push('owner', 'training_sessions', [{ ...saved, status: 'in_progress' }]);
    const replacement = await next(h);
    expect(replacement.week).toBe(1);
    expect(replacement.session.id).not.toBe(original.session.id);
    const last = skipped.session.exercises.at(-1)!;
    expect(
      await logTrainingSet({
        records: h.records,
        subject: 'owner',
        now,
        set: {
          sessionId: original.session.id,
          exerciseId: last.id,
          setNumber: last.sets,
          reps: 10,
          loadKg: 20,
          rir: skipped.session.exercises[0].targetRir,
        },
      }),
    ).toMatchObject({ kind: 'logged', sessionComplete: true });
  });
  it.each([4, 5, 6] as CycleLength[])(
    'runs %i weeks and stops for review without auto-starting another block',
    async (length) => {
      const h = await enrolled(length);
      for (let index = 0; index < length * 2; index++) {
        const workout = await next(h);
        expect(workout.week).toBe(Math.floor(index / 2) + 1);
        expect(workout.phase).toBe(
          index >= (length - 1) * 2 ? 'planned_deload' : index < 2 ? 'accumulation' : 'adjustment',
        );
        await complete(h, workout.session);
      }
      const reviewed = await getOrCreateNextWorkout({
        records: h.records,
        subject: 'owner',
        now: new Date('2028-01-01'),
      });
      expect(reviewed).toMatchObject({ kind: 'week_complete', phase: 'review', week: length });
      expect((await h.records.pull('owner', 'training_sessions')).records).toHaveLength(length * 2);
    },
  );
  it.each([
    [6, 4],
    [4, 6],
  ] as [CycleLength, CycleLength][])(
    'reviews length change from %i to %i while preserving unfinished targets and logs',
    async (from, to) => {
      const h = await enrolled(from);
      const unfinished = await next(h);
      const result = await propose(h, 'revise_cycle', to);
      if (result.kind !== 'stored') throw new Error(result.kind);
      expect(h.context.headRevision).toBe(h.setup.programRevisionId);
      expect(result.stored.proposal.priorState?.setup.cycle?.weekCount).toBe(from);
      expect(result.stored.proposal.proposedSetup?.cycle?.weekCount).toBe(to);
      expect((await apply(h, result.stored.proposal.id)).kind).toBe('decided');
      const retained = await next(h);
      expect(retained.session.exercises).toEqual(unfinished.session.exercises);
      expect(retained.session.id).toBe(unfinished.session.id);
      expect(retained.weekCount).toBe(to);
      await complete(h, retained.session);
    },
  );
  it('rejects stale training drafts and shortening that would remove an already-started deload boundary', async () => {
    const h = await enrolled(6);
    const draft = await propose(h, 'revise_cycle', 5);
    if (draft.kind !== 'stored') throw new Error(draft.kind);
    h.context.trainingFingerprint = 'training-changed';
    expect(await apply(h, draft.stored.proposal.id)).toEqual({ kind: 'stale_context' });
    for (let i = 0; i < 7; i++) await complete(h, (await next(h)).session);
    expect(await propose(h, 'revise_cycle', 4)).toEqual({
      kind: 'deload_boundary_requires_review',
    });
  });
  it('requires block review before reuse and refuses fabricated or incompatible variants', async () => {
    const h = await enrolled();
    expect(await propose(h, 'repeat_cycle', 4)).toEqual({ kind: 'cycle_review_required' });
    for (let i = 0; i < 8; i++) await complete(h, (await next(h)).session);
    expect(
      await propose(h, 'repeat_cycle', 4, {
        keepVariants: [
          { fromExerciseId: 'goblet_squat', toVariantId: 'smith_incline_press', reason: 'worked' },
        ],
      }),
    ).toEqual({ kind: 'invalid_reuse_selection' });
  });
  it('reuses the exact worked variant with its own load history, feedback and reason', async () => {
    const h = await enrolled(4, 'full_gym', ['smith']);
    await complete(h, (await next(h)).session, 80);
    await complete(h, (await next(h)).session);
    const beforeSwap = await next(h);
    expect(
      (
        await swapExercise({
          records: h.records,
          subject: 'owner',
          now,
          swap: {
            sessionId: beforeSwap.session.id,
            exerciseId: 'machine_chest_press',
            toVariantId: 'smith_incline_press',
          },
        })
      ).kind,
    ).toBe('swapped');
    const worked = await next(h);
    expect(
      worked.session.exercises.find((exercise) => exercise.id === 'smith_incline_press')
        ?.targetLoadKg,
    ).toBeNull();
    await complete(h, worked.session);
    await recordTrainingFeedback({
      records: h.records,
      subject: 'owner',
      now,
      createId: () => '66666666-6666-4666-8666-666666666666',
      feedback: {
        sessionId: worked.session.id,
        pump: 6,
        originalStatement: 'This setup worked well.',
        source: 'touch',
      },
    });
    for (let i = 3; i < 8; i++) await complete(h, (await next(h)).session);
    const feedbackBefore = (await h.records.listAll('owner')).training_feedback.filter(
      (row) => row.record_type === 'session_feedback',
    );
    const result = await propose(h, 'repeat_cycle', 5, {
      keepVariants: [
        {
          fromExerciseId: 'machine_chest_press',
          toVariantId: 'smith_incline_press',
          reason: 'Comfortable setup and useful feedback',
        },
      ],
    });
    if (result.kind !== 'stored') throw new Error(result.kind);
    const draft = result.stored.proposal;
    expect(draft.lifecyclePhase).toBe('next_block');
    expect(
      draft.plan.sessions[0].exercises.find((exercise) => exercise.id === 'smith_incline_press'),
    ).toMatchObject({ targetLoadKg: 20 });
    expect((await apply(h, draft.id)).kind).toBe('decided');
    const repeated = await next(h);
    expect(
      repeated.session.exercises.find((exercise) => exercise.id === 'smith_incline_press'),
    ).toMatchObject({ targetLoadKg: 20 });
    expect(
      repeated.session.exercises.some((exercise) => exercise.id === 'machine_chest_press'),
    ).toBe(false);
    expect(
      (await h.records.listAll('owner')).training_feedback.filter(
        (row) => row.record_type === 'session_feedback',
      ),
    ).toEqual(feedbackBefore);
  });
  it.each([false, true])(
    'expires temporary priorities/constraints unless renewed (%s) while faithfully retaining selected variants and history',
    async (renew) => {
      const h = await enrolled();
      const modified = {
        ...h.setup,
        excludedVariantIds: ['barbell_romanian_deadlift'],
        cycle: {
          ...h.setup.cycle!,
          temporaryPriorities: ['chest'],
          temporaryConstraints: [{ muscle: 'quads', reason: 'Temporary preference' }],
        },
      };
      await h.records.push('owner', 'training_feedback', [
        { ...modified, record_type: 'program_setup' },
      ]);
      for (let i = 0; i < 8; i++) await complete(h, (await next(h)).session);
      const result = await propose(h, 'repeat_cycle', 5, {
        renewPriorities: renew,
        renewConstraints: renew,
        keepVariants: [
          {
            fromExerciseId: 'goblet_squat',
            toVariantId: 'goblet_squat',
            reason: 'Comfortable and reliable',
          },
        ],
      });
      if (result.kind !== 'stored') throw new Error(result.kind);
      const draft = result.stored.proposal;
      expect(draft.reviewPoint).toBe('before_next_block');
      expect(draft.proposedSetup?.cycle?.temporaryPriorities).toEqual(renew ? ['chest'] : []);
      expect(draft.proposedSetup?.cycle?.temporaryConstraints).toHaveLength(renew ? 1 : 0);
      expect(draft.proposedSetup?.equipment).toBe('dumbbells');
      expect(draft.proposedSetup?.excludedVariantIds).toEqual(['barbell_romanian_deadlift']);
      expect(draft.proposedSetup?.cycle?.historyProgramIds).toContain(h.setup.id);
      expect(draft.assumptions).toContain('Goblet squat: Comfortable and reliable');
      const before = await h.records.listAll('owner');
      expect((await apply(h, draft.id)).kind).toBe('decided');
      const reused = await next(h);
      expect(reused.week).toBe(1);
      expect(reused.session.exercises[0]).toMatchObject({ id: 'goblet_squat', targetLoadKg: 20 });
      expect((await h.records.listAll('owner')).logged_sets).toEqual(before.logged_sets);
    },
  );
});
