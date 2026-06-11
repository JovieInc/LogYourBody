//
// LogYourBodyApp.swift
// LogYourBody
//
import SwiftUI
import Clerk
import AppIntents

@main
struct LogYourBodyApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    @StateObject private var healthKitManager = HealthKitManager.shared
    @StateObject private var realtimeSyncManager = RealtimeSyncManager.shared
    @StateObject private var bugReportManager = BugReportManager.shared
    @State private var clerk = Clerk.shared
    @State private var showAddEntrySheet = false
    @State private var selectedEntryTab = 0

    let persistenceController = CoreDataManager.shared

    init() {
        LogYourBodyAppShortcuts.updateAppShortcutParameters()
    }

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
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // App entering foreground - refresh data
                    Task {
                        if isFullBodyCompositionDashboardEnabled, healthKitManager.isAuthorized {
                            try? await HealthSyncCoordinator.shared.syncStepsFromHealthKit()
                        }
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

        if await applyPaidMVPUITestFixtureIfNeeded() {
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
    private func applyPaidMVPUITestFixtureIfNeeded() async -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        let usesPaidFixture = arguments.contains("-lybUITestPaidMVPFixture")
        let usesPaywallFixture = arguments.contains("-lybUITestPaywallFixture")
        let usesFullDashboardFixture = arguments.contains("-lybUITestFullDashboardFixture")
        let usesPhotoTimelineHUDFixture = arguments.contains("-lybUITestPhotoTimelineHUDFixture")

        guard usesPaidFixture || usesPaywallFixture || usesFullDashboardFixture || usesPhotoTimelineHUDFixture else {
            return false
        }

        let isSubscribed = usesPaidFixture || usesFullDashboardFixture || usesPhotoTimelineHUDFixture
        let fixtureName: String
        let fixtureEmail: String
        let fixtureUsername: String
        if usesPhotoTimelineHUDFixture {
            fixtureName = "Photo HUD UI"
            fixtureEmail = "photo-hud-ui@example.com"
            fixtureUsername = "photo_hud_ui"
        } else if usesFullDashboardFixture {
            fixtureName = "Full Dashboard UI"
            fixtureEmail = "full-dashboard-ui@example.com"
            fixtureUsername = "full_dashboard_ui"
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
        if usesPhotoTimelineHUDFixture {
            fixtureSlug = "photo_hud"
        } else if usesFullDashboardFixture {
            fixtureSlug = "full_dashboard"
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
        if usesPaywallFixture {
            revenueCatManager.applyCachedPaywallOfferingUITestFixture()
        }
        UserDefaults.standard.set(isSubscribed, forKey: "revenuecat_isSubscribed")

        UserDefaults.standard.set(
            MeasurementSystem.imperial.rawValue,
            forKey: Constants.preferredMeasurementSystemKey
        )
        OnboardingStateManager.shared.updateCompletionStatus(true)

        realtimeSyncManager.isOnline = false
        realtimeSyncManager.syncStatus = .offline
        realtimeSyncManager.pendingSyncCount = 0

        if usesFullDashboardFixture || usesPhotoTimelineHUDFixture {
            await seedFullDashboardUITestFixtureData(userId: userId)
        }

        if arguments.contains("-lybUITestGlp1WeeklyCheckInFixture") {
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
            let legacyFullDashboardBetaEnabled = LaunchSurfacePolicy.shouldShowLegacyFullDashboardBeta(
                gateEnabled: AnalyticsService.shared.isFeatureEnabled(
                    flagKey: Constants.fullBodyCompositionDashboardFlagKey
                )
            )
            let photoTimelineHUDEnabled = PhotoTimelineHUDPolicy.shouldShowPhotoTimelineHUD(
                gateEnabled: AnalyticsService.shared.isFeatureEnabled(
                    flagKey: Constants.photoTimelineHUDFlagKey
                )
            )
            let requiresOnboarding = LaunchSurfacePolicy.requiresBodyCompositionOnboarding(
                hasCompletedOnboarding: hasCompletedOnboarding,
                legacyFullDashboardBetaEnabled: legacyFullDashboardBetaEnabled,
                photoTimelineHUDEnabled: photoTimelineHUDEnabled
            )
            let requiresProfile = LaunchSurfacePolicy.requiresCompleteProfile(
                isProfileComplete: isProfileComplete,
                legacyFullDashboardBetaEnabled: legacyFullDashboardBetaEnabled,
                photoTimelineHUDEnabled: photoTimelineHUDEnabled
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
