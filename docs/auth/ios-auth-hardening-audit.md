# iOS shared identity security notes

The iOS identity boundary is `AuthManager`. Product, sync, photo, and Supabase
code obtain an access token through that app-owned boundary; no vendor SDK is
imported by product code.

Controls:

- Authorization Code flow with S256 PKCE, random state, and nonce.
- Exact `logyourbody://oauth` redirect and fixed `logyourbody-ios` client ID.
- Public native client with no embedded secret and no dynamic registration.
- Access, refresh, and ID tokens stored only in Keychain with
  `WhenUnlockedThisDeviceOnly` accessibility.
- Access token refreshed before expiry; refresh failure clears all auth state.
- User identity comes from the signed issuer ID-token claims. The app decodes
  claims for projection; issuer signature/audience validation occurs at the
  token exchange and every accepting backend.
- Apple authentication is brokered by Jovie Better Auth; LYB never accepts an
  Apple token directly or embeds an Apple client secret.
- Google, SMS, email OTP, and password authentication are absent from the
  current product surface. Twilio funding and credential rollout are deferred.

Jovie access tokens are accepted only by LYB/Jovie first-party APIs. The legacy
Supabase data plane is fail-closed during the Neon cutover and must not receive
or attempt to validate a Jovie token. See `shared-identity-architecture.md` and
`ios-apple-auth-smoke-test.md` for rollout proof.
