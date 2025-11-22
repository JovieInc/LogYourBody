//
// ProfileSettingsViewV2.swift
// LogYourBody
//
import SwiftUI
import OSLog

struct ProfileSettingsViewV2: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss)
    var dismiss
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

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: SettingsDesign.sectionSpacing) {
                    // Profile Header
                    profileHeader
                        .padding(.top)

                    // Basic Information Card
                    basicInformationCard

                    // Physical Information Card
                    physicalInformationCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .settingsBackground()
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.appPrimary)
                } else if hasChanges {
                    Button("Save") {
                        saveProfile()
                    }
                    .fontWeight(.medium)
                    .foregroundColor(.appPrimary)
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
    }

    // MARK: - View Components

    private var basicInformationCard: some View {
        SettingsSection(header: "Basic Information") {
            VStack(spacing: 0) {
                // First Name Field
                settingsRow(
                    label: "First Name",
                    value: editableFirstName.isEmpty ? "Not set" : editableFirstName,
                    showDisclosure: false
                ) {
                    AnyView(
                        TextField("First name", text: $editableFirstName)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: editableFirstName) { _, _ in
                                hasChanges = true
                                let first = editableFirstName.trimmingCharacters(in: .whitespaces)
                                let last = editableLastName.trimmingCharacters(in: .whitespaces)
                                editableName = [first, last]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " ")
                            }
                    )
                }

                Divider()
                    .padding(.leading, 16)

                // Last Name Field
                settingsRow(
                    label: "Last Name",
                    value: editableLastName.isEmpty ? "Not set" : editableLastName,
                    showDisclosure: false
                ) {
                    AnyView(
                        TextField("Last name", text: $editableLastName)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: editableLastName) { _, _ in
                                hasChanges = true
                                let first = editableFirstName.trimmingCharacters(in: .whitespaces)
                                let last = editableLastName.trimmingCharacters(in: .whitespaces)
                                editableName = [first, last]
                                    .filter { !$0.isEmpty }
                                    .joined(separator: " ")
                            }
                    )
                }

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

                // Gender Selector with modern segmented control
                genderSelector
            }
        }
    }

    private var genderSelector: some View {
        HStack {
            Text("Biological Sex")
                .foregroundColor(.primary)
                .font(.system(size: 16))

            Spacer()

            Picker("Biological Sex", selection: $editableGender) {
                ForEach(BiologicalSex.allCases, id: \.self) { gender in
                    Text(gender.description).tag(gender)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .frame(width: 140)
            .scaleEffect(0.95) // Slightly smaller for better fit
            .onChange(of: editableGender) { _, _ in
                hasChanges = true
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Biological sex")
        .accessibilityValue(editableGender.description)
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
                            .foregroundColor(.primary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(formattedHeight)
                                .foregroundColor(.primary)
                                .fontWeight(.medium)
                            Image(systemName: "ruler")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
                            .foregroundColor(.primary)
                        Spacer()
                        HStack(spacing: 4) {
                            Text(formattedAge)
                                .foregroundColor(.primary)
                                .fontWeight(.medium)
                            Image(systemName: "calendar")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(Color(.tertiaryLabel))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .accessibilityLabel("Age")
                .accessibilityValue(formattedAge)
                .accessibilityHint("Double-tap to edit your date of birth.")
            }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Avatar
            ZStack {
                if let avatarUrl = authManager.currentUser?.avatarUrl,
                   !avatarUrl.isEmpty,
                   let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 80)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    }
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Text(profileInitials)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.secondary)
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Profile photo")

            // Name and email
            VStack(spacing: 4) {
                Text(authManager.currentUser?.displayName ?? authManager.currentUser?.name ?? "User")
                    .font(.headline)

                Text(authManager.currentUser?.email ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func settingsRow(
        label: String,
        value: String,
        showDisclosure: Bool = true,
        isDisabled: Bool = false,
        customContent: (() -> AnyView)? = nil
    ) -> some View {
        HStack {
            Text(label)
                .foregroundColor(isDisabled ? .secondary : .primary)

            Spacer()

            if let customContent = customContent {
                customContent()
            } else {
                Text(value)
                    .foregroundColor(isDisabled ? Color(.tertiaryLabel) : .secondary)
            }

            if showDisclosure && !isDisabled {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    // MARK: - Computed Properties

    private var profileInitials: String {
        let name: String
        if !editableName.isEmpty {
            name = editableName
        } else {
            name = authManager.currentUser?.name ?? authManager.currentUser?.email ?? ""
        }
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }

    private var formattedHeight: String {
        if useMetricHeight {
            return "\(editableHeightCm) cm"
        } else {
            let totalInches = Int(Double(editableHeightCm) / 2.54)
            let feet = totalInches / 12
            let inches = totalInches % 12
            return "\(feet)'\(inches)\""
        }
    }

    private var formattedAge: String {
        let age = Calendar.current.dateComponents([.year], from: editableDateOfBirth, to: Date()).year ?? 0
        return age > 0 ? "\(age) years" : "Not set"
    }

    // MARK: - Methods

    private func loadCurrentProfile() {
        guard let user = authManager.currentUser else { return }

        editableName = user.name ?? user.profile?.fullName ?? ""
        let baseName: String
        if !editableName.isEmpty {
            baseName = editableName
        } else {
            baseName = user.email.components(separatedBy: "@").first ?? ""
        }
        let parts = baseName.split(separator: " ")
        editableFirstName = parts.first.map { String($0) } ?? ""
        editableLastName = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
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
                    onboardingCompleted: currentUser.profile?.onboardingCompleted
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
                    "onboardingCompleted": true
                ]

                await authManager.updateProfile(updates)

                await MainActor.run {
                    isSaving = false
                    withAnimation {
                        showingSaveSuccess = true
                    }

                    // Force UI refresh
                    NotificationCenter.default.post(name: .profileUpdated, object: nil)
                }

                let elapsed = Date().timeIntervalSince(start)
                Self.logger.debug("Profile save completed in \(elapsed, privacy: .public)s")
            } catch {
                await MainActor.run {
                    isSaving = false
                    hasChanges = true
                    // print("Failed to update profile: \(error)")
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
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                unitSelector
                heightDisplay
                heightPicker
            }
            .navigationTitle("Set Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        hasChanges = true
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }

    private var unitSelector: some View {
        Picker("Unit", selection: $useMetric) {
            Text("Imperial (ft/in)").tag(false)
            Text("Metric (cm)").tag(true)
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding()
    }

    private var heightDisplay: some View {
        VStack(spacing: 8) {
            Text(formattedHeight)
                .font(.system(size: 36, weight: .semibold))

            Text(alternateHeight)
                .font(.caption)
                .foregroundColor(.secondary)
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
        let totalInches = Double(heightCm) / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12))

        let feetBinding = Binding<Int>(
            get: { feet },
            set: { newFeet in
                let newHeightCm = (Double(newFeet) * 12 + Double(inches)) * 2.54
                heightCm = Int(newHeightCm)
            }
        )

        let inchesBinding = Binding<Int>(
            get: { inches },
            set: { newInches in
                let newHeightCm = (Double(feet) * 12 + Double(newInches)) * 2.54
                heightCm = Int(newHeightCm)
            }
        )

        return HStack {
            Picker("Feet", selection: feetBinding) {
                ForEach(3...8, id: \.self) { feet in
                    Text("\(feet) ft").tag(feet)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .frame(width: 100)

            Picker("Inches", selection: inchesBinding) {
                ForEach(0...11, id: \.self) { inches in
                    Text("\(inches) in").tag(inches)
                }
            }
            .pickerStyle(WheelPickerStyle())
            .frame(width: 100)
        }
    }

    private var formattedHeight: String {
        if useMetric {
            return "\(heightCm) cm"
        } else {
            let totalInches = Int(Double(heightCm) / 2.54)
            let feet = totalInches / 12
            let inches = totalInches % 12
            return "\(feet)'\(inches)\""
        }
    }

    private var alternateHeight: String {
        if useMetric {
            let totalInches = Int(Double(heightCm) / 2.54)
            let feet = totalInches / 12
            let inches = totalInches % 12
            return "\(feet)'\(inches)\" in imperial"
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
    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "",
                    selection: $date,
                    displayedComponents: .date
                )
                .datePickerStyle(WheelDatePickerStyle())
                .labelsHidden()

                Spacer()
            }
            .navigationTitle("Date of Birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        hasChanges = true
                        dismiss()
                    }
                    .fontWeight(.medium)
                }
            }
        }
    }
}

#Preview {
    NavigationView {
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
