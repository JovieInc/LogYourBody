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

// MARK: - Hero Section

struct DashboardHeroSection<HeroCard: View, StepsCard: View>: View {
    let metric: BodyMetrics?
    let heroCard: (BodyMetrics) -> HeroCard
    let stepsCard: () -> StepsCard

    var body: some View {
        Group {
            if let metric {
                VStack(spacing: 16) {
                    heroCard(metric)
                    stepsCard()
                }
                .padding(.horizontal, 20)
            }
        }
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
        max(headerStackHeight, 64 + safeAreaTop)
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
            .padding(.top, safeAreaTop + 8)
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
                        .ultraThinMaterial
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

        case .weight:
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

        case .bodyFat:
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

        case .ffmi:
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
