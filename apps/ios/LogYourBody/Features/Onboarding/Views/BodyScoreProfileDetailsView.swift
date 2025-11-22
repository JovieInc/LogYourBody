import SwiftUI

struct BodyScoreProfileDetailsView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    private var canContinue: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            isDateOfBirthWithinValidRange
    }

    private var isDateOfBirthWithinValidRange: Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        guard let age = components.year else { return false }
        return age >= 16 && age <= 80
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Finish your profile",
            subtitle: "Add your name and birthday to personalize your experience.",
            onBack: { viewModel.goBack() },
            progress: viewModel.progress(for: .profileDetails),
            content: {
                VStack(spacing: 24) {
                    nameSection
                    dobSection
                }
            },
            footer: {
                VStack(spacing: 12) {
                    Button(action: submit) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else {
                            Text("Continue")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .disabled(!canContinue || isSaving)
                    .opacity(canContinue ? 1 : 0.4)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(Color.red)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        )
        .onAppear {
            hydrateFromCurrentUser()
        }
    }

    private var nameSection: some View {
        OnboardingFormSection(title: "Name", caption: "We use this to personalize your experience.") {
            OnboardingTextFieldRow(
                title: "First name",
                placeholder: "First name",
                text: $firstName
            )

            OnboardingTextFieldRow(
                title: "Last name",
                placeholder: "Last name",
                text: $lastName
            )
        }
    }

    private var dobSection: some View {
        OnboardingFormSection(title: "Birthday", caption: "Used only for age-based insights.") {
            DatePicker(
                "Date of Birth",
                selection: $dateOfBirth,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        }
    }

    private func hydrateFromCurrentUser() {
        guard let user = authManager.currentUser else { return }

        let baseName = user.profile?.fullName ?? user.name ?? ""
        let components = baseName.split(separator: " ")
        if !components.isEmpty {
            firstName = String(components.first ?? "")
            if components.count > 1 {
                lastName = components.dropFirst().joined(separator: " ")
            }
        }

        if let existingDob = user.profile?.dateOfBirth {
            dateOfBirth = existingDob
        }
    }

    private func submit() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let trimmedFirst = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLast = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullName = "\(trimmedFirst) \(trimmedLast)".trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                if !fullName.isEmpty {
                    try await authManager.consolidateNameUpdate(fullName)
                }

                var updates: [String: Any] = [
                    "dateOfBirth": dateOfBirth,
                    "onboardingCompleted": true
                ]

                await authManager.updateProfile(updates)

                await MainActor.run {
                    isSaving = false
                    viewModel.goToNextStep()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
