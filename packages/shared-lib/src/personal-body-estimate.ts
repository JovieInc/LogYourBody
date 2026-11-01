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

function finiteUnit(value: number | null): number | null {
  if (value == null || !Number.isFinite(value) || value < 0 || value > 1) return null;
  return value;
}

function contributes(capture: CaptureInput): { width: number | null; depth: number | null } | null {
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

function median(values: number[]): number {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

function blend(prior: number, observed: number): number {
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

function snapshotId(
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

export interface JobReceipt {
  job: Job;
  snapshot: VisualizationSnapshot | null;
  diaries: DiaryEntry[];
  journey: 'estimate' | 'photo';
}

function diariesFor(captures: CaptureInput[], identity: Identity, used: Set<string>): DiaryEntry[] {
  const diaries: DiaryEntry[] = [];
  for (const capture of captures) {
    if (capture.accountId !== identity.accountId || used.has(capture.id)) continue;
    const casual = capture.view === 'diary' || capture.sessionId == null;
    diaries.push({
      accountId: capture.accountId,
      photoId: capture.photoId,
      effectiveDate: capture.effectiveDate,
      reason: casual ? 'casual' : 'unsupported',
    });
  }
  return diaries;
}

function failedJob(
  id: string,
  accountId: string,
  attempts: number,
  failure: string,
  status: Job['status'],
): Job {
  return { id, accountId, status, attempts, snapshotId: null, failure };
}

export function stepJob(existing: Job | null, request: FitRequest): JobReceipt {
  const id = existing?.id ?? jobId(request);
  const accountId = request.identity.accountId;
  if (existing?.status === 'settled') {
    return {
      job: existing,
      snapshot: null,
      diaries: [],
      journey: existing.snapshotId ? 'estimate' : 'photo',
    };
  }
  if (existing?.status === 'canceled') {
    return { job: existing, snapshot: null, diaries: [], journey: 'photo' };
  }
  const attempts = existing?.attempts ?? 0;
  if (
    existing &&
    (existing.status === 'failed' || existing.status === 'timedOut') &&
    attempts >= MAX_ATTEMPTS
  ) {
    return { job: existing, snapshot: null, diaries: [], journey: 'photo' };
  }
  if (request.canceled) {
    return {
      job: failedJob(id, accountId, attempts, 'canceled', 'canceled'),
      snapshot: null,
      diaries: diariesFor(request.captures, request.identity, new Set()),
      journey: 'photo',
    };
  }
  if (request.now > request.deadline) {
    return {
      job: failedJob(id, accountId, attempts + 1, 'timeout', 'timedOut'),
      snapshot: null,
      diaries: [],
      journey: 'photo',
    };
  }
  const boundary = externalProcessing(request);
  if (boundary !== 'not-requested') {
    return {
      job: failedJob(id, accountId, attempts + 1, boundary, 'failed'),
      snapshot: null,
      diaries: diariesFor(request.captures, request.identity, new Set()),
      journey: 'photo',
    };
  }
  const fitted = fitShape(request.captures, request.identity, request.prior);
  const used = new Set(fitted?.captureIds ?? []);
  const diaries = diariesFor(request.captures, request.identity, used);
  if (!fitted) {
    return {
      job: {
        id,
        accountId,
        status: 'settled',
        attempts: attempts + 1,
        snapshotId: null,
        failure: null,
      },
      snapshot: null,
      diaries,
      journey: 'photo',
    };
  }
  const date = request.captures.find((capture) => used.has(capture.id))?.effectiveDate ?? '';
  const sessionId = request.captures.find((capture) => used.has(capture.id))?.sessionId ?? null;
  const snapshot: VisualizationSnapshot = {
    schema: SNAPSHOT_SCHEMA,
    id: snapshotId(request.identity, date, sessionId, fitted.shape, fitted.captureIds),
    accountId,
    bodyId: request.identity.bodyId,
    frame: fitted.shape.frame,
    modelId: MODEL_ID,
    modelVersion: MODEL_VERSION,
    topologyId: request.activeTopology,
    rigId: RIG_ID,
    effectiveDate: date,
    sessionId,
    shape: fitted.shape,
    supported: fitted.supported,
    inferred: fitted.inferred,
    evidence: 'settled',
    photoIds: fitted.photoIds,
    captureIds: fitted.captureIds,
    claimsBodyFat: false,
    claimsWeeklyChange: false,
  };
  return {
    job: {
      id,
      accountId,
      status: 'settled',
      attempts: attempts + 1,
      snapshotId: snapshot.id,
      failure: null,
    },
    snapshot,
    diaries,
    journey: 'estimate',
  };
}

export function applyJob(archive: Archive, existing: Job | null, request: FitRequest): Archive {
  const receipt = stepJob(existing, request);
  const snapshots = receipt.snapshot
    ? [
        ...archive.snapshots.filter((snapshot) => snapshot.id !== receipt.snapshot?.id),
        receipt.snapshot,
      ]
    : archive.snapshots;
  const jobs = [...archive.jobs.filter((job) => job.id !== receipt.job.id), receipt.job];
  const diaries = mergeDiaries(archive.diaries, receipt.diaries);
  const captures = mergeCaptures(archive.captures, request.captures);
  return { ...archive, captures, diaries, snapshots, jobs };
}

function mergeDiaries(current: DiaryEntry[], added: DiaryEntry[]): DiaryEntry[] {
  const next = [...current];
  for (const entry of added) {
    if (
      !next.some(
        (item) =>
          item.accountId === entry.accountId &&
          item.photoId === entry.photoId &&
          item.effectiveDate === entry.effectiveDate,
      )
    ) {
      next.push(entry);
    }
  }
  return next;
}

function mergeCaptures(current: CaptureInput[], added: CaptureInput[]): CaptureInput[] {
  const next = [...current];
  for (const capture of added) {
    const index = next.findIndex(
      (item) => item.id === capture.id && item.accountId === capture.accountId,
    );
    if (index >= 0) next[index] = capture;
    else next.push(capture);
  }
  return next;
}

export function forgetPhoto(archive: Archive, photoId: string): Archive {
  return {
    ...archive,
    captures: archive.captures.filter((capture) => capture.photoId !== photoId),
    diaries: archive.diaries.filter((entry) => entry.photoId !== photoId),
    snapshots: archive.snapshots.filter((snapshot) => !snapshot.photoIds.includes(photoId)),
  };
}

export function forgetAccount(archive: Archive): Archive {
  return emptyArchive(archive.accountId);
}

function utcDay(day: string): number {
  const [year, month, date] = day.split('-').map(Number);
  return Date.UTC(year, (month || 1) - 1, date || 1);
}

function blendShape(start: Shape, end: Shape, t: number): Shape {
  const blendAt = (left: number, right: number) => left + (right - left) * t;
  return {
    adiposity: blendAt(start.adiposity, end.adiposity),
    muscularity: blendAt(start.muscularity, end.muscularity),
    frame: start.frame,
    depth: blendAt(start.depth, end.depth),
  };
}

export function displayFor(
  date: string,
  snapshots: VisualizationSnapshot[],
  activeTopology: string,
): Display {
  const refused: Display = {
    kind: 'fallback',
    shape: null,
    topologyId: null,
    isolated: false,
    label: 'Estimate unavailable for this date',
    claimsBodyFat: false,
    claimsWeeklyChange: false,
  };
  const exact = snapshots.filter((snapshot) => snapshot.effectiveDate === date);
  const matching = exact.filter((snapshot) => snapshot.topologyId === activeTopology);
  const chosen = matching[matching.length - 1];
  if (chosen) {
    return {
      kind: 'settled',
      shape: chosen.shape,
      topologyId: chosen.topologyId,
      isolated: false,
      label: 'Saved date',
      claimsBodyFat: false,
      claimsWeeklyChange: false,
    };
  }
  if (exact.length > 0) {
    return {
      ...refused,
      isolated: true,
      label: 'Saved outline uses another model',
    };
  }
  const settled = snapshots
    .filter((snapshot) => snapshot.topologyId === activeTopology)
    .slice()
    .sort((left, right) => left.effectiveDate.localeCompare(right.effectiveDate));
  const previous = [...settled].reverse().find((snapshot) => snapshot.effectiveDate < date);
  const next = settled.find((snapshot) => snapshot.effectiveDate > date);
  if (!previous || !next || previous.shape.frame !== next.shape.frame) return refused;
  const span = utcDay(next.effectiveDate) - utcDay(previous.effectiveDate);
  const t = span > 0 ? (utcDay(date) - utcDay(previous.effectiveDate)) / span : 0;
  return {
    kind: 'transitional',
    shape: blendShape(previous.shape, next.shape, Math.min(1, Math.max(0, t))),
    topologyId: activeTopology,
    isolated: false,
    label: 'Moving between saved dates',
    claimsBodyFat: false,
    claimsWeeklyChange: false,
  };
}

export function morphAcrossTopology(
  left: string,
  right: string,
): { ok: true } | { ok: false; reason: 'cross-topology' } {
  return left === right ? { ok: true } : { ok: false, reason: 'cross-topology' };
}

export function gestureOwner(dx: number, dy: number): 'timeline' | 'rotate' {
  return Math.abs(dx) > Math.abs(dy) ? 'timeline' : 'rotate';
}

export function applyDrag(yaw: number, dx: number, dy: number): number {
  if (gestureOwner(dx, dy) === 'timeline') return yaw;
  return Math.min(YAW_LIMIT, Math.max(-YAW_LIMIT, yaw + dy * DRAG_GAIN));
}

export function yawFor(action: string): number {
  return action === 'side' ? Math.PI / 2 : 0;
}

export function pairedViewpoints(view: Viewpoint): { before: Viewpoint; after: Viewpoint } {
  return { before: { ...view }, after: { ...view } };
}

export function bodyFatClaim(): null {
  return null;
}

export function weeklyChangeClaim(): null {
  return null;
}
