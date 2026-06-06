# JOV-2859 Apple Sign-In Gate Evidence

Date: 2026-06-06
Branch: codex/jov-2859-apple-signin-gate
Base: 7bd7acde0fb0a9111e12652aaf77b567cde98038

## Decision

Email OTP is the signed-out primary auth path. Apple Sign-In is hidden by default and can only render when `ios_apple_sign_in_enabled` is true after feature gates have loaded.

This keeps the signed-out surface safe before Statsig or authentication state is available. It also preserves a controlled internal/proven-cohort path for Apple Sign-In without changing code later.

## Implementation

- Added `Constants.appleSignInEnabledFlagKey = "ios_apple_sign_in_enabled"`.
- Added `AuthSurfacePolicy` with `defaultShowsAppleSignIn = false` and `primarySignInMethod = "email_otp"`.
- Made `AnalyticsService.isFeatureEnabled` return false before analytics startup and notify auth views when gates may have changed.
- Updated login and sign-up forms so email OTP renders first and the Apple button only renders when `showsAppleSignIn` is true.
- Added unit coverage for the auth surface policy.
- Added a focused UI smoke test for the default signed-out surface.

## Evidence

- SwiftLint: `swiftlint lint --strict` from `apps/ios` passed with `Done linting! Found 0 violations, 0 serious in 256 files.`
- Simulator build/run: XcodeBuildMCP `build_run_sim` passed on iPhone 17 Pro / iOS 26.5.
  - Build log: `/Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-03988719e21b/logs/build_run_sim_2026-06-06T22-55-41-672Z_pid45897_dc0f159b.log`
  - Runtime log: `/Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-03988719e21b/logs/com.logyourbody.app_2026-06-06T22-57-16-470Z_helperpid46124_ownerpid45897_2ece4abe.log`
- Focused tests: XcodeBuildMCP `test_sim` completed successfully by xcodebuild log.
  - Test log: `/Users/timwhite/Library/Developer/XcodeBuildMCP/workspaces/LogYourBody-03988719e21b/logs/test_sim_2026-06-06T22-59-56-000Z_pid45897_4c62c692.log`
  - Passed: `AuthSurfacePolicyTests.testAppleSignInDefaultsHiddenBeforeFeatureGateLoads`
  - Passed: `AuthSurfacePolicyTests.testAppleSignInCanBeEnabledByFeatureGate`
  - Passed: `AuthSurfacePolicyTests.testEmailOTPRemainsPrimaryLaunchMethod`
  - Passed: `LogYourBodyUITests.testSignedOutAppleSignInHiddenByDefault`
  - Note: the MCP tool timed out waiting for result-bundle metadata, but the xcodebuild log ended with `** TEST EXECUTE SUCCEEDED **`.
- Simulator screenshot: `docs/audits/jov-2859/signed-out-apple-hidden-local-config.jpg`
- Semantic UI snapshot confirmed `Email` field and `Sign up` were present and `Continue with Apple` was absent.

## Out Of Scope

- Real-device Apple Sign-In proof remains in JOV-2865.
- This does not alter Clerk, Apple developer configuration, RevenueCat, or billing behavior.
- This does not enable Apple Sign-In for production users.

## Done When

JOV-2859 is done when the branch lands through PR checks with Apple Sign-In hidden by default on the signed-out iOS surface, email OTP remains primary, and the evidence above is linked from Linear.
