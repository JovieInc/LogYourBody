//
// SettingsSectionGroup.swift
// LogYourBody
//
import SwiftUI

// MARK: - Organism: Settings Section Group

struct SettingsSectionGroup<Content: View>: View {
    let sections: [SectionData]

    struct SectionData {
        let id = UUID()
        let header: String?
        let footer: String?
        let content: () -> Content
    }

    init(sections: [SectionData]) {
        self.sections = sections
    }

    var body: some View {
        ForEach(sections, id: \.id) { section in
            SettingsSection(
                header: section.header,
                footer: section.footer,
                content: section.content
            )
        }
    }
}

// MARK: - Settings Link Row

struct SettingsLinkRow<Destination: View>: View {
    let icon: String
    let title: String
    let value: String?
    let tintColor: Color
    let destination: () -> Destination

    init(
        icon: String,
        title: String,
        value: String? = nil,
        tintColor: Color = .primary,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.icon = icon
        self.title = title
        self.value = value
        self.tintColor = tintColor
        self.destination = destination
    }

    var body: some View {
        NavigationLink(destination: destination) {
            SettingsRow(
                icon: icon,
                title: title,
                value: value,
                showChevron: false,
                tintColor: tintColor
            )
        }
    }
}

// MARK: - Settings Action Row

struct SettingsActionRow: View {
    let icon: String
    let title: String
    let tintColor: Color
    let action: () -> Void

    init(
        icon: String,
        title: String,
        tintColor: Color = .primary,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.tintColor = tintColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            SettingsRow(
                icon: icon,
                title: title,
                showChevron: false,
                tintColor: tintColor
            )
        }
    }
}

// MARK: - External Link Row

struct SettingsExternalLinkRow: View {
    let icon: String
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            SettingsRow(
                icon: icon,
                title: title,
                showChevron: true,
                isExternal: true
            )
        }
    }
}

// MARK: - Settings Section Builder

struct SettingsSectionBuilder {
    static func profileSection(
        email: String?,
        onProfileSettings: @escaping () -> Void
    ) -> some View {
        SettingsSection(header: "Profile") {
            SettingsRow(
                icon: "envelope",
                title: "Email",
                value: email ?? "",
                showChevron: false
            )

            SettingsActionRow(
                icon: "person.circle",
                title: "Profile Settings",
                action: onProfileSettings
            )
        }
    }

    static func securitySection(
        onActiveSessions: @escaping () -> Void,
        onChangePassword: @escaping () -> Void
    ) -> some View {
        SettingsSection(header: "Security & Devices") {
            SettingsActionRow(
                icon: "desktopcomputer",
                title: "Active Sessions",
                action: onActiveSessions
            )

            SettingsActionRow(
                icon: "lock.rotation",
                title: "Change Password",
                action: onChangePassword
            )
        }
    }

    static func dangerSection(
        onExportData: @escaping () -> Void,
        onDeleteAccount: @escaping () -> Void
    ) -> some View {
        SettingsSection(header: "Data & Privacy") {
            SettingsActionRow(
                icon: "square.and.arrow.up",
                title: "Export Data",
                action: onExportData
            )

            SettingsActionRow(
                icon: "trash",
                title: "Delete Account",
                tintColor: Color.appError,
                action: onDeleteAccount
            )
        }
    }
}

#Preview {
    List {
        SettingsSectionBuilder.profileSection(
            email: "user@example.com",
            onProfileSettings: { }
        )

        SettingsSectionBuilder.securitySection(
            onActiveSessions: { },
            onChangePassword: { }
        )

        SettingsSectionBuilder.dangerSection(
            onExportData: { },
            onDeleteAccount: { }
        )
    }
    .listStyle(.insetGrouped)
    .preferredColorScheme(.dark)
}
