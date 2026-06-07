# JOV-2874 Legacy Dashboard Routing Evidence

Date: 2026-06-07
Simulator: iPhone 17 Pro, iOS Simulator, 368x800 screenshots

## Scope

JOV-2874 keeps `ios_full_body_composition_dashboard` as a legacy beta fallback while making `ios_photo_timeline_hud` the intended post-MVP dashboard route. Production-safe default routing remains the paid MVP weight logger when neither dashboard gate is enabled.

## Runtime Evidence

| Scenario                | Launch argument                     | Expected surface                  | Screenshot                                               |
| ----------------------- | ----------------------------------- | --------------------------------- | -------------------------------------------------------- |
| Gate off default        | `-lybUITestPaidMVPFixture`          | Paid MVP weight logger            | [gate-off-mvp.jpg](./gate-off-mvp.jpg)                   |
| Legacy beta fallback    | `-lybUITestFullDashboardFixture`    | Legacy full dashboard tab surface | [legacy-beta-dashboard.jpg](./legacy-beta-dashboard.jpg) |
| Intended post-MVP route | `-lybUITestPhotoTimelineHUDFixture` | Photo-first HUD                   | [photo-hud-route.jpg](./photo-hud-route.jpg)             |

Visual review:

- Gate-off default shows `Weight log` with manual weight entry and no dashboard tabs.
- Legacy beta fallback shows the existing full dashboard with Home, Photos, and Metrics tabs.
- Photo HUD route shows the photo-first timeline HUD with progress photo stage, scrubber, and compact metric cards.

## Automated Validation

Passed:

```bash
swiftlint lint --strict
xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' -only-testing:LogYourBodyTests/LaunchSurfacePolicyTests -only-testing:LogYourBodyTests/PhotoTimelineHUDPolicyTests test
xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPaidMVPFixtureRoutesToGateOffDefaultSurface -only-testing:LogYourBodyUITests/LogYourBodyUITests/testLegacyDashboardFixtureRoutesOnlyToLegacyBetaSurface -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPhotoHUDFixtureRoutesToIntendedPostMVPDashboard test
xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build-for-testing
pnpm lint
pnpm typecheck
pnpm test
git diff --check
```

Notes:

- `pnpm` commands were run under Node v22.22.1 and emitted the existing repo warning that Node 20.x is requested.
- Cached web lint/build/test logs replayed existing warnings, including Next lint deprecation, stale browsers data, and known test console output. No validation command failed.
- The first XcodeBuildMCP focused test call timed out at the tool boundary, so focused tests were rerun with direct `xcodebuild` for deterministic pass/fail output.

## Done When Check

The app now has one intended post-MVP dashboard route (`ios_photo_timeline_hud`) and keeps the old full dashboard reachable only as an explicit legacy beta fallback (`ios_full_body_composition_dashboard`). The paid MVP default remains unchanged when both dashboard gates are off.
