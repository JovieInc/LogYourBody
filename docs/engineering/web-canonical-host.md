# Public web canonical host (LYB-223)

Public metadata uses `https://www.logyourbody.com`, matching the existing Vercel
serving domain. The product registry owns this origin and public links. The root
layout supplies `metadataBase` and the title template; each public page supplies
its own canonical and title. `/download/ios` intentionally canonicalizes to `/`
because it renders the same landing content. Product routes remain in LYB-100.

The required web tests discover public page files, execute their metadata, and
reject missing or mismatched canonicals and doubled brand titles. Dynamic blog
and tag metadata have explicit cases. Deployment smoke validates rendered public
HTML against the same single alias exception. New dynamic public routes require
adding corresponding test cases.

## Vercel domain redirect

Next.js permanently redirects requests whose Host is `logyourbody.com` to the
same path and query on `www.logyourbody.com` with HTTP 308. That rule runs only
after the request reaches this deployment.

The Vercel project domain redirect runs first. On 2026-10-24 the live apex
answered `https://logyourbody.com/security?x=1` with HTTP 307 to
`https://www.logyourbody.com/security?x=1`. The project and team ids are the
ones pinned in `packages/shared-lib/src/deploy-vercel-env-verify.test.ts`.
This checkout had no Vercel token, so that domain setting was not changed.
Set the existing redirect to 308; do not remove and re-add the domain:

```http
PATCH /v9/projects/$VERCEL_PROJECT_ID/domains/logyourbody.com?teamId=$VERCEL_ORG_ID
Content-Type: application/json

{"redirect":"www.logyourbody.com","redirectStatusCode":308}
```

After deployment, the apex response should be 308 and preserve the path and
query. `www` should return 200 with one self-referencing canonical and one
brand in each public title.

## Sitemap and robots policy (LYB-224)

`apps/web/src/data/publicMarketingRoutes.ts` supplies the sitemap and marketing
route tests with the same 14 public routes. Required web tests compare the
sitemap URLs with that inventory and check the inventory against public page
files, excluding legacy auth and dynamic blog routes. Both the sitemap and
robots host/sitemap directives use the registry's serving origin. Modification
dates are omitted until reliable content or build timestamps are available.
Legacy `/signin` and `/signup` remain blocked in robots until LYB-100 retires
them.

Tim decision flagged: should `/blog` stay in the header and footer while there
are zero published posts? Navigation remains unchanged pending that product
decision; `/blog` stays in the public route inventory.
