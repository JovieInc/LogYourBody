# JOV-2863 MVP UI Smoke Evidence

Date: 2026-06-07 UTC
Branch: `codex/jov-2863-mvp-ui-smoke`
Base: `21e0264db3934582b6ea33e9b7f90ed94a6d0630`
Simulator: iPhone 17 Pro, iOS 26.5 (`1F5679FD-2B72-40E4-816A-4B58E36C032B`)

## Scope

JOV-2863 adds deterministic smoke coverage for the current paid iOS MVP launch path. The tests cover the signed-out email-first surface, OTP-ready verification surface, paywall escape and restore controls, paid weight entry with the keyboard open, and subscribed settings escape paths.

The fixtures are DEBUG-only launch arguments:

- `-lybUITestSignedOutFixture`
- `-lybUITestEmailVerificationFixture`
- `-lybUITestPaywallFixture`
- `-lybUITestPaidMVPFixture`

These fixtures do not create a production auth, billing, privacy, or entitlement bypass. They only put the app into deterministic signed-out, OTP-ready, subscribed, or unsubscribed UI states for XCTest.

## Coverage

- `testSignedOutAppleSignInHiddenByDefault`
  - Proves email OTP is primary.
  - Proves the Apple button remains hidden when the signed-out-safe local default is off.
- `testEmailVerificationFixtureShowsOTPReadyState`
  - Proves the OTP-ready state displays the pending email, disabled verify button, OTP control, and resend timer.
- `testPaywallFixtureShowsRestoreAndLogoutEscapePaths`
  - Proves the paywall shows restore purchases and logout escape paths without requiring a live sandbox purchase.
- `testPaidMVPWeightEntrySavesWithKeyboardOpen`
  - Proves the weight field accepts input while the keyboard is open, the keyboard save control is reachable, saved feedback appears, legacy `Pending` copy is absent, and the saved weight appears in recent entries.
- `testSubscribedMVPSettingsExposeSubscriptionEscapePaths`
  - Proves paid users can reach settings and see manage subscription, restore purchases, and logout controls.

## Validation

```bash
cd apps/ios
swiftlint lint --strict
```

Result: passed with 0 violations.

```bash
xcodebuild -project apps/ios/LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testSignedOutAppleSignInHiddenByDefault \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testEmailVerificationFixtureShowsOTPReadyState \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPaidMVPWeightEntrySavesWithKeyboardOpen \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testPaywallFixtureShowsRestoreAndLogoutEscapePaths \
  -only-testing:LogYourBodyUITests/LogYourBodyUITests/testSubscribedMVPSettingsExposeSubscriptionEscapePaths \
  -resultBundlePath /tmp/jov-2863-ui.xcresult \
  test
```

Result: passed. `xcresulttool` summary reported 5 passed, 0 failed, 0 skipped.

Result bundle: `/tmp/jov-2863-ui.xcresult`

## Screenshots

- `docs/audits/jov-2863/screenshots/signed-out-email-primary.png`
- `docs/audits/jov-2863/screenshots/email-verification-fixture.png`
- `docs/audits/jov-2863/screenshots/paywall-fixture.png`
- `docs/audits/jov-2863/screenshots/paid-mvp-weight-log-fixture.png`

## Out Of Scope

- Live OTP delivery.
- Live Apple Sign-In.
- Live RevenueCat sandbox purchase or restore.
- Broad end-to-end production auth or billing flows.
- Any production-only bypass for authentication, entitlement, or privacy controls.

Done when the deterministic MVP smoke tests are committed, pass locally, carry screenshot evidence, and pass the repository PR gates.
