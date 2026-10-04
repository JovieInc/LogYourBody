import {
  buildMicrocycle,
  buildSession,
  createMesoBlock,
  evaluateDeload,
  validateSetLog,
  volume_landmarks,
} from './engine';
import {
  TRAINING_CONSENT_VERSION,
  type SetLog,
  type TrainingFeedback,
  type TrainingProgramSetup,
} from './types';

const setup: TrainingProgramSetup = {
  id: 'setup-id',
  consentVersion: TRAINING_CONSENT_VERSION,
  adultConfirmed: true,
  safetyConfirmed: true,
  sessionsPerWeek: 2,
  equipment: 'dumbbells',
  startedAt: '2026-01-05T00:00:00.000Z',
};

const emptySessionLogs: SetLog[] = [];

function feedback(input: Partial<TrainingFeedback> = {}): TrainingFeedback {
  return {
    id: 'feedback-id',
    sessionId: 'session-id',
    soreness: 2,
    pump: 5,
    performance: 'stable',
    jointPain: 0,
    createdAt: '2026-01-20T00:00:00.000Z',
    ...input,
  };
}

describe('deterministic training engine', () => {
  it('steps the RIR ladder across a four-week block and resets on the next block', () => {
    expect(createMesoBlock(setup.startedAt, setup.startedAt).targetRir).toBe(4);
    expect(createMesoBlock(setup.startedAt, '2026-01-12T00:00:00.000Z').targetRir).toBe(3);
    expect(createMesoBlock(setup.startedAt, '2026-01-26T00:00:00.000Z').targetRir).toBe(2);
    expect(createMesoBlock(setup.startedAt, '2026-02-02T00:00:00.000Z')).toMatchObject({
      id: 'block-2',
      currentWeek: 1,
      targetRir: 4,
    });
  });

  it('builds stable, evidence-tagged sessions and counts compound work fractionally', () => {
    const block = createMesoBlock(setup.startedAt, setup.startedAt);
    const week = buildMicrocycle({
      setup,
      block,
      sessionIds: ['session-a', 'session-b'],
      logs: emptySessionLogs,
      feedback: [],
    });

    expect(week.sessions.map((session) => session.pattern)).toEqual(['A', 'B']);
    expect(week.plannedFractionalVolume.chest).toBe(4);
    expect(week.plannedFractionalVolume.back).toBe(4);
    expect(week.plannedFractionalVolume.quads).toBe(4);
    expect(week.plannedFractionalVolume.biceps).toBe(4);
    expect(week.sessions[0]?.exercises[0]).toMatchObject({
      sets: 2,
      repRange: { min: 8, max: 12 },
      targetReps: 8,
      targetRir: 4,
      targetLoadKg: null,
      progression: 'hold',
    });
    expect(week.sessions[0]?.evidenceIds).toContain('k:81c218db');
    expect(Object.keys(volume_landmarks)).toHaveLength(10);
  });

  it('uses double progression only after every logged set reaches the top with the target RIR', () => {
    const block = createMesoBlock(setup.startedAt, setup.startedAt);
    const logs: SetLog[] = [1, 2].map((setNumber) => ({
      id: `log-${setNumber}`,
      sessionId: 'previous-session',
      exerciseId: 'goblet_squat',
      setNumber,
      reps: 12,
      loadKg: 15,
      rir: 4,
      completedAt: `2026-01-1${setNumber}T12:00:00.000Z`,
    }));
    const session = buildSession({
      setup,
      block,
      sessionId: 'next-session',
      slot: 0,
      logs,
      feedback: [],
    });
    expect(session.exercises[0]).toMatchObject({
      progression: 'increase_load',
      targetReps: 8,
      targetLoadKg: null,
      loadInstruction: expect.stringContaining('next available load increment'),
    });

    logs[1]!.rir = 1;
    const held = buildSession({
      setup,
      block,
      sessionId: 'held-session',
      slot: 0,
      logs,
      feedback: [],
    });
    expect(held.exercises[0]).toMatchObject({ progression: 'hold', targetLoadKg: 15 });

    logs[1]!.loadKg = null;
    const bodyweight = buildSession({
      setup,
      block,
      sessionId: 'bodyweight-session',
      slot: 0,
      logs,
      feedback: [],
    });
    expect(bodyweight.exercises[0]?.targetLoadKg).toBeNull();
  });

  it('does not escalate set volume because of a single good session', () => {
    const block = createMesoBlock(setup.startedAt, '2026-01-12T00:00:00.000Z');
    const logs: SetLog[] = [1, 2].map((setNumber) => ({
      id: `log-${setNumber}`,
      sessionId: 'previous-session',
      exerciseId: 'goblet_squat',
      setNumber,
      reps: 12,
      loadKg: 15,
      rir: 4,
      completedAt: `2026-01-1${setNumber}T12:00:00.000Z`,
    }));
    const session = buildSession({
      setup,
      block,
      sessionId: 'next-session',
      slot: 0,
      logs,
      feedback: [],
    });
    expect(session.exercises[0]?.sets).toBe(2);
    expect(session.exercises[0]?.targetRir).toBe(3);
  });

  it('reduces volume only after repeated decline plus high soreness, and pauses on high pain', () => {
    const decline = evaluateDeload([
      feedback({
        id: 'new',
        performance: 'down',
        soreness: 8,
        createdAt: '2026-01-21T00:00:00.000Z',
      }),
      feedback({
        id: 'old',
        performance: 'down',
        soreness: 5,
        createdAt: '2026-01-20T00:00:00.000Z',
      }),
    ]);
    expect(decline.action).toBe('reduce_volume');
    const reduced = buildSession({
      setup,
      block: createMesoBlock(setup.startedAt, setup.startedAt),
      sessionId: 'reduced-session',
      slot: 0,
      logs: [],
      feedback: [
        feedback({ performance: 'down', soreness: 8 }),
        feedback({ id: 'older', performance: 'down' }),
      ],
    });
    expect(reduced.exercises[0]?.sets).toBe(1);

    const pause = buildSession({
      setup,
      block: createMesoBlock(setup.startedAt, setup.startedAt),
      sessionId: 'pause-session',
      slot: 0,
      logs: [],
      feedback: [feedback({ jointPain: 5 })],
    });
    expect(pause.safetyStop).toBe(true);
    expect(pause.exercises).toEqual([]);
    expect(pause.explanation).toContain('Pause the affected exercise');
  });

  it('does not change the dose based on pump alone and rejects logs outside the returned session', () => {
    const session = buildSession({
      setup,
      block: createMesoBlock(setup.startedAt, setup.startedAt),
      sessionId: 'session-id',
      slot: 0,
      logs: [],
      feedback: [feedback({ pump: 0 })],
    });
    expect(session.exercises[0]?.sets).toBe(2);
    const validLog: SetLog = {
      id: 'log-id',
      sessionId: 'session-id',
      exerciseId: 'goblet_squat',
      setNumber: 1,
      reps: 10,
      loadKg: 15,
      rir: 3,
      completedAt: '2026-01-20T12:00:00.000Z',
    };
    expect(validateSetLog(validLog, session)).toBe(true);
    expect(validateSetLog({ ...validLog, sessionId: 'another-session' }, session)).toBe(false);
    expect(validateSetLog({ ...validLog, setNumber: 3 }, session)).toBe(false);
    expect(validateSetLog({ ...validLog, loadKg: 900 }, session)).toBe(false);
  });
});
