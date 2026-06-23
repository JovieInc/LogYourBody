# iOS Release Evidence Path

This is the exact evidence path for moving a LogYourBody iOS change from local proof to TestFlight or App Store review. The local bootstrap below is secret-free and proves compile/UI fixture health only; production Clerk, Supabase, RevenueCat, TestFlight, and App Store behavior require the later workflow and external proof steps.

## 1. Local Config Bootstrap

From the repository root:

```bash
pnpm ios:bootstrap-local-config
```

This creates missing ignored files without overwriting real local config:

- `apps/ios/LogYourBody/Config-Development.xcconfig`
- `apps/ios/LogYourBody/Config.xcconfig`
- `apps/ios/Supabase.xcconfig`

Use `bash scripts/ios/bootstrap-local-config.sh --force` only when resetting local or CI placeholder config intentionally.

## 2. Local Build Proof

From `apps/ios/`:

```bash
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=LYB Golden iPhone 16' \
  -derivedDataPath test_results/release-proof/DerivedData \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build-for-testing
```

If the named simulator is unavailable, resolve the destination first:

```bash
DESTINATION=auto pnpm ios:launch-quality-audit
```

## 3. Focused XCTest Shards

From `apps/ios/`, after the build-for-testing command above:

```bash
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=LYB Golden iPhone 16' \
  -derivedDataPath test_results/release-proof/DerivedData \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:LogYourBodyTests/LaunchSurfacePolicyTests \
  -only-testing:LogYourBodyTests/PhotoTimelineHUDPolicyTests \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  test-without-building
```

```bash
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=LYB Golden iPhone 16' \
  -derivedDataPath test_results/release-proof/DerivedData \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPaywallFixtureShowsRestoreAndLogoutEscapePaths \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPhotoHUDFixtureRoutesToIntendedPostMVPDashboard \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testLaunchQualityGateCapturesCriticalSurfaces \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  test-without-building
```

For the standing local gate, run:

```bash
RUN_LAUNCH_PERFORMANCE=false DESTINATION=auto pnpm ios:quality-gate
```

Record the artifact directory under `apps/ios/test_results/`.

## 3a. Performance And Privacy Proof Boundaries

The local quality gate proves build, launch-surface policy, static SwiftUI
performance smells, and selected performance unit tests. It does not by itself
prove frame-time, hitch, HealthKit permission, or real in-app purchase behavior.

Before claiming runtime performance budgets, capture one of:

- `RUN_TIMELINE_TRACE_WORKFLOW=true RUN_LAUNCH_PERFORMANCE=true DESTINATION=auto pnpm ios:performance-audit` with a passing `summary.json` and usable metric payloads, or
- a physical-device Instruments/ETTrace artifact that records launch, photo HUD
  first render, timeline scrub, Avatar/Photo switching, and Stats round-trip.

`summary.json` is valid performance proof only when every non-skipped section
reports at least one matching test case. Empty `unitCases`, `launchCases`, or
`timelineWorkflowCases` for a non-skipped section are infrastructure failures,
not passed performance evidence.

Launch-quality XCTest result bundles are valid proof only when each non-skipped
shard reports at least one matching test case. Empty launch-quality unit or UI
bundles are selector or target-membership failures, even when `xcodebuild`
exits successfully.

If simulator `xctrace` or XCTest metrics are unavailable, record the limitation
as trace infrastructure evidence only. Do not convert it into a passed
frame/hitch claim.

Before claiming HealthKit readiness, capture allow, deny, and skip behavior with
the current `Info.plist` usage strings and the resulting app state after each
branch. The app must remain usable when HealthKit authorization is denied or
unavailable.

## 4. PR Evidence

The PR must include:

- Local command results and artifact paths from `apps/ios/test_results/`.
- GitHub PR checks from `.github/workflows/ci.yml`: `js`, `iOS`, and `iOS Launch Quality Gate` when iOS files changed.
- The uploaded quality artifact named `ios-launch-quality-gate-<run_id>`.
- Any known simulator limitation called out as local-only, not TestFlight proof.
- Observability state: whether production `SENTRY_DSN` and
  `STATSIG_CLIENT_SDK_KEY` are configured. If either is unset, do not claim
  release crash/analytics monitoring beyond local logging.
- HealthKit allow/deny/skip proof, or an explicit statement that HealthKit proof
  remains pending for App Review.

## 5. Main And Release Evidence

After merge to `main`, use GitHub as the source of truth:

1. Confirm post-merge `main` checks and relevant deployments are green.
2. Run `.github/workflows/ios-release-loop.yml` from `main` for TestFlight or App Store release intent.
3. Capture the release-loop run ID, commit SHA, version/build, TestFlight deployment job result, generated GitHub release tag, and redacted observability status from `LogYourBody/release-observability.md` or the GitHub step summary.
4. Keep `paywall_testflight_verified=false` for App Store submission until a real TestFlight build has completed purchase and restore proof.
5. For App Store review, rerun the release loop with `release_type=app_store`, `submit_for_review=true`, `automatic_release=true`, and `phased_release=true` only after the TestFlight purchase/restore evidence exists.

Final release evidence must name the exact workflow run, release tag, TestFlight/App Store state, and any external blocker such as App Store Connect agreement, sandbox tester, or account-owner approval.

## Latest Completed Release Evidence

As of 2026-06-23, the latest completed `main` release evidence is:

- PR `#442` merged at `8db68ee058f2227e97fe62d51a09869e78243ac6`.
- Post-merge CI run `28008975918` succeeded.
- Web deploy run `28008975912` succeeded.
- iOS release-loop run `28008976044` succeeded.
- TestFlight production deployment succeeded in run `28008976044`.
- GitHub prerelease `ios-v1.2.0-testflight.20260623072428` was created at `2026-06-23T07:38:39Z`.
- App Store approved-release monitor run `28006708745` succeeded, but the public App Store URL returned HTTP `404` again on `2026-06-23T07:46:41Z`; this is not public listing proof.
- App Store direct deploy was skipped by workflow policy.

This evidence proves build, signing, TestFlight upload, release-tag creation,
RevenueCat offering validation, and App Store subscription product validation.
It does not prove real TestFlight purchase/restore, HealthKit allow/deny/skip,
or runtime frame/hitch budgets.
