# iOS Paid MVP Release Checklist

Use this checklist before sending a LogYourBody iOS build to TestFlight or App Store review.

## Configuration

- Clerk production publishable key is configured in `Config.xcconfig`.
- GitHub `Production` environment has `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`.
- Email OTP is the primary signed-out auth path for the paid MVP.
- Clerk Apple Sign In is configured for the production app but hidden unless
  `ios_apple_sign_in_enabled` is enabled for internal/proven cohorts.
- Supabase production URL and anon key are configured in `Config.xcconfig`.
- GitHub `Production` environment has `NEXT_PUBLIC_SUPABASE_URL`.
- GitHub `Production` environment has either `NEXT_PUBLIC_SUPABASE_ANON_KEY` or `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY`.
- Supabase RLS policies accept Clerk session JWT `sub` for `profiles`, `user_profiles`, `body_metrics`, and `daily_metrics`.
- RevenueCat production public key is configured.
- GitHub `Production` environment has `REVENUE_CAT_PUBLIC_KEY`.
- RevenueCat `Premium` entitlement matches `Constants.proEntitlementID`.
- StoreKit/App Store products are attached to the active RevenueCat offering.
- Release workflow verifies the RevenueCat current iOS offering exposes `$rc_annual` -> `com.logyourbody.app.pro1.annual.3daytrial` and `$rc_monthly` -> `com.logyourbody.app.pro1.monthly.3daytrial`.
- Release workflow validates the actual release ref/SHA instead of the unrelated `preview` branch.
- App Store release workflow is run from `main` with `release_type=app_store`,
  `submit_for_review=true`, `automatic_release=true`, and phased release
  enabled after the TestFlight build is accepted.
- The approved-release monitor is enabled so Apple-approved builds that enter `PENDING_DEVELOPER_RELEASE` are released without a manual App Store Connect click.
- Optional GitHub `Production` secrets `STATSIG_CLIENT_SDK_KEY` and `SENTRY_DSN` are real values if present.
- `ios_apple_sign_in_enabled` stays off for production users until Apple Sign-In
  has physical-device proof.
- Current JOV-2865 evidence keeps Apple Sign-In safely hidden; production
  enablement still requires physical Apple prompt and Clerk session proof.
- `ios_full_body_composition_dashboard` stays off for the paid MVP App Store
  launch unless the full dashboard has separate approval.
- `ios_photo_timeline_hud` stays off until the photo-first HUD has separate
  design, data, screenshot, and device proof.

## Product Path

- Fresh install opens to auth with email one-time code as the primary action.
- Apple Sign-In is hidden by default and appears only for users/cohorts covered
  by `ios_apple_sign_in_enabled`.
- Unpaid authenticated user sees the paywall.
- Purchase success unlocks the weight logger.
- Restore success unlocks the weight logger.
- Paid returning user opens directly to the weight logger after loading.
- Paid user can log body weight without body-score onboarding or full profile completion.
- Recent entries show the latest saved weight and history.
- Paid user can prepare and share a weight-only CSV export.
- Signed-out user opens to auth.

## Data And Sync

- User can save today's weight locally while online.
- User can save today's weight locally while offline.
- Sync retries after the device returns online.
- Supabase rows use the Clerk user ID for `user_id` or profile `id`.
- Sync failure shows recoverable UI and does not block local logging.

## Legal And Store Review

- Terms and privacy links open in-app from the paywall.
- App Store metadata has current support and privacy URLs.
- Public support, privacy, and terms URLs return HTTP 200.
- Native settings expose account deletion and data export paths, with support
  email fallback for export requests.
- Camera, photo library, HealthKit, and Face ID usage strings are accurate for any enabled surfaces.
- No secrets or local config files are committed.
- Any credential previously exposed in setup docs or logs has been rotated
  before release.
- App icon, display name, bundle identifier, and version/build number are correct.

## Validation

From the repository root:

```bash
pnpm install
pnpm lint
pnpm typecheck
pnpm test:ci
```

From `apps/ios/`:

```bash
swiftlint lint --strict
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build-for-testing
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

## PR Evidence

- Include screenshots or a simulator recording for auth, paywall, purchase/restore, weight logging, recent history, and CSV export.
- Include RevenueCat purchase and restore test results, or explicitly label
  the account-owner sandbox/TestFlight credential blocker.
- Do not run App Store submission with `paywall_testflight_verified=true`
  until a real TestFlight build has loaded subscription products and completed
  purchase plus restore verification.
- Include Supabase sync test results.
- Include validation command output and known risks.
