//
// PreferencesView+AccountSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var accountSection: some View {
        SettingsSection(header: "Account") {
            VStack(spacing: 0) {
                accountEmailRow
                DSDivider().insetted(16)
                changeProfilePhotoRow
                DSDivider().insetted(16)
                logoutRow
            }
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
        Button {
            showingPhotoPicker = true
        } label: {
            SettingsRow(
                icon: "camera.fill",
                title: isUploadingPhoto ? "Uploading..." : "Change profile photo",
                value: isUploadingPhoto ? "\(Int(avatarUploadProgress * 100))%" : nil
            )
        }
        .buttonStyle(.plain)
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
            VStack(spacing: 0) {
                profileFullNameRow
                DSDivider().insetted(16)
                profileDateOfBirthRow
                DSDivider().insetted(16)
                profileHeightRow
            }
        }
    }

    var profileFullNameRow: some View {
        profileRow(
            icon: "person.fill",
            title: "Full name",
            value: authManager.currentUser?.profile?.fullName ?? authManager.currentUser?.name ?? "Not set"
        ) {
            isShowingProfileSettings = true
        }
    }

    var profileDateOfBirthRow: some View {
        profileRow(
            icon: "calendar",
            title: "Date of birth",
            value: dateOfBirthDisplay
        ) {
            isShowingProfileSettings = true
        }
    }

    var profileHeightRow: some View {
        profileRow(
            icon: "ruler",
            title: "Height",
            value: heightDisplayText
        ) {
            isShowingProfileSettings = true
        }
    }

    func profileRow(
        icon: String,
        title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: icon)
                    .font(theme.typography.headlineSmall)
                    .foregroundColor(theme.colors.textSecondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text(title)
                        .font(theme.typography.labelLarge)
                        .foregroundColor(theme.colors.text)

                    Text(value)
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(theme.colors.textTertiary)
            }
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.sm)
            .background(Color.clear)
        }
        .buttonStyle(.plain)
    }
}
