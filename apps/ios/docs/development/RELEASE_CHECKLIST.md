# iOS Paid MVP Release Checklist

Use this checklist before sending a LogYourBody iOS build to TestFlight or App Store review.

## Configuration

- Clerk production publishable key is configured in `Config.xcconfig`.
- GitHub `Production` environment has `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`.
- Clerk Apple Sign In is enabled for the production app.
- Supabase production URL and anon key are configured in `Config.xcconfig`.
- GitHub `Production` environment has `NEXT_PUBLIC_SUPABASE_URL`.
- GitHub `Production` environment has either `NEXT_PUBLIC_SUPABASE_ANON_KEY` or `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY`.
- Supabase RLS policies accept Clerk session JWT `sub` for `profiles`, `user_profiles`, `body_metrics`, and `daily_metrics`.
- RevenueCat production API key is configured.
- GitHub `Production` environment has `REVENUE_CAT_API_KEY`.
- RevenueCat `Premium` entitlement matches `Constants.proEntitlementID`.
- StoreKit/App Store products are attached to the active RevenueCat offering.
- Optional GitHub `Production` secrets `STATSIG_CLIENT_SDK_KEY` and `SENTRY_DSN` are real values if present.
- `ios_full_body_composition_dashboard` stays off for the v0.1 App Store launch unless the full dashboard has separate approval.

## Product Path

- Fresh install opens to auth with Apple Sign In as the primary action.
- Email one-time code sign-in remains available as fallback.
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
- Camera, photo library, HealthKit, and Face ID usage strings are accurate for any enabled surfaces.
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

- Include screenshots or a simulator recording for auth, paywall, purchase/restore, weight logging, recent history, and CSV export.
- Include RevenueCat purchase and restore test results.
- Include Supabase sync test results.
- Include validation command output and known risks.
