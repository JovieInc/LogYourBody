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
                .environment(clerk)
                .sheet(isPresented: $showAddEntrySheet) {
                    AddEntrySheet(isPresented: $showAddEntrySheet)
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
                        if healthKitManager.isAuthorized {
                            try? await healthKitManager.syncStepsFromHealthKit()
                        }
                        // Update widget with latest data
                        await widgetDataManager.updateWidgetData()
                    }
                }
        }
    }

    // MARK: - Startup Helpers

    @MainActor
    private func performStartupSequence() async {
        scheduleDeferredMaintenance()

        let clerkInitializationTask = authManager.ensureClerkInitializationTask(priority: .userInitiated)

        async let revenueCatPipeline: Void = configureRevenueCat(waitingFor: clerkInitializationTask)
        async let healthKitPipeline: Void = bootstrapHealthKit()

        _ = await (revenueCatPipeline, healthKitPipeline)
        await clerkInitializationTask.value
    }

    @MainActor
    private func configureRevenueCat(waitingFor clerkTask: Task<Void, Never>) async {
        let apiKey = Constants.revenueCatAPIKey
        guard !apiKey.isEmpty else { return }

        revenueCatManager.configure(apiKey: apiKey)

        async let offeringsTask: Void = revenueCatManager.fetchOfferings()

        await clerkTask.value

        if authManager.isAuthenticated, let userId = authManager.currentUser?.id {
            await revenueCatManager.identifyUser(userId: userId)
        } else {
            await revenueCatManager.refreshCustomerInfo()
        }

        _ = await offeringsTask
    }

    @MainActor
    private func bootstrapHealthKit() async {
        healthKitManager.checkAuthorizationStatus()

        guard UserDefaults.standard.bool(forKey: "healthKitSyncEnabled") else { return }

        guard healthKitManager.isAuthorized else { return }

        healthKitManager.observeWeightChanges()
        healthKitManager.observeStepChanges()

        Task {
            try? await healthKitManager.setupStepCountBackgroundDelivery()
        }
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

        Task {
            await widgetDataManager.updateWidgetData()
        }
    }

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

            // Check if onboarding is complete
            let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Constants.hasCompletedOnboardingKey)
            let isProfileComplete = checkProfileComplete()

            if !hasCompletedOnboarding || !isProfileComplete {
                // User needs to complete onboarding first
                // Don't open the add entry sheet
                return
            }

            // Handle specific log types
            if let path = url.pathComponents.dropFirst().first {
                switch path {
                case "weight":
                    UserDefaults.standard.set(0, forKey: "pendingEntryTab")
                case "bodyfat":
                    UserDefaults.standard.set(1, forKey: "pendingEntryTab")
                case "photo":
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
