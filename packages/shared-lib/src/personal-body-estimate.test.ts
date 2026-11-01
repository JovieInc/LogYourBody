import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';
import {
  BENEFIT_COPY,
  ENGINE,
  MODEL_ID,
  PROTOCOL_ID,
  TOPOLOGY_ID,
  applyDrag,
  applyJob,
  bodyFatClaim,
  classifyPose,
  depthScale,
  displayFor,
  emptyArchive,
  externalProcessing,
  fitShape,
  forgetAccount,
  forgetPhoto,
  gestureOwner,
  morphAcrossTopology,
  pairedViewpoints,
  stepJob,
  weeklyChangeClaim,
  yawFor,
  type CaptureInput,
  type FitRequest,
  type Identity,
  type Shape,
} from './personal-body-estimate';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const read = (path: string) => readFileSync(`${root}/${path}`, 'utf8');

const identity: Identity = { accountId: 'account-a', bodyId: 'account-a.body', frame: 0.42 };
const prior: Shape = { adiposity: 0.5, muscularity: 0.25, frame: 0.1, depth: 0.5 };

function capture(overrides: Partial<CaptureInput> = {}): CaptureInput {
  return {
    id: 'capture-front',
    accountId: identity.accountId,
    photoId: 'photo-front',
    sessionId: 'session-1',
    view: 'front',
    effectiveDate: '2026-11-01',
    quality: 'supported',
    torsoWidth: 0.8,
    torsoDepth: null,
    dexaBodyFat: 18,
    dexaDate: '2024-01-01',
    ...overrides,
  };
}

function request(overrides: Partial<FitRequest> = {}): FitRequest {
  return {
    now: 1_000,
    deadline: 5_000,
    online: true,
    route: 'on-device',
    consentGranted: false,
    providerAvailable: false,
    canceled: false,
    identity,
    captures: [capture()],
    prior,
    activeTopology: TOPOLOGY_ID,
    ...overrides,
  };
}

it('uses the on-device wireframe protocol and explains the optional benefit', () => {
  expect(ENGINE).toMatchObject({
    protocolId: PROTOCOL_ID,
    modelId: MODEL_ID,
    route: 'on-device',
    claimsBodyFat: false,
    claimsWeeklyChange: false,
  });
  expect(BENEFIT_COPY).toContain('does not measure body fat');
  expect(bodyFatClaim()).toBeNull();
  expect(weeklyChangeClaim()).toBeNull();
});

it('fits one, two, and many views without treating a diary selfie or an old DEXA as shape', () => {
  const front = fitShape([capture()], identity, prior);
  expect(front?.supported).toEqual(['torsoWidth']);
  expect(front?.inferred).toContain('torsoDepth');
  expect(front?.shape.frame).toBe(0.42);
  expect(front?.shape.muscularity).toBe(0.25);
  expect(front?.shape.adiposity).toBeCloseTo(0.5 + (0.8 - 0.5) * 0.35);

  const pair = fitShape(
    [
      capture(),
      capture({
        id: 'side',
        photoId: 'photo-side',
        view: 'side',
        torsoWidth: null,
        torsoDepth: 0.2,
      }),
    ],
    identity,
    prior,
  );
  expect(pair?.supported).toEqual(['torsoWidth', 'torsoDepth']);
  expect(pair?.shape.depth).toBeCloseTo(0.5 + (0.2 - 0.5) * 0.35);

  const many = fitShape(
    [
      capture({ id: 'f1', torsoWidth: 0.2 }),
      capture({ id: 'f2', torsoWidth: 0.4 }),
      capture({ id: 'f3', torsoWidth: 0.9 }),
      capture({ id: 'back', photoId: 'photo-back', view: 'back', torsoWidth: null }),
    ],
    identity,
    prior,
  );
  expect(many?.shape.adiposity).toBeCloseTo(0.5 + (0.4 - 0.5) * 0.35);
  expect(many?.captureIds).not.toContain('back');

  const withDexa = fitShape(
    [capture({ dexaBodyFat: 40, dexaDate: '2026-11-01' })],
    identity,
    prior,
  );
  expect(withDexa?.shape).toEqual(front?.shape);
  expect(JSON.stringify(withDexa)).not.toContain('40');

  const diary = fitShape(
    [capture({ id: 'selfie', view: 'diary', sessionId: null, torsoWidth: 0.99 })],
    identity,
    prior,
  );
  expect(diary).toBeNull();
});

it('keeps poor, missing, occluded, and changed-pose views out of the fit', () => {
  const side = {
    id: 'side',
    photoId: 'photo-side',
    view: 'side' as const,
    torsoWidth: null,
    torsoDepth: 0.1,
  };
  for (const quality of ['poor', 'occluded', 'poseChanged', 'missing'] as const) {
    const fitted = fitShape([capture(), capture({ ...side, quality })], identity, prior);
    expect(fitted?.supported).toEqual(['torsoWidth']);
    expect(fitted?.shape.depth).toBe(prior.depth);
  }
  expect(classifyPose('front', 0.04, null)).toBe('poseChanged');
  expect(classifyPose('front', null, null)).toBe('missing');
  expect(classifyPose('side', 0.5, 0.2)).toBe('poseChanged');
  expect(classifyPose('side', 0.1, 0.2)).toBe('supported');
});

it('refuses external processing and leaves the photo journey in place', () => {
  expect(externalProcessing(request())).toBe('not-requested');
  const denied = stepJob(
    null,
    request({ route: 'external', consentGranted: false, providerAvailable: true }),
  );
  expect(denied.job.failure).toBe('denied');
  expect(denied.snapshot).toBeNull();
  expect(denied.journey).toBe('photo');

  const offline = stepJob(
    null,
    request({ route: 'external', consentGranted: true, online: false }),
  );
  expect(offline.job.failure).toBe('provider-unavailable');
  expect(offline.snapshot).toBeNull();

  const refused = stepJob(
    null,
    request({ route: 'external', consentGranted: true, providerAvailable: true, online: true }),
  );
  expect(refused.job.failure).toBe('refused-by-policy');
  expect(refused.snapshot).toBeNull();
  expect(JSON.stringify(refused)).not.toContain('http');
});

it('retries a fit within a bound and keeps cancel and timeout idempotent', () => {
  const first = stepJob(null, request());
  expect(first.job.status).toBe('settled');
  const again = stepJob(first.job, request());
  expect(again.job).toEqual(first.job);
  expect(again.snapshot).toBeNull();

  const timeout = request({ now: 9, deadline: 1 });
  let timed = stepJob(null, timeout);
  expect(timed.job.status).toBe('timedOut');
  expect(timed.snapshot).toBeNull();
  timed = stepJob(timed.job, timeout);
  timed = stepJob(timed.job, timeout);
  expect(timed.job.attempts).toBe(3);
  expect(stepJob(timed.job, timeout).job).toEqual(timed.job);

  const canceled = stepJob(null, request({ canceled: true }));
  expect(canceled.job.status).toBe('canceled');
  expect(stepJob(canceled.job, request({ canceled: true })).job).toEqual(canceled.job);
  expect(canceled.snapshot).toBeNull();
});

it('preserves the last snapshot across failure and drops it on deletion or account switch', () => {
  let archive = applyJob(emptyArchive(identity.accountId), null, request());
  const saved = archive.snapshots[0];
  archive = applyJob(
    archive,
    null,
    request({ route: 'external', consentGranted: false, providerAvailable: true }),
  );
  expect(archive.snapshots).toEqual([saved]);

  archive = forgetPhoto(archive, 'photo-front');
  expect(archive.snapshots).toEqual([]);

  const other = applyJob(
    emptyArchive('account-b'),
    null,
    request({
      identity: { ...identity, accountId: 'account-b', bodyId: 'account-b.body' },
      captures: [capture({ accountId: 'account-b' })],
    }),
  );
  expect(forgetAccount(other).snapshots).toEqual([]);
  expect(other.snapshots).toHaveLength(1);
  expect(archive.accountId).not.toBe(other.accountId);
});

it('isolates a model update and marks interpolated dates as transitional', () => {
  const archive = applyJob(emptyArchive(identity.accountId), null, request());
  const later = applyJob(
    archive,
    null,
    request({
      captures: [
        capture({
          id: 'later',
          photoId: 'photo-later',
          effectiveDate: '2026-11-05',
          torsoWidth: 0.2,
        }),
      ],
    }),
  );
  const settled = displayFor('2026-11-01', later.snapshots, TOPOLOGY_ID);
  expect(settled.kind).toBe('settled');
  expect(settled.label).toBe('Saved date');
  const between = displayFor('2026-11-03', later.snapshots, TOPOLOGY_ID);
  expect(between.kind).toBe('transitional');
  expect(between.label).toBe('Moving between saved dates');
  expect(between.claimsBodyFat).toBe(false);

  const updated = later.snapshots.map((snapshot, index) =>
    index === 0 ? { ...snapshot, topologyId: 'lyb.wireframe.torso.v2' } : snapshot,
  );
  const isolated = displayFor('2026-11-01', updated, TOPOLOGY_ID);
  expect(isolated.isolated).toBe(true);
  expect(isolated.shape).toBeNull();
  expect(morphAcrossTopology(TOPOLOGY_ID, 'lyb.wireframe.torso.v2')).toEqual({
    ok: false,
    reason: 'cross-topology',
  });
  expect(updated[0]).toBeDefined();
});

it('scrubs and rotates without starting a fit, and keeps one viewpoint for both dates', () => {
  const archive = applyJob(emptyArchive(identity.accountId), null, request());
  const jobs = archive.jobs;
  for (let day = 1; day <= 20; day += 1) {
    displayFor(`2026-11-${String(day).padStart(2, '0')}`, archive.snapshots, TOPOLOGY_ID);
    applyDrag(0.2, day, 1);
  }
  expect(archive.jobs).toBe(jobs);
  expect(gestureOwner(40, 3)).toBe('timeline');
  expect(gestureOwner(1, 30)).toBe('rotate');
  expect(applyDrag(0.2, 40, 3)).toBe(0.2);
  expect(applyDrag(0, 1, 30)).toBeCloseTo(0.24);
  expect(yawFor('front')).toBe(0);
  expect(yawFor('reset')).toBe(0);
  expect(yawFor('side')).toBeCloseTo(Math.PI / 2);
  expect(depthScale(0)).toBeCloseTo(0.85);
  expect(depthScale(1)).toBeCloseTo(1.15);
  const pair = pairedViewpoints({ yaw: 0.4, scale: 1 });
  expect(pair.before).toEqual(pair.after);
});

it('keeps the estimate inside the photo stage and off the scrubber hot path', () => {
  const surface = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2Surface.swift');
  const hero = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2TimelineHero.swift');
  const sheet = read('apps/ios/LogYourBody/Views/ProgressPhotoAttachSheet.swift');
  const offer = read('apps/ios/LogYourBody/Views/ProgressPhotoAttachSheet+PersonalBody.swift');
  const stage = read('apps/ios/LogYourBody/Components/PersonalBodyStage.swift');
  const domain = read('apps/ios/LogYourBody/Components/PersonalBodyEstimate.swift');
  const emptyStage = read('apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift');
  expect(surface).toContain('PersonalBodyEstimateStore');
  expect(surface).toContain('photoAspectRatio');
  expect(hero).not.toContain('stepJob');
  expect(hero).not.toContain('PersonalBodyJobs');
  expect(domain).toContain('adjust the personal outline for this date');
  expect(domain).toContain('does not measure body fat');
  expect(sheet).toContain('personalBodyOffer');
  expect(offer).toContain('benefitCopy');
  expect(stage).toContain('personal_body_stage');
  expect(stage).toContain('Not a body-fat measurement');
  expect(stage).not.toContain('ProgressView');
  expect(domain).toContain('refused-by-policy');
  expect(domain).toContain('cross-topology');
  expect(emptyStage).toContain('func testEmptyPhotoStageOpensAttachSheetForThatDay');
  expect(domain).not.toContain('anny');
  expect(stage).not.toContain('bodyFatPercentage');
});
