//
// LogYourBodyApp.swift
// LogYourBody
//
import SwiftUI
import AppIntents

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
                    .foregroundStyle(.yellow)
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

@main
struct LogYourBodyApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var realtimeSyncManager = RealtimeSyncManager.shared
    @StateObject private var bugReportManager = BugReportManager.shared
    @State private var showAddEntrySheet = false
    @State private var selectedEntryTab = 0
    @State private var pendingEntryDeepLinkDestination: EntryDeepLinkRoutingPolicy.PendingDestination?

    @StateObject private var persistenceController = CoreDataManager.shared

    init() {
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
                ContentView()
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
                            if let tab = UserDefaults.standard.object(forKey: "pendingEntryTab") as? Int {
                                selectedEntryTab = tab
                                UserDefaults.standard.removeObject(forKey: "pendingEntryTab")
                            }
                        }
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .task {
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
                            try? await HealthSyncCoordinator.shared.syncStepsFromHealthKit()
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

        if authManager.isAuthenticated, let userId = authManager.currentUser?.id {
            await subscriptionManager.identifyUser(userId: userId)
        } else {
            await subscriptionManager.refreshCustomerInfo()
        }
    }

    @MainActor
    private func bootstrapHealthKit() async {
        let syncEnabled = UserDefaults.standard.bool(forKey: "healthKitSyncEnabled")
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
        let userId = "ui_test_\(fixtureSlug)_user_\(UUID().uuidString)"
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
        authManager.currentUser = User(
            id: userId,
            email: fixtureEmail,
            name: fixtureName,
            profile: profile,
            onboardingCompleted: !usesBodyScoreOnboardingFixture
        )
        authManager.isAuthenticated = true
        authManager.isAuthProviderLoaded = true
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
        UserDefaults.standard.set(isSubscribed, forKey: "revenuecat_isSubscribed")
        if isSubscribed && !usesDailyReminderPromptFixture {
            NotificationManager.shared.skipDailyWeighInPrompt()
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

        if usesFullDashboardFixture || usesPhotoTimelineHUDFixture {
            await seedFullDashboardUITestFixtureData(userId: userId)
        }

        if arguments.contains("-lybUITestGlp1WeeklyCheckInFixture") &&
            !arguments.contains("-lybUITestGlp1EmptyMedicationFixture") {
            await seedGlp1WeeklyCheckInUITestFixtureData(userId: userId)
        }

        return true
    }

    private func seedFullDashboardUITestFixtureData(userId: String) async {
        let calendar = Calendar.current
        let now = Date()
        let entries: [
            (daysAgo: Int, weight: Double, bodyFat: Double?, muscle: Double, notes: String, source: String)
        ] = [
            (0, 82.1, 15.8, 66.2, "Latest check-in", "manual"),
            (7, 82.8, 16.2, 66.0, "Weekly check-in", "healthkit"),
            (14, 83.4, nil, 65.9, "Weight-only import", "healthkit"),
            (21, 84.0, 16.9, 65.7, "DEXA baseline", "bodyspec_dexa"),
            (35, 84.7, 17.4, 65.4, "Manual baseline", "manual")
        ]

        for entry in entries {
            guard let date = calendar.date(byAdding: .day, value: -entry.daysAgo, to: now) else {
                continue
            }

            let metric = BodyMetrics(
                id: "ui_test_full_dashboard_metric_\(entry.daysAgo)",
                userId: userId,
                date: date,
                weight: entry.weight,
                weightUnit: "kg",
                bodyFatPercentage: entry.bodyFat,
                bodyFatMethod: entry.bodyFat == nil ? nil : entry.source,
                muscleMass: entry.muscle,
                boneMass: nil,
                waistCm: nil,
                hipCm: nil,
                waistUnit: nil,
                notes: entry.notes,
                photoUrl: nil,
                dataSource: entry.source,
                createdAt: date,
                updatedAt: now
            )

            try? await CoreDataManager.shared.saveBodyMetricsAndWait(
                metric,
                userId: userId,
                markAsSynced: entry.source != "manual"
            )
        }
    }

    private func seedGlp1WeeklyCheckInUITestFixtureData(userId: String) async {
        let calendar = Calendar.current
        let now = Date()
        let startedAt = calendar.date(byAdding: .day, value: -42, to: now) ?? now
        let lastDoseDate = calendar.date(byAdding: .day, value: -9, to: now) ?? now

        let medication = Glp1Medication(
            id: "ui_test_glp1_medication",
            userId: userId,
            displayName: "Zepbound",
            genericName: "tirzepatide",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            isCompounded: false,
            hkIdentifier: "hk.glp1.tirzepatide.zepbound.weekly",
            startedAt: startedAt,
            endedAt: nil,
            notes: nil,
            createdAt: startedAt,
            updatedAt: now
        )

        let doseLog = Glp1DoseLog(
            id: "ui_test_glp1_dose_due",
            userId: userId,
            takenAt: calendar.startOfDay(for: lastDoseDate),
            medicationId: medication.id,
            doseAmount: 5.0,
            doseUnit: "mg/week",
            drugClass: medication.drugClass,
            brand: medication.brand,
            isCompounded: medication.isCompounded,
            supplierType: nil,
            supplierName: nil,
            notes: "UI test weekly check-in seed",
            createdAt: lastDoseDate,
            updatedAt: now
        )

        CoreDataManager.shared.saveGlp1Medications([medication], userId: userId)
        CoreDataManager.shared.saveGlp1DoseLogs([doseLog], userId: userId)
        _ = await CoreDataManager.shared.fetchGlp1Medications(for: userId)
        _ = await CoreDataManager.shared.fetchGlp1DoseLogs(for: userId)
    }
    #endif

    // MARK: - Deep Link Handling

    @MainActor
    private func handleDeepLink(_ url: URL) {
        if LogYourBodyDeepLink.isOAuthCallback(url) {
            // ASWebAuthenticationSession owns the active OAuth callback.
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
            UserDefaults.standard.set(tab, forKey: "pendingEntryTab")
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
