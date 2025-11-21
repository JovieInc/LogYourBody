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
    let healthKitManager = HealthKitManager.shared

    // Core data
    @State var dailyMetrics: DailyMetrics?
    @State var bodyMetrics: [BodyMetrics] = []
    @State private var sortedBodyMetricsAscending: [BodyMetrics] = []
    @State private var recentDailyMetrics: [DailyMetrics] = []
    @State var selectedIndex: Int = 0
    @State var hasLoadedInitialData = false
    @State var lastRefreshDate: Date?
    @State var isSyncingData = false  // Flag to prevent UI updates during sync

    // Metrics reordering state
    @AppStorage("metricsOrder") private var metricsOrderData = Data()
    @State private var metricsOrder: [MetricIdentifier] = [.steps, .weight, .bodyFat, .ffmi]
    @State private var draggedMetric: MetricIdentifier?

    // UI state
    @State private var animatingPlaceholder = false
    @State private var showAddEntrySheet = false
    @AppStorage("dashboard_selected_time_range")
    private var storedTimeRangeRawValue: String = TimeRange.month1.rawValue
    @State private var selectedRange: TimeRange = .month1
    @State private var showSyncDetails = false
    @State private var syncBannerState: SyncBannerState?
    @State private var syncBannerDismissTask: Task<Void, Never>?
    @State private var previousSyncStatus: RealtimeSyncManager.SyncStatus = .idle
    @State private var coreDataReloadTask: Task<Void, Never>?
    @State private var metricEntriesCache: [MetricType: MetricEntriesPayload] = [:]
    @State private var fullChartCache: [MetricType: [MetricChartDataPoint]] = [:]

    // Animated metric values for tweening
    @State private var animatedWeight: Double = 0
    @State private var animatedBodyFat: Double = 0
    @State private var animatedFFMI: Double = 0

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

    // Navigation state
    @State private var selectedTab: DashboardTab = .home
    @State private var isMetricDetailActive = false
    @State private var selectedMetricType: MetricType = .weight
    @State private var chartMode: ChartMode = .trend

    enum DashboardTab: Hashable {
        case home
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

    /// Calculate age from date of birth
    private func calculateAge(from dateOfBirth: Date?) -> Int? {
        guard let dob = dateOfBirth else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dob, to: now)
        return ageComponents.year
    }

    var currentMetric: BodyMetrics? {
        guard !bodyMetrics.isEmpty && selectedIndex >= 0 && selectedIndex < bodyMetrics.count else { return nil }
        return bodyMetrics[selectedIndex]
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

            if bodyMetrics.isEmpty && !hasLoadedInitialData {
                ProgressView()
                    .tint(Color(hex: "#6EE7F0"))
            } else if bodyMetrics.isEmpty {
                emptyState
            } else {
                TabView(selection: $selectedTab) {
                    LazyTabView(selectedTab: $selectedTab) {
                        homeTab
                    }
                    .tag(DashboardTab.home)
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }

                    LazyTabView(selectedTab: $selectedTab, tab: .metrics) {
                        metricsTab
                    }
                    .tag(DashboardTab.metrics)
                    .tabItem {
                        Label("Metrics", systemImage: "chart.bar.doc.horizontal.fill")
                    }
                }
            }
        }
        .onAppear {
            // Load saved metrics order from AppStorage
            loadMetricsOrder()

            selectedRange = TimeRange(rawValue: storedTimeRangeRawValue) ?? .month1
            Task { await loadData(loadOnlyNewest: true) }

            // Then refresh async (loads all data in background)
            Task {
                await refreshData()
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
            guard !isSyncingData else { return }

            coreDataReloadTask?.cancel()
            coreDataReloadTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s debounce
                guard !Task.isCancelled else { return }

                if let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>, updated.isEmpty {
                    return
                }

                await loadData()
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
    }

    private var homeTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                compactHeader
                    .padding(.horizontal, 20)

                syncStatusBanner
                    .padding(.horizontal, 20)

                if let metric = currentMetric {
                    heroCard(metric: metric)
                        .padding(.horizontal, 20)
                }
                Spacer(minLength: 160)
            }
            .padding(.top, 8)
        }
        .refreshable {
            await refreshData()
        }
    }

    private var metricsTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                compactHeader
                    .padding(.horizontal, 20)

                syncStatusBanner
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Metrics")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color.liquidTextPrimary)
                    Text("Reorder and tap any card to drill in.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.6))
                }
                .padding(.horizontal, 20)

                metricsView

                Spacer(minLength: 120)
            }
            .padding(.top, 8)
        }
        .refreshable {
            await refreshData()
        }
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        DashboardHeaderCompact(
            avatarURL: avatarURL,
            userFirstName: userFirstName,
            userAgeDisplay: userAgeDisplay,
            userHeightDisplay: userHeightDisplay,
            syncStatusTitle: syncStatusTitle,
            syncStatusDetail: syncStatusDetail,
            syncStatusColor: syncStatusColor,
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
        HeroGlassCard {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Body Score")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.65))

                        Text(bodyScoreText().scoreText)
                            .font(.system(size: 78, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .monospacedDigit()

                        Text(bodyScoreText().tagline)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.7))
                    }

                    Spacer()

                    progressRing(for: bodyScoreText().score)
                        .frame(width: 120, height: 120)
                }

                HStack(spacing: 18) {
                    heroStatTile(title: "FFMI", value: heroFFMIValue(), caption: heroFFMICaption())
                    heroStatTile(title: "Lean %ile", value: heroPercentileValue(), caption: "Among peers")
                    heroStatTile(title: "Target", value: bodyScoreTargetRange(), caption: heroTargetCaption())
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func heroStatTile(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.liquidTextPrimary.opacity(0.6))

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(Color.liquidTextPrimary)

            Text(caption)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.liquidTextPrimary.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressRing(for score: Int) -> some View {
        let progress = Double(score) / 100.0
        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 12)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "#6EE7F0"), Color(hex: "#3A7BD5")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 12
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.8), value: score)

            VStack(spacing: 4) {
                Text("Score")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                Text("/100")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.45))
            }
        }
        .frame(width: 90, height: 90)
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
                    accentColor: .orange,
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
                        accentColor: .purple,
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
                        accentColor: .purple,
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
                chartData: [], // Steps chart data would need daily metrics history
                onAdd: {
                    showAddEntrySheet = true
                },
                metricEntries: nil,
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

    // MARK: - Primary Metric Card

    private func primaryMetricCard(metric: BodyMetrics) -> some View {
        LiquidGlassCard(cornerRadius: 24, padding: 20) {
            VStack(spacing: 12) {
                // Huge weight display with interpolation indicator
                if let weightResult = metric.weight != nil ?
                    InterpolatedMetric(
                        value: metric.weight!,
                        isInterpolated: false,
                        isLastKnown: false,
                        confidenceLevel: nil
                    ) :
                    MetricsInterpolationService.shared.estimateWeight(
                        for: metric.date,
                        metrics: bodyMetrics
                    ) {
                    let weightData = weightResult
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                        let convertedWeight = convertWeight(
                            weightData.value,
                            to: system
                        ) ?? weightData.value
                        // ...
                    }
                }
                // ...

                Text("Body Fat %")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.85))
                if let metric = currentMetric {
                    if let bodyFatResult = metric.bodyFatPercentage != nil ?
                        InterpolatedMetric(
                            value: metric.bodyFatPercentage!,
                            isInterpolated: false,
                            isLastKnown: false,
                            confidenceLevel: nil
                        ) :
                        MetricsInterpolationService.shared.estimateBodyFat(
                            for: metric.date,
                            metrics: bodyMetrics
                        ) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", animatedBodyFat))
                                    .font(.system(size: 28, weight: .bold))
                                    .tracking(-0.3)
                                    .foregroundColor(Color.liquidTextPrimary)
                                    .monospacedDigit()

                                if bodyFatResult.isInterpolated || bodyFatResult.isLastKnown {
                                    DSInterpolationIcon(
                                        confidenceLevel: bodyFatResult.confidenceLevel,
                                        isLastKnown: bodyFatResult.isLastKnown
                                    )
                                }
                            }

                            Text("%")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.liquidTextPrimary.opacity(0.70))

                            bodyFatProgressBar(current: animatedBodyFat, goal: bodyFatGoal)
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.3)
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.30))
                    }
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.3)
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.30))
                }
            }
        }
    }

    private var ffmiTile: some View {
        CompactGlassCard {
            HStack(spacing: 12) {
                // Left: Value and goal
                VStack(alignment: .leading, spacing: 4) {
                    Text("FFMI")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.85))

                    if let metric = currentMetric {
                        let heightInches = convertHeightToInches(
                            height: authManager.currentUser?.profile?.height,
                            heightUnit: authManager.currentUser?.profile?.heightUnit
                        )

                        let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
                            for: metric.date,
                            metrics: bodyMetrics,
                            heightInches: heightInches
                        )

                        if let ffmiData = ffmiResult {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", animatedFFMI))
                                    .font(.system(size: 28, weight: .bold))
                                    .tracking(-0.3)
                                    .foregroundColor(Color.liquidTextPrimary)
                                    .monospacedDigit()

                                if ffmiData.isInterpolated || ffmiData.isLastKnown {
                                    DSInterpolationIcon(
                                        confidenceLevel: ffmiData.confidenceLevel,
                                        isLastKnown: ffmiData.isLastKnown
                                    )
                                }
                            }
                            Text("of \(String(format: "%.0f", ffmiGoal))")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color.liquidTextPrimary.opacity(0.70))
                        } else {
                            Text("—")
                                .font(.system(size: 28, weight: .bold))
                                .tracking(-0.3)
                                .foregroundColor(Color.liquidTextPrimary.opacity(0.30))
                        }
                    } else {
                        Text("—")
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.3)
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.30))
                    }
                }

                Spacer()

                // Right: Progress ring
                if let metric = currentMetric {
                    let heightInches = convertHeightToInches(
                        height: authManager.currentUser?.profile?.height,
                        heightUnit: authManager.currentUser?.profile?.heightUnit
                    )

                    let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
                        for: metric.date,
                        metrics: bodyMetrics,
                        heightInches: heightInches
                    )

                    if let ffmiData = ffmiResult {
                        ffmiProgressBar(current: ffmiData.value, goal: ffmiGoal)
                    }
                }
            }
        }
    }

    // MARK: - Progress Bars

    private func ffmiProgressBar(current: Double, goal: Double) -> some View {
        // Human FFMI range: 10 (very low) to 30 (elite bodybuilder)
        let minFFMI: Double = 10
        let maxFFMI: Double = 30
        let range = maxFFMI - minFFMI

        // Calculate positions (0.0 to 1.0)
        let currentPosition = max(0, min(1, (current - minFFMI) / range))
        let goalPosition = max(0, min(1, (goal - minFFMI) / range))

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

    // MARK: - Quick Actions

    // MARK: - Visual Divider

    private var visualDivider: some View {
        Rectangle()
            .fill(Color.liquidTextPrimary.opacity(0.15))
            .frame(height: 1)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
            Text("No metrics yet")
                .font(.title2)
                .foregroundColor(Color.liquidTextPrimary)
            Text("Tap the + button to log your first entry")
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            GlassPillButton(icon: "plus.circle.fill", title: "Get Started") {
                showAddEntrySheet = true
            }
        }
    }
}

// MARK: - Helpers (using existing extension methods)

extension DashboardViewLiquid {
    // Import these from DashboardView+Helpers.swift and DashboardView+Calculations.swift
    func convertWeight(_ weight: Double?, to system: MeasurementSystem) -> Double? {
        guard let weight = weight else { return nil }
        switch system {
        case .metric: return weight
        case .imperial: return weight * 2.20462
        }
    }

    func convertHeightToInches(height: Double?, heightUnit: String?) -> Double? {
        guard let height = height else { return nil }
        if heightUnit == "cm" {
            return height / 2.54
        } else {
            return height
        }
    }

    func calculateFFMI(weight: Double?, bodyFat: Double?, heightInches: Double?) -> Double? {
        guard let weight = weight, let bodyFat = bodyFat, let heightInches = heightInches else {
            return nil
        }
        let heightMeters = heightInches * 0.0254
        let leanMassKg = weight * (1 - bodyFat / 100)
        return leanMassKg / (heightMeters * heightMeters)
    }

    func loadData(loadOnlyNewest: Bool = false) async {
        guard let userId = authManager.currentUser?.id else {
            await MainActor.run { hasLoadedInitialData = true }
            return
        }

        let fetchedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        let allMetrics = fetchedMetrics
            .compactMap { $0.toBodyMetrics() }
            .sorted { $0.date ?? Date.distantPast > $1.date ?? Date.distantPast }

        let todayMetrics = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let recentDailyCached = await CoreDataManager.shared.fetchDailyMetrics(for: userId, from: thirtyDaysAgo, to: nil)
        let recentDaily = recentDailyCached.map { $0.toDailyMetrics() }

        await MainActor.run {
            if loadOnlyNewest {
                if let newest = allMetrics.first {
                    bodyMetrics = [newest]
                    sortedBodyMetricsAscending = [newest]
                    resetCaches()
                    updateAnimatedValues(for: 0)
                    hasLoadedInitialData = true

                    Task { @MainActor [allMetrics] in
                        if bodyMetrics.count == 1 {
                            bodyMetrics = allMetrics
                            sortedBodyMetricsAscending = allMetrics.sorted {
                                ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
                            }
                            resetCaches()
                        }
                    }
                }
            } else {
                bodyMetrics = allMetrics
                sortedBodyMetricsAscending = allMetrics.sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
                resetCaches()
                if !bodyMetrics.isEmpty {
                    updateAnimatedValues(for: selectedIndex)
                }
                hasLoadedInitialData = true
            }

            if let todayMetrics {
                dailyMetrics = todayMetrics.toDailyMetrics()
            }

            recentDailyMetrics = recentDaily
        }
    }

    private func resetCaches() {
        metricEntriesCache = [:]
        fullChartCache = [:]
    }

    func refreshData() async {
        // Debouncing: Skip refresh if last refresh was within 3 minutes
        if let lastRefresh = lastRefreshDate {
            let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < 180 { // 3 minutes in seconds
                // Just reload from cache for quick refresh (async - won't block UI)
                await loadData()

                // Subtle haptic for quick refresh
                await MainActor.run {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                return
            }
        }

        // Set syncing flag to prevent Core Data observer from firing
        await MainActor.run {
            isSyncingData = true
        }

        var hasErrors = false

        // Sync from HealthKit if authorized
        if healthKitManager.isAuthorized {
            do {
                // Sync weight and body fat data from HealthKit (last 30 days)
                try await healthKitManager.syncWeightFromHealthKit()

                // Sync today's steps
                await syncStepsFromHealthKit()
            } catch {
                // Log error but continue with sync
                // print("HealthKit sync error during refresh: \(error)")
                hasErrors = true
            }
        }

        // Upload local changes to Supabase and pull latest from server
        await MainActor.run {
            realtimeSyncManager.syncAll()
        }

        // Wait for sync operations to complete
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        // Re-enable Core Data observer
        await MainActor.run {
            isSyncingData = false
        }

        // Reload from local cache (async - won't block UI)
        await loadData()

        // Update last refresh timestamp and provide haptic feedback
        await MainActor.run {
            lastRefreshDate = Date()

            // Provide haptic feedback based on result
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()

            if hasErrors {
                generator.notificationOccurred(.warning)
            } else {
                generator.notificationOccurred(.success)
            }
        }
    }

    func syncStepsFromHealthKit() async {
        do {
            let stepCount = try await healthKitManager.fetchTodayStepCount()
            await updateStepCount(stepCount)
        } catch {
            // Silently fail - HealthKit sync is optional
        }
    }

    func updateStepCount(_ steps: Int) async {
        guard let userId = authManager.currentUser?.id else { return }

        let today = Date()

        if let existingMetrics = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: today) {
            // Update existing metrics
            existingMetrics.steps = Int32(steps)
            existingMetrics.updatedAt = Date()

            let dailyMetrics = existingMetrics.toDailyMetrics()
            await MainActor.run {
                self.dailyMetrics = dailyMetrics
            }
        } else {
            // Create new daily metrics
            let newMetrics = DailyMetrics(
                id: UUID().uuidString,
                userId: userId,
                date: today,
                steps: steps,
                notes: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            CoreDataManager.shared.saveDailyMetrics(newMetrics, userId: userId)

            await MainActor.run {
                self.dailyMetrics = newMetrics
            }
        }

        // Sync to backend
        await MainActor.run {
            realtimeSyncManager.syncAll()
        }
    }

    // MARK: - Animation Helpers

    /// Update animated metric values with 180ms ease-out animation
    private func updateAnimatedValues(for index: Int) {
        guard index >= 0 && index < bodyMetrics.count else { return }
        let metric = bodyMetrics[index]

        withAnimation(.easeOut(duration: 0.18)) {
            // Weight
            if let weightResult = metric.weight != nil ?
                InterpolatedMetric(
                    value: metric.weight!,
                    isInterpolated: false,
                    isLastKnown: false,
                    confidenceLevel: nil
                ) :
                MetricsInterpolationService.shared.estimateWeight(
                    for: metric.date,
                    metrics: bodyMetrics
                ) {
                let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                animatedWeight = convertWeight(weightResult.value, to: system) ?? weightResult.value
            }

            // Body Fat
            if let bodyFatResult = metric.bodyFatPercentage != nil ?
                InterpolatedMetric(
                    value: metric.bodyFatPercentage!,
                    isInterpolated: false,
                    isLastKnown: false,
                    confidenceLevel: nil
                ) :
                MetricsInterpolationService.shared.estimateBodyFat(
                    for: metric.date,
                    metrics: bodyMetrics
                ) {
                animatedBodyFat = bodyFatResult.value
            }

            // FFMI
            if let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
                for: metric.date,
                metrics: bodyMetrics,
                heightInches: authManager.currentUser?.profile?.height
            ) {
                animatedFFMI = ffmiResult.value
            }
        }
    }

    // MARK: - Metrics View Helpers

    private func formatSteps(_ steps: Int?) -> String {
        guard let steps = steps else { return "–" }
        return FormatterCache.stepsFormatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    private func formatWeightValue(_ weight: Double?) -> String {
        guard let weight = weight else { return "–" }
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        let converted = convertWeight(weight, to: system) ?? weight
        // Apple Health-style: no decimals for displayed weight
        return String(format: "%.0f", converted)
    }

    private func formatBodyFatValue(_ bodyFat: Double?) -> String {
        guard let bodyFat = bodyFat else {
            // Try to get estimated value
            if let metric = currentMetric,
               let estimated = MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics) {
                return String(format: "%.1f", estimated.value)
            }
            return "–"
        }
        return String(format: "%.1f", bodyFat)
    }

    private func formatFFMIValue(_ metric: BodyMetrics) -> String {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        if let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
            for: metric.date,
            metrics: bodyMetrics,
            heightInches: heightInches
        ) {
            // Apple Health-style: no decimals for FFMI headline value
            return String(format: "%.0f", ffmiResult.value)
        }
        return "–"
    }

    // MARK: - Metric Entries Helpers

    private func metricEntriesPayload(for metricType: MetricType) -> MetricEntriesPayload? {
        switch metricType {
        case .weight:
            return weightEntriesPayload()
        case .bodyFat:
            return bodyFatEntriesPayload()
        case .ffmi:
            return ffmiEntriesPayload()
        case .steps:
            return nil
        }
    }

    private func weightEntriesPayload() -> MetricEntriesPayload? {
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        let primaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)
        let secondaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)

        let entries = sortedBodyMetricsAscending
            .compactMap { metric -> MetricHistoryEntry? in
                guard let rawWeight = metric.weight else { return nil }
                let convertedWeight = convertWeight(rawWeight, to: system) ?? rawWeight
                return MetricHistoryEntry(
                    id: metric.id,
                    date: metric.date,
                    primaryValue: convertedWeight,
                    secondaryValue: metric.bodyFatPercentage,
                    source: metricEntrySourceType(from: metric.dataSource)
                )
            }

        guard !entries.isEmpty else { return nil }

        let config = MetricEntriesConfiguration(
            metricType: .weight,
            unitLabel: system.weightUnit,
            secondaryUnitLabel: "%",
            primaryFormatter: primaryFormatter,
            secondaryFormatter: secondaryFormatter
        )

        return MetricEntriesPayload(config: config, entries: entries)
    }

    private func bodyFatEntriesPayload() -> MetricEntriesPayload? {
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        let primaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 1, maxFractionDigits: 1)
        let secondaryFormatter = MetricFormatterCache.formatter(minFractionDigits: 0, maxFractionDigits: 1)

        let entries = sortedBodyMetricsAscending
            .compactMap { metric -> MetricHistoryEntry? in
                let primaryValue = metric.bodyFatPercentage
                    ?? MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics)?.value
                guard let bodyFatValue = primaryValue else { return nil }

                let secondaryValue: Double?
                if let weight = metric.weight {
                    secondaryValue = convertWeight(weight, to: system) ?? weight
                } else {
                    secondaryValue = nil
                }

                return MetricHistoryEntry(
                    id: metric.id,
                    date: metric.date,
                    primaryValue: bodyFatValue,
                    secondaryValue: secondaryValue,
                    source: metricEntrySourceType(from: metric.dataSource)
                )
            }

        guard !entries.isEmpty else { return nil }

        let config = MetricEntriesConfiguration(
            metricType: .bodyFat,
            unitLabel: "%",
            secondaryUnitLabel: system.weightUnit,
            primaryFormatter: primaryFormatter,
            secondaryFormatter: secondaryFormatter
        )

        return MetricEntriesPayload(config: config, entries: entries)
    }

    private func ffmiEntriesPayload() -> MetricEntriesPayload? {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        guard let heightInches else { return nil }

        let formatter = MetricFormatterCache.formatter(minFractionDigits: 1, maxFractionDigits: 1)

        let entries = sortedBodyMetricsAscending
            .compactMap { metric -> MetricHistoryEntry? in
                guard let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
                    for: metric.date,
                    metrics: bodyMetrics,
                    heightInches: heightInches
                ) else {
                    return nil
                }

                return MetricHistoryEntry(
                    id: metric.id,
                    date: metric.date,
                    primaryValue: ffmiResult.value,
                    secondaryValue: nil,
                    source: metricEntrySourceType(from: metric.dataSource)
                )
            }

        guard !entries.isEmpty else { return nil }

        let config = MetricEntriesConfiguration(
            metricType: .ffmi,
            unitLabel: "",
            secondaryUnitLabel: nil,
            primaryFormatter: formatter,
            secondaryFormatter: nil
        )

        return MetricEntriesPayload(config: config, entries: entries)
    }

    private func metricEntrySourceType(from dataSource: String?) -> MetricEntrySourceType {
        let normalized = dataSource?.lowercased() ?? ""

        if normalized.contains("healthkit") || normalized.contains("health") {
            return .healthKit
        }

        if normalized.isEmpty || normalized == "manual" {
            return .manual
        }

        return .integration(id: dataSource)
    }

    private func formatTime(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        return FormatterCache.shortTimeFormatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        return FormatterCache.mediumDateFormatter.string(from: date)
    }

    private func formatCardDateOnly(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)

        if day == today {
            return "Today"
        }

        if let days = calendar.dateComponents([.day], from: day, to: today).day, days == 1 {
            return "Yesterday"
        }

        let formatter = DateFormatter()
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
        formatter.dateFormat = sameYear ? "MMM d" : "MMM yyyy"
        return formatter.string(from: date)
    }

    private func formatCardDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let day = calendar.startOfDay(for: date)

        if day == today {
            return "Today"
        }

        if let days = calendar.dateComponents([.day], from: day, to: today).day, days == 1 {
            return "Yesterday"
        }

        let formatter = DateFormatter()
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: today)
        formatter.dateFormat = sameYear ? "MMM d" : "MMM yyyy"
        return formatter.string(from: date)
    }

    private func generateStepsChartData() -> [MetricDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lookup = dailyMetricsLookup()

        guard !lookup.isEmpty else { return [] }

        var chartData: [MetricDataPoint] = []

        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let stepsValue = lookup[date]?.steps ?? 0
            chartData.append(
                MetricDataPoint(index: 6 - offset, value: Double(max(stepsValue ?? 0, 0)))
            )
        }

        return chartData
    }

    private func latestStepsSnapshot() -> (value: Int?, date: Date?) {
        // Prefer Core Data so we can fall back to the most recent day with data
        guard let userId = authManager.currentUser?.id else {
            return (dailyMetrics?.steps, dailyMetrics?.date)
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lookup = dailyMetricsLookup()

        // Look back up to 30 days for the latest non-zero steps entry
        for offset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if let entry = lookup[date], let steps = entry.steps, steps > 0 {
                return (steps, entry.date)
            }
        }

        if let metrics = dailyMetrics {
            return (metrics.steps, metrics.date)
        }

        return (nil, nil)
    }

    private func dailyMetricsLookup() -> [Date: DailyMetrics] {
        var lookup: [Date: DailyMetrics] = [:]
        let calendar = Calendar.current

        for metric in recentDailyMetrics {
            let key = calendar.startOfDay(for: metric.date)
            if let existing = lookup[key] {
                if metric.updatedAt > existing.updatedAt {
                    lookup[key] = metric
                }
            } else {
                lookup[key] = metric
            }
        }

        return lookup
    }

    private func generateWeightChartData() -> [MetricDataPoint] {
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        return filteredMetrics(for: selectedRange).enumerated().compactMap { index, metric in
            guard let weight = metric.weight else { return nil }
            let converted = convertWeight(weight, to: system) ?? weight
            return MetricDataPoint(index: index, value: converted)
        }
    }

    private func generateBodyFatChartData() -> [MetricDataPoint] {
        filteredMetrics(for: selectedRange).enumerated().compactMap { index, metric in
            if let bf = metric.bodyFatPercentage {
                return MetricDataPoint(index: index, value: bf)
            } else if let estimated = MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics) {
                return MetricDataPoint(index: index, value: estimated.value)
            }
            return nil
        }
    }

    private func generateFFMIChartData() -> [MetricDataPoint] {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        return filteredMetrics(for: selectedRange).enumerated().compactMap { index, metric in
            if let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
                for: metric.date,
                metrics: bodyMetrics,
                heightInches: heightInches
            ) {
                return MetricDataPoint(index: index, value: ffmiResult.value)
            }
            return nil
        }
    }

    private func filteredMetrics(for range: TimeRange) -> [BodyMetrics] {
        guard let days = range.days else {
            return sortedBodyMetricsAscending
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sortedBodyMetricsAscending.filter { $0.date >= cutoffDate }
    }

    private func cachedMetricEntries(for type: MetricType) -> MetricEntriesPayload? {
        if let cached = metricEntriesCache[type] {
            return cached
        }
        let payload = metricEntriesPayload(for: type)
        metricEntriesCache[type] = payload
        return payload
    }

    private func cachedChartData(
        for type: MetricType,
        generator: () -> [MetricChartDataPoint]
    ) -> [MetricChartDataPoint] {
        if let cached = fullChartCache[type] {
            return cached
        }
        let data = generator()
        fullChartCache[type] = data
        return data
    }

    private func weightRangeStats() -> MetricRangeStats? {
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        return computeRangeStats(metrics: filteredMetrics(for: selectedRange)) { metric in
            guard let weight = metric.weight else { return nil }
            return convertWeight(weight, to: system) ?? weight
        }
    }

    private func bodyFatRangeStats() -> MetricRangeStats? {
        computeRangeStats(metrics: filteredMetrics(for: selectedRange)) { metric in
            if let value = metric.bodyFatPercentage {
                return value
            }
            return MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics)?.value
        }
    }

    private func ffmiRangeStats() -> MetricRangeStats? {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        guard let heightInches else { return nil }

        return computeRangeStats(metrics: filteredMetrics(for: selectedRange)) { metric in
            MetricsInterpolationService.shared.estimateFFMI(
                for: metric.date,
                metrics: bodyMetrics,
                heightInches: heightInches
            )?.value
        }
    }

    // Full-screen chart data helpers use the **entire** history and real dates
    // so that time ranges (W/M/6M/Y) can filter by date window.

    private func generateFullScreenWeightChartData() -> [MetricChartDataPoint] {
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial

        return sortedBodyMetricsAscending
            .compactMap { metric in
                guard let weight = metric.weight else { return nil }
                let converted = convertWeight(weight, to: system) ?? weight
                return MetricChartDataPoint(
                    date: metric.date,
                    value: converted
                )
            }
    }

    private func generateFullScreenBodyFatChartData() -> [MetricChartDataPoint] {
        return bodyMetrics
            .sorted { $0.date < $1.date }
            .compactMap { metric in
                if let bf = metric.bodyFatPercentage {
                    return MetricChartDataPoint(
                        date: metric.date,
                        value: bf,
                        isEstimated: false
                    )
                }

                if let estimated = MetricsInterpolationService.shared.estimateBodyFat(
                    for: metric.date,
                    metrics: bodyMetrics
                ) {
                    return MetricChartDataPoint(
                        date: metric.date,
                        value: estimated.value,
                        isEstimated: true
                    )
                }

                return nil
            }
    }

    private func generateFullScreenFFMIChartData() -> [MetricChartDataPoint] {
        let heightInches = convertHeightToInches(
            height: authManager.currentUser?.profile?.height,
            heightUnit: authManager.currentUser?.profile?.heightUnit
        )

        return sortedBodyMetricsAscending
            .compactMap { metric in
                guard let ffmiResult = MetricsInterpolationService.shared.estimateFFMI(
                    for: metric.date,
                    metrics: bodyMetrics,
                    heightInches: heightInches
                ) else {
                    return nil
                }

                return MetricChartDataPoint(
                    date: metric.date,
                    value: ffmiResult.value,
                    isEstimated: ffmiResult.isInterpolated
                )
            }
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
