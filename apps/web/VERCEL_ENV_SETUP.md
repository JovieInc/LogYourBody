# Vercel Environment Setup

Configure web RevenueCat values in Vercel. Do not commit real keys to docs.

## Prerequisites

1. Install dependencies with `pnpm install`.
2. Authenticate the Vercel CLI.
3. Link the Vercel project.

```bash
pnpm dlx vercel login
pnpm dlx vercel link
```

## Environment Variables

Add these values through the Vercel dashboard or CLI:

- `VITE_SUPABASE_URL`
- `VITE_REVENUECAT_IOS_KEY`
- `VITE_REVENUECAT_WEB_KEY`
- `VITE_REVENUECAT_PUBLIC_KEY` if a legacy web path still reads it

RevenueCat public SDK keys are not private secrets, but they should still be
managed through environment configuration so the docs never drift from the
configured project.

## CLI Flow

```bash
pnpm dlx vercel env add VITE_SUPABASE_URL production
pnpm dlx vercel env add VITE_SUPABASE_URL preview
pnpm dlx vercel env add VITE_REVENUECAT_IOS_KEY production
pnpm dlx vercel env add VITE_REVENUECAT_IOS_KEY preview
pnpm dlx vercel env add VITE_REVENUECAT_WEB_KEY production
pnpm dlx vercel env add VITE_REVENUECAT_WEB_KEY preview
```

## Verification

```bash
pnpm dlx vercel env ls
pnpm --filter apps/web build
```

Redeploy after environment changes so the app receives the latest values.
