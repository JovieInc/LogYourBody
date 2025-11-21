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
                VStack(spacing: SettingsDesign.sectionSpacing) {
                    // Header Section
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.red)
                            .padding(.top, 20)

                        Text("Delete Account")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("This action cannot be undone. All your data will be permanently deleted.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.bottom, 20)

                    // What will be deleted section
                    SettingsSection(header: "What will be deleted") {
                        VStack(spacing: 0) {
                            DataInfoRow(
                                icon: "scalemass",
                                title: "All weight entries",
                                iconColor: .red
                            )

                            Divider()

                            DataInfoRow(
                                icon: "person.circle",
                                title: "Your profile information",
                                iconColor: .red
                            )

                            Divider()

                            DataInfoRow(
                                icon: "heart.fill",
                                title: "Health data",
                                iconColor: .red
                            )

                            Divider()

                            DataInfoRow(
                                icon: "creditcard.fill",
                                title: "Active subscription (if any)",
                                iconColor: .red
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
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .autocapitalization(.allCharacters)
                                .disableAutocorrection(true)
                                .focused($isTextFieldFocused)
                                .submitLabel(.done)
                                .onSubmit {
                                    isTextFieldFocused = false
                                }
                                .padding(.horizontal, SettingsDesign.horizontalPadding)
                                .padding(.vertical, 8)
                        }
                    }

                    // Delete Button
                    BaseButton(
                        "Delete My Account",
                        configuration: ButtonConfiguration(
                            style: confirmationText == confirmationPhrase
                                ? .custom(background: .red, foreground: .white)
                                : .custom(background: .gray, foreground: .white),
                            isLoading: isDeleting,
                            isEnabled: confirmationText == confirmationPhrase,
                            fullWidth: true
                        ),
                        action: {
                            isTextFieldFocused = false
                            deleteAccount()
                        }
                    )
                    .padding(.horizontal, 20)

                    // Bottom padding
                    Color.clear
                        .frame(height: 100)
                }
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.interactively)
            .settingsBackground()

            // Loading overlay
            if isDeleting {
                LoadingOverlay(message: "Deleting your account...")
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
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
                // Log out from RevenueCat (this will dissociate the user from their subscription)
                // Note: The subscription itself will remain active until expiration
                // RevenueCat webhooks will handle backend cleanup
                await RevenueCatManager.shared.logoutUser()

                // Delete from Clerk
                try await deleteClerkAccount()

                // Clear local data
                await MainActor.run {
                    // Clear Core Data
                    CoreDataManager.shared.deleteAllData()

                    // Clear UserDefaults
                    UserDefaults.standard.removeObject(forKey: Constants.currentUserKey)
                    UserDefaults.standard.removeObject(forKey: Constants.authTokenKey)
                    UserDefaults.standard.removeObject(forKey: Constants.hasCompletedOnboardingKey)
                    UserDefaults.standard.removeObject(forKey: Constants.preferredWeightUnitKey)
                    UserDefaults.standard.removeObject(forKey: Constants.preferredMeasurementSystemKey)
                    UserDefaults.standard.removeObject(forKey: "healthKitSyncEnabled")

                    // Sign out
                    Task {
                        await authManager.logout()
                    }
                }
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

#Preview {
    NavigationView {
        DeleteAccountView()
            .environmentObject(AuthManager())
    }
}
