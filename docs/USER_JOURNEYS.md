# User Journeys → Test Matrix

**October 16, 2026 reconciliation (LYB-179):** The v1 journey/test inventory below
is historical source context, not a current execution or release receipt.
LYB-173's automatic-first observation, one credible decision and progressive
onboarding still govern. October 28, 2026 makes the body through time the Home
default and keeps one contextual action. That supersedes all-at-once first-run
and a raw metadata home, not the body timeline itself. Existing tests and
owners remain. See the [reconciled roadmap](product-development-roadmap.md)
and [funnel evidence contract](marketing/funnel-evidence-contract.md). Neither a
render marker nor subscription transition proves coaching activation or cash.

Canonical map of every expected user journey and the test(s) that assert its user-visible outcome.
The paid core loop is defined in [GOLDEN_PATH.md](GOLDEN_PATH.md) and enforced by `LogYourBodyTests/GoldenPathTests` (hard CI gate via the iOS Launch Quality Gate).

**Status legend**

- ✅ compiled + gated — runs in CI and blocks merge
- ❌ missing — no test asserts the outcome

Status as of 2026-08-02. **All 113 `LogYourBodyTests` Swift files are registered in the target and the iOS Launch Quality Gate runs the whole `LogYourBodyTests` suite on every PR** (the earlier orphan gap is closed). The current passing count is reported by CI rather than duplicated here.

## iOS (the product — paid, iOS-first)

| #   | Journey                             | Expected user outcome                                                                                                                       | Asserting tests                                                                                                                                                                                                                                                                                                                                                  | Status |
| --- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| 1   | Launch → correct surface            | User lands on login / onboarding / paywall / main app based on auth+subscription state; never a dead end                                    | GoldenPathTests (GP1); LaunchSurfacePolicyTests; LaunchAndBodyCompositionTests                                                                                                                                                                                                                                                                                   | ✅     |
| 2   | Sign up / sign in (Apple)           | User authenticates and their session persists across launches                                                                               | GoldenPathTests (GP2); AuthManagerLocalUserStateTests; AuthSurfacePolicyTests; AuthConfigurationValidationTests; AuthLegacyStorageMigrationTests; AuthProfileBootstrapPolicyTests                                                                                                                                                                                | ✅     |
| 3   | Onboarding → profile complete       | New user completes body-score flow and arrives at first log with profile saved                                                              | GoldenPathTests (GP2 profile-completion); OnboardingFlowViewModelTests                                                                                                                                                                                                                                                                                           | ✅     |
| 4   | Subscribe (paywall, trial, restore) | User sees correct prices/savings, can purchase or restore, and entitlement unlocks the app                                                  | GoldenPathTests (GP3); PaywallSavingsPolicyTests; RevenueCatPurchaseRestoreFlowTests; RevenueCatFlowTests; RevenueCatProductConfigurationTests; RevenueCatSubscriptionAnalyticsTransitionTests; CachedPaywallOfferingDisplayTests                                                                                                                                | ✅     |
| 5   | Log weight                          | Entry validates, saves locally, and appears immediately                                                                                     | GoldenPathTests (GP4); PaidWeightLoggerMVPPolicyTests; LogWeightFormValidatorTests; BodyMetricLoggingServiceTests; BodyMetricLoggingAndInsightTests; EditEntrySavePolicyTests; ValidationServiceTests                                                                                                                                                            | ✅     |
| 6   | See it on the timeline              | Logged data appears on the dashboard/timeline scrubber at the right date                                                                    | GoldenPathTests (GP5); TimelineDataProviderScrubTests; DashboardTimelineProviderPerformanceTests; PhotoTimelineHUDPolicyTests; DashboardMetricFormattingTests; DashboardTimelineAndPolicyTests; GlobalTimelineServiceTests; MetricChartDataPointPresenceTests; DashboardDataVizPolicyTests                                                                       | ✅     |
| 7   | Data survives (offline → sync)      | Entries logged offline survive relaunch, persistent-store migration, and sync through the first-party Neon data plane without loss          | GoldenPathTests (GP6/GP7); CoreDataModelMigrationTests; SyncIntervalAndChunkingTests; SyncIntegrationBodyMetricSyncTests; SyncIntegrationRemotePayloadTests; SyncIntegrationImportAndMappingTests; SyncIntegrationSupplementalSyncTests; ProductAPIProfilePayloadTests; BodyMetricContractTests; BodyMetricLocalDateContractTests; BodyMetricSourceContractTests | ✅     |
| 8   | HealthKit import                    | Weight from the user's scale/Health app shows up without manual entry                                                                       | HealthSyncPipelineTests; HealthSyncCoordinatorPipelineTests; HealthKitAuthorizationPolicyTests; HealthKitFullSyncCompletionPolicyTests; DashboardViewModelHealthSyncWiringTests; LoadingManagerHealthSyncTests                                                                                                                                                   | ✅     |
| 9   | Add progress photo                  | Photo attaches to the right date and renders in the carousel/timeline. The person stays matted, framed and aligned without a reshaped body. | ProgressPhotoImagePipelineTests; PhotoMetadataAndImportPolicyTests; PhotoMetadataServiceTests; ProgressPhotoAttachPolicyTests; BulkProgressPhotoImportPolicyTests; PhotoUploadBatchPolicyTests; BodyMetricPhotoUpdateTests; BodyPhotoPresentationTests                                                                                                           | ✅     |
| 10  | Settings: goals, reminders, units   | Preferences persist and reminders fire per policy                                                                                           | PreferenceGoalValidatorTests; DailyReminderPolicyTests                                                                                                                                                                                                                                                                                                           | ✅     |
| 11  | Delete account / export data        | User data is fully cleaned up on deletion; export delivers their data                                                                       | AccountDeletionCleanupServiceTests; AccountDeletionAndShareCardTests                                                                                                                                                                                                                                                                                             | ✅     |
| 12  | GLP-1 dose logging                  | Doses log, format, and surface weekly check-ins correctly                                                                                   | Glp1CardAndCatalogTests; Glp1DoseCoreDataTests; Glp1DoseHistoryFormatterTests; Glp1WeeklyCheckInPolicyTests; PhaseInsightPolicyTests                                                                                                                                                                                                                             | ✅     |
| 13  | Body composition math               | BF%/FFMI numbers shown to the user are correct                                                                                              | BodyCompositionMathGoldenTests; BodyScoreShareCardTests                                                                                                                                                                                                                                                                                                          | ✅     |

UI smoke (launch, fixtures for signed-out/paywall/MVP surfaces): `LogYourBodyUITests` — ✅ selected cases run in the Launch Quality Gate.

## Web (secondary — marketing/support/account until expansion trigger per [product-development-roadmap.md](product-development-roadmap.md))

| Journey                 | Expected user outcome                            | Asserting tests                                              | Status              |
| ----------------------- | ------------------------------------------------ | ------------------------------------------------------------ | ------------------- |
| Sign in / auth callback | User authenticates with Apple through Jovie OIDC | `src/app/signin/__tests__/page.test.tsx`                     | ✅ (Jest, CI-gated) |
| Log weight              | Entry saves and renders                          | `weight-logging.test.tsx`                                    | ✅                  |
| Import DEXA/InBody PDF  | Parsed metrics land in the user's data           | `import.test.tsx`                                            | ✅                  |
| Sync/conflict handling  | No data loss across devices                      | conflict-resolver, sync-manager, realtime-sync-manager tests | ✅                  |
| Visual regression       | Pages render correctly across viewports          | Playwright `tests/e2e/visual-regression.spec.ts`             | ✅ (non-blocking)   |

## The one human step to revenue

Everything above is machine-gated. The single human action standing between the current state and App Store revenue: a real TestFlight paywall purchase/restore, then dispatching `ios-release-loop.yml` with `release_type=app_store`, the tested `build_number`, and an equal `paywall_verified_build_number`. Full sequence: [RELEASE_APP_STORE.md](RELEASE_APP_STORE.md). App Store version 1.2.0 currently sits in `PREPARE_FOR_SUBMISSION`; the approved-release poller automates everything after Apple approval.

## Rule

Same as GOLDEN_PATH.md: a journey listed here without a compiled, CI-gated test is a defect in this document or in the pbxproj — fix whichever is wrong. Every `LogYourBodyTests` file is registered in the target and the gate runs the whole suite, so a new test file is live the moment it's added — keep `Scripts/register-test-files.rb` as the sync check.

## Agent parity acceptance — October 13, 2026

Manual weight create, read, correct, and delete. The contract is
[the first implementation slice](integrations/chatgpt-app/README.md#first-implementation-slice-manual-weight-lifecycle).
This slice does not gate TestFlight.

The rows below identify source tests for the weight slice. They are not receipts
of current-head CI, provider authorization, device execution or persisted
cross-client completion. Broader parity is tracked in the
[canonical capability inventory](integrations/chatgpt-app/README.md#canonical-ios-capability-inventory).
Keep implementation evidence separate from prospective acceptance requirements.

| Check                   | Expected outcome                                                                                                                                                                                                                                                                                                                                      | Asserting tests                                                                                                   |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| HTTP and MCP lifecycle  | Create, read, correct the same id, delete, then read the tombstone. The receipt says the cloud write committed and does not claim an Apple Health change.                                                                                                                                                                                             | `apps/web/src/app/api/metrics/weight/__tests__/route.node.test.ts`                                                |
| Units and time          | Explicit kg and lb, midnight, both DST folds, yesterday, and a second same-day entry. Ambiguous or mismatched values are rejected.                                                                                                                                                                                                                    | `apps/web/src/lib/metrics/weight-lifecycle.test.ts`; `BodyMetricLoggingServiceTests`; `BodyMetricAppIntentsTests` |
| Retries and conflicts   | Lost acknowledgement and a concurrent identical retry replay one receipt. A changed payload, a stale correction, and a delete replay do not duplicate or resurrect. A delayed native push onto a tombstone conflicts.                                                                                                                                 | `weight-lifecycle.test.ts`; `native-body-metrics-sync-adapter.test.ts`                                            |
| Isolation and admission | Another subject, a guessed id, the wrong audience, an expired token, a training scope, a revoked or unconnected grant, and a closed gate do not write.                                                                                                                                                                                                | `route.node.test.ts`; `weight-lifecycle.test.ts`                                                                  |
| Native and Siri         | The authenticated app subject reuses `LogWeightIntent` and `BodyMetricLoggingService`. A retry keeps the operation id. A second log gets a new id. Correction and delete require an owned id and expected revision and are not creates. Denied HealthKit still saves locally. Cloud completion stays unclaimed. A conflicted row is not pushed again. | `BodyMetricAppIntentsTests`; `BodyMetricLoggingServiceTests`; `SyncIntegrationBodyMetricSyncTests`                |

## Agent parity completion evidence

Every new/materially extended feature supplies the
[roadmap specification contract](product-development-roadmap.md#feature-specification-and-completion-contract)
and updates the canonical inventory. The following are prospective acceptance
requirements, **pending real execution**, not additional passing journeys:

| Journey / boundary          | Required semantic outcome                                                                                                                                             | Evidence needed                                                                                                                                                                                                 |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Claude Code qualification   | Connect explicitly to LYB, grant only required scopes, complete an owned weight lifecycle, revoke access, then reconnect without duplicate writes                     | Real per-user OAuth and official MCP client/Inspector conformance plus Claude Code dogfood receipts; persisted readback and denial after revoke. Pending.                                                       |
| ChatGPT qualification       | The same supported lifecycle and permission outcomes in ChatGPT, with health-vault sharing consent kept distinct                                                      | Independent ChatGPT OAuth/tool transcript, receipt IDs and persisted readback; no inherited qualification from Claude Code or an SDK harness. Pending.                                                          |
| Jovie qualification         | The same supported lifecycle with an explicit LYB connection, even when the subject already has Jovie identity                                                        | Independent Jovie connection/consent, scopes, revoke/reconnect, transcript and persisted readback. Pending.                                                                                                     |
| Entry-point equivalence     | Native controls, weight/latest intents, HTTP and MCP preserve action, measurement identity, units/time/provenance, retries and revision conflicts                     | Named HTTP/MCP/native cases and device invocation/resume evidence; body-fat/correction/delete intents require their own passing contracts. Optional CLI only after a recorded gap. Pending beyond source tests. |
| Device/system/user handoffs | HealthKit, camera/library, microphone, notifications, biometrics and StoreKit return truthful offered/pending/denied/cancelled/unavailable/completed outcomes         | Actual device/provider effect and correlated readback; local saved, sync pending, cloud committed, conflict and device state remain distinct. A link, dialog or HTTP 200 alone cannot pass. Pending.            |
| Remaining capability gaps   | Goals/preferences, deterministic trends, photos/imports, daily/GLP-1 records, export/deletion and integration status have owned product actions or supported handoffs | Focused contracts from the inventory, actual failure-path/provider/native tests and current CI coverage. Generic table sync and training scopes cannot substitute for delegated product permissions. Pending.   |

Each implementation receipt records exact Git revision, client/version,
environment and timestamp, named journey/case, granted scopes and connection
state, operation/measurement/revision IDs, expected versus observed result,
persisted readback, native reconciliation/device effects, and links to real
HTTP/MCP/native/provider tests and CI/coverage results. Use synthetic data and
privacy-safe references; never commit tokens, customer health data or transcripts
containing it. Missing, skipped, stale, simulated or unavailable relevant evidence
stays unverified. A same-operation concurrent/lost-response retry, a new-operation
intentional repeat, a stale correction, tombstone resurrection, account switch
and another subject's guessed ID must be tested explicitly.

KPI: successful supported journeys through an authorized agent, zero duplicate
writes or cross-user disclosure, and truthful handoff outcomes. Report supported,
passed, failed and pending cases per client/action; an empty or partial evidence
set is not full parity. This planning contract does not gate the grandfathered
TestFlight beta or authorize client registration, account connection or release.
LYB-274 authorizes only a CI parity-inventory check after the current TestFlight
release ships. Feature slices stay unauthorized. The recorded slices live in
[agent-parity-slices.md](../packages/shared-lib/decisions/agent-parity-slices.md).
LYB-275 qualifies Claude Code first on a synthetic fixture account only, then
ChatGPT, then Jovie. Real consented accounts and client registrations are not
provided. The qualification slices live in
[client-qualification-order.md](../packages/shared-lib/decisions/client-qualification-order.md).
