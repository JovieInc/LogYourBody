//
// StandardCard.swift
// LogYourBody
//
import SwiftUI

// MARK: - Card Style Enum

enum CardStyle {
    case standard
    case elevated
    case outlined
    case glass
}

// MARK: - Standard Card

struct StandardCard<Content: View>: View {
    let style: CardStyle
    let padding: CGFloat?
    @ViewBuilder let content: () -> Content

    init(
        style: CardStyle = .standard,
        padding: CGFloat? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.style = style
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding ?? 16)
            .background(backgroundView)
            .cornerRadius(12)
            .overlay(overlayView)
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }

    // MARK: - Computed Properties

    @ViewBuilder private var backgroundView: some View {
        switch style {
        case .standard:
            Color.appCard
        case .elevated:
            Color.appCard
        case .outlined:
            Color.appBackground
        case .glass:
            GlassBackground()
        }
    }

    @ViewBuilder private var overlayView: some View {
        switch style {
        case .outlined:
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorder, lineWidth: 1)
        case .glass:
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appBorder.opacity(0.3), lineWidth: 1)
        default:
            EmptyView()
        }
    }

    private var shadowColor: Color {
        switch style {
        case .elevated:
            return Color.black.opacity(0.15)
        case .glass:
            return Color.black.opacity(0.2)
        default:
            return Color.clear
        }
    }

    private var shadowRadius: CGFloat {
        switch style {
        case .elevated:
            return 8
        case .glass:
            return 12
        default:
            return 0
        }
    }

    private var shadowY: CGFloat {
        switch style {
        case .elevated:
            return 2
        case .glass:
            return 4
        default:
            return 0
        }
    }
}

// MARK: - Glass Background

struct GlassBackground: View {
    var body: some View {
        ZStack {
            Color.appCard.opacity(0.8)

            VisualEffectBlur(blurStyle: .systemUltraThinMaterialDark)
                .opacity(0.5)
        }
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let value: String
    let label: String
    let icon: String?
    let trend: Trend?
    let isEstimated: Bool

    enum Trend {
        case up(Double)
        case down(Double)
        case neutral

        var icon: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .neutral: return "minus"
            }
        }

        var color: Color {
            switch self {
            case .up: return Color(hex: "#4CAF50")
            case .down: return Color(hex: "#F44336")
            case .neutral: return Color(hex: "#9CA0A8")
            }
        }
    }

    init(
        value: String,
        label: String,
        icon: String? = nil,
        trend: Trend? = nil,
        isEstimated: Bool = false
    ) {
        self.value = value
        self.label = label
        self.icon = icon
        self.trend = trend
        self.isEstimated = isEstimated
    }

    var body: some View {
        StandardCard(style: .standard, padding: 8) {
            VStack(alignment: .leading, spacing: 4) {
                // Header with icon and trend
                HStack {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let trend = trend {
                        HStack(spacing: 2) {
                            Image(systemName: trend.icon)
                                .font(.system(size: 12, weight: .semibold))
                            if case let .up(value) = trend {
                                Text("+\(Int(value))%")
                                    .font(.caption)
                            } else if case let .down(value) = trend {
                                Text("-\(Int(value))%")
                                    .font(.caption)
                            }
                        }
                        .foregroundColor(trend.color)
                    }

                    if isEstimated {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }

                // Value
                Text(value)
                    .font(.largeTitle)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Label
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Info Card

struct InfoCard: View {
    let icon: String
    let iconColor: Color?
    let title: String
    let description: String

    init(
        icon: String,
        iconColor: Color? = nil,
        title: String,
        description: String
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.description = description
    }

    var body: some View {
        StandardCard(style: .outlined) {
            HStack(alignment: .top, spacing: 12) {
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor ?? .appPrimary)
                    .frame(width: 32, height: 32)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                        .foregroundColor(.primary)

                    Text(description)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Action Card

struct ActionCard<Destination: View>: View {
    let icon: String
    let title: String
    let subtitle: String?
    let destination: () -> Destination

    @State private var isPressed = false

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder destination: @escaping () -> Destination
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.destination = destination
    }

    var body: some View {
        NavigationLink(destination: destination) {
            StandardCard(style: .standard) {
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(.appPrimary)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(Color.appPrimary.opacity(0.1))
                        )

                    // Content
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.callout)
                            .foregroundColor(.primary)

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary.opacity(0.6))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Preview

struct StandardCard_Previews: PreviewProvider {
    static var previews: some View {
        ThemePreview {
            ScrollView {
                VStack(spacing: 16) {
                    // Standard cards
                    StandardCard {
                        Text("Standard Card")
                            .foregroundColor(.white)
                    }

                    StandardCard(style: .elevated) {
                        Text("Elevated Card")
                            .foregroundColor(.white)
                    }

                    StandardCard(style: .outlined) {
                        Text("Outlined Card")
                            .foregroundColor(.white)
                    }

                    StandardCard(style: .glass) {
                        Text("Glass Card")
                            .foregroundColor(.white)
                    }

                    // Metric cards
                    HStack(spacing: 12) {
                        MetricCard(
                            value: "72.5",
                            label: "Weight (kg)",
                            icon: "scalemass",
                            trend: .down(2.3)
                        )

                        MetricCard(
                            value: "15.2%",
                            label: "Body Fat",
                            icon: "percent",
                            trend: .up(0.5),
                            isEstimated: true
                        )
                    }

                    // Info card
                    InfoCard(
                        icon: "lightbulb.fill",
                        iconColor: .yellow,
                        title: "Pro Tip",
                        description: "Track your measurements at the same time each day for more consistent results."
                    )

                    // Action card
                    ActionCard(
                        icon: "camera.fill",
                        title: "Add Progress Photo",
                        subtitle: "Document your transformation"
                    ) {
                        Text("Camera View")
                    }
                }
                .padding()
            }
            .background(Color.black)
        }
    }
}
