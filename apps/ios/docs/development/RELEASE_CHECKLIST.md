# iOS Paid MVP Release Checklist

Use this checklist before sending a LogYourBody iOS build to TestFlight or App Store review.

Follow the exact local, PR, main, TestFlight, and App Store evidence sequence in
`apps/ios/docs/development/RELEASE_EVIDENCE_PATH.md`.

## Configuration

- `AUTH_ISSUER=https://jov.ie/api/auth`, `AUTH_CLIENT_ID=logyourbody-ios`, and `AUTH_REDIRECT_URI=logyourbody://oauth` are configured.
- Phone OTP is the only signed-out auth path.
- Supabase production URL and anon key are configured in `Config.xcconfig`.
- GitHub `Production` environment has `NEXT_PUBLIC_SUPABASE_URL`.
- GitHub `Production` environment has either `NEXT_PUBLIC_SUPABASE_ANON_KEY` or `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY`.
- Jovie has the `logyourbody-ios` public OAuth client with the exact native redirect and PKCE required.
- Supabase RLS policies accept its product session `sub` for `profiles`, `user_profiles`, `body_metrics`, and `daily_metrics`.
- RevenueCat production public key is configured.
- GitHub `Production` environment has `REVENUE_CAT_PUBLIC_KEY`.
- RevenueCat `Premium` entitlement matches `Constants.proEntitlementID`.
- StoreKit/App Store products are attached to the active RevenueCat offering.
- Release workflow verifies the RevenueCat current iOS offering exposes `$rc_annual` -> `com.logyourbody.app.pro1.annual.3daytrial` and `$rc_monthly` -> `com.logyourbody.app.pro1.monthly.3daytrial`.
- Release workflow verifies App Store Connect contains those subscription
  products in a releasable setup state: `READY_TO_SUBMIT` before first review
  or `APPROVED` after Apple approval.
- App Store Connect Paid Apps Agreement, tax, and banking must be active before
  relying on sandbox/TestFlight in-app purchase tests.
- Release workflow validates the actual release ref/SHA instead of the unrelated `preview` branch.
- App Store release workflow is run from `main` with `release_type=app_store`,
  `submit_for_review=true`, `automatic_release=true`, and phased release
  enabled after the TestFlight build is accepted.
- The approved-release monitor is enabled so Apple-approved builds that enter `PENDING_DEVELOPER_RELEASE` are released without a manual App Store Connect click.
- Optional GitHub `Production` secret `STATSIG_CLIENT_SDK_KEY` is set to the
  real production client SDK key when Statsig analytics or experiments are
  needed. V1 launch surfaces must not depend on feature gates.
- Optional GitHub `Production` secret `SENTRY_DSN` is a real value if present.
- Release evidence explicitly records whether production Sentry and Statsig are
  configured. If either optional secret is absent, the release notes must say
  that crash or analytics monitoring proof is not available for that service.
- The photo-first HUD is the default paid MVP surface. V1 launch routing,
  static avatar buckets, and daily weigh-in reminders must not depend on
  Statsig feature gates.
- `ios_phase_insight`, `ios_glp1_weekly_checkin`, and
  `ios_bulk_progress_photo_import` stay off unless separately approved and
  evidenced.

## Product Path

- Fresh install opens to Apple authentication.
- Unpaid authenticated user sees the paywall.
- Purchase success unlocks the photo-first HUD.
- Restore success unlocks the photo-first HUD.
- Paid returning user opens directly to the photo-first HUD after loading.
- Paid user can add one progress photo, log or update weight/body-fat context,
  scrub the timeline, and open Stats as a secondary surface.
- Bulk progress-photo import remains locked or gated by
  `ios_bulk_progress_photo_import`.
- Paid user can export account data from Settings.
- Signed-out user opens to auth.

## Data And Sync

- User can save today's weight/body-fat context locally while online.
- User can save today's weight/body-fat context locally while offline.
- User can attach a progress photo to an existing or newly created body metrics
  timeline point.
- HealthKit allow, deny, and skip paths all lead to a usable app state.
- Sync retries after the device returns online.
- Product-data rows use the Jovie Better Auth subject as the stable `user_id`
  or profile `id`; no Supabase auth principal is created.
- Sync failure shows recoverable UI and does not block local logging.

## Legal And Store Review

- Terms and privacy links open in-app from the paywall.
- App Store metadata has current support and privacy URLs.
- Public support, privacy, and terms URLs return HTTP 200.
- Native settings expose account deletion and data export paths, with support
  email fallback for export requests.
- Camera, photo library, HealthKit, and Face ID usage strings are accurate for any enabled surfaces.
- App Review notes explain the reviewer-accessible Apple path, purchase
  path, photo-first HUD, HealthKit skip/deny behavior, Restore Purchases, Export
  Data, and Delete Account.
- No secrets or local config files are committed.
- Any credential previously exposed in setup docs or logs has been rotated
  before release.
- App icon, display name, bundle identifier, and version/build number are correct.

## Validation

From the repository root:

```bash
pnpm install
pnpm ios:bootstrap-local-config
pnpm lint
pnpm typecheck
pnpm test:ci
```

From `apps/ios/`:

```bash
swiftlint lint --strict
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=LYB Golden iPhone 16' \
  build-for-testing
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=LYB Golden iPhone 16' \
  test
```

## PR Evidence

- Include screenshots or a simulator recording for auth, paywall,
  purchase/restore, photo-first HUD empty/populated states, add-photo
  ready/permission/success states, timeline scrubber, Stats drilldown,
  HealthKit allow/deny fallback, export, and account deletion.
- Include real TestFlight purchase and restore proof: products loaded,
  trial/purchase succeeds, Premium entitlement active, relaunch opens the HUD,
  and restore works after logout/reinstall.
- Include App Review login proof: email OTP path, terms/privacy/health
  disclaimer acceptance, paywall, post-purchase HUD, Settings restore/export/delete.
- Do not run App Store submission with `paywall_testflight_verified=true`
  until a real TestFlight build has loaded subscription products and completed
  purchase plus restore verification.
- Include HealthKit/photo/analytics proof: `healthkit` and `photo` provenance,
  photo upload/sync path, denied-permission fallback, Stats source-state quality,
  and any Statsig/Sentry release events used as launch evidence.
- Include performance proof boundaries: local static/unit performance artifacts
  are acceptable for PR confidence, but frame and hitch budgets require a
  reliable simulator metrics payload or a physical-device Instruments/ETTrace
  artifact before they are reported as passed.
- Include Supabase sync test results.
- Include validation command output and known risks.
