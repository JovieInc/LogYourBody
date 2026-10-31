# App Store Submission Runbook (v1.2.0)

The engineering pipeline automates builds and submission. Human release evidence includes a real TestFlight paywall purchase/restore and the initial ASC App Privacy comparison below. This runbook is the exact sequence.

## Current state

- App Store version **1.2.0** was observed `WAITING_FOR_REVIEW` in the [2026-10-31 approved-release run](https://github.com/JovieInc/LogYourBody/actions/runs/41177144249). This satisfies LYB-139's submission sequencing prerequisite; it does not replace native, commerce or privacy release evidence.
- `ios-app-store-approved-release.yml` runs every 30 minutes. It sets review submissions to manual release mode, gates release requests on Sentry health, and monitors every active or paused phased rollout, including older versions after the marketing version changes.
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
are complete; `paywall_testflight_verified` attests only to the purchase/restore.

## TestFlight purchase and restore

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
  -f automatic_release=false \
  -f phased_release=true \
  -f paywall_testflight_verified=true
```

4. The loop builds, runs precheck, and submits for review with manual release and phased rollout. After Apple approves, `ios-app-store-approved-release.yml` requests release only after a HEALTHY decision. Fastlane rejects `automatic_release=true` because Apple would bypass that check.

## Release health (LYB-139)

The existing poller reads [Sentry session health](https://docs.sentry.io/api/releases/retrieve-release-health-session-statistics/) for `jovie/log-your-body-ios`, environment `production`, for the latest 24 complete hours. It queries both the candidate and the preceding released App Store version using their selected ASC builds. The native adapter sets `releaseName` to `ios-<marketing version> (<build>)`; production configuration requires Sentry environment `production`. dSYM upload alone does not prove session delivery. Live session delivery remains unverified until the poller receives sufficient exact-build data.

The policy in `.github/scripts/app-store-release-health.mjs` requires, for both crash-free users and sessions:

- At least 99.50% crash-free for the candidate.
- No drop larger than 0.20 percentage points from the previous released build.
- At least 20 users and 100 sessions for each build in the observation window.

A breached floor or regression is BREACHED. Missing credentials, API failures, empty/invalid data, an incorrect build/window, insufficient samples, or no previous release produce UNVERIFIED. Neither result permits a release request. An ACTIVE phased rollout is [patched to PAUSED](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appstoreversionphasedreleases-_id_) for either result, and a `remediation:app-store-health-<version>` Linear issue is filed or reopened through the existing intake. The step summary records rates, sample sizes, thresholds, window, decision, pause result and issue outcome. The job fails on unsafe or unverified health; pause/intake errors remain visible. Paused releases never resume automatically.

The monitor uses the existing `SENTRY_AUTH_TOKEN` and `LINEAR_API_KEY` secrets. The Sentry session endpoint requires `org:read` (or a broader documented organization scope); symbol-upload access alone may be insufficient. A missing scope yields visible UNVERIFIED, not permission to release. No new secret value is stored in source.

The first App Store release has no previous-version baseline and therefore remains UNVERIFIED. Do not invent a baseline or silently waive it: investigate telemetry and record an explicit owner release decision with the existing release evidence. The monitor has no health bypass. A healthy paused release still needs investigation and a deliberate manual resume in App Store Connect. Apple limits cumulative phase pauses to 30 days; monitoring cannot hold a rollout indefinitely.

For a submission already configured for automatic release (including the original 1.2.0 submission), the first updated poller attempts to set `releaseType=MANUAL` and checks Apple's returned state. If Apple refuses, the summary reports UNVERIFIED and requires setting manual release in App Store Connect. Until that readback succeeds, Apple's existing automatic approval behavior is still possible. After deployment, verify that summary before relying on the pre-release gate.

Local fixture verification: `node --test .github/scripts/app-store-release-health.test.mjs`. It also runs the real Ruby monitor and Fastlane lane with external APIs stubbed; no build is released as a test. The same suite runs in the required shared-lib test task.

## Watch

```bash
gh run watch $(gh run list --workflow=ios-release-loop.yml --limit 1 --json databaseId --jq '.[0].databaseId')
# After submission, confirm state left PREPARE_FOR_SUBMISSION:
gh run view $(gh run list --workflow=ios-app-store-approved-release.yml --limit 1 --json databaseId --jq '.[0].databaseId') --log | grep -i "App Store version"
```

## If submission is rejected

App Review notes and metadata live in `apps/ios/fastlane/metadata/`. Fix, push to `main` (fresh TestFlight build), re-verify paywall, re-dispatch. The gate exists precisely so a broken paywall never reaches a paying user.
