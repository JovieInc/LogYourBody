import { useState } from 'react';
import { act, fireEvent, render, screen, within } from '@testing-library/react';
import { suggestAlternatives } from '@/lib/training/alternatives';
import { EXERCISE_CATALOG, type CatalogEquipment } from '@/lib/training/catalog';
import { evaluateDeload } from '@/lib/training/engine';
import type { DeloadState, TrainingFeedback } from '@/lib/training/types';
import { ExerciseSwapApproval } from './ExerciseSwapApproval';

const CURRENT = { id: 'dumbbell_curl', name: 'Dumbbell curl' };
const NAMES = Object.fromEntries(EXERCISE_CATALOG.map(({ id, name }) => [id, name]));
const EQUIPMENT = new Set<CatalogEquipment>(['dumbbells', 'adjustable_bench', 'machine']);

function feedback(exerciseId: string, trunkFatigue: number): TrainingFeedback[] {
  return [1, 2].map((day) => ({
    id: `${exerciseId}-${day}`,
    sessionId: `session-${day}`,
    context: { exerciseId },
    trunkFatigue,
    jointPain: 0,
    createdAt: `2026-10-0${day}T12:00:00.000Z`,
  }));
}

const observations = [
  ...feedback(CURRENT.id, 6),
  ...feedback('incline_dumbbell_curl', 0),
  ...feedback('preacher_machine_curl', 0),
];
const report = {
  exerciseId: CURRENT.id,
  feedback: observations,
  previousSwaps: ['incline_dumbbell_curl', 'preacher_machine_curl'].map((toVariantId) => ({
    fromExerciseId: CURRENT.id,
    toVariantId,
  })),
};
const suggestions = suggestAlternatives(report, EXERCISE_CATALOG, EQUIPMENT);
const policy = evaluateDeload(observations);

function review(
  persist = jest.fn<Promise<void>, [string]>().mockResolvedValue(undefined),
  overrides: Partial<Parameters<typeof ExerciseSwapApproval>[0]> = {},
) {
  function Harness() {
    const [active, setActive] = useState(CURRENT);
    return (
      <>
        <p role="status">Active exercise: {active.name}</p>
        <ExerciseSwapApproval
          enabled
          reviewId="session-3:revision-0"
          currentExercise={active}
          suggestions={suggestions}
          variantNames={NAMES}
          painPolicy={policy}
          onApprove={async (variantId) => {
            await persist(variantId);
            setActive({ id: variantId, name: NAMES[variantId] });
          }}
          {...overrides}
        />
      </>
    );
  }
  return { ...render(<Harness />), persist };
}

function choose(name: string) {
  fireEvent.click(screen.getByRole('radio', { name }));
}

describe('exercise swap approval', () => {
  it.each([
    { label: 'two candidates', equipment: EQUIPMENT, count: 2 },
    {
      label: 'one candidate at a gym without the station',
      equipment: new Set<CatalogEquipment>(['dumbbells', 'adjustable_bench']),
      count: 1,
    },
  ])(
    'reviews back/trunk fatigue with $label and saves only after approval',
    async ({ equipment, count }) => {
      let finish!: () => void;
      const persist = jest.fn<Promise<void>, [string]>().mockImplementation(
        () =>
          new Promise<void>((resolve) => {
            finish = resolve;
          }),
      );
      review(persist, { suggestions: suggestAlternatives(report, EXERCISE_CATALOG, equipment) });

      expect(screen.getAllByRole('radio')).toHaveLength(count);
      expect(screen.getByRole('button', { name: 'Approve swap' })).toBeDisabled();
      expect(screen.getByRole('status')).toHaveTextContent(`Active exercise: ${CURRENT.name}`);
      expect(persist).not.toHaveBeenCalled();

      choose(NAMES.incline_dumbbell_curl);
      expect(screen.getByRole('status')).toHaveTextContent(`Active exercise: ${CURRENT.name}`);
      expect(persist).not.toHaveBeenCalled();
      fireEvent.click(screen.getByRole('button', { name: 'Approve swap' }));
      expect(persist).toHaveBeenCalledTimes(1);
      expect(persist).toHaveBeenCalledWith('incline_dumbbell_curl');
      expect(screen.getByRole('status')).toHaveTextContent(`Active exercise: ${CURRENT.name}`);
      expect(screen.getByRole('button', { name: 'Saving swap…' })).toBeDisabled();
      expect(screen.getByRole('button', { name: 'Keep current exercise' })).toBeDisabled();
      fireEvent.click(screen.getByRole('button', { name: 'Saving swap…' }));
      expect(persist).toHaveBeenCalledTimes(1);

      await act(async () => finish());
      expect(screen.getByRole('status')).toHaveTextContent(
        `Active exercise: ${NAMES.incline_dumbbell_curl}`,
      );
      expect(screen.queryByRole('button', { name: 'Approve swap' })).not.toBeInTheDocument();
    },
  );

  it('rejects a selected alternative without calling persistence', () => {
    const onReject = jest.fn();
    const { persist } = review(undefined, { onReject });
    choose(NAMES.preacher_machine_curl);
    fireEvent.click(screen.getByRole('button', { name: 'Keep current exercise' }));

    expect(onReject).toHaveBeenCalledTimes(1);
    expect(persist).not.toHaveBeenCalled();
    expect(screen.getByRole('status')).toHaveTextContent(`Active exercise: ${CURRENT.name}`);
    expect(screen.queryByRole('radio')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Approve swap' })).not.toBeInTheDocument();
  });

  it('shows the exact pain-policy sentence and no swap actions even with candidates', () => {
    const painPolicy = evaluateDeload([
      ...observations,
      {
        ...feedback(CURRENT.id, 6)[0],
        id: 'pain',
        symptomFlags: ['pain'],
        createdAt: '2026-10-03T12:00:00.000Z',
      },
    ]);
    expect(painPolicy.action).toBe('pause_session');
    const { persist } = review(undefined, { painPolicy });

    const panel = screen.getByRole('region', { name: 'Review exercise swap' });
    expect(within(panel).getByText(painPolicy.explanation)).toBeInTheDocument();
    expect(within(panel).queryByRole('button')).not.toBeInTheDocument();
    expect(within(panel).queryByRole('radio')).not.toBeInTheDocument();
    expect(persist).not.toHaveBeenCalled();
    expect(screen.getByRole('status')).toHaveTextContent(`Active exercise: ${CURRENT.name}`);
  });

  it('preserves the current exercise on a failed save and allows an explicit retry', async () => {
    const persist = jest
      .fn<Promise<void>, [string]>()
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce(undefined);
    review(persist);
    choose(NAMES.preacher_machine_curl);
    await act(async () => fireEvent.click(screen.getByRole('button', { name: 'Approve swap' })));
    expect(screen.getByRole('alert')).toHaveTextContent(
      'The swap could not be saved. Your current exercise is unchanged.',
    );
    expect(screen.getByRole('status')).toHaveTextContent(`Active exercise: ${CURRENT.name}`);
    await act(async () => fireEvent.click(screen.getByRole('button', { name: 'Approve swap' })));
    expect(persist).toHaveBeenCalledTimes(2);
    expect(screen.getByRole('status')).toHaveTextContent(
      `Active exercise: ${NAMES.preacher_machine_curl}`,
    );
  });

  it.each(['not_enough_evidence', 'no_eligible_alternative'] as const)(
    'offers no swap for %s',
    (status) => {
      const { persist } = review(undefined, {
        suggestions: { status, differentExercise: null, sameExerciseSetup: null },
      });
      expect(screen.queryByRole('radio')).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Approve swap' })).not.toBeInTheDocument();
      expect(persist).not.toHaveBeenCalled();
    },
  );

  it('defaults off until the caller supplies its existing training gate', () => {
    review(undefined, { enabled: undefined });
    expect(screen.queryByRole('region', { name: 'Review exercise swap' })).not.toBeInTheDocument();
  });

  it('renders the selector outcome when floor ROM is blocked and the station is missing', () => {
    const blocked = suggestAlternatives(
      { ...report, excludedConcerns: ['floor_rom_blocked'] },
      EXERCISE_CATALOG,
      new Set(['dumbbells']),
    );
    const { persist } = review(undefined, {
      suggestions: blocked,
      reasonCodes: ['blocked_rom_or_clearance', 'missing_station'],
    });
    expect(screen.getByText(/floor setup is withheld/)).toBeInTheDocument();
    expect(screen.getByText(/station is hidden/)).toBeInTheDocument();
    expect(screen.queryByRole('radio')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Approve swap' })).not.toBeInTheDocument();
    expect(persist).not.toHaveBeenCalled();
  });

  it('cannot approve a selected candidate that is no longer returned', () => {
    const props = {
      enabled: true,
      reviewId: 'same-review',
      currentExercise: CURRENT,
      suggestions,
      variantNames: NAMES,
      painPolicy: policy,
      onApprove: jest.fn(),
    };
    const view = render(<ExerciseSwapApproval {...props} />);
    choose(NAMES.preacher_machine_curl);
    view.rerender(
      <ExerciseSwapApproval {...props} suggestions={{ ...suggestions, differentExercise: null }} />,
    );
    expect(
      screen.queryByRole('radio', { name: NAMES.preacher_machine_curl }),
    ).not.toBeInTheDocument();
    const approve = screen.getByRole('button', { name: 'Approve swap' });
    expect(approve).toBeDisabled();
    fireEvent.click(approve);
    expect(props.onApprove).not.toHaveBeenCalled();
  });

  it('clears a prior choice when a new review or a pause replaces the review', () => {
    const props = {
      enabled: true,
      reviewId: 'first',
      currentExercise: CURRENT,
      suggestions,
      variantNames: NAMES,
      painPolicy: policy,
      onApprove: jest.fn(),
    };
    const view = render(<ExerciseSwapApproval {...props} />);
    choose(NAMES.incline_dumbbell_curl);
    view.rerender(<ExerciseSwapApproval {...props} reviewId="second" />);
    expect(screen.getByRole('button', { name: 'Approve swap' })).toBeDisabled();
    choose(NAMES.incline_dumbbell_curl);
    const paused: DeloadState = {
      action: 'pause_session',
      explanation: 'Policy pause sentence.',
      evidenceIds: [],
    };
    view.rerender(<ExerciseSwapApproval {...props} painPolicy={paused} />);
    expect(screen.queryByRole('button', { name: 'Approve swap' })).not.toBeInTheDocument();
    view.rerender(<ExerciseSwapApproval {...props} />);
    expect(screen.getByRole('button', { name: 'Approve swap' })).toBeDisabled();
    expect(props.onApprove).not.toHaveBeenCalled();
  });

  it('locks four rendered reason strings without load, belt-clearance, or injury-prevention claims', () => {
    const { container } = review(undefined, {
      reasonCodes: ['blocked_rom_or_clearance', 'missing_station', 'belt_does_not_clear_symptoms'],
    });
    const reasons = Array.from(
      container.querySelectorAll('[data-reason-code]'),
      (element) => element.textContent,
    );
    expect([...new Set(reasons)]).toMatchInlineSnapshot(`
[
  "Support may reduce trunk demand; it does not mean zero spinal load.",
  "This floor setup is withheld because range of motion or clearance is blocked.",
  "This station is hidden because it is not available at your active gym.",
  "A belt does not clear persistent symptoms.",
]
`);
    for (const reason of reasons) expectSafeReason(reason ?? '');
  });

  it.each([
    'Support means zero spinal load.',
    'There is no spinal load.',
    'A belt clears persistent symptoms.',
    'This setup provides injury prevention.',
    'This prevents injuries.',
    'This prevents a back injury.',
  ])('rejects an unsafe reason: %s', (text) => {
    expect(() => expectSafeReason(text)).toThrow();
  });
});

function expectSafeReason(text: string) {
  const claims = text
    .replace('does not mean zero spinal load', '')
    .replace('does not clear persistent symptoms', '');
  expect(claims).not.toMatch(
    /(?:zero|no|without) spinal load|belt.*clear|injury[- ]prevention|prevent\w*.{0,30}injur/i,
  );
}
