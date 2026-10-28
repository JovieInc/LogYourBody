import {
  EXERCISE_CATALOG,
  type CatalogEquipment,
  catalogVariantMetadataSchema,
  catalogVariantSchema,
  catalogVariantSeedSchema,
  catalogVariantById,
  isEligibleVariant,
  missingEquipment,
  profileEquipment,
  queryExerciseLibrary,
  resolveAvailableEquipment,
  substitutionCandidates,
  variantToleranceTagsSchema,
} from './catalog';
import variantSeed from './catalog-variant-seed.json';
import { swapExercise } from './commands';
import { MemoryTrainingRecords } from './memory-records.testing';
import { getOrCreateNextWorkout, storeProgramSetup } from './service';

const NOW = new Date('2026-01-10T12:00:00.000Z');
const dumbbellSet = profileEquipment('dumbbells');
const fullGymSet = profileEquipment('full_gym');

describe('curated exercise variant contract', () => {
  it('validates the whole library and attaches all 25 seed records to existing IDs', () => {
    const seed = catalogVariantSeedSchema.parse(variantSeed);
    expect(seed).toHaveLength(25);
    expect(new Set(EXERCISE_CATALOG.map((entry) => entry.id)).size).toBe(EXERCISE_CATALOG.length);
    for (const entry of EXERCISE_CATALOG) {
      expect(catalogVariantSchema.parse(entry)).toEqual(entry);
    }
    for (const { id, ...metadata } of seed) {
      const entry = catalogVariantById(id)!;
      expect(entry.variantMetadata).toEqual(metadata);
      expect(entry.requires.length).toBeGreaterThan(0);
      expect(entry.bodyPosition.length).toBeGreaterThan(0);
    }
    expect(EXERCISE_CATALOG.filter((entry) => entry.variantMetadata)).toHaveLength(25);
    expect(catalogVariantById('dead_bug')?.variantMetadata).toBeUndefined();
    expect([...new Set(seed.map((entry) => entry.targetRegion))].sort()).toEqual([
      'biceps',
      'calves',
      'glutes',
      'hamstrings',
      'lateral_delts',
      'lats',
      'quads',
      'triceps',
      'upper_chest',
    ]);
  });

  it('rejects duplicate seed IDs, invalid target regions, support and equipment', () => {
    expect(catalogVariantSeedSchema.safeParse([variantSeed[0], variantSeed[0]]).success).toBe(
      false,
    );
    const entry = catalogVariantById('incline_dumbbell_press')!;
    for (const change of [
      { primaryMuscle: 'biceps' },
      { variantMetadata: { ...entry.variantMetadata, targetRegion: 'whole_body' } },
      { variantMetadata: { ...entry.variantMetadata, support: 'arm' } },
      { variantMetadata: { ...entry.variantMetadata, romSetupCaveat: ' ' } },
      { requires: ['unknown_machine'] },
    ]) {
      expect(catalogVariantSchema.safeParse({ ...entry, ...change }).success).toBe(false);
    }
  });

  it('rejects unknown fields throughout catalog records and the raw seed', () => {
    const entry = catalogVariantById('supported_cable_curl')!;
    for (const change of [
      { sfrScore: 9 },
      { trunkDemand: { ...entry.trunkDemand, fatigueScore: 0 } },
      { pulley: { ...entry.pulley, invented: true } },
      { muscleContribution: { biceps: 1, invented: 1 } },
      { variantMetadata: { ...entry.variantMetadata, medicalClaim: 'invented' } },
    ]) {
      expect(catalogVariantSchema.safeParse({ ...entry, ...change }).success).toBe(false);
    }
    expect(
      catalogVariantSeedSchema.safeParse([{ ...variantSeed[0], invented: true }]).success,
    ).toBe(false);
    expect(
      catalogVariantMetadataSchema.safeParse({
        ...entry.variantMetadata,
        bodyPosition: 'duplicate setup field',
      }).success,
    ).toBe(false);
  });

  it('requires four separate, editable tag fields and never accepts a combined score', () => {
    const tags = variantSeed[0].toleranceTags;
    expect(Object.keys(tags).sort()).toEqual([
      'axialTrunkFatigue',
      'jointDiscomfort',
      'rom',
      'stability',
    ]);
    for (const field of Object.keys(tags)) {
      const missing: Record<string, unknown> = { ...tags };
      delete missing[field];
      expect(variantToleranceTagsSchema.safeParse(missing).success).toBe(false);
      expect(variantToleranceTagsSchema.safeParse({ ...tags, [field]: 4 }).success).toBe(false);
    }
    expect(variantToleranceTagsSchema.safeParse({ ...tags, toleranceScore: 8 }).success).toBe(
      false,
    );
    const edited = variantToleranceTagsSchema.parse({
      ...tags,
      jointDiscomfort: ['user prefers a different grip'],
      rom: ['user selected shorter range'],
    });
    expect(edited.axialTrunkFatigue).toEqual(tags.axialTrunkFatigue);
    expect(edited.stability).toEqual(tags.stability);
    expect(edited.jointDiscomfort).toEqual(['user prefers a different grip']);
    expect(edited.rom).toEqual(['user selected shorter range']);
    expect(variantSeed[0].toleranceTags.jointDiscomfort).toEqual([]);
  });

  it('distinguishes torso contact from thigh and arm anchoring', () => {
    expect(catalogVariantById('chest_supported_dumbbell_row')?.variantMetadata?.support).toBe(
      'chest',
    );
    expect(catalogVariantById('incline_dumbbell_curl')?.variantMetadata?.support).toBe('back');
    expect(catalogVariantById('lat_pulldown')?.variantMetadata?.support).toBe('none');
    expect(catalogVariantById('preacher_machine_curl')?.variantMetadata?.support).toBe('none');
  });
});

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

describe('exercise library gym filter', () => {
  it('allows the whole library until a gym equipment set is confirmed', () => {
    expect(queryExerciseLibrary(null).map((variant) => variant.id)).toEqual(
      EXERCISE_CATALOG.map((variant) => variant.id),
    );
    const confirmed = new Set<CatalogEquipment>(['dumbbells', 'bodyweight']);
    const ids = queryExerciseLibrary(confirmed).map((variant) => variant.id);
    expect(ids).toContain('dumbbell_curl');
    expect(ids).not.toContain('cable_curl');
    expect(ids).not.toContain('smith_incline_press');
    expect(queryExerciseLibrary(new Set()).map((variant) => variant.id)).toEqual([]);
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
