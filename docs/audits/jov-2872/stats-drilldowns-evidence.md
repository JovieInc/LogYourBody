# JOV-2872 Stats Drilldowns Evidence

## Route and Scope

- The photo HUD now exposes a single `Stats` secondary action below the first-viewport metric strip.
- The secondary destination keeps the HUD photo-first while reusing `DashboardMetricsSection` cards and the existing `FullMetricChartView` drilldowns.
- The destination includes a `Timeline states` summary for measured, interpolated, last-known, and missing timeline values.
- Full chart data now carries `MetricPresence` while keeping the legacy `isEstimated` initializer behavior.

## Simulator Evidence

- Launch arguments: `-lybUITestPhotoTimelineHUDFixture`
- Simulator: iPhone 17 Pro, iOS 26.5
- HUD entry screenshot: `docs/audits/jov-2872/hud-stats-entry.jpg`
- Stats destination screenshot: `docs/audits/jov-2872/stats-destination.jpg`
- Body Fat chart screenshot: `docs/audits/jov-2872/body-fat-chart-presence-legend.jpg`

Covered states:

- Populated metric: Weight and Body Fat cards on the stats destination.
- Missing metric: Steps shows missing data in the HUD and stats summary.
- Interpolated metric: Body Fat chart legend shows `Interpolated 1`; the accessibility label uses singular `point`.
- Navigation: HUD to Stats to Body Fat chart using accessibility element refs.
- Accessibility: HUD metric tiles, the Stats row, presence summary chips, and chart presence legend expose combined labels for VoiceOver scanning.

## Validation

- `swiftlint lint --strict`
- `xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing`
- `build_run_sim` with `-lybUITestPhotoTimelineHUDFixture`; wrapper timed out after launch, but log contains `** BUILD SUCCEEDED **` and the app was running.
- Focused simulator tests: `LogYourBodyTests/MetricChartDataPointPresenceTests`, 2 passed, 0 failed.
- Broader `test_sim` wrapper reached `** TEST BUILD SUCCEEDED **` but hung in `test-without-building` with repeated debugger launch-parameter errors; stopped the single hung xcodebuild process and ran the focused tests above.

## Done When Check

Users can open stats from the photo HUD, scan metric/source state quality, and drill into existing full-screen charts without making stats the primary landing screen.
