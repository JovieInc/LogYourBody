import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MesocycleCanvasBoard } from './MesocycleCanvasBoard';
import {
  createCanvasClient,
  httpCanvasClient,
  type CanvasClient,
} from '@/lib/training/mesocycle-canvas-client';
import {
  memoryCanvasPort,
  readCanvas,
  type CanvasLedgerPort,
  type PlanOperation,
} from '@/lib/training/mesocycle-canvas';

function column(name: string) {
  return screen.getByRole('region', { name });
}

function card(columnName: string, exerciseName: string) {
  const article = within(column(columnName))
    .getByRole('heading', { name: exerciseName })
    .closest('article');
  if (!article) throw new Error(exerciseName);
  return article;
}

function dropOn(card: HTMLElement, target: HTMLElement) {
  const dataTransfer = {
    data: {} as Record<string, string>,
    setData(type: string, value: string) {
      this.data[type] = value;
    },
    getData(type: string) {
      return this.data[type] ?? '';
    },
    dropEffect: 'move',
    effectAllowed: 'all',
  };
  fireEvent.dragStart(card, { dataTransfer });
  fireEvent.dragOver(target, { dataTransfer });
  fireEvent.drop(target, { dataTransfer });
}

function clientFor(port: CanvasLedgerPort): CanvasClient {
  const inner = createCanvasClient(port);
  return {
    ...inner,
    async submit(transcript: string) {
      if (transcript === 'swap incline dumbbell press without a smith machine') {
        const operation: PlanOperation = {
          kind: 'swap',
          exerciseName: 'Incline dumbbell press',
          toVariantId: 'smith_incline_press',
          declareEquipment: [],
        };
        return inner.direct(operation);
      }
      return inner.submit(transcript);
    },
  };
}

describe('mesocycle canvas board', () => {
  it('drops an old account response when the client changes', async () => {
    const a = createCanvasClient(memoryCanvasPort());
    const b = createCanvasClient(memoryCanvasPort());
    let finish!: (result: Awaited<ReturnType<CanvasClient['submit']>>) => void;
    const oldResult = await a.read();
    oldResult.readback.narration = 'Old account response';
    const newResult = await b.read();
    newResult.readback.narration = 'New account response';
    a.submit = () =>
      new Promise((resolve) => {
        finish = resolve;
      });
    b.read = async () => newResult;
    const view = render(<MesocycleCanvasBoard client={a} viewport="phone" reduceMotion />);
    fireEvent.change(screen.getByTestId('canvas-composer'), {
      target: { value: 'old account draft' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    await waitFor(() => expect(finish).toBeDefined());
    view.rerender(<MesocycleCanvasBoard client={b} viewport="phone" reduceMotion />);
    await screen.findByText('New account response');
    expect(screen.getByTestId('canvas-composer')).toHaveValue('');
    await act(async () => {
      finish(oldResult);
    });
    expect(screen.getByTestId('canvas-narration')).toHaveTextContent('New account response');
    expect(screen.queryByText('Old account response')).not.toBeInTheDocument();
  });

  it('does not invent a plan when the account client has not loaded one', async () => {
    const fetchImpl = jest.fn(
      async () =>
        new Response(
          JSON.stringify({
            kind: 'read',
            readback: {
              version: 1,
              write: null,
              generation: 0,
              plan: null,
              goals: [],
              weeklyTotals: {},
              execution: [],
              proposal: null,
              narration: '',
            },
          }),
          { status: 200, headers: { 'content-type': 'application/json' } },
        ),
    );
    render(
      <MesocycleCanvasBoard
        mode="account"
        client={httpCanvasClient(fetchImpl as typeof fetch, { subject: 'signed-in-subject' })}
        viewport="ultrawide"
      />,
    );
    await waitFor(() => expect(fetchImpl).toHaveBeenCalled());
    expect(
      screen.queryByRole('heading', { name: 'Incline dumbbell press' }),
    ).not.toBeInTheDocument();
    expect(screen.getByTestId('mesocycle-canvas')).toHaveAttribute('data-layout', 'board');
  });

  it('replays draft, review, split, swap, drag, reload, and undo on the board', async () => {
    const port = memoryCanvasPort();
    const client = clientFor(port);
    const view = render(
      <MesocycleCanvasBoard client={client} viewport="ultrawide" reduceMotion={false} />,
    );
    expect(screen.getByTestId('mesocycle-canvas')).toHaveAttribute('data-layout', 'board');
    expect(screen.getByTestId('mesocycle-canvas')).toHaveAttribute('data-motion', 'fluid');

    async function send(transcript: string) {
      fireEvent.change(screen.getByTestId('canvas-composer'), { target: { value: transcript } });
      fireEvent.click(screen.getByRole('button', { name: 'Send' }));
    }
    async function accept() {
      const button = await screen.findByRole('button', { name: 'Accept' });
      fireEvent.click(button);
      await waitFor(() =>
        expect(screen.queryByRole('button', { name: 'Accept' })).not.toBeInTheDocument(),
      );
    }

    await send('Build a 4-week hypertrophy plan for a full gym');
    expect(await screen.findByText(/not saved/i)).toBeInTheDocument();
    expect(screen.getByText(/Incline dumbbell press added/i)).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Monday' })).not.toBeInTheDocument();
    await accept();
    expect(await screen.findByRole('region', { name: 'Monday' })).toBeInTheDocument();
    expect(
      within(column('Monday')).getByRole('heading', { name: 'Incline dumbbell press' }),
    ).toBeInTheDocument();
    expect(screen.getByTestId('canvas-goals')).toHaveTextContent(/Upper chest/i);
    expect(screen.getByTestId('canvas-goals')).toHaveTextContent(/quads/i);
    expect(screen.getByTestId('canvas-execution')).toHaveTextContent('Incline dumbbell press 3x10');
    expect(
      within(column('Tuesday')).getByRole('heading', { name: 'Leg press' }),
    ).toBeInTheDocument();

    view.rerender(<MesocycleCanvasBoard client={client} viewport="phone" reduceMotion />);
    await waitFor(() =>
      expect(screen.getByTestId('mesocycle-canvas')).toHaveAttribute('data-layout', 'stack'),
    );
    expect(screen.getByTestId('mesocycle-canvas')).toHaveAttribute('data-motion', 'reduced');
    view.rerender(
      <MesocycleCanvasBoard client={client} viewport="ultrawide" reduceMotion={false} />,
    );
    await waitFor(() =>
      expect(screen.getByTestId('mesocycle-canvas')).toHaveAttribute('data-layout', 'board'),
    );

    await send('Prioritize upper chest and triceps');
    expect(await screen.findByText(/not saved/i)).toBeInTheDocument();
    expect(card('Monday', 'Incline dumbbell press')).toHaveTextContent('3 sets');
    fireEvent.click(screen.getByRole('button', { name: 'Reject' }));
    await waitFor(() =>
      expect(screen.getByTestId('canvas-narration')).toHaveTextContent(/unchanged/i),
    );
    expect(card('Monday', 'Incline dumbbell press')).toHaveTextContent('3 sets');
    expect(screen.queryByRole('button', { name: 'Accept' })).not.toBeInTheDocument();

    await send('Prioritize upper chest and triceps');
    const sets = await screen.findByRole('spinbutton', { name: 'Sets for Incline dumbbell press' });
    fireEvent.change(sets, { target: { value: '6' } });
    await waitFor(() =>
      expect(screen.getByTestId('canvas-narration')).toHaveTextContent(/6 sets/i),
    );
    await accept();
    expect(card('Monday', 'Incline dumbbell press')).toHaveTextContent('6 sets');
    expect(
      within(column('Tuesday')).getByRole('heading', { name: 'Leg press' }),
    ).toBeInTheDocument();

    await send('five training days');
    const fiveAccept = await screen.findByRole('button', { name: 'Accept' });
    fireEvent.click(fiveAccept);
    fireEvent.click(fiveAccept);
    expect(await screen.findByRole('region', { name: 'Wednesday' })).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.queryByRole('button', { name: 'Accept' })).not.toBeInTheDocument(),
    );
    const storedFive = await readCanvas(port, 'local');
    expect(
      storedFive.readback.plan?.sessions.filter((session) => session.day === 'wednesday'),
    ).toHaveLength(1);

    await send('Split Wednesday into AM/PM');
    await accept();
    expect(await screen.findByRole('region', { name: 'Wednesday AM' })).toBeInTheDocument();
    expect(screen.getByRole('region', { name: 'Wednesday PM' })).toBeInTheDocument();
    expect(screen.queryByRole('region', { name: 'Wednesday' })).not.toBeInTheDocument();

    await send('swap incline dumbbell press without a smith machine');
    await waitFor(() =>
      expect(screen.getByTestId('canvas-narration')).toHaveTextContent(/Unsupported equipment/i),
    );
    expect(
      within(column('Monday')).getByRole('heading', { name: 'Incline dumbbell press' }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole('heading', { name: 'Smith machine incline press' }),
    ).not.toBeInTheDocument();

    await send('Swap incline dumbbell press for the Smith machine incline press');
    expect(
      await screen.findByText(/replaced with Smith machine incline press/i),
    ).toBeInTheDocument();
    const replaced = within(column('Monday'))
      .getByRole('heading', { name: 'Incline dumbbell press' })
      .closest('article');
    expect(replaced).toHaveAttribute('data-change', 'replaced');
    await accept();
    expect(
      within(column('Monday')).getByRole('heading', { name: 'Smith machine incline press' }),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole('heading', { name: 'Incline dumbbell press' }),
    ).not.toBeInTheDocument();
    expect(screen.getByTestId('canvas-execution')).toHaveTextContent('Smith machine incline press');

    dropOn(card('Tuesday', 'Standing calf raise'), column('Friday'));
    expect(
      await screen.findByText(/Standing calf raise moved to friday single/i),
    ).toBeInTheDocument();
    await accept();
    expect(
      within(column('Friday')).getByRole('heading', { name: 'Standing calf raise' }),
    ).toBeInTheDocument();
    expect(
      within(column('Tuesday')).queryByRole('heading', { name: 'Standing calf raise' }),
    ).not.toBeInTheDocument();

    const moved = await readCanvas(port, 'local');
    view.unmount();
    render(
      <MesocycleCanvasBoard client={createCanvasClient(port)} viewport="phone" reduceMotion />,
    );
    expect(await screen.findByRole('region', { name: 'Friday' })).toBeInTheDocument();
    expect(
      within(column('Friday')).getByRole('heading', { name: 'Standing calf raise' }),
    ).toBeInTheDocument();
    expect(screen.getByTestId('canvas-execution')).toHaveTextContent('Standing calf raise');
    expect(screen.getByTestId('mesocycle-canvas')).toHaveAttribute('data-motion', 'reduced');
    const execution = screen.getByTestId('canvas-execution').textContent ?? '';
    for (const session of moved.readback.execution) {
      expect(execution).toContain(session.title);
      for (const item of session.exercises)
        expect(execution).toContain(`${item.name} ${item.sets}x${item.targetReps}`);
    }

    await send('undo');
    await accept();
    expect(
      within(column('Tuesday')).getByRole('heading', { name: 'Standing calf raise' }),
    ).toBeInTheDocument();
    expect(
      within(column('Friday')).queryByRole('heading', { name: 'Standing calf raise' }),
    ).not.toBeInTheDocument();
    expect(
      within(column('Tuesday')).getByRole('heading', { name: 'Leg press' }),
    ).toBeInTheDocument();

    port.failNextSave();
    await send('set Standing calf raise to 8 sets');
    await waitFor(() =>
      expect(screen.getByTestId('canvas-narration')).toHaveTextContent(/did not land/i),
    );
    expect(card('Tuesday', 'Standing calf raise')).toHaveTextContent('2 sets');
    expect(screen.queryByRole('button', { name: 'Accept' })).not.toBeInTheDocument();
    const finalRead = await readCanvas(port, 'local');
    expect(finalRead.readback.execution).toEqual(finalRead.readback.plan ? expect.any(Array) : []);
    expect(
      finalRead.readback.plan?.sessions.some((session) =>
        session.exercises.some((item) => item.name === 'Standing calf raise' && item.sets === 8),
      ),
    ).toBe(false);
  });
});
