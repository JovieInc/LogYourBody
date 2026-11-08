import type { TOPOLOGY_ID, WireframeParameters } from './wireframe-avatar-family';

export const SELECTED_ENGINE_ID = 'lyb.personal.parametric.wireframe.v1';
export const FALLBACK_ENGINE_ID = 'lyb.wireframe.torso';
export const ISSUE = 'LYB-316';

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

export interface CandidateRecord {
  id: 'bodygram' | 'digs-avatar';
  status: 'rejected';
  executed: false;
  measuredEndToEndMs: null;
  crossScanTopology: 'not-documented' | 'not-a-mesh';
  directDexaOrBodyFatControl: false;
  reason: string;
}

export interface OutOfScopeRecord {
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

export interface Observation {
  rings: number[];
  front: number[] | null;
  side: number[] | null;
}

export interface GridEntry {
  parameters: WireframeParameters;
  front: number[];
  side: number[];
  vertices: number[][];
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
