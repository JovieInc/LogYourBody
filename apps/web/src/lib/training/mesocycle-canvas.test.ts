import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { validateSetLog } from './engine';
import { mesocycleCanvasEnabled } from '@/lib/flags/mesocycle-canvas';
import {
  canvasReadback,
  coachDraftPlan,
  createMemoryCanvasPort,
  executionQueue,
  isUpperChestExercise,
  lowerBodyPreserved,
  parseCanvasUtterance,
  parseJournal,
  persistedPlan,
  reduceCanvas,
  reviseCanvas,
  type CanvasCommand,
  type CanvasJournal,
  type CanvasPlan,
} from './mesocycle-canvas';

const NOW = '2026-10-14T12:00:00.000Z';
const SUBJECT = 'owner';

function propose(
  text: string,
  journal: CanvasJournal,
  requestId: string,
  source: 'chat' | 'voice' = 'chat',
): CanvasCommand {
  return {
    type: 'propose',
    requestId,
    expectedGeneration: journal.generation,
    baseRevisionId: canvasReadback(journal).revisionId,
    source,
    text,
  };
}

function decide(
  journal: CanvasJournal,
  proposalId: string,
  requestId: string,
  decision: 'apply' | 'reject' = 'apply',
  extra: Partial<Extract<CanvasCommand, { type: 'decide' }>> = {},
): CanvasCommand {
  return {
    type: 'decide',
    requestId,
    proposalId,
    expectedGeneration: journal.generation,
    decision,
    ...extra,
  };
}

function names(plan: CanvasPlan) {
  return plan.days.flatMap((day) =>
    day.sessions.flatMap((session) => session.exercises.map((exercise) => exercise.name)),
  );
}

function lowerNames(plan: CanvasPlan) {
  return plan.days.flatMap((day) =>
    day.sessions.flatMap((session) =>
      session.exercises
        .filter((exercise) =>
          ['quads', 'hamstrings', 'glutes', 'calves'].includes(exercise.primaryMuscle),
        )
        .map((exercise) => exercise.name),
    ),
  );
}

describe('mesocycle canvas revision service', () => {
  it('replays goal, split, swap, drag, reload, undo and fails closed on injected faults', async () => {
    const evidence: Record<string, boolean> = {
      draft: false,
      rejected: false,
      priority: false,
      selective: false,
      fiveDays: false,
      split: false,
      unsupported: false,
      duplicate: false,
      missed: false,
      swap: false,
      drag: false,
      sets: false,
      persisted: false,
      execution: false,
      undo: false,
      redo: false,
      lowerBody: false,
      voice: false,
    };
    const port = createMemoryCanvasPort();
    const goal = await reviseCanvas(
      port,
      SUBJECT,
      propose('Build a hypertrophy plan', await port.read(SUBJECT).then((j) => j!), 'req-draft'),
      NOW,
    );
    if (goal.kind !== 'proposed') throw new Error(goal.kind);
    const drafted = goal.proposal.preview;
    expect(drafted.days.map((day) => day.id)).toEqual(['mon', 'tue', 'wed', 'fri']);
    expect(names(drafted)).toContain('Incline dumbbell press');
    expect(drafted.goals.length).toBeGreaterThan(0);
    expect(drafted.weeklyTotals.quads).toBeGreaterThan(0);
    expect(drafted.weekCount).toBe(4);
    expect(canvasReadback((await port.read(SUBJECT))!).plan).toBeNull();
    const accepted = await reviseCanvas(
      port,
      SUBJECT,
      decide((await port.read(SUBJECT))!, goal.proposal.id, 'req-draft-apply'),
      NOW,
    );
    if (accepted.kind !== 'decided' || !accepted.plan) throw new Error('draft was not accepted');
    evidence.draft = lowerNames(accepted.plan).length >= 4;

    let journal = (await port.read(SUBJECT))!;
    const priorityProposal = await reviseCanvas(
      port,
      SUBJECT,
      propose('Prioritize upper chest and triceps', journal, 'req-priority'),
      NOW,
    );
    if (priorityProposal.kind !== 'proposed') throw new Error(priorityProposal.kind);
    const rejected = await reviseCanvas(
      port,
      SUBJECT,
      decide(journal, priorityProposal.proposal.id, 'req-priority-reject', 'reject'),
      NOW,
    );
    journal = (await port.read(SUBJECT))!;
    evidence.rejected =
      rejected.kind === 'decided' &&
      rejected.receipt.status === 'rejected' &&
      names(persistedPlan(journal)!).includes('Incline dumbbell press') &&
      persistedPlan(journal)!
        .days.find((day) => day.id === 'wed')!
        .sessions[0].exercises.every((exercise) => exercise.priority === 'standard');

    const priorityAgain = await reviseCanvas(
      port,
      SUBJECT,
      propose('Prioritize upper chest and triceps', journal, 'req-priority-2'),
      NOW,
    );
    if (priorityAgain.kind !== 'proposed') throw new Error(priorityAgain.kind);
    const selective = await reviseCanvas(
      port,
      SUBJECT,
      decide(journal, priorityAgain.proposal.id, 'req-priority-selective', 'apply', {
        acceptedOpIds: ['priority-triceps'],
      }),
      NOW,
    );
    journal = (await port.read(SUBJECT))!;
    const afterSelective = persistedPlan(journal)!;
    const wed = afterSelective.days.find((day) => day.id === 'wed')!;
    evidence.selective =
      selective.kind === 'decided' &&
      wed.sessions[0].exercises.find((exercise) => exercise.variantId === 'incline_dumbbell_press')
        ?.priority === 'standard' &&
      wed.sessions[0].exercises.find((exercise) => exercise.primaryMuscle === 'triceps')
        ?.priority === 'priority' &&
      lowerBodyPreserved(accepted.plan, afterSelective);

    const fullPriority = await reviseCanvas(
      port,
      SUBJECT,
      propose('Prioritize upper chest and triceps', journal, 'req-priority-3'),
      NOW,
    );
    if (fullPriority.kind !== 'proposed') throw new Error(fullPriority.kind);
    await reviseCanvas(
      port,
      SUBJECT,
      decide(journal, fullPriority.proposal.id, 'req-priority-apply'),
      NOW,
    );
    journal = (await port.read(SUBJECT))!;
    const prioritized = persistedPlan(journal)!;
    const incline = prioritized.days
      .flatMap((day) => day.sessions.flatMap((session) => session.exercises))
      .find((exercise) => exercise.variantId === 'incline_dumbbell_press')!;
    evidence.priority =
      incline.priority === 'priority' &&
      incline.sets === 4 &&
      isUpperChestExercise(incline) &&
      prioritized.goals.find((goalItem) => goalItem.id === 'upper_chest')?.role === 'priority' &&
      prioritized.goals.find((goalItem) => goalItem.id === 'quads')?.role === 'maintenance';

    const five = await reviseCanvas(
      port,
      SUBJECT,
      propose('Make it five training days', journal, 'req-five'),
      NOW,
    );
    const sibling = await reviseCanvas(
      port,
      SUBJECT,
      propose('Split Wednesday AM/PM into stacked sessions', journal, 'req-split-early'),
      NOW,
    );
    if (five.kind !== 'proposed' || sibling.kind !== 'proposed')
      throw new Error('sibling proposals');
    await reviseCanvas(port, SUBJECT, decide(journal, five.proposal.id, 'req-five-apply'), NOW);
    const missed = await reviseCanvas(
      port,
      SUBJECT,
      decide(journal, sibling.proposal.id, 'req-split-early-apply'),
      NOW,
    );
    journal = (await port.read(SUBJECT))!;
    const fivePlan = persistedPlan(journal)!;
    evidence.fiveDays = fivePlan.days.map((day) => day.id).includes('thu');
    evidence.missed =
      missed.kind === 'stale_context' &&
      !fivePlan.days
        .find((day) => day.id === 'wed')!
        .sessions.some((session) => session.period === 'pm');
    evidence.lowerBody = lowerBodyPreserved(accepted.plan, fivePlan);

    const split = await reviseCanvas(
      port,
      SUBJECT,
      propose('Split Wednesday AM/PM into stacked sessions', journal, 'req-split'),
      NOW,
    );
    if (split.kind !== 'proposed') throw new Error(split.kind);
    await reviseCanvas(port, SUBJECT, decide(journal, split.proposal.id, 'req-split-apply'), NOW);
    journal = (await port.read(SUBJECT))!;
    const wednesday = persistedPlan(journal)!.days.find((day) => day.id === 'wed')!;
    evidence.split =
      wednesday.sessions.map((session) => session.period).join(',') === 'am,pm' &&
      wednesday.sessions[0].title === 'Wednesday AM' &&
      wednesday.sessions[1].title === 'Wednesday PM';

    const unsupported = await reviseCanvas(
      port,
      SUBJECT,
      propose(
        'Swap incline dumbbell press for the Smith machine incline press',
        journal,
        'req-swap-unsupported',
      ),
      NOW,
    );
    evidence.unsupported =
      unsupported.kind === 'unsupported_equipment' &&
      unsupported.missing.includes('smith_machine') &&
      persistedPlan((await port.read(SUBJECT))!)!.days.some((day) =>
        day.sessions.some((session) =>
          session.exercises.some((exercise) => exercise.name === 'Incline dumbbell press'),
        ),
      );

    const declared = await reviseCanvas(
      port,
      SUBJECT,
      propose('I have a Smith machine', (await port.read(SUBJECT))!, 'req-declare'),
      NOW,
    );
    if (declared.kind !== 'proposed') throw new Error(declared.kind);
    journal = (await port.read(SUBJECT))!;
    await reviseCanvas(
      port,
      SUBJECT,
      decide(journal, declared.proposal.id, 'req-declare-apply'),
      NOW,
    );
    journal = (await port.read(SUBJECT))!;
    const voiceSwap = await reviseCanvas(
      port,
      SUBJECT,
      propose(
        'Swap incline dumbbell press for the Smith machine incline press',
        journal,
        'req-swap',
        'voice',
      ),
      NOW,
    );
    const chatSwap = parseCanvasUtterance(
      'Swap incline dumbbell press for the Smith machine incline press',
    );
    if (voiceSwap.kind !== 'proposed' || chatSwap.kind !== 'ops') throw new Error('swap parse');
    evidence.voice =
      voiceSwap.proposal.source === 'voice' &&
      voiceSwap.proposal.ops[0]?.kind === chatSwap.ops[0]?.kind;
    await reviseCanvas(
      port,
      SUBJECT,
      decide(journal, voiceSwap.proposal.id, 'req-swap-apply'),
      NOW,
    );
    const duplicate = await reviseCanvas(
      port,
      SUBJECT,
      decide(journal, voiceSwap.proposal.id, 'req-swap-apply'),
      NOW,
    );
    journal = (await port.read(SUBJECT))!;
    const swapped = persistedPlan(journal)!;
    const smith = swapped.days
      .flatMap((day) => day.sessions.flatMap((session) => session.exercises))
      .find((exercise) => exercise.instanceId === 'ex:wed:incline_dumbbell_press');
    evidence.swap =
      smith?.name === 'Smith machine incline press' &&
      smith.variantId === 'smith_machine_incline_press';
    evidence.duplicate =
      duplicate.kind === 'decided' &&
      duplicate.replay &&
      journal.applied.filter((revision) => revision.proposalId === voiceSwap.proposal.id).length ===
        1;

    const curl = 'ex:tue:dumbbell_curl';
    const direct = await reviseCanvas(
      port,
      SUBJECT,
      {
        type: 'propose',
        requestId: 'req-drag',
        expectedGeneration: journal.generation,
        baseRevisionId: canvasReadback(journal).revisionId,
        source: 'direct',
        ops: [
          {
            id: 'drag-curl',
            kind: 'move',
            instanceId: curl,
            toDay: 'mon',
            toSessionId: 'mon:day',
            toIndex: 0,
          },
        ],
      },
      NOW,
    );
    if (direct.kind !== 'proposed') throw new Error(direct.kind);
    expect(direct.proposal.highlights.some((highlight) => highlight.change === 'moved')).toBe(true);
    const dragged = await reviseCanvas(
      port,
      SUBJECT,
      decide(journal, direct.proposal.id, 'req-drag-apply', 'apply', {
        setEdits: [{ instanceId: curl, sets: 4 }],
      }),
      NOW,
    );
    journal = (await port.read(SUBJECT))!;
    const moved = persistedPlan(journal)!
      .days.find((day) => day.id === 'mon')!
      .sessions[0].exercises.find((exercise) => exercise.instanceId === curl);
    evidence.drag = dragged.kind === 'decided' && moved?.name === 'Dumbbell curl';
    evidence.sets = moved?.sets === 4;

    const exported = port.exportJournal(SUBJECT);
    const reloaded = createMemoryCanvasPort();
    reloaded.importJournal(SUBJECT, exported!);
    const readback = canvasReadback((await reloaded.read(SUBJECT))!);
    const queue = readback.execution;
    const firstCanvas = readback.plan!.days[0].sessions[0];
    const setOk = validateSetLog(
      {
        id: 'set-1',
        sessionId: queue[0].id,
        exerciseId: queue[0].exercises[0].id,
        setNumber: 1,
        reps: 10,
        loadKg: null,
        rir: 3,
        completedAt: NOW,
      },
      queue[0],
    );
    evidence.persisted =
      readback.plan?.days.find((day) => day.id === 'wed')?.sessions[0].exercises[0].name ===
        'Smith machine incline press' && moved?.instanceId === curl;
    evidence.execution =
      setOk &&
      queue[0].exercises.map((exercise) => exercise.name).join('|') ===
        firstCanvas.exercises.map((exercise) => exercise.name).join('|');
    evidence.lowerBody = evidence.lowerBody && lowerBodyPreserved(coachDraftPlan(), readback.plan!);

    const undo = await reviseCanvas(
      reloaded,
      SUBJECT,
      propose('undo', (await reloaded.read(SUBJECT))!, 'req-undo'),
      NOW,
    );
    if (undo.kind !== 'proposed') throw new Error(undo.kind);
    await reviseCanvas(
      reloaded,
      SUBJECT,
      decide((await reloaded.read(SUBJECT))!, undo.proposal.id, 'req-undo-apply'),
      NOW,
    );
    const undone = persistedPlan((await reloaded.read(SUBJECT))!)!;
    evidence.undo = !undone.days
      .find((day) => day.id === 'mon')!
      .sessions[0].exercises.some((exercise) => exercise.instanceId === curl);

    const redo = await reviseCanvas(
      reloaded,
      SUBJECT,
      propose('redo', (await reloaded.read(SUBJECT))!, 'req-redo'),
      NOW,
    );
    if (redo.kind !== 'proposed') throw new Error(redo.kind);
    await reviseCanvas(
      reloaded,
      SUBJECT,
      decide((await reloaded.read(SUBJECT))!, redo.proposal.id, 'req-redo-apply'),
      NOW,
    );
    evidence.redo = Boolean(
      persistedPlan((await reloaded.read(SUBJECT))!)!
        .days.find((day) => day.id === 'mon')!
        .sessions[0].exercises.find(
          (exercise) => exercise.instanceId === curl && exercise.sets === 4,
        ),
    );

    const missing = Object.entries(evidence)
      .filter(([, ok]) => !ok)
      .map(([key]) => key);
    expect(missing).toEqual([]);
  });

  it('does not let a conflicting write land a stale proposal', async () => {
    const inner = createMemoryCanvasPort();
    let blocked = false;
    const port = {
      read: inner.read,
      write: async (subject: string, generation: number, journal: CanvasJournal) => {
        if (!blocked) {
          blocked = true;
          return 'conflict' as const;
        }
        return inner.write(subject, generation, journal);
      },
    };
    const result = await reviseCanvas(
      port,
      SUBJECT,
      propose('Build a hypertrophy plan', emptySafe(await inner.read(SUBJECT)), 'req-race'),
      NOW,
    );
    expect(result.kind).toBe('stale_context');
    expect(canvasReadback(emptySafe(await inner.read(SUBJECT))).plan).toBeNull();
  });

  it('rejects an ambiguous utterance and a corrupt journal', () => {
    expect(parseCanvasUtterance('prioritize upper chest and also five training days').kind).toBe(
      'unsupported_command',
    );
    expect(
      parseJournal({ version: 1, generation: 0, head: 3, applied: [], proposals: [] }),
    ).toBeNull();
    expect(mesocycleCanvasEnabled({})).toBe(false);
    expect(mesocycleCanvasEnabled({ LYB_MESOCYCLE_CANVAS_V1: '1' })).toBe(true);
  });

  it('keeps reduced-motion fallback in the canvas stylesheet', () => {
    const css = readFileSync(
      join(process.cwd(), 'src/app/training/canvas/mesocycle-canvas.module.css'),
      'utf8',
    );
    expect(css).toContain('prefers-reduced-motion');
    expect(css).toContain('transition: none');
  });
});

function emptySafe(journal: CanvasJournal | null): CanvasJournal {
  if (!journal) throw new Error('owner_missing');
  return journal;
}
