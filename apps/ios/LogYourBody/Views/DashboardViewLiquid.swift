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

private struct SyncBannerState {
    enum Style {
        case success
        case error
    }

    let style: Style
    let detail: String?
}

private struct MetricRangeStats {
    let startValue: Double
    let endValue: Double
    let delta: Double
    let average: Double
    let percentageChange: Double
}

private func computeRangeStats(
    metrics: [BodyMetrics],
    valueProvider: (BodyMetrics) -> Double?
) -> MetricRangeStats? {
    let sortedMetrics = metrics.sorted { $0.date < $1.date }
    let dataPoints: [(date: Date, value: Double)] = sortedMetrics.compactMap { metric in
        guard let value = valueProvider(metric) else { return nil }
        return (metric.date, value)
    }

    guard let first = dataPoints.first, let last = dataPoints.last, !dataPoints.isEmpty else {
        return nil
    }

    let total = dataPoints.reduce(0) { partialResult, point in
        partialResult + point.value
    }

    let average = total / Double(dataPoints.count)
    let delta = last.value - first.value
    let percentageChange: Double

    if abs(first.value) < .leastNormalMagnitude {
        percentageChange = 0
    } else {
        percentageChange = (delta / first.value) * 100
    }

    return MetricRangeStats(
        startValue: first.value,
        endValue: last.value,
        delta: delta,
        average: average,
        percentageChange: percentageChange
    )
}

private struct MetricSeriesStats {
    let average: Double
    let delta: Double
    let percentageChange: Double
}

private func makeTrend(delta: Double, unit: String, range: TimeRange) -> MetricSummaryCard.Trend? {
    guard abs(delta) > 0.001 else {
        return MetricSummaryCard.Trend(direction: .flat, valueText: "No change", caption: range.rawValue)
    }

    let direction: MetricSummaryCard.Trend.Direction = delta > 0 ? .up : .down
    let formattedDelta = formatDelta(delta: delta, unit: unit)
    let caption = "vs \(range.rawValue)"
    return MetricSummaryCard.Trend(direction: direction, valueText: formattedDelta, caption: caption)
}

private func formatDelta(delta: Double, unit: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = unit == "%" ? 1 : 1
    formatter.minimumFractionDigits = 0

    let value = formatter.string(from: NSNumber(value: abs(delta))) ?? String(format: "%.1f", abs(delta))
    let prefix = delta > 0 ? "+" : "–"
    if unit.isEmpty {
        return "\(prefix)\(value)"
    }
    return "\(prefix)\(value)\(unit == "%" ? unit : " \(unit)")"
}

private func formatAverageFootnote(value: Double, unit: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = unit == "%" ? 1 : 1
    formatter.minimumFractionDigits = 0

    let formatted = formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    if unit.isEmpty {
        return "\(formatted) average"
    }
    return "\(formatted) \(unit) average"
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case photo
    case metrics

    var id: String { rawValue }
}

struct MetricDataPoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
}

struct DashboardViewLiquid: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var realtimeSyncManager: RealtimeSyncManager
    let healthKitManager = HealthKitManager.shared

    // Core data state
    @State var dailyMetrics: DailyMetrics?
    @State var bodyMetrics: [BodyMetrics] = []
    @State var selectedIndex: Int = 0
    @State var hasLoadedInitialData = false
    @State var lastRefreshDate: Date?
    @State var isSyncingData = false  // Flag to prevent UI updates during sync

    // Metrics reordering state
    @AppStorage("metricsOrder") private var metricsOrderData: Data = Data()
    @State private var metricsOrder: [MetricIdentifier] = [.steps, .weight, .bodyFat, .ffmi]
    @State private var draggedMetric: MetricIdentifier?

    // UI state
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var animatingPlaceholder = false
    @State private var showAddEntrySheet = false
    @State private var selectedRange: TimeRange = .month1
    @State private var showSyncDetails = false
    @State private var syncBannerState: SyncBannerState?
    @State private var syncBannerDismissTask: Task<Void, Never>?
    @State private var previousSyncStatus: RealtimeSyncManager.SyncStatus = .idle

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

    // Display mode (photo vs wireframe)
    @State private var displayMode: DisplayMode = .photo

    // Full metric chart view state
    @State private var showFullMetricChart = false
    @State private var selectedMetricType: MetricType = .weight

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
            // Background gradient - softer than pure black
            LinearGradient(
                colors: [.black, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if bodyMetrics.isEmpty && !hasLoadedInitialData {
                // Loading state
                ProgressView()
                    .tint(Color(hex: "#6EE7F0"))
            } else if bodyMetrics.isEmpty {
                // Empty state
                emptyState
            } else {
                TabView(selection: $displayMode) {
                    tabContent(for: .photo)
                        .tag(DisplayMode.photo)
                        .tabItem {
                            Label("Home", systemImage: "house.fill")
                        }

                    tabContent(for: .metrics)
                        .tag(DisplayMode.metrics)
                        .tabItem {
                            Label("Metric", systemImage: "chart.bar.fill")
                        }
                }
                .tint(Color(hex: "#6EE7F0"))
            }
        }
        .onAppear {
            // Load saved metrics order from AppStorage
            loadMetricsOrder()

            // Load ONLY newest metric immediately for instant display
            loadData(loadOnlyNewest: true)

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
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { _ in
            // Only reload if NOT currently syncing (prevents constant UI updates)
            guard !isSyncingData else { return }
            Task {
                await loadData()
            }
        }
        .onChange(of: selectedIndex) { _, newIndex in
            updateAnimatedValues(for: newIndex)
        }
        .sheet(isPresented: $showPhotoOptions) {
            PhotoOptionsSheet(
                showCamera: $showCamera,
                showPhotoPicker: $showPhotoPicker
            )
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                Task {
                    await handlePhotoCapture(image)
                }
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhoto,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                await handlePhotoSelection(newItem)
            }
        }
        .sheet(isPresented: $showAddEntrySheet) {
            AddEntrySheet(isPresented: $showAddEntrySheet)
                .environmentObject(authManager)
        }
        .sheet(isPresented: $showSyncDetails) {
            syncDetailsSheet
        }
        .fullScreenCover(isPresented: $showFullMetricChart) {
            fullMetricChartView
        }
    }

    private func tabContent(for mode: DisplayMode) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                compactHeader
                    .padding(.horizontal, 20)

                syncStatusBanner
                    .padding(.horizontal, 20)

                if mode == .photo {
                    if let metric = currentMetric {
                        heroCard(metric: metric)
                            .padding(.horizontal, 20)
                    }

                    timelineScrubber
                        .padding(.top, 4)
                        .padding(.horizontal, 20)

                    metricsRow
                        .padding(.horizontal, 20)
                } else {
                    metricsView
                }

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
        HStack(alignment: .center, spacing: 12) {
            NavigationLink(destination: PreferencesView()) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                        .frame(width: 44, height: 44)

                    if let avatarUrl = authManager.currentUser?.avatarUrl,
                       let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure, .empty:
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                            @unknown default:
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back, \(userFirstName)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    NavigationLink(destination: PreferencesView()) {
                        Text("Age: \(userAgeDisplay)")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())

                    NavigationLink(destination: PreferencesView()) {
                        Text("Height: \(userHeightDisplay)")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Spacer(minLength: 8)

            Button(action: {
                showSyncDetails = true
            }) {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 6, height: 6)
                        Text(syncStatusTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.6))
                            .lineLimit(1)
                    }

                    if let detail = syncStatusDetail {
                        Text(detail)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: false, vertical: true)
        }
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
        if let banner = syncBannerState {
            let content = VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: banner.style == .error ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(banner.style == .error ? "Sync failed. Tap to retry." : "Back in sync")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)

                if let detail = banner.detail {
                    Text(detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.9))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(bannerBackground(for: banner.style))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .cornerRadius(12)
            .transition(.move(edge: .top).combined(with: .opacity))

            if banner.style == .error {
                Button {
                    realtimeSyncManager.syncAll()
                } label: {
                    content
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                content
            }
        }
    }

    private func relativeLastSyncText(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func handleSyncStatusChange(from oldStatus: RealtimeSyncManager.SyncStatus, to newStatus: RealtimeSyncManager.SyncStatus) {
        syncBannerDismissTask?.cancel()

        if newStatus == .error {
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
        } else if oldStatus == .error && (newStatus == .success || newStatus == .idle) {
            let detail = lastSyncClockText().map { "Synced at \($0)" }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                syncBannerState = SyncBannerState(style: .success, detail: detail)
            }

            syncBannerDismissTask = Task { [weak syncBannerState] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        if self.syncBannerState?.style == .success {
                            self.syncBannerState = nil
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
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: last)
    }

    @ViewBuilder
    private var syncDetailsSheet: some View {
        SyncDetailsSheet(
            isPresented: $showSyncDetails,
            syncManager: realtimeSyncManager
        )
    }

    private func bannerBackground(for style: SyncBannerState.Style) -> LinearGradient {
        switch style {
        case .error:
            return LinearGradient(
                colors: [Color.red.opacity(0.9), Color.red.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .success:
            return LinearGradient(
                colors: [Color.green.opacity(0.85), Color.green.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func retrySync() {
        realtimeSyncManager.syncAll()
    }

    private struct SyncDetailsSheet: View {
        @Binding var isPresented: Bool
        @ObservedObject var syncManager: RealtimeSyncManager

        var body: some View {
            NavigationStack {
                List {
                    Section(header: Text("Status")) {
                        HStack {
                            Text("State")
                            Spacer()
                            Text(statusText)
                                .foregroundColor(.secondary)
                        }

                        if let last = syncManager.lastSyncDate {
                            HStack {
                                Text("Last Sync")
                                Spacer()
                                Text(last.formatted(.dateTime.hour().minute().day().month().year()))
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            Text("Pending Changes")
                            Spacer()
                            Text("\(syncManager.pendingSyncCount)")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = syncManager.error, !error.isEmpty {
                        Section(header: Text("Last Error")) {
                            Text(error)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }
                }
                .navigationTitle("Sync Details")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            isPresented = false
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Retry") {
                            syncManager.syncAll()
                        }
                        .disabled(!syncManager.isOnline)
                    }
                }
            }
        }

        private var statusText: String {
            if syncManager.isSyncing {
                return "Syncing…"
            }

            switch syncManager.syncStatus {
            case .offline:
                return "Offline"
            case .error:
                return "Error"
            case .success:
                return "Synced"
            case .syncing:
                return "Syncing…"
            case .idle:
                return "Idle"
            }
        }
    }

    // MARK: - Hero Card

    private var noPhotoPlaceholder: some View {
        Button(action: {
            showPhotoOptions = true
        }) {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.30))
                Text("Tap to Add Photo")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.60))
            }
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.05))
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(animatingPlaceholder ? 1.0 : 0.98)
        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animatingPlaceholder)
        .onAppear {
            animatingPlaceholder = true
        }
    }

    private func photoContent(for metric: BodyMetrics) -> some View {
        Group {
            if let photoUrl = metric.photoUrl, !photoUrl.isEmpty {
                AsyncImage(url: URL(string: photoUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 280)
                            .clipped()
                    case .failure(let error):
                        // Log error and show placeholder
                        _ = // print("[Dashboard] Image load failed: \(error.localizedDescription), URL: \(photoUrl)")
                        noPhotoPlaceholder
                    case .empty:
                        // Show loading state
                        ProgressView()
                            .frame(height: 280)
                            .frame(maxWidth: .infinity)
                    @unknown default:
                        noPhotoPlaceholder
                    }
                }
            } else {
                noPhotoPlaceholder
            }
        }
    }

    private func heroCard(metric: BodyMetrics) -> some View {
        Group {
            if displayMode == .photo {
                // Photo mode - carousel with hero card
                HeroGlassCard {
                    VStack(spacing: 0) {
                        TabView(selection: $selectedIndex) {
                            ForEach(Array(bodyMetrics.enumerated()), id: \.element.id) { index, m in
                                ZStack(alignment: .topTrailing) {
                                    photoContent(for: m)
                                }
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .always))
                        .indexViewStyle(.page(backgroundDisplayMode: .always))
                        .frame(height: 280)
                        .onChange(of: selectedIndex) { _, _ in
                            // Haptic feedback on swipe
                            Task { @MainActor in
                                let generator = UISelectionFeedbackGenerator()
                                generator.prepare()
                                generator.selectionChanged()
                            }
                        }
                    }
                }
            } else {
                // Metrics mode - scrollable metric cards
                metricsView
            }
        }
    }

    // MARK: - Metrics View

    private var metricsView: some View {
        VStack(spacing: 10) {
            ForEach(metricsOrder) { metricId in
                metricCardView(for: metricId)
                    .scaleEffect(draggedMetric == metricId ? 1.03 : 1.0)
                    .opacity(draggedMetric == metricId ? 0.78 : 1.0)
                    .onDrag {
                        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.85)) {
                            self.draggedMetric = metricId
                        }
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        return NSItemProvider(object: metricId.rawValue as NSString)
                    }
                    .onDrop(of: [.text], delegate: MetricDropDelegate(
                        metric: metricId,
                        metrics: $metricsOrder,
                        draggedMetric: $draggedMetric,
                        onReorder: saveMetricsOrder
                    ))
            }
        }
        // Animate layout changes (card reordering) with a gentle spring
        .animation(.interactiveSpring(response: 0.30, dampingFraction: 0.85), value: metricsOrder)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func metricCardView(for metric: MetricIdentifier) -> some View {
        switch metric {
        case .steps:
            Button {
                selectedMetricType = .steps
                showFullMetricChart = true
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
                    showFullMetricChart = true
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
                    showFullMetricChart = true
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
                    showFullMetricChart = true
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
                    showFullMetricChart = false
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
                chartData: generateFullScreenWeightChartData(),
                onAdd: {
                    showFullMetricChart = false
                    showAddEntrySheet = true
                },
                metricEntries: metricEntriesPayload(for: .weight),
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
                chartData: generateFullScreenBodyFatChartData(),
                onAdd: {
                    showFullMetricChart = false
                    showAddEntrySheet = true
                },
                metricEntries: metricEntriesPayload(for: .bodyFat),
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
                chartData: generateFullScreenFFMIChartData(),
                onAdd: {
                    showFullMetricChart = false
                    showAddEntrySheet = true
                },
                metricEntries: metricEntriesPayload(for: .ffmi),
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
                let weightResult = metric.weight != nil ?
                    InterpolatedMetric(value: metric.weight!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
                    MetricsInterpolationService.shared.estimateWeight(for: metric.date, metrics: bodyMetrics)

                if let weightData = weightResult {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                        let convertedWeight = convertWeight(weightData.value, to: system) ?? weightData.value
                        let unit = system.weightUnit

                        Text(String(format: "%.1f", convertedWeight))
                            .font(.system(size: 68, weight: .bold))
                            .tracking(-0.5)
                            .foregroundColor(Color.liquidTextPrimary)

                        Text(unit)
                            .font(.system(size: 41, weight: .semibold))  // 60% of 68
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.50))
                            .baselineOffset(-8)

                        if weightData.isInterpolated || weightData.isLastKnown {
                            DSInterpolationIcon(
                                confidenceLevel: weightData.confidenceLevel,
                                isLastKnown: weightData.isLastKnown
                            )
                            .offset(y: -20)  // Align with top of number
                        }
                    }
                }

                // Chips row
                HStack(spacing: 12) {
                    // Body fat chip with interpolation indicator
                    let bodyFatResult = metric.bodyFatPercentage != nil ?
                        InterpolatedMetric(value: metric.bodyFatPercentage!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
                        MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics)

                    if let bodyFatData = bodyFatResult {
                        HStack(spacing: 4) {
                            GlassChip(
                                icon: "flame.fill",
                                text: String(format: "%.1f%% BF", bodyFatData.value),
                                color: .orange
                            )
                            if bodyFatData.isInterpolated || bodyFatData.isLastKnown {
                                DSInterpolationIcon(
                                    confidenceLevel: bodyFatData.confidenceLevel,
                                    isLastKnown: bodyFatData.isLastKnown
                                )
                            }
                        }
                    }

                    // Change chip
                    if let firstEntry = bodyMetrics.last,
                       let lastEntry = bodyMetrics.first,
                       let firstWeight = firstEntry.weight,
                       let lastWeight = lastEntry.weight {
                        let change = lastWeight - firstWeight
                        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                        let convertedChange = convertWeight(abs(change), to: system) ?? abs(change)
                        let unit = system.weightUnit
                        let sign = change > 0 ? "+" : "−"

                        GlassChip(
                            icon: change < 0 ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                            text: String(format: "%@%.1f %@ since %@",
                                       sign,
                                       convertedChange,
                                       unit,
                                       firstEntry.date.formatted(.dateTime.month(.abbreviated).day())),
                            color: change < 0 ? .green : .red
                        )
                    }
                }
            }
        }
    }

    // MARK: - Unified Metrics Card

    private var metricsRow: some View {
        LiquidGlassCard(padding: 16) {
            HStack(spacing: 0) {
                // Weight column
                metricColumn(
                    label: "Weight",
                    value: weightValue,
                    unit: weightUnit,
                    interpolationData: weightInterpolationData,
                    progressBar: AnyView(weightProgressBar(current: animatedWeight, goal: weightGoal, unit: weightUnit))
                )
                .frame(maxWidth: .infinity)

                // Vertical divider
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 80)
                    .padding(.horizontal, 12)

                // Body Fat column
                metricColumn(
                    label: "Body Fat %",
                    value: bodyFatValue,
                    unit: "%",
                    interpolationData: bodyFatInterpolationData,
                    progressBar: AnyView(bodyFatProgressBar(current: animatedBodyFat, goal: bodyFatGoal))
                )
                .frame(maxWidth: .infinity)

                // Vertical divider
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 80)
                    .padding(.horizontal, 12)

                // FFMI column with progress ring
                ffmiColumn
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Metric Column Helper

    private func metricColumn(label: String, value: String, unit: String, interpolationData: (isInterpolated: Bool, isLastKnown: Bool, confidenceLevel: InterpolatedMetric.ConfidenceLevel?)?, progressBar: AnyView? = nil) -> some View {
        VStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.liquidTextPrimary.opacity(0.70))

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color.liquidTextPrimary)
                    .monospacedDigit()

                if let data = interpolationData, (data.isInterpolated || data.isLastKnown) {
                    DSInterpolationIcon(
                        confidenceLevel: data.confidenceLevel,
                        isLastKnown: data.isLastKnown
                    )
                }
            }

            Text(unit)
                .font(.system(size: 13, weight: .medium))  // Standardized: 13pt, medium weight
                .foregroundColor(Color.liquidTextPrimary.opacity(0.70))  // Brighter for readability

            // Progress bar if provided
            if let progressBar = progressBar {
                progressBar
            }
        }
    }

    private var ffmiColumn: some View {
        VStack(alignment: .center, spacing: 6) {
            Text("FFMI")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.liquidTextPrimary.opacity(0.70))

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
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.1f", animatedFFMI))
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(Color.liquidTextPrimary)
                                .monospacedDigit()

                            if ffmiData.isInterpolated || ffmiData.isLastKnown {
                                DSInterpolationIcon(
                                    confidenceLevel: ffmiData.confidenceLevel,
                                    isLastKnown: ffmiData.isLastKnown
                                )
                            }
                        }

                        Text("FFMI")
                            .font(.system(size: 13, weight: .medium))  // Standardized unit styling
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.70))

                        ffmiProgressBar(current: ffmiData.value, goal: ffmiGoal)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.30))
                }
            } else {
                Text("—")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.30))
            }
        }
    }

    // MARK: - Metric Data Computed Properties

    private var weightValue: String {
        guard let metric = currentMetric else { return "—" }
        let weightResult = metric.weight != nil ?
            InterpolatedMetric(value: metric.weight!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
            MetricsInterpolationService.shared.estimateWeight(for: metric.date, metrics: bodyMetrics)
        return weightResult != nil ? String(format: "%.1f", animatedWeight) : "—"
    }

    private var weightUnit: String {
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        return system.weightUnit
    }

    private var weightInterpolationData: (isInterpolated: Bool, isLastKnown: Bool, confidenceLevel: InterpolatedMetric.ConfidenceLevel?)? {
        guard let metric = currentMetric else { return nil }
        let weightResult = metric.weight != nil ?
            InterpolatedMetric(value: metric.weight!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
            MetricsInterpolationService.shared.estimateWeight(for: metric.date, metrics: bodyMetrics)
        return weightResult != nil ? (weightResult!.isInterpolated, weightResult!.isLastKnown, weightResult!.confidenceLevel) : nil
    }

    private var bodyFatValue: String {
        guard let metric = currentMetric else { return "—" }
        let bodyFatResult = metric.bodyFatPercentage != nil ?
            InterpolatedMetric(value: metric.bodyFatPercentage!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
            MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics)
        return bodyFatResult != nil ? String(format: "%.1f", animatedBodyFat) : "—"
    }

    private var bodyFatInterpolationData: (isInterpolated: Bool, isLastKnown: Bool, confidenceLevel: InterpolatedMetric.ConfidenceLevel?)? {
        guard let metric = currentMetric else { return nil }
        let bodyFatResult = metric.bodyFatPercentage != nil ?
            InterpolatedMetric(value: metric.bodyFatPercentage!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
            MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics)
        return bodyFatResult != nil ? (bodyFatResult!.isInterpolated, bodyFatResult!.isLastKnown, bodyFatResult!.confidenceLevel) : nil
    }

    // MARK: - Old Tile Views (deprecated)

    private var weightTile: some View {
        let tileContent = CompactGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Weight")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.85))

                if let metric = currentMetric {
                    let weightResult = metric.weight != nil ?
                        InterpolatedMetric(value: metric.weight!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
                        MetricsInterpolationService.shared.estimateWeight(for: metric.date, metrics: bodyMetrics)

                    if let weightData = weightResult {
                        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                        let unit = system.weightUnit

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", animatedWeight))
                                    .font(.system(size: 28, weight: .bold))
                                    .tracking(-0.3)
                                    .foregroundColor(Color.liquidTextPrimary)
                                    .monospacedDigit()

                                if weightData.isInterpolated || weightData.isLastKnown {
                                    DSInterpolationIcon(
                                        confidenceLevel: weightData.confidenceLevel,
                                        isLastKnown: weightData.isLastKnown
                                    )
                                }
                            }

                            Text(unit)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.liquidTextPrimary.opacity(0.70))

                            weightProgressBar(current: animatedWeight, goal: weightGoal, unit: unit)
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

        // Wrap in NavigationLink if no goal is set
        if weightGoal == nil {
            return AnyView(
                NavigationLink(destination: PreferencesView().environmentObject(authManager)) {
                    tileContent
                }
                .buttonStyle(PlainButtonStyle())
            )
        } else {
            return AnyView(tileContent)
        }
    }

    private var bodyFatTile: some View {
        CompactGlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Body Fat %")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.85))

                if let metric = currentMetric {
                    let bodyFatResult = metric.bodyFatPercentage != nil ?
                        InterpolatedMetric(value: metric.bodyFatPercentage!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
                        MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics)

                    if let bodyFatData = bodyFatResult {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.1f", animatedBodyFat))
                                    .font(.system(size: 28, weight: .bold))
                                    .tracking(-0.3)
                                    .foregroundColor(Color.liquidTextPrimary)
                                    .monospacedDigit()

                                if bodyFatData.isInterpolated || bodyFatData.isLastKnown {
                                    DSInterpolationIcon(
                                        confidenceLevel: bodyFatData.confidenceLevel,
                                        isLastKnown: bodyFatData.isLastKnown
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

    func loadData(loadOnlyNewest: Bool = false) {
        guard let userId = authManager.currentUser?.id else {
            hasLoadedInitialData = true
            return
        }

        // Load body metrics from CoreData (using sync version for compatibility)
        let fetchedMetrics = CoreDataManager.shared.fetchBodyMetricsSync(for: userId)
        let allMetrics = fetchedMetrics
            .compactMap { $0.toBodyMetrics() }
            .sorted { $0.date ?? Date.distantPast > $1.date ?? Date.distantPast }

        if loadOnlyNewest {
            // Load only the newest metric for immediate display
            if let newest = allMetrics.first {
                bodyMetrics = [newest]
                updateAnimatedValues(for: 0)
                hasLoadedInitialData = true

                // Load remaining data in background WITHOUT updating UI
                Task.detached { [allMetrics] in
                    // Wait a moment to ensure UI is displayed
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

                    // Store remaining data silently (will be available on next manual refresh)
                    await MainActor.run {
                        // Only update if we still have just the single newest metric
                        if self.bodyMetrics.count == 1 {
                            self.bodyMetrics = allMetrics
                        }
                    }
                }
            }
        } else {
            // Load all metrics (for manual refresh)
            bodyMetrics = allMetrics

            // Initialize animated values (without animation on first load)
            if !bodyMetrics.isEmpty {
                updateAnimatedValues(for: selectedIndex)
            }
        }

        // Load today's daily metrics (using sync version for compatibility)
        if let todayMetrics = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: Date()) {
            dailyMetrics = todayMetrics.toDailyMetrics()
        }

        if !loadOnlyNewest {
            hasLoadedInitialData = true
        }
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
                InterpolatedMetric(value: metric.weight!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
                MetricsInterpolationService.shared.estimateWeight(for: metric.date, metrics: bodyMetrics) {
                let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                animatedWeight = convertWeight(weightResult.value, to: system) ?? weightResult.value
            }

            // Body Fat
            if let bodyFatResult = metric.bodyFatPercentage != nil ?
                InterpolatedMetric(value: metric.bodyFatPercentage!, isInterpolated: false, isLastKnown: false, confidenceLevel: nil) :
                MetricsInterpolationService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics) {
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

    func handlePhotoCapture(_ image: UIImage) async {
        // Copy from DashboardView
    }

    func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        // Copy from DashboardView
    }

    // MARK: - Metrics View Helpers

    private func formatSteps(_ steps: Int?) -> String {
        guard let steps = steps else { return "–" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
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
        let primaryFormatter = makeMetricFormatter(minFractionDigits: 0, maxFractionDigits: 1)
        let secondaryFormatter = makeMetricFormatter(minFractionDigits: 0, maxFractionDigits: 1)

        let entries = bodyMetrics
            .sorted { $0.date > $1.date }
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
        let primaryFormatter = makeMetricFormatter(minFractionDigits: 1, maxFractionDigits: 1)
        let secondaryFormatter = makeMetricFormatter(minFractionDigits: 0, maxFractionDigits: 1)

        let entries = bodyMetrics
            .sorted { $0.date > $1.date }
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

        let formatter = makeMetricFormatter(minFractionDigits: 1, maxFractionDigits: 1)

        let entries = bodyMetrics
            .sorted { $0.date > $1.date }
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
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
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
        guard let userId = authManager.currentUser?.id else { return [] }

        // Get last 7 days of step data
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var chartData: [MetricDataPoint] = []

        for offset in stride(from: 6, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                continue
            }

            if let dailyData = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: date) {
                let steps = Int(dailyData.steps)
                chartData.append(MetricDataPoint(index: 6 - offset, value: Double(max(steps, 0))))
            } else {
                chartData.append(MetricDataPoint(index: 6 - offset, value: 0))
            }
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

        // Look back up to 30 days for the latest non-zero steps entry
        for offset in 0..<30 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if let dailyData = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: date),
               dailyData.steps > 0 {
                return (Int(dailyData.steps), date)
            }
        }

        // Fallback to in-memory dailyMetrics if we didn't find anything
        if let metrics = dailyMetrics {
            return (metrics.steps, metrics.date)
        }

        return (nil, nil)
    }

    private func generateWeightChartData() -> [MetricDataPoint] {
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        return filteredBodyMetrics(for: selectedRange).enumerated().compactMap { index, metric in
            guard let weight = metric.weight else { return nil }
            let converted = convertWeight(weight, to: system) ?? weight
            return MetricDataPoint(index: index, value: converted)
        }
    }

    private func generateBodyFatChartData() -> [MetricDataPoint] {
        filteredBodyMetrics(for: selectedRange).enumerated().compactMap { index, metric in
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

        return filteredBodyMetrics(for: selectedRange).enumerated().compactMap { index, metric in
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

    private func filteredBodyMetrics(for range: TimeRange) -> [BodyMetrics] {
        let sortedMetrics = bodyMetrics.sorted { $0.date < $1.date }

        guard let days = range.days else {
            return sortedMetrics
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sortedMetrics.filter { $0.date >= cutoffDate }
    }

    private func weightRangeStats() -> MetricRangeStats? {
        let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
        return computeRangeStats(metrics: filteredBodyMetrics(for: selectedRange)) { metric in
            guard let weight = metric.weight else { return nil }
            return convertWeight(weight, to: system) ?? weight
        }
    }

    private func bodyFatRangeStats() -> MetricRangeStats? {
        computeRangeStats(metrics: filteredBodyMetrics(for: selectedRange)) { metric in
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

        return computeRangeStats(metrics: filteredBodyMetrics(for: selectedRange)) { metric in
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

        return bodyMetrics
            .sorted { $0.date < $1.date }
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

        return bodyMetrics
            .sorted { $0.date < $1.date }
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

// MARK: - Full Metric Chart View Component

private enum TimeRange: String, CaseIterable {
    case week1 = "1W"
    case month1 = "1M"
    case month3 = "3M"
    case month6 = "6M"
    case year1 = "1Y"
    case all = "All"

    /// Approximate length of the range in days for filtering.
    /// `.all` returns nil to indicate the full available history should be shown.
    var days: Int? {
        switch self {
        case .week1:
            return 7
        case .month1:
            return 30
        case .month3:
            return 90
        case .month6:
            return 180
        case .year1:
            return 365
        case .all:
            return nil
        }
    }
}

private struct MetricChartDataPoint: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let value: Double
    var isEstimated: Bool = false
}

private struct ChartSeriesPreprocessor {
    let referenceDate: Date
    private let calendar = Calendar.current

    func seriesByRange(from points: [MetricChartDataPoint]) -> [TimeRange: [MetricChartDataPoint]] {
        guard !points.isEmpty else { return [:] }

        let sorted = points.sorted { $0.date < $1.date }
        var result: [TimeRange: [MetricChartDataPoint]] = [:]

        for range in TimeRange.allCases {
            let filtered = filter(sorted, for: range)
            result[range] = downsampleIfNeeded(filtered, limit: maxPointCount(for: range))
        }

        return result
    }

    private func filter(_ points: [MetricChartDataPoint], for range: TimeRange) -> [MetricChartDataPoint] {
        guard let days = range.days else {
            return points
        }

        let cutoff = calendar.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        return points.filter { $0.date >= cutoff }
    }

    private func maxPointCount(for range: TimeRange) -> Int {
        switch range {
        case .week1:
            return 140
        case .month1:
            return 180
        case .month3:
            return 210
        case .month6:
            return 240
        case .year1:
            return 260
        case .all:
            return 320
        }
    }

    private func downsampleIfNeeded(_ points: [MetricChartDataPoint], limit: Int) -> [MetricChartDataPoint] {
        guard points.count > limit, limit >= 3 else { return points }
        return largestTriangleThreeBuckets(points: points, threshold: limit)
    }

    private func largestTriangleThreeBuckets(points: [MetricChartDataPoint], threshold: Int) -> [MetricChartDataPoint] {
        guard threshold < points.count else { return points }

        let dataCount = points.count
        let bucketSize = Double(dataCount - 2) / Double(threshold - 2)

        var sampled: [MetricChartDataPoint] = [points[0]]
        var aIndex = 0

        for bucket in 0..<(threshold - 2) {
            let rangeStart = Int(floor(Double(bucket) * bucketSize)) + 1
            var rangeEnd = Int(floor(Double(bucket + 1) * bucketSize)) + 1
            rangeEnd = min(rangeEnd, dataCount - 1)

            let avgRangeStart = Int(floor(Double(bucket + 1) * bucketSize)) + 1
            var avgRangeEnd = Int(floor(Double(bucket + 2) * bucketSize)) + 1
            avgRangeEnd = min(avgRangeEnd, dataCount)

            let average = averagedPoint(points, start: avgRangeStart, end: avgRangeEnd)

            if rangeStart >= rangeEnd {
                continue
            }

            let ax = timeValue(points[aIndex])
            let ay = points[aIndex].value

            var maxArea: Double = -1
            var selectedIndex = rangeStart

            for index in rangeStart..<rangeEnd {
                let bx = timeValue(points[index])
                let by = points[index].value
                let cx = average.x
                let cy = average.y

                let area = abs((ax * (by - cy) + bx * (cy - ay) + cx * (ay - by)) * 0.5)

                if area > maxArea {
                    maxArea = area
                    selectedIndex = index
                }
            }

            sampled.append(points[selectedIndex])
            aIndex = selectedIndex
        }

        sampled.append(points.last!)
        return sampled
    }

    private func averagedPoint(_ points: [MetricChartDataPoint], start: Int, end: Int) -> (x: Double, y: Double) {
        guard !points.isEmpty else { return (0, 0) }

        let safeStart = min(max(start, 0), points.count - 1)
        let safeEndExclusive = max(min(end, points.count), safeStart + 1)

        if safeStart >= safeEndExclusive {
            let point = points[safeStart]
            return (timeValue(point), point.value)
        }

        var sumX: Double = 0
        var sumY: Double = 0
        let count = safeEndExclusive - safeStart

        for index in safeStart..<safeEndExclusive {
            let point = points[index]
            sumX += timeValue(point)
            sumY += point.value
        }

        return (sumX / Double(count), sumY / Double(count))
    }

    private func timeValue(_ point: MetricChartDataPoint) -> Double {
        point.date.timeIntervalSince1970
    }
}

private enum MetricEntrySourceType: Equatable {
    case manual
    case healthKit
    case integration(id: String?)
}

private struct MetricHistoryEntry: Identifiable {
    let id: String
    let date: Date
    let primaryValue: Double
    let secondaryValue: Double?
    let source: MetricEntrySourceType
}

private struct MetricEntriesConfiguration {
    let metricType: DashboardViewLiquid.MetricType
    let unitLabel: String
    let secondaryUnitLabel: String?
    let primaryFormatter: NumberFormatter
    let secondaryFormatter: NumberFormatter?
}

private struct MetricEntriesPayload {
    let config: MetricEntriesConfiguration
    let entries: [MetricHistoryEntry]
}

private func makeMetricFormatter(minFractionDigits: Int = 0, maxFractionDigits: Int = 1) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = minFractionDigits
    formatter.maximumFractionDigits = maxFractionDigits
    return formatter
}

private struct FullMetricChartView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let icon: String
    let iconColor: Color
    let currentValue: String
    let unit: String
    let currentDate: String
    let chartData: [MetricChartDataPoint]
    let onAdd: () -> Void
    let metricEntries: MetricEntriesPayload?

    @Binding var selectedTimeRange: TimeRange
    @State private var selectedDate: Date?
    @State private var selectedPoint: MetricChartDataPoint?
    @State private var isLoadingData: Bool = false
    @State private var edgeDragOffset: CGFloat = 0
    @State private var cachedSeries: [TimeRange: [MetricChartDataPoint]] = [:]
    @State private var preprocessingTask: Task<[TimeRange: [MetricChartDataPoint]], Never>?

    var body: some View {
        ZStack {
            // Background
            Color.black
            // ...
        }
        // ...
        let index = Int(percentage * CGFloat(filteredChartData.count - 1))
        let clampedIndex = max(0, min(filteredChartData.count - 1, index))

        return filteredChartData[clampedIndex]
    }

    private var chartDataFingerprint: String {
        guard let first = chartData.first, let last = chartData.last else {
            return "empty-\(chartData.count)"
        }

        return "\(chartData.count)-\(first.date.timeIntervalSince1970)-\(last.date.timeIntervalSince1970)-\(first.value)-\(last.value)"
    }

    private func preprocessChartData() async {
        guard !chartData.isEmpty else {
            await MainActor.run {
                cachedSeries = [:]
                isLoadingData = false
            }
            return
        }

        await MainActor.run {
            isLoadingData = true
            cachedSeries = [:]
        }

        preprocessingTask?.cancel()

        let sourceData = chartData
        let referenceDate = Date()

        let task = Task<[TimeRange: [MetricChartDataPoint]], Never>.detached(priority: .userInitiated) {
            let preprocessor = ChartSeriesPreprocessor(referenceDate: referenceDate)
            return preprocessor.seriesByRange(from: sourceData)
        }

        preprocessingTask = task

        let series = await task.value

        guard !task.isCancelled else { return }

        await MainActor.run {
            cachedSeries = series
            isLoadingData = false
            selectedDate = nil
            selectedPoint = nil
        }
    }
}

// MARK: - Metrics Order Persistence

extension DashboardViewLiquid {
    func loadMetricsOrder() {
        // ...

        do {
            let decoder = JSONDecoder()
            let loadedOrder = try decoder.decode([MetricIdentifier].self, from: metricsOrderData)
            metricsOrder = loadedOrder
        } catch {
        // print("Failed to load metrics order: \(error)")
            // Keep default order
        }
    }

    func saveMetricsOrder() {
        do {
            let encoder = JSONEncoder()
            metricsOrderData = try encoder.encode(metricsOrder)

            // Haptic feedback for successful reorder
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
        // print("Failed to save metrics order: \(error)")
        }
    }
}

// MARK: - Metric Drop Delegate

struct MetricDropDelegate: DropDelegate {
    let metric: DashboardViewLiquid.MetricIdentifier
    @Binding var metrics: [DashboardViewLiquid.MetricIdentifier]
    @Binding var draggedMetric: DashboardViewLiquid.MetricIdentifier?
    let onReorder: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedMetric = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedMetric = draggedMetric,
              draggedMetric != metric,
              let fromIndex = metrics.firstIndex(of: draggedMetric),
              let toIndex = metrics.firstIndex(of: metric) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            metrics.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // Optional: Add visual feedback when drag exits
    }
}

#Preview {
    DashboardViewLiquid()
        .environmentObject(AuthManager.shared)
        .environmentObject(RealtimeSyncManager.shared)
}
