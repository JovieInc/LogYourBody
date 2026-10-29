import { optimizeMesocycle } from './optimizer';
import { certifyOptimization } from './optimizer-certification';
import { exerciseDemands, OPTIMIZER_RULES } from './optimizer-rules';
import { resolveMuscleIntents, sequencingContextSchema } from './sequencing';
import type { SetLog } from './types';

function proposal(body: unknown) {
  const result = optimizeMesocycle(body);
  if (result.kind !== 'proposal') throw new Error('expected proposal');
  expect(certifyOptimization(body, result.proposal)).toEqual({ ok: true });
  return result.proposal;
}

function completed(exerciseId: string, count = 2): SetLog[] {
  return Array.from({ length: count }, (_, index) => ({
    id: `${exerciseId}-${index}`,
    sessionId: 'parent',
    exerciseId,
    setNumber: index + 1,
    reps: 10,
    loadKg: 5,
    rir: 3,
    completedAt: '2026-10-14T08:00:00.000Z',
  }));
}

export function sequenceFixture(overrides: Record<string, unknown> = {}) {
  return {
    equipmentProfile: 'full_gym',
    locationId: null,
    locationPermission: 'unknown',
    stationGeography: 'unknown',
    sessions: [
      {
        id: 'parent',
        day: 'monday',
        part: 'any',
        exercises: [
          { id: 'warmup', name: 'Warm-up', primaryMuscle: 'chest', sets: 1, phase: 'warmup' },
          { id: 'incline_dumbbell_press', name: 'Incline press', primaryMuscle: 'chest', sets: 2 },
          {
            id: 'dumbbell_lateral_raise',
            name: 'Lateral raise',
            primaryMuscle: 'shoulders',
            sets: 2,
          },
        ],
      },
    ],
    sequencingContext: {
      blockId: 'first-block',
      asOf: '2026-10-14T18:00:00.000Z',
      intents: [
        {
          muscle: 'side_delts',
          intent: 'emphasize',
          scope: { kind: 'block', blockId: 'first-block' },
        },
      ],
    },
    ...overrides,
  };
}

describe('priority sequencing golden scenarios', () => {
  it('keeps warm-up ahead of side-delt specialization and generic compounds', () => {
    const result = optimizeMesocycle(sequenceFixture());
    expect(result.kind).toBe('proposal');
    if (result.kind !== 'proposal') return;
    expect(result.proposal.changes).toContainEqual({
      kind: 'reorder',
      sessionId: 'parent',
      moveExerciseId: 'dumbbell_lateral_raise',
      beforeExerciseId: 'incline_dumbbell_press',
      ruleId: 'priority_sequence_v1',
    });
  });

  it('does not force under-recovered specialization work first or change allocation', () => {
    const body = sequenceFixture();
    const result = proposal({
      ...body,
      sequencingContext: {
        ...body.sequencingContext,
        muscleReadiness: [{ sessionId: 'parent', muscle: 'side_delts', reported: 'limited' }],
      },
    });
    expect(result.changes.filter((row) => row.kind === 'reorder')).toEqual([]);
    expect(result.sequencing[0]?.conflicts).toContainEqual(
      expect.objectContaining({ code: 'priority_ineligible' }),
    );
    expect(result.tradeoff.candidateVolume).toEqual(result.tradeoff.baselineVolume);
  });

  it('distinguishes anterior and medial delts without interpreting EMG as fatigue', () => {
    const pressing = exerciseDemands(OPTIMIZER_RULES, 'incline_dumbbell_press');
    const laterals = exerciseDemands(OPTIMIZER_RULES, 'dumbbell_lateral_raise');
    expect(pressing.assisting).toContain('anterior_delts');
    expect(pressing.assisting).not.toContain('side_delts');
    expect(laterals.targets).toEqual(['side_delts']);
    expect(pressing.jointTolerability).toBe('unknown');
    expect(pressing.trunk?.level).toBe('low');
    expect(pressing).not.toHaveProperty('fatigueScore');
  });

  it('reviews grip interference before biceps priority and separates observed limitations', () => {
    const body = sequenceFixture({
      sessions: [
        {
          id: 'parent',
          day: 'monday',
          part: 'any',
          exercises: [
            { id: 'wrist_curl', name: 'Wrist curl', primaryMuscle: 'biceps', sets: 2 },
            { id: 'dumbbell_curl', name: 'Curl', primaryMuscle: 'biceps', sets: 2 },
          ],
        },
      ],
      priorityMuscles: ['biceps'],
    });
    const result = proposal({
      ...body,
      sequencingContext: {
        ...body.sequencingContext,
        limitations: [
          {
            id: 'target',
            sessionId: 'parent',
            exerciseId: 'wrist_curl',
            observedAt: '2026-10-14T07:00:00Z',
            kind: 'target_muscle',
            muscle: 'forearms',
          },
          {
            id: 'grip',
            sessionId: 'parent',
            exerciseId: 'wrist_curl',
            observedAt: '2026-10-14T07:01:00Z',
            kind: 'grip',
          },
        ],
      },
    });
    expect(result.findings.some((row) => row.code === 'possible_grip_interference')).toBe(true);
    expect(result.changes).toContainEqual(
      expect.objectContaining({
        kind: 'reorder',
        moveExerciseId: 'dumbbell_curl',
        beforeExerciseId: 'wrist_curl',
      }),
    );
    expect(result.sequencing[0]?.limitations.map((row) => row.kind)).toEqual([
      'target_muscle',
      'grip',
    ]);
  });

  it('does not add side delts to a visit without planned specialization work', () => {
    const body = sequenceFixture();
    const sessions = body.sessions.map((session) => ({
      ...session,
      exercises: session.exercises.filter((row) => row.id !== 'dumbbell_lateral_raise'),
    }));
    const result = proposal({ ...body, sessions });
    expect(result.changes.filter((row) => row.kind === 'reorder')).toEqual([]);
    expect(result.sequencing[0]?.remaining.map((row) => row.exerciseId)).not.toContain(
      'dumbbell_lateral_raise',
    );
  });

  it('continues AM delts / PM chest under one parent without duplicating completed delts', () => {
    const body = sequenceFixture({ logs: completed('dumbbell_lateral_raise') });
    const result = proposal({
      ...body,
      sequencingContext: {
        ...body.sequencingContext,
        segments: [
          {
            id: 'am',
            parentSessionId: 'parent',
            startedAt: '2026-10-14T07:00:00Z',
            status: 'completed',
          },
          {
            id: 'pm',
            parentSessionId: 'parent',
            startedAt: '2026-10-14T17:00:00Z',
            status: 'active',
          },
        ],
      },
    });
    expect(result.sequencing[0]?.remaining.map((row) => row.exerciseId)).toEqual([
      'warmup',
      'incline_dumbbell_press',
    ]);
    expect(result.sequencing[0]?.completedSetIds).toEqual(
      completed('dumbbell_lateral_raise').map((row) => row.id),
    );
    expect(result.changes.filter((row) => row.kind === 'reorder')).toEqual([]);
  });

  it('retains AM pressing demands and exact set timestamps in a later segment across dates', () => {
    const body = sequenceFixture({ logs: completed('incline_dumbbell_press') });
    const result = proposal({
      ...body,
      sequencingContext: {
        ...body.sequencingContext,
        asOf: '2026-10-15T18:00:00Z',
        segments: [
          {
            id: 'am',
            parentSessionId: 'parent',
            startedAt: '2026-10-14T07:00:00Z',
            status: 'completed',
          },
          {
            id: 'next-date',
            parentSessionId: 'parent',
            startedAt: '2026-10-15T17:00:00Z',
            status: 'active',
          },
        ],
      },
    });
    const review = result.sequencing[0]!;
    expect(review.priorDemands[0]).toMatchObject({
      completedAt: '2026-10-14T08:00:00.000Z',
      demands: { assisting: ['anterior_delts', 'triceps'] },
    });
    expect(review.remaining).toContainEqual({
      exerciseId: 'dumbbell_lateral_raise',
      setNumbers: [1, 2],
    });
    expect(review.decision.rationale).not.toMatch(/fatigue reset|recovered after/i);
  });

  it('leaves cancellation for reconciliation and never allocates completed sets again', () => {
    const logs = completed('dumbbell_lateral_raise');
    const before = JSON.stringify(logs);
    const body = sequenceFixture({ logs });
    const result = proposal({
      ...body,
      sequencingContext: {
        ...body.sequencingContext,
        segments: [
          {
            id: 'am',
            parentSessionId: 'parent',
            startedAt: '2026-10-14T07:00:00Z',
            status: 'completed',
          },
          {
            id: 'pm',
            parentSessionId: 'parent',
            startedAt: '2026-10-14T17:00:00Z',
            status: 'canceled',
          },
        ],
      },
    });
    expect(result.sequencing[0]?.decision.exceptions).toContain(
      'unfinished_work_requires_reconciliation',
    );
    expect(result.sequencing[0]?.move).toBeNull();
    expect(JSON.stringify(logs)).toBe(before);
    expect(
      result.sequencing[0]?.remaining.some((row) => row.exerciseId === 'dumbbell_lateral_raise'),
    ).toBe(false);
  });

  it('uses concrete gym inventory and inspectable alternatives with invariant exclusions', () => {
    const body = sequenceFixture();
    body.sessions[0]!.exercises[2]!.id = 'cable_lateral_raise';
    const context = { ...body.sequencingContext, inventory: ['dumbbells', 'bodyweight'] };
    const result = proposal({ ...body, sequencingContext: context });
    expect(result.sequencing[0]?.conflicts[0]?.alternatives).toContain('dumbbell_lateral_raise');
    const blocked = proposal({
      ...body,
      sequencingContext: { ...context, excludedExerciseIds: ['dumbbell_lateral_raise'] },
    });
    expect(blocked.sequencing[0]?.conflicts[0]?.alternatives).not.toContain(
      'dumbbell_lateral_raise',
    );
    expect(blocked.changes.filter((row) => row.kind === 'reorder')).toEqual([]);
  });

  it('preserves unspecified growth goals and expires block intent to persistent intent', () => {
    const intents = [
      { muscle: 'chest', intent: 'grow', scope: { kind: 'persistent' } },
      { muscle: 'side_delts', intent: 'grow', scope: { kind: 'persistent' } },
      {
        muscle: 'side_delts',
        intent: 'emphasize',
        scope: { kind: 'block', blockId: 'first-block' },
      },
    ] as const;
    expect(resolveMuscleIntents(intents, 'first-block')).toEqual({
      chest: 'grow',
      side_delts: 'emphasize',
    });
    expect(resolveMuscleIntents(intents, 'next-block')).toEqual({
      chest: 'grow',
      side_delts: 'grow',
    });
    expect(resolveMuscleIntents(intents, 'next-block')).not.toHaveProperty('quads');
  });

  it('propagates hard exclusions into requested swaps and pairing offers', () => {
    const body = sequenceFixture({
      requestedSwaps: [
        {
          sessionId: 'parent',
          fromExerciseId: 'dumbbell_lateral_raise',
          toVariantId: 'cable_lateral_raise',
        },
      ],
    });
    const result = proposal({
      ...body,
      considerTimeSupersets: true,
      sequencingContext: {
        ...body.sequencingContext,
        excludedExerciseIds: ['cable_lateral_raise'],
      },
    });
    expect(result.changes).toContainEqual(
      expect.objectContaining({ kind: 'limitation', code: 'no_feasible_alternative' }),
    );
    expect(
      result.changes.some(
        (row) => row.kind === 'swap_variant' && row.toVariantId === 'cable_lateral_raise',
      ),
    ).toBe(false);
    const pairInput = sequenceFixture({
      sessions: [
        {
          id: 'parent',
          day: 'monday',
          part: 'any',
          exercises: [
            {
              id: 'cable_lateral_raise',
              name: 'Lateral raise',
              primaryMuscle: 'shoulders',
              sets: 2,
            },
            { id: 'standing_calf_raise', name: 'Calf raise', primaryMuscle: 'calves', sets: 2 },
          ],
        },
      ],
      stationGeography: 'colocated',
    });
    expect(proposal(pairInput).changes.some((row) => row.kind === 'offer_superset')).toBe(true);
    const excludedPair = proposal({
      ...pairInput,
      sequencingContext: {
        ...pairInput.sequencingContext,
        excludedExerciseIds: ['cable_lateral_raise'],
      },
    });
    expect(excludedPair.changes.some((row) => row.kind === 'offer_superset')).toBe(false);
  });

  it('rejects ambiguous identities and duplicate scoped intent instead of guessing', () => {
    const body = sequenceFixture();
    expect(
      optimizeMesocycle({ ...body, sessions: [...body.sessions, ...body.sessions] }).kind,
    ).toBe('invalid');
    expect(
      sequencingContextSchema.safeParse({
        ...body.sequencingContext,
        intents: [...body.sequencingContext.intents, ...body.sequencingContext.intents],
      }).success,
    ).toBe(false);
  });

  it('lets explicit regional intent override an inherited generic muscle priority', () => {
    const body = sequenceFixture({ priorityMuscles: ['shoulders'] });
    const result = proposal({
      ...body,
      sequencingContext: {
        ...body.sequencingContext,
        intents: [
          {
            muscle: 'side_delts',
            intent: 'maintain',
            scope: { kind: 'block', blockId: 'first-block' },
          },
        ],
      },
    });
    expect(result.changes.filter((row) => row.kind === 'reorder')).toEqual([]);
  });

  it('is deterministic and rejects fabricated reorder, numbers, rationale, or decision contracts', () => {
    const body = sequenceFixture();
    const original = proposal(body);
    expect(proposal(body)).toEqual(original);
    for (const mutated of [
      { ...original, changes: [] },
      { ...original, rationale: ['Do 99 sets'] },
      { ...original, sequencing: [] },
      {
        ...original,
        tradeoff: {
          ...original.tradeoff,
          candidateVolume: { ...original.tradeoff.candidateVolume, shoulders: 99 },
        },
      },
    ])
      expect(certifyOptimization(body, mutated).ok).toBe(false);
    expect(original.tradeoff.candidateVolume).toEqual(original.tradeoff.baselineVolume);
  });
});
