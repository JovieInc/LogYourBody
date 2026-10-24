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

Next.js config permanently redirects requests whose Host is `logyourbody.com`
to the same path and query on `www.logyourbody.com` with HTTP 308. Vercel project
domain redirects run before application routing, so its existing apex redirect
must also be set to 308.

Read-only Vercel inspection on 2026-10-24 confirmed project
`prj_6seYBdTtY3TuFqrJek1puaFG6Trj` in team
`team_bpNDbti6srVLYPKdmQLu4UgT` has the apex pointing to www with
`redirectStatusCode: null`. The connected tools expose adding domains but not
updating existing domains; the attempted add with 308 returned HTTP 409
`domain_already_in_use` and changed nothing. This host has no Vercel CLI or local
credentials. The live permanent-redirect requirement remains unverified until
the project-domain setting is updated through authenticated Vercel access:

```http
PATCH /v9/projects/prj_6seYBdTtY3TuFqrJek1puaFG6Trj/domains/logyourbody.com?teamId=team_bpNDbti6srVLYPKdmQLu4UgT
Content-Type: application/json

{"redirect":"www.logyourbody.com","redirectStatusCode":308}
```

After deployment, verify the apex response is 308, preserves paths and queries,
and that www returns 200 with one correct canonical and one brand in each title.
Do not remove/re-add the domain to work around the unavailable update operation.
Sitemap route coverage and robots policy remain owned by the sibling issue;
registry-driven origins automatically follow this host choice.

## Verification on 2026-10-24

- `pnpm lint`, `pnpm typecheck`, `pnpm test`, and `pnpm product:check` passed.
  The root test command built the production site and passed all eight Turbo
  tasks, including 122 web Jest suites (1,131 cases) and the voice adapter tests.
- The public metadata contract passed all 23 cases using Next.js's actual
  metadata resolver. Changing the security canonical back to `/` made the guard
  fail; restoring `/security` passed. The smoke regression suite passed 42 cases.
- Against the built local site, all 16 public pages passed rendered canonical
  and title checks. Robots and sitemap GET checks also passed. Three requests
  with the apex Host header returned 308 and preserved their paths and queries.
- The full local production smoke had 36/38 passing checks: its two waitlist
  POST probes failed without the local database configuration required by the
  existing rate limiter. This does not verify the deployed waitlist API.
- Live HTTPS inspection still returned 307 from the apex and the old security
  title and canonical. Deployment and the Vercel domain update remain pending.
  No Vercel token was available from the existing Doppler configuration.
- GBrain write and readback for `logyourbody/lyb-223-public-metadata` both failed
  to connect to `127.0.0.1:7801`; the durable findings remain in this document.

Generated iOS and storefront URL changes were checked by the product registry
suite. Native execution and GitHub checks are left to their configured runners.
