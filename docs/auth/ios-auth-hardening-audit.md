# iOS Auth Hardening Audit

Date: 2026-06-02

## Architecture Decision

- iOS identity provider: Clerk.
- iOS data provider: Supabase.
- User ID mapping: Clerk user id is the app user id and Supabase profile id.
- RLS expectation: Clerk JWT `sub` must match `profiles.id` and every user-owned row `user_id`.
- Supabase Auth is not used by iOS in this pass.
- Jovie production auth infrastructure is not used by LogYourBody.

## Auth Source of Truth

`apps/ios/LogYourBody/Services/AuthManager.swift` is the iOS auth entry point. It imports Clerk and owns:

- Clerk SDK initialization.
- Email-code signup.
- Email-code signin.
- Apple OAuth signin through Clerk.
- Session refresh/relaunch state.
- Logout and local auth state cleanup.
- Clerk session JWT access for Supabase data calls.

`apps/ios/LogYourBody/LogYourBodyApp.swift` starts `AuthManager.ensureClerkInitializationTask()` during app startup and passes Clerk through the SwiftUI environment.

## iOS Clerk Call Sites

- `AuthManager.initializeClerk()`: validates config, configures Clerk with publishable key, loads Clerk.
- `AuthManager.startEmailCodeSignIn(email:)`: creates Clerk email-code signin.
- `AuthManager.verifySignInEmail(code:)`: completes signin, sets active Clerk session from `createdSessionId`, refreshes local state.
- `AuthManager.signUp(email:password:name:)`: creates Clerk signup and prepares email-code verification.
- `AuthManager.verifyEmail(code:)`: completes signup, sets active Clerk session from `createdSessionId` when present, refreshes local state.
- `AuthManager.signInWithAppleOAuth()`: starts Clerk Apple OAuth redirect.
- `AuthManager.logout()` / unauthorized handling: signs out Clerk and clears local state.
- `ChangePasswordView`: uses Clerk user password update APIs.

## iOS Supabase Call Sites

Supabase is used as data/storage only:

- `SupabaseManager`: REST data operations for profiles, metrics, photos, DEXA, GLP-1 data. It obtains Clerk JWTs through `Clerk.shared.session.getToken()`.
- `SupabaseDataClient`: low-level data client that accepts an access token from callers.
- `RealtimeSyncManager`: syncs Core Data changes using Clerk session JWTs.
- `PhotoUploadManager`: uploads storage objects using Clerk session JWTs.
- `AuthManager.updateProfile`, legal consent, and delete-account notification: call Supabase REST/functions with Clerk JWTs.

No iOS code should call Supabase Auth or use service-role keys.

## Local Storage Inventory

Sensitive auth/session material must not be stored in `UserDefaults`.

Current behavior:

- Clerk SDK owns its own session persistence.
- App auth state is rebuilt from Clerk session on startup.
- `AuthManager.migrateLegacyAuthStorage(in:)` removes legacy sensitive `UserDefaults` keys including `authToken`, `refreshToken`, `clerkSession`, `supabaseAccessToken`, and `currentUser`.
- Logout clears legacy auth defaults, Keychain app auth data, current user state, analytics identity, error-reporting user id, RevenueCat identity, and pending verification state.

Allowed `UserDefaults` examples:

- UI flags and preferences such as onboarding completion, preferred units, health sync preference, and pending non-sensitive UI tabs.
- Temporary display-name helpers such as `pendingNameUpdate` / `appleSignInName`; these are not tokens and are cleared by name consolidation or reset flows.

## Config Keys Used by Auth

- `APP_ENVIRONMENT`: `development` or `production`.
- `ALLOW_PRODUCTION_SERVICES_IN_DEBUG`: explicit escape hatch for development builds only.
- `CLERK_PUBLISHABLE_KEY`: Clerk publishable key only, never a secret key.
- `CLERK_FRONTEND_API`: Clerk frontend API.
- `SUPABASE_URL`: Supabase project URL.
- `SUPABASE_EXPECTED_HOST`: host allowlist for current environment.
- `SUPABASE_ANON_KEY`: Supabase anon key only, never service role.
- `API_BASE_URL`: app/backend API URL.
- `API_EXPECTED_HOST`: host allowlist for current environment.
- `SENTRY_ENVIRONMENT`: must be `production` in production.
- `STATSIG_ENVIRONMENT_TIER`: must be `production` in production.

## Signup and Signin Paths

Fresh signup:

1. App launches and initializes Clerk after config validation.
2. User enters email/name and requests signup.
3. Clerk sends email code.
4. User verifies email code.
5. App sets the active Clerk session from `createdSessionId` when Clerk returns one.
6. App refreshes local session state, creates local `User`, saves the profile to Core Data, and idempotently upserts the Supabase `profiles` row with a Clerk JWT.
7. User proceeds through legal consent/profile/onboarding/dashboard flows.

Email signin follows the same active-session refresh pattern after email-code verification.

Logout:

1. App signs out Clerk.
2. App clears local user/session state and pending signup/signin verification state.
3. App clears legacy sensitive defaults and app Keychain auth/session data.
4. App resets analytics/error-reporting identity and RevenueCat identity.

## RLS Review

Inspected migrations:

- `supabase/migrations/20250704000003_clerk_safe_migration.sql`
- `supabase/migrations/20250704000004_switch_to_new_tables.sql`
- `supabase/migrations/20250708000000_create_dexa_results.sql`
- `supabase/migrations/20250705000001_create_glp1_medications.sql`

Current RLS shape:

- `profiles`: `id = auth.jwt()->>'sub'`.
- `body_metrics`, `daily_metrics`, `progress_photos`, `weight_logs`, `email_subscriptions`: `user_id = auth.jwt()->>'sub'`.
- Storage `photos` bucket objects: first path segment must match `auth.jwt()->>'sub'`.
- `dexa_results` and `glp1_medications`: `user_id = auth.jwt()->>'sub'`.

Manual verification still required against real dev Supabase:

- User A can select/insert/update own profile.
- User A can insert/select/update own body metrics, daily metrics, photos, DEXA, and GLP-1 data.
- User A cannot select or mutate User B rows.
- Anonymous requests cannot read protected rows.

## Risks Fixed in This PR

- Signup verification now activates the Clerk session from `createdSessionId` when available, matching signin behavior.
- Auth environment config is validated before Clerk initialization.
- Production builds reject Clerk test keys and non-production telemetry tiers.
- Development builds reject Clerk live keys unless explicitly allowed.
- Supabase/API hosts are checked against environment-specific expected hosts.
- Legacy auth/session data is removed from `UserDefaults` on startup and logout.

## Remaining Follow-Ups

- Run the smoke test in `docs/auth/ios-auth-smoke-test.md` with real Clerk/Supabase dev credentials.
- Add automated provider-backed auth smoke coverage if AgentMail or another test mailbox is provisioned.
- Add SQL-level RLS tests if the repo gains a local Supabase test harness.
