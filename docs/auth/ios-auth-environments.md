# iOS authentication environments

LogYourBody uses Jovie's first-party Better Auth deployment as its identity
issuer. Supabase is the OIDC broker for the product's data and storage session.

The app uses Supabase Authorization Code + PKCE, stores only its Supabase
access/refresh tokens in the iOS Keychain, and never contains a client secret.
Supabase delegates identity to Jovie's Better Auth OIDC provider. Sign-in and
sign-up are the same SMS one-time-code flow.

## Required values

```xcconfig
AUTH_PROVIDER_ID = custom:jovie
AUTH_REDIRECT_URI = logyourbody:/$()/oauth
```

The Supabase project must register `custom:jovie` as an OIDC provider with issuer
`https://jov.ie/api/auth`. Its confidential Better Auth client allows only the
callback URL shown by Supabase. Supabase must allow `logyourbody://oauth` as an app
redirect.

Supabase values remain environment-specific:

```xcconfig
SUPABASE_URL = https:/$()/your-project.supabase.co
SUPABASE_EXPECTED_HOST = your-project.supabase.co
SUPABASE_ANON_KEY = your-public-anon-key
```

Production validation requires `custom:jovie`, the fixed native redirect URI, an
explicit HTTPS Supabase host, and production telemetry tiers.

Never put Better Auth secrets, Twilio credentials, Supabase service-role keys,
or OAuth client secrets in the app. Twilio is called only by the server-side
identity adapter.
