//
//  DashboardViewLiquid.swift
//  LogYourBody
//
//  Redesigned dashboard with liquid glass aesthetic
//  Layout: Greeting → Hero Card → Primary Metric → 2×2 Grid → Quick Actions
//

import SwiftUI
import PhotosUI
import Photos
import Charts
import CoreData
import AVFoundation
@preconcurrency import Combine

struct DashboardViewLiquid: View {
    enum LayoutMode {
        case legacyTabbed
        case photoTimelineHUD
    }

    let layoutMode: LayoutMode

    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var realtimeSyncManager: RealtimeSyncManager
    @StateObject var viewModel = DashboardViewModel()
    @StateObject var globalTimelineStore = GlobalTimelineStore()

    // Core data / selection
    @State var selectedIndex: Int = 0

    // Metrics reordering state
    @AppStorage("metricsOrder") private var metricsOrderData = Data()
    @State var metricsOrder: [MetricIdentifier] = [.steps, .weight, .bodyFat, .ffmi]
    @State var draggedMetric: MetricIdentifier?

    // UI state
    @State private var animatingPlaceholder = false
    @State var showAddEntrySheet = false
    @AppStorage("dashboard_selected_time_range")
    private var storedTimeRangeRawValue: String = TimeRange.month1.rawValue
    @State var selectedRange: TimeRange = .month1
    @State var showSyncDetails = false
    @State var syncBannerState: SyncBannerState?
    @State var syncBannerDismissTask: Task<Void, Never>?
    @State private var previousSyncStatus: RealtimeSyncManager.SyncStatus = .idle
    @State private var coreDataReloadTask: Task<Void, Never>?
    @State var metricEntriesCache: [MetricType: MetricEntriesPayload] = [:]
    @State var fullChartCache: [MetricType: [MetricChartDataPoint]] = [:]
    @State var glp1DoseLogs: [Glp1DoseLog] = []
    @State var glp1Medications: [Glp1Medication] = []
    @State var dailyMetricsLookupCache: [Date: DailyMetrics] = [:]

    // Animated metric values for tweening
    @State var animatedWeight: Double = 0
    @State var animatedBodyFat: Double = 0
    @State var animatedFFMI: Double = 0

    // Goals - Optional values, nil means use gender-based default
    @AppStorage("stepGoal") var stepGoal: Int = 10_000
    @AppStorage(Constants.goalFFMIKey) var customFFMIGoal: Double?
    @AppStorage(Constants.goalBodyFatPercentageKey) var customBodyFatGoal: Double?
    @AppStorage(Constants.goalWeightKey) var customWeightGoal: Double?

    // Preferences
    @AppStorage(Constants.preferredMeasurementSystemKey)
    var measurementSystem = PreferencesView.defaultMeasurementSystem

    @AppStorage("dashboard_weight_uses_trend")
    var weightUsesTrend: Bool = true

    // Timeline mode
    @State private var timelineMode: TimelineMode = .photo
    @State private var photoDisplayMode: DashboardDisplayMode = .photo
    @AppStorage(Constants.defaultHomeModeKey)
    private var defaultHomeModeRawValue = DefaultHomeMode.default.rawValue

    // Navigation state
    @State private var selectedTab: DashboardTab = .home
    @State private var isPhotosTabEnabled = true
    @State private var selectedPhotoTimelineRootPage: PhotoTimelineRootPage = .timeline
    @State var isMetricDetailActive = false
    @State var selectedMetricType: MetricType = .weight
    @State private var isStatsDestinationActive = false
    @State private var isProgressPhotoAttachPresented = false
    @State private var progressPhotoAttachTarget: BodyMetrics?
    @State private var chartMode: ChartMode = .trend
    @State var bodyScoreRefreshToken = UUID()
    @State var isBodyScoreSharePresented = false
    @State var bodyScoreSharePayload: BodyScoreSharePayload?
    @State private var hasPerformedInitialRefresh = false
    @State private var featureGateRefreshToken = UUID()
    @State private var addEntryInitialTab = 0
    @State private var addEntryIncludesGlp1Entry = false

    init(layoutMode: LayoutMode = .legacyTabbed) {
        self.layoutMode = layoutMode
    }

    enum DashboardTab: Hashable {
        case home
        case photos
        case metrics
    }

    enum PhotoTimelineRootPage: Hashable {
        case timeline
        case analytics
    }

    enum MetricType {
        case steps
        case weight
        case bodyFat
        case ffmi
        case glp1
        case bodyScore
    }

    enum DashboardMetricKind {
        case steps
        case weight
        case bodyFat
        case ffmi
        case waist
    }

    enum MetricIdentifier: String, Codable, CaseIterable, Identifiable {
        case steps
        case weight
        case bodyFat
        case ffmi

        var id: String { rawValue }
    }

    var body: some View {
        let base = ZStack {
            dashboardBackground
            dashboardContent
        }

        let withLifecycle = base
            .onAppear {
                // Load saved metrics order from AppStorage
                handleOnAppear()
            }
            .onDisappear {
                syncBannerDismissTask?.cancel()
            }

        let withSyncAndState = withLifecycle
            .onChange(of: realtimeSyncManager.syncStatus) { oldStatus, newStatus in
                previousSyncStatus = oldStatus
                handleSyncStatusChange(from: oldStatus, to: newStatus)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { notification in
                handleCoreDataContextChange(notification)
            }
            .onReceive(viewModel.$recentDailyMetrics) { _ in
                rebuildDailyMetricsLookupCache()
                refreshGlobalTimelineStore()
            }
            .onReceive(viewModel.$bodyMetrics) { _ in
                refreshGlobalTimelineStore()
            }
            .onChange(of: selectedRange) { _, newValue in
                storedTimeRangeRawValue = newValue.rawValue
            }
            .onChange(of: selectedIndex) { _, newIndex in
                updateAnimatedValues(for: newIndex)
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab == .photos {
                    AnalyticsService.shared.track(event: "photos_tab_opened")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .bodyScoreUpdated)) { _ in
                bodyScoreRefreshToken = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: .featureGatesDidChange)) { _ in
                featureGateRefreshToken = UUID()
                loadGlp1WeeklyCheckInDataIfNeeded()
            }

        let withSheetsAndNavigation = withSyncAndState
            .sheet(isPresented: $showAddEntrySheet) {
                AddEntrySheet(
                    isPresented: $showAddEntrySheet,
                    initialTab: addEntryInitialTab,
                    includesGlp1Entry: addEntryIncludesGlp1Entry
                )
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showSyncDetails) {
                DashboardSyncDetailsSheet(
                    isPresented: $showSyncDetails,
                    syncManager: realtimeSyncManager
                )
            }
            .sheet(isPresented: $isProgressPhotoAttachPresented) {
                ProgressPhotoAttachSheet(
                    targetMetric: progressPhotoAttachTarget,
                    fallbackDate: progressPhotoAttachFallbackDate,
                    onComplete: {
                        await handleProgressPhotoAttachComplete()
                    }
                )
                .environmentObject(authManager)
            }
            .background(
                ZStack {
                    NavigationLink(
                        isActive: $isMetricDetailActive,
                        destination: {
                            fullMetricChartView
                        },
                        label: {
                            EmptyView()
                        }
                    )

                    NavigationLink(
                        isActive: $isStatsDestinationActive,
                        destination: {
                            photoTimelineStatsDestination
                        },
                        label: {
                            EmptyView()
                        }
                    )
                }
                    .hidden()
            )
            .toolbarBackground(Material.ultraThinMaterial, for: ToolbarPlacement.tabBar)
            .toolbarBackground(Visibility.visible, for: ToolbarPlacement.tabBar)
            .sheet(isPresented: $isBodyScoreSharePresented) {
                if let payload = bodyScoreSharePayload {
                    BodyScoreShareSheet(payload: payload)
                }
            }
            .onScreenshot {
                guard selectedTab == .home else { return }
                guard !isMetricDetailActive else { return }
                guard let payload = makeBodyScoreSharePayload() else { return }
                bodyScoreSharePayload = payload
                isBodyScoreSharePresented = true
            }
            .onChange(of: showAddEntrySheet) { _, isPresented in
                guard !isPresented else { return }
                addEntryInitialTab = 0
                addEntryIncludesGlp1Entry = false
            }

        return withSheetsAndNavigation
    }

    private var homeTab: some View {
        DashboardHomeTab(
            header: { progress in
                compactHeader(scrollProgress: progress)
            },
            syncBanner: {
                syncStatusBanner
            },
            metricContent: {
                VStack(spacing: 14) {
                    homeModeSwitch
                        .padding(.horizontal, 20)

                    heroSection
                }
            },
            quickActions: {
                quickActions
                    .padding(.horizontal, 20)
            },
            onRefresh: {
                await viewModel.refreshData(
                    authManager: authManager,
                    realtimeSyncManager: realtimeSyncManager
                )
                if !viewModel.bodyMetrics.isEmpty {
                    updateAnimatedValues(for: selectedIndex)
                }
            }
        )
    }

    private func handleOnAppear() {
        loadMetricsOrder()

        selectedRange = TimeRange(rawValue: storedTimeRangeRawValue) ?? .month1
        if !viewModel.hasLoadedInitialData {
            Task {
                await viewModel.loadData(
                    authManager: authManager,
                    loadOnlyNewest: true,
                    selectedIndex: selectedIndex
                )
                refreshGlobalTimelineStore()
                if !viewModel.bodyMetrics.isEmpty {
                    updateAnimatedValues(for: selectedIndex)
                }
            }
        }

        // Then refresh async (loads all data in background) once per dashboard lifecycle
        if !hasPerformedInitialRefresh {
            hasPerformedInitialRefresh = true
            Task {
                await viewModel.refreshData(
                    authManager: authManager,
                    realtimeSyncManager: realtimeSyncManager
                )
                refreshGlobalTimelineStore()
                if !viewModel.bodyMetrics.isEmpty {
                    updateAnimatedValues(for: selectedIndex)
                }
            }
        }

        previousSyncStatus = realtimeSyncManager.syncStatus
        handleSyncStatusChange(from: realtimeSyncManager.syncStatus, to: realtimeSyncManager.syncStatus)

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestFullDashboardFixture") {
            isPhotosTabEnabled = true
        } else {
            isPhotosTabEnabled = AnalyticsService.shared.isFeatureEnabled(flagKey: Constants.photosTabFlagKey)
        }
        #else
        isPhotosTabEnabled = AnalyticsService.shared.isFeatureEnabled(flagKey: Constants.photosTabFlagKey)
        #endif

        loadGlp1WeeklyCheckInDataIfNeeded()
    }

    private func handleCoreDataContextChange(_ notification: Notification) {
        guard !viewModel.isSyncingData else { return }

        let hasRelevantChange: Bool = {
            guard let userInfo = notification.userInfo else { return false }
            let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]

            for key in keys {
                if let objects = userInfo[key] as? Set<NSManagedObject> {
                    if objects.contains(where: { $0 is CachedBodyMetrics || $0 is CachedDailyMetrics }) {
                        return true
                    }
                }
            }

            return false
        }()

        guard hasRelevantChange else { return }

        coreDataReloadTask?.cancel()
        coreDataReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }

            await viewModel.loadData(
                authManager: authManager,
                loadOnlyNewest: true,
                selectedIndex: selectedIndex
            )
            refreshGlobalTimelineStore()
            if !viewModel.bodyMetrics.isEmpty {
                updateAnimatedValues(for: selectedIndex)
            }
        }
    }

    private func refreshGlobalTimelineStore() {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        globalTimelineStore.updateMetrics(
            bodyMetrics,
            dailyMetrics: recentDailyMetrics,
            heightInches: heightInches
        )
    }

    private var heroSection: some View {
        Group {
            if let metric = currentMetric {
                VStack(spacing: 16) {
                    homeTimelineHero(metric: metric)

                    stepsCard
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    private var selectedDefaultHomeMode: DefaultHomeMode {
        DefaultHomeMode(storedValue: defaultHomeModeRawValue)
    }

    private var selectedHomeTimelineMode: TimelineMode {
        selectedDefaultHomeMode.timelineMode
    }

    private var homeTimelineModeBinding: Binding<TimelineMode> {
        Binding(
            get: { selectedHomeTimelineMode },
            set: { newValue in
                defaultHomeModeRawValue = DefaultHomeMode(timelineMode: newValue).rawValue
            }
        )
    }

    private var homeModeSwitch: some View {
        HStack(spacing: 4) {
            ForEach(DefaultHomeMode.allCases) { mode in
                homeModeButton(mode)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home_mode_switch")
    }

    private func homeModeButton(_ mode: DefaultHomeMode) -> some View {
        let isSelected = selectedDefaultHomeMode == mode

        return Button {
            defaultHomeModeRawValue = mode.rawValue
            HapticManager.shared.selection()
        } label: {
            Label(mode.title, systemImage: mode.iconName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .foregroundColor(isSelected ? .black : Color.white.opacity(0.72))
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home_mode_\(mode.rawValue)_button")
    }

    private func homeTimelineHero(metric: BodyMetrics) -> some View {
        let bodyScore = bodyScoreText()

        return DashboardHomeTimelineHero(
            metric: metric,
            bodyMetrics: bodyMetrics,
            selectedIndex: $selectedIndex,
            displayMode: $photoDisplayMode,
            homeMode: selectedDefaultHomeMode,
            dateText: formatHUDDate(metric.date),
            gender: authManager.currentUser?.profile?.gender,
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
            }
        )
    }

    private var photosTab: some View {
        DashboardPhotosTab(
            header: {
                compactHeader
            },
            syncBanner: {
                syncStatusBanner
            },
            photosContent: {
                Group {
                    if !bodyMetrics.isEmpty {
                        VStack(spacing: 16) {
                            ProgressPhotoCarouselView(
                                currentMetric: currentMetric,
                                historicalMetrics: bodyMetrics,
                                selectedMetricsIndex: $selectedIndex,
                                displayMode: $photoDisplayMode
                            )
                            .frame(height: 360)

                            timelineScrubber
                                .padding(.horizontal, 20)
                        }
                    }
                }
            },
            onRefresh: {
                await viewModel.refreshData(
                    authManager: authManager,
                    realtimeSyncManager: realtimeSyncManager
                )
                if !viewModel.bodyMetrics.isEmpty {
                    updateAnimatedValues(for: selectedIndex)
                }
            }
        )
    }

    private var metricsTab: some View {
        DashboardMetricsTab(
            header: {
                compactHeader
            },
            syncBanner: {
                syncStatusBanner
            },
            titleBlock: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Metrics")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.liquidTextPrimary)
                    Text("Reorder and tap any card to drill in.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.6))
                }
                .padding(.horizontal, 20)
            },
            metricsContent: {
                VStack(spacing: 16) {
                    metricsView
                }
            },
            onRefresh: {
                await viewModel.refreshData(
                    authManager: authManager,
                    realtimeSyncManager: realtimeSyncManager
                )
            }
        )
    }

    private var photoTimelineHUD: some View {
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

                hudStatsAction
                    .padding(.horizontal, 20)

                Spacer(minLength: 120)
            }
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.refreshData(
                authManager: authManager,
                realtimeSyncManager: realtimeSyncManager
            )
            refreshGlobalTimelineStore()
            if !viewModel.bodyMetrics.isEmpty {
                updateAnimatedValues(for: selectedIndex)
            }
        }
        .accessibilityIdentifier("photo_timeline_hud")
    }

    private var photoTimelineRoot: some View {
        TabView(selection: $selectedPhotoTimelineRootPage) {
            Group {
                if bodyMetrics.isEmpty {
                    photoTimelineHUDEmptyState
                } else {
                    photoTimelineHUD
                }
            }
            .tag(PhotoTimelineRootPage.timeline)
            .accessibilityIdentifier("photo_timeline_root_page_timeline")

            photoTimelineAnalyticsPage
                .tag(PhotoTimelineRootPage.analytics)
                .accessibilityIdentifier("photo_timeline_root_page_analytics")
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .accessibilityIdentifier("photo_timeline_root_pager")
    }

    private var hudPhotoStage: some View {
        ZStack(alignment: .bottomLeading) {
            ProgressPhotoCarouselView(
                currentMetric: currentMetric,
                historicalMetrics: bodyMetrics,
                selectedMetricsIndex: $selectedIndex,
                displayMode: $photoDisplayMode
            )
            .frame(height: 330)
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )

            if !PhotoTimelineHUDPolicy.hasUsablePhoto(currentMetric) {
                hudMissingPhotoOverlay
            }

            hudPhotoDateChip
                .padding(14)
        }
        .accessibilityIdentifier("photo_timeline_hud_photo_stage")
    }

    private var hudMissingPhotoOverlay: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.82))

            VStack(alignment: .leading, spacing: 4) {
                Text("No progress photo")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.white)

                Text("This timeline point has metrics only.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.68))
            }

            Button {
                presentProgressPhotoAttach(for: progressPhotoAttachMetric)
            } label: {
                Label("Add photo", systemImage: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("photo_timeline_hud_add_photo_button")
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.58)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
        )
    }

    private var hudPhotoDateChip: some View {
        Text(formatHUDDate(currentMetric?.date ?? Date()))
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityIdentifier("photo_timeline_hud_date_chip")
    }

    private var hudTimelineSection: some View {
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

    private var hudMetricsStrip: some View {
        let bucket = activeTimelineBucket
        let weight = bucket?.metrics.weight ?? missingHUDMetric
        let bodyFat = bucket?.metrics.bodyFat ?? missingHUDMetric
        let ffmi = bucket?.metrics.ffmi ?? missingHUDMetric
        let steps = bucket?.metrics.steps ?? missingHUDMetric

        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            hudMetricTile(
                title: "Weight",
                value: formattedHUDWeight(weight.value),
                caption: PhotoTimelineHUDPolicy.stateText(
                    presence: weight.presence,
                    confidence: weight.confidence
                ),
                icon: "scalemass.fill",
                color: Color.metricAccentWeight,
                onTap: {
                    selectedMetricType = .weight
                    isMetricDetailActive = true
                }
            )

            hudMetricTile(
                title: "Body Fat",
                value: formattedHUDBodyFat(bodyFat.value),
                caption: PhotoTimelineHUDPolicy.stateText(
                    presence: bodyFat.presence,
                    confidence: bodyFat.confidence
                ),
                icon: "percent",
                color: Color.metricAccentBodyFat,
                onTap: {
                    selectedMetricType = .bodyFat
                    isMetricDetailActive = true
                }
            )

            hudMetricTile(
                title: "FFMI",
                value: formattedHUDFFMI(ffmi.value),
                caption: PhotoTimelineHUDPolicy.stateText(
                    presence: ffmi.presence,
                    confidence: ffmi.confidence
                ),
                icon: "figure.arms.open",
                color: Color.metricAccentFFMI,
                onTap: {
                    selectedMetricType = .ffmi
                    isMetricDetailActive = true
                }
            )

            hudMetricTile(
                title: "Steps",
                value: formattedHUDSteps(steps.value),
                caption: PhotoTimelineHUDPolicy.stateText(
                    presence: steps.presence,
                    confidence: steps.confidence
                ),
                icon: "flame.fill",
                color: Color.metricAccentSteps,
                onTap: {
                    selectedMetricType = .steps
                    isMetricDetailActive = true
                }
            )
        }
        .accessibilityIdentifier("photo_timeline_hud_metrics")
    }

    private var hudPhaseInsight: some View {
        let insight = PhaseInsightPolicy.insight(for: bodyMetrics)

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: phaseInsightIcon(for: insight.kind))
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(phaseInsightColor(for: insight.kind))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(phaseInsightColor(for: insight.kind).opacity(0.15))
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(insight.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.liquidTextPrimary)

                    if let delta = insight.weightDeltaPercentPerWeek {
                        Text(formatPhaseInsightDelta(delta))
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundColor(phaseInsightColor(for: insight.kind))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(phaseInsightColor(for: insight.kind).opacity(0.14))
                            )
                    }
                }

                Text(insight.message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = insight.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.52))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("photo_timeline_hud_phase_insight")
    }

    private var hudGlp1WeeklyCheckIn: some View {
        let summary = Glp1WeeklyCheckInPolicy.summary(
            medications: glp1Medications,
            doseLogs: glp1DoseLogs
        )

        return Button {
            presentAddEntrySheet(initialTab: 3, includesGlp1Entry: true)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "syringe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(glp1WeeklyCheckInColor(for: summary.status))
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(glp1WeeklyCheckInColor(for: summary.status).opacity(0.15))
                    )

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(summary.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color.liquidTextPrimary)

                        if let latestDoseText = summary.latestDoseText {
                            Text(latestDoseText)
                                .font(.system(size: 11, weight: .bold))
                                .monospacedDigit()
                                .foregroundColor(glp1WeeklyCheckInColor(for: summary.status))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(glp1WeeklyCheckInColor(for: summary.status).opacity(0.14))
                                )
                        }
                    }

                    Text(summary.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(summary.actionTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo_timeline_hud_glp1_weekly_checkin")
        .accessibilityLabel("\(summary.title). \(summary.message). \(summary.actionTitle)")
    }

    private var hudStatsAction: some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedPhotoTimelineRootPage = .analytics
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.metricAccent)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.08))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stats")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.liquidTextPrimary)

                    Text("Charts, sources, and history")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.58))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.42))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photo_timeline_hud_stats_button")
        .accessibilityLabel("Open stats")
    }

    private var photoTimelineStatsDestination: some View {
        photoTimelineAnalyticsPage
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("photo_timeline_stats_destination")
    }

    private var photoTimelineAnalyticsPage: some View {
        ZStack {
            Color.metricCanvas.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    photoTimelineStatsHeader
                        .padding(.horizontal, 20)

                    photoTimelinePresenceSummary
                        .padding(.horizontal, 20)

                    metricsView
                }
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
        }
    }

    private var photoTimelineStatsHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Body trends")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)

            Text("Open a metric for chart and history.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.metricTextSecondary)
        }
    }

    private var photoTimelinePresenceSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timeline states")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                Text("\(timelinePresenceValueCount) values")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.metricTextTertiary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(MetricPresence.allCases, id: \.rawValue) { presence in
                    photoTimelinePresenceChip(
                        title: photoTimelinePresenceLabel(for: presence),
                        count: timelinePresenceCounts[presence] ?? 0,
                        color: photoTimelinePresenceColor(for: presence)
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityIdentifier("photo_timeline_stats_presence_summary")
    }

    private func photoTimelinePresenceChip(
        title: String,
        count: Int,
        color: Color
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.metricTextSecondary)

            Spacer(minLength: 4)

            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.055))
        )
        .accessibilityLabel("\(title), \(count) timeline values")
    }

    private func hudMetricTile(
        title: String,
        value: String,
        caption: String,
        icon: String,
        color: Color,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(color)

                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.68))

                    Spacer(minLength: 0)
                }

                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(Color.liquidTextPrimary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)

                Text(caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.54))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value), \(caption)")
    }

    private var activeTimelineBucket: GlobalTimelineBucket? {
        if let cursor = globalTimelineStore.cursor,
           let bucket = globalTimelineStore.bucket(for: cursor) {
            return bucket
        }

        return globalTimelineStore.weeklyBuckets.last
    }

    private var progressPhotoAttachFallbackDate: Date {
        currentMetric?.date ?? globalTimelineStore.cursor?.date ?? activeTimelineBucket?.endDate ?? Date()
    }

    private var progressPhotoAttachMetric: BodyMetrics? {
        if let currentMetric {
            return currentMetric
        }

        let targetDate = progressPhotoAttachFallbackDate
        return bodyMetrics.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(targetDate)) < abs(rhs.date.timeIntervalSince(targetDate))
        }
    }

    private func presentProgressPhotoAttach(for metric: BodyMetrics?) {
        progressPhotoAttachTarget = metric
        HapticManager.shared.selection()
        isProgressPhotoAttachPresented = true
    }

    @MainActor
    private func handleProgressPhotoAttachComplete() async {
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

    private var timelinePresenceValues: [GlobalTimelineMetricValue] {
        globalTimelineStore.weeklyBuckets.flatMap { bucket in
            [
                bucket.metrics.weight,
                bucket.metrics.bodyFat,
                bucket.metrics.ffmi,
                bucket.metrics.steps
            ]
        }
    }

    private var timelinePresenceCounts: [MetricPresence: Int] {
        timelinePresenceValues.reduce(into: [:]) { counts, value in
            counts[value.presence, default: 0] += 1
        }
    }

    private var timelinePresenceValueCount: Int {
        timelinePresenceValues.count
    }

    private var missingHUDMetric: GlobalTimelineMetricValue {
        GlobalTimelineMetricValue(value: nil, presence: .missing)
    }

    private var isPhaseInsightEnabled: Bool {
        _ = featureGateRefreshToken

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestPhaseInsightFixture") {
            return true
        }
        #endif

        return PhaseInsightPolicy.shouldShowPhaseInsight(
            gateEnabled: AnalyticsService.shared.isFeatureEnabled(
                flagKey: Constants.phaseInsightFlagKey
            )
        )
    }

    private var isGlp1WeeklyCheckInEnabled: Bool {
        _ = featureGateRefreshToken

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lybUITestGlp1WeeklyCheckInFixture") {
            return true
        }
        #endif

        return Glp1WeeklyCheckInPolicy.shouldShowWeeklyCheckIn(
            gateEnabled: AnalyticsService.shared.isFeatureEnabled(
                flagKey: Constants.glp1WeeklyCheckInFlagKey
            )
        )
    }

    private func loadGlp1WeeklyCheckInDataIfNeeded() {
        guard isGlp1WeeklyCheckInEnabled else { return }

        Task {
            await loadGlp1WeeklyCheckInData()
        }
    }

    private func presentAddEntrySheet(initialTab: Int = 0, includesGlp1Entry: Bool = false) {
        addEntryInitialTab = initialTab
        addEntryIncludesGlp1Entry = includesGlp1Entry
        showAddEntrySheet = true
    }

    private func phaseInsightIcon(for kind: PhaseInsightKind) -> String {
        switch kind {
        case .cutting:
            return "chart.line.downtrend.xyaxis"
        case .maintaining:
            return "equal.circle.fill"
        case .gaining:
            return "chart.line.uptrend.xyaxis"
        case .insufficientData:
            return "clock.badge.questionmark.fill"
        }
    }

    private func phaseInsightColor(for kind: PhaseInsightKind) -> Color {
        switch kind {
        case .cutting:
            return Color.metricAccentBodyFat
        case .maintaining:
            return Color.metricAccent
        case .gaining:
            return Color.metricAccentWeight
        case .insufficientData:
            return Color.metricTextTertiary
        }
    }

    private func glp1WeeklyCheckInColor(for status: Glp1WeeklyCheckInStatus) -> Color {
        switch status {
        case .setup:
            return Color.metricAccent
        case .due:
            return Color.metricAccentWeight
        case .logged:
            return Color.metricAccentSteps
        }
    }

    private func formatPhaseInsightDelta(_ value: Double) -> String {
        String(format: "%+.1f%%/wk", value)
    }

    private func photoTimelinePresenceLabel(for presence: MetricPresence) -> String {
        switch presence {
        case .present:
            return "Measured"
        case .interpolated:
            return "Interpolated"
        case .lastKnown:
            return "Last known"
        case .missing:
            return "Missing"
        }
    }

    private func photoTimelinePresenceColor(for presence: MetricPresence) -> Color {
        switch presence {
        case .present:
            return Color.metricChartLine
        case .interpolated:
            return Color.metricAccentBodyFat
        case .lastKnown:
            return Color.metricAccentFFMI
        case .missing:
            return Color.metricTextTertiary
        }
    }

    private func selectClosestMetric(to date: Date) {
        guard let match = bodyMetrics.enumerated().min(by: { lhs, rhs in
            abs(lhs.element.date.timeIntervalSince(date)) < abs(rhs.element.date.timeIntervalSince(date))
        }) else {
            return
        }

        selectedIndex = match.offset
        updateAnimatedValues(for: match.offset)
    }

    private func formatHUDDate(_ date: Date) -> String {
        FormatterCache.mediumDateFormatter.string(from: date)
    }

    private func formattedHUDWeight(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(formatWeightValue(value)) \(weightUnit)"
    }

    private func formattedHUDBodyFat(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(formatBodyFatValue(value))%"
    }

    private func formattedHUDFFMI(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.1f", value)
    }

    private func formattedHUDSteps(_ value: Double?) -> String {
        guard let value else { return "–" }
        return FormatterCache.stepsFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    private func loadMetricsOrder() {
        guard !metricsOrderData.isEmpty else { return }

        if let decoded = try? JSONDecoder().decode([MetricIdentifier].self, from: metricsOrderData),
           !decoded.isEmpty {
            metricsOrder = decoded
        }
    }

    func saveMetricsOrder() {
        if let data = try? JSONEncoder().encode(metricsOrder) {
            metricsOrderData = data
        }
    }

    // MARK: - Metrics View

    private var metricsView: some View {
        let stepsGoalText: String? = {
            let formatted = FormatterCache.stepsFormatter.string(from: NSNumber(value: stepGoal)) ?? "\(stepGoal)"
            return "Goal \(formatted) steps"
        }()

        let weightGoalText: String? = {
            guard let goal = weightGoal else { return nil }
            let system = currentMeasurementSystem
            let converted = convertWeight(goal, to: system) ?? goal
            let formatted = String(format: "%.1f", converted)
            return "Target \(formatted) \(weightUnit)"
        }()

        let bodyFatGoalText: String? = {
            let formatted = String(format: "%.1f%%", bodyFatGoal)
            return "Target \(formatted)"
        }()

        let ffmiGoalText: String? = {
            let formatted = String(format: "%.1f", ffmiGoal)
            return "Target \(formatted)"
        }()

        return DashboardMetricsSection(
            metricsOrder: $metricsOrder,
            draggedMetric: $draggedMetric,
            onReorder: saveMetricsOrder,
            selectedRange: $selectedRange,
            selectedMetricType: $selectedMetricType,
            isMetricDetailActive: $isMetricDetailActive,
            currentMetric: currentMetric,
            bodyMetrics: bodyMetrics,
            dailyMetrics: dailyMetrics,
            weightUnit: weightUnit,
            stepsGoalText: stepsGoalText,
            weightGoalText: weightGoalText,
            bodyFatGoalText: bodyFatGoalText,
            ffmiGoalText: ffmiGoalText,
            generateStepsChartData: generateStepsChartData,
            generateWeightChartData: generateWeightChartData,
            generateBodyFatChartData: generateBodyFatChartData,
            generateFFMIChartData: generateFFMIChartData,
            weightRangeStats: weightRangeStats,
            bodyFatRangeStats: bodyFatRangeStats,
            ffmiRangeStats: ffmiRangeStats,
            formatSteps: formatSteps,
            formatWeightValue: formatWeightValue,
            formatBodyFatValue: formatBodyFatValue,
            formatFFMIValue: formatFFMIValue,
            makeTrend: makeTrend,
            formatAverageFootnote: formatAverageFootnote,
            formatCardDateOnly: formatCardDateOnly,
            formatCardDate: formatCardDate,
            latestStepsSnapshot: latestStepsSnapshot,
            weightUsesTrend: $weightUsesTrend,
            formatTrendWeightHeadline: formatTrendWeightHeadline
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Full Metric Chart View

    @ViewBuilder
    private var fullMetricChartView: some View {
        switch selectedMetricType {
        case .steps:
            FullMetricChartView(
                title: "Steps",
                icon: "flame.fill",
                iconColor: Color.metricAccentSteps,
                currentValue: formatSteps(dailyMetrics?.steps),
                unit: "steps",
                currentDate: formatDate(dailyMetrics?.updatedAt ?? Date()),
                chartData: cachedChartData(for: .steps, generator: generateFullScreenStepsChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .steps),
                goalValue: Double(stepGoal),
                selectedTimeRange: $selectedRange
            )

        case .weight:
            FullMetricChartView(
                title: "Weight",
                icon: "figure.stand",
                iconColor: Color.metricAccentWeight,
                currentValue: currentMetric.flatMap { formatWeightValue($0.weight) } ?? "–",
                unit: weightUnit,
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .weight, generator: generateFullScreenWeightChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .weight),
                goalValue: weightGoal,
                selectedTimeRange: $selectedRange
            )

        case .bodyFat:
            FullMetricChartView(
                title: "Body Fat %",
                icon: "percent",
                iconColor: Color.metricAccentBodyFat,
                currentValue: currentMetric.flatMap { formatBodyFatValue($0.bodyFatPercentage) } ?? "–",
                unit: "%",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .bodyFat, generator: generateFullScreenBodyFatChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .bodyFat),
                goalValue: bodyFatGoal,
                selectedTimeRange: $selectedRange
            )

        case .ffmi:
            FullMetricChartView(
                title: "FFMI",
                icon: "figure.arms.open",
                iconColor: Color.metricAccentFFMI,
                currentValue: currentMetric.map { formatFFMIValue($0) } ?? "–",
                unit: "",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .ffmi, generator: generateFullScreenFFMIChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .ffmi),
                goalValue: ffmiGoal,
                selectedTimeRange: $selectedRange
            )
        case .bodyScore:
            let bodyScore = bodyScoreText()
            FullMetricChartView(
                title: "Body Score",
                icon: "star.fill",
                iconColor: Color.metricAccent,
                currentValue: bodyScore.scoreText,
                unit: "",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .bodyScore, generator: generateFullScreenBodyScoreChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .bodyScore),
                goalValue: nil,
                selectedTimeRange: $selectedRange
            )
        case .glp1:
            let sortedLogs = glp1DoseLogs.sorted { $0.takenAt < $1.takenAt }
            let latestLog = sortedLogs.last
            let currentDose = latestLog?.doseAmount
            let currentValue = currentDose.map { String(format: "%.1f", $0) } ?? "–"
            let unit = latestLog?.doseUnit ?? "mg"
            let currentDate = latestLog.map { formatDate($0.takenAt) } ?? formatDate(Date())

            FullMetricChartView(
                title: "GLP-1 Dose",
                icon: "syringe",
                iconColor: Color.metricAccent,
                currentValue: currentValue,
                unit: unit,
                currentDate: currentDate,
                chartData: cachedChartData(for: .glp1, generator: generateFullScreenGlp1ChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: nil,
                goalValue: nil,
                selectedTimeRange: $selectedRange
            )
        }
    }

    // MARK: - Timeline Scrubber (Standalone)

    private var timelineScrubber: some View {
        DashboardTimelineScrubber(
            bodyMetrics: bodyMetrics,
            selectedIndex: $selectedIndex,
            timelineMode: $timelineMode
        )
    }

    private var dashboardBackground: some View {
        LinearGradient(
            colors: [.black, .black.opacity(0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var dashboardContent: some View {
        if viewModel.bodyMetrics.isEmpty && !viewModel.hasLoadedInitialData {
            DashboardSkeleton()
        } else if layoutMode == .photoTimelineHUD {
            photoTimelineRoot
        } else if viewModel.bodyMetrics.isEmpty {
            emptyState
        } else {
            TabView(selection: $selectedTab) {
                homeTab
                    .tag(DashboardTab.home)
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }

                if isPhotosTabEnabled {
                    photosTab
                        .tag(DashboardTab.photos)
                        .tabItem {
                            Image(systemName: "camera.fill")
                            Text("Photos")
                        }
                }

                metricsTab
                    .tag(DashboardTab.metrics)
                    .tabItem {
                        Image(systemName: "chart.bar.fill")
                        Text("Metrics")
                    }
            }
            .tint(Color.appPrimary)
            .accessibilityIdentifier("legacy_full_dashboard_beta")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DashboardEmptyStateLiquid {
            showAddEntrySheet = true
        }
    }

    private var photoTimelineHUDEmptyState: some View {
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
        .accessibilityIdentifier("photo_timeline_hud_empty_state")
    }
}

enum ProgressPhotoAttachStatus: Equatable {
    case empty
    case ready
    case permissionDenied
    case processing
    case success
    case failed(String)
}

struct ProgressPhotoAttachPolicy {
    static func title(targetHasPhoto: Bool) -> String {
        targetHasPhoto ? "Update progress photo" : "Add progress photo"
    }

    static func targetCopy(hasTargetMetric: Bool, targetDate: Date) -> String {
        let dateText = FormatterCache.mediumDateFormatter.string(from: targetDate)
        return hasTargetMetric ? "Attaches to \(dateText)" : "Adds to \(dateText)"
    }

    static func statusTitle(for status: ProgressPhotoAttachStatus) -> String {
        switch status {
        case .empty:
            return "Choose a photo"
        case .ready:
            return "Ready to attach"
        case .permissionDenied:
            return "Permission needed"
        case .processing:
            return "Processing photo"
        case .success:
            return "Photo added"
        case .failed:
            return "Photo failed"
        }
    }

    static func statusMessage(for status: ProgressPhotoAttachStatus) -> String {
        switch status {
        case .empty:
            return "Take one photo or choose one from your library."
        case .ready:
            return "Review the photo, then attach it to this timeline point."
        case .permissionDenied:
            return "Enable camera or photo access in Settings, then try again."
        case .processing:
            return "Keep this sheet open while the photo is prepared and uploaded."
        case .success:
            return "The photo is now part of your body-composition timeline."
        case .failed(let message):
            return message.isEmpty ? "Try again with another photo." : message
        }
    }

    static func canUseCamera(isAvailable: Bool, authorizationStatus: AVAuthorizationStatus) -> Bool {
        guard isAvailable else { return false }
        switch authorizationStatus {
        case .authorized, .notDetermined:
            return true
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

struct ProgressPhotoAttachSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var uploadManager = PhotoUploadManager.shared

    let targetMetric: BodyMetrics?
    let fallbackDate: Date
    let onComplete: () async -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedImageDate: Date?
    @State private var attachStatus: ProgressPhotoAttachStatus = .empty
    @State private var isCameraPresented = false

    private var targetDate: Date {
        targetMetric?.date ?? selectedImageDate ?? fallbackDate
    }

    private var isBusy: Bool {
        if case .processing = attachStatus {
            return true
        }
        return uploadManager.isUploading
    }

    private var isSuccess: Bool {
        if case .success = attachStatus {
            return true
        }
        return false
    }

    private var canAttach: Bool {
        selectedImage != nil && !isBusy && !isSuccess
    }

    #if DEBUG
    private var usesProgressPhotoAttachFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-lybUITestProgressPhotoAttachFixture")
    }
    #endif

    var body: some View {
        NavigationView {
            ZStack {
                Color.metricCanvas.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        previewPane
                        statusPane
                        actionPane
                        attachButton
                    }
                    .padding(20)
                    .padding(.bottom, 18)
                }
            }
            .navigationTitle("Progress Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isBusy)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSuccess {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraView { image in
                    handleCameraImage(image)
                }
            }
            .onAppear {
                updateInitialPermissionState()
            }
            .onChange(of: selectedPhotoItem) { _, item in
                loadSelectedPhoto(item)
            }
        }
        .accessibilityIdentifier("progress_photo_attach_sheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ProgressPhotoAttachPolicy.title(targetHasPhoto: PhotoTimelineHUDPolicy.hasUsablePhoto(targetMetric)))
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(.white)

            Text(
                ProgressPhotoAttachPolicy.targetCopy(
                    hasTargetMetric: targetMetric != nil,
                    targetDate: targetDate
                )
            )
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(Color.metricTextSecondary)
        }
    }

    private var previewPane: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.white.opacity(0.065))
                .frame(height: 360)

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .accessibilityLabel("Selected progress photo preview")
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.48))

                    Text("No photo selected")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.metricTextSecondary)
                }
                .accessibilityLabel("No photo selected")
            }

            if isBusy {
                processingOverlay
            }
        }
        .accessibilityIdentifier("progress_photo_attach_preview")
    }

    private var processingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView(value: uploadManager.uploadProgress > 0 ? uploadManager.uploadProgress : nil)
                .tint(.white)
                .frame(width: 120)

            Text(uploadProgressText)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.58))
        )
        .accessibilityIdentifier("progress_photo_attach_processing")
    }

    private var uploadProgressText: String {
        if uploadManager.uploadProgress > 0 {
            return "\(Int(uploadManager.uploadProgress * 100))% uploaded"
        }
        return "Preparing photo"
    }

    private var statusPane: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusIcon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(statusColor)
                .frame(width: 30, height: 30)
                .background(Circle().fill(statusColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(ProgressPhotoAttachPolicy.statusTitle(for: attachStatus))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(ProgressPhotoAttachPolicy.statusMessage(for: attachStatus))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.metricTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .accessibilityIdentifier("progress_photo_attach_status")
    }

    private var statusIcon: String {
        switch attachStatus {
        case .empty:
            return "photo"
        case .ready:
            return "checkmark.circle.fill"
        case .permissionDenied:
            return "lock.fill"
        case .processing:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.seal.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch attachStatus {
        case .empty:
            return Color.metricTextTertiary
        case .ready:
            return Color.metricAccent
        case .permissionDenied, .failed:
            return Color.metricAccentBodyFat
        case .processing:
            return Color.metricAccentFFMI
        case .success:
            return Color.metricAccentSteps
        }
    }

    private var actionPane: some View {
        VStack(spacing: 10) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images
            ) {
                actionRow(
                    title: "Choose from Library",
                    subtitle: "Select one existing progress photo",
                    icon: "photo.fill"
                )
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .accessibilityIdentifier("progress_photo_attach_library_button")

            Button {
                startCameraCapture()
            } label: {
                actionRow(
                    title: "Take Photo",
                    subtitle: cameraSubtitle,
                    icon: "camera.fill"
                )
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !UIImagePickerController.isSourceTypeAvailable(.camera))
            .accessibilityIdentifier("progress_photo_attach_camera_button")

            if !UIImagePickerController.isSourceTypeAvailable(.camera) {
                Text("Camera capture is unavailable in Simulator. Choose from Library for simulator validation.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.metricTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            #if DEBUG
            if usesProgressPhotoAttachFixture {
                Button {
                    selectFixturePhoto()
                } label: {
                    actionRow(
                        title: "Use Fixture Photo",
                        subtitle: "Debug-only simulator image",
                        icon: "testtube.2"
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityIdentifier("progress_photo_attach_fixture_button")
            }
            #endif
        }
    }

    private var cameraSubtitle: String {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            ? "Use the device camera"
            : "Unavailable in Simulator"
    }

    private func actionRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.metricAccent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.white.opacity(0.08)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.metricTextSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.metricTextTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var attachButton: some View {
        Button {
            attachSelectedPhoto()
        } label: {
            HStack {
                Spacer()

                if isBusy {
                    ProgressView()
                        .tint(.black)
                } else if isSuccess {
                    Label("Done", systemImage: "checkmark")
                } else {
                    Label("Attach Photo", systemImage: "paperclip")
                }

                Spacer()
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(height: 48)
            .background(canAttach || isSuccess ? Color.white : Color.white.opacity(0.18))
            .foregroundColor(canAttach || isSuccess ? .black : Color.white.opacity(0.42))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled((!canAttach && !isSuccess) || isBusy)
        .accessibilityIdentifier("progress_photo_attach_submit_button")
    }

    private func updateInitialPermissionState() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .denied || status == .restricted {
            attachStatus = .permissionDenied
        }
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem?) {
        guard let item else {
            selectedImage = nil
            selectedImageDate = nil
            attachStatus = .empty
            return
        }

        attachStatus = .processing

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else {
                    await MainActor.run {
                        attachStatus = .failed("Choose a different image file.")
                    }
                    return
                }

                let photoDate = PhotoMetadataService.shared.extractDate(from: data)
                await MainActor.run {
                    selectedImage = image
                    selectedImageDate = photoDate
                    attachStatus = .ready
                }
            } catch {
                await MainActor.run {
                    attachStatus = .failed("Could not read that photo. Choose another image.")
                }
            }
        }
    }

    private func startCameraCapture() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            attachStatus = .failed("Camera is not available in Simulator. Choose from Library instead.")
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            attachStatus = .processing
            Task {
                let granted = await requestCameraAccess()
                await MainActor.run {
                    attachStatus = granted ? .empty : .permissionDenied
                    isCameraPresented = granted
                }
            }
        case .denied, .restricted:
            attachStatus = .permissionDenied
        @unknown default:
            attachStatus = .permissionDenied
        }
    }

    private func requestCameraAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func handleCameraImage(_ image: UIImage) {
        selectedImage = image
        selectedImageDate = nil
        attachStatus = .ready
    }

    private func attachSelectedPhoto() {
        if isSuccess {
            dismiss()
            return
        }

        guard let selectedImage else {
            attachStatus = .empty
            return
        }

        guard let userId = authManager.currentUser?.id else {
            attachStatus = .failed("Sign in again to upload photos.")
            return
        }

        attachStatus = .processing

        Task {
            do {
                let metrics = await targetMetrics(userId: userId)

                #if DEBUG
                if usesProgressPhotoAttachFixture {
                    try await attachFixturePhoto(
                        image: selectedImage,
                        to: metrics,
                        userId: userId
                    )
                    await onComplete()
                    await MainActor.run {
                        attachStatus = .success
                        HapticManager.shared.successAction()
                    }
                    return
                }
                #endif

                _ = try await PhotoUploadManager.shared.uploadProgressPhoto(
                    for: metrics,
                    image: selectedImage
                )

                await onComplete()
                await MainActor.run {
                    attachStatus = .success
                    HapticManager.shared.successAction()
                }
            } catch {
                await MainActor.run {
                    attachStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    #if DEBUG
    private func selectFixturePhoto() {
        selectedImage = makeFixtureProgressPhoto()
        selectedImageDate = targetDate
        attachStatus = .ready
    }

    private func makeFixtureProgressPhoto() -> UIImage {
        let size = CGSize(width: 900, height: 1_200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1))
            context.cgContext.fill(CGRect(origin: .zero, size: size))

            context.cgContext.setFillColor(CGColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 1))
            context.cgContext.fillEllipse(in: CGRect(x: 330, y: 170, width: 240, height: 240))

            context.cgContext.setFillColor(CGColor(red: 0.26, green: 0.27, blue: 0.30, alpha: 1))
            let bodyPath = UIBezierPath(
                roundedRect: CGRect(x: 250, y: 430, width: 400, height: 570),
                cornerRadius: 170
            )
            context.cgContext.addPath(bodyPath.cgPath)
            context.cgContext.fillPath()

            context.cgContext.setStrokeColor(CGColor(red: 0.96, green: 0.96, blue: 0.92, alpha: 0.18))
            context.cgContext.setLineWidth(10)
            context.cgContext.move(to: CGPoint(x: 230, y: 1_050))
            context.cgContext.addLine(to: CGPoint(x: 670, y: 1_050))
            context.cgContext.strokePath()
        }
    }

    private func attachFixturePhoto(
        image: UIImage,
        to metrics: BodyMetrics,
        userId: String
    ) async throws {
        guard let photoUrl = try writeFixturePhoto(image) else {
            throw PhotoUploadManager.PhotoError.imageConversionFailed
        }

        _ = await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: metrics.date,
            photoUrl: photoUrl,
            userId: userId
        )
    }

    private func writeFixturePhoto(_ image: UIImage) throws -> String? {
        guard let data = image.jpegData(compressionQuality: 0.86) else {
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyb-progress-photo-fixture.jpg")
        try data.write(to: url, options: [.atomic])
        return url.absoluteString
    }
    #endif

    private func targetMetrics(userId: String) async -> BodyMetrics {
        if let targetMetric {
            return targetMetric
        }

        return await PhotoMetadataService.shared.createOrUpdateMetrics(
            for: selectedImageDate ?? fallbackDate,
            userId: userId
        )
    }
}

#Preview {
    DashboardViewLiquid()
        .environmentObject(AuthManager.shared)
        .environmentObject(RealtimeSyncManager.shared)
}
