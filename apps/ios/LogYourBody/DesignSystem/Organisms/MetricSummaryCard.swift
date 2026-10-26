//
// MetricSummaryCard.swift
// LogYourBody
//
// Apple Health-inspired metric summary card with full state support
//

import SwiftUI
import Charts

enum MetricCardIdentityPolicy {
    static let gateKey = "metric_card_identity_v1"

    @MainActor
    static func isEnabled(isGateEnabled: ((String) -> Bool)? = nil) -> Bool {
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return checkGate(gateKey)
    }
}

enum MetricCardActionPolicy {
    static let gateKey = "metric_card_actions_v1"

    @MainActor
    static func isEnabled(isGateEnabled: ((String) -> Bool)? = nil) -> Bool {
        let checkGate = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return MetricCardIdentityPolicy.isEnabled(isGateEnabled: checkGate) && checkGate(gateKey)
    }
}

enum MetricCardMotionPolicy {
    static func reducesMotion(systemValue: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        systemValue || arguments.contains("-lybUITestReduceMotion")
        #else
        systemValue
        #endif
    }
}

#if DEBUG
private struct MetricCardIdentityKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private struct MetricCardActionsKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var metricCardIdentity: Bool? {
        get { self[MetricCardIdentityKey.self] }
        set { self[MetricCardIdentityKey.self] = newValue }
    }

    var metricCardActions: Bool? {
        get { self[MetricCardActionsKey.self] }
        set { self[MetricCardActionsKey.self] = newValue }
    }
}
#endif

// MARK: - MetricSummaryCard Organism

/// Apple Health-style metric card with inline chart, states, and accessibility support.
public struct MetricSummaryCard: View {
    public struct DataPoint: Identifiable {
        public let index: Int
        public let value: Double
        public let date: Date?
        public var id: Int { index }

        public init(index: Int, value: Double, date: Date? = nil) {
            self.index = index
            self.value = value
            self.date = date
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

        var accessibilityDescription: String {
            let description: String
            switch direction {
            case .up:
                description = "Up \(valueText)"
            case .down:
                description = "Down \(valueText)"
            case .flat:
                description = valueText.isEmpty || valueText == "No change"
                    ? "No change"
                    : "No change \(valueText)"
            }
            guard let caption, !caption.isEmpty else { return description }
            return "\(description), \(caption)"
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
        public let chartPeriod: String?
        public let chartInterval: ClosedRange<Date>?

        public init(
            title: String,
            value: String,
            unit: String,
            timestamp: String?,
            dataPoints: [DataPoint],
            chartAccessibilityLabel: String?,
            chartAccessibilityValue: String?,
            trend: Trend?,
            footnote: String?,
            chartPeriod: String? = nil,
            chartInterval: ClosedRange<Date>? = nil
        ) {
            self.title = title
            self.value = value
            self.unit = unit
            self.timestamp = timestamp
            self.dataPoints = dataPoints
            self.chartAccessibilityLabel = chartAccessibilityLabel
            self.chartAccessibilityValue = chartAccessibilityValue
            self.trend = trend
            self.footnote = footnote
            self.chartPeriod = chartPeriod
            self.chartInterval = chartInterval
        }
    }

    public struct CardAction {
        public let title: String
        public let hint: String?
        public let handler: () -> Void

        public init(title: String, hint: String? = nil, handler: @escaping () -> Void) {
            self.title = title
            self.hint = hint
            self.handler = handler
        }
    }

    public enum State {
        case loading(title: String)
        case empty(title: String, message: String, action: CardAction?)
        case error(title: String, message: String, action: CardAction?)
        case data(Content)
    }

    public let icon: String
    public let accentColor: Color
    public let state: State
    public let detailAction: CardAction?

    /// The card owns its control. Callers supply navigation here instead of wrapping it in a Button.
    public init(icon: String, accentColor: Color, state: State, detailAction: CardAction? = nil) {
        self.icon = icon
        self.accentColor = accentColor
        self.state = state
        self.detailAction = detailAction
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.theme) private var theme
    #if DEBUG
    @Environment(\.metricCardIdentity) private var identityOverride
    @Environment(\.metricCardActions) private var actionsOverride
    #endif

    private var reduceMotion: Bool {
        MetricCardMotionPolicy.reducesMotion(systemValue: systemReduceMotion)
    }

    private var identityEnabled: Bool {
        #if DEBUG
        if let identityOverride { return identityOverride }
        #endif
        return MetricCardIdentityPolicy.isEnabled()
    }

    private var actionsEnabled: Bool {
        #if DEBUG
        if let actionsOverride { return identityEnabled && actionsOverride }
        #endif
        return MetricCardActionPolicy.isEnabled()
    }

    func primaryAction(actionsEnabled: Bool) -> CardAction? {
        switch state {
        case .loading:
            return nil
        case .data:
            return detailAction
        case .empty(_, _, let action), .error(_, _, let action):
            // The rollback path keeps its legacy inline state button, so it
            // cannot also create a surrounding navigation button.
            return actionsEnabled ? action ?? detailAction : (action == nil ? detailAction : nil)
        }
    }

    func actionHint(actionsEnabled: Bool) -> String? {
        guard let action = primaryAction(actionsEnabled: actionsEnabled) else { return nil }
        return action.hint ?? action.title
    }

    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 44
    @ScaledMetric(relativeTo: .title3) private var unitFontSize: CGFloat = 18
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 60
    @ScaledMetric(relativeTo: .body) private var headerIconSize: CGFloat = 18

    private let horizontalPadding: CGFloat = 16
    private let verticalPadding: CGFloat = 11

    private var isAccessibilityCategory: Bool {
        dynamicTypeSize >= .accessibility1
    }

    public var body: some View {
        if let action = primaryAction(actionsEnabled: actionsEnabled) {
            Button(action: action.handler) {
                cardSurface
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(actionsEnabled ? "\(accessibilityLabel), \(action.title)" : accessibilityLabel)
            .accessibilityHint(actionsEnabled ? actionHint(actionsEnabled: true) ?? "" : accessibilityHint ?? "")
        } else {
            cardSurface
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private var cardSurface: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)

        return VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, horizontalPadding)
                .padding(.top, verticalPadding + 2)

            stateView
                .padding(.horizontal, horizontalPadding)
                .padding(.top, verticalPadding)
                .padding(.bottom, verticalPadding)
        }
        .background(theme.colors.surface, in: shape)
        .overlay {
            shape.stroke(theme.colors.border.opacity(JovieTokens.hairlineOpacity), lineWidth: 1)
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(actionsEnabled ? actionHint(actionsEnabled: true) ?? "" : accessibilityHint ?? "")
        .transaction {
            if actionsEnabled && reduceMotion {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            // Keep the metric accent on the non-text icon, but use the semantic
            // text role for the small label so every metric has a readable
            // foreground independent of its accent hue.
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: headerIconSize, weight: .semibold))
                    .foregroundStyle(accentColor)

                Text(titleText(identityEnabled: identityEnabled))
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
            }

            Spacer()

            // Date (from timestamp) + chevron on the right
            HStack(spacing: 4) {
                timestampText

                if showsDetailChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondaryTextColor)
                }
            }
        }
    }

    private var stateView: some View {
        switch state {
        case .loading:
            return AnyView(loadingView())
        case .empty(_, let message, let action):
            return AnyView(
                messageView(
                    message: message,
                    action: action,
                    iconName: "plus"
                )
            )
        case .error(_, let message, let action):
            return AnyView(
                messageView(
                    message: message,
                    action: action,
                    iconName: "exclamationmark.triangle.fill",
                    isError: true
                )
            )
        case .data(let content):
            return AnyView(dataView(content))
        }
    }

    func titleText(identityEnabled: Bool) -> String {
        switch state {
        case .data(let content):
            return content.title
        case .loading(let title), .empty(let title, _, _), .error(let title, _, _):
            return identityEnabled ? title : "Metric"
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

            // JOV-6090: the trend chip spans the card's full width on its own row,
            // so its label is never squeezed by the value/chart column. At standard
            // text sizes it stays one coherent line; at accessibility sizes the
            // caption may wrap inside the chip rather than clip.
            if let chartPeriod = content.chartPeriod {
                Text(chartPeriod)
                    .font(.footnote)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let trend = content.trend {
                trendView(trend)
            }

            if let footnote = content.footnote, !footnote.isEmpty {
                Text(footnote)
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(content.chartPeriod == nil ? 2 : nil)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func valueBlock(for content: Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if content.unit.isEmpty {
                Text(content.value)
                    .font(.system(size: valueFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                    .monospacedDigit()
                    .tracking(-0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .layoutPriority(2)
            } else {
                // Render value + unit as a single Text so they stay on one line
                // and scale together, preventing vertical stacking of the unit.
                Text("\(Text(content.value).font(.system(size: valueFontSize, weight: .semibold, design: .rounded)).foregroundStyle(primaryTextColor).monospacedDigit().tracking(-0.5)) \(Text(content.unit).font(.system(size: unitFontSize, weight: .medium, design: .rounded)).foregroundStyle(secondaryTextColor))")
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .layoutPriority(2)
            }
        }
    }

    private func trendView(_ trend: Trend) -> some View {
        HStack(spacing: 8) {
            Image(systemName: trendIcon(for: trend.direction))
                .font(.system(size: 12, weight: .bold))

            HStack(spacing: 4) {
                Text(trend.valueText)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))

                if let caption = trend.caption, !caption.isEmpty {
                    Text("· \(caption)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(secondaryTextColor)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(trendBackground(for: trend.direction))
        .cornerRadius(theme.radius.full)
        .foregroundStyle(trendForeground(for: trend.direction))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isStepsContent(_ content: Content) -> Bool {
        content.unit.lowercased() == "steps"
    }

    @ViewBuilder
    private func chart(for content: Content) -> some View {
        if content.chartPeriod != nil {
            observationChart(for: content)
        } else {
            legacyChart(for: content)
        }
    }

    /// Dated observations only. No line claims continuous measurement between sparse samples.
    private func observationChart(for content: Content) -> some View {
        Chart(content.dataPoints) { point in
            if let date = point.date {
                if isStepsContent(content) {
                    BarMark(x: .value("Observation date", date), y: .value("Value", point.value))
                        .foregroundStyle(accentColor)
                } else {
                    PointMark(x: .value("Observation date", date), y: .value("Value", point.value))
                        .foregroundStyle(accentColor)
                }
            }
        }
        .chartXScale(domain: content.chartInterval ?? Date.distantPast...Date())
        .chartYScale(domain: .automatic(includesZero: isStepsContent(content)))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityHidden(true)
    }

    private func legacyChart(for content: Content) -> some View {
        let lineColor = accentColor
        let isSteps = isStepsContent(content)
        let minPoint = content.dataPoints.min(by: { $0.value < $1.value })
        let maxPoint = content.dataPoints.max(by: { $0.value < $1.value })
        let lastIndex = content.dataPoints.map(\.index).max()

        return Chart {
            if isSteps {
                ForEach(content.dataPoints) { point in
                    let isToday = lastIndex != nil && point.index == lastIndex

                    BarMark(
                        x: .value("Index", point.index),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(
                        isToday
                            ? lineColor
                            : lineColor
                    )
                }
            } else {
                ForEach(content.dataPoints) { point in
                    LineMark(
                        x: .value("Index", point.index),
                        y: .value("Value", point.value)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(lineColor)
                    .interpolationMethod(.catmullRom)
                }

                if let last = content.dataPoints.last {
                    PointMark(
                        x: .value("Index", last.index),
                        y: .value("Value", last.value)
                    )
                    .symbolSize(9)
                    .foregroundStyle(lineColor)
                }

                if let minPoint {
                    PointMark(
                        x: .value("Index", minPoint.index),
                        y: .value("Value", minPoint.value)
                    )
                    .symbolSize(6)
                    .foregroundStyle(lineColor)
                }

                if let maxPoint {
                    PointMark(
                        x: .value("Index", maxPoint.index),
                        y: .value("Value", maxPoint.value)
                    )
                    .symbolSize(6)
                    .foregroundStyle(lineColor)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: isSteps))
        .padding(.vertical, 4)
        .accessibilityLabel(content.chartAccessibilityLabel ?? "Trend chart")
        .accessibilityValue(content.chartAccessibilityValue ?? "Latest value \(content.value) \(content.unit)")
        .accessibilityHidden(isAccessibilityCategory)
        .transaction { if reduceMotion { $0.animation = nil } }
    }

    private func loadingView() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            RoundedRectangle(cornerRadius: 8)
                .fill(placeholderColor)
                .frame(width: 140, height: 36)
                .modifier(MetricCardShimmer(enabled: !(actionsEnabled && reduceMotion)))

            RoundedRectangle(cornerRadius: 8)
                .fill(placeholderColor)
                .frame(width: 80, height: 16)
                .modifier(MetricCardShimmer(enabled: !(actionsEnabled && reduceMotion)))

            RoundedRectangle(cornerRadius: 8)
                .fill(placeholderColor)
                .frame(maxWidth: .infinity, minHeight: chartHeight)
                .modifier(MetricCardShimmer(enabled: !(actionsEnabled && reduceMotion)))
        }
    }

    private func messageView(message: String, action: CardAction?, iconName: String, isError: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isError ? theme.colors.error : accentColor)

                Text(message)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(primaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let action = action {
                if actionsEnabled {
                    actionLabel(action, isError: isError)
                } else {
                    Button(action: action.handler) {
                        actionLabel(action, isError: isError)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isError ? "Retry" : "Add data")
                }
            }
        }
    }

    private func actionLabel(_ action: CardAction, isError: Bool) -> some View {
        Text(action.title)
            .font(.system(.callout, design: .rounded).weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(actionBackground(isError: isError))
            .cornerRadius(14)
            .foregroundStyle(isError ? theme.colors.error : accentColor)
    }

    private var showsDetailChevron: Bool {
        guard detailAction != nil else { return false }
        switch state {
        case .data:
            return true
        case .empty(_, _, let action), .error(_, _, let action):
            return action == nil
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

    private var primaryTextColor: Color {
        theme.colors.text
    }

    private var secondaryTextColor: Color {
        theme.colors.textSecondary
    }

    private var placeholderColor: Color {
        theme.colors.text.opacity(0.12)
    }

    private func trendIcon(for direction: Trend.Direction) -> String {
        switch direction {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .flat: return "arrow.right"
        }
    }

    private func trendBackground(for direction: Trend.Direction) -> Color {
        if MetricStatsTruthPolicy.isEnabled() {
            return secondaryTextColor.opacity(0.15)
        }
        switch direction {
        case .up:
            return theme.colors.success.opacity(0.15)
        case .down:
            return theme.colors.error.opacity(0.15)
        case .flat:
            return secondaryTextColor.opacity(0.15)
        }
    }

    private func trendForeground(for direction: Trend.Direction) -> Color {
        if MetricStatsTruthPolicy.isEnabled() {
            return secondaryTextColor
        }
        switch direction {
        case .up:
            return theme.colors.success
        case .down:
            return theme.colors.error
        case .flat:
            return secondaryTextColor
        }
    }

    private func actionBackground(isError: Bool) -> some ShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle((isError ? theme.colors.error : accentColor).opacity(0.12))
        }
        return AnyShapeStyle((isError ? theme.colors.error : accentColor).opacity(0.08))
    }

    private var accessibilityLabel: String {
        accessibilityLabel(identityEnabled: identityEnabled)
    }

    func accessibilityLabel(identityEnabled: Bool) -> String {
        switch state {
        case .loading(let title):
            return identityEnabled ? "Loading \(title)" : "Loading metric"
        case .empty(let title, let message, _):
            return identityEnabled ? "\(title), \(message)" : "No data"
        case .error(let title, let message, _):
            return identityEnabled ? "\(title), \(message)" : "Metric unavailable"
        case .data(let content):
            var components: [String] = [content.title, content.value + (content.unit.isEmpty ? "" : " " + content.unit)]
            if let trend = content.trend {
                components.append(trend.accessibilityDescription)
            }
            if let timestamp = content.timestamp {
                components.append("Updated \(timestamp)")
            }
            if identityEnabled || content.chartPeriod != nil {
                for detail in [content.chartAccessibilityLabel, content.chartAccessibilityValue, content.footnote] {
                    if let detail, !detail.isEmpty, !components.contains(detail) { components.append(detail) }
                }
            }
            return components.joined(separator: ", ")
        }
    }

    private var accessibilityHint: String? {
        switch state {
        case .loading:
            return ""
        case .empty(_, _, let action):
            return action == nil ? nil : "Double tap to add data"
        case .error(_, _, let action):
            return action == nil ? nil : "Double tap to retry"
        case .data:
            return detailAction != nil ? "Double tap for details" : nil
        }
    }
}

// MARK: - Metric Card Button Style

private struct MetricCardShimmer: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.shimmer()
        } else {
            content
        }
    }
}

struct MetricCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool {
        MetricCardMotionPolicy.reducesMotion(systemValue: systemReduceMotion)
    }

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Deterministic metric state fixture

#if DEBUG
/// Uses the production card and its native Button; handlers produce observable state/navigation.
struct MetricCardFixtureView: View {
    private let metrics = ["Steps", "Weight", "Body Fat", "FFMI"]
    @State private var order = DashboardViewLiquid.MetricIdentifier.allCases
    @State private var draggedMetric: DashboardViewLiquid.MetricIdentifier?
    @State private var dropTargetMetric: DashboardViewLiquid.MetricIdentifier?
    @State private var selectedState = "loading"
    @State private var completed: Set<String> = []
    @State private var invocations: [String: Int] = [:]
    @State private var detail: String?
    private let arguments = ProcessInfo.processInfo.arguments

    var body: some View {
        NavigationStack {
            ScrollView {
                DashboardMetricsList(
                    metricsOrder: $order, draggedMetric: $draggedMetric,
                    dropTargetMetric: $dropTargetMetric, onReorder: {},
                    cardContent: { metric in
                        metricCard(for: metric)
                    }
                )
                .padding(20)
            }
            .safeAreaInset(edge: .top) {
                VStack {
                    HStack {
                        stateButton("loading")
                        stateButton("empty")
                        stateButton("error")
                    }
                    HStack {
                        stateButton("permission")
                        stateButton("data")
                        stateButton("unavailable")
                    }
                    ForEach(metrics, id: \.self) { title in
                        Text("\(title) calls: \(invocations[title, default: 0])")
                            .font(.caption2)
                            .accessibilityIdentifier("metric_fixture_calls_\(title)")
                    }
                }
                .font(.caption)
                .padding(8)
                .background(Color.appBackground)
            }
            .navigationDestination(item: $detail) { title in
                Text("\(title) details")
                    .accessibilityIdentifier("metric_fixture_detail")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func metricCard(for metric: DashboardViewLiquid.MetricIdentifier) -> some View {
        let title = metric == .bodyFat ? "Body Fat" : metric == .ffmi ? "FFMI" : metric.rawValue.capitalized
        return MetricSummaryCard(
            icon: "chart.xyaxis.line", accentColor: Color.appPrimary,
            state: state(for: title), detailAction: detailAction(for: title)
        )
        .buttonStyle(MetricCardButtonStyle())
        .environment(\.metricCardIdentity, !arguments.contains("-lybUITestMetricCardLegacy"))
        .environment(\.metricCardActions, !arguments.contains("-lybUITestMetricCardLegacy"))
        .environment(\.dynamicTypeSize, arguments.contains("-lybUITestMetricCardAX3") ? .accessibility3 : .large)
        .accessibilityIdentifier("metric_fixture_\(title)")
    }

    private func stateButton(_ name: String) -> some View {
        Button(name.capitalized) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedState = name
                completed = []
                invocations = [:]
            }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("metric_fixture_state_\(name)")
    }

    private func state(for title: String) -> MetricSummaryCard.State {
        let actionTitle = selectedState == "error" ? "Retry"
            : selectedState == "permission" ? "Review Health access" : "Add measurement"
        let action = MetricSummaryCard.CardAction(
            title: actionTitle,
            hint: selectedState == "permission" ? "Shows Health access details" : nil
        ) {
            invocations[title, default: 0] += 1
            if selectedState == "permission" {
                detail = "\(title) Health access"
            } else {
                completed.insert(title)
            }
        }
        if completed.contains(title) || selectedState == "data" {
            let unit = title == "Steps" ? "steps" : title == "Weight" ? "kg" : title == "Body Fat" ? "%" : ""
            let value = title == "Steps" ? "8,000" : title == "Weight" ? "80" : title == "Body Fat" ? "18" : "20"
            let reading = Double(value.replacingOccurrences(of: ",", with: "")) ?? 0
            return .data(.init(
                title: title, value: value, unit: unit, timestamp: "October 25 at 08:00",
                dataPoints: [.init(index: 0, value: reading), .init(index: 1, value: reading)],
                chartAccessibilityLabel: "\(title) history, last 30 days",
                chartAccessibilityValue: "Latest value \(value) \(unit)",
                trend: .init(direction: .flat, valueText: "No change", caption: "1M"),
                footnote: title == "FFMI" ? "Calculated from weight, body fat and height" : "Source: Apple Health"
            ))
        }
        switch selectedState {
        case "empty":
            return .empty(title: title, message: "No measurements yet", action: action)
        case "error":
            return .error(title: title, message: "Unable to load measurements", action: action)
        case "permission":
            return .empty(title: title, message: "Health access needed", action: action)
        case "unavailable":
            return .error(title: title, message: "Measurements unavailable", action: nil)
        default:
            return .loading(title: title)
        }
    }

    private func detailAction(for title: String) -> MetricSummaryCard.CardAction? {
        guard selectedState != "unavailable" else { return nil }
        return .init(title: "Show \(title) details") {
            invocations[title, default: 0] += 1
            detail = title
        }
    }
}

#Preview("Metric state actions") {
    MetricCardFixtureView()
}
#endif
