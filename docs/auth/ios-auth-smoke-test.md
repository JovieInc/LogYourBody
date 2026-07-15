# iOS SMS auth smoke test

## Preconditions

- Jovie has the `logyourbody-ios` public OAuth client with exact `logyourbody://oauth` redirect.
- Jovie Better Auth phone-number and OAuth-provider plugins are deployed.
- Jovie Twilio Verify credentials are configured server-side.
- LYB production has the pooled Neon `DATABASE_URL` and the `app_users` migration.

## Test

1. Install a clean build and choose **Continue with phone**.
2. Confirm the system browser shows the Jovie-hosted phone number screen with no Apple, Google, email, password, or SSO controls.
3. Enter a real mobile number, receive the SMS code, and submit it.
4. Confirm the browser returns to `logyourbody://oauth` and onboarding opens.
5. Force-quit and reopen; the Keychain-backed session should restore without another code.
6. Wait for or simulate access-token expiry; confirm refresh succeeds without UI.
7. Sign out; confirm the local session is removed and protected screens require login.
8. Verify one `public.app_users` row exists for the Jovie `sub`, with no auth credentials stored in Neon.

Reject the release if callback state validation fails, tokens appear in `UserDefaults`, the app connects directly to Neon, or any Supabase/Clerk/SSO surface appears.
