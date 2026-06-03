# iOS Auth Environment Setup

LogYourBody iOS uses Clerk for identity and Supabase for data/storage. Real config files are gitignored.

## Files

- `apps/ios/LogYourBody/Config-Development.xcconfig.template`
- `apps/ios/LogYourBody/Config-Production.xcconfig.template`
- `apps/ios/LogYourBody/Config.xcconfig.example`
- `apps/ios/LogYourBody/Config.xcconfig` local include file, gitignored
- `apps/ios/LogYourBody/Config-Development.xcconfig` local secrets, gitignored
- `apps/ios/LogYourBody/Config-Production.xcconfig` local secrets, gitignored

## Development Setup

1. Copy `Config-Development.xcconfig.template` to `Config-Development.xcconfig`.
2. Fill only dev/test provider values:
   - Clerk test/dev publishable key.
   - Clerk dev frontend API.
   - Supabase dev URL and anon key.
   - `SUPABASE_EXPECTED_HOST` matching the Supabase dev URL host.
   - Local or dev `API_BASE_URL` and matching `API_EXPECTED_HOST`.
3. Create `Config.xcconfig` with:

```xcconfig
#include "Config-Development.xcconfig"
```

4. Keep `ALLOW_PRODUCTION_SERVICES_IN_DEBUG = NO` unless a human explicitly approves a temporary production-provider test.

## Production Setup

1. Copy `Config-Production.xcconfig.template` to `Config-Production.xcconfig`.
2. Fill reviewed production values:
   - Clerk live publishable key.
   - Supabase production URL and anon key.
   - `SUPABASE_EXPECTED_HOST` matching the production Supabase URL host.
   - HTTPS production `API_BASE_URL` and matching `API_EXPECTED_HOST`.
   - Production Statsig and Sentry environment values.
3. Create `Config.xcconfig` with:

```xcconfig
#include "Config-Production.xcconfig"
```

## Runtime Guards

`Configuration.currentAuthEnvironmentValidation` runs before Clerk initialization.

Production rejects:

- Clerk `pk_test_` keys.
- Non-HTTPS API base URL.
- Supabase/API hosts that do not match expected hosts.
- Sentry or Statsig tiers that are not `production`.

Development rejects:

- Clerk `pk_live_` keys unless `ALLOW_PRODUCTION_SERVICES_IN_DEBUG = YES`.
- Supabase/API hosts that do not match expected hosts.

Copied templates with placeholder values are treated as invalid config.

## Secret Rules

- Never commit real `.xcconfig` files.
- Never put Clerk secret keys, Supabase service role keys, Stripe secrets, or provider vault files in the app bundle.
- iOS should use only Clerk publishable keys and Supabase anon keys.
