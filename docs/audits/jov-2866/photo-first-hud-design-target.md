# JOV-2866 Photo-First HUD Design Target

Issue: JOV-2866, "Lock the photo-first HUD design target from the current full app"

Date: 2026-06-07

## Evidence Captured

Captured with XcodeBuildMCP on the configured iPhone 17 Pro simulator, scheme `LogYourBody`, Debug build.

| Artifact                                                                       | Launch arguments                  | What it proves                                                                                               |
| ------------------------------------------------------------------------------ | --------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| [mvp-paid-weight-log.jpg](./mvp-paid-weight-log.jpg)                           | `-lybUITestPaidMVPFixture`        | Current MVP first screen is a paid manual weight logger with settings/account escape controls and sync copy. |
| [full-dashboard-home.jpg](./full-dashboard-home.jpg)                           | `-lybUITestFullDashboardFixture`  | Current full dashboard Home is metrics-first: body score, FFMI, body fat, weight, steps, and actions.        |
| [full-dashboard-photos-empty.jpg](./full-dashboard-photos-empty.jpg)           | `-lybUITestFullDashboardFixture`  | Existing Photos tab has the right spatial source material, but no explicit no-photo state in this fixture.   |
| [full-dashboard-metrics.jpg](./full-dashboard-metrics.jpg)                     | `-lybUITestFullDashboardFixture`  | Existing stats/cards are good secondary-destination material, not the HUD first screen.                      |
| [photo-first-hud-annotated-target.jpg](./photo-first-hud-annotated-target.jpg) | Annotated from the Photos capture | Locked first-viewport hierarchy for the future `ios_photo_timeline_hud` implementation.                      |

## Current Runtime Read

- MVP launch lane stays on `PaidWeightLoggerMVPView`: email OTP, paywall, settings/logout escape, manual weight logging, and sync copy.
- Full dashboard route is still controlled by `ios_full_body_composition_dashboard`; it is useful source material but should remain legacy/beta until HUD proof.
- The full dashboard Home screen is too metrics-card-heavy for the next product promise. It answers "what are my numbers?" before "how am I doing?"
- The Photos tab already has the right canvas and scrubber direction, but the no-photo/empty state is too blank to become the first screen unchanged.
- The Metrics tab should survive as the Apple Health-style secondary destination for charts, reorderable cards, and drilldowns.

## Locked First Viewport

Target route: `ios_photo_timeline_hud`, default off.

1. Compact signed-in header: profile/account affordance, sync indicator, and one add action. Avoid a large dashboard title.
2. Primary progress-photo viewport: a 4:5 or vertical Instagram-style image area occupying the first visual decision point. Users swipe left/right through progress photos over time.
3. Timeline scrubber: immediately below the photo, anchored to entries and photo markers. It changes the selected date/photo and updates metric values.
4. Metric strip: three compact values below the scrubber: FFMI, body fat %, weight. Show interpolation/source state inline, not as buried chart copy.
5. Secondary stats entry: charts/cards move behind a Stats/Drilldown destination. Do not recreate the full-dashboard bottom-tab card sprawl on the first screen.

The first screen should answer "How am I doing?" from the selected photo plus the three metric facts. Body score, steps, GLP-1, DEXA details, and long charts can exist later, but they are not first-viewport content.

## State Matrix

| State                | First-viewport behavior                                                                                         | Data rule                                                             | Evidence required before build acceptance                              |
| -------------------- | --------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| No photo             | Keep the photo viewport visible with an add/attach affordance and clear empty copy. Do not collapse into cards. | Weight/body-fat metrics can still populate the strip.                 | Screenshot with empty photo plane, add affordance, and metric strip.   |
| No body fat          | Body fat shows `--` with a concise missing-source cue; FFMI shows unavailable if body fat is required.          | Do not estimate body fat silently.                                    | Screenshot where weight is present and BF/FFMI missing state is clear. |
| Interpolated metrics | Show an interpolation icon or chip next to affected values. Detail view explains source dates.                  | Interpolated values must be distinguishable from direct measurements. | Screenshot of at least one interpolated FFMI/body-fat value.           |
| HealthKit denied     | Manual logging and photo timeline stay usable; show a small source/status cue.                                  | Authorization absence must not block local-first logging.             | Screenshot or UI test proving manual flow remains available.           |
| Offline              | Show last-known local state and queued sync copy; no blocking modal.                                            | Local Core Data remains source of truth until sync resumes.           | Screenshot with offline or queued sync indicator.                      |
| Pending sync         | Keep selected photo/metric data visible; show subtle pending state.                                             | Do not hide unsynced local entries.                                   | Screenshot after local save with pending/queued state.                 |
| Subscription locked  | Preserve signed-in escape/settings path and show paid unlock affordance.                                        | No production billing bypass in fixtures or UI tests.                 | Screenshot of locked HUD/paywall handoff.                              |

## Source Material To Reuse

- `apps/ios/LogYourBody/Views/ProgressPhotoCarouselView.swift` for swipeable photo viewport behavior, after adding explicit empty/no-photo states.
- `apps/ios/LogYourBody/Components/PhotoAnchoredTimelineSlider.swift` and `apps/ios/LogYourBody/Components/LiquidGlassTimelineSlider.swift` for scrubber interaction and photo markers.
- `apps/ios/LogYourBody/DesignSystem/Organisms/CoreMetricsRow.swift` and `apps/ios/LogYourBody/DesignSystem/Organisms/DashboardContent.swift` for compact metric-row structure, not full first-screen layout.
- `apps/ios/LogYourBody/Services/MetricsInterpolationService.swift` for interpolation behavior and labels.
- `apps/ios/LogYourBody/Components/DashboardMetricsList.swift` and `apps/ios/LogYourBody/Components/FullMetricChartView.swift` for the secondary stats destination.

## Do Not Carry Forward

- Do not make Body Score the first visual object.
- Do not ship the current Photos tab blank state as the HUD empty state.
- Do not put repeated chart cards on the first screen.
- Do not add chat, food logging, workout tracking, Watch, web app, or iPad-specific work in this lane.
- Do not expand HealthKit, BodySpec/DEXA, smart-scale, or photo-derived metrics until the BodyMetricSource storage/sync contract is in place.

## Implementation Gates

- `ios_photo_timeline_hud`: new HUD route, default off.
- `ios_full_body_composition_dashboard`: legacy/beta source route until HUD and stats pass screenshot/device review.
- BodyMetricSource taxonomy must be additive and stable before import expansion: `manual`, `healthkit`, `smart_scale`, `bodyspec_dexa`, `caliper`, `photo`.

## Done When

JOV-2866 is done when this design target, screenshots, and annotated target are merged. HUD implementation starts only after the state matrix and BodyMetricSource dependency are accepted in follow-up issues.
