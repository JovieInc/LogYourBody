# JOV-2871 Photo Timeline HUD Evidence

## Gate and Route

- `ios_photo_timeline_hud` is represented by `Constants.photoTimelineHUDFlagKey`.
- `PhotoTimelineHUDPolicy.defaultShowsPhotoTimelineHUD` is `false`, so the signed-in paid app stays on the MVP surface before the gate is enabled.
- Paid route precedence is photo HUD, legacy full dashboard, then MVP weight logger.
- `ios_full_body_composition_dashboard` remains the legacy full-dashboard route and still renders `DashboardViewLiquid(layoutMode: .legacyTabbed)`.

## Simulator Evidence

- Launch arguments: `-lybUITestPhotoTimelineHUDFixture`
- Simulator: iPhone 17 Pro, iOS 26.5
- Screenshot: `docs/audits/jov-2871/photo-timeline-hud-fixture.jpg`
- Covered states: missing progress photo, measured weight/body-fat/FFMI values, missing steps, and offline sync copy.

## Validation

- `swiftlint lint --strict`
- Focused iOS policy tests: 8 passed, 0 failed via simulator `.xcresult`
- `build_run_sim` with `-lybUITestPhotoTimelineHUDFixture`
- `pnpm lint`
- `pnpm typecheck`
- `pnpm test`

## Done When Check

The gated paid user lands on a photo-first surface with progress-photo priority, a timeline scrubber, compact key metrics, truthful missing-state copy, and the legacy full-dashboard route preserved behind its existing gate.
