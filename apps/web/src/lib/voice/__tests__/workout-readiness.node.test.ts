/** @jest-environment node */

import { parseVoiceIntent } from '../intent-parser';

const currentSet = {
  exerciseId: 'bench_press',
  exerciseName: 'Bench press',
  setNumber: 2,
  reps: 10,
  loadKg: 60,
  rir: 2,
};
const context = {
  sessionId: 'session-1',
  currentSet,
  lastCompletedSet: { ...currentSet, setNumber: 1, reps: 9 },
};

describe('workout readiness commands', () => {
  it.each([
    ['still out of breath', 'breathing_limited', 2],
    ['my grip is limiting me', 'grip_limited', 2],
    ['need more rest', 'more_rest', 2],
    ['ready now', 'ready', 2],
    ['actually I am ready now', 'ready', 2],
    ['that set was unusually weak', 'unusually_weak', 1],
    ["I don't know if I'm ready", 'unknown', 2],
  ])('reviews %s against the intended set without logging it', (statement, intent, setNumber) => {
    expect(parseVoiceIntent(statement, context)).toEqual({
      kind: 'workout_feedback',
      requiresConfirmation: true,
      feedback: {
        sessionId: 'session-1',
        exerciseId: 'bench_press',
        setNumber,
        intent,
        originalStatement: statement,
      },
    });
  });

  it('does not turn negation or mixed limitations into ready', () => {
    expect(parseVoiceIntent('not ready now', context)).not.toMatchObject({
      feedback: { intent: 'ready' },
    });
    expect(parseVoiceIntent('ready now but still out of breath', context)).not.toMatchObject({
      feedback: { intent: 'ready' },
    });
  });

  it('requires set context and gives symptoms priority over readiness', () => {
    expect(parseVoiceIntent('ready now')).toEqual({
      kind: 'clarify',
      missingFields: ['current_set'],
    });
    expect(
      parseVoiceIntent('that set was unusually weak', { ...context, lastCompletedSet: undefined }),
    ).toEqual({ kind: 'clarify', missingFields: ['last_completed_set'] });
    expect(parseVoiceIntent('ready now but my shoulder hurts', context)).toMatchObject({
      kind: 'workout_action',
      requiresConfirmation: false,
      action: { kind: 'pain' },
    });
    expect(parseVoiceIntent('I feel dizzy', context)).toMatchObject({
      kind: 'workout_action',
      requiresConfirmation: false,
      action: { kind: 'pain' },
    });
  });
});
