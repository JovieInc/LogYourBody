import { optimizeMesocycle, type OptimizerInput } from './optimizer';
import { certifyOptimization } from './optimizer-certification';
import type { RollingScheduleContext } from './rolling-schedule';
import { RECOVERY_POLICY } from './recovery';
import type { RecoveryTrial } from './recovery-contract';

function source(): OptimizerInput {
  return {
    sessions: [
      {
        id: 'A',
        day: 'monday',
        part: 'am',
        exercises: [
          {
            id: 'dumbbell_lateral_raise',
            name: 'Lateral raise',
            primaryMuscle: 'shoulders',
            sets: 2,
          },
        ],
      },
      {
        id: 'B',
        day: 'tuesday',
        part: 'pm',
        exercises: [{ id: 'dumbbell_curl', name: 'Curl', primaryMuscle: 'biceps', sets: 2 }],
      },
      {
        id: 'C',
        day: 'wednesday',
        part: 'any',
        exercises: [{ id: 'goblet_squat', name: 'Squat', primaryMuscle: 'quads', sets: 2 }],
      },
    ],
    equipmentProfile: 'dumbbells',
    locationId: null,
    locationPermission: 'unknown',
    stationGeography: 'unknown',
    rollingSchedule: {
      rotationId: 'rotation-1',
      programSetupId: 'setup',
      blockId: 'block-1',
      asOf: '2026-10-26T07:00:00Z',
      attendanceSince: '2026-10-01T00:00:00Z',
      requestedVisitsPerWeek: 5,
      slots: [
        slot('am', '2026-10-26T08:00:00Z'),
        slot('pm', '2026-10-26T20:00:00Z'),
        slot('later', '2026-10-28T08:00:00Z'),
      ],
      history: [],
      observations: [],
      trials: [],
      timing: { warmUpSeconds: 300, setSeconds: 60, restSeconds: 120, transitionSeconds: 60 },
    },
  };
}

function slot(id: string, scheduledAt: string): RollingScheduleContext['slots'][number] {
  return {
    id,
    scheduledAt,
    timeZone: 'UTC',
    locationId: 'gym',
    groupId: id,
    visitId: id,
    kind: 'visit' as const,
    availableEquipment: ['dumbbells' as const, 'bench' as const],
    priorityTargets: [],
  };
}

function review(input = source()) {
  const result = optimizeMesocycle(input);
  if (result.kind !== 'proposal') throw new Error('Expected proposal');
  expect(certifyOptimization(input, result.proposal)).toEqual({ ok: true });
  expect(result.proposal.rollingSchedule).toBeDefined();
  return result.proposal.rollingSchedule!;
}

function history(
  input: OptimizerInput,
  templateId = 'A',
  completedSets = 1,
  at = '2026-10-25T08:00:00Z',
) {
  const template = input.sessions.find((row) => row.id === templateId)!;
  const context = input.rollingSchedule!;
  const id = `history-${context.history.length}`;
  context.history.push({
    id,
    templateId,
    rotationId: context.rotationId,
    groupId: id,
    visitId: id,
    startedAt: at,
    endedAt: at,
    outcome: completedSets ? 'partial' : 'empty',
    exercises: template.exercises.map((exercise) => ({
      id: exercise.id,
      primaryMuscle: exercise.primaryMuscle,
      sets: exercise.sets,
      muscleContribution: { [exercise.primaryMuscle]: 1 },
      targetRir: 2,
    })),
  });
  input.logs ??= [];
  for (let n = 1; n <= completedSets; n++)
    input.logs.push({
      id: `${id}-${n}`,
      sessionId: id,
      exerciseId: template.exercises[0]!.id,
      setNumber: n,
      reps: 10,
      loadKg: 10,
      rir: 2,
      completedAt: at,
    });
  return context.history.at(-1)!;
}

function reduction(): RecoveryTrial {
  const outcome = {
    decision: 'pending' as const,
    observationIds: [],
    completedSetIds: [],
    rationale: 'Awaiting review.',
  };
  return {
    id: '11111111-1111-4111-8111-111111111111',
    record_type: 'recovery_trial',
    version: 1,
    revision: 1,
    policyVersion: RECOVERY_POLICY.version,
    programSetupId: 'setup',
    programRevisionId: null,
    blockId: 'block-1',
    muscle: 'shoulders',
    exerciseId: 'dumbbell_lateral_raise',
    goal: 'emphasize',
    sourceFingerprint: 'source',
    requestHash: 'request',
    baseline: [],
    inference: {
      action: 'reduce',
      rationale: 'Reviewed decline.',
      uncertainty: 'high',
      evidenceIds: [],
      observationIds: [],
      completedSetIds: [],
      comparableSessionIds: [],
      change: { kind: 'sets', from: 2, to: 1 },
      parameterProposal: null,
    },
    hypothesis: 'A reduced dose may improve tolerance.',
    reviewPoint: 'next_comparable_completed_exposure',
    holdConditions: [],
    revertConditions: [],
    state: 'applied',
    outcome,
    history: [{ revision: 1, state: 'applied', at: '2026-10-25T09:00:00Z', outcome }],
    createdAt: '2026-10-25T09:00:00Z',
    updatedAt: '2026-10-25T09:00:00Z',
    appliedAt: '2026-10-25T09:00:00Z',
  };
}

describe('rolling schedule certification (LYB-174)', () => {
  it('allocates the approved rotation into actual opportunities across weekends without adding visits or sets', () => {
    const input = source();
    input.rollingSchedule!.slots = [
      slot('fri', '2026-10-30T08:00:00Z'),
      slot('sun', '2026-11-01T08:00:00Z'),
      slot('next-fri', '2026-11-06T08:00:00Z'),
    ];
    const result = review(input);
    expect(result.allocations.map((row) => row.templateId)).toEqual(['A', 'B', 'C']);
    expect(result.allocations.map((row) => row.slotId)).toEqual(['fri', 'sun', 'next-fri']);
    expect(result.allocations.flatMap((row) => row.work)).toHaveLength(6);
    expect(new Set(result.allocations.flatMap((row) => row.work.map((set) => set.id))).size).toBe(
      6,
    );
    expect(result.unallocated).toEqual([]);
  });

  it('certifies the complete scheduling receipt, including set identity and uncertainty', () => {
    const input = source();
    const proposal = optimizeMesocycle(input);
    if (proposal.kind !== 'proposal') throw new Error('Expected proposal');
    proposal.proposal.rollingSchedule!.allocations[0]!.work[0]!.setNumber = 99;
    expect(certifyOptimization(input, proposal.proposal)).toMatchObject({ ok: false });
  });

  it('keeps a half-session log and places unfinished identities once without stacking them on B', () => {
    const input = source();
    history(input);
    const before = JSON.parse(JSON.stringify(input));
    const result = review(input);
    expect(result.allocations.map((row) => row.templateId)).toEqual(['B', 'C', 'A']);
    expect(result.allocations.map((row) => row.work.length)).toEqual([2, 2, 1]);
    expect(result.allocations.at(-1)!.work[0]!.setNumber).toBe(2);
    expect(result.completedSetIds).toEqual(['history-0-1']);
    expect(result.trailingVolume.days7.shoulders).toBe(1);
    expect(input).toEqual(before);
    expect(review(input)).toEqual(result);
  });

  it('two empty missed visits do not restart or skip the next pending muscle', () => {
    const input = source();
    history(input, 'A', 2, '2026-10-23T08:00:00Z');
    history(input, 'B', 0, '2026-10-24T08:00:00Z');
    history(input, 'C', 0, '2026-10-25T08:00:00Z');
    expect(review(input).allocations.map((row) => row.templateId)).toEqual(['B', 'C']);
  });

  it('distinguishes continuation of the same visit from a separately resumed visit', () => {
    const input = source();
    const partial = history(input);
    const continued = slot('continue', '2026-10-26T08:00:00Z');
    Object.assign(continued, {
      kind: 'continuation',
      groupId: partial.groupId,
      visitId: partial.visitId,
      continueSessionId: partial.id,
    });
    input.rollingSchedule!.slots = [continued];
    expect(review(input).allocations[0]).toMatchObject({
      templateId: 'A',
      kind: 'continuation',
      continuedSessionId: partial.id,
      work: [expect.objectContaining({ setNumber: 2 })],
    });
    continued.visitId = 'different-visit';
    expect(review(input).tradeoffs[0]!.reason).toBe('continuation_context_requires_review');
    Object.assign(continued, { kind: 'visit', visitId: 'new-visit' });
    delete continued.continueSessionId;
    expect(review(input).allocations[0]!.templateId).toBe('B');
  });

  it('local under-recovery leaves other muscles available; whole-body limitation constrains all', () => {
    const input = source();
    input.rollingSchedule!.observations.push({
      id: 'sore',
      at: input.rollingSchedule!.asOf,
      scope: 'muscle',
      muscle: 'shoulders',
      state: 'limited',
    });
    const local = review(input);
    expect(local.allocations.map((row) => row.templateId)).toEqual(['B', 'C']);
    expect(local.unallocated).toHaveLength(2);
    input.rollingSchedule!.observations.push({
      id: 'global',
      at: input.rollingSchedule!.asOf,
      scope: 'whole_body',
      state: 'limited',
    });
    expect(review(input).allocations).toEqual([]);
    expect(review(input).tradeoffs).toContainEqual(
      expect.objectContaining({ kind: 'move_reduce_or_rest' }),
    );
  });

  it('a newer observation supersedes a stale limitation while same-time conflict preserves uncertainty', () => {
    const input = source();
    const context = input.rollingSchedule!;
    context.observations = [
      {
        id: 'old',
        at: '2026-09-01T08:00:00Z',
        scope: 'muscle',
        muscle: 'shoulders',
        state: 'limited',
      },
      { id: 'current', at: context.asOf, scope: 'muscle', muscle: 'shoulders', state: 'ready' },
    ];
    expect(review(input).allocations[0]).toMatchObject({
      templateId: 'A',
      uncertainty: expect.arrayContaining(['stale_or_future_observation']),
    });
    context.observations.push({ ...context.observations[1]!, id: 'conflict', state: 'limited' });
    expect(review(input).allocations[0]).toMatchObject({
      templateId: 'B',
      uncertainty: expect.arrayContaining(['conflicting_observations']),
    });
  });

  it('applies a reviewed reduction once and restores the future allocation on reject or revert', () => {
    const input = source();
    const trial = reduction();
    input.rollingSchedule!.trials = [trial];
    const applied = review(input);
    expect(applied.allocations[0]!.work).toHaveLength(1);
    expect(applied.dropped).toEqual([
      expect.objectContaining({
        reason: 'applied_recovery_reduction',
        work: expect.objectContaining({ exerciseId: trial.exerciseId, setNumber: 2 }),
      }),
    ]);
    for (const state of ['proposed', 'rejected', 'reverted'] as const) {
      trial.state = state;
      expect(review(input).allocations[0]!.work).toHaveLength(2);
      expect(review(input).dropped).toEqual([]);
    }
    trial.state = 'applied';
    history(input, 'A', 1);
    expect(
      review(input)
        .allocations.flatMap((row) => row.work)
        .some((set) => set.exerciseId === trial.exerciseId),
    ).toBe(false);
    expect(review(input).completedSetIds).toEqual(['history-0-1']);
  });

  it('consumes an applied spacing review by moving to a different muscle or explicit rest', () => {
    const input = source();
    const trial = reduction();
    trial.inference.action = 'respace';
    trial.inference.change = null;
    input.rollingSchedule!.trials = [trial];
    expect(review(input).allocations.map((row) => row.templateId)).toEqual(['B', 'C']);
    expect(review(input).unallocated.map((row) => row.work.templateId)).toEqual(['A', 'A']);
    trial.state = 'reverted';
    expect(review(input).allocations[0]!.templateId).toBe('A');
  });

  it('executes the reviewed lower-dose trial against its original local observation, while new adversity still defers work', () => {
    const input = source();
    const trial = reduction();
    trial.inference.observationIds = ['decline'];
    input.rollingSchedule!.trials = [trial];
    input.rollingSchedule!.observations = [
      {
        id: 'decline',
        at: '2026-10-25T08:00:00Z',
        scope: 'muscle',
        muscle: 'shoulders',
        state: 'limited',
      },
    ];
    expect(review(input).allocations[0]).toMatchObject({
      templateId: 'A',
      work: [expect.objectContaining({ setNumber: 1 })],
    });
    input.rollingSchedule!.observations.push({
      id: 'new-adversity',
      at: input.rollingSchedule!.asOf,
      scope: 'muscle',
      muscle: 'shoulders',
      state: 'limited',
    });
    expect(review(input).allocations[0]!.templateId).toBe('B');
  });

  it('reserves evening biceps work against morning pulling, without repeating global priority in both visits', () => {
    const input = source();
    input.sessions[0]!.exercises = [
      { id: 'one_arm_dumbbell_row', name: 'Row', primaryMuscle: 'back', sets: 2 },
    ];
    const context = input.rollingSchedule!;
    context.slots = [
      slot('am', '2026-10-26T08:00:00Z'),
      slot('pm', '2026-10-26T20:00:00Z'),
      slot('next', '2026-10-28T08:00:00Z'),
    ];
    context.slots[0]!.groupId = 'split';
    context.slots[1]!.groupId = 'split';
    context.slots[1]!.priorityTargets = ['biceps'];
    const planned = review(input);
    expect(planned.allocations.map((row) => row.templateId)).toEqual(['C', 'B', 'A']);
    // The later slot's own priority must win over a generic queue successor.
    expect(
      planned.allocations
        .find((row) => row.slotId === 'pm')!
        .work.every((set) => set.exerciseId === 'dumbbell_curl'),
    ).toBe(true);
  });

  it('intervening actual pulling/grip changes the evening selection even with more elapsed time', () => {
    const input = source();
    input.sessions[0]!.exercises = [
      { id: 'one_arm_dumbbell_row', name: 'Row', primaryMuscle: 'back', sets: 2 },
    ];
    const context = input.rollingSchedule!;
    context.slots = [slot('pm', '2026-10-26T20:00:00Z')];
    context.slots[0]!.groupId = 'split';
    context.slots[0]!.priorityTargets = ['biceps'];
    const actual = history(input, 'A', 2, '2026-10-26T06:00:00Z');
    actual.groupId = 'split';
    expect(review(input).allocations[0]!.templateId).toBe('C');
  });

  it('uses real elapsed timestamps across midnight and DST without claiming a recovery percentage or a 32-hour rule', () => {
    const input = source();
    input.rollingSchedule!.asOf = '2026-11-02T00:00:00Z';
    history(input, 'A', 1, '2026-11-01T01:30:00-04:00');
    input.rollingSchedule!.slots = [slot('dst', '2026-11-02T01:30:00-05:00')];
    input.rollingSchedule!.slots[0]!.timeZone = 'America/New_York';
    expect(review(input).allocations[0]!.priorWork[0]!.elapsedHours).toBe(25);
    expect(review(input).readiness).toBe('conditional_not_measured');
    for (const [time, hours] of [
      ['2026-11-02T01:30:00-04:00', 24],
      ['2026-11-02T13:30:00-04:00', 36],
    ] as const) {
      input.rollingSchedule!.slots[0]!.scheduledAt = time;
      expect(review(input).allocations[0]!.priorWork[0]!.elapsedHours).toBe(hours);
    }
  });

  it('cancellation and repeated rescheduling keep the same finite work identities and expose overflow', () => {
    const input = source();
    input.rollingSchedule!.slots[1]!.canceled = true;
    const first = review(input);
    expect(first.unallocated).toHaveLength(2);
    expect(first.tradeoffs.at(-1)!.reason).toBe('remaining_work_is_not_catch_up_debt');
    input.rollingSchedule!.slots[2]!.scheduledAt = '2026-11-05T20:00:00Z';
    const second = review(input);
    expect(second.allocations.flatMap((row) => row.work)).toEqual(
      first.allocations.flatMap((row) => row.work),
    );
  });

  it('uses an optional hard time cap and derives unrestricted duration above ninety minutes', () => {
    const input = source();
    input.sessions[0]!.exercises[0]!.sets = 30;
    input.rollingSchedule!.slots[0]!.priorityTargets = ['side_delts'];
    expect(review(input).allocations[0]!.durationMinutes).toBeGreaterThan(90);
    input.rollingSchedule!.slots[0]!.timeCapMinutes = 25;
    const capped = review(input);
    expect(capped.allocations[0]!.durationMinutes).toBeLessThanOrEqual(25);
    expect(capped.allocations[0]!.work.length).toBeGreaterThan(0);
    expect(capped.unallocated.length).toBeGreaterThan(0);
    expect(capped.dropped).toEqual([]);
  });

  it('travel inventory and back-pain exclusions cannot be bypassed by scheduling', () => {
    const input = source();
    input.rollingSchedule!.slots.forEach((row) => {
      row.availableEquipment = [];
    });
    expect(review(input).allocations).toEqual([]);
    input.rollingSchedule!.slots.forEach((row) => {
      row.availableEquipment = ['dumbbells'];
    });
    input.sessions[2]!.exercises = [
      { id: 'dumbbell_romanian_deadlift', name: 'RDL', primaryMuscle: 'hamstrings', sets: 2 },
    ];
    input.sequencingContext = {
      blockId: 'block-1',
      asOf: input.rollingSchedule!.asOf,
      intents: [],
      excludedConcerns: ['low_back_symptoms'],
    };
    expect(
      review(input)
        .allocations.flatMap((row) => row.work)
        .some((set) => set.exerciseId === 'dumbbell_romanian_deadlift'),
    ).toBe(false);
  });

  it('preserves a prescribed deload effort and never fills spare time with more sets', () => {
    const input = source();
    for (const template of input.sessions)
      for (const exercise of template.exercises) {
        exercise.sets = 1;
        exercise.targetRir = 5;
      }
    const result = review(input);
    expect(result.allocations.flatMap((row) => row.work)).toHaveLength(3);
    expect(result.allocations.flatMap((row) => row.work).every((set) => set.targetRir === 5)).toBe(
      true,
    );
  });

  it('requires review before exceeding agreed visits even when extra opportunities are offered', () => {
    const input = source();
    input.rollingSchedule!.requestedVisitsPerWeek = 2;
    const result = review(input);
    expect(result.allocations).toHaveLength(2);
    expect(result.tradeoffs).toContainEqual(
      expect.objectContaining({ reason: 'additional_visit_requires_review' }),
    );
    expect(result.unallocated).toHaveLength(2);
  });

  it.each([
    [5, 4],
    [6, 1],
  ] as const)(
    'offers one reversible capacity choice after %i requested / %i recorded over two weeks',
    (requested, achieved) => {
      const input = source();
      const context = input.rollingSchedule!;
      context.asOf = '2026-10-29T00:00:00Z';
      context.attendanceSince = '2026-10-15T00:00:00Z';
      context.slots = [slot('next', '2026-10-30T08:00:00Z')];
      context.requestedVisitsPerWeek = requested;
      for (let week = 0; week < 2; week++)
        for (let day = 0; day < achieved; day++) {
          const at = new Date(
            Date.parse(context.attendanceSince) + (week * 7 + day) * 86400000,
          ).toISOString();
          history(input, 'A', 1, at).rotationId = 'old';
        }
      const choice = review(input).attendanceChoice!;
      expect(choice).toMatchObject({
        requestedVisits: requested,
        observedVisitsPerWeek: [achieved, achieved],
        suggestedVisits: achieved >= 2 ? achieved : null,
        applied: false,
        reversible: true,
      });
      context.attendanceSince = '2026-10-22T00:00:00Z';
      expect(review(input).attendanceChoice).toBeNull();
    },
  );

  it('does not treat unknown/unlogged work as a missed workout or infer readiness from no feedback', () => {
    const input = source();
    history(input, 'A', 0).outcome = 'unknown';
    const result = review(input);
    expect(result.attendanceChoice).toBeNull();
    expect(result.allocations[0]!.uncertainty).toContain('unlogged_workout');
    expect(result.readiness).toBe('conditional_not_measured');
  });

  it('rejects ambiguous set identities, invalid timezones, and a continuation without an identity', () => {
    const input = source();
    history(input);
    input.logs!.push({ ...input.logs![0]! });
    expect(optimizeMesocycle(input)).toEqual({ kind: 'invalid' });
    input.logs!.pop();
    input.rollingSchedule!.slots[0]!.timeZone = 'Fake/Zone';
    expect(optimizeMesocycle(input)).toEqual({ kind: 'invalid' });
    input.rollingSchedule!.slots[0]!.timeZone = 'UTC';
    input.rollingSchedule!.slots[0]!.kind = 'continuation';
    expect(optimizeMesocycle(input)).toEqual({ kind: 'invalid' });
  });
});
