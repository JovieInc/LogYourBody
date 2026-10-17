//
// LogYourBodyApp.swift
// LogYourBody
//
import SwiftUI
import AppIntents
import CoreData
#if DEBUG
import Foundation
#endif

enum LogYourBodyDeepLink {
    enum Destination: Equatable {
        case entry(tab: Int)
    }

    private static let universalLinkHosts: Set<String> = [
        "logyourbody.com",
        "www.logyourbody.com"
    ]

    static func destination(for url: URL) -> Destination? {
        if isCustomScheme(url) {
            guard url.host?.lowercased() == "log" else { return nil }
            return entryDestination(from: Array(url.pathComponents.dropFirst()))
        }

        if isUniversalLink(url) {
            let pathComponents = Array(url.pathComponents.dropFirst())
            guard pathComponents.first?.lowercased() == "log" else { return nil }
            return entryDestination(from: Array(pathComponents.dropFirst()))
        }

        return nil
    }

    static func isOAuthCallback(_ url: URL) -> Bool {
        guard isCustomScheme(url) else { return false }
        let host = url.host?.lowercased()
        return host == "oauth" || host == "oauth-callback"
    }

    private static func isCustomScheme(_ url: URL) -> Bool {
        url.scheme == "logyourbody"
    }

    private static func isUniversalLink(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else {
            return false
        }
        return universalLinkHosts.contains(host)
    }

    private static func entryDestination(from pathComponents: [String]) -> Destination {
        switch pathComponents.first?.lowercased() {
        case "bodyfat":
            return .entry(tab: 1)
        case "photo":
            return .entry(tab: 2)
        default:
            return .entry(tab: 0)
        }
    }
}

enum EntryDeepLinkRoutingPolicy {
    struct PendingDestination: Equatable {
        let destination: LogYourBodyDeepLink.Destination
        let userId: String?
        let receivedAt: Date
    }

    enum Action: Equatable {
        case open(LogYourBodyDeepLink.Destination)
        case store(LogYourBodyDeepLink.Destination)
        case keepPending
        case ignore
    }

    static let pendingLinkTTL: TimeInterval = 120

    static func canStoreForLater(isAuthProviderLoaded: Bool, isAuthenticated: Bool) -> Bool {
        !isAuthProviderLoaded || isAuthenticated
    }

    static func action(
        for destination: LogYourBodyDeepLink.Destination?,
        canOpenNow: Bool,
        canStoreForLater: Bool
    ) -> Action {
        guard let destination else { return .ignore }

        if canOpenNow {
            return .open(destination)
        }

        return canStoreForLater ? .store(destination) : .ignore
    }

    static func actionForStoredDestination(
        _ pendingDestination: PendingDestination?,
        currentUserId: String?,
        canOpenNow: Bool,
        canStoreForLater: Bool,
        now: Date,
        ttl: TimeInterval = pendingLinkTTL
    ) -> Action {
        guard let pendingDestination else { return .ignore }

        if now.timeIntervalSince(pendingDestination.receivedAt) > ttl {
            return .ignore
        }

        if let pendingUserId = pendingDestination.userId,
           let currentUserId,
           pendingUserId != currentUserId {
            return .ignore
        }

        if canOpenNow {
            return .open(pendingDestination.destination)
        }

        return canStoreForLater ? .keepPending : .ignore
    }
}

private struct PersistentStoreLoadingView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ProgressView("Preparing your data…")
                .tint(.white)
                .foregroundStyle(.white)
        }
        .accessibilityIdentifier("persistent_store_loading_view")
    }
}

private struct PersistentStoreRecoveryView: View {
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 42))
                    .foregroundStyle(Color.appWarning)
                    .accessibilityHidden(true)

                Text("Your data couldn’t be opened")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Your existing data has not been changed. Try again, then contact support if the problem continues.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("persistent_store_retry_button")
            }
            .padding(28)
        }
        .foregroundStyle(.white)
        .accessibilityIdentifier("persistent_store_recovery_view")
    }
}

#if DEBUG
/// Test-only viewport constraint used to exercise layouts narrower than the
/// iOS 26 simulator device catalog exposes. It is activated only by a UI-test
/// launch argument and never changes a production build or user layout.
private struct UITestViewportModifier: ViewModifier {
    private var requestedWidth: CGFloat? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-lybUITestViewportWidth"),
              arguments.indices.contains(index + 1),
              let value = Double(arguments[index + 1]),
              value > 0 else {
            return nil
        }

        return CGFloat(value)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let requestedWidth {
            content
                .frame(width: requestedWidth)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("lyb_ui_test_viewport")
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}
#endif

@main
struct LogYourBodyApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var healthKitManager: HealthKitManager
    @StateObject private var realtimeSyncManager: RealtimeSyncManager
    @StateObject private var bugReportManager = BugReportManager.shared
    @State private var showAddEntrySheet = false
    @State private var selectedEntryTab = 0
    @State private var pendingEntryDeepLinkDestination: EntryDeepLinkRoutingPolicy.PendingDestination?

    @StateObject private var persistenceController = CoreDataManager.shared

    #if DEBUG
    private let correctionFixtureGraph: HomeV2CorrectionFixtureGraph?
    @State private var correctionFixtureBoot = HomeV2CorrectionFixtureBoot()
    #endif

    private static var isRunningUnitTests: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITestFixture = arguments.contains { $0.hasPrefix("-lybUITest") }
        return !isUITestFixture &&
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestHomeV2CorrectionIsolationFixture") {
            guard let nonce = HomeV2CorrectionFixtureGraph.requestedNonce(
                arguments: ProcessInfo.processInfo.arguments,
                environment: ProcessInfo.processInfo.environment
            ) else {
                preconditionFailure("Correction fixture requires an admitted XCTest session and nonce")
            }
            // A selected fixture must never fall back to a live graph on configuration failure.
            let graph: HomeV2CorrectionFixtureGraph
            do {
                precondition(!SubscriptionManager.shared.isConfigured, "Fixture requires an unconfigured purchasing SDK")
                graph = try HomeV2CorrectionFixtureGraph(nonce: nonce, authManager: .shared)
            } catch {
                preconditionFailure("Correction fixture graph configuration failed")
            }
            correctionFixtureGraph = graph
            _healthKitManager = StateObject(wrappedValue: graph.healthKitManager)
            _realtimeSyncManager = StateObject(wrappedValue: graph.realtimeSyncManager)
        } else {
            correctionFixtureGraph = nil
            _healthKitManager = StateObject(wrappedValue: HealthKitManager.shared)
            _realtimeSyncManager = StateObject(wrappedValue: RealtimeSyncManager.shared)
        }
        #else
        _healthKitManager = StateObject(wrappedValue: HealthKitManager.shared)
        _realtimeSyncManager = StateObject(wrappedValue: RealtimeSyncManager.shared)
        #endif
        LaunchMetrics.begin()
        LogYourBodyAppShortcuts.updateAppShortcutParameters()
        #if DEBUG
        FrameHitchMonitor.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            switch persistenceController.persistentStoreLoadState {
            case .ready:
                appContent
#if DEBUG
                .modifier(UITestViewportModifier())
#endif
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .environmentObject(authManager)
                .environmentObject(realtimeSyncManager)
                .environmentObject(subscriptionManager)
                .environmentObject(bugReportManager)
                .sheet(isPresented: $bugReportManager.isPromptPresented) {
                    BugReportPromptSheet()
                        .environmentObject(bugReportManager)
                }
                .fullScreenCover(isPresented: $bugReportManager.isFormPresented) {
                    BugReportFormView()
                        .environmentObject(bugReportManager)
                }
                .sheet(isPresented: $showAddEntrySheet) {
                    AddEntrySheet(isPresented: $showAddEntrySheet, initialTab: selectedEntryTab)
                        .environmentObject(authManager)
                        .onAppear {
                            // Set the selected tab based on deep link
                            if let tab = UserDefaults.standard.object(forKey: Constants.pendingEntryTabKey) as? Int {
                                selectedEntryTab = tab
                                UserDefaults.standard.removeObject(forKey: Constants.pendingEntryTabKey)
                            }
                        }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .task {
                    // Hosted unit tests launch the app process to load the test
                    // bundle. Do not let real startup race test-owned Keychain
                    // fixtures or external-service stubs in that environment.
                    guard !Self.isRunningUnitTests else { return }
#if DEBUG
                    guard !ProcessInfo.processInfo.arguments.contains("-lybUITestTrainingFixture"),
                          !ProcessInfo.processInfo.arguments.contains("-lybUITestCanvasFixture") else { return }
                    if correctionFixtureGraph != nil {
                        guard correctionFixtureBoot.begin() else { return }
                    }
#endif
                    await performStartupSequence()
                    resolvePendingEntryDeepLinkIfPossible()
                }
                .onChange(of: authManager.isAuthProviderLoaded) { _, _ in
                    resolvePendingEntryDeepLinkIfPossible()
                }
                .onChange(of: authManager.isAuthenticated) { _, _ in
                    resolvePendingEntryDeepLinkIfPossible()
                }
                .onChange(of: authManager.currentUser?.id) { _, _ in
                    resolvePendingEntryDeepLinkIfPossible()
                }
                .onChange(of: authManager.currentUser?.profile?.onboardingCompleted) { _, _ in
                    resolvePendingEntryDeepLinkIfPossible()
                }
                .onChange(of: subscriptionManager.isSubscribed) { _, _ in
                    resolvePendingEntryDeepLinkIfPossible()
                }
                .onReceive(NotificationCenter.default.publisher(for: OnboardingStateManager.onboardingStateDidChange)) { _ in
                    resolvePendingEntryDeepLinkIfPossible()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // App entering background - ensure sync is complete
                    realtimeSyncManager.syncIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // App entering foreground - refresh data
                    Task {
                        await bootstrapHealthKit()

                        if healthKitManager.isAuthorized {
                            try? await selectedHealthSyncCoordinator.syncStepsFromHealthKit()
                        }
                    }
                }
            case .loading:
                PersistentStoreLoadingView()
            case .failed:
                PersistentStoreRecoveryView(
                    retry: persistenceController.retryPersistentStoreLoad
                )
            }
        }
    }

    @ViewBuilder
    private var appContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestCanvasFixture") {
            MesocycleCanvasFixtureView()
        } else if ProcessInfo.processInfo.arguments.contains("-lybUITestTrainingFixture") {
            TrainingLiveSessionFixtureView()
        } else if let graph = correctionFixtureGraph {
            if correctionFixtureBoot.isReady {
                ContentView(
                    loadingManager: graph.loadingManager, dashboardViewModel: graph.dashboardViewModel,
                    analyticsTracker: graph.analyticsService
                )
                .environment(\.homeV2CorrectionFixtureHold, graph.heldCorrection)
                .environment(\.homeV2CorrectionFixtureGraph, graph)
                .overlay(alignment: .topTrailing) {
                    HomeV2CorrectionFixtureFailureControl(graph: graph, scope: "app")
                }
            } else {
                PersistentStoreLoadingView()
                    .overlay(alignment: .topTrailing) {
                        HomeV2CorrectionFixtureFailureControl(graph: graph, scope: "boot")
                    }
            }
        } else {
            ContentView()
        }
#else
        ContentView()
#endif
    }

    // MARK: - Startup Helpers

    @MainActor
    private func performStartupSequence() async {
        #if DEBUG
        if applySignedOutUITestFixtureIfNeeded() {
            return
        }

        if await applyPaidMVPUITestFixtureIfNeeded() {
            return
        }
        #endif

        scheduleDeferredMaintenance()

        AppServicePorts.errorTracker.start()

        AppServicePorts.analyticsTracker.start()
        AppServicePorts.analyticsTracker.track(event: "app_open")

        let authInitializationTask = authManager.ensureAuthInitializationTask(priority: .userInitiated)

        Task { @MainActor in
            await configureSubscriptions(waitingFor: authInitializationTask)
        }

        Task { @MainActor in
            await authInitializationTask.value
            await bootstrapHealthKit()
        }

        await authInitializationTask.value
    }

    @MainActor
    private func configureSubscriptions(waitingFor authTask: Task<Void, Never>) async {
        let apiKey = Constants.revenueCatAPIKey
        guard !apiKey.isEmpty else { return }

        subscriptionManager.configure(apiKey: apiKey)

        await authTask.value

        // AuthManager's bound lifecycle owns every account transition, including cold restore.
        await subscriptionManager.waitForBillingReconciliation()
    }

    private var selectedHealthSyncCoordinator: HealthSyncCoordinating {
        #if DEBUG
        if let graph = correctionFixtureGraph { return graph.healthSyncCoordinator }
        #endif
        return HealthSyncCoordinator.shared
    }

    @MainActor
    private func bootstrapHealthKit() async {
        #if DEBUG
        if let graph = correctionFixtureGraph {
            graph.healthSyncCoordinator.bootstrapIfNeeded(
                syncEnabled: graph.defaults.bool(forKey: Constants.healthKitSyncEnabledKey)
            )
            return
        }
        #endif
        let syncEnabled = UserDefaults.standard.bool(forKey: Constants.healthKitSyncEnabledKey)
        HealthKitAccountSyncPolicy.bindIfUnbound(
            userId: authManager.currentUser?.id,
            syncEnabled: syncEnabled,
            defaults: .standard
        )
        HealthSyncCoordinator.shared.bootstrapIfNeeded(syncEnabled: syncEnabled)
    }

    @MainActor
    private func scheduleDeferredMaintenance() {
        Task.detached(priority: .utility) {
            let repairedCount = await CoreDataManager.shared.repairCorruptedEntries()
            if repairedCount > 0 {
                // print("🔧 App startup: Repaired \(repairedCount) corrupted entries")
            }
        }

        Task.detached(priority: .utility) {
            AppVersionManager.shared.performStartupMaintenance()
        }

        MetricChartDataHelper.setupCacheInvalidation()
    }

    #if DEBUG
    @MainActor
    @discardableResult
    private func applySignedOutUITestFixtureIfNeeded() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("-lybUITestSignedOutFixture") else {
            return false
        }

        authManager.applySignedOutUITestFixture()
        subscriptionManager.isSubscribed = false
        subscriptionManager.customerInfo = nil
        subscriptionManager.currentOffering = nil
        subscriptionManager.errorMessage = nil
        subscriptionManager.isPurchasing = false

        return true
    }

    @MainActor
    @discardableResult
    private func applyPaidMVPUITestFixtureIfNeeded() async -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-lybUITestResetWhatsNewReviewState") {
            ReleaseReviewStateStore().reset()
        }
        if arguments.contains("-lybUITestResetHomeV2TimelineCoach") {
            UserDefaults.standard.removeObject(forKey: HomeV2Copy.coachDismissedDefaultsKey)
        }
        let usesPaidFixture = arguments.contains("-lybUITestPaidMVPFixture")
        let usesWeightLoggerFixture = arguments.contains("-lybUITestWeightLoggerMVPFixture")
        let usesPaywallFixture = arguments.contains("-lybUITestPaywallFixture")
        let usesPaywallPlansFixture = arguments.contains("-lybUITestPaywallPlansFixture")
        let usesFullDashboardFixture = arguments.contains("-lybUITestFullDashboardFixture")
        let usesPhotoTimelineHUDFixture = arguments.contains("-lybUITestPhotoTimelineHUDFixture")
        let usesBodyScoreOnboardingFixture = arguments.contains("-lybUITestBodyScoreOnboardingFixture") ||
            arguments.contains("-lybUITestBodyScoreFirstPhotoFixture")
        let usesDailyReminderPromptFixture = arguments.contains("-lybUITestDailyReminderPromptFixture")

        guard usesPaidFixture || usesWeightLoggerFixture || usesPaywallFixture || usesPaywallPlansFixture ||
            usesFullDashboardFixture || usesPhotoTimelineHUDFixture || usesBodyScoreOnboardingFixture else {
            return false
        }

        let isSubscribed = usesPaidFixture ||
            usesWeightLoggerFixture ||
            usesFullDashboardFixture ||
            usesPhotoTimelineHUDFixture ||
            usesBodyScoreOnboardingFixture
        let fixtureName: String
        let fixtureEmail: String
        let fixtureUsername: String
        if usesBodyScoreOnboardingFixture {
            fixtureName = "Onboarding UI"
            fixtureEmail = "onboarding-ui@example.com"
            fixtureUsername = "onboarding_ui"
        } else if usesPhotoTimelineHUDFixture {
            fixtureName = "Photo HUD UI"
            fixtureEmail = "photo-hud-ui@example.com"
            fixtureUsername = "photo_hud_ui"
        } else if usesFullDashboardFixture {
            fixtureName = "Full Dashboard UI"
            fixtureEmail = "full-dashboard-ui@example.com"
            fixtureUsername = "full_dashboard_ui"
        } else if usesWeightLoggerFixture {
            fixtureName = "Weight Logger UI"
            fixtureEmail = "weight-logger-ui@example.com"
            fixtureUsername = "weight_logger_ui"
        } else if isSubscribed {
            fixtureName = "Paid MVP UI"
            fixtureEmail = "paid-mvp-ui@example.com"
            fixtureUsername = "paid_mvp_ui"
        } else {
            fixtureName = "Paywall UI"
            fixtureEmail = "paywall-ui@example.com"
            fixtureUsername = "paywall_ui"
        }
        let fixtureSlug: String
        if usesBodyScoreOnboardingFixture {
            fixtureSlug = "onboarding"
        } else if usesPhotoTimelineHUDFixture {
            fixtureSlug = "photo_hud"
        } else if usesFullDashboardFixture {
            fixtureSlug = "full_dashboard"
        } else if usesWeightLoggerFixture {
            fixtureSlug = "weight_logger"
        } else {
            fixtureSlug = isSubscribed ? "paid_mvp" : "paywall"
        }
        let usesUndoPhotoFixture = arguments.contains("-lybUITestHomeV2UndoPhotoOnlyFixture")
        let undoFixtureAccount = ProcessInfo.processInfo.environment["LYB_UI_TEST_UNDO_ACCOUNT"]
            .flatMap(UUID.init(uuidString:))
        let fixtureAccount = usesUndoPhotoFixture ? undoFixtureAccount ?? UUID() : UUID()
        let userId = "ui_test_\(fixtureSlug)_user_\(fixtureAccount.uuidString)"
        let profile = UserProfile(
            id: userId,
            email: fixtureEmail,
            username: fixtureUsername,
            fullName: fixtureName,
            dateOfBirth: Calendar.current.date(from: DateComponents(year: 1_990, month: 1, day: 1)),
            height: 178,
            heightUnit: "cm",
            gender: "male",
            activityLevel: "active",
            goalWeight: nil,
            goalWeightUnit: "kg",
            onboardingCompleted: !usesBodyScoreOnboardingFixture
        )
        if isSubscribed && !usesDailyReminderPromptFixture {
            NotificationManager.shared.skipDailyWeighInPrompt()
        } else if usesDailyReminderPromptFixture {
            NotificationManager.shared.resetDailyWeighInPromptForUITests()
        }

        UserDefaults.standard.set(
            MeasurementSystem.imperial.rawValue,
            forKey: Constants.preferredMeasurementSystemKey
        )
        // UI fixtures must not inherit a goal saved by a prior test process. The
        // weight-goal editor intentionally starts empty in this fixture so its
        // validation and disabled-save state remain reproducible.
        UserDefaults.standard.removeObject(forKey: Constants.goalWeightKilogramsKey)
        UserDefaults.standard.removeObject(forKey: Constants.goalWeightKey)
        OnboardingStateManager.shared.updateCompletionStatus(!usesBodyScoreOnboardingFixture)

        realtimeSyncManager.isOnline = false
        realtimeSyncManager.syncStatus = .offline
        realtimeSyncManager.pendingSyncCount = 0

        // These data-only aliases exercise the ordinary Home policy without
        // the HomeV2 fixture arguments that force a particular rollout state.
        let usesEmptyHomeData = arguments.contains(HomeV2Policy.emptyFixtureArgument) ||
            arguments.contains("-lybUITestPhotoTimelineEmptyFixture")
        if (usesFullDashboardFixture || usesPhotoTimelineHUDFixture) && !usesEmptyHomeData {
            let usesPhotoData = arguments.contains(HomeV2Policy.photoFixtureArgument) ||
                arguments.contains("-lybUITestPhotoTimelinePhotoFixture")
            let fixturePhotoURL = usesPhotoData ? writeHomeV2FixturePhoto(fixtureUserId: userId) : nil
            if usesUndoPhotoFixture && arguments.contains("-lybUITestReuseUndoFixtureData") {
                let persisted = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
                precondition(!persisted.isEmpty, "Undo relaunch must read persisted rows without reseeding")
            } else {
                await seedFullDashboardUITestFixtureData(userId: userId, photoURL: fixturePhotoURL)
            }
        }

        if arguments.contains("-lybUITestGlp1WeeklyCheckInFixture") &&
            !arguments.contains("-lybUITestGlp1EmptyMedicationFixture") {
            await seedGlp1WeeklyCheckInUITestFixtureData(userId: userId)
        }

        // Publish the authenticated fixture only after its data and service
        // state are ready. Otherwise the dashboard can load a partially seeded
        // history while the remaining Core Data saves are still suspended.
        authManager.currentUser = User(
            id: userId,
            email: fixtureEmail,
            name: fixtureName,
            profile: profile,
            onboardingCompleted: !usesBodyScoreOnboardingFixture
        )
        authManager.authSession = .localFixture(
            subject: userId,
            email: fixtureEmail,
            name: fixtureName
        )
        authManager.isAuthProviderLoaded = true

        // Auth publication synchronously invalidates the previous billing owner.
        // Install the synthetic UI-test state afterward, without yielding or
        // configuring the live purchasing SDK.
        subscriptionManager.isSubscribed = isSubscribed
        subscriptionManager.customerInfo = nil
        subscriptionManager.currentOffering = nil
        subscriptionManager.errorMessage = nil
        subscriptionManager.isPurchasing = false
        if usesPaywallFixture {
            subscriptionManager.applyCachedPaywallOfferingUITestFixture()
        } else if usesPaywallPlansFixture {
            subscriptionManager.applyPaywallPlansUITestFixture()
        }
        UserDefaults.standard.set(isSubscribed, forKey: Constants.revenueCatIsSubscribedKey)

        if correctionFixtureGraph != nil {
            // Initial admission only. Later receipt invalidation closes old Context/editor,
            // but never resets this gate or recreates the mounted MainTab/HUD root.
            let originalOwnership = authManager.captureAccountSession()
            let context = persistenceController.viewContext
            let seededRows = await HomeV2CorrectionFixtureBoot.readSeededRows(for: userId, context: context)
            guard !Task.isCancelled, let originalOwnership,
                  authManager.ownsAccountSession(originalOwnership),
                  authManager.currentUser?.id == userId, subscriptionManager.isSubscribed,
                  !subscriptionManager.isConfigured else { return true }
            if correctionFixtureBoot.admitGeneratedOwner(
                userId, ownership: originalOwnership, seededRows: seededRows
            ) {
                correctionFixtureGraph?.heldCorrection.bindInitialOwner(originalOwnership)
            }
        }
        return true
    }

    /// A deterministic 4:5 "photo" so the photo-first Home is testable without a
    /// network: a soft gradient with a darker figure in the middle.
    private func writeHomeV2FixturePhoto(variant: Int? = nil, fixtureUserId: String? = nil) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        let option = "-lybUITestHomeV2TimelinePhotoCalibration"
        let hasFixtureSession = arguments.contains("-lybUITestPhotoTimelineHUDFixture") &&
            arguments.contains("-lybUITestHomeV2TimelineFixture") &&
            BiometricLockPolicy.shouldDisableForUITests(
                arguments: arguments, environment: ProcessInfo.processInfo.environment,
                userId: fixtureUserId
            )
        let requested = arguments.firstIndex(of: option).flatMap { index in
            arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
        }
        let calibration = hasFixtureSession && ["0", "7", "gray", "blank"].contains(requested ?? "")
            ? requested : nil
        let effectiveVariant = calibration == "gray" ? nil : calibration.flatMap(Int.init) ?? variant
        let size = CGSize(width: 400, height: 500)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            if calibration == "blank" {
                UIColor.black.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                return
            }
            let palette: [Int: UIColor] = [0: .red, 7: .blue, 14: .green, 21: .purple, 35: .orange]
            let tint = effectiveVariant.flatMap { palette[$0] }
            let colors = [(tint ?? .lightGray).cgColor, (tint ?? .darkGray).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: 0, y: size.height),
                    options: []
                )
            }
            // DEBUG-only independent photo identity remains visible after subject-plate treatment.
            let identityCodes = [0: 0b101, 7: 0b011, 14: 0b110, 21: 0b100, 35: 0b001]
            if let effectiveVariant, let code = identityCodes[effectiveVariant] {
                for (index, x) in [0.0, 155.0, 310.0].enumerated() {
                    ((code & (1 << (2 - index))) == 0 ? UIColor.black : UIColor.white).setFill()
                    context.fill(CGRect(x: x, y: 0, width: 90, height: 80))
                }
            }
            UIColor.black.withAlphaComponent(0.85).setFill()
            UIBezierPath(roundedRect: CGRect(x: 150, y: 90, width: 100, height: 360), cornerRadius: 48).fill()
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        let suffix = effectiveVariant.map { "-\($0)" } ?? ""
        // Both existing image caches key by URL, not image bytes; never reuse the old unmarked URL.
        let identityVersion = calibration.map { "-identity-v1-calibration-\($0)" } ??
            (effectiveVariant == nil ? "" : "-identity-v1")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyb-ui-test-home-v2-photo\(suffix)\(identityVersion).jpg")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return url.absoluteString
    }

    private func seedFullDashboardUITestFixtureData(userId: String, photoURL: String? = nil) async {
        let calendar = Calendar.current
        let now = Date()
        if ProcessInfo.processInfo.arguments.contains("-lybUITestHomeV2HistoricalOnlyFixture") {
            await seedHistoricalWeightUITestFixtureData(userId: userId, calendar: calendar, now: now)
            return
        }
        guard let expectedMetricIDs = try? await UITestFixtureIsolation.seedDashboardMetrics(
            userId: userId, photoURL: photoURL, now: Date(),
            timelinePhoto: { writeHomeV2FixturePhoto(variant: $0, fixtureUserId: userId) }
        ) else {
            preconditionFailure("Dashboard UI fixture could not persist its measurements")
        }
        let savedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        let savedIds = savedMetrics.compactMap { $0.toBodyMetrics()?.id }
        let expectedIds = Set(expectedMetricIDs)
        precondition(
            savedIds.count == expectedIds.count && Set(savedIds) == expectedIds,
            "Dashboard UI fixture expected \(expectedIds.count) saved measurements, found \(savedIds.count)"
        )
        if ProcessInfo.processInfo.arguments.contains("-lybUITestHomeV2StepsFixture") {
            await seedHomeV2StepsUITestFixtureData(userId: userId, metrics: savedMetrics.compactMap { $0.toBodyMetrics() })
        }
    }

    /// Opt-in real saved totals for the selected today and preceding timeline entry.
    private func seedHomeV2StepsUITestFixtureData(userId: String, metrics: [BodyMetrics]) async {
        let entries = [(daysAgo: 0, steps: 6_000), (daysAgo: 7, steps: 8_000)]
        for entry in entries {
            guard let metric = metrics.first(where: {
                $0.userId == userId && $0.id == "ui_test_full_dashboard_metric_\(entry.daysAgo)"
            }) else {
                preconditionFailure("Steps UI fixture requires the full dashboard's today and seven-days-ago entries")
            }
            let daily = DailyMetrics(
                id: "\(userId)_daily_steps_\(entry.daysAgo)",
                userId: userId,
                date: metric.date,
                steps: entry.steps,
                notes: "Selected-day steps UI fixture",
                createdAt: metric.createdAt,
                updatedAt: metric.updatedAt
            )
            do {
                try await CoreDataManager.shared.saveDailyMetricsAndWait(daily, userId: userId)
            } catch {
                preconditionFailure("Steps UI fixture could not save its daily row")
            }
            let saved = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: metric.date)
            precondition(
                saved?.id == daily.id && saved?.userId == userId && saved?.steps == Int32(entry.steps),
                "Steps UI fixture expected its saved owner/day total before authentication"
            )
        }
    }

    private func seedHistoricalWeightUITestFixtureData(
        userId: String,
        calendar: Calendar,
        now: Date
    ) async {
        UserDefaults.standard.set(
            MeasurementSystem.metric.rawValue,
            forKey: Constants.preferredMeasurementSystemKey
        )
        let day = calendar.date(from: DateComponents(year: 2_018, month: 11, day: 2)) ?? now
        let samples: [(id: String, hour: Int, minute: Int, weight: Double)] = [
            ("morning", 7, 2, 18),
            ("evening", 19, 4, 17.99)
        ]

        for sample in samples {
            let date = calendar.date(
                bySettingHour: sample.hour,
                minute: sample.minute,
                second: 0,
                of: day
            ) ?? day
            let metric = BodyMetrics(
                id: "\(userId)_historical_\(sample.id)",
                userId: userId,
                date: date,
                weight: sample.weight,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: "Imported from Apple Health",
                photoUrl: nil,
                dataSource: BodyMetricSource.healthKit.rawValue,
                sourceMetadata: BodyMetricSourceMetadata(
                    vendor: "healthkit",
                    sourceName: "Withings",
                    sourceBundleId: "com.withings.wiScaleNG",
                    sampleId: "historical-\(sample.id)",
                    quantityType: "HKQuantityTypeIdentifierBodyMass"
                ),
                createdAt: now,
                updatedAt: now
            )
            try? await CoreDataManager.shared.saveBodyMetricsAndWait(
                metric,
                userId: userId,
                markAsSynced: true
            )
        }

        let savedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        let savedIds = Set(savedMetrics.compactMap { $0.toBodyMetrics()?.id })
        let expectedIds = Set(samples.map { "\(userId)_historical_\($0.id)" })
        precondition(savedIds == expectedIds, "Historical UI fixture did not save both source samples")
    }

    private func seedGlp1WeeklyCheckInUITestFixtureData(userId: String) async {
        await CoreDataManager.shared.replaceUITestGlp1WeeklyCheckInFixture(userId: userId)
    }
    #endif

    // MARK: - Deep Link Handling

    @MainActor
    private func handleDeepLink(_ url: URL) {
        if LogYourBodyDeepLink.isOAuthCallback(url) {
            // ASWebAuthenticationSession owns the active OAuth callback.
            return
        }

        if url.isFileURL, url.pathExtension.lowercased() == "pdf" {
            NotificationCenter.default.post(name: .dexaPDFReceived, object: url)
            return
        }

        guard let destination = LogYourBodyDeepLink.destination(for: url) else {
            return
        }

        let action = EntryDeepLinkRoutingPolicy.action(
            for: destination,
            canOpenNow: canOpenEntrySheetFromDeepLink,
            canStoreForLater: canStoreEntryDeepLinkForLater
        )

        applyEntryDeepLinkAction(action)
    }

    @MainActor
    private func resolvePendingEntryDeepLinkIfPossible() {
        let action = EntryDeepLinkRoutingPolicy.actionForStoredDestination(
            pendingEntryDeepLinkDestination,
            currentUserId: authManager.currentUser?.id,
            canOpenNow: canOpenEntrySheetFromDeepLink,
            canStoreForLater: canStoreEntryDeepLinkForLater,
            now: Date()
        )

        applyEntryDeepLinkAction(action)
    }

    @MainActor
    private func applyEntryDeepLinkAction(_ action: EntryDeepLinkRoutingPolicy.Action) {
        switch action {
        case .open(let destination):
            pendingEntryDeepLinkDestination = nil
            openEntryDeepLink(destination)
        case .store(let destination):
            pendingEntryDeepLinkDestination = EntryDeepLinkRoutingPolicy.PendingDestination(
                destination: destination,
                userId: authManager.currentUser?.id,
                receivedAt: Date()
            )
        case .keepPending:
            break
        case .ignore:
            pendingEntryDeepLinkDestination = nil
        }
    }

    @MainActor
    private func openEntryDeepLink(_ destination: LogYourBodyDeepLink.Destination) {
        switch destination {
        case .entry(let tab):
            selectedEntryTab = tab
            UserDefaults.standard.set(tab, forKey: Constants.pendingEntryTabKey)
            showAddEntrySheet = true
        }
    }

    private var canStoreEntryDeepLinkForLater: Bool {
        EntryDeepLinkRoutingPolicy.canStoreForLater(
            isAuthProviderLoaded: authManager.isAuthProviderLoaded,
            isAuthenticated: authManager.isAuthenticated
        )
    }

    private var canOpenEntrySheetFromDeepLink: Bool {
        let user = authManager.currentUser

        return EntryDeepLinkPolicy.canOpenEntrySheet(
            isAuthenticated: authManager.isAuthenticated,
            user: user,
            hasCompletedOnboarding: OnboardingStateManager.shared.hasCompletedCurrentVersion(for: user?.id),
            isSubscribed: subscriptionManager.isSubscribed
        )
    }
}


#if DEBUG
enum UITestFixtureIsolation {
    static let dashboardMetricIDs = [0, 7, 14, 21, 35].map { "ui_test_full_dashboard_metric_\($0)" }

    /// UI launches mint a new fixture user but reuse these ids. Production writes
    /// must still refuse a different account; remove only these DEBUG fixture ids.
    @discardableResult
    static func seedDashboardMetrics(
        userId: String, photoURL: String?, now: Date,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        timelinePhoto: ((Int) -> String?)? = nil
    ) async throws -> [String] {
        let calendar = Calendar.current
        let usesUndoPhotoFixture = arguments.contains("-lybUITestHomeV2UndoPhotoOnlyFixture")
        let metricIdPrefix = usesUndoPhotoFixture ? "\(userId)_metric" : "ui_test_full_dashboard_metric"
        let selectedFixtureFlags = [
            "-lybUITestHomeV2SelectedMissingWeightFixture",
            "-lybUITestHomeV2SelectedBodyFatOnlyFixture",
            "-lybUITestHomeV2InferredWeightZeroPriorFixture",
            "-lybUITestHomeV2InferredWeightOnePriorFixture"
        ].filter(arguments.contains)
        guard selectedFixtureFlags.count <= 1 else {
            throw NSError(domain: "HomeV2SelectedFixture", code: 1)
        }
        let entries: [
            (daysAgo: Int, weight: Double?, bodyFat: Double?, muscle: Double, notes: String, source: String)
        ]
        switch selectedFixtureFlags.first {
        case .some("-lybUITestHomeV2SelectedMissingWeightFixture"):
            entries = [
                (0, nil, nil, 66.2, "Selected unavailable values", "manual"),
                (7, 80, nil, 66.0, "Past weight is not a selected value", "manual")
            ]
        case .some("-lybUITestHomeV2SelectedBodyFatOnlyFixture"):
            entries = [(0, nil, 20, 66.2, "Selected body fat only", "manual")]
        case .some("-lybUITestHomeV2InferredWeightZeroPriorFixture"):
            entries = [
                (-10, 90, 20, 66.2, "Future weight anchor", "healthkit"),
                (0, nil, 20, 66.2, "Selected inferred weight with zero past chart samples", "manual"),
                (40, 80, 20, 66.0, "Past weight anchor outside the chart window", "manual")
            ]
        case .some("-lybUITestHomeV2InferredWeightOnePriorFixture"):
            entries = [
                (-10, 84, 20, 66.2, "Future weight anchor", "healthkit"),
                (0, nil, 20, 66.2, "Selected inferred weight with one past chart sample", "manual"),
                (10, 80, 20, 66.0, "Past weight anchor", "manual")
            ]
        default:
            entries = [
                (0, 82.1, 15.8, 66.2, "Latest check-in", "manual"),
                (7, 82.8, 16.2, 66.0, "Weekly check-in", "healthkit"),
                (14, 83.4, nil, 65.9, "Weight-only import", "healthkit"),
                (21, 84.0, 16.9, 65.7, "DEXA baseline", "bodyspec_dexa"),
                (35, 84.7, 17.4, 65.4, "Manual baseline", "manual")
            ]
        }
        // Only the same existing DEBUG fixture ids are cleared, including this scenario's distinct anchor days.
        let staleDays = Set([0, 7, 14, 21, 35] + entries.map(\.daysAgo))
        try await removeBodyMetrics(ids: staleDays.map { "\(metricIdPrefix)_\($0)" })

        let editorialArguments = arguments
        let usesWeightOnlyHero = editorialArguments.contains("-lybUITestHomeV2WeightOnlyHeroFixture")
        let usesSingleWeightHero = editorialArguments.contains("-lybUITestHomeV2SingleWeightHeroFixture")
        let usesWeightReviewHero = editorialArguments.contains("-lybUITestHomeV2WeightReviewHeroFixture")
        let usesWeightReviewHistory = usesWeightReviewHero &&
            editorialArguments.contains("-lybUITestHomeV2WeightReviewHistoryFixture")
        guard !editorialArguments.contains("-lybUITestHomeV2WeightReviewHistoryFixture") ||
                usesWeightReviewHero else { throw NSError(domain: "HomeV2SelectedFixture", code: 2) }
        let usesSingleReading = usesSingleWeightHero || (usesWeightReviewHero && !usesWeightReviewHistory) ||
            editorialArguments.contains("-lybUITestHomeV2SingleReadingFixture")
        let usesVisualEstimateHero = editorialArguments.contains("-lybUITestHomeV2EstimateHeroFixture")
        for entry in entries {
            if usesSingleReading && entry.daysAgo != 0 { continue }
            guard let date = calendar.date(byAdding: .day, value: -entry.daysAgo, to: now) else {
                continue
            }

            let timelinePhotoURL = editorialArguments.contains("-lybUITestHomeV2TimelineFixture")
                ? timelinePhoto?(entry.daysAgo) : photoURL
            let isPhotoOnly = usesUndoPhotoFixture && entry.daysAgo == 0
            let fixturePhotoURL: String?
            if editorialArguments.contains("-lybUITestHomeV2SinglePhotoFixture"), entry.daysAgo != 0 {
                fixturePhotoURL = nil
            } else if editorialArguments.contains("-lybUITestHomeV2ShareMissingPhotoFixture"), entry.daysAgo != 0 {
                fixturePhotoURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lyb-ui-test-missing-share-photo.jpg").absoluteString
            } else {
                fixturePhotoURL = timelinePhotoURL
            }
            let fixtureSource = arguments.contains("-lybUITestHomeV2ImportedCorrectionFixture") && entry.daysAgo == 0
                ? BodyMetricSource.healthKit.rawValue : entry.source
            let metric = BodyMetrics(
                id: "\(metricIdPrefix)_\(entry.daysAgo)",
                userId: userId,
                date: date,
                weight: isPhotoOnly ? nil : (usesWeightReviewHero && entry.daysAgo == 0 ? 18 : entry.weight),
                weightUnit: "kg",
                bodyFatPercentage: usesWeightOnlyHero || usesSingleWeightHero
                        || (usesWeightReviewHero && !usesWeightReviewHistory) || isPhotoOnly
                        ? nil : entry.bodyFat,
                    bodyFatMethod: usesWeightOnlyHero || usesSingleWeightHero
                        || (usesWeightReviewHero && !usesWeightReviewHistory) || isPhotoOnly || entry.bodyFat == nil
                        ? nil : (usesVisualEstimateHero ? "visual_estimate" : fixtureSource),
                muscleMass: isPhotoOnly ? nil : entry.muscle,
                boneMass: nil,
                waistCm: nil,
                hipCm: nil,
                waistUnit: nil,
                notes: entry.notes,
                photoUrl: fixturePhotoURL,
                dataSource: usesWeightReviewHero ? "healthkit" : fixtureSource,
                createdAt: date,
                updatedAt: now
            )

            try await CoreDataManager.shared.saveBodyMetricsAndWait(
                metric,
                userId: userId,
                markAsSynced: usesWeightReviewHero || entry.source != "manual"
            )
        }

        return entries.filter { !usesSingleReading || $0.daysAgo == 0 }
            .map { "\(metricIdPrefix)_\($0.daysAgo)" }
    }

    static func removeBodyMetrics(ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        let context = CoreDataManager.shared.viewContext
        try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids as NSArray)
            let rows = try context.fetch(request)
            rows.forEach(context.delete)
            if context.hasChanges {
                try context.save()
            }
        }
    }
}
#endif

#if DEBUG
/// App-owned DEBUG transport producer; calibration and future fixture graph use this exact factory.
@MainActor
enum HomeV2CorrectionFixtureTransport {
    struct Instance {
        let product: ProductAPIClient
        let endpoint: URL
        let recorder: CorrectionFixtureTaskRecorder
        let session: URLSession
    }

    static func make(
        nonce: UUID, onInvalidated: @escaping @Sendable () -> Void
    ) throws -> Instance {
        let product = ProductAPIClient()
        // Fail before constructing a session if the actual client cannot construct its endpoint.
        let endpoint = try product.productAPIURL("/api/auth/mobile/sync/v1/body-metrics")
        let recorder = CorrectionFixtureTaskRecorder(nonce: nonce, onInvalidated: onInvalidated)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CorrectionFixtureRejectingProtocol.self]
        configuration.urlCredentialStorage = nil
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: recorder, delegateQueue: nil)
        // Assign before this client's lazy default session is ever read.
        product.session = session
        return Instance(product: product, endpoint: endpoint, recorder: recorder, session: session)
    }
}

/// Owned by one calibration session. Mutable records are protected on actual delegate threads.
final class CorrectionFixtureTaskRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    struct TaskRecord {
        let session: ObjectIdentifier
        let taskIdentifier: Int
        let method: String?
        let path: String?
    }

    struct Snapshot {
        let tasks: [TaskRecord]
        let invalidationCount: Int
        let invalidationError: String?
    }

    let nonce: UUID
    private let onInvalidated: @Sendable () -> Void
    private let lock = NSLock()
    private var tasks: [TaskRecord] = []
    private var invalidationCount = 0
    private var invalidationError: String?

    init(nonce: UUID, onInvalidated: @escaping @Sendable () -> Void) {
        self.nonce = nonce
        self.onInvalidated = onInvalidated
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.lock()
        tasks.append(TaskRecord(
            session: ObjectIdentifier(session),
            taskIdentifier: task.taskIdentifier,
            method: task.originalRequest?.httpMethod,
            path: task.originalRequest?.url?.path
        ))
        lock.unlock()
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        lock.lock()
        invalidationCount += 1
        invalidationError = error.map { String(describing: type(of: $0)) }
        lock.unlock()
        onInvalidated()
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            tasks: tasks, invalidationCount: invalidationCount, invalidationError: invalidationError
        )
    }
}

/// No mutable static handler, registry, forwarding session or host fallback.
final class CorrectionFixtureRejectingProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }
    override func stopLoading() {}
}

#endif

#if DEBUG
/// Launch-scoped admission. Once open, generation replacement cannot remount the root.
struct HomeV2CorrectionFixtureBoot {
    private(set) var isReady = false
    private var hasStarted = false

    mutating func begin() -> Bool {
        guard !hasStarted else { return false }
        hasStarted = true
        return true
    }

    /// The App and its owned-store calibration share this exact readback producer.
    @MainActor
    static func readSeededRows(for userId: String, context: NSManagedObjectContext) async -> [BodyMetrics] {
        await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(
                format: "userId == %@ AND isMarkedDeleted == %@", userId, NSNumber(value: false)
            )
            // Convert on the owning context; no managed object escapes this readback.
            guard let rows = try? context.fetch(request) else { return [] }
            let metrics = rows.compactMap { $0.toBodyMetrics() }
            guard metrics.count == rows.count else { return [] }
            return metrics
        }
    }

    mutating func admitGeneratedOwner(
        _ userId: String, ownership: AuthManager.ProfileSessionOwnership?, seededRows: [BodyMetrics]
    ) -> Bool {
        let prefix = "ui_test_photo_hud_user_"
        guard hasStarted, !isReady, userId.hasPrefix(prefix),
              UUID(uuidString: String(userId.dropFirst(prefix.count))) != nil,
              let ownership, ownership.subject == userId, !seededRows.isEmpty,
              seededRows.allSatisfy({ $0.userId == userId }) else { return false }
        isReady = true
        return true
    }
}

/// Only selected existing-source constructors are composed; this is not a provider interceptor.
@MainActor
final class HomeV2CorrectionFixtureGraph: ObservableObject {
    let nonce: UUID
    let defaultsSuiteName: String
    let defaults: UserDefaults
    let transport: HomeV2CorrectionFixtureTransport.Instance
    let healthSyncCoordinator: HomeV2CorrectionFixtureHealthSync
    let healthKitManager: HealthKitManager
    let analyticsClient: HomeV2CorrectionFixtureAnalytics
    let analyticsService: AnalyticsService
    let realtimeSyncManager: RealtimeSyncManager
    let loadingManager: LoadingManager
    let dashboardViewModel: DashboardViewModel
    let heldCorrection: HomeV2CorrectionFixtureHold
    let cleanup: HomeV2CorrectionFixtureCleanup
    @Published private(set) var mainTabIdentities: Set<UUID> = []
    @Published private(set) var hudIdentities: Set<UUID> = []
    @Published private(set) var contexts: [UUID: Bool] = [:]
    @Published private(set) var editors: [UUID: HomeV2CorrectionFixtureEditorObservation] = [:]
    @Published private(set) var publicationOwnership: AuthManager.ProfileSessionOwnership?
    @Published private(set) var publicationRows: [BodyMetrics] = []
    @Published private(set) var commandError: String?
    private var failedCaseCleanupTask: Task<Void, Never>?

    static func requestedNonce(arguments: [String], environment: [String: String]) -> UUID? {
        let hasConfiguration = environment["XCTestConfigurationFilePath"]
            .map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        let hasSession = UUID(uuidString: environment["XCTestSessionIdentifier"] ?? "") != nil &&
            (environment["XCTestBundlePath"]?.hasSuffix("/LogYourBodyUITests.xctest") ?? false)
        guard hasConfiguration || hasSession,
              arguments.contains("-lybUITestPhotoTimelineHUDFixture"),
              arguments.contains("-lybUITestHomeV2TimelineFixture"),
              arguments.contains("-lybUITestHomeV2CorrectionIsolationFixture") else { return nil }
        return UUID(uuidString: environment["LYB_UI_TEST_CORRECTION_NONCE"] ?? "")
    }

    init(nonce: UUID, authManager: AuthManager, onTransportInvalidated: @escaping @Sendable () -> Void = {}) throws {
        self.nonce = nonce
        heldCorrection = HomeV2CorrectionFixtureHold(nonce: nonce)
        let suiteName = "lyb.fixture.correction.\(nonce.uuidString)"
        defaultsSuiteName = suiteName
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw URLError(.cannotCreateFile)
        }
        self.defaults = defaults
        let cleanup = HomeV2CorrectionFixtureCleanup(nonce: nonce, defaults: defaults, suiteName: suiteName)
        self.cleanup = cleanup
        let transport = try HomeV2CorrectionFixtureTransport.make(
            nonce: nonce, onInvalidated: {
                onTransportInvalidated()
                Task { @MainActor in cleanup.didInvalidateOwnedSession() }
            }
        )
        self.transport = transport
        let health = HomeV2CorrectionFixtureHealthSync()
        healthSyncCoordinator = health
        let healthKitManager = HealthKitManager(
            userDefaults: defaults, authManager: authManager, coreDataManager: .shared,
            weightImportQuery: { _, _ in try await health.rejectRead("weightImportQuery") },
            bodyFatImportQuery: { _ in try await health.rejectRead("bodyFatImportQuery") },
            todayStepQuantityQuery: { _, _ in try await health.rejectRead("todayStepQuantityQuery") },
            stepHistoryQuery: { _ in try await health.rejectRead("stepHistoryQuery") },
            earliestImportDateQuery: { try await health.rejectRead("earliestImportDateQuery") },
            syncTrigger: { health.record("importSyncTrigger") },
            importCompletion: { _ in health.record("importCompletion") },
            bodyScoreRecalculationTrigger: { health.record("importRecalculation") },
            metricImportStore: { _, _ in try await health.rejectRead("metricImportStore") },
            rawImportStore: { _ in await health.record("rawImportStore") },
            bodyFatOnlyImportEnabled: { false }
        )
        self.healthKitManager = healthKitManager
        let analyticsClient = HomeV2CorrectionFixtureAnalytics()
        self.analyticsClient = analyticsClient
        let analyticsService = AnalyticsService(client: analyticsClient)
        self.analyticsService = analyticsService
        let realtime = RealtimeSyncManager(
            coreDataManager: .shared, authManager: authManager, productAPIClient: transport.product,
            userDefaults: defaults, analyticsService: analyticsService
        )
        realtime.isOnline = false
        realtime.syncStatus = .offline
        realtimeSyncManager = realtime
        loadingManager = LoadingManager(
            authManager: authManager, healthSyncCoordinator: health, realtimeSyncManager: realtime
        )
        dashboardViewModel = DashboardViewModel(
            healthKitManager: healthKitManager, healthSyncCoordinator: health
        )
        defaults.set(nonce.uuidString, forKey: "correctionFixtureOwnedNonce")
        guard cleanup.bind(held: heldCorrection, transport: transport) else {
            throw URLError(.cannotCreateFile)
        }
    }
}

@MainActor
final class HomeV2CorrectionFixtureHealthSync: HealthSyncCoordinating {
    private(set) var calls: [String: Int] = [:]
    func record(_ method: String) { calls[method, default: 0] += 1 }
    func rejectRead<T>(_ method: String) throws -> T {
        record(method)
        throw CancellationError()
    }
    func bootstrapIfNeeded(syncEnabled: Bool) { record("bootstrapIfNeeded") }
    func resetForCurrentUser() async { record("resetForCurrentUser") }
    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync() async {
        record("configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync")
    }
    func configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync() async {
        record("configureSyncPipelineAfterAuthorizationAndRunInitialWeightAndStepSync")
    }
    func warmUpAfterLoginIfNeeded() async { record("warmUpAfterLoginIfNeeded") }
    func performInitialConnectSync() async throws { try rejectRead("performInitialConnectSync") as Void }
    func runDeferredOnboardingWeightSync() async { record("runDeferredOnboardingWeightSync") }
    func syncWeightFromHealthKit() async throws { try rejectRead("syncWeightFromHealthKit") as Void }
    func syncStepsFromHealthKit() async throws { try rejectRead("syncStepsFromHealthKit") as Void }
    func forceFullHealthKitSync() async -> Bool { record("forceFullHealthKitSync"); return false }
}

/// Per-graph, credential-free app-event counter. No Statsig client is constructed.
final class HomeV2CorrectionFixtureAnalytics: AnalyticsClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callCounts: [String: Int] = [:]
    var calls: [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return callCounts
    }
    private func record(_ method: String) {
        lock.lock()
        callCounts[method, default: 0] += 1
        lock.unlock()
    }
    func start() { record("start") }
    func identify(userId: String?, properties: [String: String]?) { record("identify") }
    func track(event: String, properties: [String: String]?) { record("track:\(event)") }
    func reset() { record("reset") }
    func isFeatureEnabled(flagKey: String) -> Bool { record("isFeatureEnabled"); return false }
}
#endif

#if DEBUG
private struct HomeV2CorrectionFixtureHoldKey: EnvironmentKey {
    static let defaultValue: HomeV2CorrectionFixtureHold? = nil
}

extension EnvironmentValues {
    var homeV2CorrectionFixtureHold: HomeV2CorrectionFixtureHold? {
        get { self[HomeV2CorrectionFixtureHoldKey.self] }
        set { self[HomeV2CorrectionFixtureHoldKey.self] = newValue }
    }
}

/// Producer and actual mounted consumer share one nonce-owned holder; runtime proof remains pending.
@MainActor
final class HomeV2CorrectionFixtureHold: ObservableObject {
    struct Attempt {
        let id: UUID
        let nonce: UUID
        let receipt: HomeV2CorrectionReturnReceipt
        var isHeld = false
        var wasReleased = false
        var cancellationObserved = false
        var isTerminal = false
        var writerAdmissions = 0
        var writerRejections = 0
        var stored: BodyMetrics?
        var publicationReturned = false
    }

    let nonce: UUID
    @Published private(set) var attempts: [UUID: Attempt] = [:]
    private(set) var initialOwner: AuthManager.ProfileSessionOwnership?
    private var armedReceipt: HomeV2CorrectionReturnReceipt?
    private var activeByEditor: [UUID: UUID] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var terminalObservers: [UUID: Task<Void, Never>] = [:]
    private var continuations: [UUID: CheckedContinuation<Void, Never>] = [:]
    private let onHeld: @MainActor (UUID) -> Void
    private let onTerminal: @MainActor (UUID) -> Void

    init(
        nonce: UUID, onHeld: @escaping @MainActor (UUID) -> Void = { _ in },
        onTerminal: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        self.nonce = nonce
        self.onHeld = onHeld
        self.onTerminal = onTerminal
    }

    func bindInitialOwner(_ ownership: AuthManager.ProfileSessionOwnership) {
        guard initialOwner == nil, ownership.subject.hasPrefix("ui_test_photo_hud_user_") else { return }
        initialOwner = ownership
    }

    /// Caller must pass the actual mounted editor receipt, not recapture/rebase it.
    func armNextWriter(for receipt: HomeV2CorrectionReturnReceipt) -> Bool {
        guard let initialOwner, receipt.destination.ownership == initialOwner,
              let metric = receipt.destination.metric, metric.userId == initialOwner.subject,
              armedReceipt == nil, !attempts.values.contains(where: { !$0.isTerminal }) else { return false }
        armedReceipt = receipt
        return true
    }

    func isArmed(for receipt: HomeV2CorrectionReturnReceipt) -> Bool { armedReceipt == receipt }

    var hasPendingWork: Bool { armedReceipt != nil || !continuations.isEmpty || !tasks.isEmpty }

    /// Failure-only explicit command; never called by account/editor/root disappearance.
    /// Return actual terminal observers, which await actual sheet task.value before marking terminal.
    func cancelAndReleaseForFailedCase(nonce requestedNonce: UUID) -> [Task<Void, Never>]? {
        guard requestedNonce == nonce, attempts.values.allSatisfy({ $0.nonce == nonce }) else { return nil }
        if let armedReceipt, armedReceipt.destination.ownership != initialOwner { return nil }
        armedReceipt = nil
        let terminal = Array(terminalObservers.values)
        // Cancellation reaches the existing admission latch BEFORE resuming each exact continuation.
        for task in tasks.values { task.cancel() }
        for id in Array(continuations.keys) {
            guard attempts[id]?.nonce == requestedNonce,
                  releaseExact(id, nonce: requestedNonce) else { return nil }
        }
        return terminal
    }

    /// Explicit owned failure cleanup only. Not called on editor/account/root teardown.
    func disarmExact(_ receipt: HomeV2CorrectionReturnReceipt) {
        if armedReceipt == receipt { armedReceipt = nil }
    }

    /// Retain the ACTUAL sheet task. A cleared UI handle/cancel signal is not terminal.
    func observeTask(_ task: Task<Void, Never>, receipt: HomeV2CorrectionReturnReceipt) {
        guard receipt.destination.ownership == initialOwner,
              activeByEditor[receipt.editorLifetime] == nil else { return }
        let id = UUID()
        attempts[id] = Attempt(id: id, nonce: nonce, receipt: receipt)
        activeByEditor[receipt.editorLifetime] = id
        tasks[id] = task
        terminalObservers[id] = Task { @MainActor in
            await task.value
            guard var attempt = attempts[id], attempt.nonce == nonce else { return }
            attempt.isTerminal = true
            attempts[id] = attempt
            tasks[id] = nil
            terminalObservers[id] = nil
            if activeByEditor[receipt.editorLifetime] == id { activeByEditor[receipt.editorLifetime] = nil }
            onTerminal(id)
        }
    }

    func waitBeforeWriter(_ receipt: HomeV2CorrectionReturnReceipt) async {
        guard armedReceipt == receipt,
              let id = activeByEditor[receipt.editorLifetime],
              attempts[id]?.receipt == receipt else { return }
        armedReceipt = nil
        await withCheckedContinuation { continuation in
            continuations[id] = continuation
            attempts[id]?.isHeld = true
            onHeld(id)
        }
    }

    /// No cancellation/disappearance auto-resume. The mounted consumer must admit exact release eligibility.
    func releaseExact(_ id: UUID, nonce requestedNonce: UUID) -> Bool {
        guard requestedNonce == nonce, var attempt = attempts[id], attempt.nonce == nonce,
              attempt.isHeld, !attempt.wasReleased, let continuation = continuations.removeValue(forKey: id) else {
            return false
        }
        attempt.wasReleased = true
        attempt.isHeld = false
        attempts[id] = attempt
        continuation.resume()
        return true
    }

    func recordCancellation(_ receipt: HomeV2CorrectionReturnReceipt) {
        guard let id = activeByEditor[receipt.editorLifetime], attempts[id]?.receipt == receipt else { return }
        attempts[id]?.cancellationObserved = true
    }

    /// Called ONLY by the real writer's in-context admission closure, never completion admission.
    func recordWriterAdmission(_ result: Result<Void, Error>, receipt: HomeV2CorrectionReturnReceipt) {
        guard let id = activeByEditor[receipt.editorLifetime], attempts[id]?.receipt == receipt else { return }
        switch result {
        case .success: attempts[id]?.writerAdmissions += 1
        case .failure: attempts[id]?.writerRejections += 1
        }
    }

    func recordStored(_ stored: BodyMetrics, receipt: HomeV2CorrectionReturnReceipt) {
        guard let id = activeByEditor[receipt.editorLifetime], attempts[id]?.receipt == receipt else { return }
        attempts[id]?.stored = stored
    }

    func recordPublicationReturned(_ receipt: HomeV2CorrectionReturnReceipt) {
        guard let id = activeByEditor[receipt.editorLifetime], attempts[id]?.receipt == receipt else { return }
        attempts[id]?.publicationReturned = true
    }
}
#endif

#if DEBUG
private struct HomeV2CorrectionFixtureGraphKey: EnvironmentKey {
    static let defaultValue: HomeV2CorrectionFixtureGraph? = nil
}

extension EnvironmentValues {
    var homeV2CorrectionFixtureGraph: HomeV2CorrectionFixtureGraph? {
        get { self[HomeV2CorrectionFixtureGraphKey.self] }
        set { self[HomeV2CorrectionFixtureGraphKey.self] = newValue }
    }
}

struct HomeV2CorrectionFixtureEditorObservation: Equatable {
    let receipt: HomeV2CorrectionReturnReceipt
    let visible: Bool
    let isSaving: Bool
    let error: String?
    let invalidated: Bool
    let currentLifetime: UUID
}

/// Owns only this graph's nonce suite. Disposal follows the ACTUAL session invalidation callback.
@MainActor
final class HomeV2CorrectionFixtureCleanup: ObservableObject {
    @Published private(set) var requested = false
    @Published private(set) var invalidated = false
    @Published private(set) var disposed = false
    @Published private(set) var failedCaseRequested = false
    @Published private(set) var failedCaseTasksTerminal = false
    @Published private(set) var failedCaseError: String?
    let nonce: UUID
    private let defaults: UserDefaults
    private let suiteName: String
    private var boundHolder: ObjectIdentifier?
    private var boundSession: ObjectIdentifier?
    @Published private(set) var originalFailureMarker: String?

    init(nonce: UUID, defaults: UserDefaults, suiteName: String) {
        self.nonce = nonce
        self.defaults = defaults
        self.suiteName = suiteName
    }

    func bind(held: HomeV2CorrectionFixtureHold, transport: HomeV2CorrectionFixtureTransport.Instance) -> Bool {
        guard boundHolder == nil, boundSession == nil, held.nonce == nonce, transport.recorder.nonce == nonce,
              suiteName == "lyb.fixture.correction.\(nonce.uuidString)",
              defaults.string(forKey: "correctionFixtureOwnedNonce") == nonce.uuidString else { return false }
        boundHolder = ObjectIdentifier(held)
        boundSession = ObjectIdentifier(transport.session)
        return true
    }

    func owns(
        nonce requestedNonce: UUID, held: HomeV2CorrectionFixtureHold,
        transport: HomeV2CorrectionFixtureTransport.Instance
    ) -> Bool {
        requestedNonce == nonce && held.nonce == nonce && transport.recorder.nonce == nonce &&
            boundHolder == ObjectIdentifier(held) && boundSession == ObjectIdentifier(transport.session)
    }

    func begin() -> Bool {
        guard !requested, defaults.string(forKey: "correctionFixtureOwnedNonce") != nil else { return false }
        requested = true
        return true
    }

    func beginFailedCase(originalFailure: String) -> Bool {
        guard !failedCaseRequested, !originalFailure.isEmpty else { return false }
        originalFailureMarker = originalFailure
        failedCaseRequested = true
        return true
    }

    func recordFailedCaseTerminal() { failedCaseTasksTerminal = true }
    func recordFailedCaseError(_ message: String) { failedCaseError = message }

    func didInvalidateOwnedSession() {
        invalidated = true
        // This is the unique nonce-owned suite, never .standard or another actor's state.
        defaults.removePersistentDomain(forName: suiteName)
        disposed = defaults.persistentDomain(forName: suiteName) == nil
    }
}

/// The App command and owned-store regression execute this SAME cleanup orchestration.
/// Bounded XCTest waits own failure reporting; this helper never invents terminal/callback state.
@MainActor
enum HomeV2CorrectionFixtureFailedCaseCleanup {
    static func run(
        nonce: UUID, held: HomeV2CorrectionFixtureHold, cleanup: HomeV2CorrectionFixtureCleanup,
        transport: HomeV2CorrectionFixtureTransport.Instance, originalFailure: String
    ) async -> Bool {
        guard cleanup.owns(nonce: nonce, held: held, transport: transport),
              cleanup.beginFailedCase(originalFailure: originalFailure) else { return false }
        guard let terminalObservers = held.cancelAndReleaseForFailedCase(nonce: nonce) else {
            cleanup.recordFailedCaseError("Owned nonce/attempt failure cleanup rejected")
            return false
        }
        for observer in terminalObservers { await observer.value }
        guard !held.hasPendingWork,
              held.attempts.values.allSatisfy({ $0.nonce == nonce && $0.isTerminal && !$0.isHeld }) else {
            cleanup.recordFailedCaseError("Actual retained task terminal/admission phase not complete")
            return false
        }
        cleanup.recordFailedCaseTerminal()
        if !cleanup.requested {
            guard cleanup.begin() else {
                cleanup.recordFailedCaseError("Owned suite marker missing before invalidation")
                return false
            }
            transport.session.finishTasksAndInvalidate()
        }
        // Only the real delegate callback removes this exact suite.
        return true
    }
}

extension HomeV2CorrectionFixtureGraph {
    func observeMainTab(_ identity: UUID) {
        mainTabIdentities.insert(identity)
    }

    func observeHUD(_ identity: UUID) {
        hudIdentities.insert(identity)
    }

    func observeContext(_ route: HomeV2ContextRoute, visible: Bool) {
        guard route.ownership.subject == heldCorrection.initialOwner?.subject else { return }
        if contexts[route.id] != visible { contexts[route.id] = visible }
    }

    func observeEditor(_ observation: HomeV2CorrectionFixtureEditorObservation) {
        guard observation.receipt.destination.ownership.subject == heldCorrection.initialOwner?.subject else { return }
        if editors[observation.receipt.editorLifetime] != observation {
            editors[observation.receipt.editorLifetime] = observation
        }
    }

    func observePublication(_ ownership: AuthManager.ProfileSessionOwnership, rows: [BodyMetrics]) {
        guard ownership.subject == heldCorrection.initialOwner?.subject,
              !rows.isEmpty, rows.allSatisfy({ $0.userId == ownership.subject }) else { return }
        publicationOwnership = ownership
        publicationRows = rows
    }

    private func ownsSyntheticSurface(_ auth: AuthManager, subscription: SubscriptionManager) -> Bool {
        guard !cleanup.requested, !cleanup.failedCaseRequested,
              !subscription.isConfigured, subscription.isSubscribed,
              let initial = heldCorrection.initialOwner, let current = auth.captureAccountSession(),
              auth.currentUser?.id == initial.subject, current.subject == initial.subject,
              auth.ownsAccountSession(current), initial.subject.hasPrefix("ui_test_photo_hud_user_"),
              mainTabIdentities.count == 1, hudIdentities.count == 1 else { return false }
        return true
    }

    func canArmMounted(
        _ editor: HomeV2CorrectionReturnReceipt, liveRoute: HomeV2ContextRoute?,
        auth: AuthManager, subscription: SubscriptionManager
    ) -> Bool {
        guard ownsSyntheticSurface(auth, subscription: subscription),
              editor.destination.ownership == auth.captureAccountSession(),
              publicationOwnership == editor.destination.ownership,
              liveRoute == editor.destination, contexts[editor.destination.id] == true,
              let state = editors[editor.editorLifetime], state.receipt == editor,
              state.visible, !state.isSaving, !state.invalidated, state.error == nil,
              state.currentLifetime == editor.editorLifetime,
              let original = editor.destination.metric,
              publicationRows.filter({ $0.id == original.id }) == [original],
              (try? HomeV2CorrectionPolicy.storedMetric(original, store: .shared)) == original else { return false }
        return true
    }

    func armMounted(
        _ editor: HomeV2CorrectionReturnReceipt, liveRoute: HomeV2ContextRoute?,
        auth: AuthManager, subscription: SubscriptionManager
    ) {
        guard canArmMounted(editor, liveRoute: liveRoute, auth: auth, subscription: subscription),
              heldCorrection.armNextWriter(for: editor) else {
            commandError = "Exact mounted arm admission failed"
            return
        }
    }

    func canReplaceGeneration(
        attemptID: UUID, editor: HomeV2CorrectionReturnReceipt,
        auth: AuthManager, subscription: SubscriptionManager
    ) -> Bool {
        guard ownsSyntheticSurface(auth, subscription: subscription),
              let attempt = heldCorrection.attempts[attemptID], attempt.nonce == nonce,
              attempt.receipt == editor, attempt.isHeld, !attempt.wasReleased, !attempt.isTerminal,
              auth.captureAccountSession() == attempt.receipt.destination.ownership,
              contexts[editor.destination.id] == true, let state = editors[editor.editorLifetime],
              state.visible, state.isSaving, state.currentLifetime == editor.editorLifetime,
              let original = editor.destination.metric,
              (try? HomeV2CorrectionPolicy.storedMetric(original, store: .shared)) == original else { return false }
        return true
    }

    func replaceSyntheticGeneration(
        attemptID: UUID, editor: HomeV2CorrectionReturnReceipt,
        auth: AuthManager, subscription: SubscriptionManager
    ) {
        guard canReplaceGeneration(attemptID: attemptID, editor: editor, auth: auth, subscription: subscription),
              auth === AuthManager.shared, subscription === SubscriptionManager.shared,
              let before = auth.captureAccountSession(), let user = auth.currentUser else {
            commandError = "Synthetic same-subject replacement admission failed"
            return
        }
        // Direct synthetic setter ONLY. No initialize/rotate/persist/logout/Keychain/provider call.
        auth.authSession = .localFixture(subject: user.id, email: user.email, name: user.name)
        // Auth's real billing owner invalidation remains intact; re-inject without yielding.
        subscription.isSubscribed = true
        subscription.customerInfo = nil
        subscription.currentOffering = nil
        subscription.errorMessage = nil
        subscription.isPurchasing = false
        guard let after = auth.captureAccountSession(), after.subject == before.subject,
              after != before, !subscription.isConfigured else {
            commandError = "Actual synthetic receipt did not change as required"
            return
        }
        // Do not open/rebase/preserve old Context or editor. Existing observers must close them.
    }

    func canReleaseMounted(
        attemptID: UUID, requestedNonce: UUID, editor: HomeV2CorrectionReturnReceipt,
        liveRoute: HomeV2ContextRoute?, auth: AuthManager, subscription: SubscriptionManager
    ) -> Bool {
        guard requestedNonce == nonce, ownsSyntheticSurface(auth, subscription: subscription),
              let attempt = heldCorrection.attempts[attemptID], attempt.nonce == nonce,
              attempt.isHeld, !attempt.wasReleased, !attempt.isTerminal,
              let original = attempt.receipt.destination.metric,
              (try? HomeV2CorrectionPolicy.storedMetric(original, store: .shared)) == original,
              let current = auth.captureAccountSession(), publicationOwnership == current,
              publicationRows.filter({ $0.id == original.id }) == [original],
              editor.destination.ownership == current, editor.destination.metric == original,
              liveRoute == editor.destination, contexts[editor.destination.id] == true,
              let state = editors[editor.editorLifetime], state.receipt == editor,
              state.visible, !state.invalidated, state.error == nil,
              state.currentLifetime == editor.editorLifetime else { return false }
        if current == attempt.receipt.destination.ownership {
            // Positive: actual original Context/editor and original receipt still own the held write.
            return editor == attempt.receipt && state.isSaving
        }
        // Negative: same subject, new receipt/new actual Context/new editor BEFORE old release.
        guard current.subject == attempt.receipt.destination.ownership.subject,
              editor.destination.id != attempt.receipt.destination.id,
              editor.editorLifetime != attempt.receipt.editorLifetime,
              contexts[attempt.receipt.destination.id] == false,
              editors[attempt.receipt.editorLifetime]?.visible == false,
              !state.isSaving else { return false }
        return true
    }

    func releaseMounted(
        attemptID: UUID, requestedNonce: UUID, editor: HomeV2CorrectionReturnReceipt,
        liveRoute: HomeV2ContextRoute?, auth: AuthManager, subscription: SubscriptionManager
    ) {
        guard canReleaseMounted(
            attemptID: attemptID, requestedNonce: requestedNonce, editor: editor,
            liveRoute: liveRoute, auth: auth, subscription: subscription
        ), heldCorrection.releaseExact(attemptID, nonce: requestedNonce) else {
            commandError = "Exact nonce/attempt/new-editor/store-phase release admission failed"
            return
        }
    }

    func finishMounted(auth: AuthManager, subscription: SubscriptionManager) {
        guard ownsSyntheticSurface(auth, subscription: subscription),
              !heldCorrection.attempts.isEmpty,
              heldCorrection.attempts.values.allSatisfy({ $0.isTerminal && !$0.isHeld }),
              !heldCorrection.hasPendingWork,
              !contexts.values.contains(true), !editors.values.contains(where: { $0.visible }),
              cleanup.begin() else {
            commandError = "Owned fixture cleanup requires all actual tasks terminal and real modals gone"
            return
        }
        transport.session.finishTasksAndInvalidate()
        // No fabricated callback/disposal flag. Actual delegate callback performs owned-suite disposal.
    }

    /// Explicit failed-test resource cleanup, not a mounted acceptance transition.
    /// No Auth/storage/provider call is needed to cancel only this nonce's retained sheet work.
    func cleanupAfterFailedCase(requestedNonce: UUID) {
        guard requestedNonce == nonce, failedCaseCleanupTask == nil, !cleanup.failedCaseRequested else { return }
        failedCaseCleanupTask = Task { @MainActor in
            _ = await HomeV2CorrectionFixtureFailedCaseCleanup.run(
                nonce: requestedNonce, held: heldCorrection, cleanup: cleanup, transport: transport,
                originalFailure: "XCTest case did not reach its verified completion token"
            )
            failedCaseCleanupTask = nil
        }
    }

    /// Failure metadata deliberately excludes current Auth and raw-store reads.
    func failedCaseSnapshot() -> String {
        let value: [String: Any] = [
            "nonce": nonce.uuidString, "failureOnly": true, "acceptance": false,
            "originalFailureMarker": cleanup.originalFailureMarker as Any? ?? NSNull(),
            "requested": cleanup.failedCaseRequested,
            "actualHeldTasksTerminal": cleanup.failedCaseTasksTerminal,
            "pendingOwnedWork": heldCorrection.hasPendingWork,
            "attemptCount": heldCorrection.attempts.count,
            "heldCount": heldCorrection.attempts.values.filter { $0.isHeld }.count,
            "terminalCount": heldCorrection.attempts.values.filter { $0.isTerminal }.count,
            "invalidationRequested": cleanup.requested, "callbackObserved": cleanup.invalidated,
            "ownedDefaultsDisposed": cleanup.disposed,
            "ownedDefaultsActuallyAbsent": defaults.persistentDomain(forName: defaultsSuiteName) == nil,
            "transportInvalidations": transport.recorder.snapshot().invalidationCount,
            "cleanupError": cleanup.failedCaseError as Any? ?? NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "invalid failure metadata" }
        return text
    }

    func snapshot(auth: AuthManager, subscription: SubscriptionManager) -> String {
        guard let initial = heldCorrection.initialOwner, let current = auth.captureAccountSession(),
              current.subject == initial.subject, auth.currentUser?.id == initial.subject else {
            return "{\"admitted\":false}"
        }
        func object(_ metric: BodyMetrics?) -> Any {
            guard let metric, let data = try? JSONEncoder().encode(metric),
                  let value = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
            return value
        }
        let attempts: [[String: Any]] = heldCorrection.attempts.values.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            let expected = $0.stored ?? $0.receipt.destination.metric
            let actual = expected.flatMap { try? HomeV2CorrectionPolicy.storedMetric($0, store: .shared) }
            return [
                "id": $0.id.uuidString, "nonce": $0.nonce.uuidString,
                "route": $0.receipt.destination.id.uuidString, "editor": $0.receipt.editorLifetime.uuidString,
                "generation": String($0.receipt.destination.ownership.generation),
                "held": $0.isHeld, "released": $0.wasReleased, "cancelObserved": $0.cancellationObserved,
                "terminal": $0.isTerminal, "writerAdmissions": $0.writerAdmissions, "writerRejections": $0.writerRejections,
                "original": object($0.receipt.destination.metric), "stored": object($0.stored),
                "actualRaw": object(actual), "returned": $0.publicationReturned
            ]
        }
        let editorRows: [[String: Any]] = editors.values.map {
            ["route": $0.receipt.destination.id.uuidString, "editor": $0.receipt.editorLifetime.uuidString,
             "generation": String($0.receipt.destination.ownership.generation), "visible": $0.visible,
             "saving": $0.isSaving, "error": $0.error as Any? ?? NSNull(), "invalidated": $0.invalidated,
             "currentLifetime": $0.currentLifetime.uuidString]
        }
        let transportState = transport.recorder.snapshot()
        let value: [String: Any] = [
            "admitted": true, "nonce": nonce.uuidString, "generation": String(current.generation),
            "publicationGeneration": publicationOwnership.map { String($0.generation) } as Any? ?? NSNull(),
            "mainTabIDs": mainTabIdentities.map(\.uuidString).sorted(),
            "hudIDs": hudIdentities.map(\.uuidString).sorted(),
            "visibleContextIDs": contexts.filter { $0.value }.keys.map(\.uuidString).sorted(),
            "closedContextIDs": contexts.filter { !$0.value }.keys.map(\.uuidString).sorted(),
            "editors": editorRows, "attempts": attempts, "pendingWork": heldCorrection.hasPendingWork,
            "transportTasks": transportState.tasks.count, "transportInvalidations": transportState.invalidationCount,
            "invalidationError": transportState.invalidationError as Any? ?? NSNull(),
            "failureCleanupRequested": cleanup.failedCaseRequested,
            "ownedDefaultsMarker": defaults.string(forKey: "correctionFixtureOwnedNonce") as Any? ?? NSNull(),
            "cleanupRequested": cleanup.requested, "sessionInvalidated": cleanup.invalidated,
            "ownedDefaultsDisposed": cleanup.disposed, "healthCalls": healthSyncCoordinator.calls,
            "analyticsCalls": analyticsClient.calls, "healthAuthorized": healthKitManager.isAuthorized,
            "billingSDKConfigured": subscription.isConfigured, "commandError": commandError as Any? ?? NSNull()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{\"admitted\":false}" }
        return text
    }
}

/// This explicit button is exposed only in the nonce-owned DEBUG graph.
/// XCTest teardown invokes it after failure; it never runs automatically on modal/account teardown.
struct HomeV2CorrectionFixtureFailureControl: View {
    @ObservedObject var graph: HomeV2CorrectionFixtureGraph
    @ObservedObject var held: HomeV2CorrectionFixtureHold
    @ObservedObject var cleanup: HomeV2CorrectionFixtureCleanup
    let scope: String

    init(graph: HomeV2CorrectionFixtureGraph, scope: String) {
        self.graph = graph
        held = graph.heldCorrection
        cleanup = graph.cleanup
        self.scope = scope
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(graph.failedCaseSnapshot())
                .font(.system(size: 7)).lineLimit(1)
                .accessibilityIdentifier("home_v2_correction_failure_status_\(scope)_\(graph.nonce.uuidString)")
            Button("Failed-case owned cleanup") {
                graph.cleanupAfterFailedCase(requestedNonce: graph.nonce)
            }
            .disabled(cleanup.failedCaseRequested)
            .accessibilityIdentifier("home_v2_correction_failure_cleanup_\(scope)_\(graph.nonce.uuidString)")
            .font(.caption2)
        }
        .padding(2).background(Color.black)
        .accessibilityElement(children: .contain)
    }
}

struct HomeV2CorrectionFixturePanel: View {
    @ObservedObject var graph: HomeV2CorrectionFixtureGraph
    @ObservedObject var held: HomeV2CorrectionFixtureHold
    @ObservedObject var cleanup: HomeV2CorrectionFixtureCleanup
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var subscription: SubscriptionManager
    let editor: HomeV2CorrectionReturnReceipt?
    let liveRoute: HomeV2ContextRoute?
    let scope: String

    init(
        graph: HomeV2CorrectionFixtureGraph, editor: HomeV2CorrectionReturnReceipt? = nil,
        liveRoute: HomeV2ContextRoute? = nil, scope: String
    ) {
        self.graph = graph
        held = graph.heldCorrection
        cleanup = graph.cleanup
        self.editor = editor
        self.liveRoute = liveRoute
        self.scope = scope
    }

    var body: some View {
        VStack(spacing: 2) {
            HomeV2CorrectionFixtureFailureControl(graph: graph, scope: scope)
            Text(graph.snapshot(auth: auth, subscription: subscription))
                .font(.system(size: 7)).lineLimit(1)
                .accessibilityIdentifier("home_v2_correction_fixture_snapshot_\(scope)")
            HStack {
                if let editor {
                    Button("Arm held write") {
                        graph.armMounted(editor, liveRoute: liveRoute, auth: auth, subscription: subscription)
                    }
                    .disabled(!graph.canArmMounted(editor, liveRoute: liveRoute, auth: auth, subscription: subscription))
                    .accessibilityIdentifier("home_v2_correction_fixture_arm")
                    ForEach(held.attempts.values.filter { $0.isHeld }.sorted { $0.id.uuidString < $1.id.uuidString },
                            id: \.id) { attempt in
                        Button("Replace synthetic generation") {
                            graph.replaceSyntheticGeneration(
                                attemptID: attempt.id, editor: editor, auth: auth, subscription: subscription
                            )
                        }
                        .disabled(!graph.canReplaceGeneration(
                            attemptID: attempt.id, editor: editor, auth: auth, subscription: subscription
                        ))
                        .accessibilityIdentifier("home_v2_correction_fixture_replace_\(attempt.id.uuidString)")
                        Button("Release exact old write") {
                            graph.releaseMounted(
                                attemptID: attempt.id, requestedNonce: graph.nonce, editor: editor,
                                liveRoute: liveRoute, auth: auth, subscription: subscription
                            )
                        }
                        .disabled(!graph.canReleaseMounted(
                            attemptID: attempt.id, requestedNonce: graph.nonce, editor: editor,
                            liveRoute: liveRoute, auth: auth, subscription: subscription
                        ))
                        .accessibilityIdentifier("home_v2_correction_fixture_release_\(attempt.id.uuidString)")
                    }
                } else if scope == "home" {
                    Button("Finish owned fixture") { graph.finishMounted(auth: auth, subscription: subscription) }
                        .accessibilityIdentifier("home_v2_correction_fixture_finish")
                }
            }
            .font(.caption2)
        }
        .padding(4).background(Color.black.opacity(0.9))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_v2_correction_fixture_panel")
    }
}
#endif
