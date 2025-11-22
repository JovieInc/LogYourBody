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
    let header: () -> Header
    let syncBanner: () -> SyncBanner
    let metricContent: () -> MetricContent
    let quickActions: () -> QuickActions
    let onRefresh: () async -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header()
                    .padding(.horizontal, 20)

                syncBanner()
                    .padding(.horizontal, 20)

                metricContent()

                quickActions()
                Spacer(minLength: 160)
            }
            .padding(.top, 8)
        }
        .refreshable {
            await onRefresh()
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header()
                    .padding(.horizontal, 20)

                syncBanner()
                    .padding(.horizontal, 20)

                titleBlock()

                metricsContent()

                Spacer(minLength: 160)
            }
            .padding(.top, 8)
        }
        .refreshable {
            await onRefresh()
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

// MARK: - Bottom Tab Bar

struct DashboardBottomTabBar: View {
    @Binding var selectedTab: DashboardViewLiquid.DashboardTab

    var body: some View {
        LiquidGlassCard(
            cornerRadius: 24,
            blurRadius: 24,
            padding: 3,
            showShadow: false,
            showHighlight: true
        ) {
            HStack(spacing: 4) {
                tabButton(
                    tab: .home,
                    icon: "house.fill",
                    title: "Home"
                )
                tabButton(
                    tab: .metrics,
                    icon: "chart.bar.fill",
                    title: "Metrics"
                )
            }
        }
    }

    private func tabButton(
        tab: DashboardViewLiquid.DashboardTab,
        icon: String,
        title: String
    ) -> some View {
        let isSelected = selectedTab == tab

        return Button(
            action: {
                guard selectedTab != tab else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    selectedTab = tab
                }
            },
            label: {
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(
                            isSelected ?
                                Color.white :
                                Color.white.opacity(0.65)
                        )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            isSelected ?
                                Color.white.opacity(0.18) :
                                Color.white.opacity(0.06)
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(isSelected ? 0.25 : 0.10),
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
            }
        )
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Lazy Tab Loader

struct LazyTabView<Content: View>: View {
    @Binding var selectedTab: DashboardViewLiquid.DashboardTab
    var tab: DashboardViewLiquid.DashboardTab = .home
    let content: () -> Content

    var body: some View {
        if selectedTab == tab {
            content()
        } else {
            Color.clear
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
                        footnote: nil
                    )),
                    isButtonContext: true
                )
            }
            .buttonStyle(PlainButtonStyle())

        case .weight:
            if let currentMetric {
                let stats = weightRangeStats()
                ZStack(alignment: .topTrailing) {
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
                            footnote: stats.map { formatAverageFootnote($0.average, weightUnit) }
                        )),
                        isButtonContext: true
                    )

                    Button {
                        weightUsesTrend.toggle()
                    } label: {
                        Text(weightUsesTrend ? "Trend" : "Raw")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.metricTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                    .padding(.trailing, 12)
                    .accessibilityLabel("Toggle weight display mode")
                    .accessibilityHint("Switch between trend and raw weight")
                }
                .onTapGesture {
                    selectedMetricType = .weight
                    isMetricDetailActive = true
                }
            }

        case .bodyFat:
            if let currentMetric {
                let stats = bodyFatRangeStats()
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
                            footnote: stats.map { formatAverageFootnote($0.average, "%") }
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

        case .ffmi:
            if let currentMetric {
                let stats = ffmiRangeStats()
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
                            footnote: stats.map { formatAverageFootnote($0.average, "") }
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
