import { buildSession, createMesoBlock } from './engine';
import type { MesocycleLength, TrainingProgramSetup } from './types';

const startedAt = '2026-01-05T00:00:00.000Z';
const setup: TrainingProgramSetup = {
  id: 'setup',
  consentVersion: 'hypertrophy-coach-v1',
  adultConfirmed: true,
  safetyConfirmed: true,
  sessionsPerWeek: 2,
  equipment: 'dumbbells',
  startedAt,
};

it.each<[MesocycleLength, number[]]>([
  [4, [4, 3, 2, 5]],
  [5, [4, 3, 3, 2, 5]],
  [6, [4, 4, 3, 3, 2, 5]],
])('prescribes the %i-week ladder and final reduced-volume deload', (weekCount, ladder) => {
  for (let week = 1; week <= weekCount; week++) {
    const block = createMesoBlock(
      startedAt,
      new Date(Date.parse(startedAt) + (week - 1) * 7 * 86400000).toISOString(),
      { weekCount, completedWeeks: week - 1 },
    );
    expect(block.currentWeek).toBe(week);
    expect(block.targetRir).toBe(ladder[week - 1]);
    const session = buildSession({ setup, block, slot: 0, sessionId: 's', logs: [], feedback: [] });
    expect(session.exercises.every((e) => e.sets === (week === weekCount ? 1 : 2))).toBe(true);
    if (week === weekCount) {
      expect(block.phase).toBe('planned_deload');
      expect(session.explanation).toMatch(/planned deload/i);
    }
  }
});

import { applyWorkoutAction, logTrainingSet } from './commands';
import { MemoryTrainingRecords } from './memory-records.testing';
import { getOrCreateNextWorkout, storeProgramSetup } from './service';
import { cycleBlock, cycleLifecycle } from './lifecycle';
import type { NativeProductRecord } from '@/lib/ports/native-product-records';

const later = new Date('2026-06-01T00:00:00Z');
async function cycleRecords(weekCount: MesocycleLength = 4) {
  const records = new MemoryTrainingRecords();
  const program = await storeProgramSetup({
    records,
    subject: 'owner',
    now: new Date(startedAt),
    createId: () => '11111111-1111-4111-8111-111111111111',
    setup: {
      adultConfirmed: true,
      safetyConfirmed: true,
      equipment: 'dumbbells',
      sessionsPerWeek: 2,
      cycle: {
        weekCount,
        number: 1,
        priorities: [{ muscle: 'back', reason: 'My goal this block' }],
        constraints: [{ id: 'time', reason: 'Temporary schedule' }],
        retainedVariants: [],
        historySetupIds: [],
      },
    },
  });
  return { records, program };
}
async function workout(records: MemoryTrainingRecords, now = later) {
  const result = await getOrCreateNextWorkout({ records, subject: 'owner', now });
  if (result.kind !== 'workout') throw new Error(result.kind);
  return result;
}
async function complete(
  records: MemoryTrainingRecords,
  session: ReturnType<typeof buildSession>,
  now = later,
) {
  for (const exercise of session.exercises)
    for (let setNumber = 1; setNumber <= exercise.sets; setNumber++) {
      const result = await logTrainingSet({
        records,
        subject: 'owner',
        now,
        set: {
          sessionId: session.id,
          exerciseId: exercise.id,
          setNumber,
          reps: 12,
          rir: 5,
          loadKg: 10,
        },
      });
      expect(result.kind).toBe('logged');
    }
}

it('never advances missed training on calendar rollover and retains an incomplete active prescription', async () => {
  const { records } = await cycleRecords(6);
  const first = await workout(records, new Date(startedAt));
  const exercise = first.session.exercises[0]!;
  await logTrainingSet({
    records,
    subject: 'owner',
    now: new Date(startedAt),
    set: {
      sessionId: first.session.id,
      exerciseId: exercise.id,
      setNumber: 1,
      reps: 8,
      rir: 4,
      loadKg: 10,
    },
  });
  const reopened = await workout(records);
  expect(reopened.week).toBe(1);
  expect(reopened.lifecycle).toMatchObject({ phase: 'accumulation', weekCount: 6 });
  expect(reopened.session.exercises).toEqual(first.session.exercises);
  expect(reopened.session.loggedSets).toHaveLength(1);
});

it.each([false, true])(
  'early end remains skipped/incomplete and never counts as completed (logged=%s)',
  async (logged) => {
    const { records } = await cycleRecords();
    const first = await workout(records);
    if (logged) {
      const exercise = first.session.exercises[0]!;
      await logTrainingSet({
        records,
        subject: 'owner',
        now: later,
        set: {
          sessionId: first.session.id,
          exerciseId: exercise.id,
          setNumber: 1,
          reps: 8,
          rir: 4,
          loadKg: 10,
        },
      });
    }
    expect(
      await applyWorkoutAction({
        records,
        subject: 'owner',
        now: later,
        sessionId: first.session.id,
        expectedRevision: 0,
        eventId: 'end',
        action: { kind: 'end' },
      }),
    ).toMatchObject({ kind: 'updated' });
    const ended = (await records.pull('owner', 'training_sessions')).records.find(
      (row) => row.id === first.session.id,
    )!;
    expect(ended.status).toBe(logged ? 'incomplete' : 'skipped');
    const next = await workout(records);
    expect(next.week).toBe(1);
    expect(next.session.slot).toBe(0);
    expect(next.session.id).not.toBe(first.session.id);
    expect(next.session.exercises[0]?.targetLoadKg).toBeNull();
  },
);

it('skipping every exercise is a skipped session with a fresh attempt identity', async () => {
  const { records } = await cycleRecords();
  const first = await workout(records);
  for (const [index, exercise] of first.session.exercises.entries()) {
    expect(
      await applyWorkoutAction({
        records,
        subject: 'owner',
        now: later,
        sessionId: first.session.id,
        expectedRevision: index,
        eventId: `skip-${index}`,
        action: { kind: 'skip', exerciseId: exercise.id },
      }),
    ).toMatchObject({ kind: 'updated' });
  }
  const next = await workout(records);
  expect(next.week).toBe(1);
  expect(next.session.exercises).toHaveLength(first.session.exercises.length);
  expect(next.session.id).not.toBe(first.session.id);
});

it.each([4, 5, 6] as const)(
  'completes %i weeks including deload then waits for reviewed next block',
  async (weekCount) => {
    const { records } = await cycleRecords(weekCount);
    for (let week = 1; week <= weekCount; week++)
      for (let slot = 0; slot < 2; slot++) {
        const current = await workout(records);
        expect(current.week).toBe(week);
        expect(current.session.slot).toBe(slot);
        expect(
          current.session.exercises.every(
            (exercise) => exercise.sets === (week === weekCount ? 1 : 2),
          ),
        ).toBe(true);
        if (week === weekCount)
          expect(
            current.session.exercises.every((exercise) => exercise.progression === 'hold'),
          ).toBe(true);
        await complete(records, current.session);
      }
    const result = await getOrCreateNextWorkout({ records, subject: 'owner', now: later });
    expect(result).toMatchObject({
      kind: 'week_complete',
      lifecycle: { phase: 'review', nextPhase: 'next_block', priorities: [], constraints: [] },
    });
  },
);

it('waits for the next calendar week after completing this week early', async () => {
  const { records } = await cycleRecords();
  for (let slot = 0; slot < 2; slot++)
    await complete(
      records,
      (await workout(records, new Date(startedAt))).session,
      new Date(startedAt),
    );
  expect(
    await getOrCreateNextWorkout({ records, subject: 'owner', now: new Date(startedAt) }),
  ).toMatchObject({ kind: 'week_complete', week: 1 });
  expect((await workout(records, new Date('2026-01-12'))).week).toBe(2);
});

it('keeps reactive pain protection during the planned deload', () => {
  const program = {
    ...setup,
    cycle: {
      weekCount: 4 as const,
      number: 1,
      priorities: [],
      constraints: [],
      retainedVariants: [],
      historySetupIds: [],
    },
  };
  const block = createMesoBlock(startedAt, later.toISOString(), {
    weekCount: 4,
    completedWeeks: 3,
  });
  const observations = [
    { id: 'pain', sessionId: 'prior', jointPain: 8, createdAt: later.toISOString() },
  ];
  expect(
    buildSession({
      setup: program,
      block,
      sessionId: 'pause',
      slot: 0,
      logs: [],
      feedback: observations,
    }),
  ).toMatchObject({ safetyStop: true, exercises: [] });
  expect(cycleLifecycle(program, [], observations, later)?.phase).toBe('reactive_deload');
});

export function completedCycleRows(
  program: TrainingProgramSetup,
  weeks = program.cycle!.weekCount,
): NativeProductRecord[] {
  return Array.from({ length: weeks * program.sessionsPerWeek }, (_, index) => {
    const week = Math.floor(index / program.sessionsPerWeek) + 1;
    const slot = index % program.sessionsPerWeek;
    const block = createMesoBlock(program.startedAt, later.toISOString(), {
      weekCount: program.cycle!.weekCount,
      completedWeeks: week - 1,
      number: program.cycle!.number,
    });
    return {
      id: `completed-${index}`,
      deleted_at: null,
      server_updated_at: later.toISOString(),
      record_type: 'workout_session',
      programSetupId: program.id,
      blockId: block.id,
      cyclePhase: block.phase,
      weekNumber: week,
      slot,
      status: 'completed',
      prescription: buildSession({
        setup: program,
        block,
        slot,
        sessionId: `completed-${index}`,
        logs: [],
        feedback: [],
      }),
    };
  });
}

it('does not treat holes in recorded weeks as completed training', () => {
  const program = {
    ...setup,
    cycle: {
      weekCount: 4 as const,
      number: 1,
      priorities: [],
      constraints: [],
      retainedVariants: [],
      historySetupIds: [],
    },
  };
  const rows = completedCycleRows(program).filter((row) => row.weekNumber !== 2);
  expect(cycleBlock(program, rows, later).currentWeek).toBe(2);
});

import {
  createInitialTrainingProposal,
  decideInitialTrainingProposal,
  trainingRequestHash,
} from './revisions';
import { revisionHarness, proposalBody, decisionBody } from './revisions.testing';
import { loadTrainingRecords } from './service';

let requestNumber = 100;
const requestId = () => `11111111-1111-4111-8111-${String(requestNumber++).padStart(12, '0')}`;
async function reviewedCycle(weekCount: MesocycleLength = 6) {
  const h = revisionHarness();
  jest.mocked(h.port.readContext).mockImplementation(async (subject) => {
    if (subject !== 'owner') return null;
    return {
      ...h.context,
      trainingFingerprint: trainingRequestHash(await h.records.listAll('owner')),
    };
  });
  const input = {
    revisions: h.port,
    records: h.records,
    subject: 'owner',
    now: new Date(startedAt),
  };
  const created = await createInitialTrainingProposal({
    ...input,
    body: { ...proposalBody, intent: { ...proposalBody.intent, weekCount } },
  });
  if (created.kind !== 'stored') throw new Error(created.kind);
  expect((await h.records.pull('owner', 'training_feedback')).records).toHaveLength(0);
  expect(
    await decideInitialTrainingProposal({
      ...input,
      body: decisionBody(created.stored.proposal.id),
    }),
  ).toMatchObject({ kind: 'decided' });
  const program = (await loadTrainingRecords(h.records, 'owner')).setup!;
  return { ...h, input: { ...input, now: later }, program };
}
async function draftCycle(
  h: Awaited<ReturnType<typeof reviewedCycle>>,
  intent: unknown,
  reason = 'Reviewed block change',
) {
  return createInitialTrainingProposal({
    ...h.input,
    body: { requestId: requestId(), expectedGeneration: 0, intent, reason },
  });
}
async function applyCycle(h: Awaited<ReturnType<typeof reviewedCycle>>, proposalId: string) {
  return decideInitialTrainingProposal({
    ...h.input,
    body: { ...decisionBody(proposalId), requestId: requestId() },
  });
}

it.each<[MesocycleLength, MesocycleLength]>([
  [6, 4],
  [4, 6],
  [6, 5],
  [5, 6],
])('reviews shortening/extension %i → %i without rewriting history', async (from, to) => {
  const h = await reviewedCycle(from);
  await h.records.push('owner', 'training_sessions', completedCycleRows(h.program, 2));
  const before = await h.records.pull('owner', 'training_sessions');
  const proposed = await draftCycle(h, { kind: 'revise_cycle', weekCount: to });
  if (proposed.kind !== 'stored') throw new Error(proposed.kind);
  expect((await loadTrainingRecords(h.records, 'owner')).setup?.cycle?.weekCount).toBe(from);
  expect(proposed.stored.proposal).toMatchObject({
    baseRevision: h.context.headRevision,
    reviewPoint: 'before_cycle_revision',
    plan: { week: 3 },
  });
  expect(await applyCycle(h, proposed.stored.proposal.id)).toMatchObject({
    kind: 'decided',
    receipt: { status: 'applied', priorState: { setupId: h.program.id } },
  });
  const updated = (await loadTrainingRecords(h.records, 'owner')).setup!;
  expect(updated.id).toBe(h.program.id);
  expect(updated.startedAt).toBe(startedAt);
  expect(updated.cycle?.weekCount).toBe(to);
  expect(await h.records.pull('owner', 'training_sessions')).toEqual(before);
});

it('rejects shortening over trained weeks and extension after deload', async () => {
  const h = await reviewedCycle(6);
  await h.records.push('owner', 'training_sessions', completedCycleRows(h.program, 4));
  expect(await draftCycle(h, { kind: 'revise_cycle', weekCount: 4 })).toMatchObject({
    kind: 'cycle_review_required',
  });
  const h3 = await reviewedCycle(4);
  await h3.records.push('owner', 'training_sessions', completedCycleRows(h3.program));
  expect(await draftCycle(h3, { kind: 'revise_cycle', weekCount: 6 })).toMatchObject({
    kind: 'cycle_review_required',
  });
});

it('requires refreshed review when training changes after a draft and supports explicit rejection', async () => {
  const h = await reviewedCycle();
  const proposed = await draftCycle(h, { kind: 'revise_cycle', weekCount: 4 });
  if (proposed.kind !== 'stored') throw new Error(proposed.kind);
  await workout(h.records);
  expect(await applyCycle(h, proposed.stored.proposal.id)).toMatchObject({ kind: 'stale_context' });
  expect((await loadTrainingRecords(h.records, 'owner')).setup?.cycle?.weekCount).toBe(6);
  expect(
    await decideInitialTrainingProposal({
      ...h.input,
      body: { ...decisionBody(proposed.stored.proposal.id, 'reject'), requestId: requestId() },
    }),
  ).toMatchObject({ kind: 'decided', receipt: { status: 'rejected', setup: null } });
});

it.each([false, true])(
  'repeats selected variants faithfully and expires or explicitly renews temporary preferences (renew=%s)',
  async (renew) => {
    const h = await reviewedCycle(4);
    const temporary = {
      priorities: [{ muscle: 'back' as const, reason: 'User-selected focus' }],
      constraints: [{ id: 'time', reason: 'Temporary schedule' }],
    };
    h.program.cycle = { ...h.program.cycle!, ...temporary };
    h.program.excludedVariantIds = ['cable_curl', 'goblet_squat'];
    await h.records.push('owner', 'training_feedback', [
      { ...h.program, record_type: 'program_setup' },
    ]);
    await h.records.push('owner', 'training_sessions', completedCycleRows(h.program));
    const source = (await h.records.pull('owner', 'training_sessions')).records[0]!;
    await h.records.push(
      'owner',
      'logged_sets',
      [1, 2].map((setNumber) => ({
        id: `log-${setNumber}`,
        record_type: 'set_log',
        sessionId: source.id,
        exerciseId: 'dumbbell_split_squat',
        setNumber,
        reps: 9,
        loadKg: 17,
        rir: 4,
        completedAt: later.toISOString(),
      })),
    );
    await h.records.push('owner', 'training_feedback', [
      {
        id: 'feedback',
        record_type: 'session_feedback',
        sessionId: source.id,
        soreness: 1,
        jointPain: 0,
        createdAt: later.toISOString(),
      },
    ]);
    const retained = {
      fromExerciseId: 'goblet_squat',
      toVariantId: 'dumbbell_split_squat',
      reason: 'This variant was comfortable and progressed',
    };
    const prior = await h.records.listAll('owner');
    const proposed = await draftCycle(
      h,
      {
        kind: 'repeat_cycle',
        weekCount: 5,
        retainedVariants: [retained],
        ...(renew ? temporary : {}),
      },
      'Repeat the last meso and keep exercises that worked',
    );
    if (proposed.kind !== 'stored') throw new Error(proposed.kind);
    expect(await h.records.listAll('owner')).toEqual(prior);
    expect(proposed.stored.proposal.plan.sessions[0]?.exercises[0]).toMatchObject({
      id: 'dumbbell_split_squat',
      targetLoadKg: 17,
      targetReps: 10,
    });
    expect(await applyCycle(h, proposed.stored.proposal.id)).toMatchObject({ kind: 'decided' });
    const current = (await loadTrainingRecords(h.records, 'owner')).setup!;
    expect(current.id).not.toBe(h.program.id);
    expect(current.equipment).toBe('dumbbells');
    expect(current.excludedVariantIds).toEqual(['cable_curl', 'goblet_squat']);
    expect(current.cycle).toMatchObject({
      number: 2,
      weekCount: 5,
      retainedVariants: [retained],
      historySetupIds: [h.program.id],
      priorities: renew ? temporary.priorities : [],
      constraints: renew ? temporary.constraints : [],
    });
    const next = await workout(h.records);
    expect(next.session.exercises[0]).toMatchObject({
      id: 'dumbbell_split_squat',
      targetLoadKg: 17,
      targetReps: 10,
    });
    expect((await loadTrainingRecords(h.records, 'owner')).feedback).toHaveLength(1);
    expect((await h.records.pull('owner', 'logged_sets')).records).toHaveLength(2);
  },
);

it('rejects unavailable, excluded, mismatched or unobserved reuse variants', async () => {
  const h = await reviewedCycle(4);
  await h.records.push('owner', 'training_sessions', completedCycleRows(h.program));
  for (const toVariantId of ['cable_curl', 'machine_chest_press', 'unknown_variant']) {
    expect(
      await draftCycle(h, {
        kind: 'repeat_cycle',
        weekCount: 4,
        retainedVariants: [{ fromExerciseId: 'goblet_squat', toVariantId, reason: 'Keep this' }],
      }),
    ).toMatchObject({ kind: 'cycle_review_required' });
  }
});

it('revises length with an active incomplete session and preserves its exact targets at calendar rollover', async () => {
  const h = await reviewedCycle(4);
  const first = await workout(h.records);
  const exercise = first.session.exercises[0]!;
  await logTrainingSet({
    records: h.records,
    subject: 'owner',
    now: later,
    set: {
      sessionId: first.session.id,
      exerciseId: exercise.id,
      setNumber: 1,
      reps: 8,
      rir: 4,
      loadKg: 10,
    },
  });
  const proposed = await draftCycle(h, { kind: 'revise_cycle', weekCount: 6 });
  if (proposed.kind !== 'stored') throw new Error(proposed.kind);
  expect(await applyCycle(h, proposed.stored.proposal.id)).toMatchObject({ kind: 'decided' });
  const reopened = await workout(h.records, new Date('2026-07-01'));
  expect(reopened.weekCount).toBe(6);
  expect(reopened.session.exercises).toEqual(first.session.exercises);
  expect(reopened.session.loggedSets).toHaveLength(1);
  expect(
    await logTrainingSet({
      records: h.records,
      subject: 'owner',
      now: later,
      set: {
        sessionId: reopened.session.id,
        exerciseId: exercise.id,
        setNumber: 2,
        reps: 8,
        rir: 4,
        loadKg: 10,
      },
    }),
  ).toMatchObject({ kind: 'logged' });
});

it('retains deload history without using its reduced work as next-block progression evidence', async () => {
  const h = await reviewedCycle(4);
  const rows = completedCycleRows(h.program);
  await h.records.push('owner', 'training_sessions', rows);
  const accumulation = rows.find((row) => row.weekNumber === 3 && row.slot === 0)!;
  const deload = rows.find((row) => row.weekNumber === 4 && row.slot === 0)!;
  await h.records.push(
    'owner',
    'logged_sets',
    [1, 2]
      .map((setNumber) => ({
        id: `accumulation-${setNumber}`,
        record_type: 'set_log',
        sessionId: accumulation.id,
        exerciseId: 'goblet_squat',
        setNumber,
        reps: 9,
        loadKg: 17,
        rir: 4,
        completedAt: '2026-01-23T00:00:00Z',
      }))
      .concat([
        {
          id: 'deload-log',
          record_type: 'set_log',
          sessionId: deload.id,
          exerciseId: 'goblet_squat',
          setNumber: 1,
          reps: 8,
          loadKg: 12,
          rir: 5,
          completedAt: '2026-01-30T00:00:00Z',
        },
      ]),
  );
  const proposed = await draftCycle(h, {
    kind: 'repeat_cycle',
    weekCount: 6,
    retainedVariants: [
      { fromExerciseId: 'goblet_squat', toVariantId: 'goblet_squat', reason: 'Worked well' },
    ],
  });
  if (proposed.kind !== 'stored') throw new Error(proposed.kind);
  expect(proposed.stored.proposal.plan.sessions[0]?.exercises[0]).toMatchObject({
    targetLoadKg: 17,
    targetReps: 10,
  });
  expect(await applyCycle(h, proposed.stored.proposal.id)).toMatchObject({ kind: 'decided' });
  expect((await workout(h.records)).session.exercises[0]).toMatchObject({
    targetLoadKg: 17,
    targetReps: 10,
  });
  expect((await h.records.pull('owner', 'logged_sets')).records).toHaveLength(3);
});
