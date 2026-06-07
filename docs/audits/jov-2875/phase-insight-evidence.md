# JOV-2875 Deterministic Phase Insight Evidence

## Scope

- Added gated `ios_phase_insight` support for a compact deterministic phase insight on the photo-first HUD.
- Kept the default local state off until the feature gate is enabled.
- Classified only from local timeline/body metrics: cutting, maintaining, gaining, or insufficient data.
- Avoided chat, recommendations, server calls, import expansion, or medical/prescriptive copy.

## Screenshots

- `phase-insight-hidden-default.jpg` - `-lybUITestPhotoTimelineHUDFixture`; `ios_phase_insight` remains hidden by default.
- `phase-insight-cutting.jpg` - `-lybUITestPhotoTimelineHUDFixture -lybUITestPhaseInsightFixture`; deterministic cutting insight visible after scrolling the HUD.

## Runtime Evidence

- Simulator: iPhone 17 Pro, iOS 26.5, `1F5679FD-2B72-40E4-816A-4B58E36C032B`.
- Gate-off runtime snapshot contained `photo_timeline_hud` and no `photo_timeline_hud_phase_insight`.
- Gated runtime snapshot contained `photo_timeline_hud_phase_insight` with `Cutting`, `-0.6%/wk`, and `Weight is trending down and body fat is moving lower.`

## Validation

- `swiftlint lint --strict`
- `xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' -only-testing:LogYourBodyTests/PhaseInsightPolicyTests test`
- `xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPhotoHUDFixtureRoutesToIntendedPostMVPDashboard -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPhaseInsightFixtureShowsDeterministicCuttingInsight test`
- `xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' build`
- `xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' build-for-testing`
- `pnpm lint`
- `pnpm typecheck`
- `pnpm test`
- `git diff --check`

## Done When

Done when the photo-first HUD can show a short, deterministic cutting/maintaining/gaining insight behind `ios_phase_insight`, the feature remains hidden by default, focused policy/UI smoke coverage proves both states, and simulator screenshots are attached for the visible user path.
