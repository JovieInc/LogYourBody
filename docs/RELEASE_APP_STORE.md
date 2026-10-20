# App Store Submission Runbook (v1.2.0)

The engineering pipeline is fully automated. **One human step** stands between the current state and App Store revenue: a real TestFlight paywall purchase/restore. This runbook is the exact sequence.

## Current state

- App Store version **1.2.0** is stuck in `PREPARE_FOR_SUBMISSION` — nothing has been submitted. The poller `ios-app-store-approved-release.yml` (every 30 min) will auto-release it once Apple approves, but Apple can't approve what was never submitted.
- `ios-release-loop.yml` auto-builds and deploys to **TestFlight** on every push to `main` touching `apps/ios/**`. This is the build you verify against.
- TestFlight upload waits for Apple to finish processing the build before assigning tester groups. The deploy job allows up to 60 minutes for that provider-controlled step.
- App Store submission is gated behind `paywall_testflight_verified: true` — a deliberate manual gate so no build ships without a proven purchase/restore.

## Read-only readiness check

`app-store-metadata-sync.yml` uploads the committed Fastlane metadata to the editable 1.2.0 version with `upload_to_app_store` (`skip_binary_upload`, `skip_screenshots`, `submit_for_review:false`). deliver skips What's New on the first App Store version. The same job then tries to write that field from `release_notes.txt`. When 1.2.0 is the only iOS App Store version and App Store Connect rejects `whatsNew` as not editable, the step warns and succeeds. That same rejection fails the job once a second version exists, and every other rejection fails immediately. It runs on a push to `main` that changes that workflow or the metadata paths. It does not attach a build or submit.

`app-store-connect-readiness.yml` writes a pass/fail table to the job summary for version state, the newest TestFlight-uploaded build, both pro1 3-day-trial subscriptions, and What's New plus the rest of the committed storefront metadata. What's New is N/A when no iOS version was previously released. If a prior live version exists and the text differs from the committed release notes, that row FAILs. It runs on a push to `main` that changes the workflow, the readiness script, or Fastlane metadata, daily at 16:00 UTC, and again after the metadata sync succeeds. A green job means the readback finished. A FAIL row names a follow-up and does not submit, attach a build, or write metadata.

```bash
gh run list --workflow app-store-connect-readiness.yml --branch main --limit 5
```

[#1197](https://github.com/JovieInc/LogYourBody/pull/1197) already merged on 2026-10-11 (`fe054800d6c4db490e780a8a8620571ebdcacdd2`). What's New is N/A on this first version. A prior live version is still compared with that committed text.

## Preconditions (machine-verified, no action needed)

These run inside `ios-release-loop.yml`'s `build-release` job and fail the lane if unmet:

- `verify-app-store-subscriptions.rb` — subscription products exist and are in a submittable state
- `verify_revenuecat_offerings.sh` — RevenueCat "main" offering resolves with monthly + annual packages
- `ensure-app-store-free-pricing.rb` — base app price tier is Free (subscriptions carry the revenue)
- `fastlane precheck` — metadata/screenshot compliance (`apps/ios/fastlane/Precheckfile`; in-app purchases excluded because precheck cannot read them with an API key, so IAP/subscription readiness comes from `app-store-connect-readiness.yml` and the build's subscription verification)
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
