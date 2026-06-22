//
// ChangePasswordView.swift
// LogYourBody
//
import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss)
    var dismiss
    @Environment(\.theme)
    private var theme
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
                VStack(spacing: theme.spacing.sectionSpacing) {
                    VStack(spacing: theme.spacing.md) {
                        ZStack {
                            Circle()
                                .fill(theme.colors.primary.opacity(0.12))
                                .frame(width: 80, height: 80)

                            Image(systemName: "lock.shield")
                                .font(theme.typography.displayMedium)
                                .foregroundColor(theme.colors.primary)
                        }
                        .padding(.top, theme.spacing.lg)

                        Text("Change Password")
                            .font(theme.typography.headlineMedium)
                            .foregroundColor(theme.colors.text)

                        Text("Create a strong password to protect your account")
                            .font(theme.typography.bodyMedium)
                            .foregroundColor(theme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, theme.spacing.lg)
                    }
                    .padding(.bottom, theme.spacing.lg)

                    // Form Fields
                    SettingsSection(header: "Current Password") {
                        SecureField("Enter current password", text: $currentPassword)
                            .textFieldStyle(.plain)
                            .textContentType(.password)
                            .focused($focusedField, equals: .current)
                            .onSubmit {
                                focusedField = .new
                            }
                            .settingsInputStyle()
                            .padding(.horizontal, theme.spacing.md)
                            .padding(.vertical, theme.spacing.xs)
                    }

                    SettingsSection(
                        header: "New Password",
                        footer: "Password must meet all requirements below"
                    ) {
                        VStack(spacing: theme.spacing.sm) {
                            SecureField("Enter new password", text: $newPassword)
                                .textFieldStyle(.plain)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .new)
                                .onSubmit {
                                    focusedField = .confirm
                                }
                                .settingsInputStyle()
                                .padding(.horizontal, theme.spacing.md)
                                .padding(.top, theme.spacing.xs)

                            VStack(alignment: .leading, spacing: theme.spacing.xs) {
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
                            .padding(.horizontal, theme.spacing.md)
                            .padding(.bottom, theme.spacing.xs)
                        }
                    }

                    SettingsSection(
                        header: "Confirm New Password",
                        footer: !confirmPassword.isEmpty && !passwordsMatch ? "Passwords don't match" : nil
                    ) {
                        SecureField("Re-enter new password", text: $confirmPassword)
                            .textFieldStyle(.plain)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .confirm)
                            .onSubmit {
                                if isValidForm {
                                    changePassword()
                                }
                            }
                            .settingsInputStyle()
                            .padding(.horizontal, theme.spacing.md)
                            .padding(.vertical, theme.spacing.xs)
                    }

                    BaseButton(
                        "Update Password",
                        configuration: ButtonConfiguration(
                            style: isValidForm
                                ? .custom(background: theme.colors.primary, foreground: theme.colors.text)
                                : .custom(background: theme.colors.interactiveDisabled, foreground: theme.colors.text),
                            isLoading: isLoading,
                            isEnabled: isValidForm,
                            fullWidth: true
                        ),
                        action: changePassword
                    )
                    .animation(theme.animation.fast, value: isValidForm)
                    .padding(.horizontal, theme.spacing.screenPadding)
                    .padding(.top, theme.spacing.lg)

                    Spacer(minLength: 40)
                }
                .padding(.vertical, theme.spacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
            .settingsBackground()

            // Loading overlay
            if isLoading {
                LoadingOverlay(message: "Updating password...")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isLoading)
        .standardErrorAlert(isPresented: $showError, message: errorMessage)
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
                try await authManager.changePassword(
                    currentPassword: currentPassword,
                    newPassword: newPassword
                )
                isLoading = false
                showSuccess = true
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

struct PasswordRequirement: View {
    @Environment(\.theme)
    private var theme

    let text: String
    let isMet: Bool

    var body: some View {
        HStack(spacing: theme.spacing.xs) {
            Image(systemName: isMet ? "checkmark.circle.fill" : "circle")
                .font(theme.typography.captionLarge)
                .foregroundColor(isMet ? theme.colors.success : theme.colors.textTertiary)

            Text(text)
                .font(theme.typography.captionLarge)
                .foregroundColor(isMet ? theme.colors.text : theme.colors.textSecondary)
        }
    }
}

#Preview {
    NavigationStack {
        ChangePasswordView()
            .environmentObject(AuthManager.shared)
            .preferredColorScheme(.dark)
    }
}
