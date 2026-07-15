//
// PreferencesView+PhotosAdvancedSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var photosSection: some View {
        SettingsSection(header: "Photos") {
            SettingsToggleRow(
                icon: "photo.on.rectangle.angled",
                title: "Remove from Photos after import",
                isOn: $deletePhotosAfterImport,
                subtitle: "Automatically delete photos after importing them.",
                onToggle: { _ in
                    HapticManager.shared.selection()
                }
            )
        }
    }

    var advancedSection: some View {
        SettingsSection(header: "Restore purchases") {
            SettingsButtonRow(
                icon: "arrow.triangle.2.circlepath",
                title: isRestoringPurchases ? "Restoring purchases…" : "Restore purchases"
            ) {
                restorePurchases()
            }
            .disabled(isRestoringPurchases)
            .accessibilityValue(isRestoringPurchases ? "In progress" : "")
            .accessibilityHint("Attempts to restore your active subscription.")
            .accessibilityIdentifier("settings_restore_purchases_button")
        }
    }

    var dangerSection: some View {
        SettingsSection(
            header: "Danger zone",
            footer: "This permanently deletes your account and all data. This can’t be undone."
        ) {
            NavigationLink {
                DeleteAccountView()
            } label: {
                SettingsRow(
                    icon: "trash",
                    title: "Delete account",
                    subtitle: "Permanently remove your account and data.",
                    showChevron: true,
                    tintColor: theme.colors.error
                )
            }
            .accessibilityLabel("Delete account")
            .accessibilityHint("Permanently deletes your account and all data.")
            .simultaneousGesture(
                TapGesture().onEnded {
                    HapticManager.shared.notification(type: .error)
                }
            )
            .buttonStyle(.plain)
        }
    }

    func restorePurchases() {
        guard !isRestoringPurchases else { return }

        isRestoringPurchases = true
        HapticManager.shared.selection()

        Task {
            let success = await subscriptionManager.restorePurchases()
            await MainActor.run {
                isRestoringPurchases = false
                restoreAlertMessage = success
                    ? "Your subscription has been restored"
                    : (subscriptionManager.errorMessage ?? "No active subscription found")
                showingRestoreAlert = true
            }
        }
    }
}
