# iOS auth environments

Every iOS environment uses Jovie Better Auth directly with OAuth Authorization Code + PKCE.

```xcconfig
AUTH_ISSUER = https:/$()/jov.ie/api/auth
AUTH_CLIENT_ID = logyourbody-ios
AUTH_REDIRECT_URI = logyourbody:/$()/oauth
API_BASE_URL = https:/$()/logyourbody.com
```

Production validation pins the issuer, client ID, and native callback. The OAuth client is public and has no secret in the app. Tokens are stored only in Keychain. LYB's API validates the Jovie access token and performs all Neon writes server-side.
