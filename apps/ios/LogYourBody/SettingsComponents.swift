//
// SettingsComponents.swift
// LogYourBody
//
import SwiftUI

struct SettingsDesign {
    // Spacing
    static let sectionSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 0
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12

    // Sizing
    static let rowHeight: CGFloat = 48
    static let iconSize: CGFloat = 20
    static let iconFrame: CGFloat = 24
    static let chevronSize: Font = .caption2
    static let cornerRadius: CGFloat = 12

    // Typography
    static let titleFont: Font = .system(size: 16)
    static let valueFont: Font = .caption
    static let sectionHeaderFont: Font = .system(size: 13, weight: .medium)

    // Animation
    static let animation: Animation = .spring(response: 0.3, dampingFraction: 0.8)
}

// MARK: - Section Component

struct SettingsSection<Content: View>: View {
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
            // Section Header
            if let header = header {
                HStack {
                    Text(header)
                        .font(SettingsDesign.sectionHeaderFont)
                        .foregroundColor(.appTextSecondary)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Spacer()
                }
                .padding(.horizontal, SettingsDesign.horizontalPadding)
                .padding(.bottom, 8)
            }

            // Section Content
            VStack(spacing: SettingsDesign.rowSpacing) {
                content
            }
            .background(Color.appCard)
            .cornerRadius(SettingsDesign.cornerRadius)

            // Section Footer
            if let footer = footer {
                Text(footer)
                    .font(.caption)
                    .foregroundColor(.appTextTertiary)
                    .padding(.horizontal, SettingsDesign.horizontalPadding)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Row Component

struct SettingsRow: View {
    let icon: String?
    let title: String
    var subtitle: String?
    var value: String?
    var showChevron: Bool
    var isExternal: Bool
    var tintColor: Color

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        showChevron: Bool = false,
        isExternal: Bool = false,
        tintColor: Color = .primary
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
        HStack(spacing: 12) {
            // Icon
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: SettingsDesign.iconSize))
                    .foregroundColor(tintColor)
                    .frame(width: SettingsDesign.iconFrame)
            }

            // Title + Subtitle stack
            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(SettingsDesign.titleFont)
                    .foregroundColor(tintColor)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            // Value
            if let value = value {
                Text(value)
                    .font(SettingsDesign.valueFont)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // Chevron or External Link
            if showChevron {
                Image(systemName: isExternal ? "arrow.up.right.square" : "chevron.right")
                    .font(SettingsDesign.chevronSize)
                    .foregroundColor(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, SettingsDesign.horizontalPadding)
        .padding(.vertical, SettingsDesign.verticalPadding)
        .contentShape(Rectangle())
    }
}

// MARK: - Navigation Link

struct SettingsNavigationLink<Destination: View>: View {
    let icon: String?
    let title: String
    let subtitle: String?
    let value: String?
    let destination: Destination
    var tintColor: Color

    init(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        value: String? = nil,
        tintColor: Color = .primary,
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
    let icon: String?
    let title: String
    @Binding var isOn: Bool
    var tintColor: Color
    var subtitle: String?
    var onToggle: ((Bool) -> Void)?

    init(
        icon: String? = nil,
        title: String,
        isOn: Binding<Bool>,
        tintColor: Color = .primary,
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
        HStack(spacing: 12) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: SettingsDesign.iconSize))
                    .foregroundColor(tintColor)
                    .frame(width: SettingsDesign.iconFrame)
            }

            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 4) {
                Text(title)
                    .font(SettingsDesign.titleFont)
                    .foregroundColor(tintColor)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(.appPrimary)
        }
        .padding(.horizontal, SettingsDesign.horizontalPadding)
        .padding(.vertical, SettingsDesign.verticalPadding)
        .onChange(of: isOn) { newValue in
            onToggle?(newValue)
        }
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
            SettingsRow(
                icon: icon,
                title: title,
                showChevron: false,
                tintColor: role == .destructive ? .red : .primary
            )
        }
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
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: SettingsDesign.iconSize))
                        .foregroundColor(.primary)
                        .frame(width: SettingsDesign.iconFrame)
                }

                Text(title)
                    .font(SettingsDesign.titleFont)
                    .foregroundColor(.primary)
            }
        }
        .pickerStyle(.menu)
        .padding(.horizontal, SettingsDesign.horizontalPadding)
        .padding(.vertical, SettingsDesign.verticalPadding)
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
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.appCard)
                    .shadow(radius: 20)
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
    let message: String
    let progress: Double?

    init(message: String, progress: Double? = nil) {
        self.message = message
        self.progress = progress
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if let progress = progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.appPrimary)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .appPrimary))
                        .scaleEffect(1.5)
                }

                Text(message)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.appCard)
            )
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
        iconColor: Color = .appTextSecondary
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.iconColor = iconColor
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(iconColor)

            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        iconColor: Color = .appPrimary
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.iconColor = iconColor
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                if let description = description {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, SettingsDesign.horizontalPadding)
        .padding(.vertical, SettingsDesign.verticalPadding)
    }
}

// MARK: - View Extensions

extension View {
    func settingsRowStyle() -> some View {
        self
            .frame(minHeight: SettingsDesign.rowHeight)
            .contentShape(Rectangle())
    }

    func settingsCardStyle() -> some View {
        self
            .background(Color.appCard)
            .cornerRadius(SettingsDesign.cornerRadius)
    }

    func settingsSectionStyle() -> some View {
        self
            .padding(.horizontal, 20)
    }

    func settingsBackground() -> some View {
        self
            .background(Color.appBackground.ignoresSafeArea())
    }
}
