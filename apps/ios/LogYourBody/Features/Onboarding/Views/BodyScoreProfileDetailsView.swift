import SwiftUI

struct BodyScoreProfileDetailsView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var activeSubstep: ProfileSubstep = .firstName
    @FocusState private var focusedNameField: NameField?

    private var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFirstNameValid: Bool {
        !trimmedFirstName.isEmpty
    }

    private var isLastNameValid: Bool {
        !trimmedLastName.isEmpty
    }

    private var canContinue: Bool {
        switch activeSubstep {
        case .firstName:
            return isFirstNameValid
        case .lastName:
            return isLastNameValid
        case .dateOfBirth:
            return isFirstNameValid && isLastNameValid && isDateOfBirthWithinValidRange
        }
    }

    private var isDateOfBirthWithinValidRange: Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        guard let age = components.year else { return false }
        return age >= 16 && age <= 80
    }

    private var currentTitle: String {
        switch activeSubstep {
        case .firstName:
            return "What's your first name?"
        case .lastName:
            return "And your last name?"
        case .dateOfBirth:
            return "Birthday"
        }
    }

    private var currentSubtitle: String {
        switch activeSubstep {
        case .firstName:
            return "We'll use this to personalize your experience."
        case .lastName:
            return "We keep your name private and secure."
        case .dateOfBirth:
            return "Used for age-based insights."
        }
    }

    private var primaryButtonTitle: String {
        switch activeSubstep {
        case .firstName, .lastName:
            return "Continue"
        case .dateOfBirth:
            return "Continue"
        }
    }

    var body: some View {
        OnboardingPageTemplate(
            title: currentTitle,
            subtitle: currentSubtitle,
            onBack: {
                switch activeSubstep {
                case .firstName:
                    viewModel.goBack()
                case .lastName:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        activeSubstep = .firstName
                    }
                case .dateOfBirth:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        activeSubstep = .lastName
                    }
                }
            },
            progress: viewModel.progress(for: .profileDetails),
            content: {
                VStack(spacing: 24) {
                    switch activeSubstep {
                    case .firstName, .lastName:
                        nameSection
                    case .dateOfBirth:
                        dobSection
                    }
                }
            },
            footer: {
                VStack(spacing: 12) {
                    Button(action: handlePrimaryAction) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text(primaryButtonTitle)
                                .font(.system(size: 18, weight: .semibold))
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
            DispatchQueue.main.async {
                switch activeSubstep {
                case .firstName:
                    focusedNameField = .firstName
                case .lastName:
                    focusedNameField = .lastName
                case .dateOfBirth:
                    focusedNameField = nil
                }
            }
        }
        .onChange(of: activeSubstep) { _, newValue in
            DispatchQueue.main.async {
                switch newValue {
                case .firstName:
                    focusedNameField = .firstName
                case .lastName:
                    focusedNameField = .lastName
                case .dateOfBirth:
                    focusedNameField = nil
                }
            }
        }
    }

    private var nameSection: some View {
        OnboardingFormSection(title: "Name", caption: "We use this to personalize your experience.") {
            VStack(alignment: .leading, spacing: 16) {
                switch activeSubstep {
                case .firstName:
                    Text("First name")
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.appTextSecondary)

                    TextField("First name", text: $firstName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .submitLabel(.next)
                        .focused($focusedNameField, equals: .firstName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.appCard.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    focusedNameField == .firstName ? Color.appPrimary : Color.appBorder.opacity(0.6),
                                    lineWidth: 1
                                )
                        )
                        .onSubmit {
                            handleFirstNameContinue()
                        }

                case .lastName:
                    if isFirstNameValid {
                        Text("Nice to meet you,")
                            .font(OnboardingTypography.caption)
                            .foregroundStyle(Color.appTextSecondary)

                        Text(trimmedFirstName)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Color.appText)
                    }

                    Text("What's your last name?")
                        .font(OnboardingTypography.headline)
                        .foregroundStyle(Color.appText)

                    TextField("Last name", text: $lastName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .submitLabel(.next)
                        .focused($focusedNameField, equals: .lastName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.appCard.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    focusedNameField == .lastName ? Color.appPrimary : Color.appBorder.opacity(0.6),
                                    lineWidth: 1
                                )
                        )
                        .onSubmit {
                            handleLastNameContinue()
                        }

                case .dateOfBirth:
                    EmptyView()
                }
            }
        }
    }

    private var dobSection: some View {
        OnboardingFormSection(title: nil, caption: nil) {
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
        guard let user = authManager.currentUser else {
            recomputeActiveSubstep()
            return
        }

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

        recomputeActiveSubstep()
    }

    private func submit() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let trimmedFirst = trimmedFirstName
        let trimmedLast = trimmedLastName
        let fullName = "\(trimmedFirst) \(trimmedLast)".trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                if !fullName.isEmpty {
                    try await authManager.consolidateNameUpdate(fullName)
                }

                let updates: [String: Any] = [
                    "dateOfBirth": dateOfBirth,
                    "onboardingCompleted": true
                ]

                await authManager.updateProfile(updates)

                await MainActor.run {
                    isSaving = false
                    HapticManager.shared.successAction()

                    if var currentUser = authManager.currentUser {
                        let existingProfile = currentUser.profile

                        let updatedProfile = UserProfile(
                            id: existingProfile?.id ?? currentUser.id,
                            email: existingProfile?.email ?? currentUser.email,
                            username: existingProfile?.username,
                            fullName: fullName.isEmpty ? existingProfile?.fullName ?? currentUser.name : fullName,
                            dateOfBirth: dateOfBirth,
                            height: existingProfile?.height,
                            heightUnit: existingProfile?.heightUnit,
                            gender: existingProfile?.gender,
                            activityLevel: existingProfile?.activityLevel,
                            goalWeight: existingProfile?.goalWeight,
                            goalWeightUnit: existingProfile?.goalWeightUnit,
                            onboardingCompleted: true
                        )

                        currentUser.name = fullName.isEmpty ? currentUser.name : fullName
                        currentUser.profile = updatedProfile
                        currentUser.onboardingCompleted = true
                        authManager.currentUser = currentUser
                    }

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

// MARK: - Substep Helpers

private extension BodyScoreProfileDetailsView {
    func handlePrimaryAction() {
        switch activeSubstep {
        case .firstName:
            handleFirstNameContinue()
        case .lastName:
            handleLastNameContinue()
        case .dateOfBirth:
            submit()
        }
    }

    func handleFirstNameContinue() {
        guard isFirstNameValid else { return }
        HapticManager.shared.selection()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            activeSubstep = .lastName
        }
    }

    func handleLastNameContinue() {
        guard isLastNameValid else { return }
        HapticManager.shared.selection()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            activeSubstep = .dateOfBirth
        }
    }

    func recomputeActiveSubstep() {
        if !isFirstNameValid {
            activeSubstep = .firstName
        } else if !isLastNameValid {
            activeSubstep = .lastName
        } else {
            activeSubstep = .dateOfBirth
        }
    }
}

// MARK: - Local Types

private enum ProfileSubstep {
    case firstName
    case lastName
    case dateOfBirth
}

private enum NameField: Hashable {
    case firstName
    case lastName
}
