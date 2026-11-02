export * from './personal-body-estimate-model';
import {
  SNAPSHOT_SCHEMA,
  MODEL_ID,
  MODEL_VERSION,
  RIG_ID,
  MAX_ATTEMPTS,
  DRAG_GAIN,
  YAW_LIMIT,
  CaptureInput,
  Identity,
  Shape,
  VisualizationSnapshot,
  DiaryEntry,
  Job,
  Archive,
  FitRequest,
  Display,
  Viewpoint,
  emptyArchive,
  externalProcessing,
  fitShape,
  snapshotId,
  jobId,
} from './personal-body-estimate-model';

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
