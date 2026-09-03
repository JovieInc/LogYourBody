//
// SettingsComponents.swift
// LogYourBody
//
import SwiftUI

private enum SettingsLayout {
    static let rowMinHeight: CGFloat = max(52, JovieTokens.minimumHitTarget)
    static let iconFrame: CGFloat = 24
}

// MARK: - Settings Surface Policy

enum SettingsSurfacePolicy {
    static let settingsScreen = WorldClassScreen.settings
    static let editProfileScreen = WorldClassScreen.editProfile

    static let profileNameRowIdentifier = "settings_profile_name_row"
    static let profileDateOfBirthRowIdentifier = "settings_profile_date_of_birth_row"
    static let profileHeightRowIdentifier = "settings_profile_height_row"
    static let profileNameEditorIdentifier = "profile_name_editor"
    static let profileDateOfBirthEditorIdentifier = "profile_date_of_birth_editor"
    static let profileHeightEditorIdentifier = "profile_height_editor"
    static let profileEditorCancelIdentifier = "profile_editor_cancel_button"

    static let rootAccessibilityIdentifiers = [
        "settings_profile_link",
        "settings_tracking_link",
        "settings_integrations_link",
        "settings_account_subscription_link",
        "settings_privacy_data_link",
        WorldClassScreen.settings.accessibilityIdentifier
    ]

    static let profileEditorAccessibilityIdentifiers = [
        WorldClassScreen.editProfile.accessibilityIdentifier,
        profileNameEditorIdentifier,
        profileDateOfBirthEditorIdentifier,
        profileHeightEditorIdentifier,
        profileEditorCancelIdentifier
    ]

    static let nestedAccessibilityIdentifiers = [
        "settings_logout_button",
        profileNameRowIdentifier,
        profileDateOfBirthRowIdentifier,
        profileHeightRowIdentifier,
        "settings_units_row",
        "settings_step_goal_row",
        "settings_daily_weigh_in_reminder_toggle",
        "settings_daily_weigh_in_reminder_time_picker",
        "settings_subscription_status_row",
        "settings_manage_subscription_button",
        "settings_restore_purchases_button",
        "settings_goal_editor_sheet",
        "settings_goal_editor_text_field"
    ] + profileEditorAccessibilityIdentifiers
}

// MARK: - Section Component

struct SettingsSection<Content: View>: View {
    let header: String?
    let footer: String?
    let content: Content

    init(
        header: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        switch (header, footer) {
        case let (header?, footer?):
            Section {
                content
            } header: {
                Text(header)
            } footer: {
                Text(footer)
            }
        case let (header?, nil):
            Section {
                content
            } header: {
                Text(header)
            }
        case let (nil, footer?):
            Section {
                content
            } footer: {
                Text(footer)
            }
        case (nil, nil):
            Section {
                content
            }
        }
    }
}

// MARK: - Row Component

struct SettingsRow: View {
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    let icon: String?
    let title: String
    var subtitle: String?
    var subtitleColor: Color?
    var value: String?
    var showChevron: Bool
    var isExternal: Bool
    var tintColor: Color?

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        subtitleColor: Color? = nil,
        value: String? = nil,
        showChevron: Bool = false,
        isExternal: Bool = false,
        tintColor: Color? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.value = value
        self.showChevron = showChevron
        self.isExternal = isExternal
        self.tintColor = tintColor
    }

    var body: some View {
        Group {
            if usesStackedValueLayout, let value {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        leadingContent
                        Spacer(minLength: 8)
                        disclosureIndicator
                    }

                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, valueLeadingInset)
                }
            } else {
                HStack(spacing: 12) {
                    leadingContent
                    Spacer(minLength: 8)

                    if let value {
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }

                    disclosureIndicator
                }
            }
        }
        .frame(minHeight: SettingsLayout.rowMinHeight)
        .contentShape(Rectangle())
    }

    private var usesStackedValueLayout: Bool {
        dynamicTypeSize.isAccessibilitySize && value != nil
    }

    private var valueLeadingInset: CGFloat {
        icon == nil ? 0 : SettingsLayout.iconFrame + 12
    }

    private var leadingContent: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(resolvedTint)
                    .frame(width: SettingsLayout.iconFrame)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(resolvedTint)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(subtitleColor ?? .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var disclosureIndicator: some View {
        if showChevron {
            Image(systemName: isExternal ? "arrow.up.right.square" : "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var resolvedTint: Color {
        tintColor ?? .primary
    }
}

// MARK: - Navigation Link

struct SettingsNavigationLink<Destination: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let value: String?
    let destination: Destination
    var tintColor: Color?

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        tintColor: Color? = nil,
        @ViewBuilder destination: () -> Destination
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.tintColor = tintColor
        self.destination = destination()
    }

    var body: some View {
        NavigationLink(destination: destination) {
            SettingsRow(
                icon: icon,
                title: title,
                subtitle: subtitle,
                value: value,
                showChevron: false,
                tintColor: tintColor
            )
        }
    }
}

// MARK: - Detail Screen

struct SettingsBackButton: View {
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(
                    width: JovieTokens.minimumHitTarget,
                    height: JovieTokens.minimumHitTarget
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityHint("Returns to Settings")
    }
}

struct SettingsDetailScreen<Content: View>: View {
    let title: String
    let content: Content

    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Toggle Row

struct SettingsToggleRow: View {
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    let icon: String?
    let title: String
    @Binding var isOn: Bool
    var tintColor: Color?
    var subtitle: String?
    var onToggle: ((Bool) -> Void)?

    init(
        icon: String? = nil,
        title: String,
        isOn: Binding<Bool>,
        tintColor: Color? = nil,
        subtitle: String? = nil,
        onToggle: ((Bool) -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self._isOn = isOn
        self.tintColor = tintColor
        self.subtitle = subtitle
        self.onToggle = onToggle
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(resolvedTint)
                        .frame(width: SettingsLayout.iconFrame)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(resolvedTint)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(minHeight: SettingsLayout.rowMinHeight)
        .tint(.accentColor)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityHint(subtitle ?? "")
        .onChange(of: isOn) { _, newValue in
            onToggle?(newValue)
        }
    }

    private var resolvedTint: Color {
        tintColor ?? .primary
    }
}

// MARK: - Button Row

struct SettingsButtonRow: View {
    let icon: String?
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    init(
        icon: String? = nil,
        title: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            if let icon {
                Label(title, systemImage: icon)
            } else {
                Text(title)
            }
        }
        .frame(minHeight: SettingsLayout.rowMinHeight, alignment: .leading)
    }
}

// MARK: - Picker Row

struct SettingsPickerRow<SelectionValue: Hashable>: View {
    let icon: String?
    let title: String
    @Binding var selection: SelectionValue
    let options: [(value: SelectionValue, label: String)]

    var body: some View {
        Picker(selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        } label: {
            if let icon {
                Label(title, systemImage: icon)
            } else {
                Text(title)
            }
        }
        .pickerStyle(.menu)
        .frame(minHeight: SettingsLayout.rowMinHeight)
    }
}

// MARK: - Success Overlay

struct SuccessOverlay: View {
    @Binding var isShowing: Bool
    let message: String
    let icon: String
    let autoDismissDelay: TimeInterval

    init(
        isShowing: Binding<Bool>,
        message: String,
        icon: String = "checkmark.circle.fill",
        autoDismissDelay: TimeInterval = 2.0
    ) {
        self._isShowing = isShowing
        self.message = message
        self.icon = icon
        self.autoDismissDelay = autoDismissDelay
    }

    var body: some View {
        if isShowing {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundStyle(Color.appSuccess)

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.scale.combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissDelay) {
                    withAnimation {
                        isShowing = false
                    }
                }
            }
        }
    }
}

// MARK: - Loading Overlay

struct LoadingOverlay: View {
    let message: String
    let progress: Double?

    init(message: String, progress: Double? = nil) {
        self.message = message
        self.progress = progress
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                }

                Text(message)
                    .font(.headline)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Empty State

struct SettingsEmptyState: View {
    let icon: String
    let title: String
    let message: String
    let iconColor: Color

    init(
        icon: String,
        title: String,
        message: String,
        iconColor: Color = .secondary
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.iconColor = iconColor
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
                .foregroundStyle(iconColor)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Data Info Row

struct DataInfoRow: View {
    let icon: String
    let title: String
    let description: String?
    let iconColor: Color

    init(
        icon: String,
        title: String,
        description: String? = nil,
        iconColor: Color = .accentColor
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.iconColor = iconColor
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)

                if let description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
        }
        .frame(minHeight: SettingsLayout.rowMinHeight, alignment: .leading)
    }
}

// MARK: - View Extensions

extension View {
    func settingsRowStyle() -> some View {
        modifier(SettingsRowStyleModifier())
    }

    func settingsCardStyle() -> some View {
        modifier(SettingsCardStyleModifier())
    }

    func settingsSectionStyle() -> some View {
        modifier(SettingsSectionStyleModifier())
    }

    func settingsBackground() -> some View {
        modifier(SettingsBackgroundModifier())
    }

    func settingsInputStyle() -> some View {
        modifier(SettingsInputStyleModifier())
    }
}

private struct SettingsRowStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(minHeight: SettingsLayout.rowMinHeight)
            .contentShape(Rectangle())
    }
}

private struct SettingsCardStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private struct SettingsSectionStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private struct SettingsBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

private struct SettingsInputStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(.primary)
            .tint(.accentColor)
    }
}
