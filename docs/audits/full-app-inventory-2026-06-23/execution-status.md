# Full-App Inventory Execution Status

This file records what the implementation branch closed after the inventory was
created. It is not a replacement for `issue-register.csv`; it maps current work
to the register without changing the register schema.

## Closed Or Materially Reduced In This Branch

| Issue     | Status                                                                          | Evidence                                                                                                                                                                                                |
| --------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AUD-002` | Local proof bootstrap is documented and exercised                               | `pnpm ios:bootstrap-local-config`; quality gate rerun under `/tmp/lyb-quality-gate-nonempty-proof` executed 19 unit, 1 UI, and 1 performance test                                                       |
| `AUD-003` | Forced Supabase/photo/export URL crashes removed                                | `SupabaseURLBuilder`; `SupabaseURLBuilderTests`; `rg "URL\\(string:[^\\n]+\\)!" apps/ios/LogYourBody` has no release-path matches                                                                       |
| `AUD-005` | Authoritative migration root declared and drift guard added                     | `pnpm check:supabase-migrations` passes; root `supabase/migrations` is the only mounted migration tree                                                                                                  |
| `AUD-007` | Web readiness coverage improved                                                 | `pnpm --filter logyourbody test:coverage` passes with 39 suites / 323 tests and 11.06% line coverage                                                                                                    |
| `AUD-008` | Debug/test route production gate is source-derived                              | `middleware-production-gate.test.ts` verifies no debug/test routes are mounted and known debug/test patterns 404 before auth                                                                            |
| `AUD-009` | Removed-sync runtime traps removed from unavailable APIs                        | `rg` finds no runtime call sites for removed sync APIs; bodies no longer call `fatalError`                                                                                                              |
| `AUD-010` | OTP/chart/metric force unwraps removed                                          | Focused scan for `last!`, `weight!`, `bodyFatPercentage!`, `ffmi!`, and `leanMass!` is clean in targeted app code                                                                                       |
| `AUD-011` | Vendor SDK boundary has a static guard                                          | `pnpm check:vendor-boundaries` passes and `vendor-boundary-guard.test.ts` runs the guard under shared-lib tests                                                                                         |
| `AUD-012` | Advanced web import APIs are now protected by Clerk middleware                  | `middleware-production-gate.test.ts` verifies `/api/parse-pdf`, `/api/parse-pdf-alt`, and `/api/parse-pdf-v2` invoke Clerk auth before route handlers                                                   |
| `AUD-013` | Timeline and photo/cache unit performance proof no longer passes empty          | `pnpm ios:performance-audit` now targets Xcode-membered timeline, dashboard timeline provider, progress-photo pipeline, and image-cache tests; launch-quality shards also fail empty XCTest bundles     |
| `AUD-014` | Web sync conflict and queue coverage added; queued mutation failure is retained | `ConflictResolver` tests cover merge behavior; `sync-manager.test.ts` covers upload/error/offline cleanup; `realtime-sync-manager.test.ts` verifies failed queued writes stay queued and surface errors |
| `AUD-016` | Web deletion readiness is tested honestly                                       | API tests verify cleanup order and fail-closed behavior; page tests verify web page is iOS deletion plus support fallback                                                                               |
| `AUD-017` | HealthKit App Review source guard added                                         | `healthkit-app-review-proof-guard.test.ts` checks production usage strings, entitlements, Xcode wiring, and release-doc requirements for allow/deny/skip proof                                          |
| `AUD-018` | Inventory dossier exists and now has execution status plus a refresh checklist  | This file, the machine-readable appendices, and the lightweight refresh checklist below                                                                                                                 |

## Latest Landed Release Evidence

| Evidence                | Current state                                                                                                                                                             |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Merged PR               | `#443` merged to `main` at `450d568efd0f0a1a96dcb7adbca283bcfe06d571` on `2026-06-23T08:18:12Z`                                                                           |
| Post-merge CI           | GitHub run `28012399897` completed successfully                                                                                                                           |
| Web deploy              | GitHub Deploy run `28012400613` completed successfully                                                                                                                    |
| iOS release loop        | GitHub run `28012401595` completed successfully                                                                                                                           |
| TestFlight upload       | `Deploy to TestFlight / Deploy to TestFlight (production)` completed successfully in run `28012401595`                                                                    |
| GitHub release artifact | Prerelease `ios-v1.2.0-testflight.20260623082957` published at `2026-06-23T08:43:31Z`                                                                                     |
| App Store direct deploy | `Deploy to App Store` was skipped by workflow policy; App Store submission still requires real TestFlight purchase/restore evidence first                                 |
| App Store listing       | Public URL `https://apps.apple.com/us/app/logyourbody/id6755209876` returned HTTP `404` at Tue, 23 Jun 2026 08:43:58 GMT; this does not prove public listing availability |

## Guardrailed But Still Externally Blocked

| Issue     | Current state                                                                                                                                                                           | Required next proof                                                                    |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `AUD-001` | TestFlight upload now has workflow proof, but release docs still enforce `paywall_testflight_verified=false` until real purchase/restore proof exists                                   | Account-owner TestFlight purchase and restore evidence plus App Store submission state |
| `AUD-004` | Local launch-quality and performance-unit gates now require non-empty XCTest evidence; post-merge CI run `28012399897` is the latest landed CI proof; frame/hitch claims remain blocked | Reliable simulator metrics or physical-device Instruments/ETTrace artifact             |
| `AUD-015` | Release config now emits redacted Sentry/Statsig configured booleans; provider smoke proof remains external                                                                             | Production release summary plus smoke event/crash proof if enabled                     |
| `AUD-017` | Source-level HealthKit readiness is guarded; interactive permission proof remains App Review-sensitive                                                                                  | Current allow, deny, and skip evidence with production usage strings                   |

## Lightweight Inventory Refresh Checklist

Use this checklist before any release audit or after route, screen, release-flow,
or launch-surface changes:

- Recompare `README.md` counts with source for Swift app files, iOS test files,
  web pages, API route handlers, and Jest suites.
- Refresh `route-inventory.json` and `ios-screen-inventory.json` from source
  when routes, tabs, paywall/auth/onboarding, settings, or photo-HUD screens
  change.
- Update this file's latest landed release evidence from GitHub `main` runs:
  merged PR and SHA, CI, Deploy, iOS Release Loop, TestFlight job, prerelease
  tag, and App Store direct-deploy policy result.
- Recheck the public App Store URL and record only the observed HTTP result and
  timestamp. Do not claim public listing availability from a release-loop
  success alone.
- Keep `AUD-001`, `AUD-004`, `AUD-015`, and `AUD-017` external-proof gaps
  explicit until purchase/restore, runtime trace, provider smoke, and
  HealthKit permission evidence exist.

## Remaining Follow-Up Work

| Issue     | Reason it remains follow-up                                                                                                                               |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `AUD-006` | Large-file and singleton maintainability debt needs incremental refactor PRs with narrower ownership boundaries                                           |
| `AUD-012` | iOS GLP-1, DEXA/BodySpec, bulk import, and AI-adjacent surfaces remain product-scope decisions after the web parse-PDF API auth guard                     |
| `AUD-013` | Photo pipeline/cache and timeline now have target-membered unit proof; frame/hitch performance still needs runtime trace proof before optimization claims |

## Validation Run

- `pnpm install --frozen-lockfile`
- `pnpm lint`
- `pnpm typecheck`
- `pnpm test:ci`
- `pnpm --filter logyourbody test:coverage`
- `pnpm check:supabase-migrations`
- `pnpm check:vendor-boundaries`
- `pnpm --filter @logyourbody/shared-lib test`
- `pnpm --filter logyourbody test -- src/lib/sync/__tests__/sync-manager.test.ts src/lib/sync/__tests__/realtime-sync-manager.test.ts --runInBand`
- `pnpm --filter logyourbody test -- middleware-production-gate.test.ts`
- `pnpm --filter logyourbody test src/lib/db/__tests__/indexed-db.test.ts --runInBand`
- `pnpm --filter logyourbody test --config jest.config.node.js src/app/api/app-store-redirect/__tests__/route.node.test.ts src/app/api/weights/__tests__/route.node.test.ts --runInBand`
- `RUN_SWIFTLINT=false RUN_LAUNCH_PERFORMANCE=false RUN_TIMELINE_TRACE_WORKFLOW=false DESTINATION=auto ARTIFACT_DIR=/tmp/lyb-aud-013-photo-cache pnpm ios:performance-audit`
- `xcodebuild -project apps/ios/LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LogYourBodyTests/ImageCacheServiceTests -only-testing:LogYourBodyTests/ProgressPhotoImagePipelineTests -only-testing:LogYourBodyTests/DashboardTimelineProviderPerformanceTests -only-testing:LogYourBodyTests/SyncIntervalAndChunkingTests CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO test`
- `swiftlint lint --strict` from `apps/ios`
- `xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LogYourBodyTests/SupabaseURLBuilderTests CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO test`
- `pnpm ios:bootstrap-local-config`
- `xcodebuild -list -project apps/ios/LogYourBody.xcodeproj`
- `ARTIFACT_ROOT=/tmp/lyb-quality-gate-nonempty-proof RUN_LAUNCH_PERFORMANCE=false DESTINATION=auto pnpm ios:quality-gate`

Known local warnings: Node `v22.22.1` while the repo expects Node `20.x`,
existing Next lint deprecation warnings, existing Swift 6 actor-isolation
warnings, and simulator-only HealthKit entitlement warnings from local fixture
config.
