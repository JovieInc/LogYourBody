import {
  buildMicrocycle,
  buildSession,
  createMesoBlock,
  evaluateDeload,
  evaluateNextSetReadiness,
  latestFeedbackPerSession,
  progressionForExercise,
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
    expect(evaluateDeload([feedback({ pump: 10, performance: 'stable' })]).action).toBe('none');
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

  it('keeps muscle-level recovery local when evaluating deloads and progression', () => {
    const observations = [
      feedback({
        id: 'chest-current',
        sessionId: 'current-session',
        soreness: 1,
        performance: 'stable',
        muscles: { chest: { soreness: 8, performance: 'down', recovery: 'limited' } },
      }),
      feedback({
        id: 'chest-previous',
        sessionId: 'previous-session',
        createdAt: '2026-01-19T00:00:00.000Z',
        muscles: { chest: { soreness: 7, performance: 'down', recovery: 'limited' } },
      }),
    ];

    expect(evaluateDeload(observations, 'chest').action).toBe('reduce_volume');
    expect(evaluateDeload(observations, 'shoulders').action).toBe('none');

    const session = buildSession({
      setup,
      block: createMesoBlock(setup.startedAt, setup.startedAt),
      sessionId: 'scoped-session',
      slot: 0,
      logs: [],
      feedback: observations,
    });
    expect(session.exercises.find((item) => item.primaryMuscle === 'chest')?.sets).toBe(1);
    expect(session.exercises.find((item) => item.primaryMuscle === 'shoulders')?.sets).toBe(2);

    const logs: SetLog[] = [1, 2].map((setNumber) => ({
      id: `log-${setNumber}`,
      sessionId: 'previous-session',
      exerciseId: 'machine_chest_press',
      setNumber,
      reps: 12,
      loadKg: 50,
      rir: 4,
      completedAt: `2026-01-1${setNumber}T12:00:00.000Z`,
    }));
    expect(
      progressionForExercise('machine_chest_press', logs, 4, observations, 'chest').action,
    ).toBe('hold');
    expect(
      progressionForExercise('machine_chest_press', logs, 4, observations, 'shoulders').action,
    ).toBe('increase_load');
  });

  it.each([
    {
      name: 'timer expired but breathing is still limiting',
      observation: feedback({
        targetMuscle: 'shoulders',
        targetMuscleReadiness: 'ready',
        breathingReadiness: 'limited',
        context: { exerciseId: 'cable_lateral_raise', setNumber: 2, restSeconds: 180 },
      }),
      action: 'extend_rest',
    },
    {
      name: 'breathing settled but grip remains limiting',
      observation: feedback({
        targetMuscle: 'back',
        targetMuscleReadiness: 'ready',
        breathingReadiness: 'ready',
        supportingReadiness: { grip: 'limited' },
      }),
      action: 'adjust_or_skip_task',
    },
    {
      name: 'calm breathing but poor target-muscle capacity',
      observation: feedback({
        targetMuscle: 'chest',
        targetMuscleReadiness: 'limited',
        breathingReadiness: 'ready',
      }),
      action: 'adjust_or_skip_task',
    },
    {
      name: 'trunk fatigue despite a light cable load',
      observation: feedback({
        targetMuscle: 'back',
        targetMuscleReadiness: 'ready',
        breathingReadiness: 'ready',
        supportingReadiness: { trunk: 'limited' },
        trunkFatigue: 8,
        context: { exerciseId: 'seated_cable_row', setNumber: 2, loadKg: 5 },
      }),
      action: 'adjust_or_skip_task',
    },
    {
      name: 'ordinary within-session decline with the target still ready',
      observation: feedback({
        targetMuscle: 'chest',
        targetMuscleReadiness: 'ready',
        context: {
          exerciseId: 'machine_chest_press',
          setNumber: 3,
          setOrder: 3,
          reps: 9,
          loadKg: 60,
          rir: 2,
          setFormat: 'straight',
          rangeOfMotion: 'full',
        },
      }),
      action: 'proceed',
    },
    {
      name: 'whole-body exhaustion despite locally ready delts',
      observation: feedback({
        targetMuscle: 'shoulders',
        targetMuscleReadiness: 'ready',
        generalReadiness: 'limited',
        generalExhaustion: 9,
      }),
      action: 'adjust_or_skip_task',
    },
    {
      name: 'a symptom report',
      observation: feedback({
        targetMuscle: 'shoulders',
        symptomFlags: ['pain'],
        symptomNote: 'shoulder pain during the press',
      }),
      action: 'symptom_safety',
    },
  ])('returns a typed between-set action for $name', ({ observation, action }) => {
    const result = evaluateNextSetReadiness({
      feedback: [observation],
      sessionId: observation.sessionId,
      now: new Date('2026-01-20T00:05:00.000Z'),
      timerExpired: true,
    });
    expect(result).toMatchObject({
      scope: 'between_set',
      action,
      weeklyPlanChanged: false,
      safetyCertified: false,
    });
    expect(result.reasons.length).toBeGreaterThan(0);
    expect(['low', 'moderate', 'high']).toContain(result.uncertainty);
  });

  it('treats absent, stale, contradictory and duplicate observations as distinct evidence states', () => {
    expect(
      evaluateNextSetReadiness({
        feedback: [],
        sessionId: 'session-id',
        now: new Date('2026-01-20T00:05:00.000Z'),
      }).action,
    ).toBe('clarify');

    const stale = feedback({
      observedAt: '2026-01-19T20:00:00.000Z',
      targetMuscle: 'chest',
      targetMuscleReadiness: 'ready',
    });
    expect(
      evaluateNextSetReadiness({
        feedback: [stale],
        sessionId: stale.sessionId,
        now: new Date('2026-01-20T00:05:00.000Z'),
      }).action,
    ).toBe('clarify');

    const ready = feedback({
      id: 'ready',
      observedAt: '2026-01-20T00:04:00.000Z',
      sourceObservationId: 'voice-observation-1',
      targetMuscle: 'chest',
      targetMuscleReadiness: 'ready',
    });
    const retellings = Array.from({ length: 10 }, (_, index) => ({
      ...ready,
      id: `summary-${index}`,
      source: 'import' as const,
    }));
    expect(
      evaluateNextSetReadiness({
        feedback: retellings,
        sessionId: ready.sessionId,
        now: new Date('2026-01-20T00:05:00.000Z'),
      }).action,
    ).toBe('proceed');

    const conflict = {
      ...ready,
      id: 'conflict',
      sourceObservationId: 'voice-observation-2',
      targetMuscleReadiness: 'limited' as const,
    };
    expect(
      evaluateNextSetReadiness({
        feedback: [...retellings, conflict],
        sessionId: ready.sessionId,
        now: new Date('2026-01-20T00:05:00.000Z'),
      }).action,
    ).toBe('clarify');
  });

  it('applies a correction without mutating or deleting the original observation', () => {
    const original = feedback({
      id: 'original-observation',
      observedAt: '2026-01-20T00:03:00.000Z',
      targetMuscle: 'back',
      targetMuscleReadiness: 'ready',
      breathingReadiness: 'limited',
    });
    const correction = feedback({
      id: 'corrected-observation',
      createdAt: '2026-01-20T00:04:00.000Z',
      observedAt: '2026-01-20T00:03:00.000Z',
      correctsObservationId: original.id,
      targetMuscle: 'back',
      targetMuscleReadiness: 'ready',
      breathingReadiness: 'ready',
    });
    const history = [original, correction];
    const before = history.map((item) => ({ ...item }));
    expect(
      evaluateNextSetReadiness({
        feedback: history,
        sessionId: original.sessionId,
        now: new Date('2026-01-20T00:05:00.000Z'),
      }).action,
    ).toBe('proceed');
    expect(history).toEqual(before);
  });
});
