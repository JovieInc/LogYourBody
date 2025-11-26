//
// LoadingManager.swift
// LogYourBody
//
import SwiftUI

@MainActor
class LoadingManager: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var loadingStatus: String = "Initializing..."
    @Published var isLoading: Bool = true

    private let authManager: AuthManager
    private let coreDataManager = CoreDataManager.shared
    private let syncManager = RealtimeSyncManager.shared
    private let healthSyncCoordinator: HealthSyncCoordinating

    // Loading steps with their weights
    private enum LoadingStep {
        case initialize
        case checkAuth
        case loadProfile
        case setupHealthKit
        case loadLocalData
        case syncData
        case complete

        var weight: Double {
            switch self {
            case .initialize: return 0.1
            case .checkAuth: return 0.2
            case .loadProfile: return 0.2
            case .setupHealthKit: return 0.2
            case .loadLocalData: return 0.15
            case .syncData: return 0.15
            case .complete: return 0.0
            }
        }

        var status: String {
            switch self {
            case .initialize: return "Initializing app..."
            case .checkAuth: return "Checking authentication..."
            case .loadProfile: return "Loading user profile..."
            case .setupHealthKit: return "Setting up health data..."
            case .loadLocalData: return "Loading local data..."
            case .syncData: return "Syncing with server..."
            case .complete: return "Ready!"
            }
        }
    }

    private var completedWeight: Double = 0.0

    init(
        authManager: AuthManager,
        healthSyncCoordinator: HealthSyncCoordinating = HealthSyncCoordinator.shared
    ) {
        self.authManager = authManager
        self.healthSyncCoordinator = healthSyncCoordinator
    }

    func startLoading() async {
        resetLoadingState()

        // Step 1: Initialize
        await performInitializationStep()
        // Removed artificial 0.2s delay

        // Step 2: Check Authentication
        await performAuthStep()

        // Step 3: Load Profile (if authenticated)
        await performProfileStepIfNeeded()

        // Step 4: Complete blocking phase
        await completeBlockingPhase()

        // Step 5: Warm-up tasks (HealthKit, local data, sync) in background
        scheduleWarmUpTasksIfNeeded()
    }

    private func resetLoadingState() {
        isLoading = true
        progress = 0.0
        completedWeight = 0.0
    }

    private func performInitializationStep() async {
        await updateProgress(for: .initialize)
    }

    private func performAuthStep() async {
        await updateProgress(for: .checkAuth, partial: 0.5)

        // Skip Clerk loading wait if using mock auth
        if !Constants.useMockAuth {
            let clerkTask = authManager.ensureClerkInitializationTask()
            let maxWaitTimeNanoseconds: UInt64 = 500_000_000 // 0.5 seconds
            let clerkReady = await waitForClerkInitialization(
                task: clerkTask,
                timeoutNanoseconds: maxWaitTimeNanoseconds
            )

            if clerkReady {
                // print("✅ LoadingManager: Clerk loaded successfully")
            } else if authManager.clerkInitError != nil {
                // print("⚠️ LoadingManager: Clerk failed to load: \(error)")
            } else {
                // print("⚠️ LoadingManager: Clerk loading timed out after \(Double(maxWaitTimeNanoseconds) / 1_000_000_000)s")
            }
        }

        await updateProgress(for: .checkAuth)
    }

    private func performProfileStepIfNeeded() async {
        if authManager.isAuthenticated {
            await updateProgress(for: .loadProfile, partial: 0.3)

            if let userId = authManager.currentUser?.id {
                // print("📱 LoadingManager: Loading profile for user \(userId)")

                // Load profile from Core Data first
                if let cachedProfile = await coreDataManager.fetchProfile(for: userId) {
                    let profile = cachedProfile.toUserProfile()
                    // Update auth manager with cached profile
                    if let currentUser = authManager.currentUser {
                        let updatedUser = User(
                            id: currentUser.id,
                            email: currentUser.email,
                            name: currentUser.name,
                            profile: profile
                        )
                        authManager.currentUser = updatedUser

                        // Sync onboarding state to UserDefaults via OnboardingStateManager
                        if let onboardingCompleted = profile.onboardingCompleted {
                            OnboardingStateManager.shared.syncCompletionFlagFromProfile(onboardingCompleted)
                            // print("✅ LoadingManager: Synced onboarding status from profile: \(onboardingCompleted)")
                        }
                    }
                }
            } else {
                // print("⚠️ LoadingManager: Authenticated but no user ID available")
            }

            await updateProgress(for: .loadProfile)
        } else {
            // Skip profile step weight if not authenticated
            completedWeight += LoadingStep.loadProfile.weight
            progress = completedWeight
        }
    }

    private func completeBlockingPhase() async {
        await updateProgress(for: .complete)
        progress = 1.0
        loadingStatus = "Ready!"

        // Minimal delay just for UI transition
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        isLoading = false
    }

    private func scheduleWarmUpTasksIfNeeded() {
        if authManager.isAuthenticated {
            Task { @MainActor [weak self] in
                await self?.runWarmUpTasks()
            }
        }
    }

    func runWarmUpTasks() async {
        guard authManager.isAuthenticated else { return }

        await withTaskGroup(of: Void.self) { group in
            // Setup HealthKit
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                await self.healthSyncCoordinator.warmUpAfterLoginIfNeeded()
            }

            // Load local data / pending sync counts
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                self.syncManager.updatePendingSyncCount()
            }

            // Start sync (non-blocking for UI)
            group.addTask { @MainActor [weak self] in
                guard let self else { return }
                self.syncManager.syncIfNeeded()
            }

            await group.waitForAll()
        }
    }

    private func updateProgress(for step: LoadingStep, partial: Double = 1.0) async {
        loadingStatus = step.status

        let stepProgress = step.weight * partial
        completedWeight += stepProgress

        // Animate progress update
        withAnimation(.easeInOut(duration: 0.2)) { // Faster animation
            progress = min(completedWeight, 0.99) // Keep at 99% until truly complete
        }

        // Minimal delay only for UI responsiveness
        try? await Task.sleep(nanoseconds: 10_000_000) // 0.01s
    }

    private func waitForClerkInitialization(
        task: Task<Void, Never>,
        timeoutNanoseconds: UInt64
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await task.value
                return true
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}
