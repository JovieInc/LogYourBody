# Photographic appearance (LYB-319)

Recorded: 2026-11-02. Parent: LYB-311.

## Selection

The appearance path is on-device photo projection onto the accepted outline from [LYB-317](personal-body-estimate.md). The mesh stays `lyb.wireframe.torso` version `1.0.0`, topology `lyb.wireframe.torso.v1`, rig `lyb.wireframe.torso.rig.v1`, framing `lyb.capture.framing.v1`. The projection id is `lyb.appearance.photo-projection.v1`. A Gaussian layer, `lyb.appearance.gaussian-layer.v1`, stores the same observed samples and does not add a second shape.

DiGS-Avatar is not a dependency. Its published single-image timing is not a native latency or body-composition result. SMPL, SMPL-X, SOMA, and Anny are not bundled. The projection is first-party and recorded as CC0-1.0. [LYB-321](../architecture/body-reconstruction-consent.md) still forbids a reconstruction provider, a new API credential, and an external photo upload.

A generated turntable is not interactive 3D. Rotation, date scrub, and same-viewpoint comparison read a cache built when the photo was labeled. A gesture does not rebuild the texture and does not call a remote model.

## What appearance can change

Appearance copies the accepted adiposity, muscularity, frame, and depth. It does not write a new shape. Geometry drift against the matching snapshot is required to be zero. Appearance drift is the mean absolute difference between stored tones and the samples that produced them.

A supported front, side, or back sample paints only that region. Every other surface stays inferred, with no tone and no splat. The caption names the observed regions and says unseen surfaces stay unmarked. Inferred tones are not written back onto the saved photo, and a comparison of dates does not turn a tone delta into body fat or a weekly change.

An unsupported capture, a thermal or memory limit, a missing license, or a refused model leaves the photo and the existing wireframe or personal outline in place. On a low-end budget the Gaussian layer drops to the smaller projection when that projection fits. Reduced motion uses a zero duration and does not spin the body on its own.

The gate is `photographic_appearance_v1`. It stays off until that gate is on. Photo timeline, generic wireframe, and paid R1 do not wait on it.

## Promotion

The relevant tier for this output is the repeatable on-device protocol. Promotion also needs coverage above the wireframe baseline of zero observed texels, zero geometry drift, no new body-fat or weekly-change claim, recorded commercial rights, and low-end evidence from a physical device or a distributed build. Source and simulator runs do not meet that device checkpoint. This revision does not promote the view.

## Evidence

Source checks are `packages/shared-lib/src/photographic-appearance.test.ts` and `apps/ios/LogYourBodyTests/PhotographicAppearanceTests.swift`. This extends the LYB-64 path by keeping `testEmptyPhotoStageOpensAttachSheetForThatDay`.

Simulator, physical-device, and distributed-build journeys were not run for this revision. LYB-64 device performance and data-integrity evidence was not run. Public fixtures contain ids and unit tones, not personal photos or health values.
