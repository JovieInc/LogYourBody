import SwiftUI

// MARK: - Timeline Scrubber Component

struct DashboardTimelineScrubber: View {
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    @Binding var timelineMode: TimelineMode

    var body: some View {
        Group {
            if bodyMetrics.count > 1 {
                ProgressTimelineView(
                    bodyMetrics: bodyMetrics,
                    selectedIndex: $selectedIndex,
                    mode: $timelineMode
                )
                .frame(height: 80)
            }
        }
    }
}

// MARK: - Empty State

struct DashboardEmptyStateLiquid: View {
    let onAddEntry: () -> Void

    var body: some View {
        DashboardEmptyStateView(
            icon: "figure.stand",
            title: "Start tracking your progress",
            message: "Add your first entry to unlock trends, charts, and insights.",
            action: onAddEntry
        )
    }
}

struct DashboardHomeTimelineHero: View {
    let metric: BodyMetrics
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    @Binding var displayMode: DashboardDisplayMode

    let homeMode: DefaultHomeMode
    let dateText: String
    let gender: String?
    let bodyScoreText: String
    let bodyScoreTagline: String
    let bodyScoreDeltaText: String?
    let weightValue: String
    let weightCaption: String
    let bodyFatValue: String
    let bodyFatCaption: String
    let ffmiValue: String
    let ffmiCaption: String
    let onTapBodyScore: (() -> Void)?
    let onTapWeight: () -> Void
    let onTapBodyFat: () -> Void
    let onTapFFMI: () -> Void

    private var hasUsablePhoto: Bool {
        PhotoTimelineHUDPolicy.hasUsablePhoto(metric)
    }

    private var shouldShowPhoto: Bool {
        homeMode == .photo && hasUsablePhoto
    }

    private var timelinePositionText: String {
        guard !bodyMetrics.isEmpty else { return "0 / 0" }
        let clampedIndex = min(max(selectedIndex, 0), bodyMetrics.count - 1)
        return "\(clampedIndex + 1) / \(bodyMetrics.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                ProgressPhotoCarouselView(
                    currentMetric: metric,
                    historicalMetrics: bodyMetrics,
                    selectedMetricsIndex: $selectedIndex,
                    displayMode: $displayMode
                )

                if !shouldShowPhoto {
                    DashboardHomeTimelineAvatarPlaceholder(
                        bodyFatPercentage: metric.bodyFatPercentage,
                        gender: gender,
                        mode: homeMode
                    )
                    .allowsHitTesting(false)
                }

                timelineGradient
                    .allowsHitTesting(false)
            }
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipped()
            .overlay(alignment: .top) {
                timelineDateBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }

            timelineMetricsHUD
                .padding(.horizontal, 20)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Progress timeline, \(dateText)")
        .accessibilityIdentifier("dashboard_home_timeline_hero")
    }

    private var timelineGradient: some View {
        LinearGradient(
            colors: [
                Color.black.opacity(0.62),
                Color.black.opacity(0.05),
                Color.black.opacity(0.86)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var timelineDateBar: some View {
        HStack(spacing: 10) {
            Text(dateText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.black.opacity(0.42)))

            Spacer(minLength: 0)

            Text(timelinePositionText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(Color.white.opacity(0.72))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.34)))
        }
    }

    private var timelineMetricsHUD: some View {
        VStack(alignment: .leading, spacing: 14) {
            bodyScoreSummary

            HStack(alignment: .top, spacing: 0) {
                DashboardHomeTimelineMetricButton(
                    title: "Weight",
                    value: weightValue,
                    caption: weightCaption,
                    color: Color.metricAccentWeight,
                    action: onTapWeight
                )

                metricDivider

                DashboardHomeTimelineMetricButton(
                    title: "Body Fat",
                    value: bodyFatValue,
                    caption: bodyFatCaption,
                    color: Color.metricAccentBodyFat,
                    action: onTapBodyFat
                )

                metricDivider

                DashboardHomeTimelineMetricButton(
                    title: "FFMI",
                    value: ffmiValue,
                    caption: ffmiCaption,
                    color: Color.metricAccentFFMI,
                    action: onTapFFMI
                )
            }
        }
    }

    @ViewBuilder
    private var bodyScoreSummary: some View {
        if let onTapBodyScore {
            Button(action: onTapBodyScore) {
                bodyScoreContent
            }
            .buttonStyle(.plain)
        } else {
            bodyScoreContent
        }
    }

    private var bodyScoreContent: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(bodyScoreText)
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            VStack(alignment: .leading, spacing: 4) {
                Text("Body Score")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.66))
                    .textCase(.uppercase)

                Text(bodyScoreTagline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let bodyScoreDeltaText {
                    Text(bodyScoreDeltaText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Body Score \(bodyScoreText), \(bodyScoreTagline)")
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 10)
    }
}

private struct DashboardHomeTimelineMetricButton: View {
    let title: String
    let value: String
    let caption: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Rectangle()
                    .fill(color)
                    .frame(width: 28, height: 2)
                    .cornerRadius(1)

                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.62))
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value), \(caption)")
    }
}

private struct DashboardHomeTimelineAvatarPlaceholder: View {
    let bodyFatPercentage: Double?
    let gender: String?
    let mode: DefaultHomeMode

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black

                LinearGradient(
                    colors: [
                        Color.metricAccent.opacity(0.22),
                        Color.black.opacity(0.15),
                        Color.metricAccentBodyFat.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                timelineGrid

                if let bodyFatPercentage {
                    DashboardHomeTimelineSilhouette(
                        bodyFatPercentage: bodyFatPercentage,
                        gender: gender ?? "male"
                    )
                    .stroke(Color.white.opacity(0.64), lineWidth: 2)
                    .frame(
                        width: min(geometry.size.width * 0.62, 260),
                        height: geometry.size.height * 0.58
                    )
                    .shadow(color: Color.metricAccent.opacity(0.35), radius: 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -geometry.size.height * 0.04)
                } else {
                    Image(systemName: "figure.stand")
                        .font(.system(size: min(geometry.size.width * 0.24, 92), weight: .thin))
                        .foregroundColor(Color.white.opacity(0.56))
                        .shadow(color: Color.metricAccent.opacity(0.34), radius: 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: -geometry.size.height * 0.04)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(mode == .avatar ? "Avatar mode" : "Metrics only")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.82))
                        .textCase(.uppercase)

                    Text(mode == .avatar ? "Private body timeline" : "Private avatar fallback")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.58))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.top, geometry.size.height * 0.24)
            }
        }
    }

    private var timelineGrid: some View {
        GeometryReader { geometry in
            Path { path in
                let horizontalSpacing: CGFloat = 34
                let verticalSpacing: CGFloat = 40

                stride(from: CGFloat(0), through: geometry.size.width, by: horizontalSpacing).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }

                stride(from: CGFloat(0), through: geometry.size.height, by: verticalSpacing).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.045), lineWidth: 1)
        }
    }
}

private struct DashboardHomeTimelineSilhouette: Shape {
    let bodyFatPercentage: Double
    let gender: String

    func path(in rect: CGRect) -> Path {
        let proportions = proportions(for: bodyFatPercentage, gender: gender)
        let centerX = rect.midX
        let width = rect.width * 0.68
        let headTop = rect.minY + rect.height * 0.05
        let headHeight = rect.height * 0.14
        let neckTop = headTop + headHeight
        let shoulderTop = neckTop + rect.height * 0.06
        let chestMid = shoulderTop + rect.height * 0.16
        let waistTop = shoulderTop + rect.height * 0.32
        let hipTop = waistTop + rect.height * 0.12
        let bottom = rect.maxY - rect.height * 0.06
        let headRadius = width * 0.12
        let shoulderX = width * proportions.shoulder / 2
        let waistX = width * proportions.waist / 2
        let hipX = width * proportions.hip / 2
        let neckX = width * 0.11
        let armReach = width * 0.16

        var path = Path()

        path.addEllipse(in: CGRect(
            x: centerX - headRadius,
            y: headTop,
            width: headRadius * 2,
            height: headHeight
        ))

        path.move(to: CGPoint(x: centerX - neckX, y: neckTop))
        path.addLine(to: CGPoint(x: centerX - neckX, y: shoulderTop))
        path.move(to: CGPoint(x: centerX + neckX, y: neckTop))
        path.addLine(to: CGPoint(x: centerX + neckX, y: shoulderTop))

        path.move(to: CGPoint(x: centerX - shoulderX, y: shoulderTop))
        path.addCurve(
            to: CGPoint(x: centerX - waistX, y: waistTop),
            control1: CGPoint(x: centerX - shoulderX, y: chestMid),
            control2: CGPoint(x: centerX - waistX, y: chestMid)
        )

        path.move(to: CGPoint(x: centerX + shoulderX, y: shoulderTop))
        path.addCurve(
            to: CGPoint(x: centerX + waistX, y: waistTop),
            control1: CGPoint(x: centerX + shoulderX, y: chestMid),
            control2: CGPoint(x: centerX + waistX, y: chestMid)
        )

        path.move(to: CGPoint(x: centerX - waistX, y: waistTop))
        path.addLine(to: CGPoint(x: centerX - hipX, y: hipTop))
        path.addLine(to: CGPoint(x: centerX - hipX * 0.72, y: bottom))

        path.move(to: CGPoint(x: centerX + waistX, y: waistTop))
        path.addLine(to: CGPoint(x: centerX + hipX, y: hipTop))
        path.addLine(to: CGPoint(x: centerX + hipX * 0.72, y: bottom))

        path.move(to: CGPoint(x: centerX - shoulderX, y: shoulderTop))
        path.addLine(to: CGPoint(x: centerX - shoulderX - armReach, y: waistTop))

        path.move(to: CGPoint(x: centerX + shoulderX, y: shoulderTop))
        path.addLine(to: CGPoint(x: centerX + shoulderX + armReach, y: waistTop))

        return path
    }

    private func proportions(
        for bodyFatPercentage: Double,
        gender: String
    ) -> (shoulder: CGFloat, waist: CGFloat, hip: CGFloat) {
        let lower: Double
        let upper: Double
        let normalizedGender = gender.lowercased()
        let isFemale = normalizedGender.contains("female") || normalizedGender.contains("woman")

        if isFemale {
            lower = 15
            upper = 32
        } else {
            lower = 10
            upper = 28
        }

        let ratio = CGFloat(min(max((bodyFatPercentage - lower) / (upper - lower), 0), 1))

        if isFemale {
            return (
                shoulder: 0.74 - ratio * 0.08,
                waist: 0.58 + ratio * 0.24,
                hip: 0.76 + ratio * 0.10
            )
        }

        return (
            shoulder: 0.94 - ratio * 0.14,
            waist: 0.60 + ratio * 0.27,
            hip: 0.66 + ratio * 0.14
        )
    }
}

// MARK: - Home / Photos / Metrics Tabs

struct DashboardHomeTab<Header: View, SyncBanner: View, MetricContent: View, QuickActions: View>: View {
    let header: (CGFloat) -> Header
    let syncBanner: () -> SyncBanner
    let metricContent: () -> MetricContent
    let quickActions: () -> QuickActions
    let onRefresh: () async -> Void

    @State private var scrollOffset: CGFloat = 0
    @State private var headerStackHeight: CGFloat = 0

    private var scrollProgress: CGFloat {
        let rawOffset = -scrollOffset
        let threshold: CGFloat = 12
        let span: CGFloat = 40

        guard rawOffset > threshold else { return 0 }
        let adjusted = min((rawOffset - threshold) / span, 1)
        return max(adjusted, 0)
    }

    private var headerHeight: CGFloat {
        max(headerStackHeight, 64)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    metricContent()

                    quickActions()
                    Spacer(minLength: 160)
                }
                .padding(.top, headerHeight + 16)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("dashboardHomeScroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "dashboardHomeScroll")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                scrollOffset = value
            }
            .refreshable {
                await onRefresh()
            }

            VStack(spacing: 16) {
                header(scrollProgress)
                syncBanner()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear {
                            headerStackHeight = geo.size.height
                        }
                        .onChange(of: geo.size.height) { newValue in
                            headerStackHeight = newValue
                        }
                }
            )
            .background(
                Color.black.opacity(0.9)
                    .ignoresSafeArea(edges: .top)
                    .overlay(
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.2 * scrollProgress)
                            .ignoresSafeArea(edges: .top)
                    )
            )
            .shadow(
                color: Color.black.opacity(0.18 * scrollProgress),
                radius: 18,
                x: 0,
                y: 10
            )
        }
    }
}

struct DashboardPhotosTab<Header: View, SyncBanner: View, PhotosContent: View>: View {
    let header: () -> Header
    let syncBanner: () -> SyncBanner
    let photosContent: () -> PhotosContent
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header()
                    .padding(.horizontal, 20)

                syncBanner()
                    .padding(.horizontal, 20)

                photosContent()

                Spacer(minLength: 160)
            }
            .padding(.top, 8)
        }
        .refreshable {
            await onRefresh()
        }
    }
}

struct DashboardMetricsTab<Header: View, SyncBanner: View, TitleBlock: View, MetricsContent: View>: View {
    let header: () -> Header
    let syncBanner: () -> SyncBanner
    let titleBlock: () -> TitleBlock
    let metricsContent: () -> MetricsContent
    let onRefresh: () async -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                header()
                syncBanner()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    titleBlock()

                    metricsContent()

                    Spacer(minLength: 160)
                }
                .padding(.top, 16)
            }
            .refreshable {
                await onRefresh()
            }
        }
    }
}

// MARK: - Steps Card

struct DashboardStepsCard<ProgressView: View>: View {
    let formattedSteps: String
    let formattedGoal: String
    let subtext: String
    let progressView: () -> ProgressView
    let onTap: (() -> Void)?

    var body: some View {
        LiquidGlassCard(
            cornerRadius: 24,
            blurRadius: 20,
            padding: 14,
            showShadow: false,
            showHighlight: false
        ) {
            Group {
                if let onTap {
                    Button(action: onTap) {
                        cardContent
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    cardContent
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Steps: " + formattedSteps + " of " + formattedGoal)
        .accessibilityHint(subtext)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.7))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedSteps)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Text("/" + formattedGoal)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.65))

                Spacer()
            }

            progressView()
                .frame(height: 6)

            Text(subtext)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.white.opacity(0.65))
        }
    }
}

// MARK: - Metrics Section Wrapper

struct DashboardMetricsSection: View {
    typealias MetricIdentifier = DashboardViewLiquid.MetricIdentifier

    @Binding var metricsOrder: [MetricIdentifier]
    @Binding var draggedMetric: MetricIdentifier?
    let onReorder: () -> Void

    @State private var dropTargetMetric: MetricIdentifier?

    @Binding var selectedRange: TimeRange
    @Binding var selectedMetricType: DashboardViewLiquid.MetricType
    @Binding var isMetricDetailActive: Bool

    let currentMetric: BodyMetrics?
    let bodyMetrics: [BodyMetrics]
    let dailyMetrics: DailyMetrics?
    let weightUnit: String
    let stepsGoalText: String?
    let weightGoalText: String?
    let bodyFatGoalText: String?
    let ffmiGoalText: String?

    let generateStepsChartData: () -> [MetricDataPoint]
    let generateWeightChartData: () -> [MetricDataPoint]
    let generateBodyFatChartData: () -> [MetricDataPoint]
    let generateFFMIChartData: () -> [MetricDataPoint]

    let weightRangeStats: () -> MetricRangeStats?
    let bodyFatRangeStats: () -> MetricRangeStats?
    let ffmiRangeStats: () -> MetricRangeStats?

    let formatSteps: (Int?) -> String
    let formatWeightValue: (Double?) -> String
    let formatBodyFatValue: (Double?) -> String
    let formatFFMIValue: (BodyMetrics) -> String

    let makeTrend: (Double, String, TimeRange) -> MetricSummaryCard.Trend?
    let formatAverageFootnote: (Double, String) -> String
    let formatCardDateOnly: (Date?) -> String?
    let formatCardDate: (Date) -> String
    let latestStepsSnapshot: () -> (value: Int?, date: Date?)

    @Binding var weightUsesTrend: Bool
    let formatTrendWeightHeadline: (BodyMetrics, Bool) -> String

    var body: some View {
        DashboardMetricsList(
            metricsOrder: $metricsOrder,
            draggedMetric: $draggedMetric,
            dropTargetMetric: $dropTargetMetric,
            onReorder: onReorder,
            cardContent: { metric in
                metricCardView(for: metric)
            }
        )
    }

    @ViewBuilder
    private func metricCardView(for metric: MetricIdentifier) -> some View {
        switch metric {
        case .steps:
            stepsMetricCard()

        case .weight:
            weightMetricCard()

        case .bodyFat:
            bodyFatMetricCard()

        case .ffmi:
            ffmiMetricCard()
        }
    }

    // MARK: - Metric Card Builders

    @ViewBuilder
    private func stepsMetricCard() -> some View {
        Button {
            selectedMetricType = .steps
            isMetricDetailActive = true
        } label: {
            let latestSteps = latestStepsSnapshot()

            MetricSummaryCard(
                icon: "flame.fill",
                accentColor: Color.metricAccentSteps,
                state: .data(MetricSummaryCard.Content(
                    title: "Steps",
                    value: formatSteps(latestSteps.value),
                    unit: "steps",
                    timestamp: formatCardDateOnly(latestSteps.date),
                    dataPoints: generateStepsChartData().map { point in
                        MetricSummaryCard.DataPoint(index: point.index, value: point.value)
                    },
                    chartAccessibilityLabel: "Steps trend for the past week",
                    chartAccessibilityValue: "Latest value \(formatSteps(latestSteps.value)) steps",
                    trend: nil,
                    footnote: stepsGoalText
                )),
                isButtonContext: true
            )
        }
        .buttonStyle(MetricCardButtonStyle())
    }

    @ViewBuilder
    private func weightMetricCard() -> some View {
        if let currentMetric {
            let stats = weightRangeStats()
            let averageText = stats.map { formatAverageFootnote($0.average, weightUnit) }
            Button {
                selectedMetricType = .weight
                isMetricDetailActive = true
            } label: {
                MetricSummaryCard(
                    icon: "figure.stand",
                    accentColor: Color.metricAccentWeight,
                    state: .data(MetricSummaryCard.Content(
                        title: "Weight",
                        value: formatTrendWeightHeadline(currentMetric, weightUsesTrend),
                        unit: weightUnit,
                        timestamp: formatCardDate(currentMetric.date),
                        dataPoints: generateWeightChartData().map { point in
                            MetricSummaryCard.DataPoint(index: point.index, value: point.value)
                        },
                        chartAccessibilityLabel: "Weight trend for the past week",
                        chartAccessibilityValue: "Latest value \(formatTrendWeightHeadline(currentMetric, weightUsesTrend)) \(weightUnit)",
                        trend: stats.flatMap { makeTrend($0.delta, weightUnit, selectedRange) },
                        footnote: combinedAverageAndGoal(averageText, weightGoalText)
                    )),
                    isButtonContext: true
                )
            }
            .buttonStyle(MetricCardButtonStyle())
        }
    }

    @ViewBuilder
    private func bodyFatMetricCard() -> some View {
        if let currentMetric {
            let stats = bodyFatRangeStats()
            let averageText = stats.map { formatAverageFootnote($0.average, "%") }
            Button {
                selectedMetricType = .bodyFat
                isMetricDetailActive = true
            } label: {
                MetricSummaryCard(
                    icon: "percent",
                    accentColor: Color.metricAccentBodyFat,
                    state: .data(MetricSummaryCard.Content(
                        title: "Body Fat %",
                        value: formatBodyFatValue(currentMetric.bodyFatPercentage),
                        unit: "%",
                        timestamp: formatCardDate(currentMetric.date),
                        dataPoints: generateBodyFatChartData().map { point in
                            MetricSummaryCard.DataPoint(index: point.index, value: point.value)
                        },
                        chartAccessibilityLabel: "Body fat percentage trend for the past week",
                        chartAccessibilityValue: "Latest value \(formatBodyFatValue(currentMetric.bodyFatPercentage))%",
                        trend: stats.flatMap { makeTrend($0.delta, "%", selectedRange) },
                        footnote: combinedAverageAndGoal(averageText, bodyFatGoalText)
                    )),
                    isButtonContext: true
                )
            }
            .buttonStyle(MetricCardButtonStyle())
        }
    }

    @ViewBuilder
    private func ffmiMetricCard() -> some View {
        if let currentMetric {
            let stats = ffmiRangeStats()
            let averageText = stats.map { formatAverageFootnote($0.average, "") }
            Button {
                selectedMetricType = .ffmi
                isMetricDetailActive = true
            } label: {
                MetricSummaryCard(
                    icon: "figure.arms.open",
                    accentColor: Color.metricAccentFFMI,
                    state: .data(MetricSummaryCard.Content(
                        title: "FFMI",
                        value: formatFFMIValue(currentMetric),
                        unit: "FFMI",
                        timestamp: formatCardDate(currentMetric.date),
                        dataPoints: generateFFMIChartData().map { point in
                            MetricSummaryCard.DataPoint(index: point.index, value: point.value)
                        },
                        chartAccessibilityLabel: "FFMI trend for the past week",
                        chartAccessibilityValue: "Latest value \(formatFFMIValue(currentMetric))",
                        trend: stats.flatMap { makeTrend($0.delta, "", selectedRange) },
                        footnote: combinedAverageAndGoal(averageText, ffmiGoalText)
                    )),
                    isButtonContext: true
                )
            }
            .buttonStyle(MetricCardButtonStyle())
        }
    }
}

private func combinedAverageAndGoal(_ averageText: String?, _ goalText: String?) -> String? {
    switch (averageText, goalText) {
    case let (avg?, goal?):
        return "\(avg) · \(goal)"
    case let (avg?, nil):
        return avg
    case let (nil, goal?):
        return goal
    default:
        return nil
    }
}

// MARK: - GLP-1 Metric Card

extension DashboardViewLiquid {
    @ViewBuilder
    var glp1MetricCard: some View {
        let sortedLogs = glp1DoseLogs.sorted { $0.takenAt < $1.takenAt }

        if let latestLog = sortedLogs.last,
           let latestDose = latestLog.doseAmount {
            let unit = latestLog.doseUnit ?? "mg"
            let dataPoints: [MetricSummaryCard.DataPoint] = Array(sortedLogs.suffix(7))
                .enumerated()
                .compactMap { index, log in
                    guard let value = log.doseAmount else { return nil }
                    return MetricSummaryCard.DataPoint(index: index, value: value)
                }

            Button {
                selectedMetricType = .glp1
                isMetricDetailActive = true
            } label: {
                MetricSummaryCard(
                    icon: "syringe",
                    accentColor: Color.metricAccent,
                    state: .data(
                        MetricSummaryCard.Content(
                            title: "GLP-1 Dose",
                            value: String(format: "%.1f", latestDose),
                            unit: unit,
                            timestamp: formatCardDateOnly(latestLog.takenAt),
                            dataPoints: dataPoints,
                            chartAccessibilityLabel: "GLP-1 dose history",
                            chartAccessibilityValue: "Latest dose \(String(format: "%.1f", latestDose)) \(unit)",
                            trend: nil,
                            footnote: nil
                        )
                    ),
                    isButtonContext: true
                )
            }
            .buttonStyle(MetricCardButtonStyle())
        } else {
            EmptyView()
        }
    }
}
