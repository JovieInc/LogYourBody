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
                .accessibilityIdentifier("dashboard_timeline_scrubber")
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
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var bodyScoreFontSize: CGFloat = 50

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
    let onShareBodyScore: (() -> Void)?

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

                if shouldShowPhoto {
                    timelineGradient
                        .allowsHitTesting(false)
                }
            }
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(theme.colors.background)
            .clipped()
            .overlay(alignment: .top) {
                timelineDateBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
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
                theme.colors.background.opacity(0.62),
                theme.colors.background.opacity(0.05),
                theme.colors.background.opacity(0.86)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var timelineDateBar: some View {
        HStack(spacing: 10) {
            Text(dateText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(theme.colors.text)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(theme.colors.background.opacity(0.42)))
                .allowsHitTesting(false)

            Spacer(minLength: 0)

            if let onShareBodyScore {
                Button {
                    onShareBodyScore()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(theme.colors.text)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.colors.background.opacity(0.42)))
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .buttonStyle(.plain)
                .accessibilityLabel("Share Body Score")
                .accessibilityHint("Opens sharing options for this Body Score")
                .accessibilityIdentifier("body_score_hero_share_button")
            }

            Text(timelinePositionText)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundColor(theme.colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(theme.colors.background.opacity(0.34)))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var timelineMetricsHUD: some View {
        VStack(alignment: .leading, spacing: 14) {
            bodyScoreSummary

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    timelineMetricButton(
                        title: "Weight",
                        value: weightValue,
                        caption: weightCaption,
                        color: theme.colors.accentViolet,
                        action: onTapWeight
                    )

                    horizontalMetricDivider

                    timelineMetricButton(
                        title: "Body Fat",
                        value: bodyFatValue,
                        caption: bodyFatCaption,
                        color: theme.colors.accentPink,
                        action: onTapBodyFat
                    )

                    horizontalMetricDivider

                    timelineMetricButton(
                        title: "FFMI",
                        value: ffmiValue,
                        caption: ffmiCaption,
                        color: theme.colors.accentTeal,
                        action: onTapFFMI
                    )
                }
            } else {
                GeometryReader { geometry in
                    let dividerTrackWidth = 42.0
                    let columnWidth = max(0, (geometry.size.width - dividerTrackWidth) / 3.0)

                    HStack(alignment: .top, spacing: 0) {
                        timelineMetricButton(
                            title: "Weight",
                            value: weightValue,
                            caption: weightCaption,
                            color: theme.colors.accentViolet,
                            action: onTapWeight
                        )
                        .frame(width: columnWidth, alignment: .leading)

                        metricDivider

                        timelineMetricButton(
                            title: "Body Fat",
                            value: bodyFatValue,
                            caption: bodyFatCaption,
                            color: theme.colors.accentPink,
                            action: onTapBodyFat
                        )
                        .frame(width: columnWidth, alignment: .leading)

                        metricDivider

                        timelineMetricButton(
                            title: "FFMI",
                            value: ffmiValue,
                            caption: ffmiCaption,
                            color: theme.colors.accentTeal,
                            action: onTapFFMI
                        )
                        .frame(width: columnWidth, alignment: .leading)
                    }
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                .frame(height: 68)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timelineMetricButton(
        title: String,
        value: String,
        caption: String,
        color: Color,
        action: @escaping () -> Void
    ) -> DashboardHomeTimelineMetricButton {
        DashboardHomeTimelineMetricButton(
            title: title,
            value: value,
            caption: caption,
            color: color,
            action: action
        )
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
                .font(.system(size: bodyScoreFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(theme.colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            VStack(alignment: .leading, spacing: 4) {
                Text("Body Score")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(theme.colors.textSecondary)
                    .textCase(.uppercase)

                Text(bodyScoreTagline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.colors.text)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)

                if let bodyScoreDeltaText {
                    Text(bodyScoreDeltaText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Body Score \(bodyScoreText), \(bodyScoreTagline)")
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(theme.colors.border)
            .frame(width: 1, height: 44)
            .padding(.horizontal, 10)
    }

    private var horizontalMetricDivider: some View {
        Rectangle()
            .fill(theme.colors.border)
            .frame(height: 1)
    }
}

private struct DashboardHomeTimelineMetricButton: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                    .font(.caption2.weight(.bold))
                    .foregroundColor(theme.colors.textSecondary)
                    .lineLimit(1)

                Text(value)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(theme.colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(caption)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(theme.colors.textTertiary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.72)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value), \(caption)")
        .accessibilityHint("Opens \(title) details")
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
            ZStack(alignment: .bottom) {
                AvatarBodyRenderer(
                    bodyFatPercentage: bodyFatPercentage,
                    gender: gender,
                    height: geometry.size.height,
                    padding: 0,
                    verticalPadding: 0,
                    horizontalFillScale: 1.0,
                    alignment: .bottom,
                    renderMode: .fillWidth
                )
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
                .accessibilityHidden(true)

                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityText)
                    .accessibilityIdentifier("dashboard_home_timeline_avatar")
                    .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom)
        }
        .clipped()
    }
}

// MARK: - Home / Photos / Metrics Tabs

struct DashboardHomeTab<Header: View, SyncBanner: View, MetricContent: View, QuickActions: View>: View {
    @Environment(\.theme) private var theme

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
                }
                .padding(.top, headerHeight + 16)
                .padding(.bottom, 28)
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
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                updateScrollOffset(value)
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
                            updateHeaderStackHeight(geo.size.height)
                        }
                        .onChange(of: geo.size.height) { newValue in
                            updateHeaderStackHeight(newValue)
                        }
                }
            )
            .background(
                theme.colors.background.opacity(0.9)
                    .ignoresSafeArea(edges: .top)
                    .overlay(
                        Rectangle()
                            .fill(theme.materials.glassUltraThin)
                            .opacity(0.2 * scrollProgress)
                            .ignoresSafeArea(edges: .top)
                    )
            )
            .shadow(
                color: theme.colors.background.opacity(0.18 * scrollProgress),
                radius: 18,
                x: 0,
                y: 10
            )
        }
    }

    private func updateScrollOffset(_ value: CGFloat) {
        guard abs(scrollOffset - value) > 0.5 else { return }

        DispatchQueue.main.async {
            guard abs(scrollOffset - value) > 0.5 else { return }
            scrollOffset = value
        }
    }

    private func updateHeaderStackHeight(_ value: CGFloat) {
        guard value > 0, abs(headerStackHeight - value) > 0.5 else { return }

        DispatchQueue.main.async {
            guard abs(headerStackHeight - value) > 0.5 else { return }
            headerStackHeight = value
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
            }
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
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
                }
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable {
                await onRefresh()
            }
        }
    }
}

// MARK: - Steps Card

struct DashboardStepsCard<ProgressView: View>: View {
    @Environment(\.theme) private var theme

    let formattedSteps: String
    let formattedGoal: String
    let subtext: String
    let progressView: () -> ProgressView
    let onTap: (() -> Void)?

    var body: some View {
        LiquidGlassCard(
            cornerRadius: theme.radius.card,
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
                .foregroundColor(theme.colors.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formattedSteps)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.colors.text)

                Text("/" + formattedGoal)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(theme.colors.textSecondary)

                Spacer()
            }

            progressView()
                .frame(height: 6)

            Text(subtext)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.colors.textSecondary)
        }
    }
}
