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
                    .padding(.vertical, theme.spacing.sm)
                    .systemBGlassSurface(
                        cornerRadius: theme.radius.input,
                        tint: theme.colors.text,
                        tintOpacity: 0.045,
                        borderColor: theme.colors.border,
                        borderOpacity: 0.75
                    )
                }
                .accessibilityLabel("Restore purchases")
                .accessibilityHint("Attempts to restore your active subscription.")
                .accessibilityIdentifier("settings_restore_purchases_button")
            }
            .padding(.top, theme.spacing.xxs)
            .padding(.bottom, theme.spacing.xs)
            .padding(.horizontal, theme.spacing.md)
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
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: theme.radius.card)
                            .fill(theme.colors.error.opacity(0.14))
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
            .padding(.horizontal, theme.spacing.md)
        }
    }
}
