import {
  catalogVariantById,
  isEligibleVariant,
  missingEquipment,
  profileEquipment,
  resolveAvailableEquipment,
  substitutionCandidates,
} from './catalog';
import { swapExercise } from './commands';
import { MemoryTrainingRecords } from './memory-records.testing';
import { getOrCreateNextWorkout, storeProgramSetup } from './service';

const NOW = new Date('2026-01-10T12:00:00.000Z');
const dumbbellSet = profileEquipment('dumbbells');
const fullGymSet = profileEquipment('full_gym');

describe('exercise catalog eligibility', () => {
  it('fails closed when required equipment is not provably available', () => {
    const cable = catalogVariantById('cable_curl')!;
    expect(missingEquipment(cable, dumbbellSet)).toEqual(['cable']);
    expect(isEligibleVariant(cable, { available: dumbbellSet })).toBe(false);
    expect(isEligibleVariant(cable, { available: fullGymSet })).toBe(true);
  });

  it('does not assume specialty items under an inherited full-gym preset', () => {
    const ezBar = catalogVariantById('ez_bar_curl')!;
    expect(isEligibleVariant(ezBar, { available: fullGymSet })).toBe(false);
    const declared = resolveAvailableEquipment({
      profile: 'full_gym',
      declared: ['ez_bar'],
    });
    expect(isEligibleVariant(ezBar, { available: declared })).toBe(true);
  });

  it('does not treat a Smith machine as part of the full-gym preset', () => {
    const smith = catalogVariantById('smith_machine_incline_press')!;
    expect(smith.name).toBe('Smith machine incline press');
    expect(smith.requires).toEqual(['smith_machine', 'adjustable_bench']);
    expect(missingEquipment(smith, fullGymSet)).toEqual(['smith_machine']);
    expect(isEligibleVariant(smith, { available: fullGymSet })).toBe(false);
    const declared = resolveAvailableEquipment({
      profile: 'full_gym',
      declared: ['smith_machine'],
    });
    expect(isEligibleVariant(smith, { available: declared })).toBe(true);
  });

  it('fails eligibility when a bench is unavailable for the session only', () => {
    const incline = catalogVariantById('incline_dumbbell_curl')!;
    const sessionOnly = resolveAvailableEquipment({
      profile: 'dumbbells',
      sessionUnavailable: [],
    });
    expect(isEligibleVariant(incline, { available: sessionOnly })).toBe(false);
    const gymNoBench = resolveAvailableEquipment({
      profile: 'full_gym',
      sessionUnavailable: ['adjustable_bench'],
    });
    expect(isEligibleVariant(incline, { available: gymNoBench })).toBe(false);
    expect(isEligibleVariant(incline, { available: fullGymSet })).toBe(true);
  });

  it('honors hard exclusions regardless of equipment', () => {
    const rdl = catalogVariantById('dumbbell_romanian_deadlift')!;
    expect(isEligibleVariant(rdl, { available: dumbbellSet })).toBe(true);
    expect(
      isEligibleVariant(rdl, {
        available: dumbbellSet,
        excludedConcerns: ['low_back_symptoms'],
      }),
    ).toBe(false);
  });
});

describe('substitution candidates', () => {
  it('ranks supported variants first for the biceps low-trunk scenario', () => {
    const candidates = substitutionCandidates({
      primaryMuscle: 'biceps',
      currentExerciseId: 'dumbbell_curl',
      currentContribution: { biceps: 1 },
      available: dumbbellSet,
      preferTorsoSupport: true,
      maxTrunkDemand: 'low',
    });
    expect(candidates.map((variant) => variant.id)).toContain('lying_dumbbell_curl');
    expect(candidates[0]).toMatchObject({ id: 'lying_dumbbell_curl', torsoSupport: 'supported' });
    expect(candidates.every((variant) => !variant.requires.includes('cable'))).toBe(true);
    expect(candidates.every((variant) => !variant.requires.includes('ez_bar'))).toBe(true);
  });

  it('offers no feasible alternative when nothing eligible remains', () => {
    const candidates = substitutionCandidates({
      primaryMuscle: 'hamstrings',
      currentExerciseId: 'dumbbell_romanian_deadlift',
      currentContribution: { hamstrings: 1, glutes: 0.5 },
      available: dumbbellSet,
      excludedConcerns: ['low_back_symptoms'],
    });
    expect(candidates).toEqual([]);
  });
});

async function enrolledHarness(equipment: 'dumbbells' | 'full_gym' = 'dumbbells') {
  const records = new MemoryTrainingRecords();
  let nextId = 1;
  const setup = await storeProgramSetup({
    records,
    subject: 'subject-a',
    setup: {
      adultConfirmed: true,
      safetyConfirmed: true,
      sessionsPerWeek: 2,
      equipment,
    },
    now: NOW,
    createId: () => `11111111-1111-4111-8111-${String(nextId++).padStart(12, '0')}`,
  });
  const first = await getOrCreateNextWorkout({ records, subject: 'subject-a', now: NOW });
  if (first.kind !== 'workout') throw new Error(`expected a workout, got ${first.kind}`);
  return { records, setup, session: first.session };
}

describe('swapExercise', () => {
  it('swaps a movement to a supported variant and persists it for the block', async () => {
    const { records, session } = await enrolledHarness();
    const curl = session.exercises.find((item) => item.id === 'dumbbell_curl')!;

    const result = await swapExercise({
      records,
      subject: 'subject-a',
      now: NOW,
      swap: {
        sessionId: session.id,
        exerciseId: curl.id,
        preferTorsoSupport: true,
        maxTrunkDemand: 'low',
      },
    });
    expect(result.kind).toBe('swapped');
    if (result.kind !== 'swapped') return;
    expect(result.exercise.id).toBe('lying_dumbbell_curl');
    expect(result.exercise.primaryMuscle).toBe('biceps');
    expect(result.exercise.sets).toBe(curl.sets);
    expect(result.exercise.repRange).toEqual(curl.repRange);
    expect(result.exercise.targetRir).toBe(curl.targetRir);

    const again = await getOrCreateNextWorkout({ records, subject: 'subject-a', now: NOW });
    expect(again.kind).toBe('workout');
    if (again.kind !== 'workout') return;
    const stillSwapped = again.session.exercises.find((item) => item.primaryMuscle === 'biceps')!;
    expect(stillSwapped.id).toBe('lying_dumbbell_curl');

    const nextWeek = await getOrCreateNextWorkout({
      records,
      subject: 'subject-a',
      now: new Date('2026-01-20T12:00:00.000Z'),
    });
    expect(nextWeek.kind).toBe('workout');
    if (nextWeek.kind !== 'workout') return;
    expect(nextWeek.session.exercises.map((item) => item.id)).toContain('lying_dumbbell_curl');
    expect(nextWeek.session.exercises.map((item) => item.id)).not.toContain('dumbbell_curl');
  });

  it('rejects a variant whose equipment is not provably available', async () => {
    const { records, session } = await enrolledHarness();
    const result = await swapExercise({
      records,
      subject: 'subject-a',
      now: NOW,
      swap: {
        sessionId: session.id,
        exerciseId: 'dumbbell_curl',
        toVariantId: 'cable_curl',
      },
    });
    expect(result).toEqual({ kind: 'variant_ineligible', missing: ['cable'] });
  });

  it('rejects an EZ-bar variant for an inherited full-gym preset', async () => {
    const { records, session } = await enrolledHarness('full_gym');
    const result = await swapExercise({
      records,
      subject: 'subject-a',
      now: NOW,
      swap: {
        sessionId: session.id,
        exerciseId: 'cable_curl',
        toVariantId: 'ez_bar_curl',
      },
    });
    expect(result).toEqual({ kind: 'variant_ineligible', missing: ['ez_bar'] });
  });

  it('fails when no feasible alternative exists', async () => {
    const { records, session } = await enrolledHarness();
    const result = await swapExercise({
      records,
      subject: 'subject-a',
      now: NOW,
      swap: {
        sessionId: session.id,
        exerciseId: 'dumbbell_romanian_deadlift',
        excludedConcerns: ['low_back_symptoms'],
      },
    });
    expect(result.kind).toBe('no_feasible_alternative');
  });
});
