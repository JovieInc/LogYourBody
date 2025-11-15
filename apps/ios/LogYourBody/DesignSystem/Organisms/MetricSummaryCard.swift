//
// MetricSummaryCard.swift
// LogYourBody
//
// Apple Health-inspired metric summary card with full state support
//

import SwiftUI
import Charts

// MARK: - MetricSummaryCard Organism

/// Apple Health-style metric card with inline chart, states, and accessibility support.
public struct MetricSummaryCard: View {
    public struct DataPoint: Identifiable {
        public let id = UUID()
        public let index: Int
        public let value: Double

        public init(index: Int, value: Double) {
            self.index = index
            self.value = value
        }
    }

    public struct Trend {
        public let direction: Direction
        public let valueText: String
        public let caption: String?

        public enum Direction {
            case up
            case down
            case flat
        }

        public init(direction: Direction, valueText: String, caption: String? = nil) {
            self.direction = direction
            self.valueText = valueText
            self.caption = caption
        }
    }

    public struct Content {
        public let title: String
        public let value: String
        public let unit: String
        public let timestamp: String?
        public let dataPoints: [DataPoint]
        public let chartAccessibilityLabel: String?
        public let chartAccessibilityValue: String?
        public let trend: Trend?
        public let footnote: String?

        public init(title: String, value: String, unit: String, timestamp: String?, dataPoints: [DataPoint], chartAccessibilityLabel: String?, chartAccessibilityValue: String?, trend: Trend?, footnote: String?) {
            self.title = title
            self.value = value
            self.unit = unit
            self.timestamp = timestamp
            self.dataPoints = dataPoints
            self.chartAccessibilityLabel = chartAccessibilityLabel
            self.chartAccessibilityValue = chartAccessibilityValue
            self.trend = trend
            self.footnote = footnote
        }
    }

    public struct CardAction {
        public let title: String
        public let handler: () -> Void

        public init(title: String, handler: @escaping () -> Void) {
            self.title = title
            self.handler = handler
        }
    }

    public enum State {
        case loading
        case empty(message: String, action: CardAction?)
        case error(message: String, action: CardAction?)
        case data(Content)
    }

    public let icon: String
    public let accentColor: Color
    public let state: State
    public var isButtonContext: Bool = false

    public init(icon: String, accentColor: Color, state: State, isButtonContext: Bool = false) {
        self.icon = icon
        self.accentColor = accentColor
        self.state = state
        self.isButtonContext = isButtonContext
    }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title3) private var unitFontSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 60
    @ScaledMetric(relativeTo: .body) private var headerIconSize: CGFloat = 18

    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 16

    private var isAccessibilityCategory: Bool {
        dynamicTypeSize >= .accessibility1
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        return ZStack {
            // Solid background layer
            shape
                .fill(Color.linearCard)

            // Optional material overlay for subtle softness (reduced for flatter look)
            if !reduceTransparency {
                shape
                    .fill(.ultraThinMaterial.opacity(0.35))
            }

            // Border and soft shadow (Apple Health-style, low contrast)
            shape
                .strokeBorder(borderColor, lineWidth: 1)
                .shadow(color: shadowColor, radius: 6, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, verticalPadding)

                stateView
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 16)
                    .padding(.bottom, verticalPadding)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint ?? "")
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Small icon + title in accent color (Apple Health-style label)
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: headerIconSize, weight: .semibold))
                    .foregroundStyle(accentColor)

                Text(titleText)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
            }

            Spacer()

            // Date (from timestamp) + chevron on the right
            HStack(spacing: 4) {
                timestampText

                if isButtonContext && hasActionableState {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor.opacity(0.7))
                }
            }
        }
    }

    private var stateView: some View {
        switch state {
        case .loading:
            return AnyView(loadingView())
        case .empty(let message, let action):
            return AnyView(messageView(message: message, action: action, iconName: "plus") )
        case .error(let message, let action):
            return AnyView(messageView(message: message, action: action, iconName: "exclamationmark.triangle.fill", isError: true))
        case .data(let content):
            return AnyView(dataView(content))
        }
    }

    private var titleText: String {
        switch state {
        case .data(let content):
            return content.title
        default:
            return "".isEmpty ? "Metric" : "Metric"
        }
    }

    private var timestampText: some View {
        Group {
            switch state {
            case .data(let content):
                if let time = content.timestamp {
                    Text(time)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(secondaryTextColor.opacity(0.8))
                        .transition(.opacity)
                }
            default:
                EmptyView()
            }
        }
    }

    private func dataView(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                valueBlock(for: content)
                    .layoutPriority(2) // Ensure the large value gets horizontal space first

                Spacer(minLength: 12)

                if shouldShowChart(for: content) {
                    chart(for: content)
                        .frame(width: chartWidth, height: chartHeight)
                        .layoutPriority(0)
                }
            }

            if let footnote = content.footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(secondaryTextColor.opacity(0.8))
            }
        }
    }

    private func valueBlock(for content: Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if content.unit.isEmpty {
                    Text(content.value)
                        .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryTextColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .layoutPriority(2)
                } else {
                    // Render value + unit as a single Text so they stay on one line
                    // and scale together, preventing vertical stacking of the unit.
                    (
                        Text(content.value)
                            .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(primaryTextColor)
                            .monospacedDigit()
                        +
                        Text(" \(content.unit)")
                            .font(.system(size: unitFontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(secondaryTextColor)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .layoutPriority(2)
                }
            }

            if let trend = content.trend {
                trendView(trend)
            }
        }
    }

    private func trendView(_ trend: Trend) -> some View {
        HStack(spacing: 6) {
            Image(systemName: trendIcon(for: trend.direction))
                .font(.system(size: 12, weight: .bold))

            Text(trend.valueText)
                .font(.system(.footnote, design: .rounded).weight(.semibold))

            if let caption = trend.caption {
                Text(caption)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(secondaryTextColor.opacity(0.75))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(trendBackground(for: trend.direction))
        .cornerRadius(20)
        .foregroundStyle(trendForeground(for: trend.direction))
    }

    private func chart(for content: Content) -> some View {
        let lineColor = colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.35)

        return Chart {
            // Subtle grey line
            ForEach(content.dataPoints) { point in
                LineMark(
                    x: .value("Index", point.index),
                    y: .value("Value", point.value)
                )
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .foregroundStyle(lineColor)
                .interpolationMethod(.catmullRom)
            }

            // Grey dots for all points
            ForEach(content.dataPoints) { point in
                PointMark(
                    x: .value("Index", point.index),
                    y: .value("Value", point.value)
                )
                .symbolSize(12)
                .foregroundStyle(lineColor)
            }

            // Accent-colored last point
            if let last = content.dataPoints.last {
                PointMark(
                    x: .value("Index", last.index),
                    y: .value("Value", last.value)
                )
                .symbolSize(18)
                .foregroundStyle(accentColor)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .padding(.vertical, 4)
        .accessibilityLabel(content.chartAccessibilityLabel ?? "Trend chart")
        .accessibilityValue(content.chartAccessibilityValue ?? "Latest value \(content.value) \(content.unit)")
        .accessibilityHidden(isAccessibilityCategory)
        .transaction { if reduceMotion { $0.animation = nil } }
    }

    private func loadingView() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 6)
                .fill(placeholderColor)
                .frame(width: 140, height: 36)
                .shimmer()

            RoundedRectangle(cornerRadius: 6)
                .fill(placeholderColor)
                .frame(width: 80, height: 16)
                .shimmer()

            RoundedRectangle(cornerRadius: 8)
                .fill(placeholderColor)
                .frame(maxWidth: .infinity, minHeight: chartHeight)
                .shimmer()
        }
    }

    private func messageView(message: String, action: CardAction?, iconName: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isError ? Color.red : accentColor)

                Text(message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action = action {
                Button(action: action.handler) {
                    Text(action.title)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(actionBackground(isError: isError))
                        .cornerRadius(14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isError ? Color.red : accentColor)
                .accessibilityHint(isError ? "Retry" : "Add data")
            }
        }
    }

    private var hasActionableState: Bool {
        switch state {
        case .data:
            return true
        case .empty(_, let action), .error(_, let action):
            return action != nil || isButtonContext
        case .loading:
            return false
        }
    }

    private func shouldShowChart(for content: Content) -> Bool {
        guard !content.dataPoints.isEmpty else { return false }
        return !isAccessibilityCategory
    }

    private var chartWidth: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium: return 150
        case .large: return 140
        case .xLarge: return 130
        case .xxLarge: return 120
        case .xxxLarge: return 110
        default: return 0 // hidden when in accessibility sizes
        }
    }

    private var borderColor: Color {
        // Increased opacity for better card definition
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.45) : Color.black.opacity(0.12)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.appText
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : Color.appTextSecondary
    }

    private var placeholderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private func trendIcon(for direction: Trend.Direction) -> String {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "arrow.right"
        }
    }

    private func trendBackground(for direction: Trend.Direction) -> Color {
        switch direction {
        case .up:
            return accentColor.opacity(0.15)
        case .down:
            return Color.red.opacity(0.15)
        case .flat:
            return secondaryTextColor.opacity(0.15)
        }
    }

    private func trendForeground(for direction: Trend.Direction) -> Color {
        switch direction {
        case .up:
            return accentColor
        case .down:
            return Color.red
        case .flat:
            return secondaryTextColor
        }
    }

    private func actionBackground(isError: Bool) -> some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle((isError ? Color.red : accentColor).opacity(0.12))
        }
        return AnyShapeStyle((isError ? Color.red : accentColor).opacity(0.08))
    }

    private var accessibilityLabel: String {
        switch state {
        case .loading:
            return "Loading metric"
        case .empty:
            return "No data"
        case .error:
            return "Metric unavailable"
        case .data(let content):
            var components: [String] = [content.title, content.value + (content.unit.isEmpty ? "" : " " + content.unit)]
            if let trend = content.trend {
                components.append(trendAccessibilityText(trend))
            }
            if let timestamp = content.timestamp {
                components.append("Updated \(timestamp)")
            }
            return components.joined(separator: ", ")
        }
    }

    private var accessibilityHint: String? {
        switch state {
        case .loading:
            return ""
        case .empty(_, let action):
            return action == nil ? nil : "Double tap to add data"
        case .error(_, let action):
            return action == nil ? nil : "Double tap to retry"
        case .data:
            return isButtonContext ? "Double tap for details" : nil
        }
    }

    private func trendAccessibilityText(_ trend: Trend) -> String {
        switch trend.direction {
        case .up:
            return "Up \(trend.valueText)"
        case .down:
            return "Down \(trend.valueText)"
        case .flat:
            return "No change \(trend.valueText)"
        }
    }
}

// MARK: - Preview

#Preview("Metric Summary Card States") {
    ScrollView {
        VStack(spacing: 20) {
            Button(action: {}) {
                MetricSummaryCard(
                    icon: "flame.fill",
                    accentColor: .orange,
                    state: .data(
                        MetricSummaryCard.Content(
                            title: "Steps",
                            value: "7,842",
                            unit: "steps",
                            timestamp: "6:15 PM",
                            dataPoints: stride(from: 0, through: 6, by: 1).map { index in
                                MetricSummaryCard.DataPoint(index: index, value: Double(arc4random_uniform(2000) + 4000))
                            },
                            chartAccessibilityLabel: "Steps trend for the last week",
                            chartAccessibilityValue: "Latest value 7,842 steps",
                            trend: MetricSummaryCard.Trend(direction: .up, valueText: "12%", caption: "vs last week"),
                            footnote: "On track for your 10K goal"
                        )
                    ),
                    isButtonContext: true
                )
            }

            MetricSummaryCard(
                icon: "figure.stand",
                accentColor: .purple,
                state: .loading
            )

            MetricSummaryCard(
                icon: "percent",
                accentColor: .teal,
                state: .empty(
                    message: "Log your body fat to see trends and insights.",
                    action: MetricSummaryCard.CardAction(title: "Add measurement", handler: {})
                )
            )

            MetricSummaryCard(
                icon: "figure.arms.open",
                accentColor: .pink,
                state: .error(
                    message: "We couldn’t load FFMI data.",
                    action: MetricSummaryCard.CardAction(title: "Retry", handler: {})
                )
            )
        }
        .padding(24)
    }
    .background(Color.appBackground)
}
