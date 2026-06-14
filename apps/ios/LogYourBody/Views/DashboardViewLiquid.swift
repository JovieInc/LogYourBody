//
//  DashboardViewLiquid.swift
//  LogYourBody
//
//  Redesigned dashboard with liquid glass aesthetic
//  Layout: Greeting → Hero Card → Primary Metric → 2×2 Grid → Quick Actions
//

import SwiftUI
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
    @State var photoDisplayMode: DashboardDisplayMode = .photo
    @AppStorage(Constants.defaultHomeModeKey)
    var defaultHomeModeRawValue = DefaultHomeMode.default.rawValue

    // Navigation state
    @State private var selectedTab: DashboardTab = .home
    @State private var isPhotosTabEnabled = true
    @State var selectedPhotoTimelineRootPage: PhotoTimelineRootPage = .timeline
    @State var isMetricDetailActive = false
    @State var selectedMetricType: MetricType = .weight
    @State private var isStatsDestinationActive = false
    @State var isProgressPhotoAttachPresented = false
    @State var progressPhotoAttachTarget: BodyMetrics?
    @State private var chartMode: ChartMode = .trend
    @State var bodyScoreRefreshToken = UUID()
    @State var isBodyScoreSharePresented = false
    @State var bodyScoreSharePayload: BodyScoreSharePayload?
    @State private var hasPerformedInitialRefresh = false
    @State var featureGateRefreshToken = UUID()
    @State var addEntryInitialTab = 0
    @State var addEntryIncludesGlp1Entry = false

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

        isPhotosTabEnabled = true

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

    func refreshGlobalTimelineStore() {
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
}

#Preview {
    DashboardViewLiquid()
        .environmentObject(AuthManager.shared)
        .environmentObject(RealtimeSyncManager.shared)
}
