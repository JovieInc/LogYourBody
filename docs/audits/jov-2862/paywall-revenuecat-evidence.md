# JOV-2862 RevenueCat Paywall Evidence

Date: 2026-06-06
Branch: `codex/jov-2862-revenuecat-paywall`
Base: `8a4375c1772b698bf43e9c4fb0c7a1ee2113f998`

## Scope

- Kept RevenueCat product IDs, pricing, offerings, StoreKit config, and App Store billing metadata unchanged.
- Added a signed-in unsubscribed UI fixture with `-lybUITestPaywallFixture` so paywall smoke coverage does not depend on production auth or billing bypasses.
- Added paywall accessibility identifiers for the locked screen, restore path, logout path, purchase button, and unavailable-plans state.
- Added a subscribed paid-MVP settings entry point so paid users can reach subscription management, restore purchases, and logout from the MVP route.
- Guarded restore purchases before RevenueCat SDK configuration finishes so an early tap returns user-facing copy instead of calling an unconfigured SDK.
- Added focused UI smoke coverage for the paywall and subscribed settings escape paths.

## StoreKit And Product Configuration

- `apps/ios/LogYourBody.storekit` remains in the app resources.
- `apps/ios/LogYourBody.xcodeproj/xcshareddata/xcschemes/LogYourBody.xcscheme` still references `../../../LogYourBody.storekit`.
- StoreKit products verified in the local config:
  - `com.logyourbody.app.pro1.annual.3daytrial`
  - `com.logyourbody.app.pro1.monthly.3daytrial`
- No product IDs, prices, durations, trials, entitlement names, or RevenueCat offering identifiers were changed in this issue.

## Visual Evidence

- Locked paywall: `docs/audits/jov-2862/paywall-locked-state.jpg`
  - Shows `LogYourBody Pro`, unavailable plans copy, `Retry`, `Restore Purchases`, `Log out`, and legal links.
- Restore fallback: `docs/audits/jov-2862/paywall-restore-service-not-ready.jpg`
  - Shows the restore tap returning `No Subscription Found` with `Service not ready. Please try again.` when the SDK is not configured in the local fixture.
- Paywall logout confirmation: `docs/audits/jov-2862/paywall-logout-confirmation.jpg`
  - Shows the signed-in locked user can reach the logout confirmation.
- Subscribed MVP settings entry: `docs/audits/jov-2862/subscribed-mvp-settings-entry.jpg`
  - Shows the paid MVP route with the settings button available.
- Settings top escape path: `docs/audits/jov-2862/settings-top-logout-active.jpg`
  - Shows active subscription state and the top logout action.
- Settings subscription management: `docs/audits/jov-2862/settings-subscription-manage.jpg`
  - Shows the `Subscription` section and `Manage subscription`.
- Settings restore row: `docs/audits/jov-2862/settings-restore-row.jpg`
  - Shows `Manage subscription`, `Restore purchases`, and account deletion nearby in settings.

## Local Validation

- `swiftlint lint --strict` from `apps/ios`
  - Result: passed with `0 violations`.
- XcodeBuildMCP `build_run_sim` on iPhone 17 Pro / iOS 26.5 with `-lybUITestPaywallFixture`
  - Result: succeeded.
  - Build log: `/Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-03988719e21b/logs/build_run_sim_2026-06-07T00-16-44-009Z_pid45897_170e45e0.log`
  - App path: `/Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-03988719e21b/DerivedData/LogYourBody-5571ce19a282/Build/Products/Debug-iphonesimulator/LogYourBody.app`
  - Runtime log: `/Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-03988719e21b/logs/com.logyourbody.app_2026-06-07T00-18-09-407Z_helperpid64850_ownerpid45897_4537526e.log`
- XcodeBuildMCP manual simulator inspection with `-lybUITestPaywallFixture`
  - Confirmed `paywall_title`, `paywall_plans_unavailable_state`, restore, and logout controls.
  - Tapped restore and confirmed the user-facing fallback alert.
  - Tapped logout and confirmed the logout confirmation.
- XcodeBuildMCP manual simulator inspection with `-lybUITestPaidMVPFixture`
  - Confirmed the paid MVP settings entry point.
  - Confirmed Settings exposes active subscription state, manage subscription, restore purchases, and logout.
- Focused direct `xcodebuild` UI smoke:
  - Command:

    ```bash
    xcodebuild -project apps/ios/LogYourBody.xcodeproj \
      -scheme LogYourBody \
      -configuration Debug \
      -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' \
      -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPaywallFixtureShowsRestoreAndLogoutEscapePaths \
      -only-testing:LogYourBodyUITests/LogYourBodyUITests/testSubscribedMVPSettingsExposeSubscriptionEscapePaths \
      -resultBundlePath /tmp/jov-2862-ui.xcresult \
      test
    ```

  - Result: passed.
  - Result bundle: `/tmp/jov-2862-ui.xcresult`
  - Passed:
    - `LogYourBodyUITests.testPaywallFixtureShowsRestoreAndLogoutEscapePaths()`
    - `LogYourBodyUITests.testSubscribedMVPSettingsExposeSubscriptionEscapePaths()`

## Release-Loop Context

- Previous post-merge iOS release-loop evidence for the same paid MVP lane:
  - iOS Release Loop run `27077320662`: succeeded.
  - RevenueCat offering preflight step: succeeded.
  - TestFlight version `1.2.0`, build `20260606235715`.
  - Tag: `ios-v1.2.0-testflight.20260606235715`.

## Sandbox Purchase Limitation

This Codex run did not complete a live App Store sandbox purchase or restore with an account-owner sandbox Apple ID or TestFlight device session. The local work verifies that the app exposes purchase, restore, manage, and logout paths and that restore degrades safely before SDK configuration. A live sandbox purchase/restore remains the required external evidence before App Store launch if account-owner TestFlight or sandbox credentials are made available.

## Done When

JOV-2862 is done when the branch lands through PR checks with the paywall and subscribed settings escape paths covered by deterministic UI smoke, screenshots linked from Linear, no billing configuration drift, and the remaining live sandbox purchase limitation explicitly documented for release readiness.
