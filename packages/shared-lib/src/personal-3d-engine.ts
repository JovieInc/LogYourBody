/**
 * Optional personal 3D body evaluation for LYB-316.
 *
 * The runnable route fits the original CC0 torso. Bodygram and DiGS-Avatar
 * are recorded from public docs and are not executed. See
 * docs/product/personal-3d-engine.md.
 */

import { Buffer } from 'node:buffer';
import { arch, cpus, platform, release, totalmem } from 'node:os';
import { performance } from 'node:perf_hooks';
import {
  buildAsset,
  interpolate,
  RINGS,
  SEGMENTS,
  TOPOLOGY_ID,
  YAW_FRONT,
  YAW_SIDE,
  type WireframeAvatarAsset,
  type WireframeParameters,
  type WireframePresentation,
} from './wireframe-avatar-family';

export const SELECTED_ENGINE_ID = 'lyb.personal.parametric.wireframe.v1';
export const FALLBACK_ENGINE_ID = 'lyb.wireframe.torso';
export const ISSUE = 'LYB-316';

const GRID = [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1];

export const syntheticTruth: WireframeParameters = {
  adiposity: 0.62,
  muscularity: 0.18,
  frame: 0.71,
};

export const syntheticSession = 'synthetic-session-a';
export const otherSession = 'synthetic-session-b';

export interface StageTimings {
  preprocessingMs: number;
  modelInferenceMs: number;
  meshProcessingMs: number;
  assetTransferMs: number;
  frameRenderingMs: number;
  endToEndMs: number;
  cacheHit: boolean;
}

export interface FitProbe {
  id: string;
  views: Array<'front' | 'side'>;
  rings: number[];
  parameterError: number;
  vertexError: number;
  matchCount: number;
  worstVertexError: number;
  parameters: WireframeParameters;
}

export interface PersonalBodyReport {
  issue: typeof ISSUE;
  selectedEngineId: typeof SELECTED_ENGINE_ID;
  fallbackEngineId: typeof FALLBACK_ENGINE_ID;
  personalizedProduction: false;
  addsCaptureStep: false;
  mapsToBodyFat: false;
  mapsToDexa: false;
  topologyId: typeof TOPOLOGY_ID;
  host: {
    platform: string;
    arch: string;
    release: string;
    cpuModel: string;
    cpuCount: number;
    memoryBytes: number;
    node: string;
  };
  evidence: {
    source: 'host-cpu';
    simulator: 'not-run';
    physicalDevice: 'not-run';
    distributedBuild: 'not-run';
    vendorTimingsAreAppBenchmarks: false;
  };
  parametric: {
    executed: true;
    runtime: typeof FALLBACK_ENGINE_ID;
    externalAnnyExecuted: false;
    pose: 'neutral-identity';
    crop: 'torso-chest-to-waist';
    clothing: 'unsupported';
    hiddenSurface: 'parameter-extrapolation';
    vertexCorrespondence: true;
    nativeRenderability: 'cpu-orthographic-wire';
    vertexCount: number;
    transferredBytes: number;
    renderedFrames: number;
    sameDayMaxVertexDelta: number;
    timings: { cold: StageTimings; warm: StageTimings };
    probes: FitProbe[];
    improvedRings: number[];
    unchangedRings: number[];
    worseRings: number[];
    candidateCount: number;
    extraContemporaneousViewImprovesFit: boolean;
  };
  bodygram: CandidateRecord;
  digs: CandidateRecord;
  outOfScope: OutOfScopeRecord;
}

interface CandidateRecord {
  id: 'bodygram' | 'digs-avatar';
  status: 'rejected';
  executed: false;
  measuredEndToEndMs: null;
  crossScanTopology: 'not-documented' | 'not-a-mesh';
  directDexaOrBodyFatControl: false;
  reason: string;
}

interface OutOfScopeRecord {
  omniFlashOutput: 'video-audio';
  omniFlashVerifiedMeshApi: false;
  gnmPublicRelease: 'head';
  gnmPublicBody: false;
  mojuloMatchesCompilerWording: true;
  mojuloIsBodyReconstruction: false;
  meshlibResult: 'existing-mesh-boolean';
  meshlibSeconds: { meshlib: 0.08; trimeshBlender: 13 };
  meshlibIsReconstruction: false;
  exactRememberedDemoConfirmed: false;
}

interface Observation {
  rings: number[];
  front: number[] | null;
  side: number[] | null;
}

interface GridEntry {
  parameters: WireframeParameters;
  front: number[];
  side: number[];
  vertices: number[][];
}

let cachedAsset: WireframeAvatarAsset | null = null;
let cachedGrid: GridEntry[] | null = null;

function now() {
  return performance.now();
}

function round(value: number) {
  return Object.is(value, -0) ? 0 : Math.round(value * 1e6) / 1e6;
}

function parameterError(found: WireframeParameters) {
  return round(
    Math.abs(found.adiposity - syntheticTruth.adiposity) +
      Math.abs(found.muscularity - syntheticTruth.muscularity) +
      Math.abs(found.frame - syntheticTruth.frame),
  );
}

function widths(vertices: number[][]) {
  const front: number[] = [];
  const side: number[] = [];
  for (let ring = 0; ring < RINGS; ring += 1) {
    let maxX = 0;
    let maxZ = 0;
    for (let segment = 0; segment < SEGMENTS; segment += 1) {
      const vertex = vertices[ring * SEGMENTS + segment] ?? [0, 0, 0];
      maxX = Math.max(maxX, Math.abs(vertex[0] ?? 0));
      maxZ = Math.max(maxZ, Math.abs(vertex[2] ?? 0));
    }
    front.push(round(maxX * 2));
    side.push(round(maxZ * 2));
  }
  return { front, side };
}

function asset(cold: boolean) {
  if (cold) {
    cachedAsset = null;
    cachedGrid = null;
  }
  cachedAsset ??= buildAsset();
  return cachedAsset;
}

function gridFor(model: WireframeAvatarAsset, presentation: WireframePresentation) {
  if (cachedGrid) return { entries: cachedGrid, cacheHit: true };
  const entries: GridEntry[] = [];
  for (const adiposity of GRID) {
    for (const muscularity of GRID) {
      for (const frame of GRID) {
        const parameters = { adiposity, muscularity, frame };
        const vertices = interpolate(model, presentation, parameters);
        const silhouette = widths(vertices);
        entries.push({ parameters, vertices, ...silhouette });
      }
    }
  }
  cachedGrid = entries;
  return { entries, cacheHit: false };
}

function observationLoss(entry: GridEntry, observation: Observation) {
  let total = 0;
  for (const ring of observation.rings) {
    if (observation.front) {
      const delta = (entry.front[ring] ?? 0) - (observation.front[ring] ?? 0);
      total += delta * delta;
    }
    if (observation.side) {
      const delta = (entry.side[ring] ?? 0) - (observation.side[ring] ?? 0);
      total += delta * delta;
    }
  }
  return total;
}

function nearerNeutral(candidate: WireframeParameters, incumbent: WireframeParameters) {
  const distance = (value: WireframeParameters) =>
    Math.abs(value.adiposity - 0.5) +
    Math.abs(value.muscularity - 0.5) +
    Math.abs(value.frame - 0.5);
  const left = distance(candidate);
  const right = distance(incumbent);
  if (left !== right) return left < right;
  return (
    candidate.adiposity < incumbent.adiposity ||
    (candidate.adiposity === incumbent.adiposity && candidate.muscularity < incumbent.muscularity)
  );
}

function matches(entries: GridEntry[], observation: Observation) {
  let bestLoss = Number.POSITIVE_INFINITY;
  const scored = entries.map((entry) => {
    const loss = observationLoss(entry, observation);
    bestLoss = Math.min(bestLoss, loss);
    return { entry, loss };
  });
  const tied = scored.filter((item) => item.loss <= bestLoss + 1e-12).map((item) => item.entry);
  let best = tied[0];
  if (!best) throw new Error('parametric grid is empty');
  for (const entry of tied) {
    if (nearerNeutral(entry.parameters, best.parameters)) best = entry;
  }
  return { best, tied };
}

function vertexError(found: number[][], truth: number[][]) {
  let total = 0;
  for (let index = 0; index < truth.length; index += 1) {
    const left = found[index] ?? [0, 0, 0];
    const right = truth[index] ?? [0, 0, 0];
    total += Math.abs((left[0] ?? 0) - (right[0] ?? 0));
    total += Math.abs((left[1] ?? 0) - (right[1] ?? 0));
    total += Math.abs((left[2] ?? 0) - (right[2] ?? 0));
  }
  return round(total / Math.max(1, truth.length * 3));
}

function renderWires(vertices: number[][], wires: number[][], yaw: number) {
  const cosine = Math.cos(yaw);
  const sine = Math.sin(yaw);
  let segments = 0;
  for (const wire of wires) {
    const start = vertices[wire[0] ?? 0] ?? [0, 0, 0];
    const end = vertices[wire[1] ?? 0] ?? [0, 0, 0];
    const project = (vertex: number[]) => {
      const x = (vertex[0] ?? 0) * cosine + (vertex[2] ?? 0) * sine;
      const y = vertex[1] ?? 0;
      return [100 + x * 180, 140 - (y - 0.5) * 220];
    };
    project(start);
    project(end);
    segments += 1;
  }
  return segments;
}

function observe(truth: GridEntry, views: Array<'front' | 'side'>, rings: number[]): Observation {
  return {
    rings,
    front: views.includes('front') ? truth.front : null,
    side: views.includes('side') ? truth.side : null,
  };
}

function probe(
  entries: GridEntry[],
  truth: GridEntry,
  id: string,
  views: Array<'front' | 'side'>,
  rings: number[],
): FitProbe {
  const found = matches(entries, observe(truth, views, rings));
  const worstVertexError = found.tied.reduce(
    (worst, entry) => Math.max(worst, vertexError(entry.vertices, truth.vertices)),
    0,
  );
  return {
    id,
    views,
    rings,
    parameterError: parameterError(found.best.parameters),
    vertexError: vertexError(found.best.vertices, truth.vertices),
    matchCount: found.tied.length,
    worstVertexError: round(worstVertexError),
    parameters: found.best.parameters,
  };
}

function emptyTimings(cacheHit: boolean): StageTimings {
  return {
    preprocessingMs: 0,
    modelInferenceMs: 0,
    meshProcessingMs: 0,
    assetTransferMs: 0,
    frameRenderingMs: 0,
    endToEndMs: 0,
    cacheHit,
  };
}

export function runParametric(cold: boolean) {
  const timings = emptyTimings(false);
  const started = now();
  const preprocessStarted = now();
  const presentation: WireframePresentation = 'male';
  const model = asset(cold);
  const truthVertices = interpolate(model, presentation, syntheticTruth);
  const truthSilhouette = widths(truthVertices);
  const truth: GridEntry = {
    parameters: syntheticTruth,
    vertices: truthVertices,
    ...truthSilhouette,
  };
  const rings = Array.from({ length: RINGS }, (_, index) => index);
  timings.preprocessingMs = now() - preprocessStarted;

  const inferenceStarted = now();
  const searched = gridFor(model, presentation);
  timings.cacheHit = searched.cacheHit;
  const probes = [
    probe(searched.entries, truth, 'full-front', ['front'], rings),
    probe(searched.entries, truth, 'full-front-side', ['front', 'side'], rings),
  ];
  for (const ring of rings) {
    probes.push(probe(searched.entries, truth, `ring-${ring}-front`, ['front'], [ring]));
    probes.push(
      probe(searched.entries, truth, `ring-${ring}-front-side`, ['front', 'side'], [ring]),
    );
  }
  timings.modelInferenceMs = now() - inferenceStarted;

  const meshStarted = now();
  const fitted = probes.find((item) => item.id === 'full-front-side')?.parameters ?? syntheticTruth;
  const mesh = interpolate(model, presentation, fitted);
  timings.meshProcessingMs = now() - meshStarted;

  const transferStarted = now();
  const transferred = mesh.map((vertex) => vertex.slice());
  const transferredBytes = Buffer.byteLength(JSON.stringify(transferred));
  timings.assetTransferMs = now() - transferStarted;

  const renderStarted = now();
  const frontFrames = renderWires(transferred, model.wires, YAW_FRONT);
  const sideFrames = renderWires(transferred, model.wires, YAW_SIDE);
  timings.frameRenderingMs = now() - renderStarted;
  timings.endToEndMs = now() - started;

  const repeat = interpolate(model, presentation, fitted);
  let sameDayMaxVertexDelta = 0;
  for (let index = 0; index < mesh.length; index += 1) {
    for (let axis = 0; axis < 3; axis += 1) {
      sameDayMaxVertexDelta = Math.max(
        sameDayMaxVertexDelta,
        Math.abs((mesh[index]?.[axis] ?? 0) - (repeat[index]?.[axis] ?? 0)),
      );
    }
  }

  const compared = rings.map((ring) => {
    const front = probes.find((item) => item.id === `ring-${ring}-front`);
    const both = probes.find((item) => item.id === `ring-${ring}-front-side`);
    return { ring, front: front?.vertexError ?? 0, both: both?.vertexError ?? 0 };
  });
  const improvedRings = compared.filter((item) => item.both < item.front).map((item) => item.ring);
  const worseRings = compared.filter((item) => item.both > item.front).map((item) => item.ring);
  const unchangedRings = compared
    .filter((item) => item.both === item.front)
    .map((item) => item.ring);
  const extraContemporaneousViewImprovesFit = improvedRings.length > 0;

  return {
    timings,
    probes,
    vertexCount: mesh.length,
    transferredBytes,
    renderedFrames: frontFrames > 0 && sideFrames > 0 ? 2 : 0,
    sameDayMaxVertexDelta,
    extraContemporaneousViewImprovesFit,
    improvedRings,
    unchangedRings,
    worseRings,
    candidateCount: searched.entries.length,
  };
}

export function capturesShareOneBodyState(captures: { bodyState: string }[]) {
  const states = new Set(captures.map((capture) => capture.bodyState));
  return states.size <= 1;
}

export function productionPersonalBody(
  input: { photoByteCount?: number; captures?: { bodyState: string }[] } = {},
) {
  if ((input.photoByteCount ?? 0) > 0) {
    return {
      engineId: FALLBACK_ENGINE_ID,
      personalized: false as const,
      reason: 'photo-bytes-refused',
    };
  }
  if (input.captures && !capturesShareOneBodyState(input.captures)) {
    return {
      engineId: FALLBACK_ENGINE_ID,
      personalized: false as const,
      reason: 'different-body-state',
    };
  }
  return {
    engineId: FALLBACK_ENGINE_ID,
    personalized: false as const,
    reason: 'personalization-disabled',
  };
}

export const bodygram: CandidateRecord = {
  id: 'bodygram',
  status: 'rejected',
  executed: false,
  measuredEndToEndMs: null,
  crossScanTopology: 'not-documented',
  directDexaOrBodyFatControl: false,
  reason:
    'Public Platform docs return a base64 OBJ and, with two photos, a separate body-fat field. They do not document stable cross-scan vertices or a direct DEXA control. No credential, purchase, or upload was used.',
};

export const digs: CandidateRecord = {
  id: 'digs-avatar',
  status: 'rejected',
  executed: false,
  measuredEndToEndMs: null,
  crossScanTopology: 'not-a-mesh',
  directDexaOrBodyFatControl: false,
  reason:
    'The repository is MIT, and the published path needs SMPL-X, DINOv3, SANA, IDOL, and a student checkpoint that the repository does not grant. Those terms were not cleared, so the pipeline was not run. The README 0.71s figure is not an app benchmark.',
};

export const outOfScope: OutOfScopeRecord = {
  omniFlashOutput: 'video-audio',
  omniFlashVerifiedMeshApi: false,
  gnmPublicRelease: 'head',
  gnmPublicBody: false,
  mojuloMatchesCompilerWording: true,
  mojuloIsBodyReconstruction: false,
  meshlibResult: 'existing-mesh-boolean',
  meshlibSeconds: { meshlib: 0.08, trimeshBlender: 13 },
  meshlibIsReconstruction: false,
  exactRememberedDemoConfirmed: false,
};

export function decisionRecord() {
  return {
    issue: ISSUE,
    selectedEngineId: SELECTED_ENGINE_ID,
    fallbackEngineId: FALLBACK_ENGINE_ID,
    personalizedProduction: false as const,
    addsCaptureStep: false as const,
    mapsToBodyFat: false as const,
    mapsToDexa: false as const,
    topologyId: TOPOLOGY_ID,
    releaseStage: 'disabled' as const,
    flagKey: 'personal_body_engine',
    killSwitchKey: 'personal_body_engine_kill_switch',
    pose: 'neutral-identity' as const,
    crop: 'torso-chest-to-waist' as const,
    clothing: 'unsupported' as const,
    candidates: [
      { id: bodygram.id, status: bodygram.status, executed: bodygram.executed },
      { id: 'parametric-wireframe', status: 'selected' as const, executed: true },
      { id: digs.id, status: digs.status, executed: digs.executed },
    ],
    unsupported: {
      omniFlashVerifiedMeshApi: false as const,
      gnmPublicBody: false as const,
      mojuloIsBodyReconstruction: false as const,
      meshlibTimingIsReconstruction: false as const,
      exactRememberedDemoConfirmed: false as const,
    },
  };
}

export function compare(): PersonalBodyReport {
  const cold = runParametric(true);
  const warm = runParametric(false);
  return {
    issue: ISSUE,
    selectedEngineId: SELECTED_ENGINE_ID,
    fallbackEngineId: FALLBACK_ENGINE_ID,
    personalizedProduction: false,
    addsCaptureStep: false,
    mapsToBodyFat: false,
    mapsToDexa: false,
    topologyId: TOPOLOGY_ID,
    host: {
      platform: platform(),
      arch: arch(),
      release: release(),
      cpuModel: cpus()[0]?.model ?? 'unknown',
      cpuCount: cpus().length,
      memoryBytes: totalmem(),
      node: process.version,
    },
    evidence: {
      source: 'host-cpu',
      simulator: 'not-run',
      physicalDevice: 'not-run',
      distributedBuild: 'not-run',
      vendorTimingsAreAppBenchmarks: false,
    },
    parametric: {
      executed: true,
      runtime: FALLBACK_ENGINE_ID,
      externalAnnyExecuted: false,
      pose: 'neutral-identity',
      crop: 'torso-chest-to-waist',
      clothing: 'unsupported',
      hiddenSurface: 'parameter-extrapolation',
      vertexCorrespondence: true,
      nativeRenderability: 'cpu-orthographic-wire',
      vertexCount: cold.vertexCount,
      transferredBytes: cold.transferredBytes,
      renderedFrames: cold.renderedFrames,
      sameDayMaxVertexDelta: cold.sameDayMaxVertexDelta,
      timings: { cold: cold.timings, warm: warm.timings },
      probes: cold.probes,
      improvedRings: cold.improvedRings,
      unchangedRings: cold.unchangedRings,
      worseRings: cold.worseRings,
      candidateCount: cold.candidateCount,
      extraContemporaneousViewImprovesFit: cold.extraContemporaneousViewImprovesFit,
    },
    bodygram,
    digs,
    outOfScope,
  };
}

export function assess(report: PersonalBodyReport) {
  const problems: string[] = [];
  const stages = [
    'preprocessingMs',
    'modelInferenceMs',
    'meshProcessingMs',
    'assetTransferMs',
    'frameRenderingMs',
    'endToEndMs',
  ] as const;
  for (const pass of [report.parametric.timings.cold, report.parametric.timings.warm]) {
    for (const stage of stages) {
      if (!Number.isFinite(pass[stage]) || pass[stage] < 0) problems.push(`bad timing ${stage}`);
    }
  }
  if (!report.parametric.timings.warm.cacheHit) problems.push('warm pass did not reuse the grid');
  if (report.parametric.timings.cold.cacheHit) problems.push('cold pass reused the grid');
  if (report.parametric.sameDayMaxVertexDelta !== 0) problems.push('same-day repeat drifted');
  const ringPartition = [
    ...report.parametric.improvedRings,
    ...report.parametric.unchangedRings,
    ...report.parametric.worseRings,
  ];
  if (!report.parametric.extraContemporaneousViewImprovesFit)
    problems.push('side view did not improve the partial fit');
  if (report.parametric.worseRings.length === 0)
    problems.push('side view was treated as uniformly helpful');
  if (ringPartition.length !== RINGS || new Set(ringPartition).size !== RINGS) {
    problems.push('ring crops were not fully compared');
  }
  const fullFront = report.parametric.probes.find((item) => item.id === 'full-front');
  const full = report.parametric.probes.find((item) => item.id === 'full-front-side');
  if (!fullFront || !full || full.vertexError > fullFront.vertexError) {
    problems.push('full side view made the torso fit worse');
  }
  if (report.bodygram.executed || report.digs.executed)
    problems.push('a blocked engine was executed');
  if (report.bodygram.measuredEndToEndMs !== null || report.digs.measuredEndToEndMs !== null) {
    problems.push('vendor research timing was stored as an app measurement');
  }
  if (report.bodygram.directDexaOrBodyFatControl || report.digs.directDexaOrBodyFatControl) {
    problems.push('an unverified composition control was assumed');
  }
  if (
    report.personalizedProduction ||
    report.addsCaptureStep ||
    report.mapsToBodyFat ||
    report.mapsToDexa
  ) {
    problems.push('production claims a personal measurement or a new capture step');
  }
  if (report.evidence.vendorTimingsAreAppBenchmarks) problems.push('vendor timings were adopted');
  if (report.outOfScope.omniFlashVerifiedMeshApi || report.outOfScope.gnmPublicBody) {
    problems.push('an unsupported generator was treated as a body mesh');
  }
  if (report.outOfScope.exactRememberedDemoConfirmed || report.outOfScope.meshlibIsReconstruction) {
    problems.push('an unconfirmed demo was treated as reconstruction');
  }
  const photo = productionPersonalBody({ photoByteCount: 12 });
  const mixed = productionPersonalBody({
    captures: [{ bodyState: syntheticSession }, { bodyState: otherSession }],
  });
  if (photo.personalized || photo.reason !== 'photo-bytes-refused')
    problems.push('photo bytes were accepted');
  if (mixed.personalized || mixed.reason !== 'different-body-state')
    problems.push('body states were merged');
  return problems;
}
