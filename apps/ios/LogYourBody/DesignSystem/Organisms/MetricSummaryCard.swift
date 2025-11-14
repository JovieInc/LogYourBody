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
struct MetricSummaryCard: View {
    struct DataPoint: Identifiable {
        let id = UUID()
        let index: Int
        let value: Double
    }

    struct Trend {
        let direction: Direction
        let valueText: String
        let caption: String?

        enum Direction {
            case up
            case down
            case flat
        }
    }

    struct Content {
        let title: String
        let value: String
        let unit: String
        let timestamp: String?
        let dataPoints: [DataPoint]
        let chartAccessibilityLabel: String?
        let chartAccessibilityValue: String?
        let trend: Trend?
        let footnote: String?
    }

    struct CardAction {
        let title: String
        let handler: () -> Void
    }

    enum State {
        case loading
        case empty(message: String, action: CardAction?)
        case error(message: String, action: CardAction?)
        case data(Content)
    }

    let icon: String
    let accentColor: Color
    let state: State
    var isButtonContext: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title3) private var unitFontSize: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var headerIconSize: CGFloat = 18

    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        return ZStack {
            shape
                .fill(backgroundMaterial)
                .overlay(borderOverlay)
                .shadow(color: shadowColor, radius: 18, x: 0, y: 12)

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
        .accessibilityHint(accessibilityHint)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(colorScheme == .dark ? 0.22 : 0.14))
                    .frame(width: 34, height: 34)

                Image(systemName: icon)
                    .font(.system(size: headerIconSize, weight: .semibold))
                    .foregroundStyle(accentColor)
            }

            Text(titleText)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)

            Spacer()

            timestampText

            if isButtonContext && hasActionableState {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(secondaryTextColor.opacity(0.55))
            }
        }
    }

    private var stateView: some View {
        switch state {
        case .loading:
            return AnyView(loadingView)
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
                        .foregroundStyle(secondaryTextColor)
                        .transition(.opacity)
                }
            default:
                EmptyView()
            }
        }
    }

    private func dataView(_ content: Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                valueBlock(for: content)

                Spacer(minLength: 12)

                if shouldShowChart(for: content) {
                    chart(for: content)
                        .frame(width: chartWidth, height: chartHeight)
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
                Text(content.value)
                    .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                    .monospacedDigit()
                    .minimumScaleFactor(0.8)

                if !content.unit.isEmpty {
                    Text(content.unit)
                        .font(.system(size: unitFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryTextColor)
                        .padding(.bottom, 4)
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
        Chart {
            ForEach(content.dataPoints) { point in
                LineMark(
                    x: .value("Index", point.index),
                    y: .value("Value", point.value)
                )
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Gradient(colors: [accentColor.opacity(0.35), accentColor]))
                .interpolationMethod(.catmullRom)
            }

            if let last = content.dataPoints.last {
                PointMark(
                    x: .value("Index", last.index),
                    y: .value("Value", last.value)
                )
                .symbolSize(36)
                .foregroundStyle(accentColor)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel(content.chartAccessibilityLabel ?? "Trend chart")
        .accessibilityValue(content.chartAccessibilityValue ?? "Latest value \(content.value) \(content.unit)")
        .accessibilityHidden(dynamicTypeSize.isAccessibilityCategory)
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

    private var loadingView: some View { loadingView() }

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
        return !dynamicTypeSize.isAccessibilityCategory
    }

    private var chartWidth: CGFloat {
        switch dynamicTypeSize {
        case .xSmall, .small, .medium: return 200
        case .large: return 190
        case .xLarge: return 180
        case .xxLarge: return 170
        case .xxxLarge: return 150
        default: return 0 // hidden when in accessibility sizes
        }
    }

    private var backgroundMaterial: some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color.appCard)
        }
        return AnyShapeStyle(.ultraThinMaterial)
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(borderColor, lineWidth: 1)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.55) : Color.black.opacity(0.12)
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

// MARK: - MetricSummaryCard Button Style

struct MetricSummaryCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: configuration.isPressed)
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
            .buttonStyle(MetricSummaryCardButtonStyle())

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
