//
// ContentView.swift
// LogYourBody
//
import SwiftUI
struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var realtimeSyncManager: RealtimeSyncManager
    @EnvironmentObject var revenueCatManager: RevenueCatManager
    @StateObject private var loadingManager: LoadingManager
    private let onboardingStateManager = OnboardingStateManager.shared
    @State private var hasCompletedOnboarding = OnboardingStateManager.shared.hasCompletedCurrentVersion
    @State private var isLoadingComplete = false
    @State private var isUnlocked = false
    @State private var showLegalConsent = false
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    
    init() {
        // We need to initialize LoadingManager with a temporary AuthManager
        // The actual authManager will be injected from environment
        _loadingManager = StateObject(wrappedValue: LoadingManager(authManager: AuthManager.shared))
    }
    
    // Check if user profile is complete
    private var isProfileComplete: Bool {
        // Safely check if profile exists and is complete
        guard let user = authManager.currentUser,
              let profile = user.profile else {
            return false
        }

        // Check all required fields exist
        let hasName = profile.fullName != nil && !(profile.fullName?.isEmpty ?? true)
        let hasDOB = profile.dateOfBirth != nil
        let hasHeight = profile.height != nil && profile.height ?? 0 > 0
        let hasGender = profile.gender != nil && !(profile.gender?.isEmpty ?? true)

        return hasName && hasDOB && hasHeight && hasGender
    }
    
    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            if !isLoadingComplete {
                LoadingView(
                    progress: $loadingManager.progress,
                    loadingStatus: $loadingManager.loadingStatus,
                    onComplete: {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isLoadingComplete = true
                        }
                    }
                )
                .transition(.opacity)
            } else if authManager.isAuthenticated && biometricLockEnabled && !isUnlocked {
                // Show biometric lock screen
                BiometricLockView(isUnlocked: $isUnlocked)
                    .transition(AnyTransition.opacity)
            } else {
                Group {
                    if !hasCompletedOnboarding {
                        OnboardingFlowView()
                            .environmentObject(authManager)
                            .environmentObject(revenueCatManager)
                    } else if authManager.isAuthenticated {
                        if !revenueCatManager.isSubscribed {
                            PaywallView()
                                .environmentObject(authManager)
                                .environmentObject(revenueCatManager)
                        } else {
                            MainTabView()
                        }
                    } else if authManager.needsEmailVerification {
                        NavigationStack { EmailVerificationView() }
                    } else {
                        NavigationStack { LoginView() }
                    }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        // Toast presenter removed - handle notifications at view level
        .fullScreenCover(isPresented: $showLegalConsent) {
            LegalConsentView(
                isPresented: $showLegalConsent,
                userId: authManager.pendingAppleUserId ?? "",
                onAccept: {
                    await authManager.acceptLegalConsent(userId: authManager.pendingAppleUserId ?? "")
                }
            )
            .interactiveDismissDisabled(true) // Prevent dismissing without accepting
        }
        .onAppear {
            // Initialize onboarding status
            hasCompletedOnboarding = onboardingStateManager.hasCompletedCurrentVersion

            // Fallback: Check profile if UserDefaults doesn't have it
            if !hasCompletedOnboarding,
               let profileOnboardingCompleted = authManager.currentUser?.profile?.onboardingCompleted,
               profileOnboardingCompleted {
                onboardingStateManager.markCompleted()
                hasCompletedOnboarding = true
        // print("✅ ContentView: Synced onboarding status from profile to onboarding manager")
            }

            // Start loading process
            Task {
                await loadingManager.startLoading()
                // Check if loading is already complete
                if !loadingManager.isLoading && loadingManager.progress >= 1.0 {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isLoadingComplete = true
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: OnboardingStateManager.onboardingStateDidChange)) { _ in
            hasCompletedOnboarding = onboardingStateManager.hasCompletedCurrentVersion
        }
        .onChange(of: authManager.isAuthenticated) { _, _ in
            // print("🔄 Authentication state changed to: \(newValue)")
            // print("🔄 Onboarding completed: \(hasCompletedOnboarding)")
            // print("🔄 isLoadingComplete: \(isLoadingComplete)")
            // print("🔄 Current user: \(authManager.currentUser?.email ?? "nil")")
            // print("🔄 Clerk session: \(authManager.clerkSession?.id ?? "nil")")
        }
        .onChange(of: authManager.currentUser?.profile?.onboardingCompleted) { _, newValue in
            // Sync onboarding status from profile when it changes
            if let profileOnboardingCompleted = newValue {
                onboardingStateManager.updateCompletionStatus(profileOnboardingCompleted)
                hasCompletedOnboarding = onboardingStateManager.hasCompletedCurrentVersion
                if profileOnboardingCompleted {
        // print("✅ ContentView: Synced onboarding status from profile update")
                }
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, newValue in
            if newValue && isLoadingComplete {
                // print("🎯 Onboarding completed, transitioning to main app...")
                // Add a small delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.3)) {}
                }
            }
        }
        .onChange(of: authManager.needsLegalConsent) { _, newValue in
            showLegalConsent = newValue
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager.shared)
        .environmentObject(RealtimeSyncManager.shared)
}
