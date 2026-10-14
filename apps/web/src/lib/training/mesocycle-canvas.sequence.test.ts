import fs from 'node:fs';
import path from 'node:path';
import {
  amendCanvasProposal,
  canvasAgrees,
  decideCanvasProposal,
  interpretPlanUtterance,
  memoryCanvasPort,
  proposeCanvasEdit,
  readCanvas,
  type CanvasCommandResult,
  type CanvasPlan,
  type PlanOperation,
} from './mesocycle-canvas';

const NOW = '2026-10-14T18:00:00.000Z';
const SUBJECT = 'canvas-sequence';
const FIXTURE = path.resolve(
  process.cwd(),
  '../ios/LogYourBody/Resources/MesocycleCanvasSequence.json',
);

type Match = {
  action: string;
  transcript?: string;
  decision?: 'apply' | 'reject';
  operationKind?: string;
  toDay?: string;
  toSlot?: string;
  declareEquipment?: string[];
  sets?: number;
  instanceId?: string;
  exerciseName?: string;
  expectedWrite: number | null;
  checkWrite: true;
};

function requestId(index: number): string {
  return `00000000-0000-4000-8000-${index.toString(16).padStart(12, '0')}`;
}

function exercise(plan: CanvasPlan | null | undefined, name: string) {
  return plan?.sessions.flatMap((session) => session.exercises).find((item) => item.name === name);
}

function publish(result: CanvasCommandResult) {
  const clone = JSON.parse(JSON.stringify(result)) as CanvasCommandResult & {
    proposal?: { preview?: unknown };
  };
  if (clone.proposal && 'preview' in clone.proposal) delete clone.proposal.preview;
  const stored = clone.readback.proposal?.proposal as { preview?: unknown } | undefined;
  if (stored && 'preview' in stored) delete stored.preview;
  return clone;
}

describe('mesocycle canvas native fixture', () => {
  it('records the goal to undo sequence from the canonical service', async () => {
    const port = memoryCanvasPort();
    const steps: Array<{ match: Match; result: ReturnType<typeof publish> }> = [];
    let sequence = 1;
    const id = () => requestId(sequence++);

    async function run(match: Match, work: () => Promise<CanvasCommandResult>) {
      const result = await work();
      steps.push({ match, result: publish(result) });
      return result;
    }

    const opened = await run({ action: 'read', expectedWrite: null, checkWrite: true }, () =>
      readCanvas(port, SUBJECT),
    );
    expect(opened.readback.plan).toBeNull();
    let write = opened.readback.write;

    const goal = 'Build a 4-week hypertrophy plan for a full gym';
    const drafted = await run(
      { action: 'submit', transcript: goal, expectedWrite: write, checkWrite: true },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: interpretPlanUtterance(goal) as PlanOperation,
          now: NOW,
        }),
    );
    expect(drafted).toMatchObject({
      kind: 'proposed',
      readback: { plan: null, narration: expect.stringMatching(/not saved/i) },
    });
    if (drafted.kind !== 'proposed') throw new Error(drafted.kind);
    write = drafted.readback.write;
    const draftApplied = await run(
      { action: 'decide', decision: 'apply', expectedWrite: write, checkWrite: true },
      () =>
        decideCanvasProposal(port, SUBJECT, {
          requestId: id(),
          proposalId: drafted.proposal.id,
          decision: 'apply',
          expectedWrite: write,
          now: NOW,
        }),
    );
    const baseline = draftApplied.readback.plan;
    if (!baseline) throw new Error('missing draft');
    expect(canvasAgrees(baseline)).toBe(true);
    const lower = baseline.sessions
      .flatMap((session) => session.exercises)
      .filter((item) => ['quads', 'hamstrings', 'glutes', 'calves'].includes(item.primaryMuscle))
      .map((item) => item.instanceId)
      .sort();
    write = draftApplied.readback.write;

    const priorityText = 'Prioritize upper chest and triceps';
    const priority = await run(
      { action: 'submit', transcript: priorityText, expectedWrite: write, checkWrite: true },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: interpretPlanUtterance(priorityText) as PlanOperation,
          now: NOW,
        }),
    );
    if (priority.kind !== 'proposed') throw new Error(priority.kind);
    expect(priority.readback.plan).toEqual(baseline);
    write = priority.readback.write;
    const rejected = await run(
      { action: 'decide', decision: 'reject', expectedWrite: write, checkWrite: true },
      () =>
        decideCanvasProposal(port, SUBJECT, {
          requestId: id(),
          proposalId: priority.proposal.id,
          decision: 'reject',
          expectedWrite: write,
          now: NOW,
        }),
    );
    expect(rejected.readback.plan).toEqual(baseline);
    expect(rejected.readback.narration).toMatch(/unchanged/i);
    write = rejected.readback.write;

    const again = await run(
      { action: 'submit', transcript: priorityText, expectedWrite: write, checkWrite: true },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: interpretPlanUtterance(priorityText) as PlanOperation,
          now: NOW,
        }),
    );
    if (again.kind !== 'proposed') throw new Error(again.kind);
    const inclineId = exercise(again.proposal.preview, 'Incline dumbbell press')?.instanceId;
    if (!inclineId) throw new Error('missing incline');
    write = again.readback.write;
    const amended = await run(
      { action: 'amend', instanceId: inclineId, sets: 6, expectedWrite: write, checkWrite: true },
      () =>
        amendCanvasProposal(port, SUBJECT, {
          proposalId: again.proposal.id,
          instanceId: inclineId,
          sets: 6,
          expectedWrite: write,
        }),
    );
    if (amended.kind !== 'proposed') throw new Error(amended.kind);
    expect(exercise(amended.proposal.preview, 'Incline dumbbell press')?.sets).toBe(6);
    write = amended.readback.write;
    const priorityApplied = await run(
      { action: 'decide', decision: 'apply', expectedWrite: write, checkWrite: true },
      () =>
        decideCanvasProposal(port, SUBJECT, {
          requestId: id(),
          proposalId: again.proposal.id,
          decision: 'apply',
          expectedWrite: write,
          now: NOW,
        }),
    );
    expect(exercise(priorityApplied.readback.plan, 'Incline dumbbell press')?.sets).toBe(6);
    const duplicate = await decideCanvasProposal(port, SUBJECT, {
      requestId: id(),
      proposalId: again.proposal.id,
      decision: 'apply',
      expectedWrite: priorityApplied.readback.write,
      now: NOW,
    });
    expect(duplicate.kind).toBe('already_decided');
    expect(duplicate.readback.plan?.revision).toBe(priorityApplied.readback.plan?.revision);
    write = priorityApplied.readback.write;

    const fiveText = 'five training days';
    const five = await run(
      { action: 'submit', transcript: fiveText, expectedWrite: write, checkWrite: true },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: interpretPlanUtterance(fiveText) as PlanOperation,
          now: NOW,
        }),
    );
    if (five.kind !== 'proposed') throw new Error(five.kind);
    write = five.readback.write;
    const fiveApplied = await run(
      { action: 'decide', decision: 'apply', expectedWrite: write, checkWrite: true },
      () =>
        decideCanvasProposal(port, SUBJECT, {
          requestId: id(),
          proposalId: five.proposal.id,
          decision: 'apply',
          expectedWrite: write,
          now: NOW,
        }),
    );
    write = fiveApplied.readback.write;

    const splitText = 'Split Wednesday into AM/PM';
    const split = await run(
      { action: 'submit', transcript: splitText, expectedWrite: write, checkWrite: true },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: interpretPlanUtterance(splitText) as PlanOperation,
          now: NOW,
        }),
    );
    if (split.kind !== 'proposed') throw new Error(split.kind);
    write = split.readback.write;
    const splitApplied = await run(
      { action: 'decide', decision: 'apply', expectedWrite: write, checkWrite: true },
      () =>
        decideCanvasProposal(port, SUBJECT, {
          requestId: id(),
          proposalId: split.proposal.id,
          decision: 'apply',
          expectedWrite: write,
          now: NOW,
        }),
    );
    const splitPlan = splitApplied.readback.plan;
    if (!splitPlan) throw new Error('missing split');
    expect(
      splitPlan.sessions
        .filter((session) => session.day === 'wednesday')
        .map((session) => session.slot),
    ).toEqual(['am', 'pm']);
    write = splitApplied.readback.write;

    const blocked = await run(
      {
        action: 'propose',
        operationKind: 'swap',
        exerciseName: 'Incline dumbbell press',
        declareEquipment: [],
        expectedWrite: write,
        checkWrite: true,
      },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: {
            kind: 'swap',
            exerciseName: 'Incline dumbbell press',
            toVariantId: 'smith_incline_press',
            declareEquipment: [],
          },
          now: NOW,
        }),
    );
    expect(blocked.kind).toBe('unsupported_equipment');
    expect(blocked.readback.plan).toEqual(splitPlan);
    expect(blocked.missing).toContain('smith');

    const swapText = 'Swap incline dumbbell press for the Smith machine incline press';
    const swapped = await run(
      { action: 'submit', transcript: swapText, expectedWrite: write, checkWrite: true },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: interpretPlanUtterance(swapText) as PlanOperation,
          now: NOW,
        }),
    );
    if (swapped.kind !== 'proposed') throw new Error(swapped.kind);
    write = swapped.readback.write;
    const swapApplied = await run(
      { action: 'decide', decision: 'apply', expectedWrite: write, checkWrite: true },
      () =>
        decideCanvasProposal(port, SUBJECT, {
          requestId: id(),
          proposalId: swapped.proposal.id,
          decision: 'apply',
          expectedWrite: write,
          now: NOW,
        }),
    );
    const swappedPlan = swapApplied.readback.plan;
    const calf = exercise(swappedPlan, 'Standing calf raise');
    if (!swappedPlan || !calf) throw new Error('missing calf');
    expect(exercise(swappedPlan, 'Smith machine incline press')?.instanceId).toBe(
      exercise(splitPlan, 'Incline dumbbell press')?.instanceId,
    );
    expect(canvasAgrees(swappedPlan)).toBe(true);
    write = swapApplied.readback.write;

    const moved = await run(
      {
        action: 'propose',
        operationKind: 'move',
        instanceId: calf.instanceId,
        toDay: 'friday',
        toSlot: 'single',
        expectedWrite: write,
        checkWrite: true,
      },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: {
            kind: 'move',
            instanceId: calf.instanceId,
            toDay: 'friday',
            toSlot: 'single',
          },
          now: NOW,
        }),
    );
    if (moved.kind !== 'proposed') throw new Error(moved.kind);
    write = moved.readback.write;
    const moveApplied = await run(
      { action: 'decide', decision: 'apply', expectedWrite: write, checkWrite: true },
      () =>
        decideCanvasProposal(port, SUBJECT, {
          requestId: id(),
          proposalId: moved.proposal.id,
          decision: 'apply',
          expectedWrite: write,
          now: NOW,
        }),
    );
    const movedPlan = moveApplied.readback.plan;
    if (!movedPlan) throw new Error('missing move');
    expect(
      movedPlan.sessions.find((session) =>
        session.exercises.some((item) => item.instanceId === calf.instanceId),
      ),
    ).toMatchObject({ day: 'friday', slot: 'single' });
    expect(canvasAgrees(movedPlan)).toBe(true);
    const reloaded = await readCanvas(port, SUBJECT);
    expect(reloaded.readback.plan).toEqual(movedPlan);
    expect(reloaded.readback.execution).toEqual(moveApplied.readback.execution);
    write = moveApplied.readback.write;

    const undoText = 'undo';
    const undo = await run(
      { action: 'submit', transcript: undoText, expectedWrite: write, checkWrite: true },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: { kind: 'undo' },
          now: NOW,
        }),
    );
    if (undo.kind !== 'proposed') throw new Error(undo.kind);
    write = undo.readback.write;
    const undone = await run(
      { action: 'decide', decision: 'apply', expectedWrite: write, checkWrite: true },
      () =>
        decideCanvasProposal(port, SUBJECT, {
          requestId: id(),
          proposalId: undo.proposal.id,
          decision: 'apply',
          expectedWrite: write,
          now: NOW,
        }),
    );
    const undonePlan = undone.readback.plan;
    if (!undonePlan) throw new Error('missing undo');
    expect(
      undonePlan.sessions.find((session) =>
        session.exercises.some((item) => item.instanceId === calf.instanceId),
      ),
    ).toMatchObject({ day: 'tuesday' });
    expect(
      undonePlan.sessions
        .flatMap((session) => session.exercises)
        .filter((item) => ['quads', 'hamstrings', 'glutes', 'calves'].includes(item.primaryMuscle))
        .map((item) => item.instanceId)
        .sort(),
    ).toEqual(lower);
    expect(canvasAgrees(undonePlan)).toBe(true);
    write = undone.readback.write;

    port.failNextSave();
    const missed = await run(
      {
        action: 'propose',
        operationKind: 'edit_sets',
        instanceId: calf.instanceId,
        sets: 8,
        expectedWrite: write,
        checkWrite: true,
      },
      () =>
        proposeCanvasEdit(port, SUBJECT, {
          requestId: id(),
          expectedWrite: write,
          operation: { kind: 'edit_sets', instanceId: calf.instanceId, sets: 8 },
          now: NOW,
        }),
    );
    expect(missed.kind).toBe('missed_update');
    expect(missed.readback.plan).toEqual(undonePlan);
    expect(missed.readback.narration).toMatch(/unchanged/i);

    const json = `${JSON.stringify(steps, null, 2)}\n`;
    if (process.env.WRITE_CANVAS_SEQUENCE === '1' || !fs.existsSync(FIXTURE)) {
      fs.mkdirSync(path.dirname(FIXTURE), { recursive: true });
      fs.writeFileSync(FIXTURE, json);
    }
    expect(JSON.parse(fs.readFileSync(FIXTURE, 'utf8'))).toEqual(JSON.parse(json));
  });
});
