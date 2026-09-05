# Vercel deployment

The production web deployment is built in [`.github/workflows/deploy.yml`](../../.github/workflows/deploy.yml) after `main` passes its required checks. The workflow applies the checked-in Neon migrations, runs the web build, then deploys the prebuilt artifact to the linked Vercel project.

GitHub Actions authenticates the Vercel CLI with the repository `VERCEL_TOKEN` secret. Vercel OIDC is for a Vercel build or function to federate with another provider; it does not replace CLI deployment authentication from GitHub Actions.

The Vercel runtime requires a pooled Neon `DATABASE_URL`. Migration jobs use the direct Neon URL held in the GitHub `PROD_DATABASE_URL` secret. Keep both values server-only and never add data-provider credentials under `NEXT_PUBLIC_` names.

Verify a deployment with:

```bash
vercel inspect --scope Jovie
curl --fail --location https://www.logyourbody.com/
```
