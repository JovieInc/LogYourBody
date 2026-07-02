# User Journeys → Test Matrix

Canonical map of every expected user journey and the test(s) that assert its user-visible outcome.
The paid core loop is defined in [GOLDEN_PATH.md](GOLDEN_PATH.md) and enforced by `LogYourBodyTests/GoldenPathTests` (hard CI gate via the iOS Launch Quality Gate).

**Status legend**
- ✅ compiled + gated — runs in CI and blocks merge
- 🟠 orphaned — test file exists on disk but is NOT registered in the `LogYourBodyTests` target (pbxproj uses explicit file refs), so it never compiles or runs
- ❌ missing — no test asserts the outcome

Status as of 2026-07-02. The orphan rescue is tracked below; this table must be updated as files are registered.

## iOS (the product — paid, iOS-first)

| # | Journey | Expected user outcome | Asserting tests | Status |
|---|---------|----------------------|-----------------|--------|
| 1 | Launch → correct surface | User lands on login / onboarding / paywall / main app based on auth+subscription state; never a dead end | GoldenPathTests (GP1); LaunchSurfacePolicyTests; LaunchAndBodyCompositionTests | ✅ GP1; 🟠 rest |
| 2 | Sign up / sign in (email OTP + Apple) | User authenticates and their session persists across launches | GoldenPathTests (GP2); AuthManagerLocalUserStateTests; AuthSurfacePolicyTests; AuthConfigurationValidationTests; AuthLegacyStorageMigrationTests; AuthProfileBootstrapPolicyTests | ✅ GP2; 🟠 rest |
| 3 | Onboarding → profile complete | New user completes body-score flow and arrives at first log with profile saved | GoldenPathTests (GP2 profile-completion); OnboardingFlowViewModelTests | ✅ GP; 🟠 rest |
| 4 | Subscribe (paywall, trial, restore) | User sees correct prices/savings, can purchase or restore, and entitlement unlocks the app | GoldenPathTests (GP3); PaywallSavingsPolicyTests; RevenueCatPurchaseRestoreFlowTests; RevenueCatFlowTests; RevenueCatProductConfigurationTests; RevenueCatSubscriptionAnalyticsTransitionTests; CachedPaywallOfferingDisplayTests | ✅ GP3; 🟠 rest |
| 5 | Log weight | Entry validates, saves locally, and appears immediately | GoldenPathTests (GP4); PaidWeightLoggerMVPPolicyTests; LogWeightFormValidatorTests; BodyMetricLoggingServiceTests; BodyMetricLoggingAndInsightTests; EditEntrySavePolicyTests; ValidationServiceTests | ✅ GP4 + PaidWeightLoggerMVP; 🟠 rest |
| 6 | See it on the timeline | Logged data appears on the dashboard/timeline scrubber at the right date | GoldenPathTests (GP5); TimelineDataProviderScrubTests; DashboardTimelineProviderPerformanceTests; PhotoTimelineHUDPolicyTests; DashboardMetricFormattingTests; DashboardTimelineAndPolicyTests; GlobalTimelineServiceTests; MetricChartDataPointPresenceTests; DashboardDataVizPolicyTests | ✅ GP5 + 4 more; 🟠 rest |
| 7 | Data survives (offline → sync) | Entries logged offline survive relaunch and sync to Supabase without loss | GoldenPathTests (GP6/GP7); SyncIntervalAndChunkingTests; SyncIntegrationBodyMetricSyncTests; SyncIntegrationRemotePayloadTests; SyncIntegrationImportAndMappingTests; SyncIntegrationSupplementalSyncTests; SupabaseProfilePayloadTests; BodyMetricContractTests; BodyMetricLocalDateContractTests; BodyMetricSourceContractTests | ✅ GP6/7 + chunking; 🟠 rest |
| 8 | HealthKit import | Weight from the user's scale/Health app shows up without manual entry | HealthSyncPipelineTests; HealthSyncCoordinatorPipelineTests; HealthKitAuthorizationPolicyTests; HealthKitFullSyncCompletionPolicyTests; DashboardViewModelHealthSyncWiringTests; LoadingManagerHealthSyncTests | 🟠 all |
| 9 | Add progress photo | Photo attaches to the right date and renders in the carousel/timeline | ProgressPhotoImagePipelineTests; PhotoMetadataAndImportPolicyTests; PhotoMetadataServiceTests; ProgressPhotoAttachPolicyTests; BulkProgressPhotoImportPolicyTests; PhotoUploadBatchPolicyTests; BodyMetricPhotoUpdateTests; CoreDataAndPhotoPolicyTests | ✅ ImagePipeline; 🟠 rest |
| 10 | Settings: goals, reminders, units | Preferences persist and reminders fire per policy | PreferenceGoalValidatorTests; DailyReminderPolicyTests | 🟠 all |
| 11 | Delete account / export data | User data is fully cleaned up on deletion; export delivers their data | AccountDeletionCleanupServiceTests; AccountDeletionAndShareCardTests | 🟠 all |
| 12 | GLP-1 dose logging | Doses log, format, and surface weekly check-ins correctly | Glp1CardAndCatalogTests; Glp1DoseCoreDataTests; Glp1DoseHistoryFormatterTests; Glp1WeeklyCheckInPolicyTests; PhaseInsightPolicyTests | ✅ CardAndCatalog; 🟠 rest |
| 13 | Body composition math | BF%/FFMI numbers shown to the user are correct | BodyCompositionMathGoldenTests; BodyScoreShareCardTests | ✅ ShareCard; 🟠 math golden |

UI smoke (launch, fixtures for signed-out/paywall/MVP surfaces): `LogYourBodyUITests` — ✅ selected cases run in the Launch Quality Gate.

## Web (secondary — marketing/support/account until expansion trigger per [product-development-roadmap.md](product-development-roadmap.md))

| Journey | Expected user outcome | Asserting tests | Status |
|---------|----------------------|-----------------|--------|
| Sign in / auth callback | User authenticates via Clerk | `src/__tests__/auth-integration.test.tsx` | ✅ (Jest, CI-gated) |
| Log weight | Entry saves and renders | `weight-logging.test.tsx` | ✅ |
| Import DEXA/InBody PDF | Parsed metrics land in the user's data | `import.test.tsx` | ✅ |
| Sync/conflict handling | No data loss across devices | conflict-resolver, sync-manager, realtime-sync-manager tests | ✅ |
| Visual regression | Pages render correctly across viewports | Playwright `tests/e2e/visual-regression.spec.ts` | ✅ (non-blocking) |

## The one human step to revenue

Everything above is machine-gated. The single human action standing between the current state and App Store revenue: a real TestFlight paywall purchase/restore, then dispatching `ios-release-loop.yml` with `release_type=app_store` + `paywall_testflight_verified=true`. App Store version 1.2.0 currently sits in `PREPARE_FOR_SUBMISSION`; the approved-release poller automates everything after Apple approval.

## Rule

Same as GOLDEN_PATH.md: a journey listed here without a compiled, CI-gated test is a defect in this document or in the pbxproj — fix whichever is wrong. When registering an orphaned file flips a 🟠 to ✅, update this table in the same PR.
