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
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var realtimeSyncManager: RealtimeSyncManager
    @StateObject var viewModel = DashboardViewModel()

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
                await loadGlp1DoseLogs()
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
                if !viewModel.bodyMetrics.isEmpty {
                    updateAnimatedValues(for: selectedIndex)
                }
                await loadGlp1DoseLogs()
            }
        }

        previousSyncStatus = realtimeSyncManager.syncStatus
        handleSyncStatusChange(from: realtimeSyncManager.syncStatus, to: realtimeSyncManager.syncStatus)

        isPhotosTabEnabled = AnalyticsService.shared.isFeatureEnabled(flagKey: Constants.photosTabFlagKey)
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
            if !viewModel.bodyMetrics.isEmpty {
                updateAnimatedValues(for: selectedIndex)
            }
        }
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
                    glp1MetricCard
                }
            },
            onRefresh: {
                await viewModel.refreshData(
                    authManager: authManager,
                    realtimeSyncManager: realtimeSyncManager
                )
                await loadGlp1DoseLogs()
            }
        )
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
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DashboardEmptyStateLiquid {
            showAddEntrySheet = true
        }
    }
}

#Preview {
    DashboardViewLiquid()
        .environmentObject(AuthManager.shared)
        .environmentObject(RealtimeSyncManager.shared)
}
