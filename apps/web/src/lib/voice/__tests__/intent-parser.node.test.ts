/** @jest-environment node */

import { parseVoiceIntent, poundsToKg } from '../intent-parser';

const sessionId = '11111111-1111-4111-8111-111111111111';

const dumbbellContext = {
  sessionId,
  weightUnit: 'lbs' as const,
  exercises: [{ id: 'dumbbell_floor_press', name: 'Dumbbell floor press' }],
  currentSet: {
    exerciseId: 'dumbbell_floor_press',
    exerciseName: 'Dumbbell floor press',
    setNumber: 2,
    reps: 10,
    loadKg: 80,
    rir: 3,
    loadAccounting: 'per_hand' as const,
  },
};

describe('parseVoiceIntent colloquial load', () => {
  it('binds the twenties to the active set only with an established unit and per-hand convention', () => {
    const result = parseVoiceIntent('12 reps with the twenties, about two left', dumbbellContext);
    expect(result).toMatchObject({
      kind: 'log_set',
      proposal: {
        sessionId,
        exerciseId: 'dumbbell_floor_press',
        setNumber: 2,
        reps: 12,
        loadKg: poundsToKg(20),
        rir: 2,
      },
      heard: { reps: 12, loadValue: 20, weightUnit: 'lbs', loadKg: poundsToKg(20), rir: 2 },
    });
    expect(result.kind === 'log_set' ? result.proposal?.loadKg : undefined).not.toBe(80);
  });

  it('asks for the unit and does not keep the prescription load when the twenties have no unit', () => {
    const { weightUnit: _unit, ...withoutUnit } = dumbbellContext;
    const result = parseVoiceIntent('12 reps with the twenties, about two left', withoutUnit);
    expect(result).toEqual({ kind: 'clarify', missingFields: ['weight'] });
  });

  it('asks how a shared implement is counted instead of guessing the twenties', () => {
    const result = parseVoiceIntent('12 reps with the twenties, about two left', {
      ...dumbbellContext,
      weightUnit: 'kg',
      currentSet: { ...dumbbellContext.currentSet, loadAccounting: undefined },
    });
    expect(result).toEqual({ kind: 'clarify', missingFields: ['load_accounting'] });
  });

  it('does not treat an explicit correction as a new set or a plate-load guess', () => {
    const result = parseVoiceIntent('Actually, 10 reps, not 12', {
      ...dumbbellContext,
      lastCompletedSet: { ...dumbbellContext.currentSet, setNumber: 1, reps: 12, loadKg: 9.07 },
    });
    expect(result).toMatchObject({
      kind: 'correct_set',
      proposal: { setNumber: 1, reps: 10, loadKg: 9.07, rir: 3 },
    });
  });

  it('clarifies a colloquial total and binds a digit plate nickname per hand', () => {
    expect(
      parseVoiceIntent('12 reps with the twenties total, 2 left', {
        ...dumbbellContext,
        weightUnit: 'kg',
      }),
    ).toEqual({ kind: 'clarify', missingFields: ['load_accounting'] });
    expect(
      parseVoiceIntent('12 reps with the 20s, 2 left', { ...dumbbellContext, weightUnit: 'kg' }),
    ).toMatchObject({ kind: 'log_set', proposal: { reps: 12, loadKg: 20, rir: 2 } });
  });

  it('keeps an explicit numeric load and an unspoken load on the existing path', () => {
    expect(
      parseVoiceIntent('12 reps with 20 kg, 2 left', {
        ...dumbbellContext,
        weightUnit: 'kg',
        currentSet: { ...dumbbellContext.currentSet, loadAccounting: undefined },
      }),
    ).toMatchObject({ kind: 'log_set', proposal: { reps: 12, loadKg: 20, rir: 2 } });
    expect(parseVoiceIntent('nine reps, probably one left', dumbbellContext)).toMatchObject({
      kind: 'log_set',
      proposal: { reps: 9, loadKg: 80, rir: 1 },
    });
  });
});
