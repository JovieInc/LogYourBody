import {
  EXERCISE_CATALOG,
  catalogVariantById,
  isEligibleVariant,
  resolveAvailableEquipment,
} from './catalog';
import { ALTERNATIVE_REASONS, suggestAlternatives, type AlternativeReport } from './substitutions';
import type { TrainingFeedback } from './types';

const equipment = resolveAvailableEquipment({ profile: 'full_gym' });

function feedback(
  variantId: string,
  session: number,
  change: Partial<TrainingFeedback> = {},
): TrainingFeedback {
  const createdAt = `2026-10-${String(session).padStart(2, '0')}T12:00:00Z`;
  return {
    id: `${variantId}-${session}`,
    sessionId: `session-${session}`,
    createdAt,
    targetMuscle: 'biceps',
    trunkFatigue: variantId === 'cable_curl' ? 6 : 0,
    context: { exerciseId: variantId, rangeOfMotion: 'full' },
    ...change,
  };
}

function report(): AlternativeReport {
  return {
    variantId: 'cable_curl',
    feedback: ['cable_curl', 'preacher_machine_curl', 'supported_cable_curl'].flatMap((id) => [
      feedback(id, 1),
      feedback(id, 2),
    ]),
    successfulSwaps: ['preacher_machine_curl', 'supported_cable_curl'].map((toVariantId) => ({
      fromVariantId: 'cable_curl',
      toVariantId,
    })),
  };
}

const options = (value: ReturnType<typeof suggestAlternatives>) =>
  [value.differentExercise, value.sameExerciseSetup].filter((option) => option !== null);

describe('suggestAlternatives', () => {
  it.each([
    ['standing cable curl', report()],
    [
      'standing dumbbell curl',
      {
        variantId: 'dumbbell_curl',
        feedback: ['dumbbell_curl', 'incline_dumbbell_curl', 'lying_dumbbell_curl'].flatMap(
          (id) => [
            feedback(id, 1, { trunkFatigue: id === 'dumbbell_curl' ? 6 : 0 }),
            feedback(id, 2, { trunkFatigue: id === 'dumbbell_curl' ? 6 : 0 }),
          ],
        ),
        successfulSwaps: ['incline_dumbbell_curl', 'lying_dumbbell_curl'].map((toVariantId) => ({
          fromVariantId: 'dumbbell_curl',
          toVariantId,
        })),
      },
    ],
  ])('%s yields a supported distinct exercise and a same-exercise setup', (_name, input) => {
    const result = suggestAlternatives(input, EXERCISE_CATALOG, equipment);
    expect(result.kind).toBe('suggested');
    expect(result.differentExercise).toMatchObject({
      reason: ALTERNATIVE_REASONS.differentExercise,
    });
    expect(result.sameExerciseSetup).toMatchObject({
      exerciseId: input.variantId,
      reason: ALTERNATIVE_REASONS.sameExerciseSetup,
    });
    expect(result.differentExercise?.exerciseId).not.toBe(input.variantId);
    expect(options(result)).toHaveLength(2);
    for (const option of options(result)) {
      expect(catalogVariantById(option.variantId)).toMatchObject({
        primaryMuscle: 'biceps',
        torsoSupport: 'supported',
      });
    }
  });

  it.each([
    ['alternate gym has no machine station', ['machine'], null, 'supported_cable_curl'],
    ['alternate gym has no adjustable bench', ['adjustable_bench'], 'preacher_machine_curl', null],
    ['alternate gym has neither', ['machine', 'adjustable_bench'], null, null],
  ])('%s excludes unavailable alternatives', (_name, unavailable, different, same) => {
    const available = resolveAvailableEquipment({
      profile: 'full_gym',
      sessionUnavailable: unavailable,
    });
    const result = suggestAlternatives(report(), EXERCISE_CATALOG, available);
    expect(result.differentExercise?.variantId ?? null).toBe(different);
    expect(result.sameExerciseSetup?.variantId ?? null).toBe(same);
    for (const option of options(result)) {
      expect(isEligibleVariant(catalogVariantById(option.variantId)!, { available })).toBe(true);
    }
  });

  it.each([
    ['no feedback', []],
    [
      'one session across all variants',
      report().feedback.filter((row) => row.sessionId === 'session-1'),
    ],
    [
      'many reports from one session',
      Array.from({ length: 12 }, (_, i) => feedback('cable_curl', 1, { id: `set-${i}` })),
    ],
    [
      'only alternative feedback',
      report().feedback.filter((row) => row.context?.exerciseId !== 'cable_curl'),
    ],
    ['missing movement context', report().feedback.map((row) => ({ ...row, context: undefined }))],
    [
      'missing trunk feedback',
      report().feedback.map((row) => ({ ...row, trunkFatigue: undefined })),
    ],
    [
      'general fatigue only',
      report().feedback.map((row) => ({ ...row, trunkFatigue: undefined, generalExhaustion: 8 })),
    ],
    [
      'copied source observation',
      report().feedback.map((row) =>
        row.context?.exerciseId === 'cable_curl'
          ? { ...row, sourceObservationId: 'one-original-observation' }
          : row,
      ),
    ],
    [
      'historical interpretation',
      report().feedback.map((row) => ({
        ...row,
        interpretations: [
          {
            claim: 'tolerability' as const,
            timeframe: 'historical' as const,
            confidence: 'high' as const,
          },
        ],
      })),
    ],
    [
      'uncertain transcript',
      report().feedback.map((row) => ({ ...row, transcriptionUncertain: true })),
    ],
    ['session-level feedback', report().feedback.map((row) => ({ ...row, context: {} }))],
  ])('%s returns not enough evidence', (_name, observations) => {
    expect(
      suggestAlternatives({ ...report(), feedback: observations }, EXERCISE_CATALOG, equipment),
    ).toEqual({
      kind: 'not_enough_evidence',
      reason: ALTERNATIVE_REASONS.notEnoughEvidence,
      differentExercise: null,
      sameExerciseSetup: null,
    });
  });

  it('excludes a floor setup with reported ROM restriction and retains a distinct exercise', () => {
    const input: AlternativeReport = {
      variantId: 'dumbbell_curl',
      feedback: [1, 2].flatMap((session) => [
        feedback('dumbbell_curl', session, { trunkFatigue: 6 }),
        feedback('incline_dumbbell_curl', session),
        feedback('lying_dumbbell_curl', session, {
          context: {
            exerciseId: 'lying_dumbbell_curl',
            rangeOfMotion: 'partial',
            setup: 'floor blocks arm travel',
          },
        }),
      ]),
      successfulSwaps: ['incline_dumbbell_curl', 'lying_dumbbell_curl'].map((toVariantId) => ({
        fromVariantId: 'dumbbell_curl',
        toVariantId,
      })),
    };
    const result = suggestAlternatives(input, EXERCISE_CATALOG, equipment);
    expect(result.kind).toBe('suggested');
    expect(result.differentExercise?.variantId).toBe('incline_dumbbell_curl');
    expect(result.sameExerciseSetup).toBeNull();
  });

  it('a belt request with persistent fatigue changes neither option nor reason', () => {
    const original = report();
    const withBelt = {
      ...original,
      feedback: original.feedback.map((row) =>
        row.context?.exerciseId === 'cable_curl'
          ? {
              ...row,
              originalStatement: 'Would a belt help? Back fatigue persists.',
              context: { ...row.context, setup: 'standing, belt requested' },
            }
          : row,
      ),
    };
    expect(suggestAlternatives(withBelt, EXERCISE_CATALOG, equipment)).toEqual(
      suggestAlternatives(original, EXERCISE_CATALOG, equipment),
    );
  });

  it.each([
    ['a newer fatigued response', { trunkFatigue: 5 }],
    ['unknown fatigue', { trunkFatigue: undefined }],
    [
      'a newer ROM restriction',
      { context: { exerciseId: 'supported_cable_curl', rangeOfMotion: 'partial' as const } },
    ],
    ['unknown ROM', { context: { exerciseId: 'supported_cable_curl' } }],
    ['a pain report', { jointPain: 2 }],
  ])('%s invalidates older setup successes', (_name, change) => {
    const input = report();
    input.feedback = [...input.feedback, feedback('supported_cable_curl', 3, change)];
    const result = suggestAlternatives(input, EXERCISE_CATALOG, equipment);
    expect(result.differentExercise?.variantId).toBe('preacher_machine_curl');
    expect(result.sameExerciseSetup).toBeNull();
  });

  it('a newer recovered source session prevents recommending from older fatigue', () => {
    const input = report();
    input.feedback = [...input.feedback, feedback('cable_curl', 3, { trunkFatigue: 0 })];
    expect(suggestAlternatives(input, EXERCISE_CATALOG, equipment).kind).toBe(
      'not_enough_evidence',
    );
  });

  it('uses corrections before assessing repeated responses', () => {
    const input = report();
    input.feedback = [
      ...input.feedback,
      feedback('supported_cable_curl', 3, {
        sessionId: 'session-2',
        correctsObservationId: 'supported_cable_curl-2',
        trunkFatigue: 5,
      }),
    ];
    const result = suggestAlternatives(input, EXERCISE_CATALOG, equipment);
    expect(result.differentExercise?.variantId).toBe('preacher_machine_curl');
    expect(result.sameExerciseSetup).toBeNull();
  });

  it('uncorrected contradictory feedback within a session does not prove tolerance', () => {
    const input = report();
    input.feedback = [
      ...input.feedback,
      feedback('supported_cable_curl', 2, { id: 'contradiction', trunkFatigue: 5 }),
    ];
    expect(suggestAlternatives(input, EXERCISE_CATALOG, equipment).sameExerciseSetup).toBeNull();
  });

  it.each([
    ['no successful swaps', { successfulSwaps: [] }],
    [
      'success for another source',
      {
        successfulSwaps: [{ fromVariantId: 'barbell_curl', toVariantId: 'preacher_machine_curl' }],
      },
    ],
    ['blocked variants', { blockedVariantIds: ['preacher_machine_curl', 'supported_cable_curl'] }],
  ])('%s cannot authorize a suggestion', (_name, change) => {
    const result = suggestAlternatives({ ...report(), ...change }, EXERCISE_CATALOG, equipment);
    expect(options(result)).toEqual([]);
  });

  it('honors catalog exclusions and substitution eligibility even after successful swaps', () => {
    const library = EXERCISE_CATALOG.map((variant) => ({
      ...variant,
      ...(variant.id === 'preacher_machine_curl' ? { substitutionEligible: false } : {}),
    }));
    const input = { ...report(), excludedConcerns: ['shoulder_extension_intolerance'] };
    expect(suggestAlternatives(input, library, equipment).kind).toBe('no_feasible_alternative');
  });

  it('never offers another muscle or an unsupported variant despite successful history', () => {
    const input = report();
    input.successfulSwaps = ['cable_triceps_pressdown', 'barbell_curl'].map((toVariantId) => ({
      fromVariantId: 'cable_curl',
      toVariantId,
    }));
    input.feedback = [
      ...input.feedback,
      ...[1, 2].flatMap((session) => [
        feedback('cable_triceps_pressdown', session, { targetMuscle: 'triceps' }),
        feedback('barbell_curl', session),
      ]),
    ];
    expect(options(suggestAlternatives(input, EXERCISE_CATALOG, equipment))).toEqual([]);
  });

  it('is deterministic, caps each category at one and does not mutate inputs', () => {
    const input = report();
    input.successfulSwaps = [
      ...input.successfulSwaps,
      { fromVariantId: 'cable_curl', toVariantId: 'incline_dumbbell_curl' },
    ];
    input.feedback = [
      ...input.feedback,
      feedback('incline_dumbbell_curl', 1),
      feedback('incline_dumbbell_curl', 2),
    ];
    const before = JSON.stringify({ input, library: EXERCISE_CATALOG, equipment: [...equipment] });
    const expected = suggestAlternatives(input, EXERCISE_CATALOG, equipment);
    expect(expected.differentExercise?.variantId).toBe('incline_dumbbell_curl');
    expect(options(expected)).toHaveLength(2);
    expect(suggestAlternatives(input, EXERCISE_CATALOG, equipment)).toEqual(expected);
    expect(
      suggestAlternatives(
        {
          ...input,
          feedback: [...input.feedback].reverse(),
          successfulSwaps: [...input.successfulSwaps].reverse(),
        },
        [...EXERCISE_CATALOG].reverse(),
        new Set([...equipment].reverse()),
      ),
    ).toEqual(expected);
    expect(JSON.stringify({ input, library: EXERCISE_CATALOG, equipment: [...equipment] })).toBe(
      before,
    );
  });

  it('no available alternative leaves the original muscle exercise in the untouched library', () => {
    const library = [catalogVariantById('cable_curl')!];
    expect(suggestAlternatives(report(), library, equipment).kind).toBe('no_feasible_alternative');
    expect(library.map((variant) => variant.id)).toEqual(['cable_curl']);
    expect(
      suggestAlternatives({ ...report(), variantId: 'unknown' }, library, equipment).kind,
    ).toBe('not_enough_evidence');
  });
});
