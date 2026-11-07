import { z } from 'zod';
import { MUSCLE_GROUPS, type MuscleGroup } from './types';

/**
 * Reviewed exercise catalog: the engine's setup-aware substitution source.
 * Every record describes the *expected* setup of the variant — never a
 * user-reported experience and never a precise fatigue score.
 */
export const CATALOG_EQUIPMENT = [
  'dumbbells',
  'barbell',
  'ez_bar',
  'machine',
  'cable',
  'bench',
  'adjustable_bench',
  'bodyweight',
  'smith',
] as const;
export type CatalogEquipment = (typeof CATALOG_EQUIPMENT)[number];

const text = z.string().trim().min(1).max(500);
const trunkDemandLevelSchema = z.enum(['low', 'moderate', 'high']);
export type TrunkDemandLevel = z.infer<typeof trunkDemandLevelSchema>;

/** Qualitative expected trunk-support/spinal-loading demand, with provenance. */
const trunkDemandSchema = z
  .object({
    level: trunkDemandLevelSchema,
    /** 'reviewed' = human-reviewed record; 'inferred' = derived from setup fields. */
    basis: z.enum(['reviewed', 'inferred']),
    note: text,
  })
  .strict();
export type TrunkDemand = z.infer<typeof trunkDemandSchema>;

const TARGET_REGION_GROUP = {
  upper_chest: 'chest',
  lateral_delts: 'shoulders',
  lats: 'back',
  biceps: 'biceps',
  triceps: 'triceps',
  quads: 'quads',
  hamstrings: 'hamstrings',
  glutes: 'glutes',
  calves: 'calves',
} as const satisfies Record<string, MuscleGroup>;

/** Advisory, editable setup tags, not measured/reported symptoms or an aggregate score.
 * Empty arrays mean unspecified; they never imply comfort, recovery or safety. */
export const variantToleranceTagsSchema = z
  .object({
    axialTrunkFatigue: z.array(text).max(10),
    jointDiscomfort: z.array(text).max(10),
    stability: z.array(text).max(10),
    rom: z.array(text).max(10),
  })
  .strict();
export type VariantToleranceTags = z.infer<typeof variantToleranceTagsSchema>;

/** Absent tolerance, fatigue, and ROM. Never a numeric stand-in such as 0. */
export const VARIANT_MEASURE_UNKNOWN = 'unknown' as const;

export const OBJECTIVE_VARIANT_MEASURE_MESSAGE =
  'Variant metadata cannot store objective spinal load or a numeric SFR score';

/** Structured keys that would store a measured spinal load or a numeric SFR. */
const OBJECTIVE_VARIANT_MEASURE_KEY =
  /^(?:spinalload(?:newtons|n)?|axialload(?:newtons|n)?|objectivespinalload|sfr|sfrscore|stimulustofatigue|stimulustofatigueratio)$/;

const catalogVariantMetadataObject = z
  .object({
    targetRegion: z.enum(
      Object.keys(TARGET_REGION_GROUP) as Array<keyof typeof TARGET_REGION_GROUP>,
    ),
    /** Torso contact only: arm/thigh/hand bracing is not back or chest support. */
    support: z.enum(['none', 'back', 'chest']),
    romSetupCaveat: text,
    toleranceTags: variantToleranceTagsSchema,
  })
  .strict();

function rejectObjectiveVariantMeasures(
  value: unknown,
  context: z.RefinementCtx,
  path: Array<string | number> = [],
) {
  if (!value || typeof value !== 'object') return;
  for (const [key, child] of Object.entries(value)) {
    const normalized = key.replace(/[^a-z0-9]/gi, '').toLowerCase();
    const childPath = [...path, key];
    if (OBJECTIVE_VARIANT_MEASURE_KEY.test(normalized)) {
      context.addIssue({
        code: 'custom',
        path: childPath,
        message: OBJECTIVE_VARIANT_MEASURE_MESSAGE,
      });
    }
    rejectObjectiveVariantMeasures(child, context, childPath);
  }
}

/** Reject measured spinal load and numeric SFR before the strict field list runs. */
function guardedVariantMetadata<T extends z.ZodType>(schema: T) {
  return z
    .unknown()
    .superRefine((value, context) => {
      rejectObjectiveVariantMeasures(value, context);
    })
    .pipe(schema);
}

export const catalogVariantMetadataSchema = guardedVariantMetadata(catalogVariantMetadataObject);

export const catalogVariantSeedSchema = z
  .array(
    guardedVariantMetadata(
      catalogVariantMetadataObject.extend({ id: z.string().regex(/^[a-z][a-z0-9_]*$/) }).strict(),
    ),
  )
  .superRefine((entries, context) => {
    const ids = new Set<string>();
    entries.forEach((entry, index) => {
      if (ids.has(entry.id))
        context.addIssue({ code: 'custom', path: [index, 'id'], message: 'Duplicate variant ID' });
      ids.add(entry.id);
    });
  });

export const catalogVariantSchema = z
  .object({
    id: z.string().regex(/^[a-z][a-z0-9_]*$/),
    name: text,
    /** Explicit base movement identity for a setup change; never inferred from names. */
    setupOf: z
      .string()
      .regex(/^[a-z][a-z0-9_]*$/)
      .optional(),
    primaryMuscle: z.enum(MUSCLE_GROUPS),
    muscleContribution: z.partialRecord(z.enum(MUSCLE_GROUPS), z.number().nonnegative()),
    /** Concrete items that must be present; unknown availability fails eligibility. */
    requires: z.array(z.enum(CATALOG_EQUIPMENT)).min(1),
    torsoSupport: z.enum(['supported', 'unsupported']),
    trunkDemand: trunkDemandSchema,
    bodyPosition: text,
    benchAngleDeg: z.number().min(0).max(90).nullable(),
    pulley: z.object({ height: text, attachment: text }).strict().nullable(),
    unilateral: z.boolean(),
    cues: z.array(text),
    /** Hard concern exclusions remain separate from advisory tolerance tags. */
    exclusions: z.array(text),
    /** False keeps a reviewed variant addressable without offering it as a substitute. */
    substitutionEligible: z.boolean().optional(),
    // Uncurated legacy entries remain usable without invented metadata.
    variantMetadata: catalogVariantMetadataSchema.optional(),
  })
  .strict()
  .refine(
    (variant) =>
      !variant.variantMetadata ||
      TARGET_REGION_GROUP[variant.variantMetadata.targetRegion] === variant.primaryMuscle,
    {
      path: ['variantMetadata', 'targetRegion'],
      message: 'Target region must belong to the primary muscle group',
    },
  );
export type CatalogVariant = z.infer<typeof catalogVariantSchema>;

export type ExerciseVariantLoadTolerance = {
  tolerance: VariantToleranceTags | typeof VARIANT_MEASURE_UNKNOWN;
  fatigue: readonly string[] | typeof VARIANT_MEASURE_UNKNOWN;
  rom: readonly string[] | typeof VARIANT_MEASURE_UNKNOWN;
};

/** Read view over one library record. Setup fields reuse the catalog taxonomy. */
export type LoadedExerciseVariant = {
  record: CatalogVariant;
  targetedMuscle:
    NonNullable<CatalogVariant['variantMetadata']>['targetRegion'] | typeof VARIANT_MEASURE_UNKNOWN;
  bodyPosition: string;
  support:
    NonNullable<CatalogVariant['variantMetadata']>['support'] | typeof VARIANT_MEASURE_UNKNOWN;
  romSetupCaveat: string | typeof VARIANT_MEASURE_UNKNOWN;
  equipment: readonly CatalogEquipment[];
  loadTolerance: ExerciseVariantLoadTolerance;
};

const OMITTED_LOAD_TOLERANCE: ExerciseVariantLoadTolerance = {
  tolerance: VARIANT_MEASURE_UNKNOWN,
  fatigue: VARIANT_MEASURE_UNKNOWN,
  rom: VARIANT_MEASURE_UNKNOWN,
};

/** Load one library record. Omitted tolerance, fatigue, and ROM stay unknown, never 0. */
export function loadExerciseVariantRecord(raw: unknown): LoadedExerciseVariant {
  const record = catalogVariantSchema.parse(raw);
  const metadata = record.variantMetadata;
  return {
    record,
    targetedMuscle: metadata?.targetRegion ?? VARIANT_MEASURE_UNKNOWN,
    bodyPosition: record.bodyPosition,
    support: metadata?.support ?? VARIANT_MEASURE_UNKNOWN,
    romSetupCaveat: metadata?.romSetupCaveat ?? VARIANT_MEASURE_UNKNOWN,
    equipment: record.requires,
    loadTolerance: metadata
      ? {
          tolerance: metadata.toleranceTags,
          fatigue: metadata.toleranceTags.axialTrunkFatigue,
          rom: metadata.toleranceTags.rom,
        }
      : OMITTED_LOAD_TOLERANCE,
  };
}
