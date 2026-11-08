/**
 * Optional front/side capture for a persistent personal outline (LYB-317).
 *
 * The selected engine is the on-device wireframe family. LYB-321 forbids a
 * reconstruction provider and an external photo upload. Photos improve only
 * the quantities this protocol supports. They do not measure body fat.
 */

export const PROTOCOL_ID = 'lyb.capture.front-side.v1';
export const SNAPSHOT_SCHEMA = 'lyb.visualization-snapshot.v1';
export const MODEL_ID = 'lyb.wireframe.torso';
export const MODEL_VERSION = '1.0.0';
export const TOPOLOGY_ID = 'lyb.wireframe.torso.v1';
export const RIG_ID = 'lyb.wireframe.torso.rig.v1';
export const MAX_ATTEMPTS = 3;
export const FIT_BLEND = 0.35;
export const DRAG_GAIN = 0.008;
export const YAW_LIMIT = Math.PI;
export const BENEFIT_COPY =
  'A front and a side from this session can adjust the personal outline for this date. It stays on this phone and does not measure body fat.';

export const ENGINE = {
  protocolId: PROTOCOL_ID,
  modelId: MODEL_ID,
  version: MODEL_VERSION,
  topologyId: TOPOLOGY_ID,
  rigId: RIG_ID,
  route: 'on-device' as const,
  claimsBodyFat: false as const,
  claimsWeeklyChange: false as const,
};

export type ViewKind = 'front' | 'side' | 'back' | 'diary';
export type CaptureQuality = 'supported' | 'poor' | 'occluded' | 'poseChanged' | 'missing';
export type ProcessingRoute = 'on-device' | 'external';

export interface CaptureInput {
  id: string;
  accountId: string;
  photoId: string;
  sessionId: string | null;
  view: ViewKind;
  effectiveDate: string;
  quality: CaptureQuality;
  torsoWidth: number | null;
  torsoDepth: number | null;
  dexaBodyFat: number | null;
  dexaDate: string | null;
}

export interface Identity {
  accountId: string;
  bodyId: string;
  frame: number;
}

export interface Shape {
  adiposity: number;
  muscularity: number;
  frame: number;
  depth: number;
}

export interface VisualizationSnapshot {
  schema: typeof SNAPSHOT_SCHEMA;
  id: string;
  accountId: string;
  bodyId: string;
  frame: number;
  modelId: string;
  modelVersion: string;
  topologyId: string;
  rigId: string;
  effectiveDate: string;
  sessionId: string | null;
  shape: Shape;
  supported: string[];
  inferred: string[];
  evidence: 'settled';
  photoIds: string[];
  captureIds: string[];
  claimsBodyFat: false;
  claimsWeeklyChange: false;
}

export interface DiaryEntry {
  accountId: string;
  photoId: string;
  effectiveDate: string;
  reason: 'casual' | 'unsupported';
}

export interface Job {
  id: string;
  accountId: string;
  status: 'settled' | 'failed' | 'canceled' | 'timedOut';
  attempts: number;
  snapshotId: string | null;
  failure: string | null;
}

export interface Archive {
  accountId: string;
  captures: CaptureInput[];
  diaries: DiaryEntry[];
  snapshots: VisualizationSnapshot[];
  jobs: Job[];
}

export interface FitRequest {
  now: number;
  deadline: number;
  online: boolean;
  route: ProcessingRoute;
  consentGranted: boolean;
  providerAvailable: boolean;
  canceled: boolean;
  identity: Identity;
  captures: CaptureInput[];
  prior: Shape | null;
  activeTopology: string;
}

export type ExternalStatus =
  'not-requested' | 'denied' | 'provider-unavailable' | 'refused-by-policy';

export interface Display {
  kind: 'settled' | 'transitional' | 'fallback';
  shape: Shape | null;
  topologyId: string | null;
  isolated: boolean;
  label: string;
  claimsBodyFat: false;
  claimsWeeklyChange: false;
}

export interface Viewpoint {
  yaw: number;
  scale: number;
}

const DEFAULT_SHAPE: Shape = { adiposity: 0.5, muscularity: 0.5, frame: 0.5, depth: 0.5 };

export function emptyArchive(accountId: string): Archive {
  return { accountId, captures: [], diaries: [], snapshots: [], jobs: [] };
}

export function defaultShape(frame: number): Shape {
  return { ...DEFAULT_SHAPE, frame: clampUnit(frame) };
}

export function clampUnit(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.min(1, Math.max(0, value));
}

export function depthScale(depth: number): number {
  return 0.85 + clampUnit(depth) * 0.3;
}

export function fingerprint(parts: string[]): string {
  let hash = 2166136261;
  const text = parts.join('\u001f');
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

export function sessionKey(capture: CaptureInput): string | null {
  if (!capture.sessionId || capture.view === 'diary') return null;
  return `${capture.accountId}|${capture.sessionId}|${capture.effectiveDate}`;
}

export function classifyPose(
  view: ViewKind,
  shoulderSpan: number | null,
  profileDepth: number | null,
): CaptureQuality {
  if (view === 'back' || view === 'diary') return 'supported';
  if (view === 'front') {
    if (shoulderSpan == null || !Number.isFinite(shoulderSpan)) return 'missing';
    if (shoulderSpan < 0.08) return 'poseChanged';
    return 'supported';
  }
  if (profileDepth == null || !Number.isFinite(profileDepth)) return 'missing';
  if (shoulderSpan != null && shoulderSpan > 0.35) return 'poseChanged';
  return 'supported';
}

export function externalProcessing(
  request: Pick<FitRequest, 'route' | 'consentGranted' | 'providerAvailable' | 'online'>,
): ExternalStatus {
  if (request.route === 'on-device') return 'not-requested';
  if (!request.consentGranted) return 'denied';
  if (!request.online || !request.providerAvailable) return 'provider-unavailable';
  return 'refused-by-policy';
}

export function finiteUnit(value: number | null): number | null {
  if (value == null || !Number.isFinite(value) || value < 0 || value > 1) return null;
  return value;
}

export function contributes(
  capture: CaptureInput,
): { width: number | null; depth: number | null } | null {
  if (sessionKey(capture) == null || capture.quality !== 'supported') return null;
  if (capture.view === 'front') {
    const width = finiteUnit(capture.torsoWidth);
    return width == null ? null : { width, depth: null };
  }
  if (capture.view === 'side') {
    const depth = finiteUnit(capture.torsoDepth);
    return depth == null ? null : { width: null, depth };
  }
  return null;
}

export function median(values: number[]): number {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

export function blend(prior: number, observed: number): number {
  return clampUnit(prior + (observed - prior) * FIT_BLEND);
}

export function groupedCaptures(captures: CaptureInput[], identity: Identity): CaptureInput[] {
  return captures.filter(
    (capture) => capture.accountId === identity.accountId && sessionKey(capture) != null,
  );
}

export function fitShape(
  captures: CaptureInput[],
  identity: Identity,
  prior: Shape | null,
): {
  shape: Shape;
  supported: string[];
  inferred: string[];
  photoIds: string[];
  captureIds: string[];
} | null {
  const primaryKey = captures.map(sessionKey).find((key) => key != null) ?? null;
  const priorShape = prior ?? defaultShape(identity.frame);
  const widths: number[] = [];
  const depths: number[] = [];
  const photoIds: string[] = [];
  const captureIds: string[] = [];
  for (const capture of captures) {
    if (capture.accountId !== identity.accountId || sessionKey(capture) !== primaryKey) continue;
    const observation = contributes(capture);
    if (!observation) continue;
    captureIds.push(capture.id);
    photoIds.push(capture.photoId);
    if (observation.width != null) widths.push(observation.width);
    if (observation.depth != null) depths.push(observation.depth);
  }
  if (widths.length === 0 && depths.length === 0) return null;
  const supported: string[] = [];
  const inferred = ['frame', 'muscularity'];
  const shape: Shape = {
    adiposity: priorShape.adiposity,
    muscularity: priorShape.muscularity,
    frame: clampUnit(identity.frame),
    depth: priorShape.depth,
  };
  if (widths.length > 0) {
    shape.adiposity = blend(priorShape.adiposity, median(widths));
    supported.push('torsoWidth');
  } else {
    inferred.push('torsoWidth');
  }
  if (depths.length > 0) {
    shape.depth = blend(priorShape.depth, median(depths));
    supported.push('torsoDepth');
  } else {
    inferred.push('torsoDepth');
  }
  inferred.push('posterior');
  return { shape, supported, inferred, photoIds, captureIds };
}

export function snapshotId(
  identity: Identity,
  date: string,
  sessionId: string | null,
  shape: Shape,
  captureIds: string[],
): string {
  return fingerprint([
    SNAPSHOT_SCHEMA,
    identity.accountId,
    identity.bodyId,
    date,
    sessionId ?? '',
    MODEL_VERSION,
    TOPOLOGY_ID,
    shape.adiposity.toFixed(5),
    shape.muscularity.toFixed(5),
    shape.frame.toFixed(5),
    shape.depth.toFixed(5),
    [...captureIds].sort().join(','),
  ]);
}

export function jobId(request: FitRequest): string {
  const fitting = fitShape(request.captures, request.identity, request.prior);
  return fingerprint([
    request.identity.accountId,
    request.identity.bodyId,
    request.activeTopology,
    request.route,
    String(request.prior?.adiposity ?? ''),
    String(request.prior?.depth ?? ''),
    (fitting?.captureIds ?? request.captures.map((capture) => capture.id)).sort().join(','),
    request.captures
      .map((capture) =>
        [
          capture.id,
          capture.view,
          capture.quality,
          capture.effectiveDate,
          capture.torsoWidth,
          capture.torsoDepth,
        ].join(':'),
      )
      .sort()
      .join('|'),
  ]);
}
