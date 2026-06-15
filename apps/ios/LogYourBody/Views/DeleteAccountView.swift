//
// DeleteAccountView.swift
// LogYourBody
//
import SwiftUI
import Clerk

struct DeleteAccountView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.theme)
    private var theme
    @State private var showConfirmation = false
    @State private var confirmationText = ""
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isTextFieldFocused: Bool

    private let confirmationPhrase = "DELETE"

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: theme.spacing.sectionSpacing) {
                    VStack(spacing: theme.spacing.md) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(theme.typography.displayMedium)
                            .foregroundColor(theme.colors.error)
                            .padding(.top, theme.spacing.lg)

                        Text("Delete Account")
                            .font(theme.typography.headlineMedium)
                            .foregroundColor(theme.colors.text)

                        Text(
                            "This action cannot be undone. Your LogYourBody data will be permanently deleted. " +
                                "Data in Apple Health stays in the Health app."
                        )
                        .font(theme.typography.bodyMedium)
                        .foregroundColor(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, theme.spacing.lg)
                    }
                    .padding(.bottom, theme.spacing.lg)

                    SettingsSection(header: "What will be deleted") {
                        VStack(spacing: 0) {
                            DataInfoRow(
                                icon: "scalemass",
                                title: "All weight entries",
                                iconColor: theme.colors.error
                            )

                            Divider()

                            DataInfoRow(
                                icon: "person.circle",
                                title: "Your profile information",
                                iconColor: theme.colors.error
                            )

                            Divider()

                            DataInfoRow(
                                icon: "heart.fill",
                                title: "Health data stored in LogYourBody",
                                iconColor: theme.colors.error
                            )

                            Divider()

                            DataInfoRow(
                                icon: "creditcard.fill",
                                title: "Active subscription (if any)",
                                iconColor: theme.colors.error
                            )
                        }
                    }

                    // Confirm deletion section
                    SettingsSection(
                        header: "Confirm deletion",
                        footer: "Type \"\(confirmationPhrase)\" to confirm account deletion"
                    ) {
                        VStack(spacing: 12) {
                            TextField("Type \(confirmationPhrase)", text: $confirmationText)
                                .textFieldStyle(.plain)
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                                .focused($isTextFieldFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    isTextFieldFocused = false
                                }
                                .settingsInputStyle()
                                .padding(.horizontal, theme.spacing.md)
                                .padding(.vertical, theme.spacing.xs)
                        }
                    }

                    BaseButton(
                        "Delete My Account",
                        configuration: ButtonConfiguration(
                            style: confirmationText == confirmationPhrase
                                ? .custom(background: theme.colors.error, foreground: theme.colors.text)
                                : .custom(background: theme.colors.interactiveDisabled, foreground: theme.colors.text),
                            isLoading: isDeleting,
                            isEnabled: confirmationText == confirmationPhrase,
                            fullWidth: true
                        ),
                        action: {
                            isTextFieldFocused = false
                            deleteAccount()
                        }
                    )
                    .padding(.horizontal, theme.spacing.screenPadding)

                    Color.clear
                        .frame(height: 100)
                }
                .padding(.vertical, theme.spacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .settingsBackground()

            // Loading overlay
            if isDeleting {
                LoadingOverlay(message: "Deleting your account...")
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .standardErrorAlert(isPresented: $showError, message: errorMessage)
        .confirmationDialog("Delete Account?", isPresented: $showConfirmation) {
            Button("Delete", role: .destructive) {
                performDeletion()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete your account? This cannot be undone.")
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(
            SuccessOverlay(
                isShowing: .constant(false),
                message: ""
            )
        )
    }

    private func deleteAccount() {
        guard confirmationText == confirmationPhrase else { return }
        showConfirmation = true
    }

    private func performDeletion() {
        isDeleting = true

        Task {
            do {
                try await AccountDeletionCleanupService.live(
                    authManager: authManager,
                    deleteClerkAccount: deleteClerkAccount
                ).performDeletion()
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = "Failed to delete account: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    private func deleteClerkAccount() async throws {
        // Use Clerk SDK to delete the user account
        guard let user = Clerk.shared.user else {
            throw NSError(domain: "DeleteAccount", code: 1, userInfo: [NSLocalizedDescriptionKey: "No user found"])
        }

        // Delete the user through Clerk
        try await user.delete()
    }
}

struct AccountDeletionCleanupService {
    struct Dependencies {
        var logoutRevenueCat: () async -> Void
        var resetHealthKitAnchors: () async -> Void
        var notifyBackendOfAccountDeletion: () async -> Void
        var deleteClerkAccount: () async throws -> Void
        var deleteCoreData: () async throws -> Void
        var clearKeychain: () -> Void
        var deleteSpotlightMetrics: () -> Void
        var clearUserDefaults: () -> [String]
        var logoutAuthSession: () async -> Void
    }

    static let accountUserDefaultsKeys: [String] = [
        Constants.hasCompletedOnboardingKey,
        Constants.onboardingCompletedVersionKey,
        Constants.onboardingCompletedUserIdKey,
        Constants.preferredWeightUnitKey,
        Constants.preferredMeasurementSystemKey,
        Constants.goalWeightKey,
        Constants.goalBodyFatPercentageKey,
        Constants.goalFFMIKey,
        Constants.timelineModeKey,
        Constants.defaultHomeModeKey,
        Constants.deletePhotosAfterImportKey,
        Constants.hasPromptedDeletePhotosKey,
        "stepGoal",
        "metricsOrder",
        "dashboard_selected_time_range",
        "dashboard_weight_uses_trend",
        "biometricLockEnabled",
        "revenuecat_isSubscribed",
        "revenuecat_lastFetchTimestamp",
        "healthKitSyncEnabled",
        "HasSyncedHistoricalSteps",
        "lastSupabaseSyncDate",
        "lastHealthKitWeightSyncDate",
        "appleSignInName",
        "lastSyncDate",
        "hasSeenWhatsNew"
    ]

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    static func live(
        authManager: AuthManager,
        deleteClerkAccount: @escaping () async throws -> Void
    ) -> AccountDeletionCleanupService {
        AccountDeletionCleanupService(
            dependencies: Dependencies(
                logoutRevenueCat: {
                    // Dissociates RevenueCat from the deleted account; subscriptions expire normally.
                    await RevenueCatManager.shared.logoutUser()
                },
                resetHealthKitAnchors: {
                    await HealthSyncCoordinator.shared.resetForCurrentUser()
                },
                notifyBackendOfAccountDeletion: {
                    await authManager.notifyBackendOfAccountDeletion()
                },
                deleteClerkAccount: deleteClerkAccount,
                deleteCoreData: {
                    try await CoreDataManager.shared.deleteAllDataAndWait()
                },
                clearKeychain: {
                    try? KeychainManager.shared.clearAll()
                },
                deleteSpotlightMetrics: {
                    BodyMetricSpotlightIndexer.deleteAllIndexedMetrics()
                },
                clearUserDefaults: {
                    clearAccountUserDefaults(in: .standard)
                },
                logoutAuthSession: {
                    await authManager.logout()
                }
            )
        )
    }

    func performDeletion() async throws {
        await dependencies.logoutRevenueCat()
        await dependencies.resetHealthKitAnchors()
        await dependencies.notifyBackendOfAccountDeletion()
        try await dependencies.deleteClerkAccount()

        var localCleanupError: Error?
        do {
            try await dependencies.deleteCoreData()
        } catch {
            localCleanupError = error
        }

        dependencies.clearKeychain()
        _ = dependencies.clearUserDefaults()
        dependencies.deleteSpotlightMetrics()
        await dependencies.logoutAuthSession()

        if let localCleanupError {
            throw localCleanupError
        }
    }

    @discardableResult
    static func clearAccountUserDefaults(in defaults: UserDefaults) -> [String] {
        var removedKeys = AuthManager.migrateLegacyAuthStorage(in: defaults)

        for key in accountUserDefaultsKeys where defaults.object(forKey: key) != nil {
            defaults.removeObject(forKey: key)
            removedKeys.append(key)
        }

        return removedKeys
    }
}

#Preview {
    NavigationStack {
        DeleteAccountView()
            .environmentObject(AuthManager())
    }
}
