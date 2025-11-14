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
    private let healthKitManager = HealthKitManager.shared
    private let coreDataManager = CoreDataManager.shared
    private let syncManager = SyncManager.shared
    
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
    
    init(authManager: AuthManager) {
        self.authManager = authManager
    }
    
    func startLoading() async {
        isLoading = true
        progress = 0.0
        completedWeight = 0.0
        
        // Step 1: Initialize
        await updateProgress(for: .initialize)
        // Removed artificial 0.2s delay
        
        // Step 2: Check Authentication
        await updateProgress(for: .checkAuth, partial: 0.5)

        // Skip Clerk loading wait if using mock auth
        if !Constants.useMockAuth {
            // Wait for Clerk to be loaded with timeout
            let startTime = Date()
            let maxWaitTime: TimeInterval = 10.0 // Allow 10 seconds for Clerk to initialize (increased for slow networks)

            while !authManager.isClerkLoaded && authManager.clerkInitError == nil && Date().timeIntervalSince(startTime) < maxWaitTime {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s polling interval
            }

            // Log the result
            if authManager.isClerkLoaded {
                print("✅ LoadingManager: Clerk loaded successfully")
            } else if let error = authManager.clerkInitError {
                print("⚠️ LoadingManager: Clerk failed to load: \(error)")
            } else {
                print("⚠️ LoadingManager: Clerk loading timed out after \(maxWaitTime)s")
            }
        }

        await updateProgress(for: .checkAuth)
        
        // Step 3: Load Profile (if authenticated)
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

                        // Sync onboarding state to UserDefaults
                        if let onboardingCompleted = profile.onboardingCompleted {
                            UserDefaults.standard.set(onboardingCompleted, forKey: Constants.hasCompletedOnboardingKey)
                            print("✅ LoadingManager: Synced onboarding status from profile: \(onboardingCompleted)")
                        }
                    }
                }
            } else {
                // print("⚠️ LoadingManager: Authenticated but no user ID available")
            }
            
            await updateProgress(for: .loadProfile)
            
            // Run HealthKit, Local Data, and Sync concurrently
            await withTaskGroup(of: Void.self) { group in
                // Step 4: Setup HealthKit
                group.addTask { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.updateProgress(for: .setupHealthKit, partial: 0.3)
                    self.healthKitManager.checkAuthorizationStatus()
                    
                    if self.healthKitManager.isAuthorized {
                        // Request fresh data from HealthKit in background
                        Task.detached {
                            try? await self.healthKitManager.fetchTodayStepCount()
                        }
                    }
                    await self.updateProgress(for: .setupHealthKit)
                }
                
                // Step 5: Load Local Data
                group.addTask { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.updateProgress(for: .loadLocalData, partial: 0.5)
                    self.syncManager.updatePendingSyncCount()
                    await self.updateProgress(for: .loadLocalData)
                }
                
                // Step 6: Start Sync (non-blocking)
                group.addTask { @MainActor [weak self] in
                    guard let self = self else { return }
                    await self.updateProgress(for: .syncData, partial: 0.3)
                    
                    // Start sync in background - don't wait for completion
                    self.syncManager.syncIfNeeded()
                    
                    await self.updateProgress(for: .syncData)
                }
                
                // Wait for all concurrent tasks to complete
                await group.waitForAll()
            }
        } else {
            // Skip profile, healthkit, and sync steps if not authenticated
            completedWeight += LoadingStep.loadProfile.weight
            completedWeight += LoadingStep.setupHealthKit.weight
            completedWeight += LoadingStep.loadLocalData.weight
            completedWeight += LoadingStep.syncData.weight
            progress = completedWeight
        }
        
        // Step 7: Complete
        await updateProgress(for: .complete)
        progress = 1.0
        loadingStatus = "Ready!"
        
        // Minimal delay just for UI transition
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        isLoading = false
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
}
