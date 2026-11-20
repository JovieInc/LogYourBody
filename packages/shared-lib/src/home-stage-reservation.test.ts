import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';
import { homeStageAspectGaps } from './home-stage-reservation';

const read = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8');

const sharedArm = `case .photo, .noPhoto, .loading, .failedLoad, .offline:
            height = safeWidth / HomeV2Tokens.photoAspectRatio`;

const reservedSurface = `size: HomeV2StageReservation.size(
                            width: geometry.size.width,`;

it('accepts the shared Home stage reservation and rejects the old inline height', () => {
  expect(homeStageAspectGaps(reservedSurface, sharedArm)).toEqual([]);
  expect(
    homeStageAspectGaps(
      'size: CGSize(width: geometry.size.width, height: geometry.size.width / HomeV2Tokens.photoAspectRatio),',
      sharedArm,
    ),
  ).toContain('Home surface does not size the card with HomeV2StageReservation.size');
  expect(
    homeStageAspectGaps(reservedSurface, 'case .photo:\n            height = safeWidth'),
  ).toContain(
    'Home stage reservation does not share one 4:5 arm for photo, empty, loading, failed and offline',
  );
  expect(
    homeStageAspectGaps(
      reservedSurface,
      'case .photo, .noPhoto, .loading, .failedLoad, .offline:\n            height = safeWidth',
    ),
  ).toContain('shared Home stage arm omits height = safeWidth / HomeV2Tokens.photoAspectRatio');
});

it('keeps the checked-in Home card on the shared 4:5 reservation', () => {
  const surface = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2Surface.swift');
  const reservation = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2SystemStates.swift');
  expect(homeStageAspectGaps(surface, reservation)).toEqual([]);
});
