/**
 * Photographic appearance on the accepted personal outline (LYB-319).
 *
 * Samples already taken on the phone are projected onto the stable mesh, or
 * stored as a Gaussian layer of those same samples. DiGS-Avatar, SMPL, and
 * Anny are not bundled. A turntable video is not interactive 3D. Projection
 * never edits the accepted shape or the original photo samples.
 */

export const APPEARANCE_SCHEMA = 'lyb.photographic-appearance.v1';
export const PROJECTION_ID = 'lyb.appearance.photo-projection.v1';
export const GAUSSIAN_LAYER_ID = 'lyb.appearance.gaussian-layer.v1';
export const PRESENTATION_VERSION = 'lyb.appearance.presentation.v1';
export const FRAMING_ID = 'lyb.capture.framing.v1';
export const MODEL_ID = 'lyb.wireframe.torso';
export const MODEL_VERSION = '1.0.0';
export const TOPOLOGY_ID = 'lyb.wireframe.torso.v1';
export const RIG_ID = 'lyb.wireframe.torso.rig.v1';
export const LICENSE_ID = 'CC0-1.0';
export const RIGHTS_HOLDER = 'first-party';
export const CELLS_PER_REGION = 8;
export const BASELINE_COVERAGE = 0;
export const REGIONS = ['front', 'side', 'back'] as const;

export const BUDGET = {
  texelStride: 16,
  splatStride: 48,
  maxBytes: 4_096,
  lowEndMaxBytes: 1_024,
  cellCount: REGIONS.length * CELLS_PER_REGION,
} as const;

export const RELEASE = {
  blocksPaidR1: false,
  blocksPhotoTimeline: false,
  blocksWireframe: false,
  blocksPersonalMesh: false,
} as const;

export const RIGHTS = {
  licenseId: LICENSE_ID,
  holder: RIGHTS_HOLDER,
  bundledModels: [] as string[],
  allowedModels: [PROJECTION_ID, GAUSSIAN_LAYER_ID, 'first-party'] as string[],
  refusedModels: ['DiGS-Avatar', 'SMPL', 'SMPL-X', 'SOMA', 'Anny'],
} as const;

export type Region = (typeof REGIONS)[number];
export type Representation = 'projection' | 'gaussian' | 'turntable';
export type Thermal = 'nominal' | 'fair' | 'serious' | 'critical';
export type SampleQuality = 'supported' | 'poor' | 'occluded' | 'poseChanged' | 'missing';
export type Provenance = 'observed' | 'inferred';
export type FallbackReason =
  | 'not-interactive'
  | 'remote-regeneration'
  | 'gesture'
  | 'license'
  | 'compute'
  | 'thermal'
  | 'budget'
  | 'unsupported'
  | 'model';

export interface Shape {
  adiposity: number;
  muscularity: number;
  frame: number;
  depth: number;
}

export interface AcceptedGeometry {
  snapshotId: string;
  accountId: string;
  bodyId: string;
  effectiveDate: string;
  captureDate: string;
  modelId: string;
  modelVersion: string;
  topologyId: string;
  rigId: string;
  framingId: string;
  shape: Shape;
}

export interface PhotoSample {
  accountId: string;
  photoId: string;
  view: Region | 'diary';
  effectiveDate: string;
  captureDate: string;
  framingId: string;
  quality: SampleQuality;
  samples: readonly number[];
  sourceDigest: string;
}

export interface AppearanceTexel {
  cellId: string;
  region: Region;
  slot: number;
  provenance: Provenance;
  tone: number | null;
  photoId: string | null;
}

export interface GaussianSplat {
  cellId: string;
  slot: number;
  tone: number;
  opacity: number;
  provenance: 'observed';
}

export interface AppearanceAsset {
  schema: typeof APPEARANCE_SCHEMA;
  id: string;
  cacheKey: string;
  snapshotId: string;
  accountId: string;
  bodyId: string;
  effectiveDate: string;
  captureDate: string;
  modelId: string;
  modelVersion: string;
  presentationVersion: typeof PRESENTATION_VERSION;
  topologyId: string;
  rigId: string;
  framingId: string;
  shape: Shape;
  licenseId: typeof LICENSE_ID;
  rights: typeof RIGHTS_HOLDER;
  projectionId: typeof PROJECTION_ID;
  gaussianLayerId: typeof GAUSSIAN_LAYER_ID | null;
  representation: 'projection' | 'gaussian';
  texels: AppearanceTexel[];
  splats: GaussianSplat[];
  photoIds: string[];
  sourceDigests: Record<string, string>;
  geometryDrift: number;
  appearanceDrift: number;
  observedCount: number;
  inferredCount: number;
  interactive: true;
  claimsBodyFat: false;
  claimsWeeklyChange: false;
}

export interface AppearanceArchive {
  accountId: string;
  samples: PhotoSample[];
  geometries: AcceptedGeometry[];
  assets: AppearanceAsset[];
}

export interface ProjectOptions {
  representation: Representation;
  computeAvailable: boolean;
  licenseOk: boolean;
  requestedModel: string | null;
  thermal: Thermal;
  lowEndDevice: boolean;
  reduceMotion: boolean;
  gesture: boolean;
  remoteRequested: boolean;
  memoryLimitBytes: number | null;
}

export type ProjectResult =
  | { kind: 'asset'; asset: AppearanceAsset; reason: null }
  | {
      kind: 'fallback';
      asset: null;
      reason: FallbackReason;
      retains: readonly ['photo', 'wireframe', 'personal-mesh'];
    };

export interface PromotionEvidence {
  tier: 'none' | 'repeatable-on-device' | 'calibrated';
  baselineObservedCoverage: number;
  observedCoverage: number;
  geometryDrift: number;
  introducedBodyFatClaim: boolean;
  introducedWeeklyChange: boolean;
  truthfulProgress: boolean;
  rightsRecorded: boolean;
  lowEndDeviceEvidence: 'absent' | 'source' | 'simulator' | 'physical-device' | 'distributed-build';
}

export function emptyArchive(accountId: string): AppearanceArchive {
  return { accountId, samples: [], geometries: [], assets: [] };
}

export function defaultOptions(): ProjectOptions {
  return {
    representation: 'projection',
    computeAvailable: true,
    licenseOk: true,
    requestedModel: null,
    thermal: 'nominal',
    lowEndDevice: false,
    reduceMotion: false,
    gesture: false,
    remoteRequested: false,
    memoryLimitBytes: null,
  };
}

export function fingerprint(parts: string[]): string {
  let hash = 2_166_136_261;
  const text = parts.join('\u001f');
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16_777_619);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

export function copyShape(shape: Shape): Shape {
  return {
    adiposity: shape.adiposity,
    muscularity: shape.muscularity,
    frame: shape.frame,
    depth: shape.depth,
  };
}

export function shapeDrift(left: Shape, right: Shape): number {
  return Math.max(
    Math.abs(left.adiposity - right.adiposity),
    Math.abs(left.muscularity - right.muscularity),
    Math.abs(left.frame - right.frame),
    Math.abs(left.depth - right.depth),
  );
}

/** Appearance may report a rejected delta. It returns the accepted shape. */
export function sealedShape(
  accepted: Shape,
  proposed: Shape | null,
): { shape: Shape; rejectedDelta: number } {
  return {
    shape: copyShape(accepted),
    rejectedDelta: proposed ? shapeDrift(accepted, proposed) : 0,
  };
}
