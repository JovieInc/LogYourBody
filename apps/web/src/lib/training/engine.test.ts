import {
  buildMicrocycle,
  buildSession,
  createMesoBlock,
  evaluateDeload,
  latestFeedbackPerSession,
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

function permutations<T>(items: T[]): T[][] {
  if (items.length <= 1) return [items];
  return items.flatMap((item, index) =>
    permutations(items.filter((_, otherIndex) => otherIndex !== index)).map((rest) => [
      item,
      ...rest,
    ]),
  );
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
        sessionId: 'previous-session',
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
        feedback({ id: 'older', sessionId: 'previous-session', performance: 'down' }),
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

  it('counts legacy duplicate check-ins as one session of recovery evidence', () => {
    expect(
      evaluateDeload([
        feedback({
          id: 'retry',
          sessionId: 'one-session',
          performance: 'down',
          soreness: 8,
          createdAt: '2026-01-21T00:00:00.000Z',
        }),
        feedback({
          id: 'original',
          sessionId: 'one-session',
          performance: 'down',
          soreness: 8,
          createdAt: '2026-01-20T00:00:00.000Z',
        }),
      ]).action,
    ).toBe('none');
  });

  it('uses the latest deliberate update for each session while retaining pain safety', () => {
    const earlier = feedback({
      id: 'original',
      sessionId: 'one-session',
      performance: 'down',
      soreness: 8,
      jointPain: 5,
      createdAt: '2026-01-20T00:00:00.000Z',
    });
    const updated = feedback({
      id: 'update',
      sessionId: 'one-session',
      performance: 'stable',
      soreness: 2,
      jointPain: 0,
      createdAt: '2026-01-21T00:00:00.000Z',
    });
    expect(evaluateDeload([earlier, updated]).action).toBe('none');
    expect(evaluateDeload([updated, earlier]).action).toBe('none');
    expect(
      evaluateDeload([
        updated,
        {
          ...earlier,
          id: 'new-pain',
          createdAt: '2026-01-22T00:00:00.000Z',
        },
      ]).action,
    ).toBe('pause_session');
  });

  it.each(['same-session', 'different-session'])(
    'retains the pain stop for every ordering of tied %s check-ins',
    (painSessionId) => {
      const lowPain = feedback({ id: 'a-low-pain', sessionId: 'same-session' });
      const highPain = feedback({ id: 'z-high-pain', sessionId: painSessionId, jointPain: 4 });
      const older = feedback({
        id: 'older',
        sessionId: 'older-session',
        createdAt: '2026-01-19T00:00:00.000Z',
      });
      for (const input of permutations([lowPain, highPain, older])) {
        const original = input.map((item) => ({ ...item }));
        expect(evaluateDeload(input).action).toBe('pause_session');
        expect(latestFeedbackPerSession(input)[0]).toEqual(highPain);
        expect(input).toEqual(original);
      }
    },
  );

  it.each(['current-session', 'previous-session'])(
    'does not infer repeated decline when the %s has contradictory tied recovery scores',
    (ambiguousSessionId) => {
      const current = feedback({
        id: 'a-current',
        sessionId: 'current-session',
        performance: 'down',
        soreness: 8,
      });
      const previous = feedback({
        id: 'a-previous',
        sessionId: 'previous-session',
        performance: 'down',
        soreness: 8,
        createdAt: '2026-01-19T00:00:00.000Z',
      });
      const conflicting = {
        ...(ambiguousSessionId === current.sessionId ? current : previous),
        id: 'z-conflicting',
        performance: 'stable' as const,
      };
      for (const input of permutations([current, previous, conflicting])) {
        expect(evaluateDeload(input).action).toBe('none');
        expect(evaluateDeload(input).explanation).toContain('Conflicting check-ins');
        expect(latestFeedbackPerSession(input)).toEqual([current, previous]);
      }
    },
  );

  it('still recognizes distinct declining sessions when tied duplicates have identical scores', () => {
    const current = feedback({ id: 'a-current', performance: 'down', soreness: 8 });
    const retry = { ...current, id: 'z-retry' };
    const previous = feedback({
      id: 'previous',
      sessionId: 'previous-session',
      performance: 'down',
      createdAt: '2026-01-19T00:00:00.000Z',
    });
    for (const input of permutations([current, retry, previous])) {
      expect(evaluateDeload(input).action).toBe('reduce_volume');
      expect(latestFeedbackPerSession(input)).toEqual([current, previous]);
    }
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
