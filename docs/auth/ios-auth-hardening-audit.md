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
- Twilio credentials and phone OTP verification remain server-side.
- Apple, Google, email OTP, and password authentication are absent from the
  current product surface.

The Supabase acceptance contract is mandatory: trusted issuer, pinned audience,
`role=authenticated`, and RLS ownership based on the Better Auth `sub`. See
`shared-identity-architecture.md` and `ios-auth-smoke-test.md` for rollout proof.
