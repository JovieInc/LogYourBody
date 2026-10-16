# App Store Submission Runbook (v1.2.0)

The engineering pipeline is fully automated. **One human step** stands between the current state and App Store revenue: a real TestFlight paywall purchase/restore. This runbook is the exact sequence.

## Current state

- App Store version **1.2.0** is stuck in `PREPARE_FOR_SUBMISSION` — nothing has been submitted. The poller `ios-app-store-approved-release.yml` (every 30 min) will auto-release it once Apple approves, but Apple can't approve what was never submitted.
- `ios-release-loop.yml` auto-builds and deploys to **TestFlight** on every push to `main` touching `apps/ios/**`. This is the build you verify against.
- TestFlight upload waits for Apple to finish processing the build before assigning tester groups. The deploy job allows up to 60 minutes for that provider-controlled step.
- App Store submission is gated behind `paywall_testflight_verified: true` — a deliberate manual gate so no build ships without a proven purchase/restore.

## Read-only ASC readiness readback (LYB-200)

After the readiness PR merges, dispatch on `main`:

```bash
gh workflow run ios-app-store-readiness.yml --ref main
gh run list --workflow ios-app-store-readiness.yml --branch main --event workflow_dispatch --limit 5
# Use the run ID returned above:
gh run watch RUN_ID
```

Link that successful run in LYB-200/LYB-138 and inspect its job-summary table.
A successful job means the readback completed; every **FAIL** row has a named
**Tim-only T1–T7** item to resolve before Submit. Retain those names and the run
link in the release handoff, or replace each with a dedicated fix issue. A red
row never triggers an ASC mutation. The workflow has only GitHub read
permissions, uses the existing release ASC secrets, scopes each ES256 token to
a single GET, and never invokes a submit, attach, or metadata-upload lane.

The report identifies the newest main Release Loop whose **Upload to
TestFlight** step succeeded, even if later processing/distribution failed. It
reads that attempt's version/build log receipt and checks the exact ASC build
for `VALID`, unexpired, iOS 1.2.0, `APP_STORE_ELIGIBLE`, resolved export compliance,
and no association with
another App Store version. It reports whether the build is already selected;
selecting it remains outside this workflow. Missing logs or API access produce
red rows rather than a fallback to an older build.

Both exact `pro1` subscription product IDs must be `READY_TO_SUBMIT` to pass
automatically. The public API does not expose their attachment to an App Store
version, so other states (including `APPROVED`) receive a named Tim-only
attachment/state verification item. Product IDs alone do not verify a live
introductory offer's duration or price.

Live What's New must match the committed storefront manifest, and the report
compares the version's localized description, keywords, promotional text and
support/marketing URLs plus editable app-info name, subtitle and privacy URL.
This is bounded metadata/build evidence; screenshots, app privacy declarations,
agreements, and the real-device purchase/restore proof below still require the
release checklist.

**#1197 resolution:** [the What's New PR](https://github.com/JovieInc/LogYourBody/pull/1197)
already merged on **2026-10-11 at 12:53:51 UTC**, commit
`fe054800d6c4db490e780a8a8620571ebdcacdd2`, and is an ancestor of this change.
No superseding close or additional merge is needed. Its Pro/free-trial/sign-in
notes are committed; only the live readback can confirm ASC has them.

Local regression command (Node 22, no credentials or dependencies):

```bash
node --test .github/scripts/app-store-readiness.test.mjs
```

## Preconditions (machine-verified, no action needed)

These run inside `ios-release-loop.yml`'s `build-release` job and fail the lane if unmet:

- `verify-app-store-subscriptions.rb` — subscription products exist and are in a submittable state
- `verify_revenuecat_offerings.sh` — RevenueCat "main" offering resolves with monthly + annual packages
- `ensure-app-store-free-pricing.rb` — base app price tier is Free (subscriptions carry the revenue)
- `fastlane precheck` — metadata/screenshot compliance
- Metadata present in `apps/ios/fastlane/metadata/en-US/` (name, subtitle, description, keywords, privacy_url, support_url) and screenshots in `apps/ios/fastlane/screenshots/en-US/`

## The one human step

1. **Wait for a fresh TestFlight build** from the latest `main`. Confirm it finished processing and appears in the intended tester group in App Store Connect → TestFlight.
2. On a real device, install that TestFlight build and run the paid path end to end:
   - Continue with Apple → complete onboarding → reach the paywall.
   - **Purchase** the monthly (or annual) subscription with a sandbox account. Confirm the app unlocks (entitlement active, weight logging reachable).
   - Delete + reinstall (or sign out/in), tap **Restore Purchases**, confirm the subscription restores and the app unlocks.
3. Only if both purchase and restore succeed, dispatch the App Store release:

```bash
gh workflow run ios-release-loop.yml \
  -f release_type=app_store \
  -f submit_for_review=true \
  -f automatic_release=true \
  -f phased_release=true \
  -f paywall_testflight_verified=true
```

4. The loop builds, runs precheck, and submits 1.2.0 for review. After Apple approves, `ios-app-store-approved-release.yml` auto-releases it (phased). No further action.

## Watch

```bash
gh run watch $(gh run list --workflow=ios-release-loop.yml --limit 1 --json databaseId --jq '.[0].databaseId')
# After submission, confirm state left PREPARE_FOR_SUBMISSION:
gh run view $(gh run list --workflow=ios-app-store-approved-release.yml --limit 1 --json databaseId --jq '.[0].databaseId') --log | grep -i "App Store version"
```

## If submission is rejected

App Review notes and metadata live in `apps/ios/fastlane/metadata/`. Fix, push to `main` (fresh TestFlight build), re-verify paywall, re-dispatch. The gate exists precisely so a broken paywall never reaches a paying user.
