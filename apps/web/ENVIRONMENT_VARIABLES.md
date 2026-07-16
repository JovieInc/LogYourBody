# Environment variables

The canonical web architecture uses Jovie Better Auth for identity and Neon
for server-side product data. Postgres URLs and all identity credentials are
server-only; never prefix them with `NEXT_PUBLIC_`.

## Required

```bash
JOVIE_AUTH_ISSUER=https://jov.ie/api/auth
JOVIE_AUTH_CLIENT_ID=logyourbody-web
JOVIE_AUTH_REDIRECT_URI=http://localhost:3000/api/auth/callback
DATABASE_URL=postgresql://...
```

`DATABASE_URL` is the LYB product Neon database. Apply the checked-in schema
with `pnpm --filter logyourbody db:apply:neon` before exercising authenticated
profile or metric flows.

## Optional

```bash
WAITLIST_DATABASE_URL=postgresql://...
OPENAI_API_KEY=...
NEXT_PUBLIC_REVENUECAT_PUBLIC_KEY=...
NEXT_PUBLIC_VERSION=local-dev
```

## Legacy migration variables

The following variables are retained only while the remaining photo/storage,
realtime-sync, and import compatibility code is migrated. They must not be
added to new code, and they must not be used for authentication or new
product-data writes:

```bash
NEXT_PUBLIC_SUPABASE_URL=...
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
SUPABASE_JWT_SECRET=...
```

Production and preview should set the canonical variables first, run the Neon
migrations, and only then remove legacy variables after storage/sync cutover
verification passes.
