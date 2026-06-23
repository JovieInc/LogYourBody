# JOV-2864 App Store Release Closeout

Date: 2026-06-07
Issue: JOV-2864
Branch: `codex/jov-2864-release-evidence`

## Decision

Go for the next controlled App Store submission attempt after this evidence PR lands, with two explicit human-owned gates still required:

- Run `iOS Release Loop` from `main` with `release_type=app_store`, `submit_for_review=true`, `automatic_release=true`, and `phased_release=true`.
- Complete real TestFlight/App Store sandbox purchase and restore proof with an account-owner sandbox Apple ID or physical TestFlight device session.

Do not call the MVP publicly launched yet. The latest automated proof is TestFlight production upload, not Apple review approval or public App Store availability.

## Exact Build State

- Current audited `main` commit: `0c484fca0c188a16b3863d021e28af32798f2566`.
- Xcode release build settings:
  - `MARKETING_VERSION = 1.2.0`
  - `CURRENT_PROJECT_VERSION = 20251126162826`
  - `PRODUCT_BUNDLE_IDENTIFIER = com.logyourbody.app`
  - `DEVELOPMENT_TEAM = G24T327LXT`
  - `CODE_SIGN_STYLE = Manual`
- Latest TestFlight release tag: `ios-v1.2.0-testflight.20260607021614`.
- Latest TestFlight release URL: https://github.com/JovieInc/LogYourBody/releases/tag/ios-v1.2.0-testflight.20260607021614
- Release body records build `20260607021614`, deployment `testflight`, commit `0c484fca0c188a16b3863d021e28af32798f2566`, and TestFlight availability for all testers.

## Main CI And Release Workflow Evidence

Latest `main` evidence after the MVP smoke-coverage merge:

- CI run `27080055563`: success
  - URL: https://github.com/JovieInc/LogYourBody/actions/runs/27080055563
- Deploy run `27080055564`: success
  - URL: https://github.com/JovieInc/LogYourBody/actions/runs/27080055564
- iOS Release Loop run `27080055554`: success
  - URL: https://github.com/JovieInc/LogYourBody/actions/runs/27080055554
  - Completed `Validate Release`, `Check Existing Build`, `Build Release`, `Deploy to TestFlight / Deploy to TestFlight (production)`, and `Create Release`.
  - `Deploy to App Store` was skipped because the push-triggered lane defaults to TestFlight.

Recent launch-lane `main` release-loop runs are also green:

- `21e0264db3934582b6ea33e9b7f90ed94a6d0630`: iOS Release Loop `27078567239`, success.
- `8a4375c1772b698bf43e9c4fb0c7a1ee2113f998`: iOS Release Loop `27077320662`, success.
- `57da3472ca88aea2ecef2932df45083c20ec24de`: iOS Release Loop `27076634846`, success.

## App Store Submission Inputs

Fastlane metadata exists under `apps/ios/fastlane/metadata`:

- Name: `LogYourBody`
- Subtitle: `Weight and body metrics`
- Promotional text: `Log weight, keep recent history, sync to your account, and export your data from a focused tracker.`
- Description: scoped to weight logging, recent history, account sync, CSV export, paid access, and a non-medical disclaimer.
- Keywords: `weight,body metrics,fitness tracker,body composition,progress,health log`
- Marketing URL: https://logyourbody.com
- Support URL: https://logyourbody.com/support
- Privacy URL: https://logyourbody.com/privacy
- Release notes: initial App Store release with paid access, weight logging, recent history, account sync, and CSV export.

Fastlane screenshot inputs exist under `apps/ios/fastlane/screenshots/en-US`:

- `01_APP_IPHONE_65.png`: `1242 x 2688`, RGB PNG.
- `01_IPAD_PRO_3GEN_129.png`: `2048 x 2732`, RGB PNG.

The `submit_app_store` lane uploads metadata and screenshots with `skip_metadata: false`, `skip_screenshots: false`, `submit_for_review` controlled by the workflow input, and App Review contact/notes provided from env vars with safe defaults.

## Public Legal And Support Surfaces

Verified by `curl -L` on 2026-06-07:

- https://logyourbody.com/privacy -> HTTP 200
- https://logyourbody.com/support -> HTTP 200
- https://logyourbody.com/terms -> HTTP 200

The support page exposes:

- `support@logyourbody.com`
- Data export request copy.
- Account deletion FAQ copy pointing users to Settings -> Account -> Delete Account.
- Links to privacy and terms.

The native iOS app includes the review-critical account and legal surfaces:

- `DeleteAccountView` deletes RevenueCat app-user association, resets Health sync, notifies the backend deletion pipeline, deletes the Clerk account, clears local Core Data and local preferences, then logs out.
- `ExportDataView` supports local export and support-email export request fallback.
- Paywall links open terms and privacy.
- Settings exposes manage subscription, restore purchases, export data, and delete account.

Known web-only gap: `apps/web/src/app/settings/account/page.tsx` still simulates deletion. Web account management is outside the paid native iOS MVP surface, but this should be fixed before presenting the web settings account page as a production account-deletion surface. The native iOS and support-page deletion paths are the App Review launch surfaces for this MVP.

## RevenueCat And Purchase Evidence

Confirmed evidence:

- The iOS release workflow verifies the current RevenueCat iOS offering before archiving.
- Latest successful release loop `27080055554` completed `Verify RevenueCat iOS offering`.
- `docs/revenuecat-agentmail-provisioning.md` records the configured RevenueCat project, bundle ID `com.logyourbody.app`, `Premium` entitlement, current offering `default`, and monthly/annual product identifiers:
  - `com.logyourbody.app.pro1.monthly.3daytrial`
  - `com.logyourbody.app.pro1.annual.3daytrial`
- JOV-2862 verified visible paywall purchase, restore, logout, settings, and manage-subscription escape paths in simulator smoke evidence.

Still required before public launch:

- Account-owner TestFlight or sandbox credentials must prove a live purchase and restore.
- App Store Connect products must be approved/available through Apple review, not only configured and returned by RevenueCat.

## Auth And Launch Path Evidence

Launch decision remains email OTP primary:

- `ios_apple_sign_in_enabled` is the visibility gate for Apple Sign-In.
- Signed-out-safe local default is off.
- JOV-2863 UI smoke screenshots prove the signed-out screen shows email OTP and hides Apple by default.
- Apple Sign-In should remain internal/proven only until JOV-2865 supplies physical-device proof.

MVP path evidence:

- JOV-2858 audited the launch flow and release binary.
- JOV-2859 added and verified the Apple Sign-In visibility gate.
- JOV-2860 evidence proves keyboard-open manual weight save and post-save recent history. The original issue was canceled after the fix was already landed in the launch lane.
- JOV-2862 evidence proves paywall and subscription escape paths.
- JOV-2863 evidence proves deterministic signed-out, OTP-ready, paywall, paid weight entry, and settings/logout UI smoke coverage.

## External App Store State

Public App Store URL checked on 2026-06-07:

- https://apps.apple.com/us/app/logyourbody/id6739360530 -> HTTP 404

Follow-up public App Store URL check on 2026-06-23 after PR `#442` and
release-loop run `28008976044`:

- https://apps.apple.com/us/app/logyourbody/id6755209876 -> HTTP 404 at `2026-06-23T07:46:41Z`

This means the app is not publicly available from the App Store listing at audit time. That is not by itself a submission blocker for a prelaunch app, but it is a launch blocker for any claim that the app is live.

Local Codex does not have direct App Store Connect UI access or sandbox Apple ID credentials in this run. App Store Connect submission/approval state must be proven by the `release_type=app_store` workflow run and/or account-owner screenshot/export after submission.

## Human-Owned Gates

These are not hidden as agent work:

1. Confirm App Store Connect metadata, screenshots, privacy nutrition, subscription disclosure, and review notes in the App Store Connect UI before or during the first `app_store` release-loop run.
2. Run or approve the manual `iOS Release Loop` workflow from `main` with `release_type=app_store`.
3. Provide sandbox Apple ID/TestFlight device access for real purchase and restore proof.
4. Confirm Apple review submission status and any rejection/remediation notes.
5. Confirm the public App Store URL returns the live listing after Apple approval/release.

## Done When

JOV-2864 is done when this evidence packet is merged, post-merge CI/deploy/release-loop evidence is attached to Linear, and Linear records the go/no-go state:

- TestFlight production candidate: go.
- App Store submission attempt: go after account-owner confirmation of App Store Connect metadata/privacy/subscription fields.
- Public launch: not yet, pending App Store review approval, public listing availability, and live sandbox/TestFlight purchase and restore proof.
