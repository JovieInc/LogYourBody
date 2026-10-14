import {
  activeConstraints,
  applySteering,
  evaluateTrajectory,
  type ControllerInput,
  type SituationalConstraint,
} from './controller';
import {
  MESOCYCLE_WEEKS,
  TRAINING_CONSENT_VERSION,
  type TrainingFeedback,
  type TrainingProgramSetup,
} from './types';

const NOW = new Date('2026-02-02T12:00:00.000Z');

const setup: TrainingProgramSetup = {
  id: 'setup-id',
  consentVersion: TRAINING_CONSENT_VERSION,
  adultConfirmed: true,
  safetyConfirmed: true,
  sessionsPerWeek: 2,
  equipment: 'dumbbells',
  startedAt: '2026-01-05T00:00:00.000Z',
};

function feedback(input: Partial<TrainingFeedback> = {}): TrainingFeedback {
  return {
    id: 'feedback-id',
    sessionId: 'session-id',
    soreness: 2,
    pump: 5,
    performance: 'stable',
    jointPain: 0,
    createdAt: '2026-02-01T00:00:00.000Z',
    ...input,
  };
}

function declineSeries(count: number, soreness = 2): TrainingFeedback[] {
  return Array.from({ length: count }, (_, index) =>
    feedback({
      id: `decline-${index}`,
      sessionId: `session-${index}`,
      performance: 'down',
      soreness,
      createdAt: `2026-01-${String(28 - index).padStart(2, '0')}T00:00:00.000Z`,
    }),
  );
}

function input(overrides: Partial<ControllerInput> = {}): ControllerInput {
  return {
    setup,
    block: {
      id: 'block-1',
      startDate: setup.startedAt,
      weekCount: MESOCYCLE_WEEKS,
      currentWeek: 4,
      targetRir: 2,
    },
    sessions: [{ status: 'completed', server_updated_at: '2026-02-01T00:00:00.000Z' }],
    feedback: [],
    completedThisWeek: 1,
    plannedSessionsByNow: 1,
    trajectory: null,
    constraints: [],
    now: NOW,
    ...overrides,
  };
}

describe('proactive physique controller', () => {
  it('holds on a stable trajectory and answers the home questions', () => {
    const receipt = evaluateTrajectory(input());
    expect(receipt.decision).toEqual({ kind: 'hold', optionalBurdenReduction: false });
    expect(receipt.nextAction).toContain('on track');
    expect(receipt.actor).toBe('controller');
    expect(receipt.rationale).toBeTruthy();
    expect(receipt.reviewPoint).toBeTruthy();
  });

  it('does not react to a single noisy weight datum or a transient off-target day', () => {
    const singlePoint = evaluateTrajectory(
      input({
        trajectory: {
          targetRateKgPerWeek: { min: -0.75, max: -0.25 },
          points: [{ date: '2026-02-01', weightKg: 82.4 }],
        },
      }),
    );
    expect(singlePoint.decision.kind).toBe('hold');

    const shortSpan = evaluateTrajectory(
      input({
        trajectory: {
          targetRateKgPerWeek: { min: -0.75, max: -0.25 },
          points: [
            { date: '2026-01-30', weightKg: 80 },
            { date: '2026-01-31', weightKg: 80.2 },
            { date: '2026-02-01', weightKg: 81.5 },
          ],
        },
      }),
    );
    expect(shortSpan.decision.kind).toBe('hold');
  });

  it('asks one question on sustained trajectory drift instead of prescribing compensation', () => {
    const receipt = evaluateTrajectory(
      input({
        trajectory: {
          targetRateKgPerWeek: { min: -0.75, max: -0.25 },
          points: [
            { date: '2026-01-10', weightKg: 82 },
            { date: '2026-01-18', weightKg: 82.2 },
            { date: '2026-01-26', weightKg: 82.5 },
            { date: '2026-02-01', weightKg: 82.8 },
          ],
        },
      }),
    );
    expect(receipt.decision.kind).toBe('ask_question');
    expect(receipt.after).toContain('unchanged');
  });

  it('treats stale or missing evidence as an evidence gap, never non-adherence', () => {
    const stale = evaluateTrajectory(
      input({
        sessions: [{ status: 'completed', server_updated_at: '2025-12-20T00:00:00.000Z' }],
        feedback: [feedback({ performance: 'down', createdAt: '2025-12-20T00:00:00.000Z' })],
        completedThisWeek: 0,
        plannedSessionsByNow: 2,
      }),
    );
    expect(stale.decision.kind).toBe('hold');
    expect(stale.signalFreshness.training).toBe('stale');
    expect(stale.signalFreshness.recovery).toBe('stale');

    const noData = evaluateTrajectory(
      input({ sessions: [], feedback: [], completedThisWeek: 0, plannedSessionsByNow: 2 }),
    );
    expect(noData.decision.kind).toBe('hold');
    expect(noData.signalFreshness.training).toBe('missing');
  });

  it('never auto-deloads on five early-block declines; it investigates instead', () => {
    const weekOne = {
      id: 'block-1',
      startDate: setup.startedAt,
      weekCount: MESOCYCLE_WEEKS,
      currentWeek: 1,
      targetRir: 4,
    };
    const quiet = evaluateTrajectory(input({ block: weekOne, feedback: declineSeries(5) }));
    expect(quiet.decision.kind).toBe('ask_question');
    expect(quiet.decision.kind).not.toBe('recovery_proposal');

    const sore = evaluateTrajectory(input({ block: weekOne, feedback: declineSeries(5, 8) }));
    expect(sore.decision).toEqual({ kind: 'adjust_training', adjustment: 'load_correction' });
    expect(sore.nextAction).toContain('load increment lighter');
  });

  it('proposes a bounded deload on late-block decline with corroborating recovery data', () => {
    const receipt = evaluateTrajectory(input({ feedback: declineSeries(4, 8) }));
    expect(receipt.decision).toEqual({
      kind: 'recovery_proposal',
      proposal: 'deload_microcycle',
      requiresConfirmation: true,
    });
    expect(receipt.after).toContain('one microcycle');
    expect(receipt.reviewPoint).toContain('deload');
  });

  it('forces no change when recent check-ins are contradictory', () => {
    const current = feedback({
      id: 'a-current',
      sessionId: 'current-session',
      performance: 'down',
      soreness: 8,
    });
    const conflicting = { ...current, id: 'z-conflicting', performance: 'stable' as const };
    const previous = feedback({
      id: 'a-previous',
      sessionId: 'previous-session',
      performance: 'down',
      soreness: 8,
      createdAt: '2026-01-28T00:00:00.000Z',
    });
    const receipt = evaluateTrajectory(input({ feedback: [current, conflicting, previous] }));
    expect(receipt.decision.kind).toBe('hold');
    expect(receipt.rationale).toContain('conflict');
  });

  it('pauses the session on high pain through the existing engine contract', () => {
    const receipt = evaluateTrajectory(input({ feedback: [feedback({ jointPain: 5 })] }));
    expect(receipt.decision).toEqual({ kind: 'adjust_training', adjustment: 'pause_session' });
  });

  it('replans a missed session forward without punitive catch-up', () => {
    const receipt = evaluateTrajectory(input({ completedThisWeek: 0, plannedSessionsByNow: 1 }));
    expect(receipt.decision).toEqual({ kind: 'reschedule', missedSessions: 1 });
    expect(receipt.after).toContain('carried forward');
    expect(receipt.nextAction).not.toMatch(/extra|double|catch.?up/i);
  });

  it('honors expiring situational constraints without corrupting durable preferences', () => {
    const timeCap: SituationalConstraint = {
      id: 'cap-1',
      kind: 'time_cap',
      detail: '30 minutes available today',
      expiresAt: '2026-02-03T00:00:00.000Z',
    };
    const expired: SituationalConstraint = {
      id: 'cap-2',
      kind: 'readiness_low',
      detail: 'was tired last week',
      expiresAt: '2026-02-01T00:00:00.000Z',
    };
    expect(activeConstraints([timeCap, expired], NOW)).toEqual([timeCap]);
    const durableBefore = { ...setup };
    const receipt = evaluateTrajectory(input({ constraints: [timeCap, expired] }));
    expect(receipt.decision).toEqual({ kind: 'adjust_training', adjustment: 'shorten_session' });
    expect(setup).toEqual(durableBefore);
  });

  it('evaluates reduced burden instead of escalating when ahead of plan', () => {
    const receipt = evaluateTrajectory(
      input({
        completedThisWeek: 2,
        plannedSessionsByNow: 2,
        feedback: [feedback({ performance: 'up' })],
      }),
    );
    expect(receipt.decision).toEqual({ kind: 'hold', optionalBurdenReduction: true });
    expect(receipt.rationale).not.toMatch(/push harder|add sets|extra session/i);
  });

  it('honors user steering within policy and catches deliberate wrong interventions', () => {
    expect(applySteering({ type: 'rest_today' })).toMatchObject({
      applied: true,
      decision: { kind: 'reschedule' },
    });
    expect(applySteering({ type: 'reduce_today_volume' })).toMatchObject({
      applied: true,
      decision: { kind: 'adjust_training', adjustment: 'shorten_session' },
    });
    for (const request of [
      { type: 'add_extra_session' },
      { type: 'increase_weekly_volume' },
    ] as const) {
      const outcome = applySteering(request);
      expect(outcome.applied).toBe(false);
      expect(outcome.reason).toBeTruthy();
    }
  });
});
