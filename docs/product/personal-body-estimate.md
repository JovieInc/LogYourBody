# Optional personal outline (LYB-317)

Recorded: 2026-11-01. Parent: LYB-311.

## Selection

The selected engine is the on-device wireframe family from [LYB-314](wireframe-avatar-family.md): model `lyb.wireframe.torso` version `1.0.0`, topology `lyb.wireframe.torso.v1`, rig `lyb.wireframe.torso.rig.v1`. The capture protocol is `lyb.capture.front-side.v1`. Snapshots use `lyb.visualization-snapshot.v1`.

[LYB-321](../architecture/body-reconstruction-consent.md) forbids a reconstruction provider, a new API credential, and an external photo upload. A request for external processing stops at the existing privacy-policy consent screen and is refused. The photo timeline stays usable.

## What a capture can change

After the ordinary selfie is saved, the customer can optionally label a front, side, or back from that session. The benefit shown there is that a front and a side can adjust the personal outline for that date, on this phone, without measuring body fat.

A clear front can nudge adiposity. A clear side can nudge depth. Frame stays the saved identity. Muscularity and the back of the body stay inferred. A casual selfie without a supported view remains a diary entry. A poor, missing, occluded, or changed-pose view does not move the outline. An old DEXA result is not a current observation. Body-fat and weekly-change numbers stay with the separate calibration evidence in [LYB-322](body-composition-visual-claims.md).

Captures share a fit only when they have the same account, session, and effective date. The fit runs asynchronously, retries at most three times, and can be canceled. Timeout and provider refusal write no new outline. The last usable view and the selected date remain.

## Home

Photo and Estimated 3D share the existing 4:5 stage and the one timeline selection. The stage starts on Photo. Estimated 3D appears when a saved or in-between outline exists for the selected date. Dragging the body vertically rotates it. A horizontal drag stays with the timeline. Front, side, and reset keep the same scale. The viewpoint is not reset when the date changes.

An in-between date blends the saved parameters and is labeled as moving between saved dates. A saved outline from another model is kept and is not vertex-interpolated into the current topology. The stage then shows the photo or the generic wireframe. Scrubbing looks up a display that was already built. It does not fit a model.

Outlines are stored on the phone, scoped to the account, and deleted with the source photo and with account deletion. They are not deleted on an ordinary sign-out.

## Evidence

Source checks are `packages/shared-lib/src/personal-body-estimate.test.ts` and `apps/ios/LogYourBodyTests/PersonalBodyEstimateTests.swift`. This extends the LYB-64 path by keeping `testEmptyPhotoStageOpensAttachSheetForThatDay`. The supported tier is the repeatable on-device protocol covered by those source tests.

Simulator, physical-device, and distributed-build journeys were not run for this revision. LYB-64 device performance and data-integrity evidence was not run. Unvalidated conditions stay on the photo or the generic wireframe. Public fixtures contain ids and unit quantities, not personal photos or health values.
