import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { expect, it } from 'vitest';
import {
  applyDrag,
  assess,
  buildAsset,
  cacheKey,
  idleSpin,
  interpolate,
  morph,
  presentationChoiceFromUser,
  TOPOLOGY_ID,
  yawFor,
} from './wireframe-avatar-family';

const root = fileURLToPath(new URL('../../..', import.meta.url));
const assetPath = `${root}/apps/ios/LogYourBody/Resources/WireframeAvatarFamily.json`;
const stagePath = `${root}/apps/ios/LogYourBody/Components/WireframeAvatarStage.swift`;
const familyPath = `${root}/apps/ios/LogYourBody/Components/WireframeAvatarFamily.swift`;
const heroPath = `${root}/apps/ios/LogYourBody/Views/HomeV2/HomeV2Surface.swift`;
const timelinePath = `${root}/apps/ios/LogYourBody/Views/DashboardViewLiquid+Components.swift`;
const emptyStageTestPath = `${root}/apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift`;

it('ships one continuous torso family with stable topology and no measurement claim', () => {
  const asset = buildAsset();
  expect(assess(asset)).toEqual([]);
  expect(JSON.parse(readFileSync(assetPath, 'utf8'))).toEqual(asset);
  expect(asset.topologyId).toBe(TOPOLOGY_ID);
  expect(asset.license.annyBundled).toBe(false);
  expect(asset.license.smplxIncluded).toBe(false);
  expect(asset.license.smplIncluded).toBe(false);
  expect(asset.license.somaIncluded).toBe(false);
  expect(asset.mapsToBodyFat).toBe(false);
  expect(asset.mapsToFfmi).toBe(false);
  expect(asset.material.idleSpin).toBe(false);
  expect(idleSpin).toBe(false);
  expect(asset.caching).toMatchObject({
    tier: 'phone',
    disk: false,
    network: false,
    photoBytes: false,
  });
  expect(asset.families.male.rest).toHaveLength(asset.vertexCount);
  expect(asset.rig.weights).toHaveLength(asset.vertexCount);
  for (const weights of asset.rig.weights) {
    const total = weights.reduce((sum, value) => sum + value, 0);
    expect(total).toBeCloseTo(1, 5);
  }
});

it('refuses a cross-topology morph and ignores profile sex and images', () => {
  const asset = buildAsset();
  const male = {
    topologyId: asset.topologyId,
    rigId: asset.rigId,
    vertices: interpolate(asset, 'male', { adiposity: 0, muscularity: 0, frame: 0 }),
  };
  const female = {
    topologyId: asset.topologyId,
    rigId: asset.rigId,
    vertices: interpolate(asset, 'female', { adiposity: 1, muscularity: 1, frame: 1 }),
  };
  const blended = morph(male, female, 0.5);
  expect(blended.ok).toBe(true);
  expect(morph(male, { ...female, topologyId: 'smplx' }, 0.5)).toEqual({
    ok: false,
    reason: 'cross-topology',
  });
  expect(morph(male, { ...female, vertices: female.vertices.slice(0, -1) }, 0.5).ok).toBe(false);
  expect(
    presentationChoiceFromUser({ stored: null, profileSex: 'female', imageHint: 'female' }),
  ).toBe('male');
  expect(
    presentationChoiceFromUser({ stored: 'female', profileSex: 'male', imageHint: 'male' }),
  ).toBe('female');
  expect(cacheKey('male', { adiposity: 0.52, muscularity: -2, frame: 4 })).toBe(
    'male:0.50:0.00:1.00',
  );
});

it('rotates only from an explicit drag or front, side, and reset', () => {
  expect(yawFor('front')).toBe(0);
  expect(yawFor('reset')).toBe(0);
  expect(yawFor('side')).toBeCloseTo(Math.PI / 2);
  expect(applyDrag(0.2, 40, 3)).toBe(0.2);
  expect(applyDrag(0, 1, 30)).toBeCloseTo(0.24);
  expect(applyDrag(3, 0, 100)).toBeCloseTo(Math.PI);
});

it('keeps the wireframe on the existing Home stage without removing the empty-stage repair', () => {
  const stage = readFileSync(stagePath, 'utf8');
  const family = readFileSync(familyPath, 'utf8');
  const hero = readFileSync(heroPath, 'utf8');
  const timeline = readFileSync(timelinePath, 'utf8');
  const emptyStage = readFileSync(emptyStageTestPath, 'utf8');
  expect(stage).toContain('static let dragGain = 0.008');
  expect(stage).toContain('static let idleSpin = false');
  expect(stage).toContain('accessibilityReduceMotion');
  expect(stage).toContain('home_wireframe_avatar');
  expect(stage).toContain('home_wireframe_reset');
  expect(stage).toContain('home_wireframe_front');
  expect(stage).toContain('home_wireframe_side');
  expect(stage).not.toContain('TimelineView');
  expect(stage).not.toContain('repeatForever');
  expect(stage).not.toContain('bodyFatPercentage');
  expect(stage).not.toContain('AvatarBodyFatCatalog');
  expect(family).toContain('crossTopology');
  expect(hero).toContain('WireframeAvatarStage');
  expect(hero).toContain('home_v2_day_zero');
  expect(timeline).toContain('WireframeAvatarStage');
  expect(timeline).toContain('launch_timeline_add_photo');
  expect(emptyStage).toContain('func testEmptyPhotoStageOpensAttachSheetForThatDay');
});
