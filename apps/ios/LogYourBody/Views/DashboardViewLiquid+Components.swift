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
                if shouldShowPhoto {
                    ProgressPhotoCarouselView(
                        currentMetric: metric,
                        historicalMetrics: bodyMetrics,
                        selectedMetricsIndex: $selectedIndex,
                        displayMode: $displayMode
                    )
                    .accessibilityIdentifier("dashboard_home_timeline_photo_stage")
                } else {
                    DashboardHomeTimelineAvatarPlaceholder(
                        bodyFatPercentage: metric.bodyFatPercentage,
                        gender: gender,
                        mode: homeMode
                    )
                    .allowsHitTesting(false)
                }

                timelineGradient(isPhoto: shouldShowPhoto)
                    .allowsHitTesting(false)
            }
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(shouldShowPhoto ? Color.black : Color.clear)
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

    private func timelineGradient(isPhoto: Bool) -> some View {
        LinearGradient(
            colors: isPhoto ? [
                Color.black.opacity(0.62),
                Color.black.opacity(0.05),
                Color.black.opacity(0.86)
            ] : [
                Color.black.opacity(0.34),
                Color.black.opacity(0.00),
                Color.black.opacity(0.38)
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

    private var avatar: AvatarBodyFatCatalog.Match {
        AvatarBodyFatCatalog.match(bodyFatPercentage: bodyFatPercentage, gender: gender)
    }

    private var accessibilityText: String {
        mode == .avatar ? avatar.accessibilityLabel : "\(avatar.accessibilityLabel), photo fallback"
    }

    var body: some View {
        GeometryReader { geometry in
            AvatarBodyRenderer(
                bodyFatPercentage: bodyFatPercentage,
                gender: gender,
                height: geometry.size.height,
                padding: 8,
                verticalPadding: 0,
                horizontalFillScale: 1.04,
                alignment: .bottom
            )
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("dashboard_home_timeline_avatar")
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
