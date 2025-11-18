//
// StandardHeader.swift
// LogYourBody
//
import SwiftUI

enum HeaderStyle {
    case standard
    case large
    case minimal
    case transparent
}

// MARK: - Standard Header

struct StandardHeader: View {
    @Environment(\.dismiss)
    var dismiss

    let title: String
    let subtitle: String?
    let style: HeaderStyle
    let showBackButton: Bool
    let backAction: (() -> Void)?
    let trailingItems: [HeaderAction]

    @State private var scrollOffset: CGFloat = 0

    init(
        title: String,
        subtitle: String? = nil,
        style: HeaderStyle = .standard,
        showBackButton: Bool = true,
        backAction: (() -> Void)? = nil,
        trailingItems: [HeaderAction] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.showBackButton = showBackButton
        self.backAction = backAction
        self.trailingItems = trailingItems
    }

    var body: some View {
        ZStack {
            // Background
            backgroundView

            // Content
            switch style {
            case .standard, .transparent:
                standardHeader
            case .large:
                largeHeader
            case .minimal:
                minimalHeader
            }
        }
        .frame(height: headerHeight)
    }

    // MARK: - Header Variants

    private var standardHeader: some View {
        HStack(spacing: 12) {
            // Leading items
            if showBackButton {
                BackButton(action: backAction ?? { dismiss() })
            }

            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Trailing items
            HStack(spacing: 8) {
                ForEach(trailingItems) { action in
                    HeaderActionButton(action: action)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, safeAreaTop)
        .padding(.bottom, 8)
    }

    private var largeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top bar
            HStack {
                if showBackButton {
                    BackButton(action: backAction ?? { dismiss() })
                }

                Spacer()

                HStack(spacing: 8) {
                    ForEach(trailingItems) { action in
                        HeaderActionButton(action: action)
                    }
                }
            }

            // Large title
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.largeTitle)
                    .foregroundColor(.primary)
                    .lineLimit(2)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, safeAreaTop)
        .padding(.bottom, 12)
    }

    private var minimalHeader: some View {
        HStack {
            if showBackButton {
                BackButton(action: backAction ?? { dismiss() })
            }

            Spacer()

            Text(title)
                .font(.callout)
                .foregroundColor(.primary)

            Spacer()

            // Balance the layout
            if showBackButton {
                Color.clear
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, safeAreaTop)
        .padding(.bottom, 4)
    }

    // MARK: - Computed Properties

    @ViewBuilder private var backgroundView: some View {
        switch style {
        case .transparent:
            Color.clear
        default:
            Color.appBackground
                .overlay(
                    VStack {
                        Spacer()
                        Divider()
                            .background(Color.appBorder)
                    }
                )
        }
    }

    private var headerHeight: CGFloat {
        switch style {
        case .large:
            return 120 + safeAreaTop
        case .minimal:
            return 44 + safeAreaTop
        default:
            return 56 + safeAreaTop
        }
    }

    private var safeAreaTop: CGFloat {
        UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0
    }
}

// MARK: - Header Action

struct HeaderAction: Identifiable {
    let id = UUID()
    let icon: String
    let badge: Int?
    let action: () -> Void

    init(icon: String, badge: Int? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.badge = badge
        self.action = action
    }
}

// MARK: - Header Action Button

struct HeaderActionButton: View {
    let action: HeaderAction
    @State private var isPressed = false

    var body: some View {
        Button(
            action: {
                // HapticManager.shared.impact(style: .light)
                action.action()
            },
            label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: action.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.appCard)
                        )

                    // Badge
                    if let badge = action.badge, badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .padding(.horizontal, 4)
                            .background(
                                Capsule()
                                    .fill(.red)
                            )
                            .offset(x: 6, y: -6)
                    }
                }
                .scaleEffect(isPressed ? 0.9 : 1.0)
            }
        )
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Back Button

struct BackButton: View {
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(
            action: {
                // HapticManager.shared.impact(style: .light)
                action()
            },
            label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .font(.footnote)
                }
                .foregroundColor(.appPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.appPrimary.opacity(0.1))
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
            }
        )
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Progress Header

struct ProgressHeader: View {
    let title: String
    let progress: Double
    let showBackButton: Bool
    let backAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            StandardHeader(
                title: title,
                style: .minimal,
                showBackButton: showBackButton,
                backAction: backAction
            )

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color.appCard.opacity(0.5))
                        .frame(height: 3)

                    // Progress
                    Rectangle()
                        .fill(Color.appPrimary)
                        .frame(width: geometry.size.width * progress, height: 3)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Scrollable Header Wrapper

struct ScrollableHeaderView<Content: View>: View {
    let header: StandardHeader
    @ViewBuilder let content: () -> Content

    @State private var scrollOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            // Scrollable content
            ScrollView {
                VStack(spacing: 0) {
                    // Spacer for header
                    Color.clear
                        .frame(height: headerHeight)

                    // Content
                    content()
                }
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }

            // Fixed header
            header
                .background(
                    Color.appBackground
                        .opacity(scrollOffset < -10 ? 1 : 0)
                        .animation(.easeOut(duration: 0.2), value: scrollOffset)
                )
        }
    }

    private var headerHeight: CGFloat {
        switch header.style {
        case .large:
            return 120 + safeAreaTop
        case .minimal:
            return 44 + safeAreaTop
        default:
            return 56 + safeAreaTop
        }
    }

    private var safeAreaTop: CGFloat {
        UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0
    }
}

// MARK: - Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

struct StandardHeader_Previews: PreviewProvider {
    static var previews: some View {
        ThemePreview {
            VStack(spacing: 0) {
                // Standard header
                StandardHeader(
                    title: "Profile",
                    subtitle: "Manage your account",
                    trailingItems: [
                        HeaderAction(icon: "bell", badge: 3) { },
                        HeaderAction(icon: "gear") { }
                    ]
                )

                Spacer().frame(height: 40)

                // Large header
                StandardHeader(
                    title: "Dashboard",
                    subtitle: "Track your progress",
                    style: .large,
                    trailingItems: [
                        HeaderAction(icon: "plus") { }
                    ]
                )

                Spacer().frame(height: 40)

                // Minimal header
                StandardHeader(
                    title: "Settings",
                    style: .minimal
                )

                Spacer().frame(height: 40)

                // Progress header
                ProgressHeader(
                    title: "Complete Profile",
                    progress: 0.7,
                    showBackButton: true,
                    backAction: { }
                )

                Spacer()
            }
            .background(Color.black)
        }
    }
}
