# JOV-2873 Progress Photo Attach Evidence

## Scope

- The photo-first HUD now opens a focused progress-photo attach sheet from the missing-photo stage.
- The sheet supports one photo at a time from the system photo picker or camera.
- Existing production upload remains handled by `PhotoUploadManager.uploadProgressPhoto`.
- New photo-only entries still use the `photo` body metric source through `PhotoMetadataService.createOrUpdateMetrics`.
- Existing measurement entries keep their measurement provenance when a photo is attached.
- `ImageCacheService` now supports `file://` URLs so local-only fixture photos can render in simulator evidence.

## States

- Empty: `progress-photo-empty.jpg`
- Ready after selecting a single image: `progress-photo-ready.jpg`
- Permission denied: `progress-photo-permission-denied.jpg`
- Success after attach: `progress-photo-success.jpg`
- HUD display after dismissing success: `progress-photo-hud-display.jpg`

## Simulator Evidence

- Simulator: iPhone 17 Pro
- Launch arguments:
  - `-lybUITestPhotoTimelineHUDFixture`
  - `-lybUITestProgressPhotoAttachFixture`
- The fixture flag is DEBUG-only. It generates a local image and updates local Core Data so simulator screenshots can prove ready, success, and display states without requiring a production Clerk storage token.
- Production upload, processing, storage, and sync behavior still use the existing `PhotoUploadManager` path when the DEBUG fixture flag is absent.
- Camera capture is device-only for real camera proof; simulator validation uses the fixture and library-picker entry points.

## Validation

- `swiftlint lint --strict`
- Focused simulator tests: `LogYourBodyTests/ProgressPhotoAttachPolicyTests`, 3 passed, 0 failed.
- `xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing`
- `build_run_sim` with the HUD and progress-photo fixture launch arguments.
- `pnpm lint`
- `pnpm typecheck`
- `pnpm test`

The root `pnpm` commands passed with the existing local Node 22 versus repo Node 20 engine warning. `pnpm test` also replayed cached web build/test logs that include existing web warnings, but exited successfully.

## Done When Check

A user can add one progress photo from the HUD, see empty/permission/ready/processing/failure/success copy, and return to a HUD timeline stage that represents the newly attached photo.
