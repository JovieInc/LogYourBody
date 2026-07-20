//
// ProfileSettingsViewV2.swift
// LogYourBody
//
import SwiftUI
import OSLog
import UIKit

enum ProfileSettingsPolicy {
    /// Joins first/last names into a display name, trimming blanks and dropping empty parts.
    static func joinedDisplayName(first: String, last: String) -> String {
        let trimmedFirst = first.trimmingCharacters(in: .whitespaces)
        let trimmedLast = last.trimmingCharacters(in: .whitespaces)
        return [trimmedFirst, trimmedLast]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Base string used to prefill the name fields: the stored display name, or the email local-part.
    static func displayNameBase(name: String, email: String) -> String {
        if !name.isEmpty {
            return name
        }
        return email.components(separatedBy: "@").first ?? ""
    }

    /// Splits a display name into (first, last); everything after the first word becomes the last name.
    static func splitDisplayName(_ base: String) -> (first: String, last: String) {
        let parts = base.split(separator: " ")
        let first = parts.first.map { String($0) } ?? ""
        let last = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
        return (first, last)
    }

    /// Formats a height stored in cm for the profile row and picker sheet display.
    static func formattedHeight(heightCm: Int, useMetric: Bool) -> String {
        if useMetric {
            return "\(heightCm) cm"
        }
        let totalInches = Int(Double(heightCm) / 2.54)
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet)'\(inches)\""
    }

    /// Formats the age row label from a date of birth.
    static func formattedAge(dateOfBirth: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let age = calendar.dateComponents([.year], from: dateOfBirth, to: now).year ?? 0
        return age > 0 ? "\(age) years" : "Not set"
    }

    /// Imperial wheel components for a height stored in cm.
    static func imperialHeightComponents(heightCm: Int) -> (feet: Int, inches: Int) {
        let totalInches = Double(heightCm) / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))
        return (feet, inches)
    }

    /// Height in cm from imperial wheel components.
    static func heightCm(feet: Int, inches: Int) -> Int {
        Int((Double(feet) * 12 + Double(inches)) * 2.54)
    }
}

struct ProfileSettingsViewV2: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss)
    var dismiss
    @Environment(\.theme)
    private var theme
    // Editable fields
    @State private var editableName: String = ""
    @State private var editableFirstName: String = ""
    @State private var editableLastName: String = ""
    @State private var editableDateOfBirth = Date()
    @State private var editableHeightCm: Int = 170
    @State private var editableGender: BiologicalSex = .male
    @State private var useMetricHeight: Bool = false

    private static let logger = Logger(subsystem: "com.logyourbody.app", category: "ProfileSettings")

    // UI State
    @State private var showingHeightPicker = false
    @State private var showingDatePicker = false
    @State private var hasChanges = false
    @State private var isSaving = false
    @State private var showingSaveSuccess = false
    @State private var saveErrorMessage: String?

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: theme.spacing.sectionSpacing) {
                    basicInformationCard

                    physicalInformationCard
                }
                .padding(.horizontal, theme.spacing.screenPadding)
                .padding(.top, theme.spacing.md)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .settingsBackground()
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(theme.colors.primary)
                        .frame(minWidth: JovieTokens.minimumHitTarget, minHeight: JovieTokens.minimumHitTarget)
                } else if hasChanges {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.medium)
                    .foregroundColor(theme.colors.primary)
                    .jovieTouchTarget()
                    .accessibilityHint("Saves your profile changes.")
                }
            }
        }
        .sheet(isPresented: $showingHeightPicker) {
            ProfileHeightPickerSheet(
                heightCm: $editableHeightCm,
                useMetric: $useMetricHeight,
                hasChanges: $hasChanges
            )
        }
        .sheet(isPresented: $showingDatePicker) {
            DatePickerSheet(
                date: $editableDateOfBirth,
                hasChanges: $hasChanges
            )
        }
        .onAppear {
            loadCurrentProfile()
        }
        .overlay(
            SuccessOverlay(
                isShowing: $showingSaveSuccess,
                message: "Profile updated"
            )
        )
        .alert(
            "Couldn’t save profile",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )
        ) {
            Button("Try Again") {
                saveErrorMessage = nil
                saveProfile()
            }
            Button("Cancel", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "Check your connection and try again.")
        }
    }

    // MARK: - View Components

    private var basicInformationCard: some View {
        SettingsSection(header: "Basic Information") {
            VStack(spacing: 0) {
                editableTextRow(
                    label: "First name",
                    text: $editableFirstName,
                    contentType: .givenName
                )

                Divider()
                    .padding(.leading, 16)

                editableTextRow(
                    label: "Last name",
                    text: $editableLastName,
                    contentType: .familyName
                )

                Divider()
                    .padding(.leading, 16)

                // Email (read-only)
                settingsRow(
                    label: "Email",
                    value: authManager.currentUser?.email ?? "",
                    showDisclosure: false,
                    isDisabled: true
                )

                Divider()
                    .padding(.leading, 16)

                genderSelector
            }
        }
    }

    private var genderSelector: some View {
        Picker(selection: $editableGender) {
            ForEach(BiologicalSex.allCases, id: \.self) { gender in
                Text(gender.description).tag(gender)
            }
        } label: {
            HStack(spacing: theme.spacing.xs) {
                Text("Biological sex")
                    .foregroundColor(theme.colors.text)
                    .font(theme.typography.labelLarge)

                Spacer(minLength: theme.spacing.sm)

                Text(editableGender.description)
                    .font(theme.typography.labelMedium)
                    .foregroundColor(theme.colors.textSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.up.chevron.down")
                    .font(theme.typography.captionMedium.weight(.semibold))
                    .foregroundColor(theme.colors.textTertiary)
            }
        }
        .pickerStyle(.menu)
        .tint(theme.colors.text)
        .padding(.horizontal, theme.spacing.md)
        .frame(minHeight: JovieTokens.minimumHitTarget)
        .accessibilityLabel("Biological sex")
        .accessibilityValue(editableGender.description)
        .onChange(of: editableGender) { _, _ in
            hasChanges = true
        }
    }

    private var physicalInformationCard: some View {
        SettingsSection(header: "Physical Information") {
            VStack(spacing: 0) {
                // Height
                Button {
                    showingHeightPicker = true
                } label: {
                    HStack {
                        Text("Height")
                            .font(theme.typography.labelLarge)
                            .foregroundColor(theme.colors.text)
                        Spacer()
                        HStack(spacing: theme.spacing.xxs) {
                            Text(formattedHeight)
                                .font(theme.typography.labelMedium)
                                .foregroundColor(theme.colors.text)
                            Image(systemName: "ruler")
                                .font(theme.typography.captionLarge)
                                .foregroundColor(theme.colors.textSecondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(theme.typography.captionMedium.weight(.semibold))
                            .foregroundColor(theme.colors.textTertiary)
                    }
                    .padding(.horizontal, theme.spacing.md)
                    .frame(minHeight: JovieTokens.minimumHitTarget)
                }
                .accessibilityLabel("Height")
                .accessibilityValue(formattedHeight)
                .accessibilityHint("Double-tap to edit your height.")

                Divider()
                    .padding(.leading, 16)

                // Age/Date of Birth
                Button {
                    showingDatePicker = true
                } label: {
                    HStack {
                        Text("Age")
                            .font(theme.typography.labelLarge)
                            .foregroundColor(theme.colors.text)
                        Spacer()
                        HStack(spacing: theme.spacing.xxs) {
                            Text(formattedAge)
                                .font(theme.typography.labelMedium)
                                .foregroundColor(theme.colors.text)
                            Image(systemName: "calendar")
                                .font(theme.typography.captionLarge)
                                .foregroundColor(theme.colors.textSecondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(theme.typography.captionMedium.weight(.semibold))
                            .foregroundColor(theme.colors.textTertiary)
                    }
                    .padding(.horizontal, theme.spacing.md)
                    .frame(minHeight: JovieTokens.minimumHitTarget)
                }
                .accessibilityLabel("Age")
                .accessibilityValue(formattedAge)
                .accessibilityHint("Double-tap to edit your date of birth.")
            }
        }
    }

    @ViewBuilder
    private func settingsRow(
        label: String,
        value: String,
        showDisclosure: Bool = true,
        isDisabled: Bool = false
    ) -> some View {
        HStack {
            Text(label)
                .font(theme.typography.labelLarge)
                .foregroundColor(isDisabled ? theme.colors.textSecondary : theme.colors.text)

            Spacer()

            Text(value)
                .font(theme.typography.labelMedium)
                .foregroundColor(isDisabled ? theme.colors.textTertiary : theme.colors.textSecondary)

            if showDisclosure && !isDisabled {
                Image(systemName: "chevron.right")
                    .font(theme.typography.captionMedium.weight(.semibold))
                    .foregroundColor(theme.colors.textTertiary)
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .frame(minHeight: JovieTokens.minimumHitTarget)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private func editableTextRow(
        label: String,
        text: Binding<String>,
        contentType: UITextContentType
    ) -> some View {
        HStack(spacing: theme.spacing.md) {
            Text(label)
                .font(theme.typography.labelLarge)
                .foregroundColor(theme.colors.text)
                .accessibilityHidden(true)

            TextField(label, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .font(theme.typography.labelMedium)
                .foregroundColor(theme.colors.text)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(label)
                .onChange(of: text.wrappedValue) { _, _ in
                    hasChanges = true
                    updateEditableName()
                }
        }
        .padding(.horizontal, theme.spacing.md)
        .frame(minHeight: JovieTokens.minimumHitTarget)
    }

    private func updateEditableName() {
        editableName = ProfileSettingsPolicy.joinedDisplayName(first: editableFirstName, last: editableLastName)
    }

    // MARK: - Computed Properties

    private var formattedHeight: String {
        ProfileSettingsPolicy.formattedHeight(heightCm: editableHeightCm, useMetric: useMetricHeight)
    }

    private var formattedAge: String {
        ProfileSettingsPolicy.formattedAge(dateOfBirth: editableDateOfBirth)
    }

    // MARK: - Methods

    private func loadCurrentProfile() {
        guard let user = authManager.currentUser else { return }

        editableName = user.name ?? user.profile?.fullName ?? ""
        let baseName = ProfileSettingsPolicy.displayNameBase(name: editableName, email: user.email)
        let nameParts = ProfileSettingsPolicy.splitDisplayName(baseName)
        editableFirstName = nameParts.first
        editableLastName = nameParts.last
        editableDateOfBirth = user.profile?.dateOfBirth ?? Date()

        if let height = user.profile?.height {
            editableHeightCm = Int(height.rounded())
            useMetricHeight = user.profile?.heightUnit == "cm"
        }

        if let genderString = user.profile?.gender {
            editableGender = BiologicalSex(rawValue: genderString.lowercased()) ?? .male
        }

        hasChanges = false
    }

    private func saveProfile() {
        guard let currentUser = authManager.currentUser else { return }

        isSaving = true
        hasChanges = false

        Task {
            let start = Date()
            do {
                // Update name using consolidated method if changed
                if editableName != currentUser.name {
                    try await authManager.consolidateNameUpdate(editableName)
                }

                let onboardingCompleted = currentUser.profile?.onboardingCompleted ?? currentUser.onboardingCompleted

                // Create updated profile
                let updatedProfile = UserProfile(
                    id: currentUser.id,
                    email: currentUser.email,
                    username: currentUser.profile?.username,
                    fullName: editableName.isEmpty ? nil : editableName,
                    dateOfBirth: editableDateOfBirth,
                    height: Double(editableHeightCm),
                    heightUnit: useMetricHeight ? "cm" : "in",
                    gender: editableGender.description,
                    activityLevel: currentUser.profile?.activityLevel,
                    goalWeight: currentUser.profile?.goalWeight,
                    goalWeightUnit: currentUser.profile?.goalWeightUnit,
                    onboardingCompleted: onboardingCompleted
                )

                // Save to Core Data
                CoreDataManager.shared.saveProfile(updatedProfile, userId: currentUser.id, email: currentUser.email)

                // Update auth manager with proper sync
                let updates: [String: Any] = [
                    "name": editableName.isEmpty ? "" : editableName,
                    "dateOfBirth": editableDateOfBirth,
                    "height": Double(editableHeightCm),
                    "heightUnit": useMetricHeight ? "cm" : "in",
                    "gender": editableGender.description,
                    "onboardingCompleted": onboardingCompleted
                ]

                await authManager.updateProfile(updates)

                await MainActor.run {
                    let didApplyProfile = authManager.applySavedProfileToCurrentUser(updatedProfile)
                    if !didApplyProfile {
                        hasChanges = true
                    } else {
                        withAnimation {
                            showingSaveSuccess = true
                        }
                    }
                    isSaving = false
                }

                let elapsed = Date().timeIntervalSince(start)
                Self.logger.debug("Profile save completed in \(elapsed, privacy: .public)s")
            } catch {
                await MainActor.run {
                    isSaving = false
                    hasChanges = true
                    saveErrorMessage = "Your changes are still here. Check your connection and try again."
                }

                let elapsed = Date().timeIntervalSince(start)
                Self.logger.debug("Profile save failed after \(elapsed, privacy: .public)s")
            }
        }
    }
}

// MARK: - Height Picker Sheet

struct ProfileHeightPickerSheet: View {
    @Binding var heightCm: Int
    @Binding var useMetric: Bool
    @Binding var hasChanges: Bool
    @Environment(\.dismiss)
    var dismiss
    @Environment(\.theme)
    private var theme
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                unitSelector
                heightDisplay
                heightPicker
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .settingsBackground()
            .navigationTitle("Set Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .jovieTouchTarget()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        hasChanges = true
                        dismiss()
                    }
                    .fontWeight(.medium)
                    .jovieTouchTarget()
                }
            }
        }
    }

    private var unitSelector: some View {
        Picker("Unit", selection: $useMetric) {
            Text("Imperial (ft/in)").tag(false)
            Text("Metric (cm)").tag(true)
        }
        .pickerStyle(.menu)
        .tint(theme.colors.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.md)
        .frame(minHeight: JovieTokens.minimumHitTarget)
    }

    private var heightDisplay: some View {
        VStack(spacing: 8) {
            Text(formattedHeight)
                .font(theme.typography.displayMedium)
                .foregroundColor(theme.colors.text)

            Text(alternateHeight)
                .font(theme.typography.captionLarge)
                .foregroundColor(theme.colors.textSecondary)
        }
        .padding()
    }

    private var heightPicker: some View {
        Group {
            if useMetric {
                Picker("Height", selection: $heightCm) {
                    ForEach(100...250, id: \.self) { cm in
                        Text("\(cm) cm").tag(cm)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .labelsHidden()
            } else {
                imperialHeightPicker
            }
        }
    }

    private var imperialHeightPicker: some View {
        let components = ProfileSettingsPolicy.imperialHeightComponents(heightCm: heightCm)
        let feet = components.feet
        let inches = components.inches

        let feetBinding = Binding<Int>(
            get: { feet },
            set: { newFeet in
                heightCm = ProfileSettingsPolicy.heightCm(feet: newFeet, inches: inches)
            }
        )

        let inchesBinding = Binding<Int>(
            get: { inches },
            set: { newInches in
                heightCm = ProfileSettingsPolicy.heightCm(feet: feet, inches: newInches)
            }
        )

        return HStack {
            Picker("Feet", selection: feetBinding) {
                ForEach(3...8, id: \.self) { feet in
                    Text("\(feet) ft").tag(feet)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .frame(maxWidth: .infinity)

            Picker("Inches", selection: inchesBinding) {
                ForEach(0...11, id: \.self) { inches in
                    Text("\(inches) in").tag(inches)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .frame(maxWidth: .infinity)
        }
    }

    private var formattedHeight: String {
        ProfileSettingsPolicy.formattedHeight(heightCm: heightCm, useMetric: useMetric)
    }

    private var alternateHeight: String {
        if useMetric {
            return ProfileSettingsPolicy.formattedHeight(heightCm: heightCm, useMetric: false) + " in imperial"
        } else {
            return "\(heightCm) cm in metric"
        }
    }
}

// MARK: - Date Picker Sheet

struct DatePickerSheet: View {
    @Binding var date: Date
    @Binding var hasChanges: Bool
    @Environment(\.dismiss)
    var dismiss
    @Environment(\.theme)
    private var theme
    var body: some View {
        NavigationStack {
            VStack(spacing: theme.spacing.md) {
                DatePicker(
                    "",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(WheelDatePickerStyle())
                .labelsHidden()

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .settingsBackground()
            .navigationTitle("Date of Birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .jovieTouchTarget()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        hasChanges = true
                        dismiss()
                    }
                    .fontWeight(.medium)
                    .jovieTouchTarget()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ProfileSettingsViewV2()
            .environmentObject({
                let authManager = AuthManager()
                authManager.currentUser = User(
                    id: "1",
                    email: "john@example.com",
                    name: "John Doe",
                    avatarUrl: nil,
                    profile: UserProfile(
                        id: "1",
                        email: "john@example.com",
                        username: nil,
                        fullName: "John Doe",
                        dateOfBirth: Calendar.current.date(byAdding: .year, value: -25, to: Date()),
                        height: 70,
                        heightUnit: "in",
                        gender: "Male",
                        activityLevel: nil,
                        goalWeight: nil,
                        goalWeightUnit: nil,
                        onboardingCompleted: true
                    ),
                    onboardingCompleted: true
                )
                return authManager
            }())
    }
}
