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
CRON_SECRET=long-random-server-secret
```

`DATABASE_URL` is the LYB product Neon database. Apply the checked-in schema
with `pnpm --filter logyourbody db:apply:neon` before exercising authenticated
profile or metric flows.

`CRON_SECRET` protects the daily conversation-retention cleanup route. Vercel
sends it only as an authorization header; it must never use a `NEXT_PUBLIC_`
name or be exposed to iOS.

## Optional

```bash
WAITLIST_DATABASE_URL=postgresql://...
OPENAI_API_KEY=...
LYB_CHAT_MODEL=gpt-4o-mini
NEXT_PUBLIC_VERSION=local-dev
```

## Progress photos (Cloudflare R2)

Remote progress-photo uploads fail closed with HTTP 503 until every variable
below is set. Create an R2 bucket, an S3 API token with object read/write, and
a public delivery hostname (custom domain or r2.dev). See
https://developers.cloudflare.com/r2/. These names are server-only; never
prefix them with `NEXT_PUBLIC_`.

```bash
CLOUDFLARE_ACCOUNT_ID=32-char-account-id
CLOUDFLARE_R2_ACCESS_KEY_ID=...
CLOUDFLARE_R2_SECRET_ACCESS_KEY=...
CLOUDFLARE_R2_BUCKET=lyb-progress-photos
CLOUDFLARE_R2_PUBLIC_BASE_URL=https://photos.logyourbody.com
```

iOS requests a short-lived signed PUT from `POST /api/auth/mobile/photos`,
writes JPEG/PNG/WebP bytes directly to R2, then persists the public URL on the
local body-metrics row. Account deletion removes `progress-photos/<subject>/`
when these variables are present.

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
