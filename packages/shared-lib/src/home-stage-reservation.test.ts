import { readFileSync } from 'node:fs';
import { expect, it } from 'vitest';
import { homePhotoStageFindings } from './home-stage-reservation';

const read = (path: string) => readFileSync(new URL(`../../../${path}`, import.meta.url), 'utf8');

const reservedSurface = `HomeV2StageReservation.size(
                            width: geometry.size.width,
                            presentation: hasPhoto ? .photo : .noPhoto`;
const layout = `static func stageHeight(width: CGFloat, height: CGFloat) -> CGFloat {
  let fourByFive = width / HomeV2Tokens.photoAspectRatio
  return min(fourByFive, available)
}
enum HomeV2EditorialPolicy`;
const sharedArm = `enum HomeV2StageReservation {
    switch presentation {
        case .photo, .noPhoto, .loading, .failedLoad, .offline:
            break
        }
    let height = HomeV2Layout.stageHeight(width: safeWidth, height: safeContent)
}
func homeV2ReservedStage`;

it('requires every Home presentation to use the shared content-height budget', () => {
  expect(homePhotoStageFindings(reservedSurface, sharedArm, layout)).toEqual([]);
  expect(homePhotoStageFindings('height: geometry.size.width', sharedArm, layout)).toContain(
    'HomeV2Surface sizes the timeline outside HomeV2StageReservation',
  );
  const budgetBeforeSwitch = sharedArm
    .replace(
      'switch presentation {',
      'let unused = HomeV2Layout.stageHeight(width: safeWidth, height: safeContent)\n    switch presentation {',
    )
    .replace(
      'let height = HomeV2Layout.stageHeight(width: safeWidth, height: safeContent)',
      'let height = safeWidth',
    );
  expect(homePhotoStageFindings(reservedSurface, budgetBeforeSwitch, layout)).toContain(
    'HomeV2StageReservation drops HomeV2Tokens.photoAspectRatio',
  );
  const bypass = sharedArm.replace(
    '            break',
    '            return CGSize(width: safeWidth, height: safeWidth)',
  );
  expect(homePhotoStageFindings(reservedSurface, bypass, layout)).toContain(
    'HomeV2StageReservation drops HomeV2Tokens.photoAspectRatio',
  );
  const splitCase = sharedArm.replace(
    '            break',
    '            break\n        case .other:\n            break',
  );
  expect(homePhotoStageFindings(reservedSurface, splitCase, layout)).toContain(
    'HomeV2StageReservation drops HomeV2Tokens.photoAspectRatio',
  );
});

it('keeps the checked-in Home card on the shared 4:5 reservation', () => {
  const surface = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2Surface.swift');
  const reservation = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2Tokens.swift');
  const layoutSource = read('apps/ios/LogYourBody/Views/HomeV2/HomeV2Policy.swift');
  expect(homePhotoStageFindings(surface, reservation, layoutSource)).toEqual([]);
});
