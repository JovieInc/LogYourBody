# Vercel deployment

The production web deployment is built in [`.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml) after `main` passes its required checks. The workflow applies the checked-in Neon migrations, runs the web build, then deploys the prebuilt artifact to the linked Vercel project.

The `log-your-body` Vercel project uses `apps/web/` as its Root Directory. Keep **Include source files outside Root Directory** enabled: the Preview install uses the repository-root `pnpm-lock.yaml`, and the app also reads workspace packages and scripts outside `apps/web/`. The build runs `turbo run build --filter=logyourbody...` from the workspace root so shared packages build before Next.js. The source-files setting is stored in Vercel project configuration, so verify it separately when recreating or transferring the project.

GitHub Actions authenticates the Vercel CLI with the repository `VERCEL_TOKEN` secret. Vercel OIDC is for a Vercel build or function to federate with another provider; it does not replace CLI deployment authentication from GitHub Actions.

The Vercel runtime requires a pooled Neon `DATABASE_URL`. Migration jobs use the direct Neon URL held in the GitHub `PROD_DATABASE_URL` secret. Keep both values server-only and never add data-provider credentials under `NEXT_PUBLIC_` names.

Verify a deployment with:

```bash
vercel inspect --scope Jovie
curl --fail --location https://www.logyourbody.com/
```
