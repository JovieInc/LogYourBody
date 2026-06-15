//
// SettingsComponents.swift
// LogYourBody
//
import SwiftUI

private enum SettingsLayout {
    static let rowMinHeight: CGFloat = 50
    static let iconSize: CGFloat = 20
    static let iconFrame: CGFloat = 24
}

// MARK: - Section Component

struct SettingsSection<Content: View>: View {
    @Environment(\.theme)
    private var theme

    let header: String?
    let footer: String?
    @ViewBuilder let content: Content

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
        VStack(spacing: 0) {
            if let header = header {
                HStack {
                    Text(header)
                        .font(theme.typography.captionLarge.weight(.semibold))
                        .foregroundColor(theme.colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.horizontal, theme.spacing.md)
                .padding(.bottom, theme.spacing.xs)
            }

            VStack(spacing: 0) {
                content
            }
            .systemBGlassSurface(
                cornerRadius: theme.radius.card,
                tint: theme.colors.text,
                tintOpacity: 0.045,
                borderColor: theme.colors.border,
                borderOpacity: 0.75
            )

            if let footer = footer {
                Text(footer)
                    .font(theme.typography.captionMedium)
                    .foregroundColor(theme.colors.textTertiary)
                    .padding(.horizontal, theme.spacing.md)
                    .padding(.top, theme.spacing.xs)
            }
        }
    }
}

// MARK: - Row Component

struct SettingsRow: View {
    @Environment(\.theme)
    private var theme

    let icon: String?
    let title: String
    var subtitle: String?
    var value: String?
    var showChevron: Bool
    var isExternal: Bool
    var tintColor: Color?

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        showChevron: Bool = false,
        isExternal: Bool = false,
        tintColor: Color? = nil
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.showChevron = showChevron
        self.isExternal = isExternal
        self.tintColor = tintColor
    }

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(theme.typography.headlineSmall)
                    .foregroundColor(resolvedTint)
                    .frame(width: SettingsLayout.iconFrame)
            }

            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(theme.typography.labelLarge)
                    .foregroundColor(resolvedTint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if let value = value {
                Text(value)
                    .font(theme.typography.captionLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            if showChevron {
                Image(systemName: isExternal ? "arrow.up.right.square" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(theme.colors.textTertiary)
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .frame(minHeight: SettingsLayout.rowMinHeight)
        .contentShape(Rectangle())
    }

    private var resolvedTint: Color {
        tintColor ?? theme.colors.text
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
                showChevron: true,
                tintColor: tintColor
            )
        }
    }
}

// MARK: - Toggle Row

struct SettingsToggleRow: View {
    @Environment(\.theme)
    private var theme

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
        HStack(spacing: theme.spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(theme.typography.headlineSmall)
                    .foregroundColor(resolvedTint)
                    .frame(width: SettingsLayout.iconFrame)
            }

            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(theme.typography.labelLarge)
                    .foregroundColor(resolvedTint)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(theme.colors.primary)
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .frame(minHeight: SettingsLayout.rowMinHeight)
        .onChange(of: isOn) { _, newValue in
            onToggle?(newValue)
        }
    }

    private var resolvedTint: Color {
        tintColor ?? theme.colors.text
    }
}

// MARK: - Button Row

struct SettingsButtonRow: View {
    @Environment(\.theme)
    private var theme

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
            SettingsRow(
                icon: icon,
                title: title,
                showChevron: false,
                tintColor: role == .destructive ? theme.colors.error : nil
            )
        }
    }
}

// MARK: - Picker Row

struct SettingsPickerRow<SelectionValue: Hashable>: View {
    @Environment(\.theme)
    private var theme

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
            HStack(spacing: theme.spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(theme.typography.headlineSmall)
                        .foregroundColor(theme.colors.text)
                        .frame(width: SettingsLayout.iconFrame)
                }

                Text(title)
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.text)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .frame(minHeight: SettingsLayout.rowMinHeight)
    }
}

// MARK: - Success Overlay

struct SuccessOverlay: View {
    @Environment(\.theme)
    private var theme

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
            VStack(spacing: theme.spacing.md) {
                Image(systemName: icon)
                    .font(theme.typography.displayMedium)
                    .foregroundColor(theme.colors.success)

                Text(message)
                    .font(theme.typography.headlineSmall)
                    .foregroundColor(theme.colors.text)
                    .multilineTextAlignment(.center)
            }
            .padding(theme.spacing.xl)
            .systemBGlassSurface(
                cornerRadius: theme.radius.lg,
                tint: theme.colors.text,
                tintOpacity: 0.055,
                borderColor: theme.colors.border,
                borderOpacity: 0.8,
                shadowOpacity: 0.32,
                shadowRadius: 20,
                shadowY: 10
            )
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
    @Environment(\.theme)
    private var theme

    let message: String
    let progress: Double?

    init(message: String, progress: Double? = nil) {
        self.message = message
        self.progress = progress
    }

    var body: some View {
        ZStack {
            theme.colors.background.opacity(0.58)
                .ignoresSafeArea()

            VStack(spacing: theme.spacing.lg) {
                if let progress = progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(theme.colors.primary)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.primary))
                        .scaleEffect(1.5)
                }

                Text(message)
                    .font(theme.typography.headlineSmall)
                    .foregroundColor(theme.colors.text)
            }
            .padding(theme.spacing.xl)
            .systemBGlassSurface(
                cornerRadius: theme.radius.lg,
                tint: theme.colors.text,
                tintOpacity: 0.055,
                borderColor: theme.colors.border,
                borderOpacity: 0.8
            )
        }
    }
}

// MARK: - Empty State

struct SettingsEmptyState: View {
    @Environment(\.theme)
    private var theme

    let icon: String
    let title: String
    let message: String
    let iconColor: Color

    init(
        icon: String,
        title: String,
        message: String,
        iconColor: Color = DefaultTheme().colors.textSecondary
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.iconColor = iconColor
    }

    var body: some View {
        VStack(spacing: theme.spacing.md) {
            Image(systemName: icon)
                .font(theme.typography.displayLarge)
                .foregroundColor(iconColor)

            Text(title)
                .font(theme.typography.headlineSmall)
                .foregroundColor(theme.colors.text)

            Text(message)
                .font(theme.typography.bodySmall)
                .foregroundColor(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(theme.spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Data Info Row

struct DataInfoRow: View {
    @Environment(\.theme)
    private var theme

    let icon: String
    let title: String
    let description: String?
    let iconColor: Color

    init(
        icon: String,
        title: String,
        description: String? = nil,
        iconColor: Color = DefaultTheme().colors.primary
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.iconColor = iconColor
    }

    var body: some View {
        HStack(alignment: .center, spacing: theme.spacing.md) {
            Image(systemName: icon)
                .font(theme.typography.headlineMedium)
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.text)

                if let description = description {
                    Text(description)
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .frame(minHeight: SettingsLayout.rowMinHeight)
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
    @Environment(\.theme)
    private var theme

    func body(content: Content) -> some View {
        content.systemBGlassSurface(
            cornerRadius: theme.radius.card,
            tint: theme.colors.text,
            tintOpacity: 0.045,
            borderColor: theme.colors.border,
            borderOpacity: 0.75
        )
    }
}

private struct SettingsSectionStyleModifier: ViewModifier {
    @Environment(\.theme)
    private var theme

    func body(content: Content) -> some View {
        content.padding(.horizontal, theme.spacing.screenPadding)
    }
}

private struct SettingsBackgroundModifier: ViewModifier {
    @Environment(\.theme)
    private var theme

    func body(content: Content) -> some View {
        content.background(theme.colors.background.ignoresSafeArea())
    }
}

private struct SettingsInputStyleModifier: ViewModifier {
    @Environment(\.theme)
    private var theme

    func body(content: Content) -> some View {
        content
            .font(theme.typography.bodyMedium)
            .foregroundColor(theme.colors.text)
            .tint(theme.colors.primary)
            .padding(.horizontal, theme.spacing.md)
            .padding(.vertical, theme.spacing.sm)
            .systemBGlassSurface(
                cornerRadius: theme.radius.input,
                tint: theme.colors.text,
                tintOpacity: 0.045,
                borderColor: theme.colors.border,
                borderOpacity: 0.75
            )
    }
}
