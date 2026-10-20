import { applyPlanEditOps, layoutForPlan, sessionWithLayout } from './plan-edits';
import { buildMicrocycle, createMesoBlock } from './engine';
import { stableTrainingUuid } from './service';
import { planLayoutSchema, type PlanEditOperation } from './revision-contract';
import type { TrainingProgramSetup } from './types';

const setup: TrainingProgramSetup = {
  id: '11111111-1111-4111-8111-111111111111',
  consentVersion: 'hypertrophy-coach-v1',
  adultConfirmed: true,
  safetyConfirmed: true,
  sessionsPerWeek: 2,
  equipment: 'dumbbells',
  startedAt: '2026-10-10T12:00:00.000Z',
};

function basePlan() {
  const block = createMesoBlock(setup.startedAt, setup.startedAt);
  return buildMicrocycle({
    setup,
    block,
    logs: [],
    feedback: [],
    sessionIds: Array.from({ length: setup.sessionsPerWeek }, (_, slot) =>
      stableTrainingUuid('owner', setup.id, block.id, '1', String(slot)),
    ),
  });
}
const baseLayout = () => {
  const layout = layoutForPlan(basePlan());
  if (!layout) throw new Error('baseline layout missing');
  return layout;
};
const edit = (operations: PlanEditOperation[], base = baseLayout()) =>
  applyPlanEditOps({ base, operations, setup });

describe('typed plan-edit operations', () => {
  it('derives a canonical layout per pattern from the baseline plan', () => {
    const layout = baseLayout();
    expect(layout.A.map((e) => e.exerciseId)).toContain('goblet_squat');
    expect(layout.B.map((e) => e.exerciseId)).toContain('incline_dumbbell_press');
    expect(layout.A.every((e) => e.sets === 2)).toBe(true);
  });
  it('moves an exercise between days without dropping it', () => {
    const result = edit([
      {
        kind: 'move_exercise',
        exerciseId: 'incline_dumbbell_press',
        fromPattern: 'B',
        toPattern: 'A',
        toIndex: 1,
      },
    ]);
    if (result.kind !== 'applied') throw new Error('edit rejected');
    expect(result.layout.A[1].exerciseId).toBe('incline_dumbbell_press');
    expect(result.layout.B.map((e) => e.exerciseId)).not.toContain(
      'incline_dumbbell_press',
    );
    expect(result.diffs[0].change).toContain('Incline dumbbell press');
  });
  it('edits set counts and reorders within a day', () => {
    const result = edit([
      { kind: 'update_sets', pattern: 'A', exerciseId: 'dumbbell_curl', sets: 4 },
      { kind: 'reorder_exercise', pattern: 'A', exerciseId: 'goblet_squat', toIndex: 3 },
    ]);
    if (result.kind !== 'applied') throw new Error('edit rejected');
    expect(result.layout.A.find((e) => e.exerciseId === 'dumbbell_curl')?.sets).toBe(4);
    expect(result.layout.A[3].exerciseId).toBe('goblet_squat');
  });
  it('swaps to an eligible same-muscle variant, preserving sets', () => {
    const result = edit([
      {
        kind: 'swap_variant',
        pattern: 'B',
        exerciseId: 'incline_dumbbell_press',
        toVariantId: 'dumbbell_floor_press',
      },
    ]);
    if (result.kind !== 'applied') throw new Error('edit rejected');
    const entry = result.layout.B.find((e) => e.exerciseId === 'dumbbell_floor_press');
    expect(entry?.sets).toBe(2);
    expect(result.diffs[0].change).toBe(
      'Swapped Incline dumbbell press for Dumbbell floor press on day B',
    );
  });
  it.each([
    {
      kind: 'move_exercise',
      exerciseId: 'missing',
      fromPattern: 'A',
      toPattern: 'B',
      toIndex: 0,
    },
    {
      kind: 'move_exercise',
      exerciseId: 'goblet_squat',
      fromPattern: 'A',
      toPattern: 'B',
      toIndex: 99,
    },
    {
      kind: 'swap_variant',
      pattern: 'A',
      exerciseId: 'dumbbell_floor_press',
      toVariantId: 'machine_chest_press',
    },
    {
      kind: 'swap_variant',
      pattern: 'A',
      exerciseId: 'goblet_squat',
      toVariantId: 'dumbbell_floor_press',
    },
    {
      kind: 'swap_variant',
      pattern: 'A',
      exerciseId: 'goblet_squat',
      toVariantId: 'goblet_squat',
    },
    { kind: 'reorder_exercise', pattern: 'B', exerciseId: 'bird_dog', toIndex: 99 },
  ] as PlanEditOperation[])(
    'fails closed on non-applicable op %# without a partial edit',
    (op) => {
      const base = baseLayout();
      expect(edit([op], base)).toEqual({ kind: 'edit_not_applicable' });
      expect(baseLayout()).toEqual(base);
    },
  );
  it('never lets a remove leave a day empty or silently drop a day', () => {
    const only = planLayoutSchema.parse({
      A: [{ exerciseId: 'goblet_squat', sets: 2 }],
      B: baseLayout().B,
    });
    expect(
      edit([{ kind: 'remove_exercise', pattern: 'A', exerciseId: 'goblet_squat' }], only),
    ).toEqual({ kind: 'edit_not_applicable' });
    const trimmed = edit([
      { kind: 'remove_exercise', pattern: 'A', exerciseId: 'dead_bug' },
    ]);
    if (trimmed.kind !== 'applied') throw new Error('edit rejected');
    expect(trimmed.layout.A.map((e) => e.exerciseId)).not.toContain('dead_bug');
  });
  it('rejects a whole batch when any op is not applicable', () => {
    const result = edit([
      { kind: 'update_sets', pattern: 'A', exerciseId: 'goblet_squat', sets: 3 },
      { kind: 'move_exercise', exerciseId: 'missing', fromPattern: 'A', toPattern: 'B', toIndex: 0 },
    ]);
    expect(result).toEqual({ kind: 'edit_not_applicable' });
  });
});

describe('session rendering from a canonical layout', () => {
  it('rebuilds exercises per pattern while keeping engine-owned fields', () => {
    const edited = edit([
      {
        kind: 'move_exercise',
        exerciseId: 'incline_dumbbell_press',
        fromPattern: 'B',
        toPattern: 'A',
        toIndex: 0,
      },
      { kind: 'update_sets', pattern: 'A', exerciseId: 'goblet_squat', sets: 3 },
    ]);
    if (edited.kind !== 'applied') throw new Error('edit rejected');
    const plan = basePlan();
    const session = plan.sessions[0];
    const result = sessionWithLayout(session, edited.layout, []);
    expect(result.exercises[0].id).toBe('incline_dumbbell_press');
    expect(result.exercises.find((e) => e.id === 'goblet_squat')?.sets).toBe(3);
    expect(result.exercises[0].repRange).toEqual({ min: 8, max: 12 });
    expect(result.exercises[0].targetRir).toBe(session.exercises[0].targetRir);
    // The untouched pattern keeps its baseline contents.
    expect(sessionWithLayout(plan.sessions[1], edited.layout, [])).toEqual(plan.sessions[1]);
  });
  it('leaves a safety-stop session and an unresolvable layout untouched', () => {
    const plan = basePlan();
    const stopped = { ...plan.sessions[0], safetyStop: true, exercises: [] };
    expect(sessionWithLayout(stopped, baseLayout(), [])).toBe(stopped);
    const session = plan.sessions[0];
    const bogus = planLayoutSchema.parse({
      A: [{ exerciseId: 'no_such_variant', sets: 2 }, ...baseLayout().A.slice(1)],
      B: baseLayout().B,
    });
    expect(sessionWithLayout(session, bogus, [])).toBe(session);
  });
});
