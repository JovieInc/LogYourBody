//
// ContentView.swift
// LogYourBody
//
import SwiftUI

enum LaunchSurfacePolicy {
    static func requiresBodyCompositionOnboarding(
        hasCompletedOnboarding: Bool
    ) -> Bool {
        !hasCompletedOnboarding
    }

    static func requiresCompleteProfile(
        isProfileComplete: Bool
    ) -> Bool {
        !isProfileComplete
    }
}

enum EntryDeepLinkPolicy {
    static func canOpenEntrySheet(
        isAuthenticated: Bool,
        user: User?,
        hasCompletedOnboarding: Bool,
        isSubscribed: Bool
    ) -> Bool {
        guard isAuthenticated else { return false }

        let isProfileComplete = ProfileCompletionPolicy.isComplete(user: user)

        return !LaunchSurfacePolicy.requiresBodyCompositionOnboarding(
            hasCompletedOnboarding: hasCompletedOnboarding
        ) &&
            !LaunchSurfacePolicy.requiresCompleteProfile(
                isProfileComplete: isProfileComplete
            ) &&
            isSubscribed
    }
}

enum ProfileCompletionPolicy {
    static func isComplete(user: User?) -> Bool {
        guard let user else { return false }
        return isComplete(profile: user.profile, fallbackName: user.name)
    }

    static func isComplete(profile: UserProfile?, fallbackName: String?) -> Bool {
        guard let profile else { return false }

        let profileName = profile.fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDisplayName = fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = profileName?.isEmpty == false ? profileName : fallbackDisplayName
        let hasName = !(displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasDOB = profile.dateOfBirth != nil
        let hasHeight = (profile.height ?? 0) > 0
        let hasGender = !(profile.gender?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        return hasName && hasDOB && hasHeight && hasGender
    }
}

private struct ProfileCompletionSyncKey: Equatable {
    let userId: String?
    let completionFlag: Bool
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var realtimeSyncManager: RealtimeSyncManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var bugReportManager: BugReportManager
    @StateObject private var loadingManager: LoadingManager
    @StateObject private var notificationManager = NotificationManager.shared
    private let onboardingStateManager = OnboardingStateManager.shared
    @State private var currentUserId: String?
    @State private var hasCompletedOnboarding = OnboardingStateManager.shared.hasCompletedCurrentVersion
    @State private var lastProfileCompletionSync: ProfileCompletionSyncKey?
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
        let userId = currentUserId ?? authManager.currentUser?.id
        let syncKey = ProfileCompletionSyncKey(userId: userId, completionFlag: completionFlag)
        guard lastProfileCompletionSync != syncKey else { return }

        lastProfileCompletionSync = syncKey
        onboardingStateManager.syncCompletionFlagFromProfile(completionFlag, userId: userId)
        hasCompletedOnboarding = onboardingStateManager.hasCompletedCurrentVersion(for: userId)
    }

    // Check if user profile is complete
    private var isProfileComplete: Bool {
        ProfileCompletionPolicy.isComplete(user: authManager.currentUser)
    }

    private var shouldShowOnboarding: Bool {
        LaunchSurfacePolicy.requiresBodyCompositionOnboarding(
            hasCompletedOnboarding: hasCompletedOnboarding
        )
    }

    private var shouldShowProfileCompletion: Bool {
        LaunchSurfacePolicy.requiresCompleteProfile(
            isProfileComplete: isProfileComplete
        )
    }

    private var shouldShowDailyReminderPrompt: Bool {
        notificationManager.shouldShowPostPaywallPrompt(
            isSubscribed: subscriptionManager.isSubscribed
        )
    }

    private func completeLaunchOverlayIfReady() {
        guard !isLoadingComplete,
              loadingManager.progress >= 1.0 else {
            return
        }

        withAnimation(.easeInOut(duration: 0.25)) {
            isLoadingComplete = true
        }
    }

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            mainContent
            biometricLockOverlay
            loadingOverlay
        }
        .preferredColorScheme(.dark)
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        // Toast presenter removed - handle notifications at view level
        .fullScreenCover(isPresented: $showLegalConsent) {
            LegalConsentView(
                isPresented: $showLegalConsent,
                userId: authManager.currentUser?.id ?? "",
                onAccept: {
                    await authManager.acceptLegalConsent(userId: authManager.currentUser?.id ?? "")
                }
            )
            .interactiveDismissDisabled(true) // Prevent dismissing without accepting
        }
        .onAppear {
            // Initialize onboarding status
            currentUserId = authManager.currentUser?.id
            hasCompletedOnboarding = onboardingStateManager.hasCompletedCurrentVersion(for: currentUserId)

            // Fallback: Check profile if UserDefaults doesn't have it
            if !hasCompletedOnboarding {
                applyProfileCompletionIfNeeded(authManager.currentUser?.profile?.onboardingCompleted)
            }

            // Start loading process
            Task {
                await loadingManager.startLoading()
                completeLaunchOverlayIfReady()
            }
        }
        .onChange(of: loadingManager.isLoading) { _, _ in
            completeLaunchOverlayIfReady()
        }
        .onChange(of: loadingManager.progress) { _, _ in
            completeLaunchOverlayIfReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: OnboardingStateManager.onboardingStateDidChange)) { _ in
            hasCompletedOnboarding = onboardingStateManager.hasCompletedCurrentVersion(for: currentUserId)
        }
        .onChange(of: authManager.isAuthenticated) { _, newValue in
            currentUserId = authManager.currentUser?.id
            if newValue {
                hasCompletedOnboarding = onboardingStateManager.hasCompletedCurrentVersion(for: currentUserId)
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
        .onShake {
            bugReportManager.handleShakeGesture()
        }
    }

    private var mainContent: some View {
        Group {
            if authManager.isAuthenticated {
                authenticatedContent
            } else {
                loginContent
            }
        }
        .transition(.opacity)
    }

    private var authenticatedContent: some View {
        Group {
            if shouldShowOnboarding {
                BodyScoreOnboardingFlowView()
                    .onAppear {
                        AppServicePorts.analyticsTracker.track(event: "onboarding_view")
                    }
            } else if shouldShowProfileCompletion {
                ProfileCompletionGateView()
            } else if !subscriptionManager.isSubscribed {
                PaywallView()
                    .environmentObject(authManager)
                    .environmentObject(subscriptionManager)
            } else if shouldShowDailyReminderPrompt {
                DailyWeighInReminderPromptView(notificationManager: notificationManager)
            } else {
                MainTabView()
                    .onAppear {
                        AppServicePorts.analyticsTracker.track(event: "dashboard_view")
                    }
            }
        }
    }

    private var loginContent: some View {
        NavigationStack {
            LoginView()
        }
    }

    private var biometricLockOverlay: some View {
        Group {
            if authManager.isAuthenticated && biometricLockEnabled && !isUnlocked {
                BiometricLockView(isUnlocked: $isUnlocked)
                    .transition(AnyTransition.opacity)
            }
        }
    }

    private var loadingOverlay: some View {
        Group {
            if !isLoadingComplete && loadingManager.progress < 1.0 {
                LoadingView(
                    progress: $loadingManager.progress,
                    loadingStatus: $loadingManager.loadingStatus,
                    onComplete: {
                        completeLaunchOverlayIfReady()
                    }
                )
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager.shared)
        .environmentObject(RealtimeSyncManager.shared)
}
