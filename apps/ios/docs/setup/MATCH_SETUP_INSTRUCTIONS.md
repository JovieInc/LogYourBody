# Fastlane Match Setup Instructions

Fastlane Match stores encrypted signing certificates and provisioning profiles
in a private repository. Do not commit Match passwords, personal access tokens,
or private certificate material to this app repository.

## Prerequisites

1. Create a private certificates repository.
2. Create a GitHub token that can read that repository.
3. Base64 encode `username:token` locally.
4. Add these GitHub secrets:
   - `MATCH_GIT_URL`
   - `MATCH_GIT_BASIC_AUTHORIZATION`
   - `MATCH_PASSWORD`
   - `APP_STORE_CONNECT_API_KEY`
   - `APP_STORE_CONNECT_API_KEY_ID`
   - `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
   - `APPLE_TEAM_ID`

## Bootstrap Or Rotate Certificates

Run these commands only from a trusted local shell with real values supplied via
environment variables or a local secret manager:

```bash
cd apps/ios
export MATCH_GIT_URL="<private-match-repo-url>"
export MATCH_GIT_BASIC_AUTHORIZATION="<base64-username-token>"
export MATCH_PASSWORD="<match-encryption-password>"
export APP_STORE_CONNECT_API_KEY_PATH="$(pwd)/fastlane/api_key.json"
export MATCH_READONLY=false
bundle exec fastlane match appstore
bundle exec fastlane match development
```

For CI and normal release work, keep Match readonly:

```bash
cd apps/ios
export MATCH_READONLY=true
bundle exec fastlane setup_provisioning type:appstore readonly:true
```

## Troubleshooting

- Invalid password: rotate `MATCH_PASSWORD` only after confirming the current
  certificates repository can be decrypted or intentionally regenerated.
- Authentication errors: confirm the token behind
  `MATCH_GIT_BASIC_AUTHORIZATION` can clone the private Match repo.
- Missing capabilities: confirm the App ID for `com.logyourbody.app` has the
  capabilities required by the iOS target before regenerating profiles.
