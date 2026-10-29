import {
  amendCanvasProposal,
  canvasAgrees,
  decideCanvasProposal,
  interpretPlanUtterance,
  memoryCanvasPort,
  planUtteranceProposal,
  proposeCanvasEdit,
  readCanvas,
  type CanvasLedgerPort,
  type CanvasPlan,
  type PlanOperation,
} from './mesocycle-canvas';
import {
  mesocycleCanvasApiEnabled,
  mesocycleCanvasEnabled,
  mesocycleCanvasFixtureEnabled,
} from '@/lib/flags/mesocycle-canvas';

const NOW = '2026-10-14T18:00:00.000Z';
const IDS = [
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  '33333333-3333-4333-8333-333333333333',
  '44444444-4444-4444-8444-444444444444',
  '55555555-5555-4555-8555-555555555555',
  '66666666-6666-4666-8666-666666666666',
  '77777777-7777-4777-8777-777777777777',
  '88888888-8888-4888-8888-888888888888',
  '99999999-9999-4999-8999-999999999999',
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
] as const;

function lowerIds(plan: CanvasPlan): string[] {
  return plan.sessions
    .flatMap((session) => session.exercises)
    .filter((exercise) =>
      ['quads', 'hamstrings', 'glutes', 'calves'].includes(exercise.primaryMuscle),
    )
    .map((exercise) => exercise.instanceId)
    .sort();
}

function exercise(plan: CanvasPlan, name: string) {
  return plan.sessions.flatMap((session) => session.exercises).find((item) => item.name === name);
}

function days(plan: CanvasPlan): string[] {
  return [...new Set(plan.sessions.map((session) => session.day))];
}

async function accept(
  port: CanvasLedgerPort,
  operation: PlanOperation,
  requestId: string,
  decisionId: string,
) {
  const before = (await readCanvas(port, 'owner')).readback;
  const proposed = await proposeCanvasEdit(port, 'owner', {
    requestId,
    expectedWrite: before.write,
    operation,
    now: NOW,
  });
  if (proposed.kind !== 'proposed') return proposed;
  return decideCanvasProposal(port, 'owner', {
    requestId: decisionId,
    proposalId: proposed.proposal.id,
    decision: 'apply',
    expectedWrite: proposed.readback.write,
    now: NOW,
  });
}

describe('mesocycle canvas revisions', () => {
  it('persists a reviewable priority reorder without changing volume, then undoes it', async () => {
    const port = memoryCanvasPort();
    const drafted = await accept(
      port,
      { kind: 'draft', goal: 'Growth', equipment: 'full_gym', weekCount: 4 },
      IDS[0],
      IDS[1],
    );
    const before = drafted.readback;
    const operation = interpretPlanUtterance('Put side delts first');
    expect(operation).toEqual({ kind: 'order_priority', muscles: ['side_delts'] });
    const proposed = await proposeCanvasEdit(port, 'owner', {
      requestId: IDS[2],
      expectedWrite: before.write,
      operation: operation!,
      now: NOW,
    });
    expect(proposed.kind).toBe('proposed');
    if (proposed.kind !== 'proposed') return;
    expect(proposed.proposal.changes.some((row) => row.kind === 'reordered')).toBe(true);
    expect((await readCanvas(port, 'owner')).readback.plan).toEqual(before.plan);
    const amended = await amendCanvasProposal(port, 'owner', {
      proposalId: IDS[2],
      instanceId: proposed.proposal.preview.sessions[0]!.exercises[0]!.instanceId,
      sets: 8,
      expectedWrite: proposed.readback.write,
    });
    expect(amended.kind).toBe('unsupported_or_invalid_intent');
    const decided = await decideCanvasProposal(port, 'owner', {
      requestId: IDS[3],
      proposalId: IDS[2],
      decision: 'apply',
      expectedWrite: proposed.readback.write,
      now: NOW,
    });
    expect(decided.kind).toBe('decided');
    expect(decided.readback.weeklyTotals).toEqual(before.weeklyTotals);
    expect(decided.readback.plan?.policy).toEqual(before.plan?.policy);
    for (const session of decided.readback.plan!.sessions) {
      const lateral = session.exercises.find((row) => row.variantId.includes('lateral_raise'));
      if (lateral) expect(session.exercises[0]).toEqual(lateral);
    }
    expect((await readCanvas(port, 'owner')).readback.execution).toEqual(
      decided.readback.execution,
    );
    const replay = await decideCanvasProposal(port, 'owner', {
      requestId: IDS[3],
      proposalId: IDS[2],
      decision: 'apply',
      expectedWrite: proposed.readback.write,
      now: NOW,
    });
    expect(replay.kind).toBe('decided');
    if (replay.kind === 'decided' && decided.kind === 'decided')
      expect(replay.receipt).toEqual(decided.receipt);
    expect(replay.readback.plan).toEqual(decided.readback.plan);
    const undo = await accept(port, { kind: 'undo' }, IDS[4], IDS[5]);
    expect(undo.readback.plan?.sessions).toEqual(before.plan?.sessions);
    expect(undo.readback.weeklyTotals).toEqual(before.weeklyTotals);
  });
  it('keeps the canvas flag off unless it is exactly true', () => {
    expect(mesocycleCanvasEnabled({} as NodeJS.ProcessEnv)).toBe(false);
    expect(mesocycleCanvasEnabled({ LYB_MESOCYCLE_CANVAS_ENABLED: '1' } as NodeJS.ProcessEnv)).toBe(
      false,
    );
    expect(
      mesocycleCanvasEnabled({ LYB_MESOCYCLE_CANVAS_ENABLED: 'true' } as NodeJS.ProcessEnv),
    ).toBe(true);
    expect(
      mesocycleCanvasFixtureEnabled({ LYB_MESOCYCLE_CANVAS_FIXTURE: 'true' } as NodeJS.ProcessEnv),
    ).toBe(false);
    expect(
      mesocycleCanvasApiEnabled({ LYB_MESOCYCLE_CANVAS_ENABLED: 'true' } as NodeJS.ProcessEnv),
    ).toBe(false);
    expect(
      mesocycleCanvasApiEnabled({
        LYB_MESOCYCLE_CANVAS_ENABLED: 'true',
        LYB_HYPERTROPHY_COACH_API_ENABLED: 'true',
      } as NodeJS.ProcessEnv),
    ).toBe(true);
  });

  it('replays goal, priority, five days, split, swap, drag, reload, and undo', async () => {
    const port = memoryCanvasPort();
    const uttered = planUtteranceProposal('Build a 4-week hypertrophy plan for a full gym');
    expect(uttered).toMatchObject({
      kind: 'plan_edit',
      requiresConfirmation: true,
      applied: false,
    });
    if (uttered.kind !== 'plan_edit') throw new Error('expected a proposal');

    const draft = await accept(port, uttered.operation, IDS[0], IDS[1]);
    expect(draft.kind).toBe('decided');
    const drafted = draft.readback.plan;
    if (!drafted) throw new Error('missing draft');
    expect(days(drafted)).toEqual(['monday', 'tuesday', 'thursday', 'friday']);
    expect(exercise(drafted, 'Incline dumbbell press')?.sets).toBe(3);
    expect(lowerIds(drafted).length).toBeGreaterThan(0);
    expect(draft.readback.goals.some((goal) => goal.id === 'upper_chest')).toBe(true);
    expect(draft.readback.weeklyTotals.quads).toBeGreaterThan(0);
    expect(canvasAgrees(drafted)).toBe(true);

    const priority = await accept(
      port,
      interpretPlanUtterance('Prioritize upper chest and triceps')!,
      IDS[2],
      IDS[3],
    );
    const prioritized = priority.readback.plan;
    if (!prioritized) throw new Error('missing priority plan');
    const beforeLower = lowerIds(drafted);
    expect(lowerIds(prioritized)).toEqual(beforeLower);
    expect(exercise(prioritized, 'Incline dumbbell press')).toMatchObject({
      sets: 4,
      priority: 'priority',
      emphasis: 'upper_chest',
    });
    expect(exercise(prioritized, 'Cable triceps pressdown')?.priority).toBe('priority');
    expect(exercise(prioritized, 'Leg press')?.priority).toBe('maintenance');
    expect(exercise(prioritized, 'Leg press')?.sets).toBe(exercise(drafted, 'Leg press')?.sets);
    expect(priority.readback.goals.find((goal) => goal.id === 'upper_chest')?.role).toBe(
      'priority',
    );
    expect(priority.readback.goals.find((goal) => goal.id === 'quads')?.role).toBe('maintenance');

    const five = await accept(port, interpretPlanUtterance('five training days')!, IDS[4], IDS[5]);
    const fivePlan = five.readback.plan;
    if (!fivePlan) throw new Error('missing five-day plan');
    expect(days(fivePlan)).toEqual(['monday', 'tuesday', 'wednesday', 'thursday', 'friday']);
    expect(lowerIds(fivePlan)).toEqual(beforeLower);

    const split = await accept(
      port,
      interpretPlanUtterance('Split Wednesday into AM/PM')!,
      IDS[6],
      IDS[7],
    );
    const splitPlan = split.readback.plan;
    if (!splitPlan) throw new Error('missing split plan');
    const wednesday = splitPlan.sessions.filter((session) => session.day === 'wednesday');
    expect(wednesday.map((session) => session.slot)).toEqual(['am', 'pm']);
    expect(wednesday[0].title).toBe('Wednesday AM');
    expect(wednesday[1].title).toBe('Wednesday PM');
    expect(lowerIds(splitPlan)).toEqual(beforeLower);

    const unsupported = await proposeCanvasEdit(port, 'owner', {
      requestId: IDS[8],
      expectedWrite: split.readback.write,
      operation: {
        kind: 'swap',
        exerciseName: 'Incline dumbbell press',
        toVariantId: 'smith_incline_press',
        declareEquipment: [],
      },
      now: NOW,
    });
    expect(unsupported.kind).toBe('unsupported_equipment');
    expect(unsupported.missing).toContain('smith');
    expect((await readCanvas(port, 'owner')).readback.plan).toEqual(splitPlan);

    const swapped = await accept(
      port,
      interpretPlanUtterance('Swap incline dumbbell press for the Smith machine incline press')!,
      IDS[9],
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
    const swappedPlan = swapped.readback.plan;
    if (!swappedPlan) throw new Error('missing swap');
    const smith = exercise(swappedPlan, 'Smith machine incline press');
    expect(smith).toMatchObject({
      variantId: 'smith_incline_press',
      instanceId: exercise(splitPlan, 'Incline dumbbell press')?.instanceId,
    });
    expect(exercise(swappedPlan, 'Incline dumbbell press')).toBeUndefined();
    expect(lowerIds(swappedPlan)).toEqual(beforeLower);
    expect(swapped.readback.proposal).toBeNull();
    expect(canvasAgrees(swappedPlan)).toBe(true);
    expect(
      swapped.readback.execution.some((session) =>
        session.exercises.some((item) => item.name === smith?.name),
      ),
    ).toBe(true);

    const calf = exercise(swappedPlan, 'Standing calf raise');
    if (!calf) throw new Error('missing calf raise');
    const moved = await accept(
      port,
      { kind: 'move', instanceId: calf.instanceId, toDay: 'friday', toSlot: 'single' },
      'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    );
    const movedPlan = moved.readback.plan;
    if (!movedPlan) throw new Error('missing move');
    const movedCalf = movedPlan.sessions.find((session) =>
      session.exercises.some((item) => item.instanceId === calf.instanceId),
    );
    expect(movedCalf).toMatchObject({ day: 'friday', slot: 'single' });
    expect(
      movedPlan.sessions.some(
        (session) =>
          session.day === 'tuesday' &&
          session.exercises.some((item) => item.instanceId === calf.instanceId),
      ),
    ).toBe(false);
    expect(canvasAgrees(movedPlan)).toBe(true);

    const reloaded = await readCanvas(port, 'owner');
    expect(reloaded.readback.plan).toEqual(movedPlan);
    expect(reloaded.readback.execution).toEqual(moved.readback.execution);

    const undone = await accept(
      port,
      { kind: 'undo' },
      'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      'ffffffff-ffff-4fff-8fff-ffffffffffff',
    );
    const undonePlan = undone.readback.plan;
    if (!undonePlan) throw new Error('missing undo');
    const restored = undonePlan.sessions.find((session) =>
      session.exercises.some((item) => item.instanceId === calf.instanceId),
    );
    expect(restored).toMatchObject({ day: 'tuesday', slot: 'single' });
    expect(canvasAgrees(undonePlan)).toBe(true);
    expect(undone.readback.execution).toEqual(
      undonePlan.sessions.map((session) =>
        expect.objectContaining({ sessionId: session.id, day: session.day, slot: session.slot }),
      ),
    );
  });

  it('rejects a proposal, ignores a duplicate apply, and fails closed on a missed save', async () => {
    const port = memoryCanvasPort();
    const draft = await accept(
      port,
      interpretPlanUtterance('Build a hypertrophy plan for a full gym')!,
      IDS[0],
      IDS[1],
    );
    const baseline = draft.readback.plan;
    const proposed = await proposeCanvasEdit(port, 'owner', {
      requestId: IDS[2],
      expectedWrite: draft.readback.write,
      operation: interpretPlanUtterance('Prioritize upper chest and triceps')!,
      now: NOW,
    });
    if (proposed.kind !== 'proposed') throw new Error(proposed.kind);
    expect(proposed.readback.plan).toEqual(baseline);
    expect(proposed.readback.narration).toMatch(/not saved/i);
    expect(proposed.proposal.changes.some((change) => change.kind === 'updated')).toBe(true);

    const rejected = await decideCanvasProposal(port, 'owner', {
      requestId: IDS[3],
      proposalId: proposed.proposal.id,
      decision: 'reject',
      expectedWrite: proposed.readback.write,
      now: NOW,
    });
    expect(rejected.kind).toBe('decided');
    expect(rejected.readback.plan).toEqual(baseline);
    expect(rejected.readback.narration).toMatch(/unchanged/i);
    const duplicateReject = await decideCanvasProposal(port, 'owner', {
      requestId: IDS[3],
      proposalId: proposed.proposal.id,
      decision: 'reject',
      expectedWrite: 0,
      now: NOW,
    });
    expect(duplicateReject).toMatchObject({
      kind: 'decided',
      receipt: rejected.kind === 'decided' ? rejected.receipt : null,
    });

    const again = await proposeCanvasEdit(port, 'owner', {
      requestId: IDS[4],
      expectedWrite: rejected.readback.write,
      operation: interpretPlanUtterance('Prioritize upper chest and triceps')!,
      now: NOW,
    });
    if (again.kind !== 'proposed') throw new Error(again.kind);
    const amended = await amendCanvasProposal(port, 'owner', {
      proposalId: again.proposal.id,
      instanceId: exercise(again.proposal.preview, 'Incline dumbbell press')!.instanceId,
      sets: 6,
      expectedWrite: again.readback.write,
    });
    if (amended.kind !== 'proposed') throw new Error(amended.kind);
    const applied = await decideCanvasProposal(port, 'owner', {
      requestId: IDS[5],
      proposalId: again.proposal.id,
      decision: 'apply',
      expectedWrite: amended.readback.write,
      now: NOW,
    });
    expect(exercise(applied.readback.plan!, 'Incline dumbbell press')?.sets).toBe(6);
    const duplicate = await decideCanvasProposal(port, 'owner', {
      requestId: IDS[5],
      proposalId: again.proposal.id,
      decision: 'apply',
      expectedWrite: applied.readback.write,
      now: NOW,
    });
    expect(duplicate.kind).toBe('decided');
    expect(duplicate.readback.plan?.revision).toBe(applied.readback.plan?.revision);
    expect(exercise(duplicate.readback.plan!, 'Incline dumbbell press')?.sets).toBe(6);

    port.failNextSave();
    const missed = await proposeCanvasEdit(port, 'owner', {
      requestId: IDS[6],
      expectedWrite: applied.readback.write,
      operation: interpretPlanUtterance('five training days')!,
      now: NOW,
    });
    expect(missed.kind).toBe('missed_update');
    expect(missed.readback.plan).toEqual(applied.readback.plan);

    const stale = await proposeCanvasEdit(port, 'owner', {
      requestId: IDS[7],
      expectedWrite: applied.readback.write - 1,
      operation: interpretPlanUtterance('five training days')!,
      now: NOW,
    });
    expect(stale.kind).toBe('stale_context');
  });

  it('lets one concurrent proposal win and stale the other', async () => {
    const port = memoryCanvasPort();
    const draft = await accept(
      port,
      interpretPlanUtterance('Build a hypertrophy plan for a full gym')!,
      IDS[0],
      IDS[1],
    );
    const write = draft.readback.write;
    const [first, second] = await Promise.all([
      proposeCanvasEdit(port, 'owner', {
        requestId: IDS[2],
        expectedWrite: write,
        operation: interpretPlanUtterance('five training days')!,
        now: NOW,
      }),
      proposeCanvasEdit(port, 'owner', {
        requestId: IDS[3],
        expectedWrite: write,
        operation: interpretPlanUtterance('Prioritize upper chest and triceps')!,
        now: NOW,
      }),
    ]);
    const kinds = [first.kind, second.kind].sort();
    expect(kinds).toEqual(['proposed', 'stale_context']);
    const winner = first.kind === 'proposed' ? first : second;
    if (winner.kind !== 'proposed') throw new Error('missing winner');
    const applied = await decideCanvasProposal(port, 'owner', {
      requestId: IDS[4],
      proposalId: winner.proposal.id,
      decision: 'apply',
      expectedWrite: winner.readback.write,
      now: NOW,
    });
    expect(applied.kind).toBe('decided');
    expect(applied.readback.plan?.revision).toBe(2);
    expect(canvasAgrees(applied.readback.plan!)).toBe(true);

    const incline = exercise(applied.readback.plan!, 'Incline dumbbell press');
    const calf = exercise(applied.readback.plan!, 'Standing calf raise');
    if (!incline || !calf) throw new Error('missing draft exercises');
    const queued = await proposeCanvasEdit(port, 'owner', {
      requestId: IDS[5],
      expectedWrite: applied.readback.write,
      operation: { kind: 'edit_sets', instanceId: incline.instanceId, sets: 5 },
      now: NOW,
    });
    const other = await proposeCanvasEdit(port, 'owner', {
      requestId: IDS[6],
      expectedWrite: queued.kind === 'proposed' ? queued.readback.write : null,
      operation: { kind: 'move', instanceId: calf.instanceId, toDay: 'friday', toSlot: 'single' },
      now: NOW,
    });
    if (queued.kind !== 'proposed' || other.kind !== 'proposed')
      throw new Error('expected two open proposals');
    const firstDecision = await decideCanvasProposal(port, 'owner', {
      requestId: IDS[7],
      proposalId: queued.proposal.id,
      decision: 'apply',
      expectedWrite: other.readback.write,
      now: NOW,
    });
    expect(firstDecision.kind).toBe('decided');
    const staleDecision = await decideCanvasProposal(port, 'owner', {
      requestId: IDS[8],
      proposalId: other.proposal.id,
      decision: 'apply',
      expectedWrite: firstDecision.readback.write,
      now: NOW,
    });
    expect(staleDecision.kind).toBe('stale_context');
    expect(staleDecision.readback.plan?.revision).toBe(firstDecision.readback.plan?.revision);
  });
});
