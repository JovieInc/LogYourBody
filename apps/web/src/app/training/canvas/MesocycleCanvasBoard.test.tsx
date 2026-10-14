import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { validateSetLog } from '@/lib/training/engine';
import {
  canvasReadback,
  parseJournal,
  reduceCanvas,
  type CanvasJournal,
} from '@/lib/training/mesocycle-canvas';
import {
  CANVAS_STORAGE_KEY,
  MesocycleCanvasBoard,
  type CanvasStorage,
} from './MesocycleCanvasBoard';
import { mesocycleCanvasPageGate } from './page';

const NOW = '2026-10-14T12:00:00.000Z';

function memoryStorage(initial?: string): CanvasStorage & { raw(): string | null } {
  const items = new Map<string, string>();
  if (initial !== undefined) items.set(CANVAS_STORAGE_KEY, initial);
  return {
    getItem: (key) => items.get(key) ?? null,
    setItem: (key, value) => {
      items.set(key, value);
    },
    raw: () => items.get(CANVAS_STORAGE_KEY) ?? null,
  };
}

function journalOf(storage: { raw(): string | null }): CanvasJournal {
  const parsed = parseJournal(JSON.parse(storage.raw() ?? 'null'));
  if (!parsed) throw new Error('stored journal is missing');
  return parsed;
}

function card(container: HTMLElement, instanceId: string): HTMLElement {
  const node = container.querySelector<HTMLElement>(`[data-instance-id="${instanceId}"]`);
  if (!node) throw new Error(`missing card ${instanceId}`);
  return node;
}

async function send(text: string, voice = false) {
  const field = await screen.findByLabelText('Plan message');
  fireEvent.change(field, { target: { value: text } });
  fireEvent.click(screen.getByRole('button', { name: voice ? 'Send voice' : 'Send' }));
  await screen.findByRole('button', { name: 'Accept' });
}

async function accept() {
  fireEvent.click(screen.getByRole('button', { name: 'Accept' }));
  await waitFor(() =>
    expect(screen.queryByRole('button', { name: 'Accept' })).not.toBeInTheDocument(),
  );
}

describe('mesocycle canvas board', () => {
  it('replays the plan on the canvas and fails closed when evidence is missing', async () => {
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
      reduced: false,
    };
    const storage = memoryStorage();
    const first = render(
      <MesocycleCanvasBoard storage={storage} autoDraft={false} now={NOW} reducedMotion />,
    );
    await screen.findByLabelText('Plan message');
    evidence.reduced = first.container.querySelector('[data-reduced-motion="true"]') !== null;

    await send('Build a hypertrophy plan');
    expect(screen.getByTestId('canvas-readback')).toHaveTextContent('No saved plan');
    expect(screen.getByText('Incline dumbbell press')).toBeInTheDocument();
    expect(screen.getByLabelText('Muscle goals')).toHaveTextContent('Quads');
    expect(screen.getByLabelText('Weekly totals')).toHaveTextContent('quads');
    await accept();
    const drafted = journalOf(storage);
    evidence.draft =
      canvasReadback(drafted).plan !== null &&
      screen.getByTestId('canvas-readback').textContent?.includes('Goblet squat') === true;

    await send('Prioritize upper chest and triceps');
    fireEvent.click(screen.getByRole('button', { name: 'Reject' }));
    await waitFor(() =>
      expect(screen.queryByRole('button', { name: 'Accept' })).not.toBeInTheDocument(),
    );
    const rejectedCard = card(first.container, 'ex:wed:incline_dumbbell_press');
    evidence.rejected =
      rejectedCard.getAttribute('data-priority') === 'standard' &&
      journalOf(storage).proposals.some((proposal) => proposal.status === 'rejected');

    await send('Prioritize upper chest and triceps');
    fireEvent.click(screen.getByRole('checkbox', { name: 'Prioritize upper chest' }));
    await accept();
    evidence.selective =
      card(first.container, 'ex:wed:incline_dumbbell_press').getAttribute('data-priority') ===
        'standard' &&
      card(first.container, 'ex:wed:overhead_dumbbell_triceps_extension').getAttribute(
        'data-priority',
      ) === 'priority';

    await send('Prioritize upper chest and triceps');
    await accept();
    evidence.priority =
      card(first.container, 'ex:wed:incline_dumbbell_press').getAttribute('data-sets') === '4' &&
      card(first.container, 'ex:wed:incline_dumbbell_press').getAttribute('data-priority') ===
        'priority' &&
      screen.getByLabelText('Muscle goals').textContent?.includes('Upper chest: priority') ===
        true &&
      screen.getByLabelText('Muscle goals').textContent?.includes('Quads: maintenance') === true;

    await send('Make it five training days');
    const beforeAccept = journalOf(storage);
    const sibling = reduceCanvas(
      beforeAccept,
      {
        type: 'propose',
        requestId: 'req-split-early',
        expectedGeneration: beforeAccept.generation,
        baseRevisionId: canvasReadback(beforeAccept).revisionId,
        source: 'chat',
        text: 'Split Wednesday AM/PM into stacked sessions',
      },
      NOW,
    );
    if (sibling.result.kind !== 'proposed' || !sibling.persist)
      throw new Error('sibling was not proposed');
    const splitProposal = sibling.journal.proposals[sibling.journal.proposals.length - 1];
    await accept();
    const afterFive = journalOf(storage);
    const missed = reduceCanvas(
      { ...afterFive, proposals: [...afterFive.proposals, splitProposal] },
      {
        type: 'decide',
        requestId: 'req-split-early-apply',
        proposalId: splitProposal.id,
        expectedGeneration: beforeAccept.generation,
        decision: 'apply',
        acceptedOpIds: ['split-wed'],
      },
      NOW,
    );
    const wednesday = canvasReadback(afterFive).plan?.days.find((day) => day.id === 'wed');
    evidence.fiveDays =
      canvasReadback(afterFive).plan?.days.some((day) => day.id === 'thu') === true;
    evidence.missed =
      missed.result.kind === 'stale_context' &&
      missed.persist === false &&
      wednesday?.sessions.some((session) => session.period === 'pm') !== true;
    first.unmount();
    const second = render(
      <MesocycleCanvasBoard storage={storage} autoDraft={false} now={NOW} reducedMotion />,
    );
    await screen.findByRole('region', { name: 'Thursday' });
    evidence.lowerBody = [
      'Goblet squat',
      'Dumbbell Romanian deadlift',
      'Dumbbell hip thrust',
      'Split squat',
    ].every((name) => screen.getByTestId('canvas-readback').textContent?.includes(name));

    await send('Split Wednesday AM/PM into stacked sessions');
    await accept();
    const splitDay = canvasReadback(journalOf(storage)).plan?.days.find((day) => day.id === 'wed');
    evidence.split =
      splitDay?.sessions.map((session) => session.title).join(',') === 'Wednesday AM,Wednesday PM';

    fireEvent.change(screen.getByLabelText('Plan message'), {
      target: { value: 'Swap incline dumbbell press for the Smith machine incline press' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    await screen.findByText(/Unsupported equipment: smith_machine/);
    evidence.unsupported =
      screen.getByTestId('canvas-readback').textContent?.includes('Incline dumbbell press') ===
        true && screen.queryByRole('button', { name: 'Accept' }) === null;

    await send('I have a Smith machine');
    await accept();
    await send('Swap incline dumbbell press for the Smith machine incline press', true);
    expect(screen.getByTestId('canvas-preview-source')).toHaveTextContent('voice');
    await accept();
    const swapped = journalOf(storage);
    const swapProposal = [...swapped.proposals]
      .reverse()
      .find((proposal) => proposal.source === 'voice');
    if (!swapProposal?.decision) throw new Error('voice swap was not decided');
    const duplicate = reduceCanvas(
      swapped,
      {
        type: 'decide',
        requestId: swapProposal.decision.requestId,
        proposalId: swapProposal.id,
        expectedGeneration: swapProposal.generation,
        decision: 'apply',
        acceptedOpIds: swapProposal.ops.map((op) => op.id),
      },
      NOW,
    );
    evidence.voice = swapProposal.ops[0]?.kind === 'swap_variant';
    evidence.swap =
      card(second.container, 'ex:wed:incline_dumbbell_press').textContent?.includes(
        'Smith machine incline press',
      ) === true;
    evidence.duplicate =
      duplicate.result.kind === 'decided' &&
      duplicate.result.replay &&
      duplicate.persist === false &&
      swapped.applied.filter((revision) => revision.proposalId === swapProposal.id).length === 1;

    const curl = card(second.container, 'ex:tue:dumbbell_curl');
    fireEvent.dragStart(curl);
    fireEvent.dragOver(screen.getByTestId('session-mon:day'));
    fireEvent.drop(screen.getByTestId('session-mon:day'));
    await screen.findByRole('button', { name: 'Accept' });
    fireEvent.change(screen.getByLabelText('Sets for Dumbbell curl'), { target: { value: '4' } });
    await accept();
    const moved = canvasReadback(journalOf(storage))
      .plan?.days.find((day) => day.id === 'mon')
      ?.sessions[0].exercises.find((exercise) => exercise.instanceId === 'ex:tue:dumbbell_curl');
    evidence.drag = moved?.name === 'Dumbbell curl';
    evidence.sets = moved?.sets === 4;

    second.unmount();
    const reloaded = render(
      <MesocycleCanvasBoard storage={storage} autoDraft={false} now={NOW} reducedMotion />,
    );
    await screen.findByText('Smith machine incline press');
    const readback = canvasReadback(journalOf(storage));
    const setOk = validateSetLog(
      {
        id: 'set-1',
        sessionId: readback.execution[0]?.id,
        exerciseId: readback.execution[0]?.exercises[0]?.id,
        setNumber: 1,
        reps: 10,
        loadKg: null,
        rir: 3,
        completedAt: NOW,
      },
      readback.execution[0],
    );
    evidence.persisted =
      screen.getByTestId('canvas-readback').textContent?.includes('Smith machine incline press') ===
        true &&
      screen
        .getByTestId('canvas-readback')
        .textContent?.includes('ex:tue:dumbbell_curl|Dumbbell curl|4') === true;
    evidence.execution =
      setOk &&
      readback.execution[0]?.exercises.map((exercise) => exercise.name).join('|') ===
        readback.plan?.days[0]?.sessions[0]?.exercises.map((exercise) => exercise.name).join('|');
    evidence.lowerBody =
      evidence.lowerBody &&
      ['Goblet squat', 'Dumbbell Romanian deadlift', 'Dumbbell hip thrust', 'Split squat'].every(
        (name) => screen.getByTestId('canvas-readback').textContent?.includes(name),
      );

    await send('undo');
    await accept();
    evidence.undo = !canvasReadback(journalOf(storage))
      .plan?.days.find((day) => day.id === 'mon')
      ?.sessions[0].exercises.some((exercise) => exercise.instanceId === 'ex:tue:dumbbell_curl');
    await send('redo');
    await accept();
    evidence.redo = Boolean(
      canvasReadback(journalOf(storage))
        .plan?.days.find((day) => day.id === 'mon')
        ?.sessions[0].exercises.find(
          (exercise) => exercise.instanceId === 'ex:tue:dumbbell_curl' && exercise.sets === 4,
        ),
    );
    reloaded.unmount();

    const missing = Object.entries(evidence)
      .filter(([, ok]) => !ok)
      .map(([key]) => key);
    expect(missing).toEqual([]);
  });

  it('shows a coach preview before anything is saved and refuses a corrupt journal', async () => {
    const empty = memoryStorage();
    const preview = render(<MesocycleCanvasBoard storage={empty} now={NOW} />);
    expect(await screen.findByText('Incline dumbbell press')).toBeInTheDocument();
    expect(screen.getByTestId('canvas-readback')).toHaveTextContent('No saved plan');
    preview.unmount();

    const corrupt = memoryStorage(
      JSON.stringify({ version: 1, generation: 0, head: 3, applied: [], proposals: [] }),
    );
    render(<MesocycleCanvasBoard storage={corrupt} autoDraft now={NOW} />);
    expect(await screen.findByTestId('canvas-corrupt')).toHaveTextContent('Nothing was changed');
    expect(screen.queryByText('Incline dumbbell press')).not.toBeInTheDocument();
  });

  it('pages one day at a time on the mobile layout', async () => {
    const storage = memoryStorage();
    render(<MesocycleCanvasBoard storage={storage} autoDraft={false} layout="mobile" now={NOW} />);
    await send('Build a hypertrophy plan');
    const monday = screen.getByRole('region', { name: 'Monday' });
    const tuesday = screen.getByRole('region', { name: 'Tuesday' });
    expect(monday).toHaveAttribute('data-active', 'true');
    expect(tuesday).toHaveAttribute('data-active', 'false');
    fireEvent.click(screen.getByRole('button', { name: 'Next day' }));
    expect(tuesday).toHaveAttribute('data-active', 'true');
  });

  it('keeps the page unavailable until the flag is on', () => {
    expect(mesocycleCanvasPageGate({})).toBe('not-found');
    expect(mesocycleCanvasPageGate({ LYB_MESOCYCLE_CANVAS_V1: '1' })).toBe('page');
  });

  it('fails closed unless the journal migration keeps canvas writes off the workout generation', () => {
    const sql = readFileSync(
      join(process.cwd(), 'db/migrations/20261014054500_training_canvas_journal.sql'),
      'utf8',
    );
    const write = sql.slice(
      sql.indexOf('function public.training_canvas_write'),
      sql.indexOf('function public.training_revision_command'),
    );
    expect(sql).toContain('on delete cascade');
    expect(sql).toContain(
      'delete from public.training_canvas_journals where user_subject=p_subject;',
    );
    expect(write).toContain('p_expected_generation');
    expect(write).toContain("'conflict'");
    expect(write).not.toContain('training_revision_state');
  });
});
