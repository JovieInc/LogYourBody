import { buildSession, createMesoBlock } from './engine';
import { nextEligibleSession, type RollingProgram } from './rolling-session';
import {
  planSessionDuration,
  type SessionDurationInput,
  type SessionDurationPlan,
} from './session-duration';
import { TRAINING_CONSENT_VERSION, type MuscleGroup } from './types';

const rotation: RollingProgram = {
  sessions: [
    { id: 'A', muscles: ['chest', 'back'] },
    { id: 'B', muscles: ['quads'] },
  ],
  requestedExposures: 2,
  minHoursBetweenSessions: 24,
  muscleRecoveryHours: 48,
};

function fixture(sets = 2): SessionDurationInput {
  const startedAt = '2026-10-25T12:00:00.000Z';
  const session = buildSession({
    setup: {
      id: 'committed-user',
      consentVersion: TRAINING_CONSENT_VERSION,
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment: 'full_gym',
      startedAt,
    },
    block: createMesoBlock(startedAt, startedAt),
    sessionId: 'prescribed-session-a',
    slot: 0,
    logs: [],
    feedback: [],
  });
  session.exercises = session.exercises.map((exercise) => ({ ...exercise, sets }));
  return {
    session,
    eligibility: nextEligibleSession(rotation, { entries: [] }, new Date(startedAt)),
    priorityMuscles: ['chest', 'back'],
    timing: {
      warmUpSeconds: 300,
      equipmentTransitionSeconds: 90,
      exercises: Object.fromEntries(
        session.exercises.map((exercise) => [
          exercise.id,
          {
            setSeconds: 60,
            restSeconds: 120,
            stationId: exercise.id,
          },
        ]),
      ),
    },
    setSignals: Object.fromEntries(
      session.exercises.map((exercise) => [
        exercise.id,
        Array.from({ length: sets }, (_, index) => ({ marginalValue: 20 - index })),
      ]),
    ),
  };
}

function setList(plan: SessionDurationPlan): string[] {
  return (plan.session?.exercises ?? []).flatMap((exercise) =>
    Array.from({ length: exercise.sets }, (_, index) => `${exercise.id}:${index + 1}`),
  );
}

function volume(plan: SessionDurationPlan, muscle: MuscleGroup): number {
  return (plan.session?.exercises ?? []).reduce(
    (sum, exercise) => sum + exercise.sets * (exercise.muscleContribution[muscle] ?? 0),
    0,
  );
}

/** Independently account for each returned set, rest interval and station change. */
function expectExplainedDuration(plan: SessionDurationPlan, input: SessionDurationInput): void {
  const exercises = plan.session?.exercises ?? [];
  const warmUp = exercises.length ? input.timing.warmUpSeconds : 0;
  let work = 0;
  let rest = 0;
  let transitions = 0;
  exercises.forEach((exercise, index) => {
    const estimate = input.timing.exercises[exercise.id]!;
    for (let set = 1; set <= exercise.sets; set += 1) {
      work += estimate.setSeconds;
      if (set < exercise.sets) rest += estimate.restSeconds;
    }
    if (
      index > 0 &&
      input.timing.exercises[exercises[index - 1]!.id]!.stationId !== estimate.stationId
    ) {
      transitions += input.timing.equipmentTransitionSeconds;
    }
  });
  expect(plan.duration).toEqual({
    warmUpSeconds: warmUp,
    setSeconds: work,
    restSeconds: rest,
    transitionSeconds: transitions,
    totalSeconds: warmUp + work + rest + transitions,
    minutes: (warmUp + work + rest + transitions) / 60,
  });
}

describe('derived session duration and optional limits (LYB-290)', () => {
  test('committed user needs no required duration or duration choice', () => {
    const input = fixture();
    const plan = planSessionDuration(input);
    expect(plan.requiredDurationMinutes).toBeNull();
    expect(plan.actualDurationMinutes).toBeNull();
    expect(plan.actualMinusPlannedMinutes).toBeNull();
    expect(plan.status).toBe('planned');
    expect(plan.duration).toEqual({
      warmUpSeconds: 300,
      setSeconds: 960,
      restSeconds: 960,
      transitionSeconds: 630,
      totalSeconds: 2850,
      minutes: 47.5,
    });
    expect(plan.session).toEqual(input.session);
    expectExplainedDuration(plan, input);
    expect(planSessionDuration({ ...input, timeCapMinutes: null })).toEqual(plan);
  });

  test.each([20, 25, 30, 37.25])(
    'busy user with a %s minute cap keeps priority touches in one shorter session',
    (timeCapMinutes) => {
      const input = { ...fixture(), timeCapMinutes };
      const full = planSessionDuration({ ...input, timeCapMinutes: undefined });
      const plan = planSessionDuration(input);
      expect(plan.status).toBe('abbreviated');
      expect(plan.session?.id).toBe(input.session.id);
      expect(plan.requiredDurationMinutes).toBe(timeCapMinutes);
      expect(plan.duration.totalSeconds).toBeLessThanOrEqual(timeCapMinutes * 60);
      expect(plan.duration.minutes).toBeLessThan(full.duration.minutes);
      expect(setList(plan).length).toBeLessThan(setList(full).length);
      expect(plan.omittedPriorityMuscles).toEqual([]);
      for (const muscle of input.priorityMuscles) {
        expect(plan.session?.exercises.some((exercise) => exercise.primaryMuscle === muscle)).toBe(
          true,
        );
      }
      expect(plan.eligibility).toEqual(full.eligibility);
      expect(plan.reasonCodes).toContain('time_cap_applied');
      expectExplainedDuration(plan, input);
    },
  );

  test('removes a lower-value tail set before higher-value work', () => {
    const input = fixture();
    input.timeCapMinutes = 45;
    const lowest = input.session.exercises[0]!;
    input.setSignals[lowest.id] = [{ marginalValue: 20 }, { marginalValue: 0.1 }];
    const plan = planSessionDuration(input);
    expect(plan.session?.exercises.find((exercise) => exercise.id === lowest.id)?.sets).toBe(1);
    expect(
      plan.session?.exercises
        .filter((exercise) => exercise.id !== lowest.id)
        .every((exercise) => exercise.sets === 2),
    ).toBe(true);
    expectExplainedDuration(plan, input);
  });

  test('same cap twice preserves the exact set list and does not mutate its inputs', () => {
    const input = { ...fixture(), timeCapMinutes: 25 };
    const before = JSON.stringify(input);
    const first = planSessionDuration(input);
    const repeated = planSessionDuration(input);
    const reapplied = planSessionDuration({ ...input, session: first.session! });
    expect(setList(repeated)).toEqual(setList(first));
    expect(setList(reapplied)).toEqual(setList(first));
    expect(reapplied.duration).toEqual(first.duration);
    expect(JSON.stringify(input)).toBe(before);
  });

  test('recovery-limited time-rich user loses fractional sets despite ample time', () => {
    const input: SessionDurationInput = {
      ...fixture(),
      timeCapMinutes: 240,
      recoveryLimit: {
        biceps: { maxFractionalSets: 1 },
        chest: { maxFractionalSets: 1, minimumRir: 5 },
      },
    };
    const full = planSessionDuration({ ...input, recoveryLimit: undefined });
    const plan = planSessionDuration(input);
    expect(setList(plan).length).toBeLessThan(setList(full).length);
    expect(volume(plan, 'biceps')).toBeLessThanOrEqual(1);
    expect(volume(plan, 'chest')).toBeLessThanOrEqual(1);
    expect(
      plan.session?.exercises.find((exercise) => exercise.primaryMuscle === 'chest')?.targetRir,
    ).toBe(5);
    expect(plan.reasonCodes).toContain('recovery_limit_applied');
    expect(plan.reasonCodes).not.toContain('time_cap_applied');
    expect(plan.eligibility).toEqual(full.eligibility);
    expectExplainedDuration(plan, input);
    const reapplied = planSessionDuration({ ...input, session: plan.session! });
    expect(setList(reapplied)).toEqual(setList(plan));
    expect(reapplied.session).toEqual(plan.session);
    const reversed = planSessionDuration({
      ...input,
      recoveryLimit: { chest: input.recoveryLimit!.chest, biceps: input.recoveryLimit!.biceps },
    });
    expect(reversed).toEqual(plan);
  });

  test('recovery may reduce effort alone and never leaves an increase-load instruction', () => {
    const input = fixture();
    const press = input.session.exercises.find((exercise) => exercise.primaryMuscle === 'chest')!;
    press.progression = 'increase_load';
    press.loadInstruction = 'Increase the load';
    input.recoveryLimit = { triceps: { maxFractionalSets: 100, minimumRir: 6 } };
    const plan = planSessionDuration(input);
    expect(plan.session?.exercises.find((exercise) => exercise.id === press.id)).toMatchObject({
      sets: 2,
      targetRir: 6,
      progression: 'hold',
      loadInstruction: null,
    });
    expect(setList(plan)).toHaveLength(16);
    expect(plan.duration.minutes).toBe(47.5);
    expectExplainedDuration(plan, input);
  });

  test.each([true, false])(
    'duration-only changes leave eligibleNow=%s unchanged',
    (eligibleNow) => {
      const input = fixture();
      input.eligibility = { ...input.eligibility, eligibleNow };
      const plan = planSessionDuration(input);
      input.timing = { ...input.timing, warmUpSeconds: 900, equipmentTransitionSeconds: 240 };
      input.actualDurationMinutes = 100;
      const changed = planSessionDuration(input);
      expect(changed.duration.minutes).toBeGreaterThan(plan.duration.minutes);
      expect(changed.eligibility).toEqual(plan.eligibility);
      expect(changed.session).toEqual(plan.session);
    },
  );

  test('a long productive session carries a marginal-benefit reason with no fixed minute ceiling', () => {
    const input = fixture(8);
    const plan = planSessionDuration(input);
    expect(plan.duration.minutes).toBe(191.5);
    expect(plan.status).toBe('planned');
    expect(plan.requiredDurationMinutes).toBeNull();
    expect(setList(plan)).toHaveLength(64);
    expect(plan.reasonCodes).toContain('marginal_benefit_retained');
    expectExplainedDuration(plan, input);
  });

  test.each(['marginalValue', 'fatigue'] as const)(
    'extra work stops at the supplied %s signal even with unlimited time',
    (signal) => {
      const input = fixture(8);
      const exercise = input.session.exercises[0]!;
      input.setSignals[exercise.id] = [
        { marginalValue: 10 },
        signal === 'marginalValue'
          ? { marginalValue: 0 }
          : { marginalValue: 10, fatigueLimited: true },
        ...Array.from({ length: 6 }, () => ({ marginalValue: 20 })),
      ];
      const plan = planSessionDuration(input);
      expect(plan.session?.exercises[0]?.sets).toBe(1);
      expect(plan.reasonCodes).toContain(
        signal === 'marginalValue' ? 'marginal_value_exhausted' : 'fatigue_limit_reached',
      );
      expectExplainedDuration(plan, input);
    },
  );

  test('returns supplied actual duration and its signed difference beside the derived plan', () => {
    const input = { ...fixture(), actualDurationMinutes: 52.25 };
    const plan = planSessionDuration(input);
    expect(plan.actualDurationMinutes).toBe(52.25);
    expect(plan.duration.minutes).toBe(47.5);
    expect(plan.actualMinusPlannedMinutes).toBe(4.75);
    expect(
      planSessionDuration({ ...input, actualDurationMinutes: 0 }).actualMinusPlannedMinutes,
    ).toBe(-47.5);
    expectExplainedDuration(plan, input);
  });

  test('charges transitions only for station changes and recomputes them after removing an exercise', () => {
    const input = fixture();
    input.session.exercises = input.session.exercises.slice(0, 3);
    const [first, middle, last] = input.session.exercises;
    input.timing.exercises[first!.id]!.stationId = 'same-station';
    input.timing.exercises[last!.id]!.stationId = 'same-station';
    expect(planSessionDuration(input).duration.transitionSeconds).toBe(180);
    input.setSignals[middle!.id] = [{ marginalValue: -1 }, { marginalValue: 10 }];
    const plan = planSessionDuration(input);
    expect(plan.duration.transitionSeconds).toBe(0);
    expect(plan.duration.restSeconds).toBe(240);
    expectExplainedDuration(plan, input);
  });

  test('reports an infeasible cap without dropping one protected priority or exceeding the cap', () => {
    const input = { ...fixture(), timeCapMinutes: 7 };
    const plan = planSessionDuration(input);
    expect(plan.status).toBe('unavailable');
    expect(plan.session).toBeNull();
    expect(plan.reasonCodes).toContain('priority_touches_do_not_fit');
    expect(plan.omittedPriorityMuscles).toEqual(['chest', 'back']);
    expect(plan.duration.totalSeconds).toBe(0);
    expect(plan.eligibility).toEqual(input.eligibility);
    expectExplainedDuration(plan, input);
  });

  test.each(['safetyStop', 'executionPaused'] as const)(
    '%s remains authoritative with ample time',
    (flag) => {
      const input = fixture();
      input.session[flag] = true;
      const plan = planSessionDuration(input);
      expect(plan.session).toBeNull();
      expect(plan.reasonCodes).toContain('session_unavailable');
      expectExplainedDuration(plan, input);
    },
  );

  test('a zero recovery budget overrides priority touches without inventing replacement work', () => {
    const input = fixture();
    input.recoveryLimit = { chest: { maxFractionalSets: 0 } };
    const plan = planSessionDuration(input);
    expect(volume(plan, 'chest')).toBe(0);
    expect(plan.omittedPriorityMuscles).toEqual(['chest']);
    expect(plan.reasonCodes).toContain('recovery_limit_applied');
    expectExplainedDuration(plan, input);
  });

  test('retained alternatives cannot restore removed sets or effort', () => {
    const input = fixture();
    input.recoveryLimit = { chest: { maxFractionalSets: 1, minimumRir: 6 } };
    const plan = planSessionDuration(input);
    const press = plan.session?.exercises.find((exercise) => exercise.primaryMuscle === 'chest')!;
    expect(press.substitutions.length).toBeGreaterThan(0);
    expect(
      press.substitutions.every(
        (alternative) => alternative.sets <= 1 && alternative.targetRir >= 6,
      ),
    ).toBe(true);
  });

  test.each([NaN, Infinity, -1, 0])('rejects an invalid time cap %s', (timeCapMinutes) => {
    expect(() => planSessionDuration({ ...fixture(), timeCapMinutes })).toThrow(
      'session_duration_input_invalid',
    );
  });

  test('rejects missing timing or value signals rather than inventing an estimate', () => {
    const input = fixture();
    const id = input.session.exercises[0]!.id;
    delete input.timing.exercises[id];
    expect(() => planSessionDuration(input)).toThrow('session_duration_prescription_invalid');
    const missingSignal = fixture();
    missingSignal.setSignals[id] = [{ marginalValue: 1 }];
    expect(() => planSessionDuration(missingSignal)).toThrow(
      'session_duration_prescription_invalid',
    );
  });

  test('rejects invalid recovery limits and nonfinite timing or value signals', () => {
    const input = fixture();
    input.recoveryLimit = { chest: { maxFractionalSets: -1 } };
    expect(() => planSessionDuration(input)).toThrow('session_duration_recovery_limit_invalid');
    input.recoveryLimit = { chest: { maxFractionalSets: 2, minimumRir: 7 } };
    expect(() => planSessionDuration(input)).toThrow('session_duration_recovery_limit_invalid');
    input.recoveryLimit = undefined;
    const id = input.session.exercises[0]!.id;
    input.timing.exercises[id]!.restSeconds = Infinity;
    expect(() => planSessionDuration(input)).toThrow('session_duration_prescription_invalid');
    input.timing.exercises[id]!.restSeconds = 120;
    input.setSignals[id] = [{ marginalValue: NaN }, { marginalValue: 1 }];
    expect(() => planSessionDuration(input)).toThrow('session_duration_prescription_invalid');
  });
});
