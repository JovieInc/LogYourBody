# iOS Paid MVP Release Checklist

Use this checklist before sending a LogYourBody iOS build to TestFlight or App Store review.

## Configuration

- Clerk production publishable key is configured in `Config.xcconfig`.
- Clerk Apple Sign In is enabled for the production app.
- Supabase production URL and anon key are configured in `Config.xcconfig`.
- Supabase RLS policies accept Clerk session JWT `sub` for `profiles`, `user_profiles`, `body_metrics`, and `daily_metrics`.
- RevenueCat production API key is configured.
- RevenueCat `pro` entitlement matches `Constants.proEntitlementID`.
- StoreKit/App Store products are attached to the active RevenueCat offering.

## Product Path

- Fresh install opens to auth with Apple Sign In as the primary action.
- Email one-time code sign-in remains available as fallback.
- New user can complete name, date of birth, sex at birth, and height setup.
- Unpaid authenticated user sees the paywall.
- Purchase success unlocks the dashboard.
- Restore success unlocks the dashboard.
- Paid returning user opens directly to the dashboard after loading.
- Signed-out user opens to auth.

## Data And Sync

- User can save today's weight locally while online.
- User can save today's weight locally while offline.
- Sync retries after the device returns online.
- Supabase rows use the Clerk user ID for `user_id` or profile `id`.
- Sync failure shows recoverable UI and does not block local logging.

## Legal And Store Review

- Terms and privacy links open in-app from the paywall.
- Camera, photo library, HealthKit, and Face ID usage strings are accurate.
- No secrets or local config files are committed.
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

- Include screenshots or a simulator recording for auth, onboarding/profile completion, paywall, dashboard, and logging.
- Include RevenueCat purchase and restore test results.
- Include Supabase sync test results.
- Include validation command output and known risks.
