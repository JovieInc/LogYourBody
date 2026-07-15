# Shared Identity Architecture: Jovie + LogYourBody

Date: 2026-07-14
Status: Accepted; implementation in progress

## Decision

Jovie and LogYourBody will use one product-neutral, first-party identity service.
Better Auth is the only source of a person's identity. It runs in Jovie's existing
Next.js/Postgres deployment, behind product-neutral OAuth/OIDC endpoints and
tables. LogYourBody's Supabase project keeps only a derived product principal and
session so its existing RLS data plane can verify requests.

LogYourBody has no production users, so its Clerk integration will be removed in a
clean cutover. There will be no dual-auth period, user-ID compatibility layer, or
legacy session migration for LogYourBody.

## Service Boundary

The identity module is published by `https://jov.ie` and owns only identity
concerns:

- Better Auth core user, account, session, verification, and signing-key tables.
- OAuth client registrations and grants for first-party products.
- Verified phone numbers and identity-level recovery metadata.
- Security events, abuse controls, and session revocation.

It must not create Jovie artists, LogYourBody profiles, subscriptions, onboarding
rows, or other product records. Each product provisions its own local record after
it accepts a valid identity token.

The immutable Better Auth user ID is the cross-product identity subject (`sub`).
Each product may project it to a local principal. Supabase assigns LogYourBody a
local `auth.users.id`; the OIDC identity row durably links that local principal to
the Better Auth subject. LogYourBody rows use the local UUID so native Supabase
RLS semantics remain unchanged.

## Better Auth Configuration

The shared service will pin the same reviewed Better Auth release used by Jovie
and expose standards-based clients through the Better Auth OAuth 2.1 provider.

Required server capabilities:

- `phoneNumber` for six-digit SMS OTP verification and signup-on-verification.
- `jwt` with asymmetric signing, a `kid`, OIDC discovery, and JWKS publication.
- `oauthProvider` for authorization-code + PKCE clients and refresh tokens.
- `bearer` only for first-party native/service calls that cannot use cookies.
- Durable, shared rate limits for send, verify, token, refresh, and recovery paths.
- Postgres-backed sessions and verification state.

Disabled at the LogYourBody launch:

- Email/password.
- Email OTP.
- Google, Apple, and other social providers.
- SAML/enterprise SSO.
- Dynamic client registration.

The provider may retain a migration-only method needed by existing Jovie users,
but client policy must prevent that method from appearing in LogYourBody. Adding
a provider later must not require a LogYourBody client release.

## SMS Provider

Twilio is an adapter behind an internal SMS port. Product and UI code never call
Twilio directly.

Prefer Twilio Verify instead of sending a Better Auth-generated code through the
Messages API. Verify owns code generation, expiry, attempt limits, and carrier
delivery behavior. Better Auth's phone plugin supports provider-owned verification
through `sendOTP` and `verifyOTP`.

Credentials remain server-side and may reuse the existing Jovie Twilio account:

- `TWILIO_ACCOUNT_SID`
- `TWILIO_AUTH_TOKEN`
- A dedicated LogYourBody/shared-auth Verify Service SID

A dedicated Verify service keeps auth traffic, templates, spend, rate limits, and
operational metrics separate from Jovie notification SMS even when the parent
Twilio account is shared.

## Product Clients

Register a separate OAuth client for every trust boundary:

| Client                          | Type         | Flow                           |
| ------------------------------- | ------------ | ------------------------------ |
| Jovie web                       | Confidential | Authorization code + PKCE      |
| Jovie iOS                       | Public       | Authorization code + PKCE      |
| LogYourBody Supabase broker     | Confidential | OIDC authorization code + PKCE |
| LogYourBody account/billing web | Confidential | Authorization code + PKCE      |

Each client has an exact redirect allowlist. The LogYourBody Better Auth client
allows only the Supabase callback URL. Supabase validates issuer, audience, nonce,
ID-token signature, and its provider-side PKCE exchange. The native app separately
uses PKCE when obtaining its Supabase product session.

Cross-product identity is shared. Cross-product silent login is a separate policy
and should remain disabled initially by requesting an explicit login prompt. This
keeps “one account” from silently becoming “one browser session everywhere.”

## LogYourBody iOS Flow

1. The app opens Supabase's authorize endpoint in `ASWebAuthenticationSession`
   for `custom:jovie`, with its app redirect and PKCE challenge.
2. Supabase redirects to the shared Jovie OIDC authorization endpoint.
3. The hosted mobile-first screen asks for a phone number.
4. Twilio Verify sends a six-digit code. The input uses `oneTimeCode` semantics so
   iOS can offer SMS AutoFill.
5. Better Auth verifies the code and creates or restores the shared identity.
6. Supabase verifies the OIDC result, links or creates the product principal, and
   returns a one-time code to the app redirect URI.
7. The app exchanges the code and PKCE verifier for a short-lived Supabase access
   token and rotating refresh token, then stores them in Keychain.
8. LogYourBody provisions its local profile idempotently using `auth.uid()`.

The native app never stores credentials or auth tokens in `UserDefaults` and never
receives Twilio, Better Auth, database, or service-role secrets.

## LogYourBody + Supabase Authorization

LogYourBody registers Jovie as Supabase custom OIDC provider `custom:jovie`.
Supabase validates Better Auth's discovery document, JWKS, ID token, nonce, and
audience, then issues the product-scoped JWT used by REST, Storage, Realtime, and
Functions. Existing policies continue comparing `auth.uid()`/JWT `sub` to the
local profile UUID, row `user_id`, and Storage path prefix.

This is deliberate federation, not a second user-facing auth system: signup,
verification, recovery, phone ownership, and cross-product account identity all
remain in Better Auth. Supabase owns only the LYB data-plane session and derived
principal. No Better Auth, Twilio, OAuth-client, or Supabase service-role secret is
placed in the app, and Jovie never receives the Supabase JWT signing secret.

## Product Provisioning

Authentication and product enrollment are separate transactions.

- Identity creation writes only to the shared identity database.
- A successful Jovie callback idempotently creates or links a Jovie user record.
- A successful LogYourBody callback idempotently creates a LogYourBody profile.
- A failure to provision a product record does not roll back or duplicate the
  identity; the product retries on the next authenticated request.
- Product roles, entitlements, bans, subscriptions, and onboarding state never
  live in identity token source tables.

## Clean LogYourBody Cutover

Because LogYourBody has zero users, replace instead of adapt:

1. Prove the issuer, PKCE, refresh, logout, revocation, SMS, and Supabase RLS
   contracts in development.
2. Add the shared-auth client and Keychain-backed session store to iOS.
3. Replace the email/signup/signin screens with the single SMS authorization path.
4. Replace Clerk token suppliers with the Supabase OIDC-brokered product session
   in REST, Storage, photo upload, Functions, and Realtime.
5. Remove Clerk SDK packages, imports, configuration, middleware, webhook code,
   tests, scripts, docs, and secrets from LogYourBody.
6. Remove Apple/Google buttons and capabilities that exist only for login. Keep
   Apple capabilities required by unrelated app features.
7. Rebuild the empty development data set using shared subject IDs.
8. Verify on a physical iPhone, then ship through the normal PR, CI, TestFlight,
   and production gates.

## Security and Operations

- Exact Better Auth and OAuth-provider package pins.
- Dedicated production/staging issuers and databases; never share signing keys.
- Rotating asymmetric signing keys with an overlap/grace period.
- Short access-token lifetime and rotating refresh tokens with reuse detection.
- Durable per-IP and per-phone rate limits. Store phone hashes—not raw numbers—in
  rate-limit keys and telemetry.
- Generic send responses to avoid phone-number enumeration.
- Twilio errors and logs must redact phone numbers and OTPs.
- Separate Twilio Verify service, spend alerts, geo permissions, and fraud guard.
- No deterministic OTP outside a triple-guarded local/E2E environment.
- Central revocation and per-product session inventory.
- Audit login, verification, refresh, recovery, client, and revocation events
  without recording OTP values or access tokens.

## Rejected Designs

### A Better Auth instance in each product

Rejected because it creates two user stores, two signing-key rotations, two SMS
configurations, and no shared identity.

### Point LogYourBody at Jovie's existing auth tables unchanged

Rejected because Jovie's current Better Auth lifecycle provisions Jovie-specific
application rows. LogYourBody-only signups would leak across the product boundary,
and an outage or schema change in the Jovie product deployment would become an
identity outage for every product.

### Use Supabase Auth as the shared identity source

Rejected because the stated goal is a first-party Better Auth system aligned with
Jovie. Supabase can remain the LogYourBody data plane and, if necessary, a temporary
OIDC token adapter.

### Mint Supabase JWTs in the iOS app

Rejected because it would require a signing secret in the client and would destroy
the RLS trust boundary.

## Implementation Gate

Do not merge or deploy the identity flip until all of these pass:

- Better Auth OAuth discovery and JWKS are reachable at the production-shaped
  issuer path.
- Public-client authorization code flow rejects missing/wrong PKCE and state.
- SMS send/verify is rate-limited, non-enumerating, and works through Twilio Verify.
- Access-token refresh, reuse rejection, logout, and remote revocation are proven.
- Supabase links the Jovie OIDC subject to a stable product principal and accepts
  its product token for REST, Storage, Realtime, and Functions,
  and cross-user/anonymous RLS tests fail closed.
- Jovie-only provisioning is no longer triggered by identity creation.
- LogYourBody can cold-launch, sign in, restore a session, upload a photo, sync,
  sign out, and delete an account on a physical iPhone.
