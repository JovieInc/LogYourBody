# LogYourBody Full-App Inventory - 2026-06-23

## Executive Summary

This dossier began as a read-only application inventory and execution plan. The
follow-up implementation branch now includes targeted crash-risk, data-drift,
release-evidence, and web-readiness fixes. It still avoids schema changes,
public API changes, and broad product refactors.

The paid native iOS app remains the default launch surface. Web is treated as marketing, legal, support, account, billing, and operational support unless usage proves a full web product is needed.

Current source-derived inventory:

| Surface                   | Count | Notes                                     |
| ------------------------- | ----: | ----------------------------------------- |
| iOS app Swift files       |   290 | `apps/ios/LogYourBody`                    |
| iOS unit-test Swift files |    73 | `apps/ios/LogYourBodyTests`               |
| iOS UI-test Swift files   |     2 | `apps/ios/LogYourBodyUITests`             |
| Web pages                 |    38 | `apps/web/src/app/**/page.tsx`            |
| Web API route handlers    |    12 | `apps/web/src/app/**/route.ts`            |
| Web Jest suites           |    34 | `pnpm --filter logyourbody test:coverage` |
| Web Jest tests            |   300 | All passed in the implementation pass     |

Current validation evidence:

- `pnpm install --frozen-lockfile` passed with Node engine warnings because local Node is `v22.22.1` while the repo expects Node `20.x`.
- `pnpm lint`, `pnpm typecheck`, and `pnpm test:ci` passed.
- `pnpm --filter logyourbody test:coverage` passed: 34 suites, 300 tests.
- Web coverage improved but remains low: 463/6525 lines (7.10%), 481/6977 statements (6.89%), 93/1361 functions (6.83%), 230/4051 branches (5.68%).
- `pnpm check:supabase-migrations` passed and now fails on unsafe legacy-only migration drift or same-filename content mismatches.
- `xcodebuild -list -project apps/ios/LogYourBody.xcodeproj` resolved the iOS packages and listed `LogYourBody`, `LogYourBodyTests`, and `LogYourBodyUITests`.
- Focused `SupabaseURLBuilderTests` passed.
- `RUN_LAUNCH_PERFORMANCE=false DESTINATION=auto pnpm ios:quality-gate` passed and wrote artifacts under `apps/ios/test_results/quality-gate/20260622-211712`.

Appendices:

- [issue-register.csv](issue-register.csv)
- [route-inventory.json](route-inventory.json)
- [ios-screen-inventory.json](ios-screen-inventory.json)
- [architecture.mmd](architecture.mmd)
- [dependency-graph.mmd](dependency-graph.mmd)
- [execution-status.md](execution-status.md)

## Feature Map

### Native iOS Paid Product

| Feature area                | Primary source                                                         | User value                                                    | App Store readiness                                                  |
| --------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------------- |
| Launch/auth routing         | `LogYourBodyApp.swift`, `ContentView.swift`, `AuthManager*`, Clerk SDK | Email OTP/Clerk session restore and signed-out routing        | High impact; auth dead ends block review                             |
| Onboarding/body score       | `Features/Onboarding/**`                                               | Collect baseline body-composition context before the paid HUD | High impact; activation path                                         |
| Paywall/subscription        | `PaywallView.swift`, `RevenueCatManager*`, StoreKit config             | Trial/purchase/restore and paid entitlement                   | Highest App Store gate; needs real TestFlight purchase/restore proof |
| Photo-first HUD             | `MainTabView.swift`, `DashboardViewLiquid*`, timeline components       | Default paid surface for "How am I doing?"                    | Launch-critical                                                      |
| Weight/body metrics logging | `AddEntrySheet*`, `BodyMetricLoggingService`, Core Data                | Minimal daily input and local-first history                   | Launch-critical                                                      |
| HealthKit sync              | `HealthKitManager*`, `HealthSyncCoordinator`                           | Import weight and steps with permission fallback              | Review-sensitive usage strings and denied-state handling             |
| Progress photos             | `ProgressPhotoAttachSheet`, `PhotoUploadManager`, image pipeline       | Visual timeline activation                                    | Performance and privacy sensitive                                    |
| Sync/offline                | `RealtimeSyncManager*`, `CoreDataManager*`, `SupabaseManager*`         | Local-first entry with Supabase sync                          | Data-loss sensitive                                                  |
| Settings/support            | `PreferencesView*`, `ExportDataView`, `DeleteAccountView`              | Restore purchases, export, deletion, preferences              | App Review required                                                  |
| GLP-1 and DEXA/BodySpec     | `Glp1*`, `BodySpec*`, `Dexa*`                                          | Advanced body-composition context                             | Lower priority unless already enabled                                |
| Error/analytics             | `ErrorTrackingService`, `AnalyticsService`, `ExternalServicePorts`     | Release observability and flags                               | Useful for launch confidence                                         |

### Web Product And Support Surface

| Feature area           | Routes                                                                                             | User value                           | Readiness                                    |
| ---------------------- | -------------------------------------------------------------------------------------------------- | ------------------------------------ | -------------------------------------------- |
| Marketing/download     | `/`, `/landing`, `/mobile`, `/download/*`, `/about`, `/brand`                                      | App Store handoff and positioning    | Supportive of iOS launch                     |
| Legal/support/security | `/privacy`, `/terms`, `/support`, `/security`, `/health-disclosure`, `/delete-account`             | Review and customer support surfaces | App Store relevant                           |
| Account/auth           | `/signin`, `/signup`, `/login`, `/auth/callback`, auth API routes                                  | Web account support                  | Must not contradict iOS-first posture        |
| Product web app        | `/dashboard`, `/log`, `/photos`, `/import`, `/steps`, `/settings/*`, `/onboarding`                 | Early web tracking surface           | Deprioritized unless support/billing/account |
| API support            | `/api/weights`, `/api/auth/*`, `/api/webhooks/clerk`, `/api/parse-pdf*`, `/api/app-store-redirect` | Data and operational endpoints       | Needs coverage and production hygiene        |
| Debug/test routes      | None currently mounted; middleware still blocks `/debug*`, `/test*`, `/diag`, and related patterns | Internal diagnostics                 | Keep source-derived inventory guard          |

## User Story Map

### Launch-Critical iOS Stories

1. As a new user, I can open the app, use email OTP, accept required legal/health disclosures, complete baseline onboarding, see the paywall, and start or restore a subscription.
2. As a paid user, I land directly on the photo-first HUD and understand my latest body state without navigating a dense dashboard.
3. As a paid user, I can log today's weight/body-composition context online or offline and see it appear in recent history/timeline state.
4. As a paid user, I can add or attach one progress photo and see the photo-first timeline update without a crash or long UI stall.
5. As a paid returning user, I can restore purchases, export my data, delete my account, manage preferences, and sign out.
6. As a user who denies HealthKit/photo permission, I remain in a usable state with clear fallback behavior.

### Supporting Stories

1. As a reviewer, I can reach support, privacy, terms, restore purchases, export, and delete-account surfaces.
2. As a support user, I can download the iOS app, read legal/support pages, and request help without relying on unfinished web product flows.
3. As an operator, I can trace auth, billing, sync, and crash issues through Sentry/Statsig/GitHub release evidence without exposing secrets.

## Screen Map

Primary iOS navigation:

1. `LogYourBodyApp` handles app startup, deep links, startup tasks, HealthKit bootstrap, bug-report overlays, and global environment objects.
2. `ContentView` gates between auth, email verification, onboarding, profile completion, paywall, reminder prompt, and paid app.
3. `MainTabView` selects the paid surface; current policy defaults to `photoTimelineHUD`.
4. `DashboardViewLiquid` and its extensions own the photo-first timeline HUD, stats surfaces, timeline controls, hero/action areas, metrics, and GLP-1 card.
5. `PreferencesView` and extensions own settings, account, subscription, reminders, photos, tracking goals, security, export, and deletion entry points.

Machine-readable screen and route inventory lives in:

- [ios-screen-inventory.json](ios-screen-inventory.json)
- [route-inventory.json](route-inventory.json)

## Architecture Map

The current application is a monorepo with separate native and web runtimes:

- Native iOS: SwiftUI app, Core Data local store, Clerk auth, RevenueCat subscription state, Supabase REST/sync, HealthKit, Photos, Sentry, Statsig, Fastlane release.
- Web: Next.js App Router, Clerk middleware/auth, Supabase web clients, IndexedDB/offline sync utilities, PDF/OpenAI import routes, Vercel deploy.
- Shared packages: design tokens, shared UI placeholder package, shared migration/edge-function test utilities.
- Backend/data: Supabase migrations under the root `supabase/migrations` tree, plus edge functions for account deletion, export, download, and photo processing.
- CI/release: GitHub `CI`, `Deploy`, `iOS Release Loop`, `iOS TestFlight Deploy`, `Web Release Loop`, CodeQL, and security scanning.

See [architecture.mmd](architecture.mmd) and [dependency-graph.mmd](dependency-graph.mmd).

## Dependency Graph

High-risk dependency boundaries:

| Dependency                 | Current usage                                          | Boundary risk                                                         |
| -------------------------- | ------------------------------------------------------ | --------------------------------------------------------------------- |
| Clerk iOS/web              | Auth/session, JWT for Supabase                         | Launch-critical; vendor imports should stay in adapter/service layers |
| RevenueCat                 | iOS paid access, offering validation, restore/purchase | Highest App Store readiness dependency                                |
| Supabase                   | REST data, RLS, storage, functions, migrations         | Data-loss and schema drift risk                                       |
| HealthKit                  | Weight/steps import, permission states                 | Privacy and App Review-sensitive                                      |
| Photos/PhotosUI            | Progress-photo attachment/import                       | Permission and performance-sensitive                                  |
| Sentry                     | Crash/error tracking                                   | Release observability                                                 |
| Statsig                    | Analytics/feature gates                                | Do not let v1 launch surface depend on gates                          |
| OpenAI/PDF libs            | Web DEXA/PDF parse routes                              | Web-only operational cost/privacy risk                                |
| Vercel                     | Web deploy                                             | Support/legal availability                                            |
| Fastlane/App Store Connect | iOS release                                            | Required external release proof                                       |

## Performance Profile

Known performance-critical areas:

1. Cold launch to auth/paywall/HUD.
2. Photo-first HUD first render.
3. Timeline scrub and Avatar/Photo mode switching.
4. Progress-photo image load, decode, downsample, cache, and upload.
5. Core Data fetch/sort/filter on dashboard and timeline paths.
6. HealthKit import and sync batching.
7. Web dashboard/log/photos/import page render and upload flows.

Current evidence:

- Static SwiftUI performance smell audit passed: no raw image decoding in launch-critical render paths, no inline `ForEach` sort/filter/map in covered launch-critical timeline controls, and no per-render UUID identities in covered rows.
- Launch UI regression audit passed and confirms paid users default to the timeline HUD without Statsig or legacy fallback.
- Existing performance docs set target budgets once reliable device traces work: cold launch to usable timeline hero <= 2.5s, warm launch <= 1.2s, timeline scrub p95 <= 16.7ms, p99 <= 33.3ms, and zero hitches over 250ms during key interactions.
- Runtime trace proof remains incomplete; simulator `xctrace` has known reliability limitations in prior evidence. Device or reliable simulator trace is still required before claiming frame/hitch budgets.

## Test Coverage Report

| Area              | Current evidence                                                                              | Gap                                                              |
| ----------------- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Web Jest          | 34 suites, 300 tests passed                                                                   | Aggregate line coverage is 7.10%                                 |
| Web routes        | Dashboard/log/import/auth/settings and readiness pages covered in parts                       | Many pages, components, sync modules, and API routes are 0%      |
| iOS unit tests    | 73 test files covering auth, sync, HealthKit, dashboard, paywall, photos, metrics, onboarding | Need current full local/CI run after bootstrap                   |
| iOS UI tests      | Launch/paywall/HUD paths exist                                                                | Runtime simulator health must be separated from product failures |
| Static iOS audits | Launch UI and SwiftUI perf smell audits pass                                                  | Static checks do not prove frame times or App Store purchase     |
| Release tests     | Release workflow verifies RevenueCat offering                                                 | Real TestFlight purchase/restore proof remains human/external    |

## Code Health Report

Highest-priority health findings are ranked in [issue-register.csv](issue-register.csv). Themes:

- App Store readiness is proof-gated, not code-gated: the workflow blocks App Store submission until real TestFlight paywall purchase/restore proof exists.
- Local iOS validation is easy to misclassify as broken source until ignored config files are bootstrapped.
- Crash-risk tokens exist in launch-adjacent services and views: forced URL construction, removed-sync `fatalError` sentinels, and force unwraps in OTP/chart/metric UI paths.
- Maintainability risk is concentrated in large files and singleton-heavy service flows: auth, sync, Core Data, RevenueCat, HealthKit, timeline, add-entry, import, export, and profile settings.
- Supabase schema ownership has been consolidated to the root migration tree; the new drift guard should stay in the release path.
- Web debug/test routes are no longer mounted on this branch; middleware still blocks known debug/test patterns before auth if they are reintroduced.
- Web coverage is too low to call broad product behavior protected.

## Ranked Issue Register Summary

Scoring uses 0-5 impact for each dimension. The launch priority sort weights paid native iOS, App Store readiness, data-loss/crash risk, and user-visible performance above web expansion.

Top issues:

1. `AUD-001`: Real TestFlight purchase/restore and App Store Connect proof are still external launch gates.
2. `AUD-002`: Local iOS proof depends on ignored config bootstrapping.
3. `AUD-003`: Forced URL unwraps in network/photo/export managers need a crash-focused pass.
4. `AUD-004`: Runtime performance budgets are not yet proven by reliable trace evidence.
5. `AUD-005`: Supabase migration ownership is now root-only, with drift prevention still release-relevant.
6. `AUD-006`: Large singleton service files carry sync/auth/billing maintainability risk.
7. `AUD-007`: Web coverage is very low.
8. `AUD-008`: Debug/test web route inventory is currently empty; keep the guard to prevent regression.

See [issue-register.csv](issue-register.csv) for the full ranked list.

## Refactor Plan

### Phase 0 - Evidence And Guardrails

- Bootstrap iOS local config, run the standing local quality gate, and record artifacts.
- Refresh App Store/TestFlight/RevenueCat proof state from GitHub workflows and account-owner evidence.
- Keep audit-only checks for schema root drift, production debug-route gating, and crash-token inventory before changing behavior.

### Phase 1 - Crash And Launch Readiness

- Replace forced URL construction in network/export/photo paths with typed URL builders that return recoverable errors.
- Audit removed-sync `fatalError` sentinels and ensure no runtime path can call them.
- Add focused tests around OTP input, chart sampling, secondary metric optionals, and malformed URL/config states.
- Keep this phase split into small PRs: crash tokens, App Store proof docs, local bootstrap hardening.

### Phase 2 - Performance Proof

- Use the existing performance workflow to capture launch/HUD/timeline timings.
- If simulator trace remains unreliable, move frame/hitch proof to physical-device Instruments or ETTrace.
- Add enforceable summary budgets only after reliable trace capture exists.
- Prioritize photo decode/cache, Core Data fetch paths, and timeline scrub interactions.

### Phase 3 - Data And Sync Maintainability

- Declare one Supabase migration root as authoritative and add a drift check.
- Extract stable sync/auth/data ports where product/UI code currently has direct service coupling.
- Tighten tests around offline save, retry, conflict, delete/export, and Clerk JWT RLS mapping.

### Phase 4 - UI And Web Coverage

- Expand tests for production-adjacent web surfaces: support/legal/account deletion, App Store redirect, weights API, webhooks, and settings.
- Keep full web product work out of scope unless activation/subscriber triggers are met.
- Reduce large view files incrementally around natural seams: add-entry tabs, import steps, profile sections, dashboard timeline sections.

## Validation Commands For This Audit

Run from the repo root unless noted:

```bash
pnpm install --frozen-lockfile
pnpm lint
pnpm typecheck
pnpm test:ci
pnpm --filter logyourbody test:coverage
pnpm ios:bootstrap-local-config
xcodebuild -list -project apps/ios/LogYourBody.xcodeproj
RUN_LAUNCH_PERFORMANCE=false DESTINATION=auto pnpm ios:quality-gate
```

Optional focused iOS release evidence follows `apps/ios/docs/development/RELEASE_EVIDENCE_PATH.md`.

## Assumptions

- This audit prioritizes the paid native iOS App Store path.
- Web is inventoried fully, but expansion work remains below native MVP unless it affects support, legal, billing, or account management.
- Node 22 local warnings are documented; CI Node 20 remains authoritative.
- Implementation refactors require a separate approval after this dossier lands.
