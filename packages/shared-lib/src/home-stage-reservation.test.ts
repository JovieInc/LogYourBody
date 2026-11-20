import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';
import { homePhotoStageFindings } from './home-stage-reservation';

const read = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8');

const reservedSurface = `HomeV2StageReservation.size(
                            width: geometry.size.width,
                            presentation: hasPhoto ? .photo : .noPhoto`;

const sharedArm = `enum HomeV2StageReservation {
        case .photo, .noPhoto, .loading, .failedLoad, .offline:
            height = safeWidth / HomeV2Tokens.photoAspectRatio
        }
func homeV2ReservedStage`;

it('accepts the shared Home stage reservation and rejects a formula outside that arm', () => {
  expect(homePhotoStageFindings(reservedSurface, sharedArm)).toEqual([]);
  expect(
    homePhotoStageFindings(
      'size: CGSize(width: geometry.size.width, height: geometry.size.width / HomeV2Tokens.photoAspectRatio),',
      sharedArm,
    ),
  ).toContain('HomeV2Surface sizes the timeline outside HomeV2StageReservation');
  expect(
    homePhotoStageFindings(
      reservedSurface,
      'enum HomeV2StageReservation { case .photo: height = safeWidth / HomeV2Tokens.photoAspectRatio } func homeV2ReservedStage',
    ),
  ).toContain('HomeV2StageReservation does not keep a photo on the shared frame');
  const formulaBeforeArm = `enum HomeV2StageReservation {
        height = safeWidth / HomeV2Tokens.photoAspectRatio
        case .photo, .noPhoto, .loading, .failedLoad, .offline:
            height = safeWidth
        }
func homeV2ReservedStage`;
  expect(homePhotoStageFindings(reservedSurface, formulaBeforeArm)).toEqual([
    'HomeV2StageReservation drops HomeV2Tokens.photoAspectRatio',
  ]);
});

it('keeps the checked-in Home card on the shared 4:5 reservation', () => {
  const surface = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2Surface.swift');
  const reservation = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2SystemStates.swift');
  expect(homePhotoStageFindings(surface, reservation)).toEqual([]);
});
