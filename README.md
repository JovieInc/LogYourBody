# LogYourBody

A private iPhone body-composition timeline. Weight, body fat, lean mass, HealthKit data, and progress photos in one place.

The native paid iOS app is the default product. Web is marketing, legal, support, billing, and first-party APIs.

## Canonical architecture

| Layer         | Source of truth                                                                                                   |
| ------------- | ----------------------------------------------------------------------------------------------------------------- |
| Identity      | Jovie Better Auth issuer, OAuth clients `logyourbody-ios` / `logyourbody-web`. Sign in with Apple only. No Clerk. |
| Cloud data    | Neon via first-party bearer APIs. Native never connects to Postgres.                                              |
| Device data   | Core Data                                                                                                         |
| Product shell | Timeline is paid home. Stats and Chat are peers.                                                                  |
| Chat          | LYB-5 bearer API (`/api/auth/mobile/chat/v1`)                                                                     |
| Photos        | Cloudflare R2 via first-party signed PUTs. Neon stores the public URL, not the bytes.                             |

JOV-4831 / PR #903 owns the remaining Neon schema/sync/delete cutover, including retiring leftover Supabase photo/export/deletion helpers.

## Project structure

```
apps/ios          Native SwiftUI app
apps/web          Next.js marketing / legal / first-party API
packages/         product-registry, shared-lib, design-tokens
supabase/         Legacy photo/export/deletion functions until JOV-4831 cutover
```

## Getting started

Prerequisites: Node.js 20+, pnpm, Xcode 15+ (iOS).

```bash
pnpm install
pnpm --filter logyourbody dev
```

Web env: copy `apps/web/.env.example` to `apps/web/.env` and set Jovie OAuth + Neon (`DATABASE_URL`). Supabase keys remain only for the leftover photo/export/deletion path.

iOS: open `apps/ios/LogYourBody.xcodeproj`, configure signing, build.

## Scripts

From the repo root (pnpm + Turborepo):

- `pnpm lint` / `pnpm typecheck` / `pnpm test` / `pnpm build`
- `pnpm product:check` after registry or public-copy changes
- `pnpm ios` to open the Xcode project

## License

Proprietary. See [LICENSE](LICENSE). This repository is public solely to support CI; it is not open source.

Support: support@logyourbody.com
