# iOS Feature Inventory & Test-Coverage Map

> **Purpose:** Source of truth for the test-hardening effort. Every user-facing
> feature and critical logic surface of the LogYourBody iOS app, its risk
> rating, the smallest test layer that proves it, and its current coverage.
> Update the status columns as batches land.

## Standards (from Jovie company docs via gbrain)

- `sources/jovie-product/docs/testing_guidelines` — risk-based effort;
  smallest test that proves the behavior; fixtures over mocks; mock contracts,
  not internals; unit/integration fast; E2E reserved for golden paths; failing
  test before fix for regressions; skipped tests need a TODO + owner.
- `sources/jovie-product/docs/test_risk_register` — per-surface
  `target_coverage` driven by blast radius / reversibility / visibility.
- `docs/testing/TEST_COVERAGE_ANALYSIS.md` (Jovie repo) — **70%+ overall line
  coverage; 80%+ patch coverage on new/modified lines.**

### Quality bar for every test added here

1. Behavior assertions on observable outcomes — no implementation wiring checks.
2. Mocks/stubs only at external boundaries: Supabase/HTTP, Clerk REST,
   HealthKit, RevenueCat, Photos/Camera, UserNotifications, Sentry, Statsig.
3. Deterministic: fixed clocks, seeded data, temp-dir Core Data stores.
4. Independent: no global state, no cross-test coupling.
5. Fast: unit tests target <200ms each (measured, report-only); integration
   may be slower; XCUITest only for golden paths.
6. No coverage-padding tests. If a surface is dead code, propose deletion
   instead of tests.

## Coverage baseline

- **Baseline run:** `test_results/baseline-unit.xcresult` (unit target only,
  iPhone 17 simulator, `-enableCodeCoverage YES`, 2026-07-19).
- **Overall line coverage (app target `LogYourBody.app`): 14.36%**
  (13,243 / 92,243 executable lines) — unit suite only; a combined
  unit+UI run would read higher. This is the honest starting point against
  the 70% floor; dead-code removal (section C) shrinks the denominator.
- **Suite:** 360 test cases, **all passing**, ~93s total test time.
- **Duration report (report-only, unit target <200ms):** 5 tests exceed
  200ms — `testPersistentStoreRetryRemainsFailedWhenReloadFailsAgain`
  (2.0s), `testPersistentStoreRetryRecoversAfterInitialLoadFailure` (2.0s),
  `testRefreshSkipsHealthKitSyncWhenDeniedAndKeepsLocalMetrics` (1.0s),
  `testPersistentStoreFailureDoesNotCreateWritableInMemoryFallback` (1.0s),
  `testRenderSignatureConstructionPerformance` (0.5s, intentional
  `measure {}`). The 2.0s/1.0s store-retry tests use real waits — move to
  the integration tier or inject clocks during tiering (batch 2).
- Floors for this effort: **≥70% overall**, **≥80% patch on touched lines**.

## Test-infrastructure findings (fix early — they gate everything else)

| #   | Finding                                                                                                                                 | Evidence                                            | Fix                                                                                                             |
| --- | --------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| I1  | No CI job runs the unit suite as a merge gate; `ci_ios` lane is lint+build only. Tests execute only inside `ios_quality` audit scripts. | `fastlane/Fastfile:597`, `.github/workflows/ci.yml` | Extend the `ios` CI job (name stays stable) to run `LogYourBodyTests` via `run_tests`.                          |
| I2  | 7 test files under `LogYourBodyTests/DesignSystem/` are **not in the pbxproj** — they never compile or run.                             | pbxproj has no references                           | Add to target if meaningful; delete if padding.                                                                 |
| I3  | Duplicate `MockHealthSyncCoordinator` in `HealthSyncTestDoubles.swift` and `Mocks/MockHealthSyncCoordinator.swift`.                     | both on disk                                        | Keep one canonical double; delete the other.                                                                    |
| I4  | `ui_snapshot` lane targets a `SnapshotTests` class that does not exist.                                                                 | `Fastfile:362`                                      | Remove or repoint the lane.                                                                                     |
| I5  | `golden_path` lane exists but no workflow calls it.                                                                                     | `Fastfile:603`                                      | GoldenPathTests is Unit-tier (pure logic), so the CI unit gate covers it on every PR; lane kept for local runs. |
| I6  | No `.xctestplan`; scheme uses `shouldAutocreateTestPlan`. No formal tiering.                                                            | `LogYourBody.xcscheme`                              | Add test plans: `Unit`, `Integration`, `UITests`.                                                               |
| I7  | Coverage collected by fastlane but nothing reports/enforces it; AGENTS.md claims a 70% floor.                                           | no xccov parsing anywhere                           | Produce a coverage + duration report per run (report-only).                                                     |
| I8  | Eight 14-line one-assertion test files each carry the full import preamble.                                                             | `LogYourBodyTests/`                                 | Consolidate during tiering.                                                                                     |
| I9  | No `NSInMemoryStoreType` anywhere; Core Data tests use temp-dir SQLite (slower but realistic).                                          | `CoreDataModelMigrationTests`                       | Keep pattern (matches "realistic fixtures"); note in tier doc.                                                  |

Tier definitions adopted here: **Unit** = pure logic/policies/math, no I/O,
<200ms each. **Integration** = in-process Core Data (temp-dir SQLite), sync,
HealthKit coordination, stubbed external boundaries. **XCUITest** = fixture-
driven golden paths only (launch args `-lybUITest*Fixture`).

---

## A. User-facing surfaces (72 total; 27 with any test linkage)

Legend — Risk: **H**igh (data loss / auth / money / health data / launch
blocking), **M**edium, **L**ow. Layer: smallest layer that proves the surface.
Status: ✅ adequate · 🔶 partial/indirect only · ❌ none · 🗑 dead-code
candidate (propose deletion, not tests).

### A.1 Root routing & launch

| Surface                                                    | File                      | Risk | Layer                      | Status / existing                                                                |
| ---------------------------------------------------------- | ------------------------- | ---- | -------------------------- | -------------------------------------------------------------------------------- |
| `LogYourBodyApp` (entry, deep links, store recovery)       | `LogYourBodyApp.swift`    | H    | unit (policies) + XCUITest | 🔶 `LaunchSurfacePolicyTests`, deep-link policy covered; store recovery untested |
| `ContentView` (root router: login→onboarding→paywall→main) | `ContentView.swift`       | H    | unit (policies) + XCUITest | 🔶 `LaunchSurfacePolicyTests`, `AuthSurfacePolicyTests`, `GoldenPathTests`       |
| `MainTabView` (paid-surface switcher)                      | `Views/MainTabView.swift` | H    | XCUITest                   | 🔶 `GoldenPathTests` GP1, UI routing tests                                       |

### A.2 Dashboard (primary paid surface)

| Surface                                                         | File                                               | Risk | Layer           | Status / existing                                                               |
| --------------------------------------------------------------- | -------------------------------------------------- | ---- | --------------- | ------------------------------------------------------------------------------- |
| `DashboardViewLiquid` (photoTimelineHUD)                        | `Views/DashboardViewLiquid.swift`                  | H    | unit + XCUITest | 🔶 HUD policy + timeline + formatting tests, UI fixture tests                   |
| `DashboardViewLiquid` (legacyTabbed) + home/photos/metrics tabs | `Views/DashboardViewLiquid*.swift`                 | M    | XCUITest        | 🔶 legacy UI fixture test                                                       |
| Stats page (`photoTimelineAnalyticsPage`)                       | `DashboardViewLiquid+PhotoTimelineAnalytics.swift` | M    | XCUITest        | 🔶 UI fixture tests                                                             |
| `FullMetricChartView`                                           | `Components/FullMetricChartView.swift`             | M    | unit + XCUITest | 🔶 `MetricChartDataPointPresenceTests`, UI tests                                |
| `PaidWeightLoggerMVPView`                                       | `Views/MainTabView.swift`                          | H    | unit + XCUITest | 🔶 `PaidWeightLoggerMVPPolicyTests`, `LogWeightFormValidatorTests`, UI fixtures |
| `DashboardSyncDetailsSheet`                                     | `Components/DashboardSyncComponents.swift`         | M    | unit            | ❌                                                                              |
| `BackgroundTaskDetailsSheet`                                    | `Components/BackgroundTaskDetailsSheet.swift`      | L    | unit            | ❌ (also duplicated in Models/)                                                 |
| `BodyScoreShareSheet`                                           | `Components/BodyScoreShareCard.swift`              | M    | unit + XCUITest | 🔶 `BodyScoreShareCardTests`, UI fixtures                                       |
| `PhotoOptionsSheet`                                             | `Components/DashboardMetricCards.swift`            | L    | —               | 🗑 no caller found                                                              |
| `DietPhaseHistoryView`                                          | `Views/DietPhaseHistoryView.swift`                 | L    | —               | 🗑 orphaned                                                                     |

### A.3 Photo timeline & progress photos

| Surface                     | File                                    | Risk | Layer             | Status / existing                                                              |
| --------------------------- | --------------------------------------- | ---- | ----------------- | ------------------------------------------------------------------------------ |
| `ProgressPhotoCarouselView` | `Views/ProgressPhotoCarouselView.swift` | M    | unit              | ✅ `ProgressPhotoCarouselPreloadRangeTests`, `ProgressPhotoImagePipelineTests` |
| `ProgressPhotoAttachSheet`  | `Views/ProgressPhotoAttachSheet.swift`  | M    | unit + XCUITest   | 🔶 `ProgressPhotoAttachPolicyTests`                                            |
| `CameraView`                | `Views/CameraView.swift`                | L    | XCUITest (manual) | ❌                                                                             |

### A.4 Onboarding (BodyScore flow, 19 surfaces — coverage rests on ViewModel tests)

| Surface                                                                                                                                                                                  | File                                                                  | Risk           | Layer                                             | Status / existing                                                                                                                                                                                                                   |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | -------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BodyScoreOnboardingFlowView` (17-step router)                                                                                                                                           | `Features/Onboarding/Views/BodyScoreOnboardingFlowView.swift`         | H              | unit (VM) + XCUITest                              | 🔶 `OnboardingFlowViewModelTests`, UI CTA tests                                                                                                                                                                                     |
| 16 step views (hook, basics, height, health connect/confirm, manual weight, BF choice/numeric/visual, loading, reveal, home-mode, email, account creation, profile details, first photo) | `Features/Onboarding/Views/BodyScore*.swift`                          | H (activation) | unit (step policies in VM) + XCUITest golden path | 🔶 `OnboardingStepEntryPolicyTests`, `OnboardingScoreDisplayPolicyTests`, `OnboardingFlowValidationTests` + indirect via `OnboardingFlowViewModelTests`; reveal math via `BodyScoreEngineTests`; XCUITest golden path still missing |
| `ProfileCompletionGateView`                                                                                                                                                              | `Features/Onboarding/Views/ProfileCompletionGateView.swift`           | H              | unit                                              | 🔶 `LaunchSurfacePolicyTests`, VM tests                                                                                                                                                                                             |
| `PreAuthBodyScoreOnboardingContainer`                                                                                                                                                    | `Features/Onboarding/Views/PreAuthBodyScoreOnboardingContainer.swift` | L              | —                                                 | 🗑 orphaned                                                                                                                                                                                                                         |

### A.5 Auth (LYB iOS auth — Sign in with Apple via Clerk REST)

| Surface                                | File                            | Risk | Layer           | Status / existing                                       |
| -------------------------------------- | ------------------------------- | ---- | --------------- | ------------------------------------------------------- |
| `LoginView`                            | `Views/LoginView.swift`         | H    | unit + XCUITest | 🔶 `AuthSurfacePolicyTests`, UI signed-out fixture, GP2 |
| `BiometricLockView`                    | `Views/BiometricLockView.swift` | H    | unit (policy)   | ❌                                                      |
| `SignUpView`                           | `Views/SignUpView.swift`        | —    | —               | 🗑 orphaned                                             |
| `OTPInputView`, `EnhancedOTPInputView` | `Views/`                        | —    | —               | 🗑 orphaned                                             |
| `FaceIDEnableView.swift`               | `Views/`                        | —    | —               | 🗑 not in build target                                  |

### A.6 Paywall / subscription

| Surface       | File                      | Risk | Layer                                          | Status / existing                                                                 |
| ------------- | ------------------------- | ---- | ---------------------------------------------- | --------------------------------------------------------------------------------- |
| `PaywallView` | `Views/PaywallView.swift` | H    | unit + integration (mock RC client) + XCUITest | 🔶 6 RevenueCat test files + UI fixtures + GP3 — strongest area, verify gaps only |

### A.7 Settings / preferences

| Surface                                                                       | File                                | Risk | Layer           | Status / existing                                       |
| ----------------------------------------------------------------------------- | ----------------------------------- | ---- | --------------- | ------------------------------------------------------- |
| `PreferencesView` (hub)                                                       | `Views/PreferencesView.swift`       | M    | unit + XCUITest | 🔶 UI settings fixtures, `DailyReminderPolicyTests`     |
| `ProfileSettingsViewV2` (+2 picker sheets)                                    | `Views/ProfileSettingsViewV2.swift` | M    | unit            | ❌                                                      |
| `PreferenceGoalEditorSheet`                                                   | `Views/PreferenceGoalEditing.swift` | M    | unit            | 🔶 `PreferenceGoalValidatorTests`, UI goal-editor tests |
| `SecuritySessionsView`                                                        | `Views/SecuritySessionsView.swift`  | M    | unit            | ❌                                                      |
| `DeleteAccountView`                                                           | `Views/DeleteAccountView.swift`     | H    | integration     | 🔶 `AccountDeletionCleanupServiceTests` (service-level) |
| `LegalView`, `WhatsNewView`, `SyncStatusView`/`SyncDetailsView`, `VersionRow` | `Views/`                            | —    | —               | 🗑 all orphaned                                         |

### A.8 HealthKit / integrations

| Surface                   | File                                  | Risk | Layer                      | Status / existing                                                  |
| ------------------------- | ------------------------------------- | ---- | -------------------------- | ------------------------------------------------------------------ |
| `IntegrationsView`        | `Views/IntegrationsView.swift`        | M    | unit + XCUITest            | 🔶 HealthKit policy/pipeline tests, UI bulk-import fixtures        |
| `BodySpecIntegrationView` | `Views/BodySpecIntegrationView.swift` | M    | integration (stubbed HTTP) | ❌ view; importer covered (`SyncIntegrationImportAndMappingTests`) |
| `HealthKitPromptView`     | `Views/HealthKitPromptView.swift`     | —    | —                          | 🗑 orphaned                                                        |

### A.9 Data export / import

| Surface               | File                              | Risk | Layer              | Status / existing                                            |
| --------------------- | --------------------------------- | ---- | ------------------ | ------------------------------------------------------------ |
| `ExportDataView`      | `Views/ExportDataView.swift`      | M    | unit (CSV builder) | ❌                                                           |
| `BulkPhotoImportView` | `Views/BulkPhotoImportView.swift` | M    | unit + XCUITest    | 🔶 `BulkImportManagerBoundsTests`, policy tests, UI fixtures |

### A.10 Legal / consent

| Surface                                   | File                               | Risk | Layer           | Status / existing |
| ----------------------------------------- | ---------------------------------- | ---- | --------------- | ----------------- |
| `LegalConsentView` (non-dismissible gate) | `Views/LegalConsentView.swift`     | H    | unit + XCUITest | ❌                |
| `LegalDocumentView`                       | `Views/LegalDocumentView.swift`    | M    | unit            | ❌                |
| `HealthDisclaimerView`                    | `Views/HealthDisclaimerView.swift` | —    | —               | 🗑 orphaned       |

### A.11 Reminders / notifications

| Surface                          | File                                         | Risk | Layer | Status / existing             |
| -------------------------------- | -------------------------------------------- | ---- | ----- | ----------------------------- |
| `DailyWeighInReminderPromptView` | `Views/DailyWeighInReminderPromptView.swift` | M    | unit  | 🔶 `DailyReminderPolicyTests` |

### A.12 App Intents (Siri/Shortcuts)

| Surface                                                          | File                                  | Risk | Layer       | Status / existing             |
| ---------------------------------------------------------------- | ------------------------------------- | ---- | ----------- | ----------------------------- |
| `LogWeightIntent`, `LogBodyFatIntent`, `ShowLatestMetricsIntent` | `Services/BodyMetricAppIntents.swift` | M    | integration | ❌                            |
| Widgets                                                          | —                                     | —    | —           | n/a — no widget target exists |

### A.13 Other surfaces

| Surface                                            | File                                         | Risk | Layer                         | Status / existing                                                   |
| -------------------------------------------------- | -------------------------------------------- | ---- | ----------------------------- | ------------------------------------------------------------------- |
| `AddEntrySheet` (Weight/BodyFat/Photos/GLP-1 tabs) | `Views/AddEntrySheet*.swift`                 | H    | unit + integration + XCUITest | 🔶 validators, GLP-1 policy, photo-batch policy, UI dose-flow tests |
| `Glp1AddMedicationView`                            | `Views/AddEntrySheet.swift`                  | M    | unit                          | 🔶 `Glp1CardAndCatalogTests`, UI fixture                            |
| `EditEntrySheet`                                   | `Views/EditEntrySheet.swift`                 | —    | —                             | 🗑 orphaned (GLP-1 dose editing lives in AddEntrySheet)             |
| `BugReportPromptSheet`/`BugReportFormView`         | `Views/BugReportViews.swift`                 | L    | unit                          | ❌                                                                  |
| `LoadingView`                                      | `Views/LoadingView.swift`                    | L    | unit                          | 🔶 manager-level only                                               |
| `ImageProcessingStatusView`                        | `Components/ImageProcessingStatusView.swift` | —    | —                             | 🗑 orphaned                                                         |

---

## B. Business-logic inventory (110 files; 54 full, 9 partial, 47 untested)

Fully/partially covered areas (verify only): Supabase manager + payload
contracts, RevenueCat manager, RealtimeSyncManager + sync integration,
CoreDataManager (+migration tests), HealthKitManager + coordinator,
BodyScore engine/cache/recalc, OnboardingFlowViewModel, DashboardViewModel,
TimelineDataProvider, interpolation + caches, image cache, bulk import
manager, validation/logging services, launch/auth surface policies.

### B.1 High-risk untested/partial (priority queue)

| File                                                        | Responsibility                                           | Boundaries                             | Layer                             |
| ----------------------------------------------------------- | -------------------------------------------------------- | -------------------------------------- | --------------------------------- |
| `Services/KeychainManager.swift`                            | Auth-token keychain storage                              | Keychain                               | unit (keychain-backed, sandboxed) |
| `Services/PhotoUploadManager.swift`                         | Progress-photo upload to Supabase Storage                | Supabase, Photos                       | integration (stubbed HTTP)        |
| `Services/BackgroundPhotoUploadService.swift` (+Processing) | Background photo pipeline                                | Supabase, Core Data, Photos            | integration                       |
| `Services/ExternalServicePorts.swift`                       | Vendor ports/adapters (biometrics, photos, camera)       | LocalAuthentication, Photos            | unit (fake adapters)              |
| `Services/AppVersionManager.swift`                          | Upgrade migrations, defaults seeding (data-loss risk)    | Core Data, UserDefaults                | integration                       |
| `Services/AuthManager.swift` gaps                           | Session/token lifecycle beyond current local-state tests | Clerk REST, Keychain                   | integration (stubbed HTTP)        |
| `Services/NotificationManager.swift`                        | Reminder scheduling (policy covered; scheduler not)      | UserNotifications                      | unit (fake scheduling client)     |
| `ViewModels/GlobalTimelineStore.swift`                      | Paged timeline state store                               | none                                   | unit                              |
| `Services/BodySpecAPI.swift`, `BodySpecAuthManager.swift`   | BodySpec REST + OAuth                                    | URLSession, ASWebAuthenticationSession | integration (stubbed HTTP)        |
| `Services/BodyMetricAppIntents.swift`                       | Siri intents logging path                                | AppIntents → Core Data                 | integration                       |

### B.2 Medium-risk untested

| File                                                                                                                                                | Responsibility                                | Layer                   |
| --------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ----------------------- |
| `Services/AnalyticsService.swift`                                                                                                                   | Statsig event adapter                         | unit (fake client)      |
| `Services/ErrorTrackingService.swift`, `Utils/ErrorReporter.swift`                                                                                  | Sentry wrappers                               | unit (fake client)      |
| `Services/BugReportManager.swift`                                                                                                                   | Shake-to-report capture/submit                | unit                    |
| `Services/DeviceNormalizationService.swift` + `Models/HKRawSample.swift`                                                                            | Device confidence inference                   | unit                    |
| `Services/ImageProcessingService.swift`, `BackgroundRemovalService.swift`, `VisionOrientationService.swift`, `PhotoLibraryScanner.swift`            | Vision/photo pipeline                         | unit (synthetic images) |
| `Services/BodyMetricSpotlightIndexer.swift`                                                                                                         | Spotlight indexing (document mapping covered) | unit                    |
| `Helpers/TimelineCalculator.swift`, `LRUCache.swift`, `TimelinePhotoSampler.swift`, `MetricChartDataHelper.swift`, `TimelineBucketCalculator.swift` | Timeline/chart helpers                        | unit                    |
| `Models/GlobalTimelineModels.swift` (bucket/cursor/scale)                                                                                           | Timeline models                               | unit                    |
| `Utils/AppVersion.swift`, `Utils/AppError.swift`                                                                                                    | Semver + error taxonomy                       | unit                    |
| `Utils/ShakeDetector.swift` (incl. `DebugResetManager` — data-loss risk)                                                                            | Shake/screenshot/debug reset                  | unit                    |
| `Models/Changelog.swift`                                                                                                                            | What's-new tracking                           | unit                    |
| `Models/TimelineMode.swift`                                                                                                                         | Timeline mode + formatter cache               | unit                    |

### B.3 Low-risk untested (sweep last)

`Utils/AppLogger.swift`, `Utils/FrameHitchMonitor.swift`,
`Utils/PerfSignpost.swift`, `Utils/VersionInfo.swift`,
`Utilities/HapticManager.swift`, `Models/DailyLog.swift`,
`Models/BodyCompMeasurement.swift`, `Models/BodyCompMethod.swift`,
`Models/DashboardMetric.swift`, `Models/BackgroundTaskType.swift`,
`Models/BackgroundTaskMonitor.swift` (duplicate of Services type?),
`Services/BackgroundTaskMonitor.swift`, `GeneratedProductRegistry.swift`
(generated — exclude from coverage target).

### B.4 Misplaced/duplicate files (propose moves/deletes in follow-ups)

`Models/DashboardTaskBanner.swift`, `Models/AnimatedTaskIcon.swift`,
`Models/BackgroundTaskDetailsSheet.swift` (SwiftUI views in Models/;
details sheet duplicated in Components/), possible duplicate
`BackgroundTaskMonitor` in Models vs Services.

---

## C. Dead/orphaned code candidates (delete rather than test — separate PRs)

**Removed in this PR** (verified zero callers; deleted from disk and pbxproj):
`SignUpView`, `OTPInputView`, `EnhancedOTPInputView`, `LegalView`,
`HealthKitPromptView`, `HealthDisclaimerView`, `SyncStatusView` (incl.
`SyncDetailsView`/`CompactSyncIndicator`, defined in the same file),
`DietPhaseHistoryView`, `WhatsNewView`, `WhatsNewRow`, `VersionRow`,
`EditEntrySheet` (`EditEntrySavePolicy` extracted to
`Utils/EditEntrySavePolicy.swift`; its tests are unchanged),
`PreAuthBodyScoreOnboardingContainer`, `DashboardMetricCards.swift` (incl.
`PhotoOptionsSheet`), `DeveloperToolsList`, `DeveloperTapHandler`,
`DeveloperTapIndicator`, `ProcessingImagePlaceholder`,
`Models/BackgroundTaskMonitor.swift`, `Models/BackgroundTaskDetailsSheet.swift`,
`Models/BackgroundTaskType.swift`, `DesignSystem/Atoms/AnimatedTaskIcon.swift`,
`BackgroundPhotoUploadService+Processing.swift`, and `queuePhotosForUpload`
from `BackgroundPhotoUploadService.swift` (rest of the service stays).
On-disk-only files removed with plain `rm` (never in the build target):
`FaceIDEnableView.swift`, `ImageProcessingStatusView`, `DeveloperMenuSection`,
`Models/DashboardTaskBanner.swift`, `Models/AnimatedTaskIcon.swift`,
`Components/BackgroundTaskDetailsSheet.swift`, `Services/BackgroundTaskMonitor.swift`.

**Deferred — product decision needed, not tests:**

- `Models/Changelog.swift` — its only consumer was the deleted `WhatsNewView`.
- `Services/BackgroundPhotoUploadService.swift` remainder — its only
  observers were the deleted `BackgroundTaskMonitor` copies.

Each deletion PR must verify no caller + remove from pbxproj.

---

## D. Work queue (risk-ordered batches; one small PR per batch)

| Batch | Scope                                                                                                                                                                                               | Type             |
| ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- |
| 1     | This inventory + baseline numbers                                                                                                                                                                   | docs             |
| 2     | Infra fixes I1–I8: CI unit gate in `ios` job, resolve duplicate mock, orphan DesignSystem tests, xctestplans (Unit/Integration/UI), wire `golden_path`, fix `ui_snapshot`, coverage+duration report | CI/test-infra    |
| 3     | Auth hardening: KeychainManager, AuthManager session/token gaps, BiometricLockView policy, launch/store-recovery policies                                                                           | unit+integration |
| 4     | Legal consent gate (`LegalConsentView`, `LegalDocumentView`) — launch-blocking                                                                                                                      | unit+XCUITest    |
| 5     | Photo upload pipeline: PhotoUploadManager, BackgroundPhotoUploadService, ExternalServicePorts                                                                                                       | integration      |
| 6     | AppVersionManager upgrade migrations + DebugResetManager (data-loss)                                                                                                                                | integration+unit |
| 7     | BodySpec: API client contract + auth manager + IntegrationsView policy                                                                                                                              | integration      |
| 8     | App Intents logging path                                                                                                                                                                            | integration      |
| 9     | Onboarding: step-policy gaps + XCUITest golden path (hook→reveal)                                                                                                                                   | unit+XCUITest    |
| 10    | Settings: ProfileSettingsViewV2, SecuritySessionsView, DeleteAccountView flow, ExportDataView CSV                                                                                                   | unit+integration |
| 11    | B.2 medium sweep (analytics/error/bug-report adapters, device normalization, Vision pipeline, timeline helpers, models)                                                                             | unit             |
| 12    | B.3 low sweep + dead-code deletion PRs                                                                                                                                                              | unit/chore       |
| 13    | Final: duration report review, verify ≥70% overall / ≥80% patch floors, golden-path XCUITest gap-fill                                                                                               | verification     |

Progress tracker: mark batches here as PRs merge.

- Batch 1 — inventory + baseline: ✅ #480
- Batch 2a — hygiene (I2/I3/I4): ✅ #481
- Batch 2b — tier plans + report script (I6/I7): ✅ #482
- Batch 2c — CI unit gate + report step (I1, I5 by design): this PR
- Batch 3 — auth hardening: ✅ #483 (in review)
- Batch 4 — legal consent gate: ✅ #485
- Batch 5 — photo upload pipeline: ✅ #486
- Batch 9 (unit part) — onboarding step-policy + VM validation gaps: this PR
  (`OnboardingStepEntryPolicyTests`, `OnboardingScoreDisplayPolicyTests`,
  `OnboardingFlowValidationTests`; hook→reveal XCUITest golden path deferred)
- Dead-code deletion (section C sweep): this PR — ~4,068 app-target lines
  removed against the 92,243-line baseline denominator (coverage % rises
  accordingly)
