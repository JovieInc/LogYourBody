# Full-App Inventory Execution Status

This file records what the implementation branch closed after the inventory was
created. It is not a replacement for `issue-register.csv`; it maps current work
to the register without changing the register schema.

## Closed Or Materially Reduced In This Branch

| Issue     | Status                                                      | Evidence                                                                                                                          |
| --------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `AUD-002` | Local proof bootstrap is documented and exercised           | `pnpm ios:bootstrap-local-config`; iOS quality gate artifacts under `apps/ios/test_results/quality-gate/20260622-211712`          |
| `AUD-003` | Forced Supabase/photo/export URL crashes removed            | `SupabaseURLBuilder`; `SupabaseURLBuilderTests`; `rg "URL\\(string:[^\\n]+\\)!" apps/ios/LogYourBody` has no release-path matches |
| `AUD-005` | Authoritative migration root declared and drift guard added | `pnpm check:supabase-migrations` passes; root `supabase/migrations` is the only mounted migration tree                            |
| `AUD-007` | Web readiness coverage improved                             | `pnpm --filter logyourbody test:coverage` passes with 34 suites / 300 tests and 7.10% line coverage                               |
| `AUD-008` | Debug/test route production gate is source-derived          | `middleware-production-gate.test.ts` verifies no debug/test routes are mounted and known debug/test patterns 404 before auth      |
| `AUD-009` | Removed-sync runtime traps removed from unavailable APIs    | `rg` finds no runtime call sites for removed sync APIs; bodies no longer call `fatalError`                                        |
| `AUD-010` | OTP/chart/metric force unwraps removed                      | Focused scan for `last!`, `weight!`, `bodyFatPercentage!`, `ffmi!`, and `leanMass!` is clean in targeted app code                 |
| `AUD-014` | Web sync conflict coverage added                            | `ConflictResolver` tests cover merge and conflict detection behavior                                                              |
| `AUD-016` | Web deletion readiness is tested honestly                   | API tests verify cleanup order and fail-closed behavior; page tests verify web page is iOS deletion plus support fallback         |
| `AUD-018` | Inventory dossier exists and now has execution status       | This file plus the machine-readable appendices                                                                                    |

## Guardrailed But Still Externally Blocked

| Issue     | Current state                                                                                                | Required next proof                                                                                       |
| --------- | ------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `AUD-001` | Release docs enforce `paywall_testflight_verified=false` until real TestFlight purchase/restore proof exists | Account-owner TestFlight purchase and restore evidence plus App Store Connect metadata/subscription state |
| `AUD-004` | Local static/performance-unit gates pass; frame/hitch claims remain blocked                                  | Reliable simulator metrics or physical-device Instruments/ETTrace artifact                                |
| `AUD-015` | Release docs now require explicit Sentry/Statsig config evidence                                             | Production secret state and smoke event/crash proof if enabled                                            |
| `AUD-017` | HealthKit permission proof remains App Review-sensitive                                                      | Current allow, deny, and skip evidence with production usage strings                                      |

## Remaining Follow-Up Work

| Issue     | Reason it remains follow-up                                                                                     |
| --------- | --------------------------------------------------------------------------------------------------------------- |
| `AUD-006` | Large-file and singleton maintainability debt needs incremental refactor PRs with narrower ownership boundaries |
| `AUD-011` | Vendor import boundary needs a full static import rule after the current adapter surface stabilizes             |
| `AUD-012` | GLP-1, DEXA/BodySpec, bulk import, and AI-adjacent surfaces remain product-scope decisions                      |
| `AUD-013` | Photo pipeline and timeline performance need runtime trace proof before optimization claims                     |

## Validation Run

- `pnpm install --frozen-lockfile`
- `pnpm lint`
- `pnpm typecheck`
- `pnpm test:ci`
- `pnpm --filter logyourbody test:coverage`
- `pnpm check:supabase-migrations`
- `swiftlint lint --strict` from `apps/ios`
- `xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:LogYourBodyTests/SupabaseURLBuilderTests CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO test`
- `pnpm ios:bootstrap-local-config`
- `xcodebuild -list -project apps/ios/LogYourBody.xcodeproj`
- `RUN_LAUNCH_PERFORMANCE=false DESTINATION=auto pnpm ios:quality-gate`

Known local warnings: Node `v22.22.1` while the repo expects Node `20.x`,
existing Next lint deprecation warnings, existing Swift 6 actor-isolation
warnings, and simulator-only HealthKit entitlement warnings from local fixture
config.
