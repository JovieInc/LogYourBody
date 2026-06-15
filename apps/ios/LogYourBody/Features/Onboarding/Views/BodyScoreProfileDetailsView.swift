import SwiftUI

struct BodyScoreProfileDetailsView: View {
    @Environment(\.theme)
    private var theme

    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel

    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @FocusState private var focusedNameField: NameField?

    private var trimmedFirstName: String {
        viewModel.profileFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedLastName: String {
        viewModel.profileLastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFirstNameValid: Bool {
        !trimmedFirstName.isEmpty
    }

    private var isLastNameValid: Bool {
        !trimmedLastName.isEmpty
    }

    private var canContinue: Bool {
        switch viewModel.profileDetailsActiveSubstep {
        case .firstName:
            return isFirstNameValid
        case .lastName:
            return isLastNameValid
        case .dateOfBirth:
            return isFirstNameValid && isLastNameValid && isDateOfBirthWithinValidRange
        case .sex:
            return viewModel.profileBiologicalSex != nil
        case .height:
            return isHeightValid
        }
    }

    private var isDateOfBirthWithinValidRange: Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: viewModel.profileDateOfBirth, to: Date())
        guard let age = components.year else { return false }
        return age >= 16 && age <= 80
    }

    private var heightInCentimeters: Double? {
        switch viewModel.profileHeightUnit {
        case .centimeters:
            return Double(viewModel.profileHeightCentimetersText)
        case .inches:
            let totalInches = Double((viewModel.profileHeightFeet * 12) + viewModel.profileHeightInches)
            return totalInches > 0 ? totalInches * 2.54 : nil
        }
    }

    private var isHeightValid: Bool {
        switch viewModel.profileHeightUnit {
        case .centimeters:
            let value = Double(viewModel.profileHeightCentimetersText) ?? 0
            return value >= 100 && value <= 250
        case .inches:
            let totalInches = (viewModel.profileHeightFeet * 12) + viewModel.profileHeightInches
            return totalInches >= 48 && totalInches <= 96
        }
    }

    private var heightUnitStorageValue: String {
        switch viewModel.profileHeightUnit {
        case .centimeters:
            return "cm"
        case .inches:
            return "in"
        }
    }

    private var currentTitle: String {
        switch viewModel.profileDetailsActiveSubstep {
        case .firstName:
            return "What's your first name?"
        case .lastName:
            return "And your last name?"
        case .dateOfBirth:
            return "Birthday"
        case .sex:
            return "Sex at birth"
        case .height:
            return "Height"
        }
    }

    private var currentSubtitle: String {
        switch viewModel.profileDetailsActiveSubstep {
        case .firstName:
            return "We'll use this to personalize your experience."
        case .lastName:
            return "We keep your name private and secure."
        case .dateOfBirth:
            return "Used for age-based insights."
        case .sex:
            return "Used only for body composition calculations."
        case .height:
            return "Needed for FFMI and body score."
        }
    }

    private var primaryButtonTitle: String {
        switch viewModel.profileDetailsActiveSubstep {
        case .firstName, .lastName, .dateOfBirth, .sex:
            return "Continue"
        case .height:
            return "Finish setup"
        }
    }

    var body: some View {
        OnboardingPageTemplate(
            title: currentTitle,
            subtitle: currentSubtitle,
            onBack: {
                switch viewModel.profileDetailsActiveSubstep {
                case .firstName:
                    viewModel.goBack()
                case .lastName:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.profileDetailsActiveSubstep = .firstName
                    }
                case .dateOfBirth:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.profileDetailsActiveSubstep = .lastName
                    }
                case .sex:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.profileDetailsActiveSubstep = .dateOfBirth
                    }
                case .height:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.profileDetailsActiveSubstep = viewModel.profileShouldAskSex ? .sex : .dateOfBirth
                    }
                }
            },
            progress: viewModel.progress(for: .profileDetails),
            content: {
                VStack(spacing: 24) {
                    switch viewModel.profileDetailsActiveSubstep {
                    case .firstName, .lastName:
                        nameSection
                    case .dateOfBirth:
                        dobSection
                    case .sex:
                        sexSection
                    case .height:
                        heightSection
                    }
                }
            },
            footer: {
                VStack(spacing: 12) {
                    Button(action: handlePrimaryAction) {
                        if isSaving {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
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
                            .foregroundStyle(theme.colors.error)
                            .multilineTextAlignment(.center)
                    }
                }
            }
        )
        .onAppear {
            viewModel.hydrateProfileDetailsDraftIfNeeded(from: authManager.currentUser)
            DispatchQueue.main.async {
                focusNameFieldIfNeeded()
            }
        }
        .onChange(of: viewModel.profileDetailsActiveSubstep) { _, newValue in
            DispatchQueue.main.async {
                focusNameFieldIfNeeded(newValue)
            }
        }
    }

    private var nameSection: some View {
        OnboardingFormSection(title: "Name", caption: "We use this to personalize your experience.") {
            VStack(alignment: .leading, spacing: 16) {
                switch viewModel.profileDetailsActiveSubstep {
                case .firstName:
                    Text("First name")
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.appTextSecondary)

                    TextField("First name", text: $viewModel.profileFirstName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .submitLabel(.next)
                        .focused($focusedNameField, equals: .firstName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .systemBGlassSurface(
                            cornerRadius: theme.radius.input,
                            tint: focusedNameField == .firstName ? theme.colors.primary : theme.colors.text,
                            tintOpacity: focusedNameField == .firstName ? 0.07 : 0.03,
                            borderColor: focusedNameField == .firstName ? theme.colors.primary : theme.colors.border,
                            borderOpacity: focusedNameField == .firstName ? 0.9 : 0.65
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

                    TextField("Last name", text: $viewModel.profileLastName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .submitLabel(.next)
                        .focused($focusedNameField, equals: .lastName)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .systemBGlassSurface(
                            cornerRadius: theme.radius.input,
                            tint: focusedNameField == .lastName ? theme.colors.primary : theme.colors.text,
                            tintOpacity: focusedNameField == .lastName ? 0.07 : 0.03,
                            borderColor: focusedNameField == .lastName ? theme.colors.primary : theme.colors.border,
                            borderOpacity: focusedNameField == .lastName ? 0.9 : 0.65
                        )
                        .onSubmit {
                            handleLastNameContinue()
                        }

                case .dateOfBirth, .sex, .height:
                    EmptyView()
                }
            }
        }
    }

    private var dobSection: some View {
        OnboardingFormSection(title: nil, caption: nil) {
            DatePicker(
                "Date of Birth",
                selection: $viewModel.profileDateOfBirth,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        }
    }

    private var sexSection: some View {
        OnboardingFormSection(title: nil, caption: nil) {
            VStack(spacing: 12) {
                ForEach(BiologicalSex.allCases, id: \.self) { sex in
                    OnboardingOptionButton(
                        title: sex.description,
                        subtitle: nil,
                        isSelected: viewModel.profileBiologicalSex == sex,
                        action: {
                            viewModel.updateProfileBiologicalSex(sex)
                            HapticManager.shared.selection()
                        }
                    )
                }
            }
        }
    }

    private var heightSection: some View {
        OnboardingFormSection(title: nil, caption: "You can update this later in Settings.") {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Height unit", selection: $viewModel.profileHeightUnit) {
                    ForEach(HeightUnit.allCases, id: \.self) { unit in
                        Text(unit.description).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: viewModel.profileHeightUnit) { oldValue, newValue in
                    convertHeightFields(from: oldValue, to: newValue)
                }

                switch viewModel.profileHeightUnit {
                case .centimeters:
                    TextField("178", text: $viewModel.profileHeightCentimetersText)
                        .keyboardType(.decimalPad)
                        .font(theme.typography.displayMedium)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .systemBGlassSurface(
                            cornerRadius: theme.radius.input,
                            tint: theme.colors.text,
                            tintOpacity: 0.03,
                            borderColor: theme.colors.border,
                            borderOpacity: 0.65
                        )
                        .accessibilityLabel("Height in centimeters")

                    Text("Enter a height from 100 to 250 cm.")
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.appTextSecondary)

                case .inches:
                    HStack(spacing: 12) {
                        Picker("Feet", selection: $viewModel.profileHeightFeet) {
                            ForEach(3...8, id: \.self) { feet in
                                Text("\(feet) ft").tag(feet)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()

                        Picker("Inches", selection: $viewModel.profileHeightInches) {
                            ForEach(0...11, id: \.self) { inches in
                                Text("\(inches) in").tag(inches)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()
                    }

                    Text("Enter a height from 4'0\" to 8'0\".")
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.appTextSecondary)
                }
            }
        }
    }

    private func submit() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        let trimmedFirst = trimmedFirstName
        let trimmedLast = trimmedLastName
        let fullName = "\(trimmedFirst) \(trimmedLast)".trimmingCharacters(in: .whitespacesAndNewlines)
        let completesOnboardingNow = !viewModel.includesFirstPhotoStep ||
            OnboardingStateManager.shared.hasCompletedCurrentVersion(for: authManager.currentUser?.id)

        Task {
            do {
                if !fullName.isEmpty {
                    try await authManager.consolidateNameUpdate(fullName)
                }

                var updates: [String: Any] = [
                    "dateOfBirth": viewModel.profileDateOfBirth,
                    "onboardingCompleted": completesOnboardingNow
                ]

                if let biologicalSex = viewModel.profileBiologicalSex {
                    updates["gender"] = biologicalSex.description
                }

                if let heightInCentimeters {
                    updates["height"] = heightInCentimeters
                    updates["heightUnit"] = heightUnitStorageValue
                }

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
                            dateOfBirth: viewModel.profileDateOfBirth,
                            height: heightInCentimeters ?? existingProfile?.height,
                            heightUnit: heightInCentimeters == nil ? existingProfile?.heightUnit : heightUnitStorageValue,
                            gender: viewModel.profileBiologicalSex?.description ?? existingProfile?.gender,
                            activityLevel: existingProfile?.activityLevel,
                            goalWeight: existingProfile?.goalWeight,
                            goalWeightUnit: existingProfile?.goalWeightUnit,
                            onboardingCompleted: completesOnboardingNow
                        )

                        currentUser.name = fullName.isEmpty ? currentUser.name : fullName
                        currentUser.profile = updatedProfile
                        currentUser.onboardingCompleted = completesOnboardingNow
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
        switch viewModel.profileDetailsActiveSubstep {
        case .firstName:
            handleFirstNameContinue()
        case .lastName:
            handleLastNameContinue()
        case .dateOfBirth:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                viewModel.profileDetailsActiveSubstep = viewModel.profileShouldAskSex ? .sex : .height
            }
        case .sex:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                viewModel.profileDetailsActiveSubstep = .height
            }
        case .height:
            submit()
        }
    }

    func handleFirstNameContinue() {
        guard isFirstNameValid else { return }
        HapticManager.shared.selection()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            viewModel.profileDetailsActiveSubstep = .lastName
        }
    }

    func handleLastNameContinue() {
        guard isLastNameValid else { return }
        HapticManager.shared.selection()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            viewModel.profileDetailsActiveSubstep = .dateOfBirth
        }
    }

    func focusNameFieldIfNeeded(_ step: OnboardingFlowViewModel.ProfileDetailsSubstep? = nil) {
        switch step ?? viewModel.profileDetailsActiveSubstep {
        case .firstName:
            focusedNameField = .firstName
        case .lastName:
            focusedNameField = .lastName
        case .dateOfBirth, .sex, .height:
            focusedNameField = nil
        }
    }

    func convertHeightFields(from oldUnit: HeightUnit, to newUnit: HeightUnit) {
        guard oldUnit != newUnit else { return }

        switch (oldUnit, newUnit) {
        case (.centimeters, .inches):
            guard let centimeters = Double(viewModel.profileHeightCentimetersText) else { return }
            let totalInches = Int((centimeters / 2.54).rounded())
            viewModel.profileHeightFeet = max(3, min(8, totalInches / 12))
            viewModel.profileHeightInches = max(0, min(11, totalInches % 12))
        case (.inches, .centimeters):
            let totalInches = Double((viewModel.profileHeightFeet * 12) + viewModel.profileHeightInches)
            viewModel.profileHeightCentimetersText = String(format: "%.0f", totalInches * 2.54)
        default:
            break
        }
    }
}

// MARK: - Local Types

private enum NameField: Hashable {
    case firstName
    case lastName
}
