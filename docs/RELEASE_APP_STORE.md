# App Store Submission Runbook (v1.2.0)

The engineering pipeline is fully automated. **One human step** stands between the current state and App Store revenue: a real TestFlight paywall purchase/restore. This runbook is the exact sequence.

## Current state

- App Store version **1.2.0** is stuck in `PREPARE_FOR_SUBMISSION` — nothing has been submitted. The poller `ios-app-store-approved-release.yml` (every 30 min) will auto-release it once Apple approves, but Apple can't approve what was never submitted.
- `ios-release-loop.yml` auto-builds and deploys to **TestFlight** on every push to `main` touching `apps/ios/**`. This is the build you verify against.
- TestFlight upload waits for Apple to finish processing the build before assigning tester groups. The deploy job allows up to 60 minutes for that provider-controlled step.
- App Store submission is gated behind `paywall_testflight_verified: true` — a deliberate manual gate so no build ships without a proven purchase/restore.

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
   - Sign in with email OTP → complete onboarding → reach the paywall.
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
