import { adaptiveRecoveryEnabled } from '@/lib/flags/adaptive-recovery';
import { buildSession, createMesoBlock } from './engine';
import { MemoryTrainingRecords } from './memory-records.testing';
import { evaluateRecovery, type RecoveryExposure } from './recovery';
import { createRecoveryTrial, decideRecoveryTrial, readRecovery } from './recovery-records';
import { getOrCreateNextWorkout, storeProgramSetup } from './service';
import type { TrainingFeedback, TrainingProgramSetup } from './types';

const monday = new Date('2026-10-12T09:00:00.000Z');
const tuesday = new Date('2026-10-13T09:00:00.000Z');
const now = new Date('2026-10-13T10:00:00.000Z');
const id = (number: number) => `11111111-1111-4111-8111-${String(number).padStart(12, '0')}`;
const target = {
  muscle: 'shoulders',
  exerciseId: 'dumbbell_lateral_raise',
  goal: 'emphasize',
} as const;
const setup: TrainingProgramSetup = {
  id: id(1),
  consentVersion: 'hypertrophy-coach-v1',
  adultConfirmed: true,
  safetyConfirmed: true,
  equipment: 'dumbbells',
  sessionsPerWeek: 3,
  startedAt: monday.toISOString(),
};

function exposure(number: number, time: Date, reps: number[]): RecoveryExposure {
  const session = buildSession({
    setup,
    block: createMesoBlock(setup.startedAt, time.toISOString()),
    sessionId: id(number),
    slot: 0,
    logs: [],
    feedback: [],
  });
  const prescription = session.exercises.find((item) => item.id === target.exerciseId)!;
  return {
    sessionId: session.id,
    prescription,
    completed: reps.map((count, index) => ({
      id: id(number * 10 + index),
      sessionId: session.id,
      exerciseId: prescription.id,
      setNumber: index + 1,
      reps: count,
      loadKg: 10,
      rir: 3,
      completedAt: time.toISOString(),
    })),
  };
}
function observation(
  exposure: RecoveryExposure,
  overrides: Partial<TrainingFeedback> = {},
): TrainingFeedback {
  return {
    id: id(Number(exposure.sessionId.slice(-3)) + 100),
    sessionId: exposure.sessionId,
    createdAt: exposure.completed[0].completedAt,
    observedAt: exposure.completed[0].completedAt,
    source: 'touch',
    sourceObservationId: `source-${exposure.sessionId}`,
    muscles: {
      shoulders: {
        performance: 'stable',
        recovery: 'ready',
        soreness: 2,
        pump: 6,
        workload: 'as_expected',
      },
    },
    targetMuscle: 'shoulders',
    targetMuscleReadiness: 'ready',
    generalReadiness: 'ready',
    jointPain: 0,
    supportingReadiness: { grip: 'ready', trunk: 'ready' },
    context: {
      exerciseId: target.exerciseId,
      setNumber: 1,
      setOrder: 1,
      restSeconds: 120,
      setup: 'same-dumbbells',
      rangeOfMotion: 'full',
      setFormat: 'straight',
    },
    ...overrides,
  };
}
function scenario() {
  const first = exposure(2, monday, [12, 10]);
  const second = exposure(3, tuesday, [8, 6]);
  const feedback = [
    observation(first),
    observation(second, {
      muscles: { shoulders: { performance: 'down', recovery: 'limited', soreness: 5 } },
      targetMuscleReadiness: 'limited',
    }),
  ];
  return { first, second, exposures: [first, second], feedback };
}
function evaluate(overrides: Partial<Parameters<typeof evaluateRecovery>[0]> = {}) {
  return evaluateRecovery({ ...target, ...scenario(), now, deload: false, ...overrides });
}

describe('bounded adaptive recovery policy', () => {
  it('offers a one-variable lower-dose trial after an unexpected Tuesday decline without diagnosing its cause', () => {
    expect(evaluate()).toMatchObject({
      action: 'reduce',
      change: { kind: 'sets', from: 2, to: 1 },
      uncertainty: 'high',
    });
    expect(evaluate().rationale).toContain('does not establish its cause');
  });
  it('holds favorable side-delt response and exposes only the missing numerical policy decision', () => {
    const { first } = scenario();
    const second = exposure(3, tuesday, [13, 10]);
    const favorable = {
      exposures: [first, second],
      feedback: [observation(first), observation(second)],
    };
    expect(evaluate(favorable)).toMatchObject({
      action: 'hold',
      change: null,
      parameterProposal: { status: 'needs_policy_review', scope: 'side_delt_specialization' },
    });
    expect(evaluate({ ...favorable, goal: 'grow' }).parameterProposal).toBeNull();
    expect(evaluate({ ...favorable, goal: 'maintain' }).action).toBe('hold');
  });
  it('ignores ordinary within-session rep loss and a new week alone', () => {
    const first = exposure(2, monday, [12, 10]);
    const second = exposure(3, tuesday, [12, 8]);
    expect(
      evaluate({ exposures: [first, second], feedback: [observation(first), observation(second)] })
        .action,
    ).toBe('hold');
  });
  it.each(['setup', 'restSeconds', 'setOrder', 'rangeOfMotion', 'setFormat'] as const)(
    'does not infer local capacity after missing/changed %s',
    (field) => {
      const { feedback } = scenario();
      delete feedback[1].context![field];
      expect(evaluate({ feedback })).toMatchObject({ action: 'respace', change: null });
    },
  );
  it.each(['loadKg', 'rir'] as const)(
    'requires comparable %s and known load conventions',
    (field) => {
      const { exposures } = scenario();
      exposures[1].completed[0][field] = field === 'loadKg' ? 20 : 0;
      expect(evaluate({ exposures }).change).toBeNull();
      exposures[1].completed[0].loadKg = null;
      expect(evaluate({ exposures }).change).toBeNull();
    },
  );
  it('distinguishes local, supporting-muscle and whole-body limits and deload', () => {
    const { feedback } = scenario();
    feedback[1].supportingReadiness = { trunk: 'limited' };
    expect(evaluate({ feedback }).action).toBe('substitute');
    feedback[1].generalReadiness = 'limited';
    expect(evaluate({ feedback }).action).toBe('recovery_review');
    expect(evaluate({ deload: true }).action).toBe('recovery_review');
  });
  it('does not escalate on missing, conflicting, stale, historical or adverse observations', () => {
    expect(evaluate({ feedback: [] }).action).toBe('insufficient_evidence');
    const { feedback } = scenario();
    expect(
      evaluate({
        feedback: [
          ...feedback,
          {
            ...feedback[1],
            id: id(999),
            sourceObservationId: 'conflict',
            jointPain: 0,
            generalReadiness: 'limited',
          },
        ],
      }).action,
    ).toBe('insufficient_evidence');
    expect(evaluate({ now: new Date('2026-12-01') }).action).toBe('insufficient_evidence');
    feedback[1].symptomFlags = ['pain'];
    expect(evaluate({ feedback }).action).toBe('recovery_review');
  });
  it('deduplicates source observations and replays corrections without deleting the originals', () => {
    const { feedback } = scenario();
    const duplicated = { ...feedback[1], id: id(777) };
    expect(evaluate({ feedback: [...feedback, duplicated] }).observationIds).toHaveLength(2);
    const correction = {
      ...feedback[1],
      id: id(778),
      createdAt: now.toISOString(),
      correctsObservationId: feedback[1].id,
      muscles: {
        shoulders: { performance: 'up' as const, recovery: 'ready' as const, soreness: 2 },
      },
    };
    expect(evaluate({ feedback: [...feedback, correction] })).toMatchObject({
      action: 'insufficient_evidence',
      change: null,
    });
    expect(evaluate({ feedback: [...feedback, correction] }).observationIds).not.toContain(
      feedback[1].id,
    );
    expect(feedback).toHaveLength(2);
  });
  it('does not let a positive pump override stagnating performance or adverse tolerance', () => {
    const { feedback } = scenario();
    feedback[1].muscles!.shoulders!.pump = 10;
    expect(evaluate({ feedback }).action).toBe('reduce');
  });
});

async function fixture() {
  const records = new MemoryTrainingRecords();
  await storeProgramSetup({
    records,
    subject: 'owner',
    setup,
    now: monday,
    createId: () => setup.id,
  });
  const data = scenario();
  for (const item of data.exposures) {
    const session = buildSession({
      setup,
      block: createMesoBlock(setup.startedAt, now.toISOString()),
      sessionId: item.sessionId,
      slot: 0,
      logs: [],
      feedback: [],
    });
    await records.push('owner', 'training_sessions', [
      {
        id: item.sessionId,
        record_type: 'workout_session',
        programSetupId: setup.id,
        blockId: 'block-1',
        weekNumber: 1,
        slot: 0,
        status: 'completed',
        prescription: session,
      },
    ]);
    await records.push(
      'owner',
      'logged_sets',
      item.completed.map((log) => ({ ...log, record_type: 'set_log' })),
    );
  }
  await records.push(
    'owner',
    'training_feedback',
    data.feedback.map((item) => ({ ...item, record_type: 'session_feedback' })),
  );
  const base = { records, subject: 'owner', now };
  const create = () => createRecoveryTrial({ ...base, target, requestId: id(900) });
  const decide = (
    decision: 'apply' | 'reject' | 'revert' | 'review',
    expectedRevision: number,
    at = now,
  ) => decideRecoveryTrial({ ...base, now: at, trialId: id(900), expectedRevision, decision });
  const next = (persist = false, at = now, recoveryEnabled = true) =>
    getOrCreateNextWorkout({ ...base, now: at, persist, recoveryEnabled });
  return { records, ...data, base, create, decide, next };
}
const shoulderSets = (result: Awaited<ReturnType<typeof getOrCreateNextWorkout>>) =>
  result.kind === 'workout'
    ? result.session.exercises.find((item) => item.id === target.exerciseId)?.sets
    : null;

describe('reviewed durable recovery loop', () => {
  it('is default-off and evaluation plus proposal creation never mutate the prior plan', async () => {
    expect(adaptiveRecoveryEnabled({})).toBe(false);
    expect(adaptiveRecoveryEnabled({ LYB_ADAPTIVE_RECOVERY_ENABLED: 'true' })).toBe(false);
    const h = await fixture();
    const before = await h.records.listAll('owner');
    expect((await readRecovery({ ...h.base, target })).evaluation.action).toBe('reduce');
    expect(await h.records.listAll('owner')).toEqual(before);
    await h.create();
    expect(shoulderSets(await h.next())).toBe(2);
    expect(await h.create()).toMatchObject({ revision: 0, state: 'proposed' });
    await h.decide('reject', 0);
    expect(shoulderSets(await h.next())).toBe(2);
  });
  it('applies a persisted proposal to the next prescription, survives session replay, and restores future work on revert', async () => {
    const h = await fixture();
    const trial = await h.create();
    expect(trial.baseline[1].completed).toHaveLength(2);
    await h.decide('apply', 0);
    expect(shoulderSets(await h.next(false, now, false))).toBe(2);
    expect(shoulderSets(await h.next())).toBe(1);
    const saved = await h.next(true);
    expect(shoulderSets(saved)).toBe(1);
    expect(shoulderSets(await h.next())).toBe(1);
    expect(shoulderSets(await h.next(false, now, false))).toBe(1);
    await h.decide('revert', 1);
    // Work already started keeps its reviewed prescription; later sessions restore the prior plan.
    expect(shoulderSets(await h.next())).toBe(1);
    if (saved.kind !== 'workout') throw new Error('missing workout');
    const stored = (await h.records.pull('owner', 'training_sessions')).records.find(
      (row) => row.id === saved.session.id,
    )!;
    await h.records.push('owner', 'training_sessions', [{ ...stored, status: 'completed' }]);
    expect(shoulderSets(await h.next(false, new Date('2026-10-19T09:00:00Z')))).toBe(2);
    const replay = await readRecovery({ ...h.base, target });
    expect(replay.trials[0]).toMatchObject({ state: 'reverted', revision: 2 });
    expect(replay.trials[0].history.map((entry) => entry.state)).toEqual([
      'proposed',
      'applied',
      'reverted',
    ]);
    expect(replay.trials[0].inference).toEqual(trial.inference);
  });
  it('reviews the next comparable completed exposure and keeps outcomes separate from intervention approval', async () => {
    const h = await fixture();
    await h.create();
    await h.decide('apply', 0);
    expect((await h.decide('review', 1)).outcome.decision).toBe('inconclusive');
    const nextExposure = exposure(4, new Date('2026-10-14T09:00:00Z'), [10]);
    nextExposure.prescription.sets = 1;
    const session = buildSession({
      setup,
      block: createMesoBlock(setup.startedAt, now.toISOString()),
      sessionId: nextExposure.sessionId,
      slot: 0,
      logs: [],
      feedback: [],
    });
    session.exercises = [nextExposure.prescription];
    await h.records.push('owner', 'training_sessions', [
      {
        id: nextExposure.sessionId,
        record_type: 'workout_session',
        programSetupId: setup.id,
        blockId: 'block-1',
        weekNumber: 1,
        slot: 0,
        status: 'completed',
        prescription: session,
      },
    ]);
    await h.records.push(
      'owner',
      'logged_sets',
      nextExposure.completed.map((log) => ({ ...log, record_type: 'set_log' })),
    );
    await h.records.push('owner', 'training_feedback', [
      { ...observation(nextExposure), record_type: 'session_feedback' },
    ]);
    const reviewed = await h.decide('review', 2, new Date('2026-10-14T10:00:00Z'));
    expect(reviewed).toMatchObject({ state: 'applied', outcome: { decision: 'retain' } });
    expect(reviewed.outcome.observationIds).toContain(observation(nextExposure).id);
    expect(reviewed.history).toHaveLength(4);
  });

  it('applies only to the actual reviewed variant and retains its reduced allocation on replay', async () => {
    const h = await fixture();
    const variantId = 'cable_lateral_raise';
    for (const collection of ['training_sessions', 'logged_sets', 'training_feedback'] as const) {
      const rows = (await h.records.pull('owner', collection)).records;
      for (const row of rows) {
        const payload = JSON.parse(JSON.stringify(row).replaceAll(target.exerciseId, variantId));
        await h.records.push('owner', collection, [payload]);
      }
    }
    await h.records.push('owner', 'training_sessions', [
      {
        id: id(910),
        record_type: 'exercise_swap',
        programSetupId: setup.id,
        blockId: 'block-1',
        sessionId: h.second.sessionId,
        fromExerciseId: target.exerciseId,
        toVariantId: variantId,
      },
    ]);
    const trial = await createRecoveryTrial({
      ...h.base,
      target: { ...target, exerciseId: variantId },
      requestId: id(900),
    });
    expect(trial.inference.action).toBe('reduce');
    await h.decide('apply', 0);
    const saved = await h.next(true);
    expect(
      saved.kind === 'workout' &&
        saved.session.exercises.find((item) => item.id === variantId)?.sets,
    ).toBe(1);
    const replayed = await h.next();
    expect(
      replayed.kind === 'workout' &&
        replayed.session.exercises.find((item) => item.id === variantId)?.sets,
    ).toBe(1);
  });
  it('rejects stale apply after a correction, conflicting decisions, and missing atomic persistence', async () => {
    const h = await fixture();
    await h.create();
    await h.records.push('owner', 'training_feedback', [
      {
        ...h.feedback[1],
        id: id(880),
        record_type: 'session_feedback',
        correctsObservationId: h.feedback[1].id,
      },
    ]);
    await expect(h.decide('apply', 0)).rejects.toThrow('trial_context_changed');
    await h.decide('reject', 0);
    await expect(h.decide('apply', 0)).rejects.toThrow('trial_revision_conflict');
    const unavailable = await fixture();
    unavailable.records.trainingMutations.commitRecoveryTrial = undefined;
    await expect(unavailable.create()).rejects.toThrow('training_mutations_unavailable');
  });
  it('expires the trial at the next block and refuses to apply across deload', async () => {
    const h = await fixture();
    await h.create();
    await h.decide('apply', 0);
    expect(shoulderSets(await h.next(false, new Date('2026-11-09T09:00:00Z')))).toBe(2);
    const stale = await fixture();
    await stale.create();
    await expect(stale.decide('apply', 0, new Date('2026-11-02T09:00:00Z'))).rejects.toThrow(
      'trial_context_changed',
    );
  });
});
