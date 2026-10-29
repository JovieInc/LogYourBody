import { z } from 'zod';
import variantSeed from './catalog-variant-seed.json';
import { MUSCLE_GROUPS, type Equipment, type MuscleContribution, type MuscleGroup } from './types';

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

export const catalogVariantMetadataSchema = z
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

export const catalogVariantSeedSchema = z
  .array(
    catalogVariantMetadataSchema.extend({ id: z.string().regex(/^[a-z][a-z0-9_]*$/) }).strict(),
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

const reviewed = (level: TrunkDemandLevel, note: string): TrunkDemand => ({
  level,
  basis: 'reviewed',
  note,
});

const baseCatalog: CatalogVariant[] = [
  {
    id: 'goblet_squat',
    name: 'Goblet squat',
    primaryMuscle: 'quads',
    muscleContribution: { quads: 1, glutes: 0.5 },
    requires: ['dumbbells'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed(
      'moderate',
      'Load held at the chest; trunk braces but carries modest load.',
    ),
    bodyPosition: 'standing',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: [
      'Hold one dumbbell vertically at the chest',
      'Sit between the hips, keep the chest tall',
    ],
    exclusions: [],
  },
  {
    id: 'dumbbell_floor_press',
    name: 'Dumbbell floor press',
    primaryMuscle: 'chest',
    muscleContribution: { chest: 1, triceps: 0.5, shoulders: 0.5 },
    requires: ['dumbbells'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Torso rests on the floor throughout the set.'),
    bodyPosition: 'lying supine on the floor',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Upper arms touch the floor at the bottom', 'Press straight over the shoulders'],
    exclusions: [],
  },
  {
    id: 'one_arm_dumbbell_row',
    name: 'One-arm dumbbell row',
    primaryMuscle: 'back',
    muscleContribution: { back: 1, biceps: 0.5 },
    requires: ['dumbbells'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed(
      'moderate',
      'Free hand braces on a surface; trunk still holds the hinge.',
    ),
    bodyPosition: 'hinged, one hand braced',
    benchAngleDeg: null,
    pulley: null,
    unilateral: true,
    cues: ['Pull the elbow toward the hip', 'Keep the shoulders level'],
    exclusions: [],
  },
  {
    id: 'dumbbell_romanian_deadlift',
    name: 'Dumbbell Romanian deadlift',
    primaryMuscle: 'hamstrings',
    muscleContribution: { hamstrings: 1, glutes: 0.5 },
    requires: ['dumbbells'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('high', 'Hinge pattern loads the spinal extensors throughout.'),
    bodyPosition: 'standing hinge',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Push the hips back, dumbbells slide down the thighs', 'Keep a long spine'],
    exclusions: ['low_back_symptoms'],
  },
  {
    id: 'dumbbell_lateral_raise',
    name: 'Dumbbell lateral raise',
    primaryMuscle: 'shoulders',
    muscleContribution: { shoulders: 1 },
    requires: ['dumbbells'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('low', 'Standing with light loads; trunk demand is minimal.'),
    bodyPosition: 'standing',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Lead with the elbows', 'Stop at shoulder height'],
    exclusions: [],
  },
  {
    id: 'dumbbell_curl',
    name: 'Dumbbell curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['dumbbells'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('low', 'Standing with light loads; the trunk only stabilizes.'),
    bodyPosition: 'standing',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Elbows stay by the ribs', 'Curl without swinging'],
    exclusions: [],
  },
  {
    id: 'standing_calf_raise',
    name: 'Standing calf raise',
    primaryMuscle: 'calves',
    muscleContribution: { calves: 1 },
    requires: ['bodyweight'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('low', 'Upright; a hand may rest on a surface for balance.'),
    bodyPosition: 'standing',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Full stretch at the bottom', 'Pause at the top'],
    exclusions: [],
  },
  {
    id: 'dead_bug',
    name: 'Dead bug',
    primaryMuscle: 'core',
    muscleContribution: { core: 1 },
    requires: ['bodyweight'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Back rests on the floor; demand is the exercise itself.'),
    bodyPosition: 'lying supine',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Keep the low back gently on the floor', 'Move opposite arm and leg slowly'],
    exclusions: [],
  },
  {
    id: 'dumbbell_split_squat',
    name: 'Dumbbell split squat',
    primaryMuscle: 'quads',
    muscleContribution: { quads: 1, glutes: 0.5 },
    requires: ['dumbbells'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('moderate', 'Upright trunk with load at the sides.'),
    bodyPosition: 'split stance',
    benchAngleDeg: null,
    pulley: null,
    unilateral: true,
    cues: ['Drop the back knee toward the floor', 'Stay tall through the torso'],
    exclusions: [],
  },
  {
    id: 'incline_dumbbell_press',
    name: 'Incline dumbbell press',
    primaryMuscle: 'chest',
    muscleContribution: { chest: 1, triceps: 0.5, shoulders: 0.5 },
    requires: ['dumbbells', 'adjustable_bench'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Torso is fully supported by the bench.'),
    bodyPosition: 'seated, back on the bench',
    benchAngleDeg: 45,
    pulley: null,
    unilateral: false,
    cues: ['Set the bench near 45 degrees', 'Press up and slightly back'],
    exclusions: [],
  },
  {
    id: 'chest_supported_dumbbell_row',
    name: 'Chest-supported dumbbell row',
    primaryMuscle: 'back',
    muscleContribution: { back: 1, biceps: 0.5 },
    requires: ['dumbbells', 'adjustable_bench'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Chest rests on the bench; the trunk does not hold the position.'),
    bodyPosition: 'lying prone on an incline bench',
    benchAngleDeg: 45,
    pulley: null,
    unilateral: false,
    cues: ['Chest stays on the pad', 'Row the elbows toward the hips'],
    exclusions: [],
  },
  {
    id: 'dumbbell_hip_thrust',
    name: 'Dumbbell hip thrust',
    primaryMuscle: 'glutes',
    muscleContribution: { glutes: 1, hamstrings: 0.25 },
    requires: ['dumbbells', 'bench'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Upper back rests on the bench.'),
    bodyPosition: 'upper back on a bench',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Drive through the heels', 'Ribs stay down at the top'],
    exclusions: [],
  },
  {
    id: 'overhead_dumbbell_triceps_extension',
    name: 'Overhead dumbbell triceps extension',
    primaryMuscle: 'triceps',
    muscleContribution: { triceps: 1 },
    requires: ['dumbbells'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('moderate', 'Overhead load asks the trunk to stay braced.'),
    bodyPosition: 'standing or seated',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Elbows point up and stay narrow', 'Lower behind the head with control'],
    exclusions: ['shoulder_overhead_intolerance'],
  },
  {
    id: 'single_leg_calf_raise',
    name: 'Single-leg calf raise',
    primaryMuscle: 'calves',
    muscleContribution: { calves: 1 },
    requires: ['bodyweight'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('low', 'Upright; a hand may rest on a surface for balance.'),
    bodyPosition: 'standing on one leg',
    benchAngleDeg: null,
    pulley: null,
    unilateral: true,
    cues: ['Full stretch at the bottom', 'Pause at the top'],
    exclusions: [],
  },
  {
    id: 'bird_dog',
    name: 'Bird dog',
    primaryMuscle: 'core',
    muscleContribution: { core: 1 },
    requires: ['bodyweight'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Hands and knees on the floor.'),
    bodyPosition: 'on all fours',
    benchAngleDeg: null,
    pulley: null,
    unilateral: true,
    cues: ['Reach long without rotating', 'Keep hips level'],
    exclusions: [],
  },
  {
    id: 'leg_press',
    name: 'Leg press',
    primaryMuscle: 'quads',
    muscleContribution: { quads: 1, glutes: 0.5 },
    requires: ['machine'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Back and hips are supported by the sled seat.'),
    bodyPosition: 'seated, back on the pad',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Feet shoulder width on the plate', 'Lower until hips stay planted'],
    exclusions: [],
  },
  {
    id: 'machine_chest_press',
    name: 'Machine chest press',
    primaryMuscle: 'chest',
    muscleContribution: { chest: 1, triceps: 0.5, shoulders: 0.5 },
    requires: ['machine'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Back is fully supported by the seat.'),
    bodyPosition: 'seated',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Handles start at chest height', 'Press without shrugging'],
    exclusions: [],
  },
  {
    id: 'seated_cable_row',
    name: 'Seated cable row',
    primaryMuscle: 'back',
    muscleContribution: { back: 1, biceps: 0.5 },
    requires: ['cable'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('moderate', 'Seated but the trunk holds the pull without a pad.'),
    bodyPosition: 'seated facing the stack',
    benchAngleDeg: null,
    pulley: { height: 'low', attachment: 'close-grip handle' },
    unilateral: false,
    cues: ['Pull the handle to the ribs', 'Stay tall, no rocking back'],
    exclusions: [],
  },
  {
    id: 'barbell_romanian_deadlift',
    name: 'Romanian deadlift',
    primaryMuscle: 'hamstrings',
    muscleContribution: { hamstrings: 1, glutes: 0.5 },
    requires: ['barbell'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('high', 'Barbell hinge loads the spinal extensors throughout.'),
    bodyPosition: 'standing hinge',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Push the hips back', 'Bar slides down the thighs, spine long'],
    exclusions: ['low_back_symptoms'],
  },
  {
    id: 'cable_lateral_raise',
    name: 'Cable lateral raise',
    primaryMuscle: 'shoulders',
    muscleContribution: { shoulders: 1 },
    requires: ['cable'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('low', 'Standing with light loads; trunk demand is minimal.'),
    bodyPosition: 'standing side-on to the stack',
    benchAngleDeg: null,
    pulley: { height: 'low', attachment: 'single handle' },
    unilateral: true,
    cues: ['Lead with the elbow', 'Stop at shoulder height'],
    exclusions: [],
  },
  {
    id: 'cable_curl',
    name: 'Cable curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['cable'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('low', 'Standing with light loads; the trunk only stabilizes.'),
    bodyPosition: 'standing facing the stack',
    benchAngleDeg: null,
    pulley: { height: 'low', attachment: 'straight bar or single handle' },
    unilateral: false,
    cues: ['Elbows stay by the ribs', 'Control the lowering'],
    exclusions: [],
  },
  {
    id: 'split_squat',
    name: 'Split squat',
    primaryMuscle: 'quads',
    muscleContribution: { quads: 1, glutes: 0.5 },
    requires: ['bodyweight'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('moderate', 'Upright trunk; bodyweight or light load.'),
    bodyPosition: 'split stance',
    benchAngleDeg: null,
    pulley: null,
    unilateral: true,
    cues: ['Drop the back knee toward the floor', 'Stay tall through the torso'],
    exclusions: [],
  },
  {
    id: 'incline_machine_press',
    name: 'Incline machine press',
    primaryMuscle: 'chest',
    muscleContribution: { chest: 1, triceps: 0.5, shoulders: 0.5 },
    requires: ['machine'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Back is fully supported by the seat.'),
    bodyPosition: 'seated at an incline station',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Handles start at upper-chest height', 'Press without shrugging'],
    exclusions: [],
  },
  {
    id: 'lat_pulldown',
    name: 'Lat pulldown',
    primaryMuscle: 'back',
    muscleContribution: { back: 1, biceps: 0.5 },
    requires: ['cable'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Thigh pad anchors the legs; trunk stays braced lightly.'),
    bodyPosition: 'seated facing the stack',
    benchAngleDeg: null,
    pulley: { height: 'high', attachment: 'wide bar' },
    unilateral: false,
    cues: ['Pull the bar to the upper chest', 'Drive the elbows down'],
    exclusions: [],
  },
  {
    id: 'hip_thrust',
    name: 'Hip thrust',
    primaryMuscle: 'glutes',
    muscleContribution: { glutes: 1, hamstrings: 0.25 },
    requires: ['barbell', 'bench'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Upper back rests on the bench.'),
    bodyPosition: 'upper back on a bench',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Drive through the heels', 'Ribs stay down at the top'],
    exclusions: [],
  },
  {
    id: 'cable_triceps_pressdown',
    name: 'Cable triceps pressdown',
    primaryMuscle: 'triceps',
    muscleContribution: { triceps: 1 },
    requires: ['cable'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('low', 'Standing; the trunk only stabilizes.'),
    bodyPosition: 'standing facing the stack',
    benchAngleDeg: null,
    pulley: { height: 'high', attachment: 'rope or straight bar' },
    unilateral: false,
    cues: ['Elbows pinned at the ribs', 'Straighten fully at the bottom'],
    exclusions: [],
  },
  {
    id: 'seated_calf_raise',
    name: 'Seated calf raise',
    primaryMuscle: 'calves',
    muscleContribution: { calves: 1 },
    requires: ['machine'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Seated with a pad over the thighs.'),
    bodyPosition: 'seated',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Full stretch at the bottom', 'Pause at the top'],
    exclusions: [],
  },
  // Reviewed additions: alternatives the catalog did not previously offer.
  {
    id: 'lying_dumbbell_curl',
    name: 'Lying dumbbell curl',
    setupOf: 'dumbbell_curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['dumbbells'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Torso rests on the floor; bracing varies with execution.'),
    bodyPosition: 'lying supine on the floor',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Upper arms rest on the floor', 'Curl without lifting the elbows'],
    exclusions: ['floor_rom_blocked'],
  },
  {
    id: 'incline_dumbbell_curl',
    name: 'Incline dumbbell curl',
    setupOf: 'dumbbell_curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['dumbbells', 'adjustable_bench'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Torso is fully supported by the bench.'),
    bodyPosition: 'seated, back on the bench',
    benchAngleDeg: 60,
    pulley: null,
    unilateral: false,
    cues: ['Set the bench near 60 degrees', 'Let the arms hang long, curl without swinging'],
    exclusions: ['shoulder_extension_intolerance'],
  },
  {
    id: 'supported_cable_curl',
    name: 'Incline cable curl',
    setupOf: 'cable_curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['cable', 'adjustable_bench'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Torso is supported by the bench between low pulleys.'),
    bodyPosition: 'seated on a bench between two low pulleys',
    benchAngleDeg: 60,
    pulley: { height: 'low', attachment: 'single handle' },
    unilateral: false,
    cues: ['Set the bench near 60 degrees', 'Curl toward the ears without moving the upper arms'],
    exclusions: ['shoulder_extension_intolerance'],
  },
  {
    id: 'preacher_machine_curl',
    name: 'Machine preacher curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['machine'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Seated with the arms braced on the pad.'),
    bodyPosition: 'seated at the preacher station',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Armpits rest over the pad', 'Lower without locking out hard'],
    exclusions: [],
  },
  {
    id: 'concentration_curl',
    name: 'Concentration curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['dumbbells', 'bench'],
    torsoSupport: 'supported',
    trunkDemand: reviewed('low', 'Seated with the upper arm braced against the thigh.'),
    bodyPosition: 'seated on a bench, leaning forward',
    benchAngleDeg: null,
    pulley: null,
    unilateral: true,
    cues: ['Upper arm braces on the inner thigh', 'Curl without rocking the torso'],
    exclusions: [],
  },
  {
    id: 'barbell_curl',
    name: 'Barbell curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['barbell'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('low', 'Standing with a moderate load; the trunk only stabilizes.'),
    bodyPosition: 'standing',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Elbows stay by the ribs', 'Curl without leaning back'],
    exclusions: ['wrist_intolerance'],
  },
  {
    id: 'ez_bar_curl',
    name: 'EZ-bar curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['ez_bar'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed('low', 'Standing with a moderate load; the trunk only stabilizes.'),
    bodyPosition: 'standing',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Elbows stay by the ribs', 'Curl without leaning back'],
    exclusions: [],
  },
  {
    id: 'wrist_curl',
    name: 'Dumbbell wrist curl',
    primaryMuscle: 'biceps',
    muscleContribution: { biceps: 1 },
    requires: ['dumbbells'],
    torsoSupport: 'supported',
    trunkDemand: reviewed(
      'low',
      'Forearms rest on the thighs; the trunk maintains the seated position.',
    ),
    bodyPosition: 'seated, forearms on the thighs',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Forearms stay on the thighs', 'Curl at the wrist through a comfortable range'],
    exclusions: ['wrist_intolerance'],
    substitutionEligible: false,
  },
  {
    id: 'pull_up',
    name: 'Pull-up',
    primaryMuscle: 'back',
    muscleContribution: { back: 1, biceps: 0.5 },
    requires: ['bodyweight'],
    torsoSupport: 'unsupported',
    trunkDemand: reviewed(
      'moderate',
      'The body hangs from the hands; the trunk braces in the air.',
    ),
    bodyPosition: 'hanging from a bar',
    benchAngleDeg: null,
    pulley: null,
    unilateral: false,
    cues: ['Start from a full hang', 'Pull until the chin is level with the bar'],
    exclusions: ['shoulder_overhead_intolerance'],
  },
  {
    id: 'smith_incline_press',
    name: 'Smith machine incline press',
    primaryMuscle: 'chest',
    muscleContribution: { chest: 1, triceps: 0.5, shoulders: 0.5 },
    requires: ['smith', 'adjustable_bench'],
    torsoSupport: 'supported',
    trunkDemand: reviewed(
      'low',
      'Torso is supported by the bench; the bar travels on the Smith rails.',
    ),
    bodyPosition: 'seated, back on the bench',
    benchAngleDeg: 45,
    pulley: null,
    unilateral: false,
    cues: ['Set the bench near 45 degrees', 'Press along the Smith rail path'],
    exclusions: [],
  },
];

// Extend the existing IDs and setup fields rather than creating a second library.
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
