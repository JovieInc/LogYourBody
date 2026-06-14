# GitHub Secrets Setup

This repository must never contain live credential values. Store release
credentials only in GitHub Secrets or environment-scoped secrets.

## Actions Secrets

Required for iOS signing and App Store Connect:

- `APP_STORE_CONNECT_API_KEY`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
- `APPLE_TEAM_ID`
- `APP_STORE_APP_ID`
- `MATCH_PASSWORD`
- `MATCH_GIT_URL`
- `MATCH_GIT_BASIC_AUTHORIZATION`

Required for paid iOS release config:

- `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` or `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_DEFAULT_KEY`
- `REVENUE_CAT_PUBLIC_KEY`

Optional integrations:

- `SENTRY_DSN`
- `STATSIG_CLIENT_SDK_KEY`

## Setup

1. Open the repository in GitHub.
2. Go to Settings > Secrets and variables > Actions.
3. Add repository-level signing secrets.
4. Go to Settings > Environments > Production.
5. Add production app configuration secrets.
6. Re-run the iOS Release Loop from `main`.

## Security Notes

- Do not commit private keys, Match passwords, personal access tokens, or
  application-specific passwords.
- Do not use Apple ID password fallback in CI; use App Store Connect API key
  authentication.
- Rotate any credential that was previously committed or pasted into a shared
  log.
- Prefer environment secrets for production app config and repository secrets
  for signing material shared across release workflows.
