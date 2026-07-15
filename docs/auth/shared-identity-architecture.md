# Shared first-party identity architecture

## Decision

Jovie Better Auth is the single identity authority for Jovie, LogYourBody, and future first-party products. LogYourBody does not run its own auth service and does not broker authentication through Supabase, Clerk, Neon Auth, or another identity vendor.

LogYourBody's identity projection and onboarding profile live in its dedicated Neon project in the Jovie Neon organization. Neon stores a product-local projection keyed by Jovie's immutable OpenID Connect `sub`; it is not a second user directory.

The remaining native metrics, photo-storage, realtime, and sync migration is a separate rollout. Legacy Supabase paths are disabled during that cutover and must never receive a Jovie OAuth token.

## Login surface

Jovie hosts the shared `/identity` experience. The only enabled onboarding method is a phone number followed by an SMS one-time code. Better Auth owns the user, session, OAuth grants, token rotation, and OpenID Connect claims. Twilio Verify is accessed only through Jovie's internal phone-verification adapter.

Social login, enterprise SSO, email/password, and dynamic OAuth client registration are disabled for this phase.

## First-party OAuth clients

| Client            | Type           | Redirect URI                                | Authentication                   |
| ----------------- | -------------- | ------------------------------------------- | -------------------------------- |
| `logyourbody-ios` | Native/public  | `logyourbody://oauth`                       | Authorization Code + PKCE (S256) |
| `logyourbody-web` | Web/public BFF | `https://logyourbody.com/api/auth/callback` | Authorization Code + PKCE (S256) |

Development web redirects are registered explicitly. Redirect matching is exact. Both clients request `openid profile email phone offline_access`, use refresh-token rotation, and have no distributable client secret. The verified phone number is released only under the standard OIDC `phone` scope.

## Web flow

1. `/api/auth/login` generates cryptographically random state and a PKCE verifier.
2. Transaction values are stored in short-lived, secure, HttpOnly, SameSite=Lax cookies.
3. The browser opens Jovie's `/api/auth/oauth2/authorize` endpoint and completes SMS verification.
4. `/api/auth/callback` validates state and exchanges the code directly with Jovie.
5. LYB reads `/oauth2/userinfo`, upserts the Jovie `sub` into Neon, and stores tokens only in secure HttpOnly cookies.
6. `/api/auth/session` refreshes expired access tokens server-side. Browser code never receives the refresh token.

## iOS flow

1. `ASWebAuthenticationSession` opens the same Jovie authorization endpoint.
2. The app generates state and an S256 PKCE verifier/challenge locally.
3. Jovie returns to the exact `logyourbody://oauth` callback.
4. The app validates state, exchanges the code directly with Jovie, and calls userinfo.
5. Access and refresh tokens are stored in Keychain, never `UserDefaults`.
6. The app registers the authenticated Jovie subject through LYB's server-only Neon adapter.

## Data ownership

- Jovie owns credentials, verified phone numbers, OAuth grants, and global account identity.
- LYB Neon owns the identity projection and onboarding state today, and is the destination for product data as each server-side replacement is verified.
- `public.app_users.identity_subject` is the immutable join key to Jovie.
- Neon credentials are server-only. iOS and browser clients use LYB APIs and never connect to Postgres directly.
- Jovie access tokens are accepted only by LYB/Jovie first-party APIs. They are never forwarded to Supabase REST, Storage, Realtime, or Functions.
- Vendor SDK/API calls remain behind internal ports and adapters.

## Security invariants

- PKCE S256 and state validation are mandatory on every authorization request.
- OAuth redirect URIs are exact and pre-registered; dynamic registration is disabled.
- Access tokens expire after 15 minutes; refresh tokens expire after 30 days.
- OAuth client secrets and tokens are hashed in Jovie storage.
- Web auth cookies are HttpOnly, Secure in production, SameSite=Lax, and path-scoped to `/`.
- No Supabase or Clerk auth session is created anywhere in the flow.
