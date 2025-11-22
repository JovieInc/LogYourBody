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
    @State private var currentUserId: String?
    @State private var hasCompletedOnboarding = OnboardingStateManager.shared.hasCompletedCurrentVersion
    @State private var lastProfileCompletionSync: Bool?
    @State private var isLoadingComplete = false
    @State private var isUnlocked = false
    @State private var showLegalConsent = false
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false

    init() {
        // We need to initialize LoadingManager with a temporary AuthManager
        // The actual authManager will be injected from environment
        _loadingManager = StateObject(wrappedValue: LoadingManager(authManager: AuthManager.shared))
    }

    private func applyProfileCompletionIfNeeded(_ completionFlag: Bool?) {
        guard let completionFlag else { return }
        guard lastProfileCompletionSync != completionFlag else { return }

        lastProfileCompletionSync = completionFlag
        onboardingStateManager.updateCompletionStatus(completionFlag)
        hasCompletedOnboarding = onboardingStateManager.hasCompletedCurrentVersion
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

    private var shouldShowOnboarding: Bool {
        return !hasCompletedOnboarding
    }

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            Group {
                if authManager.isAuthenticated {
                    if shouldShowOnboarding {
                        BodyScoreOnboardingFlowView()
                    } else if !revenueCatManager.isSubscribed {
                        PaywallView()
                            .environmentObject(authManager)
                            .environmentObject(revenueCatManager)
                            .onAppear {
                                // print("💰 Showing PaywallView")
                            }
                    } else {
                        MainTabView()
                            .onAppear {
                                // print("🏠 Showing MainTabView (Dashboard)")
                            }
                    }
                } else if authManager.needsEmailVerification {
                    NavigationStack {
                        EmailVerificationView()
                    }
                    .onAppear {
                        // print("📧 Showing EmailVerificationView")
                    }
                } else {
                    NavigationStack {
                        LoginView()
                    }
                    .onAppear {
                        // print("🔐 Showing LoginView")
                    }
                }
            }
            .transition(.opacity)

            if authManager.isAuthenticated && biometricLockEnabled && !isUnlocked {
                BiometricLockView(isUnlocked: $isUnlocked)
                    .transition(AnyTransition.opacity)
            }

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
            currentUserId = authManager.currentUser?.id

            // Fallback: Check profile if UserDefaults doesn't have it
            if !hasCompletedOnboarding {
                applyProfileCompletionIfNeeded(authManager.currentUser?.profile?.onboardingCompleted)
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
        .onChange(of: authManager.isAuthenticated) { _, newValue in
            currentUserId = authManager.currentUser?.id
            if newValue {
                hasCompletedOnboarding = onboardingStateManager.hasCompletedCurrentVersion
            } else {
                lastProfileCompletionSync = nil
                if hasCompletedOnboarding {
                    onboardingStateManager.updateCompletionStatus(false)
                    hasCompletedOnboarding = false
                }
            }
        }
        .onChange(of: authManager.currentUser?.id) { oldValue, newValue in
            guard oldValue != newValue else { return }
            currentUserId = newValue
            lastProfileCompletionSync = nil
            applyProfileCompletionIfNeeded(authManager.currentUser?.profile?.onboardingCompleted)
        }
        .onChange(of: authManager.currentUser?.profile?.onboardingCompleted) { _, newValue in
            // Sync onboarding status from profile when it changes
            applyProfileCompletionIfNeeded(newValue)
        }
        .onChange(of: hasCompletedOnboarding) { _, newValue in
            if newValue && isLoadingComplete {
                // print("🎯 Onboarding completed, transitioning to main app...")
                // Add a small delay to ensure smooth transition
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Force a view refresh if needed
                    withAnimation(.easeInOut(duration: 0.3)) {
                        // The view should automatically update based on shouldShowOnboarding
                    }
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
