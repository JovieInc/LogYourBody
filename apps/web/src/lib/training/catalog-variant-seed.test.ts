import { catalogVariantById, catalogVariantSeedSchema, type CatalogVariant } from './catalog';
import variantSeed from './catalog-variant-seed.json';

/** Muscles in the first five-session aesthetic plan. This list is the allow-list. */
const CURATED_AREAS = ['arms', 'lateral_delts', 'lats', 'lower_body', 'upper_chest'] as const;

const TARGET_AREA = {
  upper_chest: 'upper_chest',
  lateral_delts: 'lateral_delts',
  lats: 'lats',
  biceps: 'arms',
  triceps: 'arms',
  quads: 'lower_body',
  hamstrings: 'lower_body',
  glutes: 'lower_body',
  calves: 'lower_body',
} as const satisfies Record<string, (typeof CURATED_AREAS)[number]>;

type CurlKind = 'exercise' | 'setup';

/** Named biceps and back-sensitive curl alternatives. This list is the allow-list. */
const CURL_ALLOW_LIST: ReadonlyArray<{ id: string; label: string; kind: CurlKind }> = [
  { id: 'cable_curl', label: 'standing cable curl', kind: 'exercise' },
  { id: 'barbell_curl', label: 'standing barbell curl', kind: 'exercise' },
  { id: 'preacher_machine_curl', label: 'seated machine preacher curl', kind: 'exercise' },
  {
    id: 'incline_dumbbell_curl',
    label: 'incline dumbbell curl with back support',
    kind: 'setup',
  },
  { id: 'supported_cable_curl', label: 'bench-supported cable curl', kind: 'setup' },
  { id: 'supported_cable_floor_curl', label: 'floor-lying cable curl', kind: 'setup' },
];

const ZERO_AXIAL_OR_SPINAL_STRESS =
  /\b(?:zero|no|none|0)\b(?:\s+\w+){0,4}\s+(?:axial|spinal)\b(?:\s+\w+){0,4}\s+(?:stress|load(?:ing)?)\b|\b(?:axial|spinal)\b(?:\s+\w+){0,4}\s+(?:stress|load(?:ing)?)\b(?:\s+\w+){0,3}\s+(?:is\s+)?(?:zero|none|0)\b/i;
const BELT_ELIMINATES_AXIAL_LOAD =
  /\bbelt\b(?:\s+\w+){0,6}\s+(?:eliminat\w*|remov\w*|clear\w*)\b(?:\s+\w+){0,4}\s+(?:axial|spinal)\b(?:\s+\w+){0,3}\s+load\b/i;
const SYMPTOMATIC_LOADING_IS_SAFE =
  /\bsymptomatic\s+loading\s+is\s+safe\b|\buniversally\s+safe\b|\bsafe\s+(?:for\s+)?symptomatic\s+loading\b|\bsymptomatic\s+loading\s+is\s+universally\s+safe\b/i;

const FORBIDDEN_SEED_CLAIMS = [
  { id: 'zero-axial-or-spinal-stress', pattern: ZERO_AXIAL_OR_SPINAL_STRESS },
  { id: 'belt-eliminates-axial-load', pattern: BELT_ELIMINATES_AXIAL_LOAD },
  { id: 'symptomatic-loading-safe', pattern: SYMPTOMATIC_LOADING_IS_SAFE },
] as const;

function isNegated(text: string, index: number): boolean {
  const prefix = text.slice(Math.max(0, index - 80), index);
  return /\b(?:not|no|never|without|does not|do not|don't|cannot|can't)\b[\w\s,'’-]*$/i.test(
    prefix,
  );
}

/** Returns the forbidden claim id when text asserts one, ignoring an explicit denial. */
function forbiddenSeedClaim(text: string): (typeof FORBIDDEN_SEED_CLAIMS)[number]['id'] | null {
  for (const rule of FORBIDDEN_SEED_CLAIMS) {
    const match = text.match(rule.pattern);
    if (!match || match.index === undefined) continue;
    if (isNegated(text, match.index) || /\b(?:not|never|without)\b/i.test(match[0])) continue;
    return rule.id;
  }
  return null;
}

function seededStatements(entry: (typeof variantSeed)[number]): string[] {
  const tags = entry.toleranceTags;
  return [entry.romSetupCaveat, ...Object.values(tags).flat()];
}

function record(id: string): CatalogVariant {
  const variant = catalogVariantById(id);
  if (!variant) throw new Error(`missing catalog record ${id}`);
  return variant;
}

describe('narrow curated variant seed', () => {
  const seed = catalogVariantSeedSchema.parse(variantSeed);

  it('keeps the named biceps and supported-curl alternatives as separate records', () => {
    expect(new Set(CURL_ALLOW_LIST.map((item) => item.id)).size).toBe(CURL_ALLOW_LIST.length);
    for (const item of CURL_ALLOW_LIST) {
      const variant = record(item.id);
      const metadata = seed.find((entry) => entry.id === item.id);
      expect(metadata).toBeDefined();
      const { id: _id, ...metadataFields } = metadata!;
      expect(variant.variantMetadata).toEqual(metadataFields);
      expect(variant.primaryMuscle).toBe('biceps');
      if (item.kind === 'exercise') {
        expect(variant.setupOf).toBeUndefined();
      } else {
        expect(variant.setupOf).toBeDefined();
        expect(variant.setupOf).not.toBe(variant.id);
        expect(record(variant.setupOf!).id).not.toBe(variant.id);
      }
    }

    const standingCable = record('cable_curl');
    const standingBarbell = record('barbell_curl');
    const preacher = record('preacher_machine_curl');
    const incline = record('incline_dumbbell_curl');
    const benchCable = record('supported_cable_curl');
    const floorCable = record('supported_cable_floor_curl');

    expect(standingCable).toMatchObject({
      name: 'Cable curl',
      torsoSupport: 'unsupported',
      bodyPosition: expect.stringMatching(/standing/i),
    });
    expect(standingBarbell).toMatchObject({
      name: 'Barbell curl',
      torsoSupport: 'unsupported',
      bodyPosition: expect.stringMatching(/standing/i),
      requires: ['barbell'],
    });
    expect(preacher).toMatchObject({
      name: 'Machine preacher curl',
      torsoSupport: 'supported',
      bodyPosition: expect.stringMatching(/seated/i),
      requires: ['machine'],
    });
    expect(preacher.variantMetadata?.support).toBe('none');
    expect(incline).toMatchObject({
      name: 'Incline dumbbell curl',
      setupOf: 'dumbbell_curl',
      torsoSupport: 'supported',
    });
    expect(incline.variantMetadata?.support).toBe('back');
    expect(benchCable).toMatchObject({
      name: 'Incline cable curl',
      setupOf: 'cable_curl',
      torsoSupport: 'supported',
      bodyPosition: expect.stringMatching(/bench/i),
      requires: expect.arrayContaining(['cable', 'adjustable_bench']),
    });
    expect(benchCable.variantMetadata?.support).toBe('back');
    expect(floorCable).toMatchObject({
      name: 'Floor-lying cable curl',
      setupOf: 'cable_curl',
      torsoSupport: 'supported',
      bodyPosition: expect.stringMatching(/lying/i),
      requires: ['cable'],
      exclusions: ['floor_rom_blocked'],
    });
    expect(floorCable.variantMetadata?.support).toBe('back');
    expect(floorCable.variantMetadata?.romSetupCaveat).toMatch(/clearance/i);
    expect(floorCable.variantMetadata?.romSetupCaveat).toMatch(/range/i);
    expect(floorCable.variantMetadata?.toleranceTags.axialTrunkFatigue.join(' ')).toMatch(
      /may reduce trunk demand/i,
    );
    expect(floorCable.id).not.toBe(benchCable.id);
    expect(floorCable.bodyPosition).not.toBe(benchCable.bodyPosition);
    expect(floorCable.requires).not.toEqual(benchCable.requires);
  });

  it('fails when a seeded tag claims zero axial or spinal stress, belt clearance, or safe symptomatic loading', () => {
    const forbidden = [
      'zero axial stress',
      'zero spinal stress',
      'no axial load',
      'no spinal stress',
      'axial stress is zero',
      'spinal loading is 0',
      'a belt eliminates axial load',
      'belt removes the axial load',
      'belt clears spinal load',
      'symptomatic loading is safe',
      'universally safe',
      'safe for symptomatic loading',
    ];
    for (const text of forbidden) expect(forbiddenSeedClaim(text)).not.toBeNull();

    const allowed = [
      'floor contact may reduce trunk demand',
      'a belt does not eliminate axial load',
      'support does not mean zero spinal stress',
      'symptomatic loading is not a safety clearance',
      'bench contact with bracing',
    ];
    for (const text of allowed) expect(forbiddenSeedClaim(text)).toBeNull();

    for (const entry of seed) {
      for (const text of seededStatements(entry)) {
        expect(forbiddenSeedClaim(text)).toBeNull();
      }
    }
  });

  it('covers only upper chest, lateral delts, lats, arms, and lower body', () => {
    const areas = new Set<(typeof CURATED_AREAS)[number]>();
    for (const entry of seed) {
      expect(TARGET_AREA).toHaveProperty(entry.targetRegion);
      areas.add(TARGET_AREA[entry.targetRegion]);
    }
    expect([...areas].sort()).toEqual([...CURATED_AREAS].sort());
    expect(seed.some((entry) => entry.targetRegion === 'biceps')).toBe(true);
    expect(seed.some((entry) => entry.targetRegion === 'triceps')).toBe(true);
  });
});
