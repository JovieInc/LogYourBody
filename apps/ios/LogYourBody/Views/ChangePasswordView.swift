//
// ChangePasswordView.swift
// LogYourBody
//
import SwiftUI
import Clerk

struct ChangePasswordView: View {
    @Environment(\.dismiss)
    var dismiss
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @FocusState private var focusedField: Field?

    enum Field {
        case current, new, confirm
    }

    private var isValidForm: Bool {
        !currentPassword.isEmpty &&
            newPassword.count >= 8 &&
            newPassword == confirmPassword &&
            hasUpperAndLower &&
            hasNumberOrSymbol
    }

    private var hasUpperAndLower: Bool {
        let hasUpper = newPassword.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLower = newPassword.rangeOfCharacter(from: .lowercaseLetters) != nil
        return hasUpper && hasLower
    }

    private var hasNumberOrSymbol: Bool {
        let hasNumber = newPassword.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbol = newPassword.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil
        return hasNumber || hasSymbol
    }

    private var passwordsMatch: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: SettingsDesign.sectionSpacing) {
                    // Header Icon
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(Color.appPrimary.opacity(0.1))
                                .frame(width: 80, height: 80)

                            Image(systemName: "lock.shield")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundColor(.appPrimary)
                        }
                        .padding(.top, 20)

                        Text("Change Password")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text("Create a strong password to protect your account")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.bottom, 20)

                    // Form Fields
                    SettingsSection(header: "Current Password") {
                        SecureField("Enter current password", text: $currentPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.password)
                            .focused($focusedField, equals: .current)
                            .onSubmit {
                                focusedField = .new
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, 8)
                    }

                    SettingsSection(
                        header: "New Password",
                        footer: "Password must meet all requirements below"
                    ) {
                        VStack(spacing: 12) {
                            SecureField("Enter new password", text: $newPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .new)
                                .onSubmit {
                                    focusedField = .confirm
                                }
                                .padding(.horizontal, SettingsDesign.horizontalPadding)
                                .padding(.top, 8)

                            // Password Requirements
                            VStack(alignment: .leading, spacing: 8) {
                                PasswordRequirement(
                                    text: "At least 8 characters",
                                    isMet: newPassword.count >= 8
                                )

                                PasswordRequirement(
                                    text: "Mix of uppercase and lowercase",
                                    isMet: hasUpperAndLower
                                )

                                PasswordRequirement(
                                    text: "At least one number or symbol",
                                    isMet: hasNumberOrSymbol
                                )
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.bottom, 8)
                        }
                    }

                    SettingsSection(
                        header: "Confirm New Password",
                        footer: !confirmPassword.isEmpty && !passwordsMatch ? "Passwords don't match" : nil
                    ) {
                        SecureField("Re-enter new password", text: $confirmPassword)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirm)
                            .onSubmit {
                                if isValidForm {
                                    changePassword()
                                }
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, 8)
                    }

                    // Submit Button
                    BaseButton(
                        "Update Password",
                        configuration: ButtonConfiguration(
                            style: isValidForm
                                ? .custom(background: .appPrimary, foreground: .white)
                                : .custom(background: .gray, foreground: .white),
                            isLoading: isLoading,
                            isEnabled: isValidForm,
                            fullWidth: true
                        ),
                        action: changePassword
                    )
                    .animation(.easeInOut(duration: 0.2), value: isValidForm)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    Spacer(minLength: 40)
                }
                .padding(.vertical)
            }
            .settingsBackground()

            // Loading overlay
            if isLoading {
                LoadingOverlay(message: "Updating password...")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isLoading)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .overlay(
            SuccessOverlay(
                isShowing: $showSuccess,
                message: "Password updated successfully"
            )
            .onChange(of: showSuccess) { _, newValue in
                if !newValue {
                    // Dismiss after success overlay disappears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        dismiss()
                    }
                }
            }
        )
        .onTapGesture {
            focusedField = nil
        }
    }

    private func changePassword() {
        guard isValidForm else { return }

        focusedField = nil
        isLoading = true

        Task { @MainActor in
            do {
                guard let user = Clerk.shared.user else {
                    throw PasswordError.notAuthenticated
                }

                // Update password using Clerk
                try await user.updatePassword(.init(
                    newPassword: newPassword,
                    currentPassword: currentPassword,
                    signOutOfOtherSessions: true
                ))

                isLoading = false
                showSuccess = true
            } catch {
                isLoading = false

                // Handle specific Clerk errors
                if let clerkError = error as? ClerkAPIError {
                    switch clerkError.code {
                    case "form_password_incorrect":
                        errorMessage = "Current password is incorrect"
                    case "form_password_not_strong_enough":
                        errorMessage = "Please choose a stronger password"
                    default:
                        errorMessage = clerkError.message ?? "Failed to update password"
                    }
                } else {
                    errorMessage = error.localizedDescription
                }

                showError = true
            }
        }
    }
}

struct PasswordRequirement: View {
    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundColor(isMet ? .green : .secondary)

            Text(text)
                .font(SettingsDesign.valueFont)
                .foregroundColor(isMet ? .primary : .secondary)
        }
    }
}

enum PasswordError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to change your password"
        }
    }
}

#Preview {
    NavigationView {
        ChangePasswordView()
            .preferredColorScheme(.dark)
    }
}
