import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { catalogVariantById, isEligibleVariant } from './catalog';
import { MemoryTrainingRecords } from './memory-records.testing';
import { getOrCreateNextWorkout, storeProgramSetup } from './service';
import {
  SETUP_DIMENSIONS,
  ineligibleAlternatives,
  reloadApprovedSwap,
  rollbackSavedSwap,
  saveApprovedSwap,
  storeApprovedSwap,
  type ApprovedSwapSubmission,
} from './swap-persistence';

const subject = 'swap-persistence-user';
const now = new Date('2026-11-19T12:00:00.000Z');
const later = new Date('2026-11-19T12:05:00.000Z');

const submission = {
  gymId: 'north-gym',
  approvedExerciseId: 'incline_dumbbell_curl',
  setupId: 'incline_dumbbell_curl',
  previousExerciseId: 'dumbbell_curl',
  confirmedEquipment: ['dumbbells', 'adjustable_bench'],
  dimensions: {
    benchClearance: 45,
    cableLine: null,
    floorClearance: undefined,
  },
  responses: {
    trunkFatigue: 4,
    jointDiscomfort: null,
    symptomNote: 'Low back felt tight after the set.',
  },
  narrative: 'Persistent medical history that must not be stored.',
  latitude: 37.77,
  longitude: -122.42,
  location: { lat: 37.77, lon: -122.42 },
  confidence: 'high',
  axialLoadCleared: true,
  clearedAxialLoad: true,
  spinalLoad: 0,
  ineligibleAlternativeIds: ['preacher_machine_curl'],
} as ApprovedSwapSubmission;

async function enrolled() {
  const records = new MemoryTrainingRecords();
  await storeProgramSetup({
    records,
    subject,
    setup: {
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment: 'dumbbells',
    },
    now,
    createId: () => '11111111-1111-4111-8111-000000000099',
  });
  const workout = await getOrCreateNextWorkout({ records, subject, now, persist: true });
  if (workout.kind !== 'workout') throw new Error(workout.kind);
  return { records, workout };
}

describe('approved swap persistence', () => {
  it('reloads an approved swap, submitted dimensions and equipment, and leaves omitted dimensions unknown', async () => {
    const { records, workout } = await enrolled();
    const saved = await saveApprovedSwap({
      records,
      subject,
      sessionId: workout.session.id,
      now,
      submission,
    });
    expect(saved).toMatchObject({
      gymId: 'north-gym',
      approvedExerciseId: 'incline_dumbbell_curl',
      setupId: 'incline_dumbbell_curl',
      confirmedEquipment: ['dumbbells', 'adjustable_bench'],
      previousExerciseId: 'dumbbell_curl',
      dimensions: { benchClearance: 45 },
      responses: { trunkFatigue: 4 },
    });
    const stored = (await records.pull(subject, 'training_sessions')).records.find(
      (record) => record.id === workout.session.id,
    );
    const reloaded = reloadApprovedSwap(JSON.parse(JSON.stringify(stored?.swapPersistence)));
    expect(reloaded?.dimensions).toEqual({ benchClearance: 45 });
    expect(reloaded?.confirmedEquipment).toEqual(['dumbbells', 'adjustable_bench']);
    expect(reloaded?.responses).toEqual({ trunkFatigue: 4 });
    for (const key of SETUP_DIMENSIONS) {
      if (key === 'benchClearance') continue;
      expect(Object.hasOwn(reloaded?.dimensions ?? {}, key)).toBe(false);
    }
    expect(reloaded?.dimensions.cableLine).toBeUndefined();
    expect(reloaded?.dimensions.floorClearance).toBeUndefined();
    expect(reloaded?.dimensions.rangeOfMotion).toBeUndefined();
    expect(reloaded?.responses.jointDiscomfort).toBeUndefined();
    expect(JSON.stringify(reloaded?.dimensions)).not.toContain(':0');
    expect(JSON.stringify(reloaded)).not.toMatch(
      /narrative|symptomNote|latitude|longitude|location|confidence|axialLoad|spinalLoad|ineligible/i,
    );
  });

  it('rolls back to the prior prescription in one action and the next read uses the restored exercise', async () => {
    const { records, workout } = await enrolled();
    expect(workout.session.exercises.map((exercise) => exercise.id)).toContain('dumbbell_curl');
    expect(
      await saveApprovedSwap({
        records,
        subject,
        sessionId: workout.session.id,
        now,
        submission,
      }),
    ).toMatchObject({ approvedExerciseId: 'incline_dumbbell_curl' });

    const swapped = await getOrCreateNextWorkout({ records, subject, now, persist: true });
    if (swapped.kind !== 'workout') throw new Error(swapped.kind);
    expect(swapped.session.exercises.map((exercise) => exercise.id)).toContain(
      'incline_dumbbell_curl',
    );
    expect(swapped.session.exercises.map((exercise) => exercise.id)).not.toContain('dumbbell_curl');

    const update = jest.spyOn(records, 'updateTrainingSession');
    const rolled = await rollbackSavedSwap({
      records,
      subject,
      sessionId: workout.session.id,
      now: later,
    });
    expect(update).toHaveBeenCalledTimes(1);
    expect(rolled).toMatchObject({
      rolledBack: true,
      previousExerciseId: 'dumbbell_curl',
    });

    const restored = await getOrCreateNextWorkout({ records, subject, now: later, persist: true });
    if (restored.kind !== 'workout') throw new Error(restored.kind);
    expect(restored.session.exercises.map((exercise) => exercise.id)).toContain('dumbbell_curl');
    expect(restored.session.exercises.map((exercise) => exercise.id)).not.toContain(
      'incline_dumbbell_curl',
    );
  });

  it('does not treat one tolerated supported curl as ineligibility or a belt as cleared axial load', () => {
    const tolerated = storeApprovedSwap(
      {
        gymId: 'north-gym',
        approvedExerciseId: 'supported_cable_curl',
        setupId: 'supported_cable_curl',
        previousExerciseId: 'cable_curl',
        confirmedEquipment: ['cable', 'adjustable_bench', 'dumbbells', 'machine'],
        responses: { tolerated: true, trunkFatigue: 0 },
        confidence: 'high',
        ineligibleAlternativeIds: ['preacher_machine_curl', 'incline_dumbbell_curl'],
      } as ApprovedSwapSubmission,
      { sessionId: '11111111-1111-4111-8111-000000000098', updatedAt: now.toISOString() },
    );
    expect(tolerated?.responses).toEqual({ tolerated: true, trunkFatigue: 0 });
    expect(tolerated).not.toHaveProperty('confidence');
    expect(ineligibleAlternatives(tolerated!)).toEqual([]);
    for (const id of ['preacher_machine_curl', 'incline_dumbbell_curl', 'lying_dumbbell_curl']) {
      expect(ineligibleAlternatives(tolerated!).includes(id)).toBe(false);
      expect(
        isEligibleVariant(catalogVariantById(id)!, {
          available: new Set(tolerated!.confirmedEquipment),
        }),
      ).toBe(true);
    }
    const serialized = JSON.stringify(tolerated);
    expect(serialized).not.toMatch(/confidence|ineligible|high/);

    const belted = storeApprovedSwap(
      {
        gymId: 'north-gym',
        approvedExerciseId: 'supported_cable_curl',
        setupId: 'supported_cable_curl',
        previousExerciseId: 'cable_curl',
        confirmedEquipment: ['cable', 'adjustable_bench'],
        responses: { beltRequested: true, symptomsPersist: true, jointDiscomfort: 6 },
        axialLoadCleared: true,
        clearedAxialLoad: true,
        spinalLoad: 0,
      } as ApprovedSwapSubmission,
      { sessionId: '11111111-1111-4111-8111-000000000098', updatedAt: now.toISOString() },
    );
    expect(belted?.responses).toEqual({
      beltRequested: true,
      symptomsPersist: true,
      jointDiscomfort: 6,
    });
    const reloaded = reloadApprovedSwap(JSON.parse(JSON.stringify(belted)));
    expect(reloaded?.responses.beltRequested).toBe(true);
    expect(reloaded?.responses.symptomsPersist).toBe(true);
    expect(JSON.stringify(reloaded)).not.toMatch(/axialLoad|spinalLoad|clearedAxial/i);
    expect(reloadApprovedSwap({ ...belted, axialLoadCleared: true })).toBeNull();
  });

  it('ships no off-device export and no learning job', () => {
    const source = readFileSync(resolve(__dirname, 'swap-persistence.ts'), 'utf8');
    expect(source).not.toMatch(
      /\b(?:fetch|axios|setInterval|setTimeout|geolocation|XMLHttpRequest|preferenceLearning|preference-learning|learningJob|offDevice|exportSync|cron)\b/,
    );
    expect(source).not.toMatch(
      /from\s+['"][^'"]*(?:mail|analytics|sentry|openai|axios|node-fetch)/,
    );
    const api = [
      'SETUP_DIMENSIONS',
      'ineligibleAlternatives',
      'latestSwapState',
      'readNextPrescriptionExercise',
      'reloadApprovedSwap',
      'rollbackApprovedSwap',
      'rollbackSavedSwap',
      'saveApprovedSwap',
      'storeApprovedSwap',
    ];
    expect(
      Object.keys(require('./swap-persistence') as Record<string, unknown>)
        .filter((key) => api.includes(key) || /export|learn|job|sync/i.test(key))
        .sort(),
    ).toEqual([...api].sort());
  });
});
