# GitHub Actions Secrets for iOS CI/CD

Use this guide to configure iOS release secrets in GitHub. Do not paste actual
secret values into this repository, pull requests, issues, logs, or docs.

## Required Repository Secrets

- `APP_STORE_CONNECT_API_KEY`
  - Raw App Store Connect private key content in PEM format.
- `APP_STORE_CONNECT_API_KEY_ID`
  - App Store Connect API key ID.
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
  - App Store Connect issuer ID.
- `APPLE_TEAM_ID`
  - Apple Developer team ID.
- `APP_STORE_APP_ID`
  - Numeric App Store Connect app ID for the iOS app.
- `MATCH_PASSWORD`
  - Fastlane Match encryption password.
- `MATCH_GIT_URL`
  - Private Fastlane Match certificates repository URL.
- `MATCH_GIT_BASIC_AUTHORIZATION`
  - Base64 encoded `username:personal_access_token` for the private Match repo.
- `REVENUE_CAT_PUBLIC_KEY`
  - RevenueCat iOS public SDK key used by release config and offering preflight.

## Required Release Environment Secrets

The iOS Release Loop reads production app config from GitHub deployment
environments:

- TestFlight builds use `production-testflight`, which allows release-candidate
  branch dispatches.
- App Store builds use `Production`, which is branch-restricted to protect live
  releases.

Both environments need these secrets:

- `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` or `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY`
- `REVENUE_CAT_PUBLIC_KEY`
- `REVENUE_CAT_API_KEY`

Optional production integrations:

- `STATSIG_CLIENT_SDK_KEY`
- `SENTRY_DSN`

## Match Setup

1. Create a private certificates repository for Fastlane Match.
2. Create a GitHub token with access to that private repository.
3. Store the repository URL in `MATCH_GIT_URL`.
4. Store the base64 encoded `username:token` value in
   `MATCH_GIT_BASIC_AUTHORIZATION`.
5. Store the Match encryption password in `MATCH_PASSWORD`.
6. Run certificate creation locally only when rotating or bootstrapping Match.
   CI release jobs should use readonly Match sync.

## Rotation

If a real value is ever committed or exposed in logs:

1. Revoke or rotate that credential immediately in the source service.
2. Update the matching GitHub secret.
3. Re-run the relevant release workflow.
4. Remove the exposed value from docs/history where feasible.

## Verification

After secrets are configured, run the iOS Release Loop with:

- `release_type=testflight` from a release-candidate branch or `main`.
- `release_type=app_store` from `main`.

The release job must pass:

- production config generation
- RevenueCat offering preflight
- Match certificate sync
- archive/export
- TestFlight or App Store deployment
