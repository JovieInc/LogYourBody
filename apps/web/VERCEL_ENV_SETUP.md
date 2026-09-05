# Vercel environment setup

Use the Vercel CLI from `apps/web` after linking the `log-your-body` project.

```bash
pnpm dlx vercel login
pnpm dlx vercel link
```

Set production `DATABASE_URL` to the pooled Neon connection string. The app also needs its server-side Jovie auth, RevenueCat, Statsig, Sentry, and Cloudflare R2 values when those integrations are enabled. Keep every credential server-only unless the value is explicitly designed for browser use.

```bash
pnpm dlx vercel env ls
pnpm --filter logyourbody build
```

After changing an environment value, deploy a new production artifact and verify the canonical hostname.
