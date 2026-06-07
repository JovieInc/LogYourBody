# JOV-2865 Apple Sign-In Real-Device Evidence

Date: 2026-06-06 local / 2026-06-07 UTC
Branch: codex/jov-2865-apple-signin-proof
Base: origin/main at e32a56a5f6dde5bf7bd7f3ca8cfab8fdc6371200

## Decision

Apple Sign-In remains safely hidden for the paid MVP launch. Email OTP remains the primary signed-out auth path.

Do not enable `ios_apple_sign_in_enabled` for production users until a physical-device run proves the Apple prompt completes, Clerk returns a completed transfer, `clerk.setActive(sessionId:)` succeeds, and the app transitions out of the signed-out UI.

## Current App State

- `Constants.appleSignInEnabledFlagKey` is `ios_apple_sign_in_enabled`.
- `AuthSurfacePolicy.defaultShowsAppleSignIn` is `false`.
- `AuthSurfacePolicy.primarySignInMethod` is `email_otp`.
- `LoginView` and `SignUpView` initialize `showsAppleSignIn` from the local default before feature gates load.
- The Apple button only renders after `AnalyticsService.isFeatureEnabled(flagKey: Constants.appleSignInEnabledFlagKey)` returns true.
- `LogYourBody.entitlements` includes `com.apple.developer.applesignin = Default`.
- `AuthManager` has the Apple credential path wired through `SignIn.authenticateWithIdToken(provider: .apple, idToken:)`, completed-transfer validation, `clerk.setActive(sessionId:)`, session reconciliation, and forced session-state refresh.

## Physical Device Evidence

Device checked with CoreDevice:

- Device: `@timwhite`
- Identifier: `363C1025-47AD-5EA2-A994-134B539FBA6E`
- UDID: `00008130-001958C20A2B803A`
- Hardware: iPhone 15 Pro (`iPhone16,1`)
- OS: iOS 26.5 (`23F77`)
- Reality: physical
- Pairing: paired
- Developer Mode: enabled
- Transport: local network
- Tunnel state during evidence capture: connected
- Lock state: `passcodeRequired=false`, `unlockedSinceBoot=true`

Installed app evidence:

```text
xcrun devicectl device info apps \
  --device 363C1025-47AD-5EA2-A994-134B539FBA6E \
  --bundle-id com.logyourbody.app

Name          Bundle Identifier     Version   Bundle Version
-----------   -------------------   -------   --------------
LogYourBody   com.logyourbody.app   1.2.0     20260607021614
```

Launch evidence:

```text
xcrun devicectl device process launch \
  --terminate-existing \
  --device 363C1025-47AD-5EA2-A994-134B539FBA6E \
  com.logyourbody.app

Launched application with com.logyourbody.app bundle identifier.
processIdentifier: 756
executable: file:///private/var/containers/Bundle/Application/92554A9B-B05E-46DA-8AA8-45E56E71264A/LogYourBody.app/LogYourBody
```

Running process evidence:

```text
xcrun devicectl device info processes \
  --device 363C1025-47AD-5EA2-A994-134B539FBA6E

{
  "executable": "file:///private/var/containers/Bundle/Application/92554A9B-B05E-46DA-8AA8-45E56E71264A/LogYourBody.app/LogYourBody",
  "processIdentifier": 756
}
```

## Existing Simulator And Test Evidence

JOV-2859 and JOV-2863 already prove the safe signed-out surface in deterministic simulator coverage:

- `AuthSurfacePolicyTests.testAppleSignInDefaultsHiddenBeforeFeatureGateLoads`
- `AuthSurfacePolicyTests.testAppleSignInCanBeEnabledByFeatureGate`
- `AuthSurfacePolicyTests.testEmailOTPRemainsPrimaryLaunchMethod`
- `LogYourBodyUITests.testSignedOutAppleSignInHiddenByDefault`
- `docs/audits/jov-2859/signed-out-apple-hidden-local-config.jpg`
- `docs/audits/jov-2863/mvp-ui-smoke-evidence.md`

## What Is Proven

- A physical iPhone can see the current installed LogYourBody app, launch it, and report the live app process.
- The app has the Apple Sign-In entitlement.
- Production launch behavior is safe because Apple Sign-In is locally hidden before feature gates load.
- Email OTP remains the primary and always-visible signed-out auth path for the paid MVP.
- Enabling Apple Sign-In is a Statsig/cohort decision, not a code change.

## What Is Not Proven

The current run did not prove Apple Sign-In can be enabled for production. These items still require a physical-device interactive pass:

- Apple prompt appears after enabling `ios_apple_sign_in_enabled` for an internal/proven cohort.
- Apple credential returns an identity token on the physical device.
- Clerk returns a completed Apple transfer.
- The created Clerk session activates through `clerk.setActive(sessionId:)`.
- The app transitions to the authenticated/paywall path after Apple auth.
- Physical screenshots or screen recording capture the Apple prompt, completion, and post-auth state.

CoreDevice reports `View Device Screen` capability, but this local setup did not expose a scriptable physical-device screenshot command. The machine can provide device/process proof through `devicectl`; Apple prompt proof still needs human interaction and screen evidence from the device or an available device-screen tool.

## Out Of Scope

- No production gate rollout.
- No Clerk dashboard, Apple developer, RevenueCat, or billing configuration changes.
- No auth implementation rewrite.
- No web, Watch, iPad, food logging, workout tracking, or chat assistant work.

## Done When

JOV-2865 is done for the paid MVP launch when Apple Sign-In is either safely hidden or safely enabled with physical-device proof. This branch satisfies the safe-hidden path: the physical device can run the app, Apple Sign-In stays hidden by default, email OTP remains primary, and production enablement remains blocked until the unproven Apple prompt and Clerk session activation steps above are captured.
