# Optional personal 3D engines (LYB-316)

Recorded: 2026-11-01. Parent: LYB-311.

## Selection

The selected path is `lyb.personal.parametric.wireframe.v1`: an on-device fit of the existing `lyb.wireframe.torso.v1` torso. It stays optional. Production uses the fallback `lyb.wireframe.torso`, with personalization off and the release stage `disabled`. The weekly photo loop does not gain a capture step.

Bodygram is rejected for this slice. Its public Platform docs return a base64 OBJ and, when two photos are sent, a separate body-fat field. They do not document stable cross-scan vertices or a direct DEXA control. No credential, purchase, or upload was used, so its latency and price were not measured.

DiGS-Avatar is rejected for this slice. The repository license is MIT. The published path also needs SMPL-X, DINOv3, SANA, IDOL, and a student checkpoint that the repository does not grant. Those terms were not cleared, so the pipeline was not run. The README's 0.71 second figure is not an app benchmark. An unsuccessful run is a rejection, not a proof that no Gaussian avatar can exist.

NAVER Anny remains the external parametric model recorded by the wireframe family. It is not executed here.

## Measurement

`compare()` in `packages/shared-lib/src/personal-3d-engine.ts` fits a synthetic illustration target on this host's CPU: adiposity 0.62, muscularity 0.18, frame 0.71, male torso, grid step 0.1 (1331 candidates). The target is not a photo and not a health value. Timings are split into preprocessing, grid inference, mesh assembly, byte transfer, and orthographic wire projection. The warm pass reuses the grid. Those durations are host-CPU source measurements. They are not phone, simulator, or vendor benchmarks.

A full front silhouette selects adiposity 0.6, muscularity 0.2, and frame 0.7. The parameter L1 is 0.05 and the mean absolute vertex error is 0.000414. The contemporaneous side silhouette selects the same point. Repeating that mesh on the same day changes no vertex.

A single-ring crop is a different question. Adding that ring's side width lowered vertex error on rings 1, 2, 5, 8, and 9, left rings 3, 4, and 7 unchanged, and raised it on rings 0 and 6. Ring 0's front crop has four tied grid points and a worst vertex error of 0.006425. Its side width leaves one point and cuts that worst case to 0.003535, while the selected point gets worse. An extra contemporaneous view can help, do nothing, or hurt. Captures from two body-state ids are refused rather than merged.

The fit reads no photo bytes. Clothing is unsupported. The pose is the neutral torso, not an A-pose. Hidden surface is extrapolation from the three illustration parameters, not completion of an occluded photograph. The sliders do not map to body fat, FFMI, or DEXA. Vertices stay on `lyb.wireframe.torso.v1`.

## Capture protocol

The weekly photo stays on the existing attach sheet. There is no new pose gate, required side photo, or vendor upload. `launch_timeline_add_photo` still opens that sheet.

## Out of scope

Omni Flash's model card documents video and audio output. It is not a verified mesh API.

Google's public GNM repository begins with GNM Head. It is not a public body model.

Mojulo's README describes a recipe compiler. That matches compiler wording. It is not personal body reconstruction. The exact remembered demo was not re-run.

MeshLib's published table includes about 0.08 seconds against about 13 seconds. That comparison is an existing-mesh boolean, not body reconstruction, and it was not re-run.

## Evidence

Source checks are `packages/shared-lib/src/personal-3d-engine.test.ts` and `apps/ios/LogYourBodyTests/PersonalBodyEngineTests.swift`. This extends the LYB-64 path by keeping `testEmptyPhotoStageOpensAttachSheetForThatDay`. Simulator, physical-device, and distributed-build journeys were not run. The public fixture is a generic decision record, not a personal photo or a health value.

`PersonalBodyEngine.appliedIllustration` is what the wireframe stage calls, with `photoByteCount: 0`. While `personalizedProduction` is false and the release stage stays disabled, the stage keeps the stored illustration sliders.
