# iOS auth environments

Every iOS environment uses Jovie Better Auth directly with OAuth Authorization Code + PKCE.

```xcconfig
AUTH_ISSUER = https:/$()/jov.ie/api/auth
AUTH_CLIENT_ID = logyourbody-ios
AUTH_REDIRECT_URI = logyourbody:/$()/oauth
API_BASE_URL = https:/$()/www.logyourbody.com
API_EXPECTED_HOST = www.logyourbody.com
```

Production validation pins the issuer, client ID, and native callback. The OAuth client is public and has no secret in the app. Tokens are stored only in Keychain. LYB's API validates the Jovie access token and performs all Neon writes server-side.

Native API requests must use the registry's canonical `www` host directly. The
apex redirects across hosts and URLSession drops the bearer header. A failed
`POST /api/auth/mobile/session` then shows “Your LogYourBody account could not be
initialized.” before the app persists the OAuth session. Runtime configuration
and release generation normalize the legacy HTTPS apex override and its matching
expected host; unrelated development endpoints and host mismatches retain their
existing validation.
