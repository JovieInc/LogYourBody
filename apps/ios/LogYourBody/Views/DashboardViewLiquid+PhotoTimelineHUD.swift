import SwiftUI

extension DashboardViewLiquid {
    // MARK: - Photo Timeline HUD

    var photoTimelineHUD: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                compactHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                syncStatusBanner
                    .padding(.horizontal, 20)

                homeModeSwitch
                    .padding(.horizontal, 20)

                if let metric = currentMetric {
                    homeTimelineHero(metric: metric)
                }

                hudTimelineSection
                    .padding(.horizontal, 20)

                if isGlp1WeeklyCheckInEnabled {
                    hudGlp1WeeklyCheckIn
                        .padding(.horizontal, 20)
                }

                if isPhaseInsightEnabled {
                    hudPhaseInsight
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 120)
            }
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .refreshable {
            await viewModel.refreshData(
                authManager: authManager,
                realtimeSyncManager: realtimeSyncManager
            )
            scheduleDashboardDerivedStateRefresh(animatedIndex: selectedIndex)
        }
        .accessibilityIdentifier("photo_timeline_hud")
    }

    var photoTimelineRoot: some View {
        ZStack {
            switch selectedPhotoTimelineRootPage {
            case .timeline:
                Group {
                    if bodyMetrics.isEmpty {
                        photoTimelineHUDEmptyState
                    } else {
                        photoTimelineHUD
                    }
                }
                .accessibilityIdentifier("photo_timeline_root_page_timeline")
            case .analytics:
                photoTimelineAnalyticsPage
                    .accessibilityIdentifier("photo_timeline_root_page_analytics")
            }
        }
        .contentShape(Rectangle())
        .gesture(photoTimelineRootSwipeGesture)
        .accessibilityIdentifier("photo_timeline_root_pager")
    }

    private var photoTimelineRootSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 44 else { return }

                withAnimation(.easeOut(duration: 0.2)) {
                    selectedPhotoTimelineRootPage = horizontal < 0 ? .analytics : .timeline
                }
            }
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
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.06))
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
        guard let match = bodyMetrics.enumerated().min(by: { lhs, rhs in
            abs(lhs.element.date.timeIntervalSince(date)) < abs(rhs.element.date.timeIntervalSince(date))
        }) else {
            return
        }

        selectedIndex = match.offset
        updateAnimatedValues(for: match.offset)
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
                    .foregroundColor(Color.white.opacity(0.78))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Start with a photo")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    Text("Add a progress photo or weight entry to build your body-composition timeline.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    presentProgressPhotoAttach(for: nil)
                } label: {
                    Label("Add photo", systemImage: "camera.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white))
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photo_timeline_hud_empty_add_photo_button")
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 420, alignment: .bottomLeading)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .padding(.horizontal, 20)

            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
