# App Store Submission Runbook (v1.2.0)

The engineering pipeline automates builds and submission. Human release evidence includes a real TestFlight paywall purchase/restore and the initial ASC App Privacy comparison below. This runbook is the exact sequence.

## Current state

- App Store version **1.2.0** is stuck in `PREPARE_FOR_SUBMISSION` — nothing has been submitted. The poller `ios-app-store-approved-release.yml` (every 30 min) will auto-release it once Apple approves, but Apple can't approve what was never submitted.
- `ios-release-loop.yml` auto-builds and deploys to **TestFlight** on every push to `main` touching `apps/ios/**`. This is the build you verify against.
- TestFlight upload waits for Apple to finish processing the build before assigning tester groups. The deploy job allows up to 60 minutes for that provider-controlled step.
- App Store promotion requires `build_number` and an equal `paywall_verified_build_number`, attesting that purchase and restore passed on that exact TestFlight binary. Neither input may be omitted for `release_type=app_store`; they remain optional on the shared dispatch form so TestFlight builds need no promotion inputs.

## Read-only readiness check

`app-store-metadata-sync.yml` uploads the committed Fastlane metadata to the editable 1.2.0 version with `upload_to_app_store` (`skip_binary_upload`, `skip_screenshots`, `submit_for_review:false`). deliver skips What's New on the first App Store version. The same job then tries to write that field from `release_notes.txt`. When 1.2.0 is the only iOS App Store version and App Store Connect rejects `whatsNew` as not editable, the step warns and succeeds. That same rejection fails the job once a second version exists, and every other rejection fails immediately. It runs on a push to `main` that changes that workflow or the metadata paths. It does not attach a build or submit.

`app-store-connect-readiness.yml` writes a pass/fail table to the job summary for version state, the newest TestFlight-uploaded build, both pro1 3-day-trial subscriptions, and What's New plus the rest of the committed storefront metadata. What's New is N/A when no iOS version was previously released. If a prior live version exists and the text differs from the committed release notes, that row FAILs. It runs on a push to `main` that changes the workflow, the readiness script, or Fastlane metadata, daily at 16:00 UTC, and again after the metadata sync succeeds. A green job means the readback finished. A FAIL row names a follow-up and does not submit, attach a build, or write metadata.

```bash
gh run list --workflow app-store-connect-readiness.yml --branch main --limit 5
```

[#1197](https://github.com/JovieInc/LogYourBody/pull/1197) already merged on 2026-10-11 (`fe054800d6c4db490e780a8a8620571ebdcacdd2`). What's New is N/A on this first version. A prior live version is still compared with that committed text.

## Preconditions (machine-verified, no action needed)

The TestFlight build checks subscriptions and RevenueCat. App Store promotion resolves the selected release tag and successful TestFlight producing run, then reads ASC to require the exact version/build to be processed, valid and unexpired before any ASC write:

- `verify-app-store-subscriptions.rb` — subscription products exist and are in a submittable state
- `verify_revenuecat_offerings.sh` — RevenueCat "main" offering resolves with monthly + annual packages
- `ensure-app-store-free-pricing.rb` — base app price tier is Free (subscriptions carry the revenue)
- `fastlane precheck` — metadata/screenshot compliance (`apps/ios/fastlane/Precheckfile`; in-app purchases excluded because precheck cannot read them with an API key, so IAP/subscription readiness comes from `app-store-connect-readiness.yml` and the build's subscription verification)
- Metadata present in `apps/ios/fastlane/metadata/en-US/` (name, subtitle, description, keywords, privacy_url, support_url) and screenshots in `apps/ios/fastlane/screenshots/en-US/`

## App Privacy evidence before submission

The versioned [ASC privacy questionnaire](compliance/app-store-privacy.json) and
its [review instructions](compliance/app-store-privacy.md) cover HealthKit,
photos, auth, subscriptions, analytics, diagnostics and coach content. The
required Detect Changes correction ratchet rejects HealthKit/Info.plist drift
on every diff; a green source check does not verify the live ASC answers.

Before the first submission with this inventory, Tim must compare all ASC App
Privacy answers with the questionnaire and record the date, questionnaire
version, source commit, TestFlight build and redacted ASC readback in release
evidence. The committed comparison is currently **pending**. Before later
submissions, reconcile changed answers and the archive's SDK privacy report
against that receipt. Required Reason API declarations in PrivacyInfo remain a
separate review. Do not submit until both privacy evidence and paywall evidence
are complete; `paywall_verified_build_number` attests only to purchase/restore for the selected build.

## TestFlight purchase and restore

1. **Select a TestFlight build** from a successful `main` release-loop run. Record its CFBundleVersion, `ios-v<version>-testflight.<build_number>` release tag, source commit and producing run. Confirm it finished processing and appears in the intended tester group in App Store Connect → TestFlight. Later commits on `main` do not change the binary selected for promotion.
2. On a real device, install that TestFlight build and run the paid path end to end:
   - Continue with Apple → complete onboarding → reach the paywall.
   - **Purchase** the monthly (or annual) subscription with a sandbox account. Confirm the app unlocks (entitlement active, weight logging reachable).
   - Delete + reinstall (or sign out/in), tap **Restore Purchases**, confirm the subscription restores and the app unlocks.
3. Only if both purchase and restore succeed, dispatch the App Store release:

```bash
BUILD_NUMBER="<the TestFlight build number you verified>"
gh workflow run ios-release-loop.yml --ref main \
  -f release_type=app_store \
  -f build_number="$BUILD_NUMBER" \
  -f paywall_verified_build_number="$BUILD_NUMBER" \
  -f submit_for_review=true \
  -f automatic_release=true \
  -f phased_release=true
```

4. The loop validates provenance and ASC processing, runs precheck, and submits the selected TestFlight build for review with binary upload disabled. No archive, signing or IPA download/upload runs on the App Store path. Its summary records the build, release-tag commit, original TestFlight run and dispatcher attestation. Missing or ambiguous tags, unpublished release evidence, failed producing runs, missing TestFlight upload/processing receipts and unprocessed or expired ASC builds fail closed. Restore missing provenance through the normal TestFlight release path; never substitute dispatch HEAD or the latest ASC build. After Apple approves, `ios-app-store-approved-release.yml` auto-releases it (phased). No further action.

## Watch

```bash
gh run watch $(gh run list --workflow=ios-release-loop.yml --limit 1 --json databaseId --jq '.[0].databaseId')
# After submission, confirm state left PREPARE_FOR_SUBMISSION:
gh run view $(gh run list --workflow=ios-app-store-approved-release.yml --limit 1 --json databaseId --jq '.[0].databaseId') --log | grep -i "App Store version"
```

## If submission is rejected

App Review notes and metadata live in `apps/ios/fastlane/metadata/`. Fix, push to `main` (fresh TestFlight build), re-verify paywall, re-dispatch. The gate exists precisely so a broken paywall never reaches a paying user.
