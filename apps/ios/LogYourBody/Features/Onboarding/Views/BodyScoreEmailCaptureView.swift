import SwiftUI

struct BodyScoreEmailCaptureView: View {
    @Environment(\.theme)
    private var theme

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var emailFieldFocused: Bool
    @AccessibilityFocusState private var emailErrorFocused: Bool
    @State private var emailError: String?
    @State private var showWhyEmail = false

    var body: some View {
        OnboardingPageTemplate(
            title: "Save your score?",
            subtitle: "Enter email to sync across devices.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .emailCapture),
            content: {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        OnboardingTextFieldRow(
                            title: "Email address",
                            placeholder: "you@domain.com",
                            text: Binding(
                                get: { viewModel.emailAddress },
                                set: { viewModel.emailAddress = $0 }
                            ),
                            keyboardType: .emailAddress
                        )
                        .focused($emailFieldFocused)
                        .onChange(of: viewModel.emailAddress) { _, _ in
                            updateEmailError()
                        }

                        if let error = emailError {
                            Text(error)
                                .font(OnboardingTypography.caption)
                                .foregroundStyle(theme.colors.error)
                                .accessibilityFocused($emailErrorFocused)
                        } else {
                            Button {
                                toggleWhyEmail()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.system(.footnote, design: .default).weight(.semibold))
                                    Text("No spam. Only to save your progress.")
                                        .font(OnboardingTypography.caption)
                                }
                                .foregroundStyle(theme.colors.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .jovieTouchTarget()
                            .accessibilityValue(showWhyEmail ? "Expanded" : "Collapsed")

                            if showWhyEmail {
                                Text("We'll only use this email to save your Body Score and keep progress in sync.")
                                    .font(OnboardingTypography.body)
                                    .foregroundStyle(theme.colors.textSecondary)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
            },
            footer: {
                Button {
                    viewModel.persistEmailCapture()
                    viewModel.goToNextStep()
                } label: {
                    Text("Continue")
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueEmailCapture)
            }
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.emailFieldFocused = true
            }
            updateEmailError()
        }
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        emailFieldFocused = false
                    }
                }
            }
        }
        .onChange(of: emailError) { _, error in
            emailErrorFocused = error != nil
        }
    }
}

private extension BodyScoreEmailCaptureView {
    private func updateEmailError() {
        let trimmed = viewModel.emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emailError = nil
            return
        }

        if viewModel.canContinueEmailCapture {
            emailError = nil
        } else {
            emailError = "Enter a valid email address."
        }
    }

    private func toggleWhyEmail() {
        if reduceMotion {
            showWhyEmail.toggle()
        } else {
            withAnimation(theme.animation.fast) {
                showWhyEmail.toggle()
            }
        }
    }
}

#Preview {
    BodyScoreEmailCaptureView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
