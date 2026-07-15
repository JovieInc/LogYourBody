# Shared identity iOS smoke test

Run this on a physical iPhone against a non-production Supabase project before
promoting the auth cutover.

## Prerequisites

- Jovie Better Auth issuer deployed with the confidential Supabase OIDC client.
- Twilio Verify service configured on the issuer.
- Supabase custom provider `custom:jovie` configured with the exact Jovie issuer,
  client credentials, and callback.
- A phone number that can receive the verification SMS.

## Flow

1. Install a clean build and launch it.
2. Confirm the signed-out screen has one action: **Continue with phone**. There
   must be no Apple, Google, email, or password path.
3. Enter a phone number in the secure Jovie identity sheet.
4. Enter the SMS code. Confirm the sheet closes and onboarding opens.
5. Complete the profile and save a weight and progress photo.
6. Force-quit and reopen. Confirm the Keychain session restores without another
   code and the data syncs from Supabase.
7. Expire the access token and confirm refresh succeeds without signing out.
8. Revoke/expire the refresh token and confirm the next unauthorized request
   clears local auth and returns to the phone screen.
9. Sign out and inspect UserDefaults. No access, refresh, legacy Clerk, or
   Supabase session token may be present.

## Ownership checks

- The Supabase OIDC identity row links its provider subject to Better Auth `sub`.
- `profiles.id` and every user-owned `user_id` equal the Supabase `auth.uid()`.
- Supabase REST and Storage accept only the Supabase product access token.
- A token for User A cannot read or mutate User B rows or objects.
- RevenueCat is identified with the stable LogYourBody product principal.
