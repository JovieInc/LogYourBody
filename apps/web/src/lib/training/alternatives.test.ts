import { EXERCISE_CATALOG, isEligibleVariant, type CatalogEquipment } from './catalog';
import { suggestAlternatives, type AlternativeReport } from './alternatives';
import type { TrainingFeedback } from './types';

const equipment = new Set<CatalogEquipment>(['dumbbells', 'adjustable_bench', 'machine']);

function observations(exerciseId: string, trunkFatigue: number): TrainingFeedback[] {
  return [1, 2].map((day) => ({
    id: `${exerciseId}-observation-${day}`,
    sessionId: `session-${day}`,
    context: { exerciseId },
    trunkFatigue,
    jointPain: 0,
    createdAt: `2026-10-0${day}T12:00:00.000Z`,
  }));
}

function report(): AlternativeReport {
  return {
    exerciseId: 'dumbbell_curl',
    feedback: [
      ...observations('dumbbell_curl', 6),
      ...observations('incline_dumbbell_curl', 0),
      ...observations('preacher_machine_curl', 0),
      ...observations('lying_dumbbell_curl', 0),
    ],
    previousSwaps: ['incline_dumbbell_curl', 'preacher_machine_curl', 'lying_dumbbell_curl'].map(
      (toVariantId) => ({ fromExerciseId: 'dumbbell_curl', toVariantId }),
    ),
  };
}

describe('back/trunk fatigue alternatives', () => {
  it('offers distinct exercise and setup trials after the first explicit fatigue report', () => {
    const input = Object.assign(report(), {
      allowTrials: true,
      previousSwaps: [],
      feedback: observations('cable_curl', 6).slice(0, 1),
      exerciseId: 'cable_curl',
    });
    const result = suggestAlternatives(input, EXERCISE_CATALOG, new Set([...equipment, 'cable']));
    expect(result.status).toBe('suggested');
    expect(result.differentExercise).toMatchObject({ reason: 'supported_exercise_trial' });
    expect(result.sameExerciseSetup).toEqual({
      variantId: 'supported_cable_curl',
      reason: 'supported_setup_trial',
    });
  });

  it.each([
    { name: 'standing curls fatigue the trunk; supported curls tolerated', patch: {} },
    {
      name: 'floor range of motion is blocked',
      patch: { excludedConcerns: ['floor_rom_blocked'] },
    },
    { name: 'a belt was requested but fatigue persists', patch: { beltRequested: true } },
  ])('$name', ({ patch }) => {
    expect(suggestAlternatives({ ...report(), ...patch }, EXERCISE_CATALOG, equipment)).toEqual({
      status: 'suggested',
      differentExercise: {
        variantId: 'preacher_machine_curl',
        reason: 'supported_exercise_previously_tolerated',
      },
      sameExerciseSetup: {
        variantId: 'incline_dumbbell_curl',
        reason: 'supported_setup_previously_tolerated',
      },
    });
  });

  it.each([
    { name: 'no feedback', feedback: [] },
    {
      name: 'one session with many reports',
      feedback: report().feedback.filter((f) => f.sessionId === 'session-1'),
    },
    {
      name: 'one fatigue session despite repeated supported tolerance',
      feedback: report().feedback.filter(
        (f) => f.context?.exerciseId !== 'dumbbell_curl' || f.sessionId === 'session-1',
      ),
    },
  ])('returns not enough evidence for $name', ({ feedback }) => {
    expect(suggestAlternatives({ ...report(), feedback }, EXERCISE_CATALOG, equipment)).toEqual({
      status: 'not_enough_evidence',
      differentExercise: null,
      sameExerciseSetup: null,
    });
  });

  it('excludes the missing station at an alternate gym even after successful swaps', () => {
    const result = suggestAlternatives(
      report(),
      EXERCISE_CATALOG,
      new Set(['dumbbells', 'adjustable_bench']),
    );
    expect(result).toMatchObject({ status: 'suggested', differentExercise: null });
    expect(result.sameExerciseSetup?.variantId).toBe('incline_dumbbell_curl');
  });

  it('offers the floor setup only when its range of motion is feasible', () => {
    const available = new Set<CatalogEquipment>(['dumbbells']);
    expect(
      suggestAlternatives(report(), EXERCISE_CATALOG, available).sameExerciseSetup?.variantId,
    ).toBe('lying_dumbbell_curl');
    expect(
      suggestAlternatives(
        { ...report(), excludedConcerns: ['floor_rom_blocked'] },
        EXERCISE_CATALOG,
        available,
      ),
    ).toMatchObject({
      status: 'no_eligible_alternative',
      sameExerciseSetup: null,
    });
  });

  it.each([
    { name: 'never applied', previousSwaps: [] },
    {
      name: 'applied from a different movement',
      previousSwaps: report().previousSwaps.map((swap) => ({
        ...swap,
        fromExerciseId: 'cable_curl',
      })),
    },
  ])('does not recommend swaps that were $name', ({ previousSwaps }) => {
    expect(
      suggestAlternatives({ ...report(), previousSwaps }, EXERCISE_CATALOG, equipment),
    ).toEqual({
      status: 'no_eligible_alternative',
      differentExercise: null,
      sameExerciseSetup: null,
    });
  });

  it.each([
    {
      name: 'one tolerated session',
      change: (f: TrainingFeedback) =>
        f.sessionId === 'session-1' ? f : { ...f, trunkFatigue: undefined },
    },
    {
      name: 'unknown tolerance',
      change: (f: TrainingFeedback) => ({ ...f, trunkFatigue: undefined }),
    },
    {
      name: 'uncertain transcript',
      change: (f: TrainingFeedback) => ({ ...f, transcriptionUncertain: true }),
    },
    {
      name: 'copied observation',
      change: (f: TrainingFeedback) => ({
        ...f,
        sourceObservationId: `${f.context?.exerciseId}-one-source`,
      }),
    },
  ])('does not infer successful tolerance from $name', ({ change }) => {
    const input = report();
    input.feedback = input.feedback.map((f) =>
      f.context?.exerciseId === input.exerciseId ? f : change(f),
    );
    const result = suggestAlternatives(input, EXERCISE_CATALOG, equipment);
    expect(result.differentExercise).toBeNull();
    expect(result.sameExerciseSetup).toBeNull();
  });

  it.each([
    { name: 'session-level', change: (f: TrainingFeedback) => ({ ...f, context: undefined }) },
    {
      name: 'all from one session',
      change: (f: TrainingFeedback) => ({ ...f, sessionId: 'one-session' }),
    },
    {
      name: 'copied across sessions',
      change: (f: TrainingFeedback) => ({ ...f, sourceObservationId: 'one-source' }),
    },
    { name: 'unknown', change: (f: TrainingFeedback) => ({ ...f, trunkFatigue: undefined }) },
    {
      name: 'historical interpretation',
      change: (f: TrainingFeedback): TrainingFeedback => ({
        ...f,
        interpretations: [{ claim: 'tolerability', timeframe: 'historical', confidence: 'high' }],
      }),
    },
  ])('does not infer repeated fatigue from $name feedback', ({ change }) => {
    const input = report();
    input.feedback = input.feedback.map((f) =>
      f.context?.exerciseId === input.exerciseId ? change(f) : f,
    );
    expect(suggestAlternatives(input, EXERCISE_CATALOG, equipment).status).toBe(
      'not_enough_evidence',
    );
  });

  it('respects corrections that retract an earlier fatigue report', () => {
    const input = report();
    const prior = input.feedback[0];
    input.feedback = [
      ...input.feedback,
      {
        ...prior,
        id: 'correction',
        trunkFatigue: 0,
        correctsObservationId: prior.id,
        createdAt: '2026-10-03T12:00:00.000Z',
      },
    ];
    expect(suggestAlternatives(input, EXERCISE_CATALOG, equipment).status).toBe(
      'not_enough_evidence',
    );
  });

  it('does not let an older successful swap override later persistent fatigue', () => {
    const input = report();
    input.feedback = [
      ...input.feedback,
      ...observations('incline_dumbbell_curl', 6).map((f, i) => ({
        ...f,
        id: `later-${i}`,
        sessionId: `later-${i}`,
        createdAt: `2026-10-0${i + 3}T12:00:00.000Z`,
      })),
    ];
    const result = suggestAlternatives(input, EXERCISE_CATALOG, equipment);
    expect(result.sameExerciseSetup?.variantId).toBe('lying_dumbbell_curl');
    expect(result.differentExercise?.variantId).toBe('preacher_machine_curl');
  });

  it('abstains on conflicting reports for the same exercise at the same time', () => {
    const input = report();
    input.feedback = [
      ...input.feedback,
      { ...input.feedback[0], id: 'conflicting', trunkFatigue: 0 },
    ];
    expect(suggestAlternatives(input, EXERCISE_CATALOG, equipment).status).toBe(
      'not_enough_evidence',
    );
  });

  it('uses explicit trunk readiness when fatigue has no numeric score', () => {
    const input = report();
    input.feedback = input.feedback.map((f) =>
      f.context?.exerciseId === input.exerciseId
        ? { ...f, trunkFatigue: undefined, supportingReadiness: { trunk: 'limited' } }
        : f,
    );
    expect(suggestAlternatives(input, EXERCISE_CATALOG, equipment).status).toBe('suggested');
  });

  it.each(['unsupported', 'wrong_muscle', 'not_reviewed', 'not_eligible'] as const)(
    'rejects a %s variant from the supplied library',
    (kind) => {
      const library = EXERCISE_CATALOG.map((v) => {
        if (v.id !== 'preacher_machine_curl') return v;
        switch (kind) {
          case 'unsupported':
            return { ...v, torsoSupport: 'unsupported' as const };
          case 'wrong_muscle':
            return { ...v, primaryMuscle: 'triceps' as const };
          case 'not_reviewed':
            return { ...v, trunkDemand: { ...v.trunkDemand, basis: 'inferred' as const } };
          case 'not_eligible':
            return { ...v, substitutionEligible: false };
        }
      });
      expect(suggestAlternatives(report(), library, equipment).differentExercise).toBeNull();
    },
  );

  it('classifies a supported cable setup by its explicit base identity', () => {
    const input: AlternativeReport = {
      exerciseId: 'cable_curl',
      feedback: [
        ...observations('cable_curl', 6),
        ...observations('supported_cable_curl', 0),
        ...observations('preacher_machine_curl', 0),
      ],
      previousSwaps: ['supported_cable_curl', 'preacher_machine_curl'].map((toVariantId) => ({
        fromExerciseId: 'cable_curl',
        toVariantId,
      })),
    };
    const result = suggestAlternatives(input, EXERCISE_CATALOG, new Set([...equipment, 'cable']));
    expect(result.sameExerciseSetup?.variantId).toBe('supported_cable_curl');
    expect(result.differentExercise?.variantId).toBe('preacher_machine_curl');
  });

  it('never removes the muscle or invents equipment when all alternatives are blocked', () => {
    const input = { ...report(), excludedConcerns: ['floor_rom_blocked'] };
    const before = JSON.stringify({ input, library: EXERCISE_CATALOG });
    expect(suggestAlternatives(input, EXERCISE_CATALOG, new Set(['dumbbells']))).toEqual({
      status: 'no_eligible_alternative',
      differentExercise: null,
      sameExerciseSetup: null,
    });
    expect(JSON.stringify({ input, library: EXERCISE_CATALOG })).toBe(before);
    expect(EXERCISE_CATALOG.find((v) => v.id === input.exerciseId)?.primaryMuscle).toBe('biceps');
  });

  it('returns the same result on repeat and when input ordering changes', () => {
    const input = report();
    const expected = suggestAlternatives(input, EXERCISE_CATALOG, equipment);
    expect(suggestAlternatives(input, EXERCISE_CATALOG, equipment)).toEqual(expected);
    expect(
      suggestAlternatives(
        {
          ...input,
          feedback: [...input.feedback].reverse(),
          previousSwaps: [...input.previousSwaps].reverse(),
        },
        [...EXERCISE_CATALOG].reverse(),
        new Set([...equipment].reverse()),
      ),
    ).toEqual(expected);
  });

  it.each([
    new Set<CatalogEquipment>(),
    new Set<CatalogEquipment>(['dumbbells']),
    new Set<CatalogEquipment>(['machine']),
    equipment,
  ])('returns only alternatives accepted by the equipment filter (%p)', (available) => {
    const result = suggestAlternatives(report(), EXERCISE_CATALOG, available);
    const options = [result.differentExercise, result.sameExerciseSetup].filter(
      (option) => option !== null,
    );
    expect(options.length).toBeLessThanOrEqual(2);
    for (const option of options) {
      const variant = EXERCISE_CATALOG.find((v) => v.id === option.variantId)!;
      expect(variant.primaryMuscle).toBe('biceps');
      expect(variant.torsoSupport).toBe('supported');
      expect(isEligibleVariant(variant, { available })).toBe(true);
    }
  });
});
