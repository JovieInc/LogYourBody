//
// SettingsRow.swift
// LogYourBody
//
import SwiftUI

// MARK: - Settings Row Type

enum SettingsRowType {
    case navigation
    case toggle(isOn: Binding<Bool>)
    case value(text: String)
    case action
    case picker(selection: Binding<String>, options: [String])
    case stepper(value: Binding<Int>, range: ClosedRange<Int>)
}

// MARK: - Settings Row

struct DesignSettingsRow: View {
    let icon: String?
    let iconColor: Color?
    let title: String
    let subtitle: String?
    let type: SettingsRowType
    let action: (() -> Void)?

    init(
        icon: String? = nil,
        iconColor: Color? = nil,
        title: String,
        subtitle: String? = nil,
        type: SettingsRowType = .navigation,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.action = action
    }

    var body: some View {
        switch type {
        case .toggle(let isOn):
            Toggle(isOn: isOn) {
                rowLabel
            }
        case .picker(let selection, let options):
            Picker(selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            } label: {
                rowLabel
            }
            .pickerStyle(.menu)
        case .stepper(let value, let range):
            Stepper(value: value, in: range) {
                HStack {
                    rowLabel
                    Spacer()
                    Text("\(value.wrappedValue)")
                        .foregroundStyle(.secondary)
                }
            }
        case .value(let text):
            LabeledContent {
                Text(text)
                    .foregroundStyle(.secondary)
            } label: {
                rowLabel
            }
        case .navigation, .action:
            Button(
                action: { action?() },
                label: {
                    HStack {
                        rowLabel
                        Spacer()
                        if case .navigation = type {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
            )
            .buttonStyle(.plain)
            .disabled(!isInteractive)
        }
    }

    private var rowLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        } icon: {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(iconColor ?? .accentColor)
            }
        }
    }

    private var isInteractive: Bool {
        switch type {
        case .navigation, .action:
            return true
        default:
            return false
        }
    }
}

// MARK: - Settings Section

struct DesignSettingsSection<Content: View>: View {
    let title: String?
    let footer: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.content = content
    }

    var body: some View {
        SettingsSection(header: title, footer: footer, content: content)
    }
}

// MARK: - List Row

struct ListRow: View {
    let title: String
    let subtitle: String?
    let leading: AnyView?
    let trailing: AnyView?
    let action: (() -> Void)?

    init(
        title: String,
        subtitle: String? = nil,
        leading: AnyView? = nil,
        trailing: AnyView? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.leading = leading
        self.trailing = trailing
        self.action = action
    }

    var body: some View {
        Button(
            action: { action?() },
            label: {
                HStack(spacing: 12) {
                    if let leading {
                        leading
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    if let trailing {
                        trailing
                    } else if action != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
        )
        .buttonStyle(.plain)
        .disabled(action == nil)
    }
}

// MARK: - Destructive Row

struct DestructiveRow: View {
    let title: String
    let icon: String?
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            if let icon {
                Label(title, systemImage: icon)
            } else {
                Text(title)
            }
        }
    }
}

// MARK: - Preview

struct SettingsRow_Previews: PreviewProvider {
    static var previews: some View {
        ThemePreview {
            List {
                DesignSettingsSection(title: "Account") {
                    DesignSettingsRow(
                        icon: "person.circle",
                        title: "Profile",
                        subtitle: "John Doe",
                        type: .navigation
                    ) { }

                    DesignSettingsRow(
                        icon: "envelope",
                        title: "Email",
                        type: .value(text: "john@example.com")
                    )
                }

                DesignSettingsSection(title: "Preferences") {
                    DesignSettingsRow(
                        icon: "moon",
                        title: "Dark Mode",
                        type: .toggle(isOn: .constant(true))
                    )

                    DesignSettingsRow(
                        icon: "textformat",
                        title: "Font Size",
                        type: .picker(
                            selection: .constant("Medium"),
                            options: ["Small", "Medium", "Large"]
                        )
                    )

                    DesignSettingsRow(
                        icon: "bell",
                        title: "Notifications",
                        subtitle: "Manage notification preferences",
                        type: .navigation
                    ) { }
                }

                DesignSettingsSection(
                    title: "Data",
                    footer: "Your data will be permanently deleted"
                ) {
                    DestructiveRow(
                        title: "Delete Account",
                        icon: "trash"
                    ) { }
                }

                DesignSettingsSection(title: "Recent Activity") {
                    ListRow(
                        title: "Workout Session",
                        subtitle: "45 minutes • 320 calories",
                        leading: AnyView(
                            Image(systemName: "figure.run")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        ),
                        trailing: AnyView(
                            Text("2h ago")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        )
                    ) { }

                    ListRow(
                        title: "Weight Entry",
                        subtitle: "72.5 kg",
                        leading: AnyView(
                            Image(systemName: "scalemass")
                                .font(.title3)
                                .foregroundStyle(.blue)
                        ),
                        trailing: AnyView(
                            Text("Yesterday")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        )
                    ) { }
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}
