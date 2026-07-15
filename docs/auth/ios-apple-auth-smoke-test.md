# iOS Apple auth smoke test

## Preconditions

- Jovie has the `logyourbody-ios` public OAuth client with exact `logyourbody://oauth` redirect.
- Jovie Better Auth has its OAuth-provider and Apple social provider configured.
- Apple's service identifier allows Jovie's exact `/api/auth/callback/apple` return URL.
- LYB production has the pooled Neon `DATABASE_URL` and the `app_users` migration.

## Test

1. Install a clean build and choose **Continue with Apple**.
2. Confirm the system browser shows the Jovie-hosted identity screen with Apple as the only method; Google, phone, email, password, and enterprise SSO controls must be absent.
3. Complete Apple authentication, including the private-email relay option.
4. Confirm the browser returns to `logyourbody://oauth` and onboarding opens.
5. Force-quit and reopen; the Keychain-backed session should restore without another sign in.
6. Wait for or simulate access-token expiry; confirm refresh succeeds without UI.
7. Sign out; confirm the local session is removed and protected screens require login.
8. Verify one `public.app_users` row exists for the Jovie `sub`, with no auth credentials stored in Neon.

Reject the release if callback state validation fails, tokens appear in `UserDefaults`, the app connects directly to Neon, an Apple or Jovie token is sent to Supabase, LYB accepts an Apple token directly, or any Supabase/Clerk/Google/SMS/password auth surface appears.
