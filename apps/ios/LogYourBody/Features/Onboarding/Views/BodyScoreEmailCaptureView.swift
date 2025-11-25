import SwiftUI

struct BodyScoreEmailCaptureView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @FocusState private var emailFieldFocused: Bool
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
                                .foregroundStyle(Color.red)
                        } else {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showWhyEmail.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("No spam. Only to save your progress.")
                                        .font(OnboardingTypography.caption)
                                }
                                .foregroundStyle(Color.appTextSecondary)
                            }
                            .buttonStyle(.plain)

                            if showWhyEmail {
                                Text("We'll only use this email to save your Body Score and keep progress in sync.")
                                    .font(OnboardingTypography.body)
                                    .foregroundStyle(Color.appTextSecondary)
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
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                .disabled(!viewModel.canContinueEmailCapture)
                .opacity(continueButtonOpacity)
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
    }
}

private extension BodyScoreEmailCaptureView {
    var continueButtonOpacity: Double {
        viewModel.canContinueEmailCapture ? 1 : 0.4
    }

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
}

#Preview {
    BodyScoreEmailCaptureView(viewModel: OnboardingFlowViewModel())
        .preferredColorScheme(.dark)
}
