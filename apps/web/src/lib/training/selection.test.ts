import { EXERCISE_CATALOG, type CatalogEquipment } from './catalog';
import { suggestAlternatives } from './alternatives';
import { applyWorkoutAction, logTrainingSet, recordTrainingFeedback } from './commands';
import { MemoryTrainingRecords } from './memory-records.testing';
import { reviewExerciseSelection, exerciseSelectionEnabled } from './selection';
import { CONCERNING_PAIN_MESSAGE } from './pain-policy';
import {
  applyExerciseSwaps,
  learnedExerciseSwaps,
  loadTrainingRecords,
  storeProgramSetup,
} from './service';
import type { ExerciseSelectionContext, Session, TrainingFeedback } from './types';

const subject = 'selection-user';
const now = new Date('2026-10-30T12:00:00.000Z');
const context: ExerciseSelectionContext = {
  gymId: 'Home gym',
  availableEquipment: ['cable', 'adjustable_bench', 'machine', 'dumbbells'],
  excludedConcerns: [],
};
const session: Session = {
  id: '11111111-1111-4111-8111-000000000002',
  week: 1,
  slot: 0,
  pattern: 'A',
  title: 'Arms',
  safetyStop: false,
  explanation: null,
  evidenceIds: [],
  executionRevision: 0,
  executionPaused: false,
  executionEvents: [],
  exercises: [
    {
      id: 'cable_curl',
      name: 'Cable curl',
      primaryMuscle: 'biceps',
      muscleContribution: { biceps: 1 },
      sets: 3,
      repRange: { min: 8, max: 12 },
      targetReps: 8,
      targetRir: 3,
      targetLoadKg: 20,
      loadInstruction: null,
      progression: 'hold',
      evidenceIds: [],
      substitutions: [],
    },
  ],
};
const fatigue: TrainingFeedback = {
  id: 'fatigue',
  sessionId: session.id,
  context: { exerciseId: 'cable_curl', gymId: context.gymId },
  trunkFatigue: 6,
  createdAt: now.toISOString(),
};

async function fixture() {
  const records = new MemoryTrainingRecords();
  const setup = await storeProgramSetup({
    records,
    subject,
    now,
    createId: () => '11111111-1111-4111-8111-000000000001',
    setup: {
      sessionsPerWeek: 5,
      equipment: 'full_gym',
      adultConfirmed: true,
      safetyConfirmed: true,
    },
  });
  await records.push(subject, 'training_sessions', [
    {
      id: session.id,
      record_type: 'workout_session',
      programSetupId: setup.id,
      blockId: 'block',
      status: 'in_progress',
      prescription: session,
      initialPrescription: session,
    },
  ]);
  await records.push(subject, 'training_feedback', [
    { ...fatigue, record_type: 'session_feedback' },
  ]);
  return records;
}

function action(
  records: MemoryTrainingRecords,
  extra: Partial<Parameters<typeof applyWorkoutAction>[0]> = {},
) {
  return applyWorkoutAction({
    records,
    subject,
    now,
    sessionId: session.id,
    eventId: 'swap-1',
    expectedRevision: 0,
    action: {
      kind: 'swap',
      exerciseId: 'cable_curl',
      replacementExerciseId: 'supported_cable_curl',
      selectionContext: context,
    },
    ...extra,
  });
}

describe('curated exercise selection', () => {
  it('requires both rollout switches and leaves the new path off by default', () => {
    expect(exerciseSelectionEnabled({})).toBe(false);
    expect(exerciseSelectionEnabled({ LYB_HYPERTROPHY_COACH_API_ENABLED: 'true' })).toBe(false);
    expect(
      exerciseSelectionEnabled({
        LYB_HYPERTROPHY_COACH_API_ENABLED: 'true',
        LYB_EXERCISE_SELECTION_ENABLED: 'true',
      }),
    ).toBe(true);
  });

  it('reads two distinct levers without changing the plan or storing a proposal', async () => {
    const records = await fixture();
    const snapshot = await loadTrainingRecords(records, subject);
    const before = JSON.stringify(snapshot);
    const review = reviewExerciseSelection(snapshot, session, 'cable_curl', context)!;
    expect(review.status).toBe('suggested');
    expect(review.options).toHaveLength(2);
    expect(review.options.map((item) => item.reason)).toEqual([
      'supported_exercise_trial',
      'supported_setup_trial',
    ]);
    expect(review.options.every((item) => item.setup.primaryMuscle === 'biceps')).toBe(true);
    expect(JSON.stringify(snapshot)).toBe(before);
    expect(await learnedExerciseSwaps(snapshot)).toEqual([]);
  });

  it.each([
    { jointPain: 2 },
    { symptomFlags: ['neurologic'] as TrainingFeedback['symptomFlags'] },
    { symptomFlags: ['pain'] as TrainingFeedback['symptomFlags'] },
  ])(
    'offers no swap for symptoms %p, including shoulder pain during an arm movement',
    async (symptoms) => {
      const records = await fixture();
      await records.push(subject, 'training_feedback', [
        {
          ...fatigue,
          ...symptoms,
          id: 'symptoms',
          record_type: 'session_feedback',
          symptomNote: 'Shoulder hurts',
          createdAt: '2026-10-30T12:01:00.000Z',
        },
      ]);
      const snapshot = await loadTrainingRecords(records, subject);
      expect(reviewExerciseSelection(snapshot, session, 'cable_curl', context)).toMatchObject({
        status: 'symptom_safety',
        options: [],
        message: CONCERNING_PAIN_MESSAGE,
      });
      expect(await action(records)).toEqual({ kind: 'no_eligible_substitution' });
    },
  );

  it('has no symptom or fatigue assumptions for missing feedback', async () => {
    const records = await fixture();
    const snapshot = await loadTrainingRecords(records, subject);
    expect(
      reviewExerciseSelection({ ...snapshot, feedback: [] }, session, 'cable_curl', context),
    ).toMatchObject({ status: 'not_enough_evidence', options: [] });
  });

  it('does not invent an alternate gym station or use blocked floor ROM', () => {
    const input = {
      exerciseId: 'dumbbell_curl',
      feedback: [{ ...fatigue, context: { exerciseId: 'dumbbell_curl' } }],
      previousSwaps: [],
      allowTrials: true,
    };
    const available = new Set<CatalogEquipment>(['dumbbells']);
    expect(
      suggestAlternatives(input, EXERCISE_CATALOG, available).sameExerciseSetup?.variantId,
    ).toBe('lying_dumbbell_curl');
    expect(
      suggestAlternatives(
        { ...input, excludedConcerns: ['floor_rom_blocked'], beltRequested: true },
        EXERCISE_CATALOG,
        available,
      ),
    ).toMatchObject({ status: 'no_eligible_alternative' });
    const alternate = suggestAlternatives(
      { ...input, exerciseId: 'cable_curl', feedback: [fatigue] },
      EXERCISE_CATALOG,
      available,
    );
    expect(alternate.sameExerciseSetup).toBeNull();
    expect(alternate.differentExercise?.variantId).not.toBe('preacher_machine_curl');
  });

  it('requires approval, preserves completed identities and starts a separate load history', async () => {
    const records = await fixture();
    const logged = await logTrainingSet({
      records,
      subject,
      now,
      set: {
        sessionId: session.id,
        exerciseId: 'cable_curl',
        setNumber: 1,
        reps: 8,
        loadKg: 20,
        rir: 3,
      },
    });
    expect(logged.kind).toBe('logged');
    const result = await action(records);
    expect(result.kind).toBe('updated');
    if (result.kind !== 'updated') throw new Error(result.kind);
    expect(result.session.exercises.map((item) => [item.id, item.sets])).toEqual([
      ['cable_curl', 1],
      ['supported_cable_curl', 2],
    ]);
    expect(result.session.exercises[1]).toMatchObject({ targetLoadKg: null, progression: 'hold' });
    expect(result.session.loggedSets).toHaveLength(1);
    expect(result.session.executionEvents[0].selectionContext).toEqual(context);
    expect(await action(records)).toEqual(result); // Lost-response replay is not another swap.
    expect((await action(records, { eventId: 'stale' })).kind).toBe('stale_revision');
    const undone = await action(records, {
      eventId: 'undo',
      expectedRevision: 1,
      action: { kind: 'restore_swap', swapEventId: 'swap-1' },
    });
    expect(undone.kind).toBe('updated');
    if (undone.kind === 'updated') expect(undone.session.exercises).toEqual(session.exercises);
    expect(learnedExerciseSwaps(await loadTrainingRecords(records, subject))).toEqual([]);
  });

  it('refuses a forged candidate, newly unavailable station and undo after replacement work', async () => {
    const records = await fixture();
    expect(
      (
        await action(records, {
          action: {
            kind: 'swap',
            exerciseId: 'cable_curl',
            replacementExerciseId: 'leg_press',
            selectionContext: context,
          },
        })
      ).kind,
    ).toBe('no_eligible_substitution');
    expect(
      (
        await action(records, {
          action: {
            kind: 'swap',
            exerciseId: 'cable_curl',
            replacementExerciseId: 'supported_cable_curl',
            selectionContext: { ...context, availableEquipment: ['dumbbells'] },
          },
        })
      ).kind,
    ).toBe('no_eligible_substitution');
    expect((await action(records)).kind).toBe('updated');
    await logTrainingSet({
      records,
      subject,
      now,
      set: {
        sessionId: session.id,
        exerciseId: 'supported_cable_curl',
        setNumber: 1,
        reps: 8,
        loadKg: 5,
        rir: 3,
      },
    });
    expect(
      (
        await action(records, {
          eventId: 'undo',
          expectedRevision: 1,
          action: { kind: 'restore_swap', swapEventId: 'swap-1' },
        })
      ).kind,
    ).toBe('no_eligible_substitution');
  });

  it('retains an approved choice only after two independent usable responses and respects correction', async () => {
    const records = await fixture();
    await action(records);
    const positive = (day: number): TrainingFeedback => ({
      id: `positive-${day}`,
      sessionId: `session-${day}`,
      jointPain: 0,
      trunkFatigue: 0,
      stability: 'stable',
      targetMuscleQuality: 'good',
      performance: 'stable',
      context: { exerciseId: 'supported_cable_curl', gymId: context.gymId, romRestriction: 'none' },
      createdAt: `2026-10-${day}T12:00:00.000Z`,
    });
    const snapshot = await loadTrainingRecords(records, subject);
    expect(learnedExerciseSwaps({ ...snapshot, feedback: [positive(29)] })).toEqual([]);
    const learned = learnedExerciseSwaps({ ...snapshot, feedback: [positive(29), positive(30)] });
    expect(learned).toHaveLength(1);
    expect(applyExerciseSwaps(session, learned, []).exercises[0].id).toBe('supported_cable_curl');
    const corrected = {
      ...positive(30),
      id: 'corrected',
      correctsObservationId: 'positive-30',
      trunkFatigue: 5,
      createdAt: '2026-10-31T12:00:00.000Z',
    };
    expect(
      learnedExerciseSwaps({ ...snapshot, feedback: [positive(29), positive(30), corrected] }),
    ).toEqual([]);
    expect(
      learnedExerciseSwaps({
        ...snapshot,
        feedback: [positive(29), { ...positive(30), jointPain: undefined }],
      }),
    ).toEqual([]);
    expect(
      learnedExerciseSwaps({
        ...snapshot,
        feedback: [
          positive(29),
          {
            ...positive(30),
            context: {
              ...positive(30).context,
              gymId: 'Alternate gym',
              availableEquipment: ['dumbbells'],
            },
          },
        ],
      }),
    ).toEqual([]);
    expect(
      learnedExerciseSwaps({
        ...snapshot,
        feedback: [
          positive(29),
          {
            ...positive(30),
            context: { ...positive(30).context, availableEquipment: ['dumbbells'] },
          },
        ],
      }),
    ).toEqual([]);
  });

  it('records and corrects separate response dimensions without replacing other exercise observations', async () => {
    const records = await fixture();
    const submit = (exerciseId: string, id: string) =>
      recordTrainingFeedback({
        records,
        subject,
        now,
        createId: () => id,
        feedback: {
          sessionId: session.id,
          context: { exerciseId },
          stability: 'unstable',
          targetMuscleQuality: 'poor',
          generalExhaustion: 2,
        },
      });
    expect((await submit('cable_curl', 'one')).kind).toBe('recorded');
    expect((await submit('preacher_machine_curl', 'two')).kind).toBe('recorded');
    const snapshot = await loadTrainingRecords(records, subject);
    expect(
      snapshot.feedback.find((item) => item.id === 'two')?.correctsObservationId,
    ).toBeUndefined();
    expect(snapshot.feedback.find((item) => item.id === 'one')).toMatchObject({
      stability: 'unstable',
      targetMuscleQuality: 'poor',
      generalExhaustion: 2,
    });
    expect(snapshot.feedback.find((item) => item.id === 'one')?.trunkFatigue).toBeUndefined();
  });
});
