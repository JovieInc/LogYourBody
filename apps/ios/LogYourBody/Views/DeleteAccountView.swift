//
// DeleteAccountView.swift
// LogYourBody
//
import SwiftUI
import UIKit

enum AccountDeletionConfirmationPolicy {
    static let confirmationPhrase = "DELETE"

    /// The delete action is armed only by an exact, case-sensitive match of the phrase.
    static func isValidConfirmation(_ text: String) -> Bool {
        text == confirmationPhrase
    }

    /// Guidance shown once the user has typed something that does not match the phrase.
    static func validationMessage(for text: String) -> String? {
        guard !text.isEmpty, !isValidConfirmation(text) else { return nil }
        return "Type \(confirmationPhrase) exactly to enable account deletion."
    }
}

struct DeleteAccountView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.theme)
    private var theme
    @State private var showConfirmation = false
    @State private var confirmationText = ""
    @State private var isDeleting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var isTextFieldFocused: Bool

    private let confirmationPhrase = AccountDeletionConfirmationPolicy.confirmationPhrase

    private var hasValidConfirmation: Bool {
        AccountDeletionConfirmationPolicy.isValidConfirmation(confirmationText)
    }

    private var confirmationValidationMessage: String? {
        AccountDeletionConfirmationPolicy.validationMessage(for: confirmationText)
    }

    var body: some View {
        ZStack {
            Color.jovieCanvas
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: JovieTokens.sectionGap) {
                    deletionHeader
                    deletionSummary
                    accountBoundaryNotice
                    confirmationSection
                }
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.top, JovieTokens.sectionGap)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            if isDeleting {
                LoadingOverlay(message: "Deleting your account...")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            deleteAction
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
            Text(
                "This permanently deletes your account and app-stored data. Apple Health data stays in Health. " +
                    "This does not cancel an App Store subscription."
            )
        }
        .onChange(of: showError) { _, isShowing in
            if isShowing {
                UIAccessibility.post(notification: .announcement, argument: errorMessage)
            }
        }
    }

    private var deletionHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Permanent action", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.colors.error)

            Text("Delete your account")
                .font(.title2.weight(.bold))
                .foregroundColor(.jovieText)

            Text("This cannot be undone. Your LogYourBody data will be permanently deleted.")
                .font(.body)
                .foregroundColor(.jovieTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var deletionSummary: some View {
        SettingsSection(header: "What will be deleted") {
            VStack(spacing: 0) {
                DataInfoRow(
                    icon: "scalemass",
                    title: "Body records",
                    description: "Weight, body composition, and measurements",
                    iconColor: theme.colors.error
                )

                Divider()

                DataInfoRow(
                    icon: "photo.on.rectangle",
                    title: "Progress data",
                    description: "Photos, daily logs, and notes stored in LogYourBody",
                    iconColor: theme.colors.error
                )

                Divider()

                DataInfoRow(
                    icon: "person.crop.circle",
                    title: "Account data",
                    description: "Profile, goals, preferences, and local app data",
                    iconColor: theme.colors.error
                )
            }
        }
    }

    private var accountBoundaryNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Apple Health data stays in the Health app.", systemImage: "heart.text.square")
            Label(
                "Deleting your account does not cancel an App Store subscription. Manage subscriptions in the App Store.",
                systemImage: "creditcard"
            )
        }
        .font(.footnote)
        .foregroundColor(.jovieTextSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                .fill(Color.jovieSurfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                .stroke(Color.jovieHairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var confirmationSection: some View {
        SettingsSection(
            header: "Confirm permanent deletion",
            footer: "Type \"\(confirmationPhrase)\" exactly to enable account deletion."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Type \(confirmationPhrase)", text: $confirmationText)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .focused($isTextFieldFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isTextFieldFocused = false
                    }
                    .settingsInputStyle()
                    .frame(minHeight: JovieTokens.minimumHitTarget)
                    .accessibilityLabel("Deletion confirmation")
                    .accessibilityHint("Type DELETE exactly to enable account deletion.")
                    .accessibilityIdentifier("delete_account_confirmation_field")

                if let confirmationValidationMessage {
                    Label(confirmationValidationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(theme.colors.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("delete_account_confirmation_error")
                }
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.sm)
        }
    }

    private var deleteAction: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.jovieHairline)
                .frame(height: 1)

            BaseButton(
                "Delete account",
                configuration: ButtonConfiguration(
                    style: hasValidConfirmation
                        ? .custom(background: theme.colors.error, foreground: .jovieText)
                        : .custom(background: theme.colors.interactiveDisabled, foreground: .jovieTextSecondary),
                    isLoading: isDeleting,
                    isEnabled: hasValidConfirmation,
                    fullWidth: true,
                    cornerRadius: JovieTokens.controlRadius
                ),
                action: {
                    isTextFieldFocused = false
                    deleteAccount()
                }
            )
            .accessibilityIdentifier("delete_account_confirm_button")
            .accessibilityHint(
                hasValidConfirmation
                    ? "Shows one final confirmation before permanently deleting your account."
                    : "Type DELETE exactly to enable this action."
            )
            .padding(.horizontal, JovieTokens.screenInset)
            .padding(.vertical, 12)
        }
        .background(Color.jovieCanvas.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }

    private func deleteAccount() {
        guard hasValidConfirmation else { return }
        showConfirmation = true
    }

    private func performDeletion() {
        isDeleting = true

        Task {
            do {
                try await AccountDeletionCleanupService.live(
                    authManager: authManager,
                    deleteProductAccount: authManager.deleteCurrentAccount
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
}

struct AccountDeletionCleanupService {
    struct Dependencies {
        var logoutSubscriptionProvider: () async -> Void
        var resetHealthKitAnchors: () async -> Void
        var deleteProductAccount: () async throws -> Void
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
        Constants.goalWeightKilogramsKey,
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
        HealthKitDefaultsKey.authorizationConfirmed.rawValue,
        HealthKitDefaultsKey.lastObserverSyncDate.rawValue,
        HealthKitDefaultsKey.fullSyncCompleted.rawValue,
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
        deleteProductAccount: @escaping () async throws -> Void
    ) -> AccountDeletionCleanupService {
        AccountDeletionCleanupService(
            dependencies: Dependencies(
                logoutSubscriptionProvider: {
                    // Dissociates subscription state from the deleted account; subscriptions expire normally.
                    await SubscriptionManager.shared.logoutUser()
                },
                resetHealthKitAnchors: {
                    await HealthSyncCoordinator.shared.resetForCurrentUser()
                },
                deleteProductAccount: deleteProductAccount,
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
        await dependencies.logoutSubscriptionProvider()
        await dependencies.resetHealthKitAnchors()
        try await dependencies.deleteProductAccount()

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
