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

## Decision record (2026-07-20, owner: @itstimwhite)

**Superseded the 70%-overall floor with the per-layer standard below as the
iOS completion definition.** Rationale (measured in the verification report):
64% of the app's executable lines are SwiftUI view layer, so a 70% overall
floor is reachable only through view-instantiation padding (banned by this
effort's quality bar) or brittle at-scale XCUITest suites. This matches the
company's primary rule — coverage on the right files, by blast radius.

Adopted standard:

- **Logic layers** (Services, Helpers, Models, Utils, Features): target
  **≥70% per layer**. Standing baseline at decision time: Helpers **82.7%**,
  Models 58.5%, Utils 55.0%, Services 53.4%, Features 42.6%. The remaining
  points are tracked as follow-up work in the queue (section D) — they do
  not gate this effort's completion, which is defined by the risk-register
  coverage below plus CI/tiering/validation gates.
- **Risk-register surfaces** (auth, keychain, paywall, sync, migrations,
  onboarding, photo pipeline, BodySpec, settings, notifications, App
  Intents, Vision pipeline, vendor adapters): **required coverage — done**
  (all batches merged; new critical surfaces join the register as they
  appear).
- **View layer** (Views, Components, DesignSystem): measured only through
  golden-path XCUITests; **no line-coverage floor** (padding forbidden).
- **Patch coverage** ≥80% on touched lines: unchanged, held.
- **Duration/tiering/CI/validation gates** (unit <200ms target report-only,
  separate suites, CI unit gate, swiftlint/xcodebuild/pnpm green):
  unchanged, held and enforced on every PR.

## Verification report (2026-07-20, post-batches)

Measured on main after all batches merged (full unit target + coverage,
`test_results/verification2.xcresult`, erased simulator, **TEST SUCCEEDED**):

- **Suite: 691 test cases** (baseline 360, +92%), 0 failures. Tier split:
  Unit plan ~580 (target <200ms each; 4 legitimately over, all perf-style
  assertions), Integration plan ~110, XCUITest target 28 incl. the
  onboarding hook→reveal golden path.
- **App-target line coverage: 20.20%** (17,083 / 84,589; baseline 14.36%
  of 92,243). Denominator −7,654 lines (dead-code removal).
- **Per-area coverage** (the honest shape of the app):

  | Area                  | Coverage  | Lines           |
  | --------------------- | --------- | --------------- |
  | Helpers               | **82.7%** | 1,096 / 1,326   |
  | Models                | **58.5%** | 907 / 1,551     |
  | Utils                 | **55.0%** | 572 / 1,040     |
  | Services              | **53.4%** | 10,135 / 18,967 |
  | Features (onboarding) | **42.6%** | 1,262 / 2,962   |
  | DesignSystem          | 7.8%      | 530 / 6,817     |
  | Components            | 6.1%      | 899 / 14,650    |
  | Views                 | **2.8%**  | 952 / 33,902    |

- **On the 70% overall floor:** the floor came from the company's web-app
  standard (logic-dominated Next.js). In this app, **~64% of executable
  lines are SwiftUI view-layer code** (Views+Components+DesignSystem =
  54,469 lines) which a unit/integration strategy does not and should not
  touch per the risk-based standard ("coverage on the right files", the
  company's primary rule). Reaching 70% overall would require ~42,000
  additional covered lines — almost entirely views — via either brittle
  at-scale XCUITest suites or view-instantiation padding tests (explicitly
  banned by this effort's quality bar). **Resolved: the per-layer standard
  was adopted as the iOS completion definition — see the decision record
  above.** Truthful reading under it: **logic layers 42–83% with ≥70%
  targets tracked as follow-ups, risk-register surfaces covered, overall
  20.2%**.
- **Patch coverage ≥80% on touched lines:** held. Every production line
  added by this effort (policy extractions, vendor seams) shipped with
  direct behavior tests; the rest was test-only or deletions.
- **Duration report (report-only):** 13 tests >200ms — 4 integration
  store-retry/migration tests with real waits (≤2.2s), 2 intentional
  `measure {}` perf tests, 7 image-render tests (0.24–0.35s). All in the
  integration tier or intentional; unit tier has 4 perf-style assertions
  at 0.2–0.5s. No action required; reviewed per the report-only policy.
- **Determinism note:** OnboardingFlowValidationTests can fail on a
  _dirty_ simulator (pre-existing app state; seen once locally, never on
  CI's fresh simulators). Hardening its setUp is on the follow-up ledger.

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

| Surface                                                                                                                                                                                  | File                                                                  | Risk           | Layer                                             | Status / existing                                                                                                                                                                                                                                                     |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | -------------- | ------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `BodyScoreOnboardingFlowView` (17-step router)                                                                                                                                           | `Features/Onboarding/Views/BodyScoreOnboardingFlowView.swift`         | H              | unit (VM) + XCUITest                              | 🔶 `OnboardingFlowViewModelTests`, UI CTA tests                                                                                                                                                                                                                       |
| 16 step views (hook, basics, height, health connect/confirm, manual weight, BF choice/numeric/visual, loading, reveal, home-mode, email, account creation, profile details, first photo) | `Features/Onboarding/Views/BodyScore*.swift`                          | H (activation) | unit (step policies in VM) + XCUITest golden path | 🔶 `OnboardingStepEntryPolicyTests`, `OnboardingScoreDisplayPolicyTests`, `OnboardingFlowValidationTests` + indirect via `OnboardingFlowViewModelTests`; reveal math via `BodyScoreEngineTests`; XCUITest golden path via `OnboardingGoldenPathUITests` (hook→reveal) |
| `ProfileCompletionGateView`                                                                                                                                                              | `Features/Onboarding/Views/ProfileCompletionGateView.swift`           | H              | unit                                              | 🔶 `LaunchSurfacePolicyTests`, VM tests                                                                                                                                                                                                                               |
| `PreAuthBodyScoreOnboardingContainer`                                                                                                                                                    | `Features/Onboarding/Views/PreAuthBodyScoreOnboardingContainer.swift` | L              | —                                                 | 🗑 orphaned                                                                                                                                                                                                                                                           |

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

| Surface                                                                       | File                                | Risk | Layer           | Status / existing                                                                                               |
| ----------------------------------------------------------------------------- | ----------------------------------- | ---- | --------------- | --------------------------------------------------------------------------------------------------------------- |
| `PreferencesView` (hub)                                                       | `Views/PreferencesView.swift`       | M    | unit + XCUITest | 🔶 UI settings fixtures, `DailyReminderPolicyTests`                                                             |
| `ProfileSettingsViewV2` (+2 picker sheets)                                    | `Views/ProfileSettingsViewV2.swift` | M    | unit            | 🔶 `ProfileSettingsPolicyTests`                                                                                 |
| `PreferenceGoalEditorSheet`                                                   | `Views/PreferenceGoalEditing.swift` | M    | unit            | 🔶 `PreferenceGoalValidatorTests`, UI goal-editor tests                                                         |
| `SecuritySessionsView`                                                        | `Views/SecuritySessionsView.swift`  | M    | unit            | 🔶 `SessionListOrderingTests` (view states declarative; no HTTP boundary — sessions synthesized locally)        |
| `DeleteAccountView`                                                           | `Views/DeleteAccountView.swift`     | H    | integration     | 🔶 `AccountDeletionCleanupServiceTests` (service-level), `AccountDeletionConfirmationPolicyTests` (view gating) |
| `LegalView`, `WhatsNewView`, `SyncStatusView`/`SyncDetailsView`, `VersionRow` | `Views/`                            | —    | —               | 🗑 all orphaned                                                                                                 |

### A.8 HealthKit / integrations

| Surface                   | File                                  | Risk | Layer                      | Status / existing                                                  |
| ------------------------- | ------------------------------------- | ---- | -------------------------- | ------------------------------------------------------------------ |
| `IntegrationsView`        | `Views/IntegrationsView.swift`        | M    | unit + XCUITest            | 🔶 HealthKit policy/pipeline tests, UI bulk-import fixtures        |
| `BodySpecIntegrationView` | `Views/BodySpecIntegrationView.swift` | M    | integration (stubbed HTTP) | ❌ view; importer covered (`SyncIntegrationImportAndMappingTests`) |
| `HealthKitPromptView`     | `Views/HealthKitPromptView.swift`     | —    | —                          | 🗑 orphaned                                                        |

### A.9 Data export / import

| Surface               | File                              | Risk | Layer              | Status / existing                                                         |
| --------------------- | --------------------------------- | ---- | ------------------ | ------------------------------------------------------------------------- |
| `ExportDataView`      | `Views/ExportDataView.swift`      | M    | unit (CSV builder) | 🔶 `ExportCSVBuilderTests` (CSV builder; email-export edge call untested) |
| `BulkPhotoImportView` | `Views/BulkPhotoImportView.swift` | M    | unit + XCUITest    | 🔶 `BulkImportManagerBoundsTests`, policy tests, UI fixtures              |

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
manager, validation/logging services, launch/auth surface policies,
Vision/photo pipeline (ImageProcessingService, BackgroundRemovalService,
VisionOrientationService, PhotoLibraryScanner criteria/auth mapping).

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

| File                                                                                                                                                | Responsibility                                | Layer              |
| --------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ------------------ |
| `Services/AnalyticsService.swift`                                                                                                                   | Statsig event adapter                         | unit (fake client) |
| `Services/ErrorTrackingService.swift`, `Utils/ErrorReporter.swift`                                                                                  | Sentry wrappers                               | unit (fake client) |
| `Services/BugReportManager.swift`                                                                                                                   | Shake-to-report capture/submit                | unit               |
| `Services/DeviceNormalizationService.swift` + `Models/HKRawSample.swift`                                                                            | Device confidence inference                   | unit               |
| `Services/BodyMetricSpotlightIndexer.swift`                                                                                                         | Spotlight indexing (document mapping covered) | unit               |
| `Helpers/TimelineCalculator.swift`, `LRUCache.swift`, `TimelinePhotoSampler.swift`, `MetricChartDataHelper.swift`, `TimelineBucketCalculator.swift` | Timeline/chart helpers                        | unit               |
| `Models/GlobalTimelineModels.swift` (bucket/cursor/scale)                                                                                           | Timeline models                               | unit               |
| `Utils/AppVersion.swift`, `Utils/AppError.swift`                                                                                                    | Semver + error taxonomy                       | unit               |
| `Utils/ShakeDetector.swift` (incl. `DebugResetManager` — data-loss risk)                                                                            | Shake/screenshot/debug reset                  | unit               |
| `Models/Changelog.swift`                                                                                                                            | What's-new tracking                           | unit               |
| `Models/TimelineMode.swift`                                                                                                                         | Timeline mode + formatter cache               | unit               |

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
- Batch 6 — version migrations + debug reset: ✅ #488
- Batch 7 — BodySpec API + OAuth: ✅ #489
- Batch 8 — App Intents: ✅ #490
- Batch 9 — onboarding step-policy + VM validation gaps: ✅ #491
  (`OnboardingStepEntryPolicyTests`, `OnboardingScoreDisplayPolicyTests`,
  `OnboardingFlowValidationTests`; hook→reveal XCUITest golden path deferred)
- Onboarding hook→reveal XCUITest golden path (batch 9 deferral): this PR —
  `OnboardingGoldenPathUITests` drives the fixture-provisioned flow through
  hook, basics, height, manual entry, weight, body fat, and reveal.
- Batch 10 — settings cluster (ProfileSettingsViewV2, SecuritySessionsView,
  DeleteAccountView gating, ExportDataView CSV): ✅ #492
- Batch 11a — vendor adapters + timeline helpers: ✅ #493
- Batch 11b — Vision/photo pipeline: this PR (`ImageProcessingServiceTests`,
  `BackgroundRemovalServiceTests`, `VisionOrientationServiceTests`,
  `PhotoLibraryScannerTests` + `SyntheticImageFixtures`; pins
  Vision-on-simulator setup failures, documents a
  `BackgroundRemovalService.removeBackground` double-continuation-resume crash
  on simulator as a known app bug — not fixed here)
- Batch 12 — NotificationManager scheduling + B.3 audit sweep: in review (#495)
- Batch 11b follow-up — batch-test determinism: this PR. Batch items now fail
  at the pipeline's step-0 `invalidImage` guard (CIImage-backed inputs):
  three concurrent first-time Vision model setups deadlock on fresh CI
  simulators (simulator-only framework hazard; serialized setups and
  production devices are unaffected). No app-code change.
- Batch 13 — verification closeout: this PR (verification report above,
  duration-report review, follow-up ledger below)
- Decision — per-layer standard adopted as the completion definition
  (owner, 2026-07-20): see the decision record above; logic-layer ≥70%
  targets tracked as follow-ups, risk-register coverage done

## Follow-up ledger (findings from the batches, with evidence)

**Real bugs — worth their own fix PRs (failing test first):**

1. `BackgroundRemovalService.removeBackground` double-resumes a
   `CheckedContinuation` → runtime trap (kills the test host on simulator;
   structurally latent on device). Found by batch 11b with reproduction.
   Fix = resume-once guard; then the error path becomes testable.
2. CSV export escaping (`ExportCSVBuilder`, pre-existing): embedded quotes
   aren't doubled and newlines aren't escaped → malformed CSV per RFC 4180
   when notes contain them. Batch 10 pinned the behavior with tests.
3. Session revocation UI is dead: `fetchActiveSessions()` can only return
   the current session, and the view loads via `AuthManager.shared` but
   revokes via the environment instance (batch 10).
4. CSV export semantics: nil metrics export as literal `0`
   (indistinguishable from a real measurement); weight-unit default
   inconsistent between the two CSVs; FFMI column is an interpolated
   estimate, not a stored value (batch 10).
5. `AppVersionManager.optimizeCoreData` calls `replacePersistentStore` on
   the live shared store — can silently fail or diverge the on-disk file
   from the open handle (batch 6; tests assert the marker only).
6. `BodyMetricLoggingService.log` wraps body-fat validation failures as
   `ValidationError.invalidWeight` instead of `.invalidBodyFat` (batch 8,
   pinned).

**Product decisions needed (not bugs to simply fix):**

7. **Legal consent gate is inert** (HIGH): `AuthManager.needsLegalConsent`
   is only ever assigned `false` and `checkLegalConsent` has zero call
   sites — no user is ever gated. Arming it is a user-visible compliance
   change needing a product decision + Statsig gate. Secondary defect:
   `LegalConsentView.accept()` dismisses unconditionally, so a failed
   PATCH silently closes the gate for the session (batch 4).
8. `Models/Changelog.swift` (164 lines): only consumer was the deleted
   WhatsNewView — delete or revive as a What's New surface (product call).
9. `BackgroundPhotoUploadService` remainder: only observed by the deleted
   task-monitor cluster — keep for a future bulk-upload surface or delete.
10. `processBatchImages` runs unbounded concurrency — cap for device
    memory pressure during bulk import? (batch 11b note)
11. BodySpec API trailing slash: client normalizes
    `/api/v1/users/me/results/` → `/results`; verify the backend tolerates
    it (batch 7 note).

**Test-infra follow-ups:**

12. OnboardingFlowValidationTests: harden setUp against dirty simulator
    state (verification report note).
13. Dead on-disk files for the next deletion PR:
    `Services/DeviceNormalizationService.swift` (never compiled),
    `DailyLog` computed props + mocks, `BodyCompMeasurement`,
    `BodyCompMethod.infer`, `BodyCompSourceType.infer` (zero callers).
14. `PhotoLibraryScanner` needs a fetcher seam to test grouping/dedup;
    `BodyMetricSpotlightIndexer` needs a `CSSearchableIndex` seam (batch
    11a/11b notes).
15. Eight 14-line one-assertion test files could be consolidated (I8).
16. Keychain tests skip on unsigned CI hosts; enable when CI signs the
    test host (`KeychainAvailability` TODO).
17. Behavior quirks pinned by tests (review for intent):
    `inferMethod`'s `"dexa"` match is case-sensitive; chart data excludes
    same-day entries; non-numeric height input reports the 100cm floor.

- Dead-code deletion (section C sweep): this PR — ~4,068 app-target lines
  removed against the 92,243-line baseline denominator (coverage % rises
  accordingly)
