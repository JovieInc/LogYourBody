# Continuous wireframe avatar family (LYB-314)

Recorded: 2026-11-01. Parent: LYB-311.

## Selection

NAVER Anny 0.6.2, released 2026-10-26, was evaluated as the starting mesh family and is not bundled.

- Anny core code is Apache-2.0. The MakeHuman and MPFB2 data Anny uses is CC0-1.0.
- Optional SMPL-X assets are non-commercial and are not included. SMPL and SOMA are not included.
- A PyTorch runtime would block Home. [LYB-321](../architecture/body-reconstruction-consent.md) forbids adding Anny as a reconstruction provider, an API credential, or an external photo upload.
- Anny phenotype sliders are not body-fat percentage or FFMI. This family does not map them.

The shipped asset is an original CC0-1.0 torso: model `lyb.wireframe.torso` version `1.0.0`, topology `lyb.wireframe.torso.v1`, rig `lyb.wireframe.torso.rig.v1`. Male and female share that topology and rig. Adiposity, muscularity, and frame are independent 0...1 illustration controls. A later Anny export would need its own topology id. This family refuses a cross-topology morph.

The asset file records the model version, topology id, parameter ranges, license, and a phone-only memory cache. It does not store photos or measurements.

## Home

The selectable male or female wireframe is the drawing for a Home day without a photo. It uses the existing empty stage and does not change that stage's height. `launch_timeline_add_photo` stays, so the no-photo repair does not wait on this family. Presentation is an explicit device preference. It is not inferred from a profile field or an uploaded image. Missing measurements do not create a body-fat value.

Claims stay inside [body-composition visual claims](body-composition-visual-claims.md). Photo visibility stays inside [home photo visibility](home-photo-visibility.md). Background strength and wireframe appearance stay inside [selfie background and wireframe](selfie-background-wireframe.md).

## Evidence

Source checks are `packages/shared-lib/src/wireframe-avatar-family.test.ts` and `apps/ios/LogYourBodyTests/WireframeAvatarFamilyTests.swift`. This extends the LYB-64 path by keeping `testEmptyPhotoStageOpensAttachSheetForThatDay`. Simulator, physical-device, and distributed-build journeys were not run for this revision. The public fixture is a generic mesh, not a personal photo or a health value.
