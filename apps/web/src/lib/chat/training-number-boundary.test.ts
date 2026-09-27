import type { NextWorkoutResult } from '@/lib/training/service';
import { hasUnauthorizedTrainingQuantity } from './training-number-boundary';

const engineOutput: NextWorkoutResult = {
  kind: 'workout',
  week: 1,
  weekCount: 4,
  weeklyFractionalVolume: { chest: 4 },
  session: {
    id: 'engine-session',
    week: 1,
    slot: 0,
    pattern: 'A',
    title: 'Full body A',
    safetyStop: false,
    explanation: null,
    evidenceIds: ['k:81c218db'],
    exercises: [
      {
        id: 'goblet_squat',
        name: 'Goblet squat',
        primaryMuscle: 'quads',
        muscleContribution: { quads: 1 },
        sets: 2,
        repRange: { min: 8, max: 12 },
        targetReps: 9,
        targetRir: 4,
        targetLoadKg: null,
        loadInstruction: null,
        progression: 'add_reps',
        evidenceIds: ['k:1795aef0'],
      },
    ],
  },
};

describe('hasUnauthorizedTrainingQuantity', () => {
  it('accepts set, rep, range, and effort quantities returned by the engine', () => {
    expect(hasUnauthorizedTrainingQuantity('Use 2 sets of 9 reps at 4 RIR.', engineOutput)).toBe(
      false,
    );
    expect(hasUnauthorizedTrainingQuantity('Stay within 8-12 reps.', engineOutput)).toBe(false);
  });

  it('rejects unsupported numeric and spelled-out set or rep prescriptions', () => {
    expect(hasUnauthorizedTrainingQuantity('Try 3 sets.', engineOutput)).toBe(true);
    expect(hasUnauthorizedTrainingQuantity('Try thirteen reps.', engineOutput)).toBe(true);
    expect(hasUnauthorizedTrainingQuantity('Try 3x10.', engineOutput)).toBe(true);
  });

  it('rejects load values unless an exact engine load was returned', () => {
    expect(hasUnauthorizedTrainingQuantity('Use 20 kg.', engineOutput)).toBe(true);
    expect(hasUnauthorizedTrainingQuantity('Set the load to 20.', engineOutput)).toBe(true);
    expect(hasUnauthorizedTrainingQuantity('Increase the load to 20.', engineOutput)).toBe(true);
  });

  it('rejects prescription quantities when there is no usable engine output', () => {
    expect(hasUnauthorizedTrainingQuantity('Try 2 sets of 9 reps.', null)).toBe(true);
    expect(hasUnauthorizedTrainingQuantity('Talk about recovery, not sets.', null)).toBe(false);
  });
});
