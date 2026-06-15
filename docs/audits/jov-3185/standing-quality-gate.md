# JOV-3185 Standing iOS Quality Gate

## Summary

The repository now has a repeatable iOS quality gate for the launch-quality issues Tim called out: incohesive social/share layouts, janky screen switching, bottom-card stats switching, over-scroll regressions, and slow first-render performance.

## Gate

Run locally:

```bash
pnpm ios:quality-gate
```

The gate writes artifacts under `apps/ios/test_results/quality-gate/` and runs:

- Strict SwiftLint once.
- Photo timeline HUD policy tests.
- Body Score share card layout tests.
- Timeline UI routing tests with deterministic home and analytics fixture states.
- Screenshot-attached home timeline, analytics, and onboarding fixed-CTA UI tests.
- Dashboard timeline provider performance tests.
- Progress photo image pipeline performance tests.
- Launch performance smoke test.

For the lighter CI-equivalent local path, use:

```bash
RUN_LAUNCH_PERFORMANCE=false DESTINATION=auto pnpm ios:quality-gate
```

## CI Behavior

`.github/workflows/ci.yml` now runs `iOS Launch Quality Gate` for iOS-relevant PRs and `main` pushes. The job uses a stable modern macOS/Xcode lane with concrete iPhone simulator availability, auto-selects an available iPhone simulator, and uploads the result bundles and logs as a GitHub Actions artifact named `ios-launch-quality-gate-<run_id>`.

The CI job is split into visible launch-quality and performance-budget steps. The launch-quality audit runs unit and UI selectors separately with simulator parallelism disabled so GitHub does not use cloned simulator destinations for the screenshot-backed UI checks. CI blocks on those UI checks and the deterministic performance unit budgets; the heavier `testLaunchPerformance` XCTest remains part of the full local audit but is disabled in PR CI to avoid making a simulator launch measurement the required merge bottleneck.

The gate intentionally avoids App Store Connect, TestFlight, Doppler, and production credentials. It uses simulator fixtures and generated local config from the existing iOS setup action so it can run on every iOS PR.

## Current Limits

This is the first standing gate, not the final visual-regression system. It catches concrete layout/navigation regressions through UI assertions and preserves screenshots for review, but it does not yet perform pixel-diff snapshot comparison or Instruments-level hitch budgets.

Next hardening step: add a real screenshot baseline/diff tool or ETTrace-derived hitch budget once the current simulator fixtures stabilize.
