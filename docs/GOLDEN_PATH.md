# The LogYourBody Golden Path

**One sentence:** A paying user can launch the app, sign in with their email, subscribe,
log today's weight, immediately see it on their body timeline, and trust that it survives —
offline, across launches, and through sync.

This is the entire value loop of the product. LogYourBody is a paid iOS app with a single
promise: *log your body, see your progress*. If any stage below breaks, a paying user gets
zero value from the app that day — every stage is therefore revenue-critical, and the
Golden Path gate (`GoldenPathTests`) must stay green on every commit to `main`.

## Why this path, from first principles

1. **The product is the loop, not the features.** Avatars, HealthKit, photos, GLP-1 cards
   are all accelerants. The irreducible core is: *get in → record a data point → see it in
   context → trust it persists*. A user who completes this loop daily retains and pays; a
   user who cannot, churns.
2. **It's a paid app.** Auth and the subscription gate are not chrome — they are stages of
   the path. A broken paywall is indistinguishable from a broken app for a new customer.
3. **Offline is the normal case.** People weigh in at home in the bathroom, phone on
   airplane mode, mid-morning in a gym basement. "Saved offline, syncs later" is a stage
   of the path, not an edge case.

## The six stages and their contracts

| # | Stage | Contract | Enforced by |
|---|-------|----------|-------------|
| 1 | **Launch** | The app boots to the pinned paid surface (photo timeline HUD); email OTP is the primary sign-in method; the RevenueCat entitlement is `Premium`. | `GoldenPathTests` GP1 |
| 2 | **Sign in** | An unauthenticated user can never reach the paid surface; a profile is "complete" only with name + DOB + height + gender. | `GoldenPathTests` GP2 |
| 3 | **Subscribe** | An unsubscribed user is gated; a fully qualified user (authed + onboarded + complete profile + subscribed) passes every gate; trial→paid emits the conversion event. | `GoldenPathTests` GP3 |
| 4 | **Log weight** | Valid weights (70–660 lbs / 32–300 kg) save; garbage and out-of-range input is rejected with a plain-language message; no double-submit while saving. | `GoldenPathTests` GP4 |
| 5 | **See it** | A weight logged today appears on the timeline at today's date as *Measured* (not interpolated); the scrubber snaps to the logged date. | `GoldenPathTests` GP5 |
| 6 | **It survives** | Offline saves report "Saved offline"; sync batching never drops or reorders entries; battery policy never stops sync entirely. | `GoldenPathTests` GP6 |

GP7 walks the full journey end-to-end in a single test.

## How it's enforced

- **Suite:** `apps/ios/LogYourBodyTests/GoldenPathTests.swift` — deterministic unit-level
  contract tests over the app's pure policy seams (`EntryDeepLinkPolicy`,
  `PaidWeightLoggerMVPPolicy`, `TimelineDataProvider`, `BatterySyncIntervalPolicy`, …).
  No network, no simulator state, no flakiness.
- **CI:** the `ios_golden_path` job in `.github/workflows/ci.yml` runs
  `bundle exec fastlane golden_path` (hard gate — test failures fail the PR) whenever iOS
  code changes.
- **Local:** `cd apps/ios && bundle exec fastlane golden_path`

## Rules of the road

- **Any change that breaks a Golden Path test is a P0.** Fix the product or, if the product
  decision changed (e.g. a new paid surface), update the contract *and this document in the
  same PR* — the definition and the gate must never drift apart.
- **Keep the suite fast and pure.** UI-level golden path coverage (launch → OTP screen →
  paywall render on simulator) belongs in the launch-quality gate, not here.
- **New golden-path stages** (e.g. progress photos becoming core) require updating this doc,
  the suite, and the table above together.
