import SwiftUI

struct BodyScoreProfileDetailsView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject var viewModel: OnboardingFlowViewModel

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var dateOfBirth: Date = Calendar.current.date(byAdding: .year, value: -25, to: Date()) ?? Date()
    @State private var biologicalSex: BiologicalSex?
    @State private var heightUnit: HeightUnit = .centimeters
    @State private var heightCentimetersText: String = ""
    @State private var heightFeet: Int = 5
    @State private var heightInches: Int = 10
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
        case .sex:
            return biologicalSex != nil
        case .height:
            return isHeightValid
        }
    }

    private var isDateOfBirthWithinValidRange: Bool {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        guard let age = components.year else { return false }
        return age >= 16 && age <= 80
    }

    private var heightInCentimeters: Double? {
        switch heightUnit {
        case .centimeters:
            return Double(heightCentimetersText)
        case .inches:
            let totalInches = Double((heightFeet * 12) + heightInches)
            return totalInches > 0 ? totalInches * 2.54 : nil
        }
    }

    private var isHeightValid: Bool {
        switch heightUnit {
        case .centimeters:
            let value = Double(heightCentimetersText) ?? 0
            return value >= 100 && value <= 250
        case .inches:
            let totalInches = (heightFeet * 12) + heightInches
            return totalInches >= 48 && totalInches <= 96
        }
    }

    private var heightUnitStorageValue: String {
        switch heightUnit {
        case .centimeters:
            return "cm"
        case .inches:
            return "in"
        }
    }

    private var currentTitle: String {
        switch activeSubstep {
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
        switch activeSubstep {
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
        switch activeSubstep {
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
                case .sex:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        activeSubstep = .dateOfBirth
                    }
                case .height:
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        activeSubstep = .sex
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
                focusNameFieldIfNeeded()
            }
        }
        .onChange(of: activeSubstep) { _, newValue in
            DispatchQueue.main.async {
                focusNameFieldIfNeeded(newValue)
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
                selection: $dateOfBirth,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
        }
    }

    private var sexSection: some View {
        OnboardingFormSection(title: nil, caption: nil) {
            HStack(spacing: 16) {
                ForEach(BiologicalSex.allCases, id: \.self) { sex in
                    OnboardingOptionButton(
                        title: sex.description,
                        subtitle: nil,
                        isSelected: biologicalSex == sex,
                        action: {
                            biologicalSex = sex
                            HapticManager.shared.selection()
                        }
                    )
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var heightSection: some View {
        OnboardingFormSection(title: nil, caption: "You can update this later in Settings.") {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Height unit", selection: $heightUnit) {
                    ForEach(HeightUnit.allCases, id: \.self) { unit in
                        Text(unit.description).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: heightUnit) { oldValue, newValue in
                    convertHeightFields(from: oldValue, to: newValue)
                }

                switch heightUnit {
                case .centimeters:
                    TextField("178", text: $heightCentimetersText)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.appCard.opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.appBorder.opacity(0.6), lineWidth: 1)
                        )
                        .accessibilityLabel("Height in centimeters")

                    Text("Enter a height from 100 to 250 cm.")
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.appTextSecondary)

                case .inches:
                    HStack(spacing: 12) {
                        Picker("Feet", selection: $heightFeet) {
                            ForEach(3...8, id: \.self) { feet in
                                Text("\(feet) ft").tag(feet)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipped()

                        Picker("Inches", selection: $heightInches) {
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

        if let existingGender = user.profile?.gender {
            biologicalSex = Self.biologicalSex(from: existingGender)
        }

        if let existingHeight = user.profile?.height, existingHeight > 0 {
            if user.profile?.heightUnit?.lowercased() == "in" {
                heightUnit = .inches
                let totalInches = Int((existingHeight / 2.54).rounded())
                heightFeet = max(3, min(8, totalInches / 12))
                heightInches = max(0, min(11, totalInches % 12))
            } else {
                heightUnit = .centimeters
            }

            heightCentimetersText = String(format: "%.0f", existingHeight)
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
        let completesOnboardingNow = !viewModel.includesFirstPhotoStep ||
            OnboardingStateManager.shared.hasCompletedCurrentVersion

        Task {
            do {
                if !fullName.isEmpty {
                    try await authManager.consolidateNameUpdate(fullName)
                }

                var updates: [String: Any] = [
                    "dateOfBirth": dateOfBirth,
                    "onboardingCompleted": completesOnboardingNow
                ]

                if let biologicalSex {
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
                            dateOfBirth: dateOfBirth,
                            height: heightInCentimeters ?? existingProfile?.height,
                            heightUnit: heightInCentimeters == nil ? existingProfile?.heightUnit : heightUnitStorageValue,
                            gender: biologicalSex?.description ?? existingProfile?.gender,
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
        switch activeSubstep {
        case .firstName:
            handleFirstNameContinue()
        case .lastName:
            handleLastNameContinue()
        case .dateOfBirth:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                activeSubstep = .sex
            }
        case .sex:
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                activeSubstep = .height
            }
        case .height:
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
        } else if !isDateOfBirthWithinValidRange {
            activeSubstep = .dateOfBirth
        } else if biologicalSex == nil {
            activeSubstep = .sex
        } else if !isHeightValid {
            activeSubstep = .height
        } else {
            activeSubstep = .height
        }
    }

    func focusNameFieldIfNeeded(_ step: ProfileSubstep? = nil) {
        switch step ?? activeSubstep {
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
            guard let centimeters = Double(heightCentimetersText) else { return }
            let totalInches = Int((centimeters / 2.54).rounded())
            heightFeet = max(3, min(8, totalInches / 12))
            heightInches = max(0, min(11, totalInches % 12))
        case (.inches, .centimeters):
            let totalInches = Double((heightFeet * 12) + heightInches)
            heightCentimetersText = String(format: "%.0f", totalInches * 2.54)
        default:
            break
        }
    }

    static func biologicalSex(from gender: String) -> BiologicalSex? {
        let normalized = gender.lowercased()
        if normalized.contains("female") || normalized.contains("woman") {
            return .female
        }
        if normalized.contains("male") || normalized.contains("man") {
            return .male
        }
        return nil
    }
}

// MARK: - Local Types

private enum ProfileSubstep {
    case firstName
    case lastName
    case dateOfBirth
    case sex
    case height
}

private enum NameField: Hashable {
    case firstName
    case lastName
}
