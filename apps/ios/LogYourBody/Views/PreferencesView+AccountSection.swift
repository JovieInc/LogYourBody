//
// PreferencesView+AccountSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var accountSection: some View {
        SettingsSection(header: "Account") {
            accountEmailRow
            changeProfilePhotoRow
            logoutRow
        }
    }

    var accountEmailRow: some View {
        SettingsRow(
            icon: "envelope.fill",
            title: "Email",
            value: userEmail
        )
    }

    var changeProfilePhotoRow: some View {
        AppPhotosPicker(maxSelectionCount: 1) { assets in
            await handlePhotoSelection(assets.first)
        } label: {
            SettingsRow(
                icon: "camera.fill",
                title: isUploadingPhoto ? "Uploading..." : "Change profile photo",
                value: isUploadingPhoto ? "\(Int(avatarUploadProgress * 100))%" : nil
            )
        }
        .disabled(isUploadingPhoto)
    }

    var logoutRow: some View {
        SettingsButtonRow(
            icon: "rectangle.portrait.and.arrow.right",
            title: "Log out",
            role: .destructive
        ) {
            showingLogoutConfirmation = true
        }
        .accessibilityIdentifier("settings_logout_button")
    }

    var profileSection: some View {
        SettingsSection(header: "Profile") {
            profileFullNameRow
            profileDateOfBirthRow
            profileHeightRow
        }
    }

    var profileFullNameRow: some View {
        profileRow(
            icon: "person.fill",
            title: "Full name",
            value: authManager.currentUser?.profile?.fullName ?? authManager.currentUser?.name ?? "Not set"
        ) {
            beginProfileEditor(.fullName)
        }
    }

    var profileDateOfBirthRow: some View {
        profileRow(
            icon: "calendar",
            title: "Date of birth",
            value: dateOfBirthDisplay
        ) {
            beginProfileEditor(.dateOfBirth)
        }
    }

    var profileHeightRow: some View {
        profileRow(
            icon: "ruler",
            title: "Height",
            value: heightDisplayText
        ) {
            beginProfileEditor(.height)
        }
        .accessibilityIdentifier("settings_profile_height_row")
    }

    func profileRow(
        icon: String,
        title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SettingsRow(
                icon: icon,
                title: title,
                value: value,
                showChevron: false
            )
        }
        .foregroundStyle(.primary)
    }

    func beginProfileEditor(_ editor: PreferencesProfileEditor) {
        let profile = authManager.currentUser?.profile
        profileEditorName = profile?.fullName ?? authManager.currentUser?.name ?? ""
        profileEditorDateOfBirth = profile?.dateOfBirth ?? Date()
        profileEditorHeightCm = Int((profile?.height ?? 170).rounded())
        profileEditorUsesMetricHeight = profile?.heightUnit == "cm"
        profileEditorHasChanges = false
        activeProfileEditor = editor
    }

    func saveProfileName() {
        let name = profileEditorName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            profileEditorErrorMessage = "Enter a name before saving."
            return
        }

        saveProfileField(updates: ["fullName": name]) { profile in
            UserProfile(
                id: profile.id,
                email: profile.email,
                username: profile.username,
                fullName: name,
                dateOfBirth: profile.dateOfBirth,
                height: profile.height,
                heightUnit: profile.heightUnit,
                gender: profile.gender,
                activityLevel: profile.activityLevel,
                goalWeight: profile.goalWeight,
                goalWeightUnit: profile.goalWeightUnit,
                onboardingCompleted: profile.onboardingCompleted
            )
        }
    }

    func saveProfileDateOfBirth() {
        saveProfileField(updates: ["dateOfBirth": profileEditorDateOfBirth]) { profile in
            UserProfile(
                id: profile.id,
                email: profile.email,
                username: profile.username,
                fullName: profile.fullName,
                dateOfBirth: profileEditorDateOfBirth,
                height: profile.height,
                heightUnit: profile.heightUnit,
                gender: profile.gender,
                activityLevel: profile.activityLevel,
                goalWeight: profile.goalWeight,
                goalWeightUnit: profile.goalWeightUnit,
                onboardingCompleted: profile.onboardingCompleted
            )
        }
    }

    func saveProfileHeight() {
        saveProfileField(
            updates: [
                "height": Double(profileEditorHeightCm),
                "heightUnit": profileEditorUsesMetricHeight ? "cm" : "in"
            ]
        ) { profile in
            UserProfile(
                id: profile.id,
                email: profile.email,
                username: profile.username,
                fullName: profile.fullName,
                dateOfBirth: profile.dateOfBirth,
                height: Double(profileEditorHeightCm),
                heightUnit: profileEditorUsesMetricHeight ? "cm" : "in",
                gender: profile.gender,
                activityLevel: profile.activityLevel,
                goalWeight: profile.goalWeight,
                goalWeightUnit: profile.goalWeightUnit,
                onboardingCompleted: profile.onboardingCompleted
            )
        }
    }

    private func saveProfileField(
        updates: [String: Any],
        updatedProfile: @escaping (UserProfile) -> UserProfile
    ) {
        guard let currentUser = authManager.currentUser else { return }
        let currentProfile = authManager.currentUser?.profile ?? UserProfile(
            id: currentUser.id,
            email: currentUser.email,
            username: nil,
            fullName: currentUser.name,
            dateOfBirth: nil,
            height: nil,
            heightUnit: nil,
            gender: nil,
            activityLevel: nil,
            goalWeight: nil,
            goalWeightUnit: nil,
            onboardingCompleted: currentUser.onboardingCompleted
        )
        let nextProfile = updatedProfile(currentProfile)

        CoreDataManager.shared.saveProfile(
            nextProfile,
            userId: currentUser.id,
            email: currentUser.email,
            markSynced: false
        )

        Task { @MainActor in
            do {
                try await authManager.updateProfileDurably(updates)
                _ = authManager.applySavedProfileToCurrentUser(nextProfile)
            } catch {
                profileEditorErrorMessage = "Your change is saved locally and will retry when the connection is available."
            }
        }
    }
}

struct ProfileNameEditorSheet: View {
    @Binding var name: String
    @Binding var hasChanges: Bool
    let onCommit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Full name", text: $name)
                        .textContentType(.name)
                        .focused($isFocused)
                        .onChange(of: name) { _, _ in hasChanges = true }
                }
            }
            .navigationTitle("Full Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .jovieTouchTarget()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onCommit()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .jovieTouchTarget()
                }
            }
            .onAppear {
                isFocused = true
            }
        }
    }
}
