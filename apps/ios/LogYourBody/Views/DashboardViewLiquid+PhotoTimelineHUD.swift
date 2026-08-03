import SwiftUI

extension DashboardViewLiquid {
    // MARK: - Photo Timeline HUD

    var photoTimelineHUD: some View {
        ZStack(alignment: .topLeading) {
            timelineAccessibilityMarker(id: "photo_timeline_hud", label: "Timeline overview")

            Group {
                if let metric = currentMetric {
                    let bodyScore = bodyScoreText()

                    LaunchTimelineSurface(
                        metric: metric,
                        bodyMetrics: bodyMetrics,
                        selectedIndex: $selectedIndex,
                        dateText: formatHUDDate(metric.date),
                        bodyScoreText: bodyScore.scoreText,
                        bodyScoreTagline: bodyScore.tagline,
                        bodyScoreDeltaText: heroBodyScoreDeltaText(),
                        weightValue: heroWeightValue(),
                        weightCaption: heroWeightCaption(),
                        bodyFatValue: heroBodyFatValue(),
                        bodyFatCaption: heroBodyFatCaption(),
                        ffmiValue: heroFFMIValue(),
                        ffmiCaption: heroFFMICaption(),
                        onTapBodyScore: bodyScore.score > 0 ? {
                            selectedMetricType = .bodyScore
                            isMetricDetailActive = true
                        } : nil,
                        onTapWeight: {
                            selectedMetricType = .weight
                            isMetricDetailActive = true
                        },
                        onTapBodyFat: {
                            selectedMetricType = .bodyFat
                            isMetricDetailActive = true
                        },
                        onTapFFMI: {
                            selectedMetricType = .ffmi
                            isMetricDetailActive = true
                        },
                        onShareBodyScore: makeBodyScoreShareAction(metric: metric, score: bodyScore.score)
                    )
                } else {
                    photoTimelineHUDEmptyState
                }
            }
        }
        .worldClassScreen(.home)
    }

    var photoTimelineRoot: some View {
        VStack(spacing: 0) {
            photoTimelineRootNavigation
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ZStack {
                switch selectedPhotoTimelineRootPage {
                case .timeline:
                    ZStack {
                        timelineAccessibilityMarker(
                            id: "photo_timeline_root_page_timeline",
                            label: "Timeline page"
                        )
                        if bodyMetrics.isEmpty {
                            photoTimelineHUDEmptyState
                        } else {
                            photoTimelineHUD
                        }
                    }
                case .analytics:
                    ZStack {
                        timelineAccessibilityMarker(
                            id: "photo_timeline_root_page_analytics",
                            label: "Stats page"
                        )
                        photoTimelineAnalyticsPage
                    }
                case .chat:
                    ZStack {
                        timelineAccessibilityMarker(
                            id: "photo_timeline_root_page_chat",
                            label: "Chat page"
                        )
                        ChatTabView()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .worldClassScreen(selectedPhotoTimelineRootPage.worldClassScreen)
    }

    private var photoTimelineRootNavigation: some View {
        HStack(spacing: 22) {
            photoTimelineRootNavigationButton(page: .timeline)

            photoTimelineRootNavigationButton(page: .analytics)

            photoTimelineRootNavigationButton(page: .chat)

            Spacer(minLength: 0)

            NavigationLink {
                PreferencesView()
                    .environmentObject(authManager)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens account and app settings")
            .accessibilityIdentifier("photo_timeline_root_settings")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topLeading) {
            timelineAccessibilityMarker(id: "photo_timeline_root_nav", label: "Timeline navigation")
        }
    }

    private func timelineAccessibilityMarker(id: String, label: String) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityIdentifier(id)
            .allowsHitTesting(false)
    }

    private func photoTimelineRootNavigationButton(page: PhotoTimelineRootPage) -> some View {
        let isSelected = selectedPhotoTimelineRootPage == page

        return Button {
            HapticManager.shared.selection()
            selectedPhotoTimelineRootPage = page
        } label: {
            VStack(spacing: 6) {
                Text(page.navigationTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        selectedPhotoTimelineRootPage == page
                            ? theme.colors.text
                            : theme.colors.textSecondary
                    )

                Capsule()
                    .fill(
                        isSelected
                            ? theme.colors.text
                            : Color.clear
                    )
                    .frame(width: 24, height: 2)
            }
            .frame(minHeight: 44, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(page.navigationTitle)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Shows the \(page.navigationTitle.lowercased()) page")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier(page.accessibilityIdentifier)
    }

    var hudTimelineSection: some View {
        VStack(spacing: 12) {
            if !globalTimelineStore.weeklyBuckets.isEmpty ||
                !globalTimelineStore.monthlyBuckets.isEmpty ||
                !globalTimelineStore.yearlyBuckets.isEmpty {
                GlobalTimelineHeader(
                    weeklyBuckets: globalTimelineStore.weeklyBuckets,
                    monthlyBuckets: globalTimelineStore.monthlyBuckets,
                    yearlyBuckets: globalTimelineStore.yearlyBuckets,
                    cursor: globalTimelineStore.cursor,
                    onCursorChange: { cursor in
                        globalTimelineStore.updateCursor(cursor)
                        selectClosestMetric(to: cursor.date)
                    },
                    onTodayTap: {
                        globalTimelineStore.selectToday()
                        if let cursor = globalTimelineStore.cursor {
                            selectClosestMetric(to: cursor.date)
                        }
                    }
                )
            }

            DashboardTimelineScrubber(
                bodyMetrics: bodyMetrics,
                selectedIndex: $selectedIndex,
                timelineMode: homeTimelineModeBinding
            )
        }
        .padding(.vertical, 8)
        .systemBGlassSurface(
            cornerRadius: theme.radius.card,
            tint: theme.colors.text,
            tintOpacity: 0.025,
            borderColor: theme.colors.border,
            borderOpacity: 0.85
        )
        .accessibilityIdentifier("photo_timeline_hud_timeline")
    }

    var activeTimelineBucket: GlobalTimelineBucket? {
        if let cursor = globalTimelineStore.cursor,
           let bucket = globalTimelineStore.bucket(for: cursor) {
            return bucket
        }

        return globalTimelineStore.weeklyBuckets.last
    }

    var progressPhotoAttachFallbackDate: Date {
        currentMetric?.date ?? globalTimelineStore.cursor?.date ?? activeTimelineBucket?.endDate ?? Date()
    }

    var progressPhotoAttachMetric: BodyMetrics? {
        if let currentMetric {
            return currentMetric
        }

        let targetDate = progressPhotoAttachFallbackDate
        return bodyMetrics.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(targetDate)) < abs(rhs.date.timeIntervalSince(targetDate))
        }
    }

    func presentProgressPhotoAttach(for metric: BodyMetrics?) {
        progressPhotoAttachTarget = metric
        HapticManager.shared.selection()
        isProgressPhotoAttachPresented = true
    }

    @MainActor
    func handleProgressPhotoAttachComplete() async {
        await viewModel.refreshData(
            authManager: authManager,
            realtimeSyncManager: realtimeSyncManager
        )
        refreshGlobalTimelineStore()

        if let targetId = progressPhotoAttachTarget?.id,
           let refreshedIndex = bodyMetrics.firstIndex(where: { $0.id == targetId }) {
            selectedIndex = refreshedIndex
            updateAnimatedValues(for: refreshedIndex)
        } else if !bodyMetrics.isEmpty {
            selectedIndex = min(selectedIndex, bodyMetrics.count - 1)
            updateAnimatedValues(for: selectedIndex)
        }
    }

    var timelinePresenceValues: [GlobalTimelineMetricValue] {
        globalTimelineStore.weeklyBuckets.flatMap { bucket in
            [
                bucket.metrics.weight,
                bucket.metrics.bodyFat,
                bucket.metrics.ffmi,
                bucket.metrics.steps
            ]
        }
    }

    var timelinePresenceCounts: [MetricPresence: Int] {
        timelinePresenceValues.reduce(into: [:]) { counts, value in
            counts[value.presence, default: 0] += 1
        }
    }

    var timelinePresenceValueCount: Int {
        timelinePresenceValues.count
    }

    func selectClosestMetric(to date: Date) {
        PerfSignpost.measure("scrub_select_closest") {
            guard let index = nearestBodyMetricIndex(in: bodyMetrics, to: date) else {
                return
            }

            selectedIndex = index
            updateAnimatedValues(for: index, animate: false)
        }
    }

    func formatHUDDate(_ date: Date) -> String {
        FormatterCache.mediumDateFormatter.string(from: date)
    }

    var photoTimelineHUDEmptyState: some View {
        VStack(spacing: 16) {
            compactHeader
                .padding(.horizontal, 20)
                .padding(.top, 8)

            syncStatusBanner
                .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "camera.metering.center.weighted")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(theme.colors.textSecondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Start with a photo")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(theme.colors.text)

                    Text("Add a progress photo or weight entry to build your body-composition timeline.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                photoTimelineHUDEmptyActions
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 420, alignment: .bottomLeading)
            .systemBGlassSurface(
                cornerRadius: theme.radius.card,
                tint: theme.colors.text,
                tintOpacity: 0.03,
                borderColor: theme.colors.border,
                borderOpacity: 0.9
            )
            .padding(.horizontal, 20)

            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var photoTimelineHUDEmptyActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                photoTimelineHUDEmptyAddWeightButton
                photoTimelineHUDEmptyAddPhotoButton
            }
        } else {
            HStack(spacing: 12) {
                photoTimelineHUDEmptyAddWeightButton
                photoTimelineHUDEmptyAddPhotoButton
            }
        }
    }

    private var photoTimelineHUDEmptyAddWeightButton: some View {
        Button {
            presentAddEntrySheet(initialTab: 0)
        } label: {
            Label("Add weight", systemImage: "scalemass.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.colors.background)
        .background(Capsule().fill(theme.colors.text))
        .contentShape(Capsule())
        .accessibilityLabel("Add weight")
        .accessibilityHint("Opens the weight entry form")
        .accessibilityIdentifier("photo_timeline_hud_empty_add_weight_button")
    }

    private var photoTimelineHUDEmptyAddPhotoButton: some View {
        Button {
            presentProgressPhotoAttach(for: nil)
        } label: {
            Label("Add photo", systemImage: "camera.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.colors.background)
        .background(Capsule().fill(theme.colors.text))
        .contentShape(Capsule())
        .accessibilityLabel("Add photo")
        .accessibilityHint("Opens progress photo options")
        .accessibilityIdentifier("photo_timeline_hud_empty_add_photo_button")
    }
}

func nearestBodyMetricIndex(in metrics: [BodyMetrics], to date: Date) -> Int? {
    metrics.enumerated().min(by: { lhs, rhs in
        abs(lhs.element.date.timeIntervalSince(date)) < abs(rhs.element.date.timeIntervalSince(date))
    })?.offset
}
