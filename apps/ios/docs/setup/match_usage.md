# Fastlane Match Usage

The iOS release pipeline uses Fastlane Match with App Store Connect API key
authentication. Keep all real values in local environment variables or GitHub
Secrets.

## Local Readonly Sync

```bash
cd apps/ios
export APP_STORE_CONNECT_API_KEY_PATH="$(pwd)/fastlane/api_key.json"
export MATCH_PASSWORD="<match-encryption-password>"
export MATCH_GIT_URL="<private-match-repo-url>"
export MATCH_GIT_BASIC_AUTHORIZATION="<base64-username-token>"
bundle exec fastlane match appstore --readonly
```

## Regenerate Profiles

Only regenerate profiles intentionally during signing maintenance:

```bash
cd apps/ios
export MATCH_READONLY=false
bundle exec fastlane match appstore
bundle exec fastlane match development
```

## CI Setup

GitHub Actions needs these secret names:

- `APP_STORE_CONNECT_API_KEY`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
- `MATCH_PASSWORD`
- `MATCH_GIT_URL`
- `MATCH_GIT_BASIC_AUTHORIZATION`
- `APPLE_TEAM_ID`

The release workflow should sync Match in readonly mode and should fail if any
required secret is missing.
