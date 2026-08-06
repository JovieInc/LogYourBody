import SwiftUI

// MARK: - Timeline Scrubber Component

struct DashboardTimelineScrubber: View {
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    @Binding var timelineMode: TimelineMode

    var body: some View {
        Group {
            if !bodyMetrics.isEmpty {
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
                    DashboardQuickAnswerField(
                        headline: bodyScoreTagline,
                        deltaText: bodyScoreDeltaText,
                        dateText: dateText
                    )
                    .allowsHitTesting(false)
                }

                if shouldShowPhoto {
                    timelineGradient
                        .allowsHitTesting(false)
                }
            }
            .aspectRatio(
                shouldShowPhoto ? 4.0 / 5.0 : (dynamicTypeSize.isAccessibilitySize ? 1.05 : 1.55),
                contentMode: .fit
            )
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

private struct DashboardQuickAnswerField: View {
    @Environment(\.theme) private var theme

    let headline: String
    let deltaText: String?
    let dateText: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geometry in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * 0.72))
                    path.addCurve(
                        to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.26),
                        control1: CGPoint(x: geometry.size.width * 0.28, y: geometry.size.height * 0.62),
                        control2: CGPoint(x: geometry.size.width * 0.62, y: geometry.size.height * 0.42)
                    )
                }
                .stroke(theme.colors.info, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            .padding(.vertical, 28)
            .opacity(0.8)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(theme.colors.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(deltaText ?? "Your latest measurements are ready to review.")
                    .font(.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(dateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.colors.textTertiary)
            }
            .padding(20)
        }
        .background(theme.colors.surface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            ["Quick answer", headline, deltaText ?? "Your latest measurements are ready to review", dateText]
                .joined(separator: ". ")
        )
        .accessibilityIdentifier("dashboard_home_quick_answer")
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
                    // Avatar assets do not share one aspect ratio. Fit the
                    // native asset inside the hero so narrow screens never
                    // crop the head, feet, or side silhouette.
                    renderMode: .fit
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

// MARK: - Launch Timeline

/// The focused timeline surface used by the launch experience.
///
/// Composition follows the locked JOV-2866 photo-first hierarchy: the photo
/// stage is the visual anchor, the timeline scrubber sits immediately below
/// it, three compact metric facts follow, and Body Score stays available as a
/// secondary row rather than the first visual object.
///
/// This intentionally has no vertical scroll container. The only scrolling
/// gesture on the page is the photo strip, so a user can move through time
/// directly without losing the essential metrics below it.
struct LaunchTimelineSurface: View {
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var scoreFontSize: CGFloat = 34

    let metric: BodyMetrics
    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    let dateText: String
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

    var body: some View {
        GeometryReader { geometry in
            let stageHeight = min(336, max(216, geometry.size.height * 0.44))

            ZStack(alignment: .topLeading) {
                launchAccessibilityMarker(id: "launch_timeline_surface", label: "Timeline")

                VStack(alignment: .leading, spacing: 0) {
                    timelineStage
                        .frame(height: stageHeight)
                        .clipShape(RoundedRectangle(cornerRadius: theme.radius.card))

                    timelineScrubber
                        .frame(height: 80)
                        .padding(.top, 12)

                    metricStrip
                        .padding(.top, 12)

                    scoreRow
                        .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
    }

    private func launchAccessibilityMarker(id: String, label: String) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
            .allowsHitTesting(false)
    }

    private var timelineStage: some View {
        ZStack(alignment: .bottomLeading) {
            if let photoURL = metric.photoUrl, !photoURL.isEmpty {
                CachedAsyncImage(urlString: photoURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    stagePlaceholder
                }
            } else {
                stagePlaceholder
            }

            LinearGradient(
                colors: [
                    theme.colors.background.opacity(0.04),
                    theme.colors.background.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Selected day")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(dateText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let onShareBodyScore {
                    Button(action: onShareBodyScore) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.black.opacity(0.32), in: Circle())
                    }
                    .frame(width: 44, height: 44)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share Body Score")
                    .accessibilityIdentifier("body_score_hero_share_button")
                }
            }
            .padding(14)
        }
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: theme.radius.card))
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            metric.photoUrl?.isEmpty == false
                ? "Selected progress photo, \(dateText)"
                : "No progress photo for \(dateText)"
        )
        .accessibilityIdentifier("launch_timeline_stage")
    }

    private var stagePlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [theme.colors.surface, theme.colors.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 7) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)

                Text("No progress photo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.text)

                Text("Your Body Score stays front and center")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
    }

    private var metricStrip: some View {
        HStack(spacing: 8) {
            launchMetricCell(
                title: "Weight",
                value: weightValue,
                caption: weightCaption,
                accent: theme.colors.accentViolet,
                action: onTapWeight
            )

            launchMetricCell(
                title: "Body Fat",
                value: bodyFatValue,
                caption: bodyFatCaption,
                accent: theme.colors.accentPink,
                action: onTapBodyFat
            )

            launchMetricCell(
                title: "FFMI",
                value: ffmiValue,
                caption: ffmiCaption,
                accent: theme.colors.accentTeal,
                action: onTapFFMI
            )
        }
    }

    private var scoreRow: some View {
        Group {
            if let onTapBodyScore {
                Button(action: onTapBodyScore) {
                    scoreContent
                }
                .buttonStyle(.plain)
            } else {
                scoreContent
            }
        }
        .accessibilityIdentifier("launch_timeline_body_score")
    }

    private var scoreContent: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(bodyScoreText)
                .font(.system(size: scoreFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(theme.colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            VStack(alignment: .leading, spacing: 3) {
                Text("Body Score")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.colors.textSecondary)
                    .textCase(.uppercase)

                Text(bodyScoreTagline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.colors.text)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.78)

                if let bodyScoreDeltaText {
                    Text(bodyScoreDeltaText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Body Score \(bodyScoreText), \(bodyScoreTagline)")
    }

    private func launchMetricCell(
        title: String,
        value: String,
        caption: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule()
                    .fill(accent)
                    .frame(width: 22, height: 2)

                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(theme.colors.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.colors.border.opacity(0.8), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(value), \(caption)")
    }

    private var timelineScrubber: some View {
        DashboardTimelineScrubber(
            bodyMetrics: bodyMetrics,
            selectedIndex: $selectedIndex,
            timelineMode: .constant(.photo)
        )
        .accessibilityIdentifier("launch_timeline_scrubber")
    }
}
