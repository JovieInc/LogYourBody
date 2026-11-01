/**
 * Continuous illustrative torso family for LYB-314.
 *
 * Anny 0.6.2 was evaluated and is not bundled. See
 * docs/product/wireframe-avatar-family.md. These shapes are original,
 * share one topology and one rig, and are not body-fat or FFMI values.
 */

export const MODEL_ID = 'lyb.wireframe.torso';
export const MODEL_VERSION = '1.0.0';
export const TOPOLOGY_ID = 'lyb.wireframe.torso.v1';
export const RIG_ID = 'lyb.wireframe.torso.rig.v1';
export const RINGS = 10;
export const SEGMENTS = 16;
export const dragGain = 0.008;
export const idleSpin = false;
export const animatedDuration = 0.2;
export const YAW_LIMIT = Math.PI;
export const YAW_FRONT = 0;
export const YAW_SIDE = Math.PI / 2;

const PRESENTATIONS = ['male', 'female'] as const;
export type WireframePresentation = (typeof PRESENTATIONS)[number];

export interface WireframeParameters {
  adiposity: number;
  muscularity: number;
  frame: number;
}

export interface ResolvedWireframe {
  topologyId: string;
  rigId: string;
  vertices: number[][];
}

export interface WireframeAvatarAsset {
  modelId: string;
  version: string;
  topologyId: string;
  rigId: string;
  illustrative: true;
  mapsToBodyFat: false;
  mapsToFfmi: false;
  pose: 'neutral-identity';
  crop: 'torso-chest-to-waist';
  vertexCount: number;
  families: Record<
    WireframePresentation,
    {
      rest: number[][];
      adiposity: number[][];
      muscularity: number[][];
      frame: number[][];
    }
  >;
  faces: number[][];
  wires: number[][];
  rig: {
    joints: { name: string; position: number[] }[];
    weights: number[][];
    pose: 'identity';
  };
  parameters: {
    adiposity: { min: 0; max: 1; meaning: string };
    muscularity: { min: 0; max: 1; meaning: string };
    frame: { min: 0; max: 1; meaning: string };
  };
  defaults: {
    presentation: 'male';
    adiposity: 0.5;
    muscularity: 0.5;
    frame: 0.5;
    yaw: 0;
  };
  camera: {
    projection: 'perspective';
    fovDegrees: 28;
    distance: 2.35;
    target: [number, number, number];
    frontYaw: number;
    sideYaw: number;
  };
  material: {
    kind: 'wire';
    fill: false;
    color: '#F5F7FB';
    lineWidth: 1.15;
    idleSpin: false;
  };
  lighting: { model: 'unlit-wire'; depthCue: 'opacity-by-depth' };
  caching: {
    tier: 'phone';
    vertexBudget: number;
    wireBudget: number;
    memoryEntries: 32;
    quantization: 0.05;
    disk: false;
    network: false;
    photoBytes: false;
  };
  license: {
    asset: 'CC0-1.0';
    holder: 'LogYourBody';
    annyEvaluated: '0.6.2';
    annyReleased: '2026-10-26';
    annyCodeLicense: 'Apache-2.0';
    annyDataLicense: 'CC0-1.0';
    annyBundled: false;
    smplxIncluded: false;
    smplIncluded: false;
    somaIncluded: false;
  };
  selectionRecord: string;
  audit: {
    presentation: WireframePresentation;
    adiposity: number;
    muscularity: number;
    frame: number;
    index: number;
    position: number[];
  }[];
}

const canonical = (value: number) => (Object.is(value, -0) ? 0 : value);
const round = (value: number) => canonical(Math.round(value * 1e6) / 1e6);

export const clampUnit = (value: number) => Math.min(1, Math.max(0, value));

/** Profile sex and uploaded images are intentionally not arguments. */
export function presentationChoice(stored: string | null | undefined): WireframePresentation {
  return stored === 'female' ? 'female' : 'male';
}

export function presentationChoiceFromUser(input: {
  stored?: string | null;
  profileSex?: string | null;
  imageHint?: string | null;
}): WireframePresentation {
  return presentationChoice(input.stored);
}

export function animationDuration(reduceMotion: boolean) {
  return reduceMotion ? 0 : animatedDuration;
}

export function yawFor(action: 'front' | 'side' | 'reset') {
  return action === 'side' ? YAW_SIDE : YAW_FRONT;
}

export function applyDrag(yaw: number, dx: number, dy: number) {
  if (Math.abs(dx) > Math.abs(dy)) return yaw;
  const next = yaw + dy * dragGain;
  return Math.max(-YAW_LIMIT, Math.min(YAW_LIMIT, next));
}

export function cacheKey(presentation: WireframePresentation, parameters: WireframeParameters) {
  const quantize = (value: number) => (Math.round(clampUnit(value) / 0.05) * 0.05).toFixed(2);
  return `${presentation}:${quantize(parameters.adiposity)}:${quantize(parameters.muscularity)}:${quantize(parameters.frame)}`;
}

function radii(presentation: WireframePresentation, t: number, parameters: WireframeParameters) {
  const shoulder = t * t;
  const belly = Math.exp(-((t - 0.32) ** 2) / 0.04);
  const chest = Math.exp(-((t - 0.74) ** 2) / 0.03);
  const female = presentation === 'female';
  let rx = female
    ? 0.3 + 0.04 * (1 - t) + 0.03 * shoulder
    : 0.27 + 0.01 * (1 - t) + 0.09 * shoulder;
  let rz = female ? 0.24 + 0.05 * chest + 0.03 * (1 - t) : 0.22 + 0.03 * chest + 0.02 * (1 - t);
  rx += parameters.adiposity * (0.05 + 0.09 * belly);
  rz += parameters.adiposity * (0.04 + 0.07 * belly);
  rx += parameters.muscularity * (0.01 + 0.045 * chest + 0.02 * shoulder);
  rz += parameters.muscularity * (0.01 + 0.04 * chest);
  rx += parameters.frame * (0.06 * shoulder - 0.015 * (1 - shoulder));
  rz += parameters.frame * (0.01 * shoulder);
  return { rx, rz };
}

function shape(presentation: WireframePresentation, parameters: WireframeParameters) {
  const vertices: number[][] = [];
  for (let ring = 0; ring < RINGS; ring += 1) {
    const t = ring / (RINGS - 1);
    const y = round(0.12 + t * 0.76);
    const { rx, rz } = radii(presentation, t, parameters);
    for (let segment = 0; segment < SEGMENTS; segment += 1) {
      const theta = (segment / SEGMENTS) * Math.PI * 2;
      vertices.push([round(Math.cos(theta) * rx), y, round(Math.sin(theta) * rz)]);
    }
  }
  return vertices;
}

function delta(to: number[][], from: number[][]) {
  return to.map((vertex, index) =>
    vertex.map((coordinate, axis) => round(coordinate - (from[index]?.[axis] ?? 0))),
  );
}

function wiresAndFaces() {
  const wires: number[][] = [];
  const faces: number[][] = [];
  for (let ring = 0; ring < RINGS; ring += 1) {
    for (let segment = 0; segment < SEGMENTS; segment += 1) {
      const current = ring * SEGMENTS + segment;
      wires.push([current, ring * SEGMENTS + ((segment + 1) % SEGMENTS)]);
      if (ring < RINGS - 1) {
        const below = current + SEGMENTS;
        const belowNext = ring * SEGMENTS + SEGMENTS + ((segment + 1) % SEGMENTS);
        const next = ring * SEGMENTS + ((segment + 1) % SEGMENTS);
        wires.push([current, below]);
        faces.push([current, next, below], [next, belowNext, below]);
      }
    }
  }
  return { wires, faces };
}

function rig(rest: number[][]) {
  const joints = [
    { name: 'waist', position: [0, 0.2, 0] },
    { name: 'ribcage', position: [0, 0.5, 0] },
    { name: 'chest', position: [0, 0.82, 0] },
  ];
  const weights = rest.map((vertex) => {
    const raw = joints.map((joint) => 1 / (Math.abs(vertex[1] - joint.position[1]) + 0.08));
    const total = raw.reduce((sum, value) => sum + value, 0);
    return raw.map((value) => round(value / total));
  });
  return { joints, weights, pose: 'identity' as const };
}

export function buildAsset(): WireframeAvatarAsset {
  const zero: WireframeParameters = { adiposity: 0, muscularity: 0, frame: 0 };
  const families = Object.fromEntries(
    PRESENTATIONS.map((presentation) => {
      const rest = shape(presentation, zero);
      return [
        presentation,
        {
          rest,
          adiposity: delta(shape(presentation, { ...zero, adiposity: 1 }), rest),
          muscularity: delta(shape(presentation, { ...zero, muscularity: 1 }), rest),
          frame: delta(shape(presentation, { ...zero, frame: 1 }), rest),
        },
      ];
    }),
  ) as WireframeAvatarAsset['families'];
  const { wires, faces } = wiresAndFaces();
  const asset: WireframeAvatarAsset = {
    modelId: MODEL_ID,
    version: MODEL_VERSION,
    topologyId: TOPOLOGY_ID,
    rigId: RIG_ID,
    illustrative: true,
    mapsToBodyFat: false,
    mapsToFfmi: false,
    pose: 'neutral-identity',
    crop: 'torso-chest-to-waist',
    vertexCount: RINGS * SEGMENTS,
    families,
    faces,
    wires,
    rig: rig(families.male.rest),
    parameters: {
      adiposity: { min: 0, max: 1, meaning: 'Illustrative size. Not a body-fat percentage.' },
      muscularity: { min: 0, max: 1, meaning: 'Illustrative muscle. Not FFMI.' },
      frame: { min: 0, max: 1, meaning: 'Illustrative proportion.' },
    },
    defaults: { presentation: 'male', adiposity: 0.5, muscularity: 0.5, frame: 0.5, yaw: 0 },
    camera: {
      projection: 'perspective',
      fovDegrees: 28,
      distance: 2.35,
      target: [0, 0.5, 0],
      frontYaw: YAW_FRONT,
      sideYaw: YAW_SIDE,
    },
    material: { kind: 'wire', fill: false, color: '#F5F7FB', lineWidth: 1.15, idleSpin: false },
    lighting: { model: 'unlit-wire', depthCue: 'opacity-by-depth' },
    caching: {
      tier: 'phone',
      vertexBudget: RINGS * SEGMENTS,
      wireBudget: wires.length,
      memoryEntries: 32,
      quantization: 0.05,
      disk: false,
      network: false,
      photoBytes: false,
    },
    license: {
      asset: 'CC0-1.0',
      holder: 'LogYourBody',
      annyEvaluated: '0.6.2',
      annyReleased: '2026-10-26',
      annyCodeLicense: 'Apache-2.0',
      annyDataLicense: 'CC0-1.0',
      annyBundled: false,
      smplxIncluded: false,
      smplIncluded: false,
      somaIncluded: false,
    },
    selectionRecord:
      'Evaluated NAVER Anny 0.6.2 (Apache-2.0 code, CC0 MakeHuman data). It is not bundled: the PyTorch runtime would block Home, LYB-321 forbids an Anny reconstruction provider or photo upload, and SMPL-X assets are non-commercial. This original torso keeps one topology and one rig so presentation and shape can interpolate. Sliders are illustrative, not body-fat or FFMI.',
    audit: [],
  };
  const samples: Array<{
    presentation: WireframePresentation;
    adiposity: number;
    muscularity: number;
    frame: number;
    index: number;
  }> = [
    { presentation: 'male', ...zero, index: 0 },
    { presentation: 'female', adiposity: 1, muscularity: 1, frame: 1, index: 4 },
    {
      presentation: 'male',
      adiposity: 0.5,
      muscularity: 0.5,
      frame: 0.5,
      index: 9 * SEGMENTS,
    },
  ];
  asset.audit = samples.map((sample) => ({
    ...sample,
    position: interpolate(asset, sample.presentation, sample)[sample.index] ?? [],
  }));
  return asset;
}

export function interpolate(
  asset: WireframeAvatarAsset,
  presentation: WireframePresentation,
  parameters: WireframeParameters,
): number[][] {
  const family = asset.families[presentation];
  const adiposity = clampUnit(parameters.adiposity);
  const muscularity = clampUnit(parameters.muscularity);
  const frame = clampUnit(parameters.frame);
  return family.rest.map((vertex, index) =>
    vertex.map((coordinate, axis) =>
      canonical(
        coordinate +
          adiposity * (family.adiposity[index]?.[axis] ?? 0) +
          muscularity * (family.muscularity[index]?.[axis] ?? 0) +
          frame * (family.frame[index]?.[axis] ?? 0),
      ),
    ),
  );
}

export function morph(
  from: ResolvedWireframe,
  to: ResolvedWireframe,
  t: number,
): { ok: true; wireframe: ResolvedWireframe } | { ok: false; reason: 'cross-topology' } {
  if (
    from.topologyId !== to.topologyId ||
    from.rigId !== to.rigId ||
    from.vertices.length !== to.vertices.length
  ) {
    return { ok: false, reason: 'cross-topology' };
  }
  const blend = Math.min(1, Math.max(0, t));
  return {
    ok: true,
    wireframe: {
      topologyId: from.topologyId,
      rigId: from.rigId,
      vertices: from.vertices.map((vertex, index) =>
        vertex.map(
          (coordinate, axis) =>
            coordinate + ((to.vertices[index]?.[axis] ?? coordinate) - coordinate) * blend,
        ),
      ),
    },
  };
}

function meanAbsX(vertices: number[][], ring: number) {
  let total = 0;
  for (let segment = 0; segment < SEGMENTS; segment += 1)
    total += Math.abs(vertices[ring * SEGMENTS + segment]?.[0] ?? 0);
  return total / SEGMENTS;
}

export function assess(asset: WireframeAvatarAsset) {
  const problems: string[] = [];
  if (
    asset.mapsToBodyFat ||
    asset.mapsToFfmi ||
    asset.license.annyBundled ||
    asset.license.smplxIncluded
  ) {
    problems.push('asset makes a forbidden measurement or license claim');
  }
  if (
    asset.material.idleSpin ||
    asset.caching.disk ||
    asset.caching.network ||
    asset.caching.photoBytes
  ) {
    problems.push('asset spins, persists photos, or fetches wire detail');
  }
  const presentations = Object.keys(asset.families);
  if (
    presentations.length !== 2 ||
    asset.families.male.rest.length !== asset.families.female.rest.length
  ) {
    problems.push('presentations do not share a vertex count');
  }
  const steps = [0, 0.5, 1];
  for (const presentation of PRESENTATIONS) {
    for (const adiposity of steps) {
      for (const muscularity of steps) {
        for (const frame of steps) {
          const parameters = { adiposity, muscularity, frame };
          const vertices = interpolate(asset, presentation, parameters);
          if (vertices.length !== asset.vertexCount)
            problems.push(`${presentation} changed vertex count`);
          vertices.forEach((vertex, index) => {
            if (vertex.some((coordinate) => !Number.isFinite(coordinate)))
              problems.push(`non-finite vertex ${index}`);
            const radius = Math.hypot(vertex[0] ?? 0, vertex[2] ?? 0);
            if (radius < 0.18 || radius > 0.62)
              problems.push(`${presentation} radius ${radius.toFixed(3)} at ${index}`);
          });
          for (let ring = 0; ring < RINGS - 1; ring += 1) {
            const y = vertices[ring * SEGMENTS]?.[1] ?? 0;
            const next = vertices[(ring + 1) * SEGMENTS]?.[1] ?? 0;
            if (!(next > y)) problems.push('rings are not stacked');
          }
        }
      }
    }
    const thin = interpolate(asset, presentation, { adiposity: 0, muscularity: 0, frame: 0 });
    const full = interpolate(asset, presentation, { adiposity: 1, muscularity: 0, frame: 0 });
    if (!(meanAbsX(full, 3) > meanAbsX(thin, 3)))
      problems.push(`${presentation} adiposity did not widen the waist`);
    const narrow = interpolate(asset, presentation, { adiposity: 0, muscularity: 0, frame: 0 });
    const broad = interpolate(asset, presentation, { adiposity: 0, muscularity: 0, frame: 1 });
    if (!(meanAbsX(broad, RINGS - 1) > meanAbsX(narrow, RINGS - 1)))
      problems.push(`${presentation} frame did not widen the shoulders`);
  }
  for (const parameters of [
    { adiposity: 0, muscularity: 0, frame: 0 },
    { adiposity: 0.5, muscularity: 0.5, frame: 0.5 },
    { adiposity: 1, muscularity: 1, frame: 1 },
  ]) {
    const male = meanAbsX(interpolate(asset, 'male', parameters), RINGS - 1);
    const female = meanAbsX(interpolate(asset, 'female', parameters), RINGS - 1);
    if (!(male > female)) problems.push('male and female shoulders lost their identity');
  }
  const same = interpolate(asset, 'male', { adiposity: 0.25, muscularity: 0.75, frame: 0.5 });
  const again = interpolate(asset, 'male', { adiposity: 0.25, muscularity: 0.75, frame: 0.5 });
  if (JSON.stringify(same) !== JSON.stringify(again)) problems.push('interpolation is not stable');
  for (const sample of asset.audit) {
    const position = interpolate(asset, sample.presentation, sample)[sample.index];
    if (
      !position ||
      position.some(
        (coordinate, axis) => Math.abs(coordinate - (sample.position[axis] ?? 0)) > 1e-9,
      )
    ) {
      problems.push(`audit vertex ${sample.index} drifted`);
    }
  }
  const resolved = (presentation: WireframePresentation): ResolvedWireframe => ({
    topologyId: asset.topologyId,
    rigId: asset.rigId,
    vertices: interpolate(asset, presentation, asset.defaults),
  });
  const blended = morph(resolved('male'), resolved('female'), 0.5);
  if (!blended.ok) problems.push('same-topology presentation morph was refused');
  const refused = morph(resolved('male'), { ...resolved('female'), topologyId: 'smplx' }, 0.5);
  if (refused.ok) problems.push('cross-topology morph was accepted');
  return problems;
}
