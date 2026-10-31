# App Store Submission Runbook (v1.2.0)

The engineering pipeline automates builds and submission. Human release evidence includes a real TestFlight paywall purchase/restore and the initial ASC App Privacy comparison below. This runbook is the exact sequence.

## Current state

- App Store version **1.2.0** was `WAITING_FOR_REVIEW` in [approved-release run 41177144249](https://github.com/JovieInc/LogYourBody/actions/runs/41177144249) on 2026-10-31 at 06:35 UTC. Submission (LYB-138) has happened; this satisfies LYB-139's sequencing prerequisite. This is a dated readback, not a current approval receipt.
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
  -f phased_release=true \
  -f paywall_testflight_verified=true
```

4. The loop builds, runs precheck, and submits for review with `automatic_release:false`. After Apple approves, the scheduled approved-release monitor requests release only after verified health. The already-submitted 1.2.0 Apple release setting is not changed by this workflow update; continue manual observation for that submission.

## Watch

```bash
gh run watch $(gh run list --workflow=ios-release-loop.yml --limit 1 --json databaseId --jq '.[0].databaseId')
# After submission, confirm state left PREPARE_FOR_SUBMISSION:
gh run view $(gh run list --workflow=ios-app-store-approved-release.yml --limit 1 --json databaseId --jq '.[0].databaseId') --log | grep -i "App Store version"
```

## If submission is rejected

App Review notes and metadata live in `apps/ios/fastlane/metadata/`. Fix, push to `main` (fresh TestFlight build), re-verify paywall, re-dispatch. The gate exists precisely so a broken paywall never reaches a paying user.

## Release health and phased rollout (LYB-139)

`ios-app-store-approved-release.yml` runs every 30 minutes. Before requesting
release, and on each run for every ACTIVE or PAUSED live rollout, it reads the
build attached to that App Store version. Sentry's identity must match the app's
existing `ios-<marketing version> (<build>)` release name. A newer TestFlight
build with the same marketing version cannot substitute. Active rollouts remain
monitored even when the project or manual `app_version` selects another version.

The monitor queries [Sentry release-health session statistics](https://docs.sentry.io/api/releases/retrieve-release-health-session-statistics/)
for each exact build in the `production` environment with a `24h` window and
`1h` interval. Sentry rounds that window to hour boundaries; its end may be up
to one hour ahead of the request time.
The previous version is the highest lower released iOS version in ASC, using
numeric version ordering, with its own attached build. Both crash-free user and
session fractions must meet the absolute floor and must not regress beyond the
allowed percentage-point drop against that previous build.

Repository variables configure the policy (defaults below):

| Variable                                | Default                                  |
| --------------------------------------- | ---------------------------------------- |
| `RELEASE_HEALTH_MIN_CRASH_FREE_PERCENT` | `99.5` for both users and sessions       |
| `RELEASE_HEALTH_MAX_REGRESSION_PP`      | `0.5` percentage points for both metrics |
| `RELEASE_HEALTH_MIN_SESSIONS`           | `100` per build                          |
| `RELEASE_HEALTH_MIN_USERS`              | `20` per build                           |
| `SENTRY_ORG`                            | `jovie`                                  |
| `SENTRY_PROJECT`                        | `log-your-body-ios`                      |

The existing Actions `SENTRY_AUTH_TOKEN` must have Sentry `org:read` access
(symbol-upload permissions alone do not prove release-health read access).
The job's `GITHUB_TOKEN` has `issues:write` to create or reopen the version's
`[LYB-139] App Store <version> release health` issue. No new credential is added.
Credentials and live session reporting still need a hosted provider receipt;
source inspection and fixtures cannot prove them.

A breach produces **BREACHED**. Missing credentials, missing current/previous
builds, no sessions, null metrics, insufficient samples, an invalid policy, a
wrong release identity, a session window ending more than two hours ago, or no
previous release produces **UNVERIFIED**. Both outcomes fail the job and block
a release request. A known absolute breach remains BREACHED even when previous
health is unavailable. Missing phased-release configuration also blocks release.

For an ACTIVE rollout either outcome requests `phasedReleaseState: PAUSED`
through [Apple's phased-release update API](https://developer.apple.com/documentation/appstoreconnectapi/patch-v1-appstoreversionphasedreleases-_id_).
The response must confirm PAUSED. The monitor then creates or updates one
remediation issue, reopening it if closed, and records metrics, comparison,
decision, pause outcome and issue URL in the step summary. Pause failure still
files remediation; issue failure cannot prevent the pause. Neither failure is
silently successful. PAUSED releases are checked but never automatically resumed.

The first release has no previous-version baseline and stays UNVERIFIED. Do not
call it healthy or weaken policy to bootstrap it. For the already-submitted
1.2.0, manually inspect Sentry Releases for its exact attached build and current
crash-free users/sessions during rollout; confirm the live ASC phase, pause in
ASC on a breach or missing data, and record that decision. Apple release options
already submitted are unchanged here. A first-version release/resume decision
requires explicit operator handling of that missing baseline. Apple limits the
total paused time; the monitor does not provide an indefinite distribution hold.
Pausing phased automatic updates also does not stop users manually downloading
the version. After remediation, verify health and explicitly resume in ASC.

Fixtures cover healthy, breached and no-data outcomes plus regression-only
breaches, exact release identity, stale/null/low-sample data, missing credentials,
active and paused releases, and pause/issue API failures. They execute the real
Ruby monitor with HTTP-only substitutes through the required JavaScript check:

```bash
corepack pnpm --filter @logyourbody/shared-lib exec vitest run src/app-store-release-health.test.ts
```
