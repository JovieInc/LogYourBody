//
// LogYourBodyApp.swift
// LogYourBody
//
import SwiftUI
import Clerk

@main
struct LogYourBodyApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var realtimeSyncManager = RealtimeSyncManager.shared
    @StateObject private var widgetDataManager = WidgetDataManager.shared
    @StateObject private var bugReportManager = BugReportManager.shared
    @State private var clerk = Clerk.shared
    @State private var showAddEntrySheet = false
    @State private var selectedEntryTab = 0

    let persistenceController = CoreDataManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .environmentObject(authManager)
                .environmentObject(realtimeSyncManager)
                .environmentObject(revenueCatManager)
                .environmentObject(bugReportManager)
                .environment(clerk)
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
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // App entering background - ensure sync is complete
                    realtimeSyncManager.syncIfNeeded()

                    // Update widget data
                    Task {
                        await widgetDataManager.updateWidgetData()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // App entering foreground - refresh data
                    Task {
                        if isFullBodyCompositionDashboardEnabled, healthKitManager.isAuthorized {
                            try? await HealthSyncCoordinator.shared.syncStepsFromHealthKit()
                        }
                        // Update widget with latest data
                        await widgetDataManager.updateWidgetData()
                    }
                }
        }
    }

    // MARK: - Startup Helpers

    private var isFullBodyCompositionDashboardEnabled: Bool {
        AnalyticsService.shared.isFeatureEnabled(flagKey: Constants.fullBodyCompositionDashboardFlagKey)
    }

    @MainActor
    private func performStartupSequence() async {
        #if DEBUG
        if applySignedOutUITestFixtureIfNeeded() {
            return
        }

        if applyEmailVerificationUITestFixtureIfNeeded() {
            return
        }

        if applyPaidMVPUITestFixtureIfNeeded() {
            return
        }
        #endif

        scheduleDeferredMaintenance()

        ErrorTrackingService.shared.start()

        AnalyticsService.shared.start()
        AnalyticsService.shared.track(event: "app_open")

        let clerkInitializationTask = authManager.ensureClerkInitializationTask(priority: .userInitiated)

        Task { @MainActor in
            await configureRevenueCat(waitingFor: clerkInitializationTask)
        }

        Task { @MainActor in
            if isFullBodyCompositionDashboardEnabled {
                await bootstrapHealthKit()
            }
        }

        await clerkInitializationTask.value
    }

    @MainActor
    private func configureRevenueCat(waitingFor clerkTask: Task<Void, Never>) async {
        let apiKey = Constants.revenueCatAPIKey
        guard !apiKey.isEmpty else { return }

        revenueCatManager.configure(apiKey: apiKey)

        await clerkTask.value

        if authManager.isAuthenticated, let userId = authManager.currentUser?.id {
            await revenueCatManager.identifyUser(userId: userId)
        } else {
            await revenueCatManager.refreshCustomerInfo()
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

        widgetDataManager.setupAutomaticUpdates()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await widgetDataManager.updateWidgetData()
        }
    }

    #if DEBUG
    @MainActor
    @discardableResult
    private func applySignedOutUITestFixtureIfNeeded() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("-lybUITestSignedOutFixture") else {
            return false
        }

        authManager.applySignedOutUITestFixture()
        revenueCatManager.isSubscribed = false
        revenueCatManager.customerInfo = nil
        revenueCatManager.currentOffering = nil
        revenueCatManager.errorMessage = nil
        revenueCatManager.isPurchasing = false

        return true
    }

    @MainActor
    @discardableResult
    private func applyEmailVerificationUITestFixtureIfNeeded() -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("-lybUITestEmailVerificationFixture") else {
            return false
        }

        authManager.applyEmailVerificationUITestFixture()
        revenueCatManager.isSubscribed = false
        revenueCatManager.customerInfo = nil
        revenueCatManager.currentOffering = nil
        revenueCatManager.errorMessage = nil
        revenueCatManager.isPurchasing = false

        return true
    }

    @MainActor
    @discardableResult
    private func applyPaidMVPUITestFixtureIfNeeded() -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let usesPaidFixture = arguments.contains("-lybUITestPaidMVPFixture")
        let usesPaywallFixture = arguments.contains("-lybUITestPaywallFixture")

        guard usesPaidFixture || usesPaywallFixture else {
            return false
        }

        let isSubscribed = usesPaidFixture
        let fixtureName = isSubscribed ? "Paid MVP UI" : "Paywall UI"
        let fixtureEmail = isSubscribed ? "paid-mvp-ui@example.com" : "paywall-ui@example.com"
        let fixtureUsername = isSubscribed ? "paid_mvp_ui" : "paywall_ui"
        let userId = "ui_test_\(isSubscribed ? "paid_mvp" : "paywall")_user_\(UUID().uuidString)"
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
            onboardingCompleted: true
        )
        authManager.currentUser = User(
            id: userId,
            email: fixtureEmail,
            name: fixtureName,
            profile: profile,
            onboardingCompleted: true
        )
        authManager.isAuthenticated = true
        authManager.isClerkLoaded = true
        revenueCatManager.isSubscribed = isSubscribed
        revenueCatManager.customerInfo = nil
        revenueCatManager.currentOffering = nil
        revenueCatManager.errorMessage = nil
        revenueCatManager.isPurchasing = false
        UserDefaults.standard.set(isSubscribed, forKey: "revenuecat_isSubscribed")

        UserDefaults.standard.set(
            MeasurementSystem.imperial.rawValue,
            forKey: Constants.preferredMeasurementSystemKey
        )
        OnboardingStateManager.shared.updateCompletionStatus(true)

        realtimeSyncManager.isOnline = false
        realtimeSyncManager.syncStatus = .offline
        realtimeSyncManager.pendingSyncCount = 0

        return true
    }
    #endif

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "logyourbody" else { return }

        switch url.host {
        case "oauth", "oauth-callback":
            // Handle OAuth callbacks (e.g., from Apple Sign In)
            // Clerk SDK handles the OAuth callback automatically
            break

        case "log":
            // Check if user is authenticated and has completed onboarding
            guard authManager.isAuthenticated else {
                // User needs to sign in first
                return
            }

            // Check if body-composition onboarding/profile gates apply to this launch surface.
            let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Constants.hasCompletedOnboardingKey)
            let isProfileComplete = checkProfileComplete()
            let fullDashboardEnabled = LaunchSurfacePolicy.shouldShowFullBodyCompositionDashboard(
                gateEnabled: AnalyticsService.shared.isFeatureEnabled(
                    flagKey: Constants.fullBodyCompositionDashboardFlagKey
                )
            )
            let requiresOnboarding = LaunchSurfacePolicy.requiresBodyCompositionOnboarding(
                hasCompletedOnboarding: hasCompletedOnboarding,
                fullDashboardEnabled: fullDashboardEnabled
            )
            let requiresProfile = LaunchSurfacePolicy.requiresCompleteProfile(
                isProfileComplete: isProfileComplete,
                fullDashboardEnabled: fullDashboardEnabled
            )

            if requiresOnboarding || requiresProfile {
                // User needs to complete onboarding first
                // Don't open the add entry sheet
                return
            }

            // Handle specific log types
            if let path = url.pathComponents.dropFirst().first {
                switch path {
                case "weight":
                    selectedEntryTab = 0
                    UserDefaults.standard.set(0, forKey: "pendingEntryTab")
                case "bodyfat":
                    selectedEntryTab = 1
                    UserDefaults.standard.set(1, forKey: "pendingEntryTab")
                case "photo":
                    selectedEntryTab = 2
                    UserDefaults.standard.set(2, forKey: "pendingEntryTab")
                default:
                    break
                }
            }
            showAddEntrySheet = true

        default:
            // Unhandled URL host
            break
        }
    }

    private func checkProfileComplete() -> Bool {
        guard let profile = authManager.currentUser?.profile else { return false }
        return profile.fullName != nil &&
            profile.dateOfBirth != nil &&
            profile.height != nil &&
            profile.gender != nil
    }
}
