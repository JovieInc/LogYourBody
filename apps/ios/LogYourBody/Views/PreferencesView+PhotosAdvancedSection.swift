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
        SettingsSection(header: "Advanced") {
            VStack(spacing: 12) {
                Button {
                    HapticManager.shared.selection()
                    Task {
                        let success = await revenueCatManager.restorePurchases()
                        await MainActor.run {
                            restoreAlertMessage = success
                                ? "Your subscription has been restored"
                                : (revenueCatManager.errorMessage ?? "No active subscription found")
                            showingRestoreAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Restore purchases")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.appCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                    )
                }
                .accessibilityLabel("Restore purchases")
                .accessibilityHint("Attempts to restore your active subscription.")
                .accessibilityIdentifier("settings_restore_purchases_button")
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
            .padding(.horizontal, SettingsDesign.horizontalPadding)
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
                Text("Delete account")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.red.opacity(0.15))
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
            .padding(.horizontal, SettingsDesign.horizontalPadding)
        }
    }
}
