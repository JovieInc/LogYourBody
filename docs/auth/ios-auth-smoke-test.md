# iOS Auth Smoke Test

Date: 2026-06-02

Purpose: verify that iOS uses Clerk as the only auth source of truth while Supabase remains data/storage only.

## Prerequisites

- Development Clerk project with email-code signup/signin enabled.
- Development Supabase project with Clerk JWT verification configured.
- Local `apps/ios/LogYourBody/Config.xcconfig` including `Config-Development.xcconfig`.
- `APP_ENVIRONMENT = development`.
- `ALLOW_PRODUCTION_SERVICES_IN_DEBUG = NO` unless a human explicitly approves a temporary production-provider test.
- Test mailbox that can receive Clerk verification codes.

## Build Validation

Run from `apps/ios`:

```bash
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  build-for-testing
```

The app must launch without `clerkInitError`. A copied template with placeholder values should fail validation before Clerk loads.

## Fresh Signup

1. Install a clean build or delete the app from the simulator.
2. Launch the app.
3. Create a new account with a unique test email and password.
4. Enter the Clerk email verification code.
5. Confirm the app transitions into the authenticated flow without returning to the verification screen.
6. Confirm onboarding/profile setup can continue.

Expected result:

- Clerk has an active session for the new user.
- The local app state has `isAuthenticated = true`.
- A local Core Data profile exists for the Clerk user id.
- Supabase `profiles.id` equals the Clerk user id.

## Returning Signin

1. Log out.
2. Sign in with the same email using the email-code flow.
3. Enter the Clerk verification code.

Expected result:

- Clerk active session is restored from `createdSessionId`.
- User data reloads without creating a second profile id.
- Supabase requests use a Clerk JWT, not a Supabase Auth token.

## Protected Data Access

While signed in as User A:

1. Add a body metric or weight entry.
2. Upload or select a progress photo if storage is configured.
3. Confirm the rows or storage objects are owned by User A's Clerk user id.
4. Sign out and sign in as User B.
5. Confirm User B cannot see or mutate User A's profile, metrics, photos, DEXA, or GLP-1 rows.

Expected result:

- User-owned tables and storage paths are scoped by `auth.jwt()->>'sub'`.
- Anonymous requests cannot read protected rows.

## Logout Cleanup

1. Sign in.
2. Perform a user-initiated logout.
3. Relaunch the app.
4. Inspect local defaults and Keychain if using a debug helper or LLDB.

Expected result:

- Clerk session is signed out.
- App returns to the unauthenticated state.
- Legacy sensitive `UserDefaults` keys are absent:
  - `authToken`
  - `refreshToken`
  - `accessToken`
  - `idToken`
  - `clerkToken`
  - `clerkSession`
  - `supabaseAccessToken`
  - `supabaseRefreshToken`
  - `currentUser`
- App Keychain auth/session entries are cleared.
- Analytics, error-reporting, and RevenueCat identity state is reset.

## Unauthorized Session Handling

1. Sign in.
2. Revoke or invalidate the Clerk session from the provider console.
3. Trigger a Supabase-backed app request.

Expected result:

- A `401` response drives the app through session-expired logout.
- Pending signup/signin verification state is cleared.
- The app does not retain stale user data as an authenticated session.

## Config Negative Checks

Run these checks with local gitignored config only:

- Development config with `CLERK_PUBLISHABLE_KEY = pk_live_...` and `ALLOW_PRODUCTION_SERVICES_IN_DEBUG = NO` must fail before Clerk loads.
- Production config with `CLERK_PUBLISHABLE_KEY = pk_test_...` must fail before Clerk loads.
- Production config with non-production `SENTRY_ENVIRONMENT` or `STATSIG_ENVIRONMENT_TIER` must fail before Clerk loads.
- Supabase/API URLs whose hosts do not match their expected-host settings must fail before Clerk loads.

## Evidence to Attach to PR

- Xcode build/test command results.
- Simulator screenshots or recording showing signup verification, authenticated landing, and logout.
- Supabase profile row for the test Clerk user id.
- RLS negative check results for User A versus User B.
