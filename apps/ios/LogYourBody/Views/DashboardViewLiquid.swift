//
//  DashboardViewLiquid.swift
//  LogYourBody
//
//  Redesigned dashboard with liquid glass aesthetic
//  Layout: Greeting → Hero Card → Primary Metric → 2×2 Grid → Quick Actions
//

import SwiftUI
import PhotosUI

struct DashboardViewLiquid: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var syncManager: SyncManager
    let healthKitManager = HealthKitManager.shared

    // Core data state
    @State var dailyMetrics: DailyMetrics?
    @State var bodyMetrics: [BodyMetrics] = []
    @State var selectedIndex: Int = 0
    @State var hasLoadedInitialData = false

    // UI state
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var displayMode: DisplayMode = .photo
    @State private var animatingPlaceholder = false
    @State private var showAddEntrySheet = false

    // Animated metric values for tweening
    @State private var animatedWeight: Double = 0
    @State private var animatedBodyFat: Double = 0
    @State private var animatedFFMI: Double = 0

    enum DisplayMode {
        case photo
        case wireframe
    }

    // Goals
    @AppStorage("stepGoal") var stepGoal: Int = 10000
    @AppStorage("ffmiGoal") var ffmiGoal: Double = 22.0

    // Preferences
    @AppStorage(Constants.preferredMeasurementSystemKey)
    var measurementSystem = PreferencesView.defaultMeasurementSystem

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
        NavigationView {
            ZStack {
                // Background - True black for OLED
                Color.liquidBg
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
                        VStack(spacing: 20) {
                            // 1. Compact header (user info + status + toggle)
                            compactHeader

                            // 2. Hero Progress Card
                            if let metric = currentMetric {
                                heroCard(metric: metric)
                            }

                            // 3. Timeline Scrubber
                            timelineScrubber
                                .padding(.horizontal, 16)

                            // 4. Visual Divider
                            visualDivider
                                .padding(.top, 8)

                            // 5. Metrics Row (3 tiles: Weight, Body Fat %, FFMI)
                            metricsRow

                            Spacer(minLength: 100) // Tab bar clearance
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            // Load data immediately to prevent loading spinner
            loadData()

            // Then refresh async
            Task {
                await refreshData()
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
                        .frame(width: 36, height: 36)

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
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                            @unknown default:
                                Image(systemName: "person.fill")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .medium))
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
                Text("Just now")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.70))
                    .lineLimit(1)
                Text("·")
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.3))
                Text("Offline OK")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.70))
                    .lineLimit(1)
            }
            .fixedSize()

            // Compact icon-only toggle
            compactToggle
        }
    }

    // MARK: - Compact Icon-Only Toggle

    private var compactToggle: some View {
        HStack(spacing: 0) {
            // Photo button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.28)) {
                    displayMode = .photo
                }
            }) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(displayMode == .photo ? Color(hex: "#6EE7F0") : .white.opacity(0.5))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())

            // Wireframe button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.28)) {
                    displayMode = .wireframe
                }
            }) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(displayMode == .wireframe ? Color(hex: "#6EE7F0") : .white.opacity(0.5))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background {
            // Sliding indicator
            GeometryReader { geometry in
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color(hex: "#6EE7F0").opacity(0.3), lineWidth: 1)
                    )
                    .frame(width: geometry.size.width / 2, height: 32)
                    .offset(x: displayMode == .photo ? 0 : geometry.size.width / 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayMode)
            }
        }
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .frame(width: 64, height: 32)
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
            .frame(height: 400)
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
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 400)
                            .clipped()
                    } else {
                        noPhotoPlaceholder
                    }
                }
            } else {
                noPhotoPlaceholder
            }
        }
    }

    private func heroCard(metric: BodyMetrics) -> some View {
        HeroGlassCard {
            VStack(spacing: 0) {
                // Photo/Wireframe based on display mode
                TabView(selection: $selectedIndex) {
                    ForEach(Array(bodyMetrics.enumerated()), id: \.element.id) { index, m in
                        ZStack(alignment: .topTrailing) {
                            if displayMode == .photo {
                                photoContent(for: m)
                            } else {
                                AvatarBodyRenderer(
                                    bodyFatPercentage: m.bodyFatPercentage,
                                    gender: authManager.currentUser?.profile?.gender,
                                    height: 400
                                )
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 400)
                .animation(.easeInOut(duration: 0.28), value: displayMode)
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
    }

    // MARK: - Timeline Scrubber (Standalone)

    private var timelineScrubber: some View {
        Group {
            if bodyMetrics.count > 1 {
                PhotoAnchoredTimelineSlider(
                    metrics: bodyMetrics,
                    selectedIndex: $selectedIndex,
                    accentColor: Color(hex: "#6EE7F0")
                )
                .frame(height: 50)
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
        LiquidGlassCard(padding: 20) {
            HStack(spacing: 0) {
                // Weight column
                metricColumn(
                    label: "Weight",
                    value: weightValue,
                    unit: weightUnit,
                    interpolationData: weightInterpolationData
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
                    interpolationData: bodyFatInterpolationData
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

    private func metricColumn(label: String, value: String, unit: String, interpolationData: (isInterpolated: Bool, isLastKnown: Bool, confidenceLevel: InterpolatedMetric.ConfidenceLevel?)?) -> some View {
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
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color.liquidTextPrimary.opacity(0.60))
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

                        ffmiProgressRing(current: ffmiData.value, goal: ffmiGoal)
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
        CompactGlassCard {
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

                        VStack(alignment: .leading, spacing: 2) {
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
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color.liquidTextPrimary.opacity(0.70))
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
                        VStack(alignment: .leading, spacing: 2) {
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
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(Color.liquidTextPrimary.opacity(0.50))
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
                        ffmiProgressRing(current: ffmiData.value, goal: ffmiGoal)
                    }
                }
            }
        }
    }

    // MARK: - FFMI Progress Ring

    private func ffmiProgressRing(current: Double, goal: Double) -> some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 2.5)
                .frame(width: 36, height: 36)

            // Progress ring
            Circle()
                .trim(from: 0, to: min(current / goal, 1.0))
                .stroke(
                    Color(hex: "#6EE7F0"),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: 36, height: 36)
                .rotationEffect(.degrees(-90))
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

    func loadData() {
        guard let userId = authManager.currentUser?.id else {
            hasLoadedInitialData = true
            return
        }

        // Load body metrics from CoreData
        let fetchedMetrics = CoreDataManager.shared.fetchBodyMetrics(for: userId)
        bodyMetrics = fetchedMetrics
            .compactMap { $0.toBodyMetrics() }
            .sorted { $0.date ?? Date.distantPast > $1.date ?? Date.distantPast }

        // Load today's daily metrics
        if let todayMetrics = CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date()) {
            dailyMetrics = todayMetrics.toDailyMetrics()
        }

        // Initialize animated values (without animation on first load)
        if !bodyMetrics.isEmpty {
            updateAnimatedValues(for: selectedIndex)
        }

        hasLoadedInitialData = true
    }

    func refreshData() async {
        // Sync steps from HealthKit if authorized
        if healthKitManager.isAuthorized {
            await syncStepsFromHealthKit()
        }

        // Sync with remote
        syncManager.syncAll()

        // Wait a bit for sync
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Reload from cache
        await MainActor.run {
            loadData()
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

        if let existingMetrics = CoreDataManager.shared.fetchDailyMetrics(for: userId, date: today) {
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
}

#Preview {
    DashboardViewLiquid()
        .environmentObject(AuthManager.shared)
        .environmentObject(SyncManager.shared)
}
