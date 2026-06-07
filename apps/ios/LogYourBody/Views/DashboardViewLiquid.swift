//
//  DashboardViewLiquid.swift
//  LogYourBody
//
//  Redesigned dashboard with liquid glass aesthetic
//  Layout: Greeting → Hero Card → Primary Metric → 2×2 Grid → Quick Actions
//

import SwiftUI
import PhotosUI
import Charts
import CoreData
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

    // Navigation state
    @State private var selectedTab: DashboardTab = .home
    @State private var isPhotosTabEnabled = true
    @State var isMetricDetailActive = false
    @State var selectedMetricType: MetricType = .weight
    @State private var chartMode: ChartMode = .trend
    @State var bodyScoreRefreshToken = UUID()
    @State var isBodyScoreSharePresented = false
    @State var bodyScoreSharePayload: BodyScoreSharePayload?
    @State private var hasPerformedInitialRefresh = false

    init(layoutMode: LayoutMode = .legacyTabbed) {
        self.layoutMode = layoutMode
    }

    enum DashboardTab: Hashable {
        case home
        case photos
        case metrics
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

        let withSheetsAndNavigation = withSyncAndState
            .sheet(isPresented: $showAddEntrySheet) {
                AddEntrySheet(isPresented: $showAddEntrySheet)
                    .environmentObject(authManager)
            }
            .sheet(isPresented: $showSyncDetails) {
                DashboardSyncDetailsSheet(
                    isPresented: $showSyncDetails,
                    syncManager: realtimeSyncManager
                )
            }
            .background(
                NavigationLink(
                    isActive: $isMetricDetailActive,
                    destination: {
                        fullMetricChartView
                    },
                    label: {
                        EmptyView()
                    }
                )
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
                heroSection
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
        DashboardHeroSection(
            metric: currentMetric,
            heroCard: { metric in
                heroCard(metric: metric)
            },
            stepsCard: {
                stepsCard
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

                hudPhotoStage
                    .padding(.horizontal, 20)

                hudTimelineSection
                    .padding(.horizontal, 20)

                hudMetricsStrip
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
                showAddEntrySheet = true
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
                timelineMode: $timelineMode
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
    }

    private var activeTimelineBucket: GlobalTimelineBucket? {
        if let cursor = globalTimelineStore.cursor,
           let bucket = globalTimelineStore.bucket(for: cursor) {
            return bucket
        }

        return globalTimelineStore.weeklyBuckets.last
    }

    private var missingHUDMetric: GlobalTimelineMetricValue {
        GlobalTimelineMetricValue(value: nil, presence: .missing)
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
        } else if viewModel.bodyMetrics.isEmpty && layoutMode == .photoTimelineHUD {
            photoTimelineHUDEmptyState
        } else if viewModel.bodyMetrics.isEmpty {
            emptyState
        } else if layoutMode == .photoTimelineHUD {
            photoTimelineHUD
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
                    showAddEntrySheet = true
                } label: {
                    Label("Add first entry", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Color.white))
                        .foregroundColor(.black)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("photo_timeline_hud_empty_add_entry_button")
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

#Preview {
    DashboardViewLiquid()
        .environmentObject(AuthManager.shared)
        .environmentObject(RealtimeSyncManager.shared)
}
