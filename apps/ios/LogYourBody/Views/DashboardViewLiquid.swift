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
    @State private var metricsOrder: [MetricIdentifier] = [.steps, .weight, .bodyFat, .ffmi]
    @State private var draggedMetric: MetricIdentifier?

    // UI state
    @State private var animatingPlaceholder = false
    @State private var showAddEntrySheet = false
    @AppStorage("dashboard_selected_time_range")
    private var storedTimeRangeRawValue: String = TimeRange.month1.rawValue
    @State var selectedRange: TimeRange = .month1
    @State private var showSyncDetails = false
    @State private var syncBannerState: SyncBannerState?
    @State private var syncBannerDismissTask: Task<Void, Never>?
    @State private var previousSyncStatus: RealtimeSyncManager.SyncStatus = .idle
    @State private var coreDataReloadTask: Task<Void, Never>?
    @State var metricEntriesCache: [MetricType: MetricEntriesPayload] = [:]
    @State var fullChartCache: [MetricType: [MetricChartDataPoint]] = [:]

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

    // Timeline mode
    @State private var timelineMode: TimelineMode = .photo
    @State private var photoDisplayMode: DashboardDisplayMode = .photo

    // Navigation state
    @State private var selectedTab: DashboardTab = .home
    @State private var isMetricDetailActive = false
    @State private var selectedMetricType: MetricType = .weight
    @State private var chartMode: ChartMode = .trend

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

    // MARK: - Goal Helpers

    /// Returns the FFMI goal based on custom setting or gender-based default
    private var ffmiGoal: Double {
        if let custom = customFFMIGoal {
            return custom
        }
        // Use gender-based default
        let gender = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
        return gender.contains("female") || gender.contains("woman") ?
            Constants.BodyComposition.FFMI.femaleIdealValue :
            Constants.BodyComposition.FFMI.maleIdealValue
    }

    /// Returns the body fat % goal based on custom setting or gender-based default
    private var bodyFatGoal: Double {
        if let custom = customBodyFatGoal {
            return custom
        }
        // Use gender-based default
        let gender = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
        return gender.contains("female") || gender.contains("woman") ?
            Constants.BodyComposition.BodyFat.femaleIdealValue :
            Constants.BodyComposition.BodyFat.maleIdealValue
    }

    /// Returns the weight goal (optional, nil if not set)
    private var weightGoal: Double? {
        return customWeightGoal
    }

    private var weightUnit: String {
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        return system.weightUnit
    }

    var bodyMetrics: [BodyMetrics] {
        viewModel.bodyMetrics
    }

    var sortedBodyMetricsAscending: [BodyMetrics] {
        viewModel.sortedBodyMetricsAscending
    }

    var recentDailyMetrics: [DailyMetrics] {
        viewModel.recentDailyMetrics
    }

    var dailyMetrics: DailyMetrics? {
        viewModel.dailyMetrics
    }

    /// Calculate age from date of birth
    private func calculateAge(from dateOfBirth: Date?) -> Int? {
        guard let dob = dateOfBirth else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dob, to: now)
        return ageComponents.year
    }

    var currentMetric: BodyMetrics? {
        let metrics = viewModel.bodyMetrics
        guard !metrics.isEmpty && selectedIndex >= 0 && selectedIndex < metrics.count else { return nil }
        return metrics[selectedIndex]
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.black, .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if viewModel.bodyMetrics.isEmpty && !viewModel.hasLoadedInitialData {
                DashboardSkeleton()
            } else if viewModel.bodyMetrics.isEmpty {
                emptyState
            } else {
                ZStack {
                    TabView(selection: $selectedTab) {
                        LazyTabView(selectedTab: $selectedTab) {
                            homeTab
                        }
                        .tag(DashboardTab.home)

                        LazyTabView(selectedTab: $selectedTab, tab: .photos) {
                            photosTab
                        }
                        .tag(DashboardTab.photos)

                        LazyTabView(selectedTab: $selectedTab, tab: .metrics) {
                            metricsTab
                        }
                        .tag(DashboardTab.metrics)
                    }

                    VStack {
                        Spacer()
                        DashboardBottomTabBar(selectedTab: $selectedTab)
                            .frame(maxWidth: 360)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
                    .ignoresSafeArea(edges: .bottom)
                }
            }
        }
        .onAppear {
            // Load saved metrics order from AppStorage
            loadMetricsOrder()

            selectedRange = TimeRange(rawValue: storedTimeRangeRawValue) ?? .month1
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

            // Then refresh async (loads all data in background)
            Task {
                await viewModel.refreshData(
                    authManager: authManager,
                    realtimeSyncManager: realtimeSyncManager
                )
                if !viewModel.bodyMetrics.isEmpty {
                    updateAnimatedValues(for: selectedIndex)
                }
            }

            previousSyncStatus = realtimeSyncManager.syncStatus
            handleSyncStatusChange(from: realtimeSyncManager.syncStatus, to: realtimeSyncManager.syncStatus)
        }
        .onDisappear {
            syncBannerDismissTask?.cancel()
        }
        .onChange(of: realtimeSyncManager.syncStatus) { oldStatus, newStatus in
            previousSyncStatus = oldStatus
            handleSyncStatusChange(from: oldStatus, to: newStatus)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { notification in
            guard !viewModel.isSyncingData else { return }

            coreDataReloadTask?.cancel()
            coreDataReloadTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s debounce
                guard !Task.isCancelled else { return }

                if let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>, updated.isEmpty {
                    return
                }

                await viewModel.loadData(
                    authManager: authManager,
                    selectedIndex: selectedIndex
                )
                if !viewModel.bodyMetrics.isEmpty {
                    updateAnimatedValues(for: selectedIndex)
                }
            }
        }
        .onChange(of: selectedRange) { _, newValue in
            storedTimeRangeRawValue = newValue.rawValue
        }
        .onChange(of: selectedIndex) { _, newIndex in
            updateAnimatedValues(for: newIndex)
        }
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
        .toolbar(.hidden, for: .tabBar)
    }

    private var homeTab: some View {
        DashboardHomeTab(
            header: {
                compactHeader
            },
            syncBanner: {
                syncStatusBanner
            },
            metricContent: {
                Group {
                    if let metric = currentMetric {
                        VStack(spacing: 16) {
                            heroCard(metric: metric)
                            stepsCard
                            primaryMetricCard(metric: metric)
                            ffmiTile
                        }
                        .padding(.horizontal, 20)
                    }
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

    private var photosTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                compactHeader
                    .padding(.horizontal, 20)

                syncStatusBanner
                    .padding(.horizontal, 20)

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

                Spacer(minLength: 160)
            }
            .padding(.top, 8)
        }
        .refreshable {
            await viewModel.refreshData(
                authManager: authManager,
                realtimeSyncManager: realtimeSyncManager
            )
            if !viewModel.bodyMetrics.isEmpty {
                updateAnimatedValues(for: selectedIndex)
            }
        }
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Metrics")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.liquidTextPrimary)
                    Text("Reorder and tap any card to drill in.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.6))
                }
                .padding(.horizontal, 20)
            },
            metricsContent: {
                metricsView
            },
            onRefresh: {
                await viewModel.refreshData(
                    authManager: authManager,
                    realtimeSyncManager: realtimeSyncManager
                )
            }
        )
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        DashboardHeaderCompact(
            avatarURL: avatarURL,
            userFirstName: userFirstName,
            hasAge: hasAge,
            hasHeight: hasHeight,
            syncStatusTitle: syncStatusTitle,
            syncStatusDetail: syncStatusDetail,
            syncStatusColor: syncStatusColor,
            isSyncError: isSyncError,
            onShowSyncDetails: { showSyncDetails = true }
        )
    }

    private var avatarURL: URL? {
        guard let urlString = authManager.currentUser?.avatarUrl else {
            return nil
        }
        return URL(string: urlString)
    }

    private var userFirstName: String {
        if let fullName = authManager.currentUser?.profile?.fullName, !fullName.isEmpty {
            return fullName.components(separatedBy: " ").first ?? fullName
        } else if let username = authManager.currentUser?.profile?.username {
            return username
        } else if let name = authManager.currentUser?.name, !name.isEmpty {
            return name
        } else if let email = authManager.currentUser?.email {
            let localPart = email.components(separatedBy: "@").first
            if let localPart, !localPart.isEmpty {
                return localPart
            }
        }
        return "User"
    }

    private var userGender: String {
        authManager.currentUser?.profile?.gender ?? "N/A"
    }

    private var userGenderShort: String {
        let gender = authManager.currentUser?.profile?.gender ?? ""
        switch gender.lowercased() {
        case "male": return "M"
        case "female": return "F"
        case "non-binary", "nonbinary": return "NB"
        case "other": return "O"
        default: return gender.prefix(1).uppercased()
        }
    }

    private var hasAge: Bool {
        if let dob = authManager.currentUser?.profile?.dateOfBirth,
           let age = calculateAge(from: dob), age > 0 {
            return true
        }
        return false
    }

    private var hasHeight: Bool {
        if let height = authManager.currentUser?.profile?.height, height > 0 {
            return true
        }
        return false
    }

    private var userAgeDisplay: String {
        if let dob = authManager.currentUser?.profile?.dateOfBirth,
           let age = calculateAge(from: dob), age > 0 {
            return String(age)
        }
        return "—"
    }

    private var userHeightDisplay: String {
        guard let height = authManager.currentUser?.profile?.height else {
            return "—"
        }

        let unit = authManager.currentUser?.profile?.heightUnit ?? "in"

        if unit == "in" {
            let totalInches = Int(height.rounded())
            let feet = totalInches / 12
            let inches = totalInches % 12
            return "\(feet)'\(inches)\""
        } else if unit == "cm" {
            return "\(Int(height.rounded())) cm"
        }

        // Fallback: assume value is centimeters and convert to feet/inches
        let totalInches = height / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches) % 12
        return "\(feet)'\(inches)\""
    }

    private var isSyncError: Bool {
        if case .error = realtimeSyncManager.syncStatus {
            return true
        }
        return false
    }

    private var syncStatusTitle: String {
        if realtimeSyncManager.isSyncing || realtimeSyncManager.syncStatus == .syncing {
            return "Syncing…"
        }

        switch realtimeSyncManager.syncStatus {
        case .offline:
            return "Offline"
        case .error:
            // Keep header copy neutral; red banner handles the explicit error messaging
            return "Sync"
        case .success, .idle:
            return "Synced"
        case .syncing:
            return "Syncing…"
        }
    }

    private var syncStatusDetail: String? {
        if case .error = realtimeSyncManager.syncStatus {
            if let message = realtimeSyncManager.error, !message.isEmpty {
                return message
            }

            if let timeString = lastSyncClockText() {
                return "Last successful sync: \(timeString)"
            }

            return nil
        }

        // Offline messaging stays inline, since the banner is reserved for hard errors
        if !realtimeSyncManager.isOnline || realtimeSyncManager.syncStatus == .offline {
            return "Offline · changes queued"
        }

        // For healthy states, show explicit last-sync time (time-of-day) if available
        if let timeString = lastSyncClockText(),
           realtimeSyncManager.syncStatus == .success || realtimeSyncManager.syncStatus == .idle {
            return "Last synced: \(timeString)"
        }

        return nil
    }

    private var syncStatusColor: Color {
        if realtimeSyncManager.isSyncing {
            return .yellow
        }

        switch realtimeSyncManager.syncStatus {
        case .offline:
            return .gray
        case .error:
            return .red
        case .success:
            return .green
        case .syncing:
            return .yellow
        case .idle:
            return .green
        }
    }

    @ViewBuilder
    private var syncStatusBanner: some View {
        DashboardSyncBanner(banner: syncBannerState) {
            realtimeSyncManager.syncAll()
        }
    }

    private func handleSyncStatusChange(
        from oldStatus: RealtimeSyncManager.SyncStatus,
        to newStatus: RealtimeSyncManager.SyncStatus
    ) {
        syncBannerDismissTask?.cancel()

        if case .error = newStatus {
            let detail: String?
            if let message = realtimeSyncManager.error, !message.isEmpty {
                detail = message
            } else if let last = lastSyncClockText() {
                detail = "Last successful sync: \(last)"
            } else {
                detail = nil
            }

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                syncBannerState = SyncBannerState(style: .error, detail: detail)
            }
        } else if case .error = oldStatus,
                  newStatus == .success || newStatus == .idle {
            let detail = lastSyncClockText().map { "Synced at \($0)" }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                syncBannerState = SyncBannerState(style: .success, detail: detail)
            }

            syncBannerDismissTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        if syncBannerState?.style == .success {
                            syncBannerState = nil
                        }
                    }
                }
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                syncBannerState = nil
            }
        }
    }

    private func lastSyncClockText() -> String? {
        guard let last = realtimeSyncManager.lastSyncDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: last)
    }

    // MARK: - Hero Card

    private func heroCard(metric: BodyMetrics) -> some View {
        let bodyScore = bodyScoreText()
        return DashboardBodyScoreHeroCard(
            score: bodyScore.score,
            scoreText: bodyScore.scoreText,
            tagline: bodyScore.tagline,
            ffmiValue: heroFFMIValue(),
            ffmiCaption: heroFFMICaption(),
            percentileValue: heroPercentileValue(),
            targetRange: bodyScoreTargetRange(),
            targetCaption: heroTargetCaption()
        )
    }

    private func bodyScoreText() -> (score: Int, scoreText: String, tagline: String) {
        guard let result = latestBodyScoreResult() else {
            return (0, "--", "Complete onboarding to unlock")
        }
        return (result.score, "\(result.score)", result.statusTagline)
    }

    private func heroFFMIValue() -> String {
        if let result = latestBodyScoreResult() {
            return String(format: "%.1f", result.ffmi)
        }

        if let metric = currentMetric {
            let heightInches = convertHeightToInches(
                height: authManager.currentUser?.profile?.height,
                heightUnit: authManager.currentUser?.profile?.heightUnit
            )
            if let ffmiData = MetricsInterpolationService.shared.estimateFFMI(
                for: metric.date,
                metrics: bodyMetrics,
                heightInches: heightInches
            ) {
                return String(format: "%.1f", ffmiData.value)
            }
        }
        return "--"
    }

    private func heroFFMICaption() -> String {
        guard let result = latestBodyScoreResult() else {
            return "FFMI"
        }
        return result.ffmiStatus
    }

    private func heroPercentileValue() -> String {
        guard let result = latestBodyScoreResult() else {
            return "--"
        }
        return String(format: "%.0f", result.leanPercentile)
    }

    private func bodyScoreTargetRange() -> String {
        guard let result = latestBodyScoreResult() else {
            return "--"
        }
        return "\(Int(result.targetBodyFat.lowerBound))%-\(Int(result.targetBodyFat.upperBound))%"
    }

    private func heroTargetCaption() -> String {
        guard let result = latestBodyScoreResult() else { return "Body fat" }
        return result.targetBodyFat.label
    }

    private func latestBodyScoreResult() -> BodyScoreResult? {
        return BodyScoreCache.shared.latestResult(for: authManager.currentUser?.id)
    }

    private func loadMetricsOrder() {
        guard !metricsOrderData.isEmpty else { return }

        if let decoded = try? JSONDecoder().decode([MetricIdentifier].self, from: metricsOrderData),
           !decoded.isEmpty {
            metricsOrder = decoded
        }
    }

    private func saveMetricsOrder() {
        if let data = try? JSONEncoder().encode(metricsOrder) {
            metricsOrderData = data
        }
    }

    // MARK: - Metrics View

    private var metricsView: some View {
        DashboardMetricsList(
            metricsOrder: $metricsOrder,
            draggedMetric: $draggedMetric,
            onReorder: saveMetricsOrder,
            cardContent: { metric in
                metricCardView(for: metric)
            }
        )
        .padding(.horizontal, 20)
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
                    accentColor: Color(hex: "#FF9F0A"),
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
            if let currentMetric = currentMetric {
                let stats = weightRangeStats()
                Button {
                    selectedMetricType = .weight
                    isMetricDetailActive = true
                } label: {
                    MetricSummaryCard(
                        icon: "figure.stand",
                        accentColor: Color(hex: "#AF52DE"),
                        state: .data(MetricSummaryCard.Content(
                            title: "Weight",
                            value: formatWeightValue(currentMetric.weight),
                            unit: weightUnit,
                            timestamp: formatCardDate(currentMetric.date),
                            dataPoints: generateWeightChartData().map { point in
                                MetricSummaryCard.DataPoint(index: point.index, value: point.value)
                            },
                            chartAccessibilityLabel: "Weight trend for the past week",
                            chartAccessibilityValue: "Latest value \(formatWeightValue(currentMetric.weight)) \(weightUnit)",
                            trend: stats.flatMap { makeTrend(delta: $0.delta, unit: weightUnit, range: selectedRange) },
                            footnote: stats.map { formatAverageFootnote(value: $0.average, unit: weightUnit) }
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

        case .bodyFat:
            if let currentMetric = currentMetric {
                let stats = bodyFatRangeStats()
                Button {
                    selectedMetricType = .bodyFat
                    isMetricDetailActive = true
                } label: {
                    MetricSummaryCard(
                        icon: "percent",
                        accentColor: Color(hex: "#FF2D55"),
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
                            trend: stats.flatMap { makeTrend(delta: $0.delta, unit: "%", range: selectedRange) },
                            footnote: stats.map { formatAverageFootnote(value: $0.average, unit: "%") }
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

        case .ffmi:
            if let currentMetric = currentMetric {
                let stats = ffmiRangeStats()
                Button {
                    selectedMetricType = .ffmi
                    isMetricDetailActive = true
                } label: {
                    MetricSummaryCard(
                        icon: "figure.arms.open",
                        accentColor: .purple,
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
                            trend: stats.flatMap { makeTrend(delta: $0.delta, unit: "", range: selectedRange) },
                            footnote: stats.map { formatAverageFootnote(value: $0.average, unit: "") }
                        )),
                        isButtonContext: true
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Full Metric Chart View

    @ViewBuilder
    private var fullMetricChartView: some View {
        switch selectedMetricType {
        case .steps:
            FullMetricChartView(
                title: "Steps",
                icon: "flame.fill",
                iconColor: .orange,
                currentValue: formatSteps(dailyMetrics?.steps),
                unit: "steps",
                currentDate: formatDate(dailyMetrics?.updatedAt ?? Date()),
                chartData: cachedChartData(for: .steps, generator: generateFullScreenStepsChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .steps),
                selectedTimeRange: $selectedRange
            )

        case .weight:
            FullMetricChartView(
                title: "Weight",
                icon: "figure.stand",
                iconColor: .purple,
                currentValue: currentMetric.flatMap { formatWeightValue($0.weight) } ?? "–",
                unit: weightUnit,
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .weight, generator: generateFullScreenWeightChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .weight),
                selectedTimeRange: $selectedRange
            )

        case .bodyFat:
            FullMetricChartView(
                title: "Body Fat %",
                icon: "percent",
                iconColor: .purple,
                currentValue: currentMetric.flatMap { formatBodyFatValue($0.bodyFatPercentage) } ?? "–",
                unit: "%",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .bodyFat, generator: generateFullScreenBodyFatChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .bodyFat),
                selectedTimeRange: $selectedRange
            )

        case .ffmi:
            FullMetricChartView(
                title: "FFMI",
                icon: "figure.arms.open",
                iconColor: .purple,
                currentValue: currentMetric.map { formatFFMIValue($0) } ?? "–",
                unit: "",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: cachedChartData(for: .ffmi, generator: generateFullScreenFFMIChartData),
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: cachedMetricEntries(for: .ffmi),
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

    // MARK: - Primary Metric Card

    private var stepsCard: some View {
        let stepsValue = dailyMetrics?.steps ?? 0
        let goalValue = max(stepGoal, 1)
        let formattedSteps = formatSteps(stepsValue)
        let formattedGoal = formatSteps(goalValue)
        let subtext = stepsGoalSubtext(steps: stepsValue, goal: goalValue)

        return DashboardStepsCard(
            formattedSteps: formattedSteps,
            formattedGoal: formattedGoal,
            subtext: subtext,
            progressView: {
                stepsProgressBar(steps: stepsValue, goal: goalValue)
            }
        )
    }

    private func primaryMetricCard(metric: BodyMetrics) -> some View {
        let bodyFatResult: InterpolatedMetric? = {
            guard let metric = currentMetric else {
                return nil
            }

            if let bodyFat = metric.bodyFatPercentage {
                return InterpolatedMetric(
                    value: bodyFat,
                    isInterpolated: false,
                    isLastKnown: false,
                    confidenceLevel: nil
                )
            }

            return MetricsInterpolationService.shared.estimateBodyFat(
                for: metric.date,
                metrics: bodyMetrics
            )
        }()

        return DashboardPrimaryMetricCard(
            animatedBodyFat: animatedBodyFat,
            bodyFatResult: bodyFatResult,
            bodyFatProgress: bodyFatProgressBar(current: animatedBodyFat, goal: bodyFatGoal)
        )
    }

    private var ffmiTile: some View {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        return DashboardFFMITile(
            currentMetric: currentMetric,
            bodyMetrics: bodyMetrics,
            heightInches: heightInches,
            ffmiGoal: ffmiGoal,
            animatedFFMI: animatedFFMI
        )
    }

    // MARK: - Progress Bars

    private func stepsProgressBar(steps: Int, goal: Int) -> some View {
        let clampedGoal = max(goal, 1)
        let progress = max(0, min(Double(steps) / Double(clampedGoal), 1))

        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999)
                    .fill(Color.white.opacity(0.15))

                RoundedRectangle(cornerRadius: 999)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#6EE7F0"),
                                Color(hex: "#22C1C3")
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(progress))
            }
        }
    }

    private func bodyFatProgressBar(current: Double, goal: Double) -> some View {
        // Body fat range: 0% to 40% (human range)
        let minBF: Double = 0
        let maxBF: Double = 40
        let range = maxBF - minBF

        // Calculate positions (0.0 to 1.0)
        let currentPosition = max(0, min(1, (current - minBF) / range))
        let goalPosition = max(0, min(1, (goal - minBF) / range))

        return VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 4)

                // Progress fill (from min to current value)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: "#6EE7F0"))
                    .frame(width: max(0, currentPosition * 60), height: 4)  // 60pt total width

                // Goal indicator tick
                Rectangle()
                    .fill(Color.white.opacity(0.90))
                    .frame(width: 2, height: 8)
                    .offset(x: goalPosition * 60 - 1)  // Center the tick on goal position
            }
            .frame(width: 60, height: 8)  // Container for the bar
        }
    }

    private func weightProgressBar(current: Double, goal: Double?, unit: String) -> some View {
        if let goal = goal {
            // Determine reasonable weight range based on goal
            let range = goal * 0.4  // 40% range (±20% from goal)
            let minWeight = goal - (range / 2)
            let maxWeight = goal + (range / 2)

            // Calculate positions (0.0 to 1.0)
            let currentPosition = max(0, min(1, (current - minWeight) / (maxWeight - minWeight)))
            let goalPosition: Double = 0.5  // Goal is always in the middle

            return AnyView(
                VStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 4)

                        // Progress fill (from min to current value)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "#6EE7F0"))
                            .frame(width: max(0, currentPosition * 60), height: 4)  // 60pt total width

                        // Goal indicator tick
                        Rectangle()
                            .fill(Color.white.opacity(0.90))
                            .frame(width: 2, height: 8)
                            .offset(x: goalPosition * 60 - 1)  // Center the tick on goal position
                    }
                    .frame(width: 60, height: 8)  // Container for the bar
                }
            )
        } else {
            // No goal set - show "Tap to set" placeholder
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.40))

                    Text("Tap to set")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.40))
                }
                .frame(width: 60, height: 8)
            )
        }
    }

    private func stepsGoalSubtext(steps: Int, goal: Int) -> String {
        let remaining = max(goal - steps, 0)
        guard remaining > 0 else {
            return "Goal reached"
        }

        let formattedRemaining = FormatterCache.stepsFormatter.string(from: NSNumber(value: remaining)) ?? "\(remaining)"
        return "\(formattedRemaining) to goal"
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            GlassPillButton(icon: "plus.circle.fill", title: "Log Weight") {
                showAddEntrySheet = true
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Visual Divider

    private var visualDivider: some View {
        Rectangle()
            .fill(Color.liquidTextPrimary.opacity(0.15))
            .frame(height: 1)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DashboardEmptyStateLiquid {
            showAddEntrySheet = true
        }
    }
}

// MARK: - Timeline Scrubber Component

private struct DashboardTimelineScrubber: View {
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

private struct DashboardEmptyStateLiquid: View {
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

private struct DashboardHomeTab<Header: View, SyncBanner: View, MetricContent: View, QuickActions: View>: View {
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

private struct DashboardMetricsTab<Header: View, SyncBanner: View, TitleBlock: View, MetricsContent: View>: View {
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

private struct DashboardStepsCard<ProgressView: View>: View {
    let formattedSteps: String
    let formattedGoal: String
    let subtext: String
    let progressView: () -> ProgressView

    var body: some View {
        LiquidGlassCard(
            cornerRadius: 24,
            blurRadius: 30,
            padding: 20,
            showShadow: true,
            showHighlight: true
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(formattedSteps)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text("/" + formattedGoal)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.7))

                    Spacer()

                    Image(systemName: "flame.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.orange)
                }

                progressView()
                    .frame(height: 10)

                Text(subtext)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.7))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Steps: " + formattedSteps + " of " + formattedGoal)
        .accessibilityHint(subtext)
    }
}

// MARK: - Legacy MetricSummaryCard Removed
// Now using the DesignSystem/Organisms/MetricSummaryCard.swift version with Apple Health styling

// MARK: - Array Extension for Safe Access

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    DashboardViewLiquid()
        .environmentObject(AuthManager.shared)
        .environmentObject(RealtimeSyncManager.shared)
}

// MARK: - Dashboard Bottom Tab Bar

private struct DashboardBottomTabBar: View {
    @Binding var selectedTab: DashboardViewLiquid.DashboardTab

    var body: some View {
        LiquidGlassCard(
            cornerRadius: 28,
            blurRadius: 24,
            padding: 4,
            showShadow: true,
            showHighlight: true
        ) {
            HStack(spacing: 4) {
                tabButton(
                    tab: .home,
                    icon: "house.fill",
                    title: "Home"
                )
                tabButton(
                    tab: .photos,
                    icon: "photo.fill",
                    title: "Photos"
                )
                tabButton(
                    tab: .metrics,
                    icon: "chart.bar.doc.horizontal.fill",
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
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(
                            isSelected ?
                                Color.black.opacity(0.9) :
                                Color.white.opacity(0.75)
                        )

                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(
                            isSelected ?
                                Color.black.opacity(0.9) :
                                Color.white.opacity(0.75)
                        )
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Group {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white)
                                .shadow(
                                    color: Color.white.opacity(0.35),
                                    radius: 16,
                                    x: 0,
                                    y: 6
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.02))
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(isSelected ? 0.25 : 0.12),
                            lineWidth: isSelected ? 1.2 : 0.8
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

private struct LazyTabView<Content: View>: View {
    @Binding var selectedTab: DashboardViewLiquid.DashboardTab
    var tab: DashboardViewLiquid.DashboardTab = .home
    let content: () -> Content

    var body: some View {
        if tab == .home || selectedTab == tab {
            content()
        } else {
            Color.clear
        }
    }
}
