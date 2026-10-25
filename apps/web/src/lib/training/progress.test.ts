import { progressExplanation, reviewRepeatBlock } from './progress';

describe('training progress review', () => {
  it('does not explain hypertrophy from a pump or lower reported back fatigue', () => {
    expect(
      progressExplanation('A bigger pump means hypertrophy is up.', {
        pump: 9,
      }),
    ).toBeNull();
    expect(
      progressExplanation('Lower back fatigue shows the muscle grew.', {
        trunkFatigue: 2,
        previousTrunkFatigue: 7,
      }),
    ).toBeNull();
    expect(
      progressExplanation('The pump was high, so today changes.', {
        pump: 8,
        trunkFatigue: 2,
        previousTrunkFatigue: 6,
      }),
    ).toBeNull();
    expect(
      progressExplanation(
        'Performance has declined repeatedly with high soreness. The bounded correction is one load step down.',
        { performance: 'down', soreness: 8, pump: 9 },
      ),
    ).toMatch(/load step down/);
  });

  it('reuses an exact logged variant and expires only unrenewed temporary priorities', () => {
    const now = new Date('2026-02-08T12:00:00.000Z');
    const review = reviewRepeatBlock({
      now,
      currentBlockId: 'block-2',
      swaps: [
        {
          fromExerciseId: 'one_arm_dumbbell_row',
          toVariantId: 'chest_supported_dumbbell_row',
          blockId: 'block-1',
          sessionId: 'session-1',
        },
        {
          fromExerciseId: 'dumbbell_lateral_raise',
          toVariantId: 'dumbbell_curl',
          blockId: 'block-1',
          sessionId: 'session-1',
        },
        {
          fromExerciseId: 'goblet_squat',
          toVariantId: 'dumbbell_split_squat',
          blockId: 'block-2',
          sessionId: 'session-2',
        },
      ],
      logs: [{ sessionId: 'session-1', exerciseId: 'chest_supported_dumbbell_row' }],
      sessionBlockIds: new Map([
        ['session-1', 'block-1'],
        ['session-2', 'block-2'],
      ]),
      priorities: [
        {
          id: 'prio-upper',
          detail: 'upper chest',
          expiresAt: '2026-01-20T00:00:00.000Z',
        },
        {
          id: 'prio-kept',
          detail: 'arms',
          expiresAt: '2026-01-20T00:00:00.000Z',
          renewed: true,
        },
        {
          id: 'prio-open',
          detail: 'calves',
          expiresAt: '2026-03-01T00:00:00.000Z',
        },
      ],
    });

    expect(review.reusableVariants).toEqual([
      {
        fromExerciseId: 'one_arm_dumbbell_row',
        variantId: 'chest_supported_dumbbell_row',
        name: 'Chest-supported dumbbell row',
        sessionId: 'session-1',
        blockId: 'block-1',
      },
    ]);
    expect(review.expiredPriorities).toEqual([{ id: 'prio-upper', detail: 'upper chest' }]);
  });
});
