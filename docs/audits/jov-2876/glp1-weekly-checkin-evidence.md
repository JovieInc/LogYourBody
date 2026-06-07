# JOV-2876 GLP-1 Weekly Check-In Evidence

Date: 2026-06-07
Simulator: iPhone 17 Pro, iOS Simulator, 368x800 screenshots

## Scope

- Added gated `ios_glp1_weekly_checkin` support for a compact weekly GLP-1 check-in on the photo-first HUD.
- Kept the production default off unless the feature gate is enabled; the UI test launch argument is DEBUG-only fixture behavior.
- Reused the existing GLP-1 dose entry flow in `AddEntrySheet` instead of adding a separate logging path.
- Kept copy focused on dose history alignment with weight and photos. It does not tell users to take, inject, change, or continue medication.
- Avoided auth, billing, privacy, HealthKit, BodySpec, bulk photo import, AI chat, or product configuration changes.

## Screenshots

- `glp1-weekly-checkin-prompt.jpg` - `-lybUITestPhotoTimelineHUDFixture -lybUITestGlp1WeeklyCheckInFixture`; HUD prompt shows Zepbound, `5.0 mg/week`, 9 days since last logged, and `Log dose`.
- `glp1-weekly-checkin-dose-flow.jpg` - same fixture after tapping the prompt; existing `Log GLP-1 dose` sheet opens with the Zepbound medication chip and `Save GLP-1`.

## Runtime Evidence

- Simulator: iPhone 17 Pro, iOS 26.5, `1F5679FD-2B72-40E4-816A-4B58E36C032B`.
- XcodeBuildMCP `build_run_sim` passed with launch args `-lybUITestPhotoTimelineHUDFixture -lybUITestGlp1WeeklyCheckInFixture`.
- Runtime snapshot exposed `photo_timeline_hud_glp1_weekly_checkin` as an accessible button with label text containing `Weekly GLP-1 check-in`, `Zepbound was last logged 9 days ago`, and `Log dose`.
- Tapping `photo_timeline_hud_glp1_weekly_checkin` opened the existing dose entry sheet; focused UI smoke also verified `Log GLP-1 dose`, `Zepbound`, and `Save GLP-1`.

## Validation

Passed:

```bash
swiftlint lint --strict
xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' -only-testing:LogYourBodyTests/Glp1WeeklyCheckInPolicyTests test
xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' -only-testing:LogYourBodyUITests/LogYourBodyUITests/testGlp1WeeklyCheckInFixtureShowsPromptAndOpensDoseFlow test
xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' build-for-testing
pnpm lint
pnpm typecheck
pnpm test
git diff --check
```

Notes:

- `pnpm` commands were run under Node v22.22.1 and emitted the existing repo warning that Node 20.x is requested.
- Cached web lint/build/test logs replayed existing warnings, including Next lint deprecation, stale browser data, `read-excel-file` export warnings during build, and known test console output. No validation command failed.
- Xcode emitted existing Swift 6 readiness and deprecation warnings during simulator builds; no new required failure was introduced.

## Done When

Done when paid users can see a short weekly GLP-1 check-in behind `ios_glp1_weekly_checkin`, the feature remains hidden by default in production, tapping the prompt opens the existing dose entry path without a production bypass, policy tests prove non-medical copy and gate behavior, UI smoke proves the visible prompt-to-sheet path, and simulator screenshots are attached.
