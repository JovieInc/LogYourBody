import variantSeed from './catalog-variant-seed.json';
import {
  catalogVariantSchema,
  catalogVariantSeedSchema,
  CATALOG_EQUIPMENT,
  type CatalogEquipment,
  type CatalogVariant,
  type TrunkDemandLevel,
} from './catalog-schema';
import { BASE_CATALOG_VARIANTS } from './catalog-variants-base';
import { REVIEWED_CATALOG_VARIANTS } from './catalog-variants-reviewed';
import { type Equipment, type MuscleContribution, type MuscleGroup } from './types';

export * from './catalog-schema';

// Extend the existing IDs and setup fields rather than creating a second library.
const baseCatalog: CatalogVariant[] = [...BASE_CATALOG_VARIANTS, ...REVIEWED_CATALOG_VARIANTS];

const metadataById = new Map(
  catalogVariantSeedSchema.parse(variantSeed).map(({ id, ...metadata }) => [id, metadata]),
);
for (const id of metadataById.keys()) {
  if (!baseCatalog.some((variant) => variant.id === id))
    throw new Error(`Unknown catalog variant: ${id}`);
}
export const EXERCISE_CATALOG: CatalogVariant[] = baseCatalog.map((variant) =>
  catalogVariantSchema.parse({ ...variant, variantMetadata: metadataById.get(variant.id) }),
);

const catalogById = new Map(EXERCISE_CATALOG.map((variant) => [variant.id, variant]));

export function catalogVariantById(id: string): CatalogVariant | undefined {
  return catalogById.get(id);
}

const SHARED_LOAD_IMPLEMENTS = ['barbell', 'ez_bar', 'smith', 'machine', 'cable'] as const;

/** Dumbbell-only variants name the weight of the implement in one hand.
 * Bars, machines, cables, and Smith rails do not establish that convention. */
export function establishedLoadAccounting(exerciseId: string): 'per_hand' | undefined {
  const variant = catalogVariantById(exerciseId);
  if (!variant?.requires.includes('dumbbells')) return undefined;
  if (
    variant.requires.some((item) => (SHARED_LOAD_IMPLEMENTS as readonly string[]).includes(item))
  ) {
    return undefined;
  }
  return 'per_hand';
}

/** Standard inventory each profile can prove. Specialty items (an EZ bar, a
 * Smith machine) are never assumed; a full-gym preset alone cannot prove them. */
export function profileEquipment(profile: Equipment): Set<CatalogEquipment> {
  return new Set<CatalogEquipment>(
    profile === 'full_gym'
      ? ['dumbbells', 'barbell', 'cable', 'machine', 'bench', 'adjustable_bench', 'bodyweight']
      : ['dumbbells', 'bodyweight'],
  );
}

export function resolveAvailableEquipment(input: {
  profile: Equipment;
  /** Extra items the user has explicitly confirmed available. */
  declared?: readonly string[];
  /** Items unavailable for this session only; never rewrites stored preferences. */
  sessionUnavailable?: readonly string[];
}): Set<CatalogEquipment> {
  const available = profileEquipment(input.profile);
  for (const item of input.declared ?? []) {
    if ((CATALOG_EQUIPMENT as readonly string[]).includes(item)) {
      available.add(item as CatalogEquipment);
    }
  }
  for (const item of input.sessionUnavailable ?? []) available.delete(item as CatalogEquipment);
  return available;
}

export function missingEquipment(
  variant: CatalogVariant,
  available: ReadonlySet<CatalogEquipment>,
): CatalogEquipment[] {
  return variant.requires.filter((item) => !available.has(item));
}

/** `equipment === null` means no gym is confirmed, so every variant stays available.
 * A set is the active gym's saved equipment. An empty set matches nothing that requires an item.
 * Specialty equipment is included only when the user saved it on that gym. */
export function queryExerciseLibrary(
  equipment: ReadonlySet<CatalogEquipment> | null,
): CatalogVariant[] {
  if (equipment === null) return [...EXERCISE_CATALOG];
  return EXERCISE_CATALOG.filter((variant) => missingEquipment(variant, equipment).length === 0);
}

export function isEligibleVariant(
  variant: CatalogVariant,
  input: {
    available: ReadonlySet<CatalogEquipment>;
    excludedConcerns?: readonly string[];
    excludedExerciseIds?: readonly string[];
  },
): boolean {
  if (input.excludedExerciseIds?.includes(variant.id)) return false;
  if (missingEquipment(variant, input.available).length > 0) return false;
  const excluded = new Set(input.excludedConcerns ?? []);
  return !variant.exclusions.some((concern) => excluded.has(concern));
}

function contributionDistance(a: MuscleContribution, b: MuscleContribution): number {
  const muscles = new Set([...Object.keys(a), ...Object.keys(b)]);
  let distance = 0;
  for (const muscle of muscles) {
    distance += Math.abs(
      Number(a[muscle as MuscleGroup] ?? 0) - Number(b[muscle as MuscleGroup] ?? 0),
    );
  }
  return distance;
}

const TRUNK_ORDER: Record<TrunkDemandLevel, number> = { low: 0, moderate: 1, high: 2 };

/** Deterministic substitution candidates for one prescribed exercise.
 * Ranked by expected torso support (when requested), expected trunk demand,
 * muscle-contribution similarity, then id. */
export function substitutionCandidates(input: {
  primaryMuscle: MuscleGroup;
  currentExerciseId: string;
  currentContribution: MuscleContribution;
  available: ReadonlySet<CatalogEquipment>;
  excludedConcerns?: readonly string[];
  excludedExerciseIds?: readonly string[];
  preferTorsoSupport?: boolean;
  maxTrunkDemand?: TrunkDemandLevel;
}): CatalogVariant[] {
  const maxDemand = input.maxTrunkDemand ? TRUNK_ORDER[input.maxTrunkDemand] : null;
  return EXERCISE_CATALOG.filter(
    (variant) =>
      variant.substitutionEligible !== false &&
      variant.primaryMuscle === input.primaryMuscle &&
      variant.id !== input.currentExerciseId &&
      (maxDemand === null || TRUNK_ORDER[variant.trunkDemand.level] <= maxDemand) &&
      isEligibleVariant(variant, {
        available: input.available,
        excludedConcerns: input.excludedConcerns,
        excludedExerciseIds: input.excludedExerciseIds,
      }),
  ).sort((a, b) => {
    if (input.preferTorsoSupport && a.torsoSupport !== b.torsoSupport) {
      return a.torsoSupport === 'supported' ? -1 : 1;
    }
    const demand = TRUNK_ORDER[a.trunkDemand.level] - TRUNK_ORDER[b.trunkDemand.level];
    if (demand !== 0) return demand;
    const distance =
      contributionDistance(a.muscleContribution, input.currentContribution) -
      contributionDistance(b.muscleContribution, input.currentContribution);
    if (distance !== 0) return distance;
    return a.id.localeCompare(b.id);
  });
}
