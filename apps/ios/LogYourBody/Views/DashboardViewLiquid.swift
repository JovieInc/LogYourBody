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

enum DisplayMode {
    case photo
    case metrics
}

struct MetricDataPoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
}

struct DashboardViewLiquid: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var syncManager: SyncManager
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

    // Animated metric values for tweening
    @State private var animatedWeight: Double = 0
    @State private var animatedBodyFat: Double = 0
    @State private var animatedFFMI: Double = 0

    // Goals - Optional values, nil means use gender-based default
    @AppStorage("stepGoal") var stepGoal: Int = 10000
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
                    // Main content
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            // 1. Compact header (user info + status)
                            compactHeader
                                .padding(.horizontal, 20)

                            // 2. Display mode toggle (Photo / Metrics)
                            displayModeToggle
                                .padding(.horizontal, 20)
                                .padding(.top, 8)

                            // 3. Hero Card (Photo or Metrics view)
                            if let metric = currentMetric {
                                heroCard(metric: metric)
                                    .padding(.horizontal, 20)
                            }

                            // 4. Timeline (only in photo mode)
                            if displayMode == .photo {
                                timelineScrubber
                            }

                            // 5. Primary Metric Card (only in photo mode)
                            if displayMode == .photo, let metric = currentMetric {
                                primaryMetricCard(metric: metric)
                                    .padding(.horizontal, 20)
                            }

                            // 6. Metrics Row (only in photo mode)
                            if displayMode == .photo {
                                metricsRow
                                    .padding(.horizontal, 20)
                            }

                            Spacer(minLength: 80) // Tab bar clearance
                        }
                        .padding(.top, 8)
                    }
                    .refreshable {
                        await refreshData()
                    }
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
        .fullScreenCover(isPresented: $showFullMetricChart) {
            fullMetricChartView
        }
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Avatar button - Opens settings
            NavigationLink(destination: PreferencesView()) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                        .frame(width: 44, height: 44)  // Increased tap target from 36 to 44

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
                                    .font(.system(size: 18, weight: .medium))  // Slightly larger icon
                                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                            @unknown default:
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18, weight: .medium))  // Slightly larger icon
                                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                            }
                        }
                        .frame(width: 44, height: 44)  // Increased from 36 to 44
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .medium))  // Slightly larger icon
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            Spacer(minLength: 8)

            // Sync status pill
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Synced just now")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.50))  // Reduced from 0.70 to 0.50
                    .lineLimit(1)
                Text("·")
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.3))
                Text("Works offline")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.50))  // Reduced from 0.70 to 0.50
                    .lineLimit(1)
            }
            .fixedSize()
        }
    }

    // Computed properties for user info
    private var userName: String {
        if let fullName = authManager.currentUser?.profile?.fullName, !fullName.isEmpty {
            // Extract first name from full name
            return fullName.components(separatedBy: " ").first ?? fullName
        } else if let username = authManager.currentUser?.profile?.username {
            return username
        } else if let name = authManager.currentUser?.name {
            return name
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

    private var userAge: Int {
        authManager.currentUser?.profile?.age ?? 0
    }

    // MARK: - Display Mode Toggle

    private var displayModeToggle: some View {
        HStack(spacing: 0) {
            // Photo button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    displayMode = .photo
                }
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("Photo")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(displayMode == .photo ? .white : Color.liquidTextPrimary.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    displayMode == .photo ?
                        Color.appPrimary :
                        Color.clear
                )
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())

            // Metrics button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    displayMode = .metrics
                }
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14, weight: .medium))
                    Text("Metrics")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(displayMode == .metrics ? .white : Color.liquidTextPrimary.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    displayMode == .metrics ?
                        Color.appPrimary :
                        Color.clear
                )
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
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
                        let _ = print("[Dashboard] Image load failed: \(error.localizedDescription), URL: \(photoUrl)")
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
        VStack(spacing: 20) {
            ForEach(metricsOrder) { metricId in
                metricCardView(for: metricId)
                    .scaleEffect(draggedMetric == metricId ? 1.05 : 1.0)
                    .opacity(draggedMetric == metricId ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: draggedMetric)
                    .onDrag {
                        withAnimation(.easeInOut(duration: 0.2)) {
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
                MetricSummaryCard(
                    icon: "flame.fill",
                    iconColor: .orange,
                    label: "Steps",
                    value: formatSteps(dailyMetrics?.steps),
                    unit: "steps",
                    timestamp: formatTime(dailyMetrics?.updatedAt),
                    chartData: generateStepsChartData()
                )
            }
            .buttonStyle(PlainButtonStyle())

        case .weight:
            if let currentMetric = currentMetric {
                Button {
                    selectedMetricType = .weight
                    showFullMetricChart = true
                } label: {
                    MetricSummaryCard(
                        icon: "figure.stand",
                        iconColor: .purple,
                        label: "Weight",
                        value: formatWeightValue(currentMetric.weight),
                        unit: weightUnit,
                        timestamp: formatTime(currentMetric.date),
                        chartData: generateWeightChartData()
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

        case .bodyFat:
            if let currentMetric = currentMetric {
                Button {
                    selectedMetricType = .bodyFat
                    showFullMetricChart = true
                } label: {
                    MetricSummaryCard(
                        icon: "percent",
                        iconColor: .purple,
                        label: "Body Fat Percentage",
                        value: formatBodyFatValue(currentMetric.bodyFatPercentage),
                        unit: "%",
                        timestamp: formatTime(currentMetric.date),
                        chartData: generateBodyFatChartData()
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

        case .ffmi:
            if let currentMetric = currentMetric {
                Button {
                    selectedMetricType = .ffmi
                    showFullMetricChart = true
                } label: {
                    MetricSummaryCard(
                        icon: "figure.arms.open",
                        iconColor: .purple,
                        label: "Fat Free Mass Index",
                        value: formatFFMIValue(currentMetric),
                        unit: "",
                        timestamp: formatTime(currentMetric.date),
                        chartData: generateFFMIChartData()
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
                }
            )

        case .weight:
            FullMetricChartView(
                title: "Weight",
                icon: "figure.stand",
                iconColor: .purple,
                currentValue: currentMetric.flatMap { formatWeightValue($0.weight) } ?? "–",
                unit: weightUnit,
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: generateWeightChartData().map { point in
                    MetricChartDataPoint(date: bodyMetrics[safe: point.index]?.date ?? Date(), value: point.value)
                },
                onAdd: {
                    showFullMetricChart = false
                    showAddEntrySheet = true
                }
            )

        case .bodyFat:
            FullMetricChartView(
                title: "Body Fat %",
                icon: "percent",
                iconColor: .purple,
                currentValue: currentMetric.flatMap { formatBodyFatValue($0.bodyFatPercentage) } ?? "–",
                unit: "%",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: generateBodyFatChartData().map { point in
                    MetricChartDataPoint(date: bodyMetrics[safe: point.index]?.date ?? Date(), value: point.value)
                },
                onAdd: {
                    showFullMetricChart = false
                    showAddEntrySheet = true
                }
            )

        case .ffmi:
            FullMetricChartView(
                title: "FFMI",
                icon: "figure.arms.open",
                iconColor: .purple,
                currentValue: currentMetric.map { formatFFMIValue($0) } ?? "–",
                unit: "",
                currentDate: formatDate(currentMetric?.date ?? Date()),
                chartData: generateFFMIChartData().map { point in
                    MetricChartDataPoint(date: bodyMetrics[safe: point.index]?.date ?? Date(), value: point.value)
                },
                onAdd: {
                    showFullMetricChart = false
                    showAddEntrySheet = true
                }
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
                print("HealthKit sync error during refresh: \(error)")
                hasErrors = true
            }
        }

        // Upload local changes to Supabase
        syncManager.syncAll()

        // Download remote changes from Supabase (cross-device sync)
        await syncManager.downloadRemoteChanges()

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
        syncManager.syncAll()
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
        return String(format: "%.1f", converted)
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
            return String(format: "%.1f", ffmiResult.value)
        }
        return "–"
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

    private func generateStepsChartData() -> [MetricDataPoint] {
        guard let userId = authManager.currentUser?.id else { return [] }

        // Get last 7 days of step data
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).compactMap { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return nil
            }

            // Fetch daily metrics for this date (using sync version for compatibility)
            if let dailyData = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: date) {
                let steps = dailyData.steps
                if steps > 0 {
                    return MetricDataPoint(index: 6 - daysAgo, value: Double(steps))
                }
            }

            return nil
        }.reversed()
    }

    private func generateWeightChartData() -> [MetricDataPoint] {
        // Get last 6-7 weight entries
        let recentMetrics = bodyMetrics.prefix(7)
        return recentMetrics.enumerated().compactMap { index, metric in
            guard let weight = metric.weight else { return nil }
            let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
            let converted = convertWeight(weight, to: system) ?? weight
            return MetricDataPoint(index: index, value: converted)
        }
    }

    private func generateBodyFatChartData() -> [MetricDataPoint] {
        // Get last 6-7 body fat entries
        let recentMetrics = bodyMetrics.prefix(7)
        return recentMetrics.enumerated().compactMap { index, metric in
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

        let recentMetrics = bodyMetrics.prefix(7)
        return recentMetrics.enumerated().compactMap { index, metric in
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
}

// MARK: - MetricSummaryCard

/// A card displaying a metric summary with inline trend chart, inspired by Apple Health
private struct MetricSummaryCard: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let unit: String
    let timestamp: String?
    let chartData: [MetricDataPoint]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        }
        .overlay(
            VStack(alignment: .leading, spacing: 12) {
                // TOP ROW: label + time
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.caption)
                        Text(label)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(iconColor)

                    Spacer()

                    if let time = timestamp {
                        Text(time)
                            .font(.caption)
                            .foregroundColor(Color(.secondaryLabel))
                    }
                }

                // MIDDLE ROW: value + unit
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 34, weight: .bold, design: .default))
                        .foregroundColor(Color(.label))

                    Text(unit)
                        .font(.subheadline)
                        .foregroundColor(Color(.secondaryLabel))
                }

                // BOTTOM ROW: graph
                HStack {
                    Spacer()

                    // Inline Chart
                    if !chartData.isEmpty {
                        Chart {
                            ForEach(chartData) { point in
                                LineMark(
                                    x: .value("Index", point.index),
                                    y: .value("Value", point.value)
                                )
                                .foregroundStyle(iconColor.gradient)
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(width: 120, height: 40)
                    }
                }
            }
            .padding(16)
        )
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

// MARK: - Array Extension for Safe Access

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Full Metric Chart View Component

private enum TimeRange: String, CaseIterable {
    case day = "D"
    case week = "W"
    case month = "M"
    case sixMonths = "6M"
    case year = "Y"

    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .sixMonths: return 180
        case .year: return 365
        }
    }
}

private struct MetricChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    var isEstimated: Bool = false
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

    @State private var selectedTimeRange: TimeRange = .week
    @State private var selectedDate: Date?
    @State private var selectedPoint: MetricChartDataPoint?
    @State private var isLoadingData: Bool = false

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Navigation bar
                navigationBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)

                // Time range selector
                timeRangeSelector
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                // Current value display
                currentValueDisplay
                    .padding(.bottom, 24)

                // Chart
                chartView
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                Spacer()
            }
        }
        .navigationBarHidden(true)
    }

    private var navigationBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1), in: Circle())
            }

            Spacer()

            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            Spacer()

            Button {
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
        }
    }

    private var timeRangeSelector: some View {
        HStack(spacing: 0) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTimeRange = range
                    }
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                } label: {
                    Text(range.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selectedTimeRange == range ? .black : .white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            selectedTimeRange == range ?
                                Color.white.opacity(0.9) :
                                Color.clear
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
    }

    private var currentValueDisplay: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(displayValue)
                    .font(.system(size: 68, weight: .bold))
                    .foregroundColor(.white)

                Text(unit)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }

            HStack(spacing: 8) {
                Text(displayDate)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))

                // Show "Estimated" badge when displaying estimated data
                if let point = selectedPoint, point.isEstimated {
                    Text("Estimated")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.15))
                        )
                }
            }
        }
    }

    // Computed properties for display value and date (selected or current)
    private var displayValue: String {
        if let point = selectedPoint {
            return String(format: "%.1f", point.value)
        }
        return currentValue
    }

    private var displayDate: String {
        if let point = selectedPoint {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: point.date)
        }
        return currentDate
    }

    private var chartView: some View {
        VStack {
            if isLoadingData {
                loadingState
            } else if filteredChartData.isEmpty {
                emptyState
            } else {
                Chart {
                    ForEach(filteredChartData) { point in
                        // Area fill gradient (render first, below the line)
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    iconColor.opacity(point.isEstimated ? 0.15 : 0.3),
                                    iconColor.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)

                        // Line (dotted for estimated data)
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(iconColor.gradient)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(
                            lineWidth: 3,
                            dash: point.isEstimated ? [8, 4] : []
                        ))
                        .opacity(point.isEstimated ? 0.7 : 1.0)

                        // Points (smaller, subtle, only show when scrubbing)
                        if selectedDate != nil {
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle(iconColor)
                            .symbolSize(30)
                            .opacity(0.5)
                        }
                    }

                    // Vertical scrubber line
                    if let selectedDate = selectedDate,
                       let selectedPoint = selectedPoint {
                        RuleMark(x: .value("Selected", selectedDate))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))

                        // Highlight selected point
                        PointMark(
                            x: .value("Date", selectedPoint.date),
                            y: .value("Value", selectedPoint.value)
                        )
                        .foregroundStyle(Color.white)
                        .symbolSize(120)
                        .symbol {
                            Circle()
                                .fill(iconColor)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: 3)
                                )
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .automatic(desiredCount: 7)) { value in
                        // Grid lines hidden by default (Apple Health style)
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(formatAxisDate(date))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .aligned, position: .trailing, values: .automatic(desiredCount: 5)) { value in
                        // Grid lines hidden by default (Apple Health style)
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formatAxisValue(doubleValue))
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.clear)
                }
                .frame(height: 360)
                .chartAngleSelection(value: $selectedDate)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Find nearest point to drag location
                            if let point = findNearestPoint(to: value.location) {
                                selectedDate = point.date
                                selectedPoint = point

                                // Haptic feedback
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        }
                        .onEnded { _ in
                            // Clear selection after a delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation {
                                    selectedDate = nil
                                    selectedPoint = nil
                                }
                            }
                        }
                )
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Loading chart data...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(height: 360)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))

            Text("No data for this period")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(height: 360)
    }

    private var filteredChartData: [MetricChartDataPoint] {
        let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -selectedTimeRange.days,
            to: Date()
        ) ?? Date()

        return chartData
            .filter { $0.date >= cutoffDate }
            .sorted { $0.date < $1.date }
    }

    private func formatAxisDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedTimeRange {
        case .day:
            formatter.dateFormat = "ha"
        case .week:
            formatter.dateFormat = "EEE"
        case .month:
            formatter.dateFormat = "d"
        case .sixMonths, .year:
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }

    private func formatAxisValue(_ value: Double) -> String {
        return String(format: "%.0f", value)
    }

    private func findNearestPoint(to location: CGPoint) -> MetricChartDataPoint? {
        guard !filteredChartData.isEmpty else { return nil }

        // Simple implementation: find point closest in time based on X position
        // The chart width corresponds to the time range
        let chartWidth: CGFloat = UIScreen.main.bounds.width - 40 // accounting for padding

        guard chartWidth > 0 else { return nil }

        let xPosition = location.x
        let percentage = max(0, min(1, xPosition / chartWidth))

        let index = Int(percentage * CGFloat(filteredChartData.count - 1))
        let clampedIndex = max(0, min(filteredChartData.count - 1, index))

        return filteredChartData[clampedIndex]
    }
}

// MARK: - Metrics Order Persistence

extension DashboardViewLiquid {
    func loadMetricsOrder() {
        guard !metricsOrderData.isEmpty else { return }

        do {
            let decoder = JSONDecoder()
            let loadedOrder = try decoder.decode([MetricIdentifier].self, from: metricsOrderData)
            metricsOrder = loadedOrder
        } catch {
            print("Failed to load metrics order: \(error)")
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
            print("Failed to save metrics order: \(error)")
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
        .environmentObject(SyncManager.shared)
}
