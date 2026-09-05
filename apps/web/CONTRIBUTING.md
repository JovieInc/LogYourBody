# Contributing to LogYourBody web

Use Node and pnpm versions declared by the repository. Run commands from the repository root:

```bash
pnpm lint
pnpm typecheck
pnpm test:ci
pnpm --filter logyourbody build
```

Product data is server-side Neon data accessed through first-party APIs. Authentication uses Jovie Better Auth. Do not add browser-accessible database credentials or a direct database client to product UI code.

Schema changes belong in `apps/web/db/migrations` and must be applied with `pnpm --filter logyourbody db:apply:neon` using a direct Neon connection. New user-visible behavior needs appropriate test coverage and a feature gate when the change is risky.
