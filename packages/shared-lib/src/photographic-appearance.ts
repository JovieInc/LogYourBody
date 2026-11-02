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

const RETAINS = ['photo', 'wireframe', 'personal-mesh'] as const;

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

export function replaceOriginal(
  original: readonly number[],
  proposed: readonly number[],
): { ok: false; reason: 'original-photo'; original: number; proposed: number } {
  return {
    ok: false,
    reason: 'original-photo',
    original: original.length,
    proposed: proposed.length,
  };
}

export function estimateBytes(
  representation: 'projection' | 'gaussian',
  observedCount: number,
): number {
  const projection = BUDGET.cellCount * BUDGET.texelStride;
  if (representation === 'projection') return projection;
  return projection + observedCount * BUDGET.splatStride;
}

export function withinBudget(
  bytes: number,
  lowEndDevice: boolean,
  memoryLimitBytes: number | null,
): boolean {
  const tier = lowEndDevice ? BUDGET.lowEndMaxBytes : BUDGET.maxBytes;
  const limit = memoryLimitBytes == null ? tier : Math.min(tier, memoryLimitBytes);
  return bytes <= limit;
}

export function visibleRegion(yaw: number): Region {
  const wrapped = Math.atan2(Math.sin(yaw), Math.cos(yaw));
  const distance = Math.abs(wrapped);
  if (distance <= Math.PI / 4) return 'front';
  if (distance >= (Math.PI * 3) / 4) return 'back';
  return 'side';
}

export function motion(reduceMotion: boolean): { duration: number; autoSpin: false } {
  return { duration: reduceMotion ? 0 : 0.2, autoSpin: false };
}

export function coverage(asset: AppearanceAsset | null): number {
  if (!asset || asset.texels.length === 0) return 0;
  return asset.observedCount / asset.texels.length;
}

export function appearanceLabel(asset: AppearanceAsset): string {
  const observed = REGIONS.filter((region) =>
    asset.texels.some((texel) => texel.region === region && texel.provenance === 'observed'),
  );
  if (observed.length === 0) return 'Unseen surfaces stay unmarked';
  return `Observed ${joinRegions(observed)}. Unseen surfaces stay unmarked.`;
}

function joinRegions(regions: readonly string[]): string {
  if (regions.length === 1) return regions[0] ?? '';
  if (regions.length === 2) return `${regions[0]} and ${regions[1]}`;
  return `${regions.slice(0, -1).join(', ')}, and ${regions[regions.length - 1]}`;
}

function fallback(reason: FallbackReason): ProjectResult {
  return { kind: 'fallback', asset: null, reason, retains: RETAINS };
}

function usable(
  sample: PhotoSample,
  geometry: AcceptedGeometry,
): sample is PhotoSample & { view: Region } {
  if (sample.accountId !== geometry.accountId) return false;
  if (sample.effectiveDate !== geometry.effectiveDate) return false;
  if (sample.view === 'diary') return false;
  if (sample.quality !== 'supported') return false;
  if (sample.framingId !== geometry.framingId || sample.framingId !== FRAMING_ID) return false;
  if (!sample.photoId || !sample.captureDate || !sample.sourceDigest) return false;
  if (sample.samples.length !== CELLS_PER_REGION) return false;
  return sample.samples.every((tone) => Number.isFinite(tone) && tone >= 0 && tone <= 1);
}

function acceptedModel(geometry: AcceptedGeometry): boolean {
  return (
    geometry.modelId === MODEL_ID &&
    geometry.modelVersion === MODEL_VERSION &&
    geometry.topologyId === TOPOLOGY_ID &&
    geometry.rigId === RIG_ID &&
    geometry.framingId === FRAMING_ID &&
    geometry.snapshotId.length > 0 &&
    geometry.bodyId.length > 0
  );
}

function listed(models: readonly string[], requested: string): boolean {
  return models.some((model) => model === requested);
}

function licenseRefusal(options: ProjectOptions): boolean {
  if (!options.licenseOk) return true;
  const requested = options.requestedModel;
  if (!requested) return false;
  if (listed(RIGHTS.refusedModels, requested)) return true;
  return !listed(RIGHTS.allowedModels, requested);
}

function representationFor(
  options: ProjectOptions,
  observedCount: number,
): 'projection' | 'gaussian' | null {
  if (options.representation === 'turntable') return null;
  const wanted = options.representation === 'gaussian' ? 'gaussian' : 'projection';
  if (
    withinBudget(
      estimateBytes(wanted, observedCount),
      options.lowEndDevice,
      options.memoryLimitBytes,
    )
  ) {
    return wanted;
  }
  if (
    wanted === 'gaussian' &&
    withinBudget(
      estimateBytes('projection', observedCount),
      options.lowEndDevice,
      options.memoryLimitBytes,
    )
  ) {
    return 'projection';
  }
  return null;
}

export function project(
  geometry: AcceptedGeometry,
  samples: readonly PhotoSample[],
  options: ProjectOptions,
): ProjectResult {
  if (options.gesture) return fallback('gesture');
  if (options.remoteRequested) return fallback('remote-regeneration');
  if (options.representation === 'turntable') return fallback('not-interactive');
  if (licenseRefusal(options)) return fallback('license');
  if (!options.computeAvailable) return fallback('compute');
  if (options.thermal === 'serious' || options.thermal === 'critical') return fallback('thermal');
  if (!acceptedModel(geometry)) return fallback('model');
  const used = samples.filter((sample) => usable(sample, geometry));
  if (used.length === 0) return fallback('unsupported');
  const representation = representationFor(options, BUDGET.cellCount);
  if (!representation) return fallback('budget');

  const sealed = sealedShape(geometry.shape, null);
  const byRegion = new Map<Region, PhotoSample>();
  for (const sample of used) byRegion.set(sample.view, sample);
  const texels: AppearanceTexel[] = [];
  const splats: GaussianSplat[] = [];
  for (const region of REGIONS) {
    const source = byRegion.get(region);
    for (let index = 0; index < CELLS_PER_REGION; index += 1) {
      const slot = REGIONS.indexOf(region) * CELLS_PER_REGION + index;
      const cellId = `${region}-${index}`;
      if (!source) {
        texels.push({ cellId, region, slot, provenance: 'inferred', tone: null, photoId: null });
        continue;
      }
      const tone = source.samples[index] ?? 0;
      texels.push({
        cellId,
        region,
        slot,
        provenance: 'observed',
        tone,
        photoId: source.photoId,
      });
      if (representation === 'gaussian') {
        splats.push({ cellId, slot, tone, opacity: 1, provenance: 'observed' });
      }
    }
  }
  const photoIds = [...new Set(used.map((sample) => sample.photoId))];
  const sourceDigests: Record<string, string> = {};
  for (const sample of used) sourceDigests[sample.photoId] = sample.sourceDigest;
  const captureDates = used.map((sample) => sample.captureDate).sort();
  const captureDate = captureDates[captureDates.length - 1] ?? geometry.captureDate;
  const cacheKey = fingerprint([
    geometry.snapshotId,
    geometry.topologyId,
    geometry.modelVersion,
    geometry.framingId,
    representation,
    ...photoIds.slice().sort(),
  ]);
  const asset: AppearanceAsset = {
    schema: APPEARANCE_SCHEMA,
    id: fingerprint([geometry.accountId, geometry.effectiveDate, cacheKey]),
    cacheKey,
    snapshotId: geometry.snapshotId,
    accountId: geometry.accountId,
    bodyId: geometry.bodyId,
    effectiveDate: geometry.effectiveDate,
    captureDate,
    modelId: geometry.modelId,
    modelVersion: geometry.modelVersion,
    presentationVersion: PRESENTATION_VERSION,
    topologyId: geometry.topologyId,
    rigId: geometry.rigId,
    framingId: geometry.framingId,
    shape: sealed.shape,
    licenseId: LICENSE_ID,
    rights: RIGHTS_HOLDER,
    projectionId: PROJECTION_ID,
    gaussianLayerId: representation === 'gaussian' ? GAUSSIAN_LAYER_ID : null,
    representation,
    texels,
    splats,
    photoIds,
    sourceDigests,
    geometryDrift: shapeDrift(geometry.shape, sealed.shape),
    appearanceDrift: toneDrift(used, texels),
    observedCount: texels.filter((texel) => texel.provenance === 'observed').length,
    inferredCount: texels.filter((texel) => texel.provenance === 'inferred').length,
    interactive: true,
    claimsBodyFat: false,
    claimsWeeklyChange: false,
  };
  return { kind: 'asset', asset, reason: null };
}

function toneDrift(samples: readonly PhotoSample[], texels: readonly AppearanceTexel[]): number {
  const deltas: number[] = [];
  for (const sample of samples) {
    if (sample.view === 'diary') continue;
    for (let index = 0; index < sample.samples.length; index += 1) {
      const texel = texels.find((item) => item.cellId === `${sample.view}-${index}`);
      const tone = sample.samples[index];
      if (!texel || texel.tone == null || tone == null) continue;
      deltas.push(Math.abs(texel.tone - tone));
    }
  }
  if (deltas.length === 0) return 0;
  return deltas.reduce((sum, value) => sum + value, 0) / deltas.length;
}

export function quantifyDrift(
  corpus: readonly AcceptedGeometry[],
  asset: AppearanceAsset,
): { matched: boolean; geometryDrift: number; appearanceDrift: number } {
  const accepted = corpus.find((item) => item.snapshotId === asset.snapshotId);
  if (!accepted) {
    return {
      matched: false,
      geometryDrift: Number.POSITIVE_INFINITY,
      appearanceDrift: asset.appearanceDrift,
    };
  }
  return {
    matched: true,
    geometryDrift: shapeDrift(accepted.shape, asset.shape),
    appearanceDrift: asset.appearanceDrift,
  };
}

export function lookupAppearance(
  date: string,
  cache: readonly AppearanceAsset[],
  topologyId: string,
): AppearanceAsset | null {
  const matches = cache.filter(
    (asset) => asset.effectiveDate === date && asset.topologyId === topologyId,
  );
  return matches[matches.length - 1] ?? null;
}

export function readForGesture(
  cacheKey: string,
  cache: readonly AppearanceAsset[],
  remoteRequested: boolean,
): {
  asset: AppearanceAsset | null;
  regenerated: false;
  reason: 'remote-regeneration' | 'cache-miss' | null;
} {
  if (remoteRequested) return { asset: null, regenerated: false, reason: 'remote-regeneration' };
  const asset = cache.find((item) => item.cacheKey === cacheKey) ?? null;
  return { asset, regenerated: false, reason: asset ? null : 'cache-miss' };
}

export interface AppearanceComparison {
  bodyFatDelta: null;
  weeklyChange: null;
  geometryChangedByAppearance: false;
  observedToneDelta: number | null;
  label: string;
  before: Shape;
  after: Shape;
}

export function progressDisplay(
  before: AppearanceAsset,
  after: AppearanceAsset,
  yaw: number,
): AppearanceComparison {
  const region = visibleRegion(yaw);
  const deltas: number[] = [];
  for (const left of before.texels) {
    if (left.region !== region || left.provenance !== 'observed' || left.tone == null) continue;
    const right = after.texels.find((texel) => texel.cellId === left.cellId);
    if (!right || right.provenance !== 'observed' || right.tone == null) continue;
    deltas.push(right.tone - left.tone);
  }
  const observedToneDelta =
    deltas.length === 0 ? null : deltas.reduce((sum, value) => sum + value, 0) / deltas.length;
  return {
    bodyFatDelta: null,
    weeklyChange: null,
    geometryChangedByAppearance: false,
    observedToneDelta,
    label:
      observedToneDelta == null
        ? 'Viewpoint has no shared observation'
        : 'Appearance only. Not a weekly change.',
    before: copyShape(before.shape),
    after: copyShape(after.shape),
  };
}

export function remember(
  archive: AppearanceArchive,
  sample: PhotoSample,
  geometry: AcceptedGeometry,
  options: ProjectOptions = defaultOptions(),
): AppearanceArchive {
  const samples = mergeSamples(archive.samples, sample);
  const geometries = mergeGeometries(archive.geometries, geometry);
  const dated = samples.filter(
    (item) =>
      item.accountId === geometry.accountId && item.effectiveDate === geometry.effectiveDate,
  );
  const projected = project(geometry, dated, options);
  if (!projected.asset) return { ...archive, samples, geometries };
  const assets = archive.assets.filter(
    (asset) =>
      !(asset.accountId === geometry.accountId && asset.effectiveDate === geometry.effectiveDate),
  );
  assets.push(projected.asset);
  return { ...archive, samples, geometries, assets };
}

export function forgetPhoto(archive: AppearanceArchive, photoId: string): AppearanceArchive {
  const samples = archive.samples.filter((sample) => sample.photoId !== photoId);
  return {
    ...archive,
    samples,
    geometries: archive.geometries.filter((geometry) =>
      samples.some(
        (sample) =>
          sample.accountId === geometry.accountId &&
          sample.effectiveDate === geometry.effectiveDate,
      ),
    ),
    assets: archive.assets.filter((asset) => !assetUsesPhoto(asset, photoId)),
  };
}

export function forgetAccount(archive: AppearanceArchive): AppearanceArchive {
  return emptyArchive(archive.accountId);
}

function assetUsesPhoto(asset: AppearanceAsset, photoId: string): boolean {
  return (
    asset.photoIds.includes(photoId) ||
    asset.texels.some((texel) => texel.photoId === photoId) ||
    Object.prototype.hasOwnProperty.call(asset.sourceDigests, photoId)
  );
}

function mergeSamples(current: readonly PhotoSample[], sample: PhotoSample): PhotoSample[] {
  const next = current.filter(
    (item) =>
      !(
        item.accountId === sample.accountId &&
        item.photoId === sample.photoId &&
        item.view === sample.view
      ),
  );
  next.push(sample);
  return next;
}

function mergeGeometries(
  current: readonly AcceptedGeometry[],
  geometry: AcceptedGeometry,
): AcceptedGeometry[] {
  const next = current.filter(
    (item) =>
      !(
        item.accountId === geometry.accountId &&
        item.effectiveDate === geometry.effectiveDate &&
        item.topologyId === geometry.topologyId
      ),
  );
  next.push(geometry);
  return next;
}

export function promotionDecision(evidence: PromotionEvidence): {
  promoted: boolean;
  reasons: string[];
} {
  const reasons: string[] = [];
  if (evidence.tier !== 'repeatable-on-device' && evidence.tier !== 'calibrated')
    reasons.push('tier');
  if (!(evidence.observedCoverage > evidence.baselineObservedCoverage)) reasons.push('improvement');
  if (evidence.geometryDrift !== 0) reasons.push('geometry-drift');
  if (
    evidence.introducedBodyFatClaim ||
    evidence.introducedWeeklyChange ||
    !evidence.truthfulProgress
  ) {
    reasons.push('false-progress');
  }
  if (!evidence.rightsRecorded) reasons.push('rights');
  if (
    evidence.lowEndDeviceEvidence !== 'physical-device' &&
    evidence.lowEndDeviceEvidence !== 'distributed-build'
  ) {
    reasons.push('device-evidence');
  }
  return { promoted: reasons.length === 0, reasons };
}

export function bodyFatClaim(): null {
  return null;
}

export function weeklyChangeClaim(): null {
  return null;
}
