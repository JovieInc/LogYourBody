import SwiftUI

/// Deterministic entry point for XCUITest-only scenarios. It is selected only
/// with the `-uiTestScenario` launch argument and keeps external services out
/// of interaction tests while rendering the production screens themselves.
@MainActor
struct UITestRootView: View {
    let scenario: String

    @StateObject private var authManager: AuthManager
    @StateObject private var onboardingViewModel: OnboardingFlowViewModel
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    @StateObject private var realtimeSyncManager: RealtimeSyncManager
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var securitySessionFixture: SecuritySessionFixture
    @StateObject private var bulkPhotoScanner: PhotoLibraryScanner
    @State private var isAddEntryPresented = true
    @State private var selectedChartRange: TimeRange = .month1
    @State private var didRequestChartEntry = false
    @State private var didConfigureFixture = false
    @State private var isFixtureReady = false
    @State private var isLegalConsentPresented = true
    @State private var didAcceptLegalConsent = false
    @State private var isWhatsNewPresented = true
    @State private var selectedPhotoIndex = 0
    @State private var photoDisplayMode: DashboardDisplayMode = .photo
    @State private var biometricRecoveryResult = "Biometric recovery idle"
    @State private var isBiometricLockUnlocked = false
    @State private var selectedTimelineIndex = 0
    @State private var timelineMode: TimelineMode = .photo
    @State private var isSyncDetailsPresented = true

    init(scenario: String) {
        self.scenario = scenario

        if [
            "onboarding",
            "onboarding-health",
            "add-entry",
            "add-entry-no-medication",
            "log-metrics",
            "export"
        ].contains(scenario) {
            UserDefaults.standard.set(
                MeasurementSystem.metric.rawValue,
                forKey: Constants.preferredMeasurementSystemKey
            )
        }

        let testAuthManager = AuthManager()
        let testBulkPhotoScanner = PhotoLibraryScanner()
        if scenario == "dashboard-background-task" {
            let scanner = PhotoLibraryScanner.shared
            scanner.scannedPhotos = []
            scanner.scanProgress = 0.6
            scanner.isScanning = true
        }
        if scenario == "dashboard-background-processing" {
            let imageProcessingService = ImageProcessingService.shared
            imageProcessingService.processingTasks = []
            imageProcessingService.activeProcessingCount = 2
        }
        if scenario.hasPrefix("bulk-photo-import-") {
            testBulkPhotoScanner.scannedPhotos = []
            switch scenario {
            case "bulk-photo-import-scanning":
                testBulkPhotoScanner.authorizationStatus = .authorized
                testBulkPhotoScanner.scanProgress = 0.65
                testBulkPhotoScanner.isScanning = true
            case "bulk-photo-import-empty":
                testBulkPhotoScanner.authorizationStatus = .authorized
                testBulkPhotoScanner.scanProgress = 1
                testBulkPhotoScanner.isScanning = false
            case "bulk-photo-import-denied":
                testBulkPhotoScanner.authorizationStatus = .denied
                testBulkPhotoScanner.scanProgress = 0
                testBulkPhotoScanner.isScanning = false
            default:
                break
            }
        }
        let testRealtimeSyncManager = RealtimeSyncManager(
            coreDataManager: CoreDataManager.shared,
            authManager: testAuthManager,
            supabaseManager: SupabaseManager.shared
        )
        testRealtimeSyncManager.isOnline = false
        if scenario == "dashboard-sync-details" {
            testRealtimeSyncManager.syncStatus = .offline
            testRealtimeSyncManager.lastSyncDate = Date(timeIntervalSince1970: 1_700_000_000)
            testRealtimeSyncManager.pendingSyncCount = 4
            testRealtimeSyncManager.unsyncedBodyCount = 2
            testRealtimeSyncManager.unsyncedDailyCount = 1
            testRealtimeSyncManager.unsyncedProfileCount = 1
            testRealtimeSyncManager.error = "No network available. Changes will sync when you reconnect."
        }
        _authManager = StateObject(wrappedValue: testAuthManager)
        _realtimeSyncManager = StateObject(wrappedValue: testRealtimeSyncManager)
        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel())
        _securitySessionFixture = StateObject(wrappedValue: SecuritySessionFixture())
        _bulkPhotoScanner = StateObject(wrappedValue: testBulkPhotoScanner)

        let testOnboardingViewModel = OnboardingFlowViewModel(entryContext: .preAuth)
        switch scenario {
        case "onboarding-email":
            testOnboardingViewModel.currentStep = .emailCapture
        case "onboarding-profile":
            testOnboardingViewModel.currentStep = .profileDetails
        case "onboarding-reveal":
            testOnboardingViewModel.currentStep = .bodyScore
            testOnboardingViewModel.bodyScoreResult = BodyScoreResult(
                score: 82,
                ffmi: 21.4,
                leanPercentile: 78,
                ffmiStatus: "Advanced",
                targetBodyFat: .init(lowerBound: 10, upperBound: 15, label: "Lean"),
                statusTagline: "Solid base. Room to tighten up."
            )
        case "onboarding-health":
            testOnboardingViewModel.currentStep = .healthConfirmation
            testOnboardingViewModel.bodyScoreInput = BodyScoreInput(
                sex: .male,
                birthYear: 1_989,
                height: HeightValue(value: 180, unit: .centimeters),
                weight: WeightValue(value: 80, unit: .kilograms),
                bodyFat: BodyFatValue(percentage: 18.5, source: .healthKit),
                measurementPreference: .metric,
                healthSnapshot: HealthImportSnapshot(
                    heightCm: 180,
                    weightKg: 80,
                    bodyFatPercentage: 18.5,
                    birthYear: 1_989,
                    heightDate: Date(),
                    weightDate: Date(),
                    bodyFatDate: Date()
                )
            )
        default:
            break
        }
        _onboardingViewModel = StateObject(wrappedValue: testOnboardingViewModel)
    }

    var body: some View {
        scenarioContent
            // ContentView keeps the production app in dark mode. Apply the
            // same environment to isolated scenarios so UI tests and visual
            // QA exercise the colors users actually see.
            .preferredColorScheme(.dark)
            .task {
                await configureFixtureIfNeeded()
            }
    }

    @ViewBuilder
    private var scenarioContent: some View {
        switch scenario {
        case "login":
            NavigationStack {
                LoginView()
            }
            .environmentObject(authManager)
        case "signup":
            NavigationStack {
                SignUpView()
            }
            .environmentObject(authManager)
        case "onboarding", "onboarding-email", "onboarding-profile", "onboarding-reveal", "onboarding-health":
            BodyScoreOnboardingFlowView(viewModel: onboardingViewModel)
                .environmentObject(authManager)
                .environmentObject(revenueCatManager)
        case "legal-consent":
            if isLegalConsentPresented {
                LegalConsentView(
                    isPresented: $isLegalConsentPresented,
                    userId: "ui-test-user",
                    onAccept: {
                        didAcceptLegalConsent = true
                    }
                )
            } else {
                Text(didAcceptLegalConsent ? "Legal consent accepted" : "Legal consent dismissed")
                    .accessibilityIdentifier("legal-consent-result")
            }
        case "whats-new":
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if !isWhatsNewPresented {
                    Text("Changelog dismissed")
                        .accessibilityIdentifier("whats-new-dismissed")
                }
            }
            .sheet(isPresented: $isWhatsNewPresented) {
                WhatsNewView()
            }
        case "add-entry", "add-entry-no-medication":
            if isFixtureReady {
                ZStack {
                    Color.appBackground
                        .ignoresSafeArea()

                    if !isAddEntryPresented {
                        Text("Entry dismissed")
                            .accessibilityIdentifier("entry-dismissed")
                    }
                }
                .sheet(isPresented: $isAddEntryPresented) {
                    AddEntrySheet(isPresented: $isAddEntryPresented)
                        .environmentObject(authManager)
                }
            } else {
                fixtureLoadingView
            }
        case "settings":
            NavigationStack {
                PreferencesView()
            }
            .environmentObject(authManager)
        case "dashboard-sync-details":
            if isSyncDetailsPresented {
                DashboardSyncDetailsSheet(
                    isPresented: $isSyncDetailsPresented,
                    syncManager: realtimeSyncManager
                )
            } else {
                Text("Sync details dismissed")
                    .accessibilityIdentifier("sync-details-dismissed")
            }
        case "integrations":
            NavigationStack {
                IntegrationsView()
            }
            .environmentObject(authManager)
        case "bulk-photo-import":
            NavigationStack {
                BulkPhotoImportView()
            }
            .environmentObject(authManager)
        case "bulk-photo-import-scanning", "bulk-photo-import-empty", "bulk-photo-import-denied":
            NavigationStack {
                BulkPhotoImportView(
                    scanner: bulkPhotoScanner,
                    startsOnWelcomeScreen: false,
                    hasStartedScan: scenario != "bulk-photo-import-denied"
                )
            }
            .environmentObject(authManager)
        case "dashboard-background-task", "dashboard-background-processing":
            BackgroundTaskDetailsSheet(taskMonitor: BackgroundTaskMonitor.shared)
        case "body-spec":
            NavigationStack {
                BodySpecIntegrationView()
            }
            .environmentObject(authManager)
        case "change-password":
            NavigationStack {
                ChangePasswordView()
            }
        case "security-sessions":
            NavigationStack {
                SecuritySessionsView()
                    .environmentObject(authManager)
            }
        case "security-sessions-fixture":
            NavigationStack {
                SecuritySessionsView(
                    sessionLoader: { securitySessionFixture.sessions },
                    sessionRevoker: { sessionId in
                        securitySessionFixture.revoke(sessionId: sessionId)
                    }
                )
                .environmentObject(authManager)
            }
        case "email-verification-success":
            NavigationStack {
                EmailVerificationView(
                    verifyHandler: { _ in },
                    resendHandler: {},
                    resendCooldown: 0
                )
                .environmentObject(authManager)
            }
        case "email-verification-failure":
            NavigationStack {
                EmailVerificationView(
                    verifyHandler: { _ in throw UITestEmailVerificationError.invalidCode },
                    resendHandler: {},
                    resendCooldown: 0
                )
                .environmentObject(authManager)
            }
        case "delete-account":
            NavigationStack {
                DeleteAccountView()
                    .environmentObject(authManager)
            }
        case "progress-photos-empty":
            ProgressPhotoCarouselView(
                currentMetric: nil,
                historicalMetrics: [],
                selectedMetricsIndex: $selectedPhotoIndex,
                displayMode: $photoDisplayMode
            )
            .environmentObject(authManager)
        case "optimized-photo-empty":
            OptimizedProgressPhotoView(photoUrl: nil, maxHeight: 240)
                .padding()
        case "optimized-photo-invalid":
            OptimizedProgressPhotoView(photoUrl: "not a valid image URL", maxHeight: 240)
                .padding()
        case "biometric-recovery":
            ZStack {
                Color.appBackground.ignoresSafeArea()
                BiometricAuthView(
                    biometricType: .faceID,
                    onAuthenticate: {
                        biometricRecoveryResult = "Biometric retry requested"
                    },
                    onUsePassword: {
                        biometricRecoveryResult = "Biometric fallback selected"
                    }
                )

                Text(biometricRecoveryResult)
                    .accessibilityIdentifier("biometric-recovery-result")
            }
        case "biometric-lock-success":
            if isBiometricLockUnlocked {
                Text("Biometric lock unlocked")
                    .accessibilityIdentifier("biometric-lock-result")
            } else {
                BiometricLockView(
                    isUnlocked: $isBiometricLockUnlocked,
                    biometricTypeOverride: .faceID,
                    authenticationAttempt: { true }
                )
            }
        case "biometric-lock-failure":
            if isBiometricLockUnlocked {
                Text("Biometric lock unlocked")
                    .accessibilityIdentifier("biometric-lock-result")
            } else {
                BiometricLockView(
                    isUnlocked: $isBiometricLockUnlocked,
                    biometricTypeOverride: .touchID,
                    authenticationAttempt: { false },
                    deviceOwnerAuthenticationAttempt: { false }
                )
            }
        case "biometric-lock-passcode-success":
            if isBiometricLockUnlocked {
                Text("Biometric lock unlocked")
                    .accessibilityIdentifier("biometric-lock-result")
            } else {
                BiometricLockView(
                    isUnlocked: $isBiometricLockUnlocked,
                    biometricTypeOverride: .touchID,
                    authenticationAttempt: { false },
                    deviceOwnerAuthenticationAttempt: { true }
                )
            }
        case "progress-timeline":
            VStack(spacing: 20) {
                ProgressTimelineView(
                    bodyMetrics: timelineFixtureMetrics,
                    selectedIndex: $selectedTimelineIndex,
                    mode: $timelineMode
                )
                .frame(height: 80)

                Text("Timeline selection \(selectedTimelineIndex)")
                    .accessibilityIdentifier("progress-timeline-selection")
            }
            .padding()
            .background(Color.liquidBg.ignoresSafeArea())
        case "profile-editor":
            NavigationStack {
                ProfileSettingsViewV2()
            }
            .environmentObject(authManager)
        case "full-chart":
            NavigationStack {
                chartScenario(chartData: chartFixtureData, metricEntries: chartFixtureEntries)
            }
        case "full-chart-empty":
            NavigationStack {
                chartScenario(chartData: [], metricEntries: nil)
            }
        case "log-metrics":
            if isFixtureReady {
                LogWeightView()
                    .environmentObject(authManager)
            } else {
                fixtureLoadingView
            }
        case "export":
            if isFixtureReady {
                ExportDataView()
                    .environmentObject(authManager)
            } else {
                fixtureLoadingView
            }
        case "paywall":
            PaywallView()
                .environmentObject(authManager)
                .environmentObject(revenueCatManager)
        case "dashboard":
            if isFixtureReady {
                NavigationStack {
                    DashboardViewLiquid()
                        .environmentObject(authManager)
                        .environmentObject(realtimeSyncManager)
                }
            } else {
                fixtureLoadingView
            }
        case "dashboard-preloaded", "dashboard-empty":
            if isFixtureReady {
                NavigationStack {
                    DashboardViewLiquid(
                        viewModel: dashboardViewModel,
                        performsInitialRefresh: false
                    )
                    .environmentObject(authManager)
                    .environmentObject(realtimeSyncManager)
                }
            } else {
                fixtureLoadingView
            }
        case "dashboard-sync-error":
            if isFixtureReady {
                NavigationStack {
                    DashboardViewLiquid(
                        viewModel: dashboardViewModel,
                        performsInitialRefresh: false
                    )
                    .environmentObject(authManager)
                    .environmentObject(realtimeSyncManager)
                }
                .task {
                    await Task.yield()
                    realtimeSyncManager.isOnline = true
                    realtimeSyncManager.error = "Unable to reach the sync service."
                    realtimeSyncManager.syncStatus = .error("Unable to reach the sync service.")
                }
            } else {
                fixtureLoadingView
            }
        case "legal":
            NavigationStack {
                LegalView()
            }
        default:
            VStack(spacing: 12) {
                Text("Unsupported UI test scenario")
                Text(scenario)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timelineFixtureMetrics: [BodyMetrics] {
        let start = Date(timeIntervalSince1970: 86_400)
        let end = start.addingTimeInterval(9 * 86_400)

        return [
            BodyMetrics(
                id: "timeline-start",
                userId: "ui-test-user",
                date: start,
                weight: 80,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: nil,
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: start,
                updatedAt: start
            ),
            BodyMetrics(
                id: "timeline-end",
                userId: "ui-test-user",
                date: end,
                weight: 78,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: nil,
                photoUrl: nil,
                dataSource: "Manual",
                createdAt: end,
                updatedAt: end
            )
        ]
    }

    private func configureFixtureIfNeeded() async {
        guard !didConfigureFixture else { return }
        didConfigureFixture = true

        let fixtureUserId: String
        if scenario == "add-entry-no-medication" {
            fixtureUserId = ProcessInfo.processInfo.environment["UI_TEST_FIXTURE_USER_ID"] ?? "ui-test-add-medication"
        } else {
            fixtureUserId = "ui-test-user"
        }

        authManager.isClerkLoaded = true
        authManager.isAuthenticated = true
        authManager.currentUser = User(
            id: fixtureUserId,
            email: "ui.test@example.com",
            name: "UI Test User",
            avatarUrl: nil,
            profile: UserProfile(
                id: fixtureUserId,
                email: "ui.test@example.com",
                username: "uitest",
                fullName: "UI Test User",
                dateOfBirth: Date(timeIntervalSince1970: 631_152_000),
                height: 170,
                heightUnit: "cm",
                gender: "Female",
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: nil,
                onboardingCompleted: true
            ),
            onboardingCompleted: true
        )
        if scenario == "paywall" {
            revenueCatManager.isSubscribed = false
            revenueCatManager.currentOffering = nil
            revenueCatManager.isPurchasing = false
            revenueCatManager.errorMessage = nil
            return
        }

        revenueCatManager.isSubscribed = true

        let fixtureScenarios: Set<String> = [
            "add-entry",
            "add-entry-no-medication",
            "dashboard",
            "dashboard-preloaded",
            "dashboard-empty",
            "dashboard-sync-error",
            "log-metrics",
            "export"
        ]
        guard fixtureScenarios.contains(scenario) else {
            return
        }

        if scenario == "dashboard-empty" {
            dashboardViewModel.hasLoadedInitialData = true
            isFixtureReady = true
            return
        }

        let date = Date()
        let metric = BodyMetrics(
            id: "ui-test-fixture-metric",
            userId: fixtureUserId,
            date: date,
            weight: 72,
            weightUnit: "kg",
            bodyFatPercentage: 18,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: "UI test fixture",
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: date,
            updatedAt: date
        )
        let dailyMetric = DailyMetrics(
            id: "ui-test-fixture-daily",
            userId: fixtureUserId,
            date: date,
            steps: 7_500,
            notes: "UI test fixture",
            createdAt: date,
            updatedAt: date
        )

        CoreDataManager.shared.saveBodyMetrics(metric, userId: fixtureUserId)
        CoreDataManager.shared.saveDailyMetrics(dailyMetric, userId: fixtureUserId)

        if scenario == "dashboard-preloaded" {
            dashboardViewModel.bodyMetrics = [metric]
            dashboardViewModel.sortedBodyMetricsAscending = [metric]
            dashboardViewModel.dailyMetrics = dailyMetric
            dashboardViewModel.recentDailyMetrics = [dailyMetric]
            dashboardViewModel.hasLoadedInitialData = true
        }

        if scenario == "add-entry" {
            let medication = Glp1Medication(
                id: "ui-test-wegovy",
                userId: "ui-test-user",
                displayName: "Wegovy",
                genericName: "semaglutide",
                drugClass: "GLP-1 receptor agonist",
                brand: "Wegovy",
                route: "subcutaneous",
                frequency: "once weekly",
                doseUnit: "mg/week",
                isCompounded: false,
                hkIdentifier: "hk.glp1.semaglutide.wegovy.weekly",
                startedAt: date,
                endedAt: nil,
                notes: nil,
                createdAt: date,
                updatedAt: date
            )
            CoreDataManager.shared.saveGlp1Medications([medication], userId: "ui-test-user")
        }

        // The save APIs enqueue Core Data work. Awaiting a fetch on the same
        // context provides an ordering barrier before fixture-backed views can
        // read, preventing UI tests from racing their setup.
        _ = await CoreDataManager.shared.fetchBodyMetrics(for: fixtureUserId)
        isFixtureReady = true
    }

    private var fixtureLoadingView: some View {
        Color.appBackground
            .ignoresSafeArea()
            .accessibilityIdentifier("ui-test-fixture-loading")
    }

    @ViewBuilder
    private func chartScenario(
        chartData: [MetricChartDataPoint],
        metricEntries: MetricEntriesPayload?
    ) -> some View {
        ZStack(alignment: .bottom) {
            FullMetricChartView(
                title: "Weight",
                icon: "figure.stand",
                iconColor: .metricAccentWeight,
                currentValue: chartData.isEmpty ? "–" : "72.0",
                unit: "kg",
                currentDate: "Today",
                chartData: chartData,
                onAdd: { didRequestChartEntry = true },
                metricEntries: metricEntries,
                goalValue: 70,
                selectedTimeRange: $selectedChartRange
            )

            if didRequestChartEntry {
                Text("Chart add requested")
                    .accessibilityIdentifier("chart-add-requested")
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 16)
            }
        }
    }

    private var chartFixtureData: [MetricChartDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<31).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }

            return MetricChartDataPoint(
                date: date,
                value: 72 - Double(offset) * 0.05,
                isEstimated: offset == 14
            )
        }
    }

    private var chartFixtureEntries: MetricEntriesPayload {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entries = [
            MetricHistoryEntry(
                id: "chart-entry-today",
                date: today,
                primaryValue: 72,
                secondaryValue: 18,
                source: .manual
            ),
            MetricHistoryEntry(
                id: "chart-entry-week",
                date: calendar.date(byAdding: .day, value: -7, to: today) ?? today,
                primaryValue: 72.4,
                secondaryValue: 18.2,
                source: .healthKit
            ),
            MetricHistoryEntry(
                id: "chart-entry-month",
                date: calendar.date(byAdding: .day, value: -28, to: today) ?? today,
                primaryValue: 73.5,
                secondaryValue: 18.8,
                source: .integration(id: "scale")
            )
        ]
        let configuration = MetricEntriesConfiguration(
            metricType: .weight,
            unitLabel: "kg",
            secondaryUnitLabel: "%",
            primaryFormatter: makeMetricFormatter(minFractionDigits: 1, maxFractionDigits: 1),
            secondaryFormatter: makeMetricFormatter(minFractionDigits: 1, maxFractionDigits: 1)
        )

        return MetricEntriesPayload(config: configuration, entries: entries)
    }
}

@MainActor
private final class SecuritySessionFixture: ObservableObject {
    @Published private(set) var sessions: [SessionInfo]

    init() {
        let now = Date()
        sessions = [
            SessionInfo(
                id: "ui-test-current-device",
                deviceName: "iPhone 16",
                deviceType: "iPhone",
                location: "San Francisco, CA",
                ipAddress: "192.0.2.10",
                lastActiveAt: now,
                createdAt: now.addingTimeInterval(-86_400),
                isCurrentSession: true
            ),
            SessionInfo(
                id: "ui-test-secondary-device",
                deviceName: "MacBook Pro",
                deviceType: "Mac",
                location: "Oakland, CA",
                ipAddress: "198.51.100.9",
                lastActiveAt: now.addingTimeInterval(-3_600),
                createdAt: now.addingTimeInterval(-172_800),
                isCurrentSession: false
            )
        ]
    }

    func revoke(sessionId: String) {
        sessions.removeAll { $0.id == sessionId }
    }
}

private enum UITestEmailVerificationError: Error {
    case invalidCode
}
