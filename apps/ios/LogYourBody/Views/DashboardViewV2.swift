//
// DashboardViewV2.swift
// LogYourBody
//
import SwiftUI
import HealthKit
import PhotosUI

struct DashboardViewV2: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var syncManager: SyncManager
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var dailyMetrics: DailyMetrics?
    @State private var selectedDateMetrics: DailyMetrics?
    @State private var bodyMetrics: [BodyMetrics] = []
    @State private var selectedIndex: Int = 0
    @State private var isLoading = false
    @State private var refreshID = UUID()
    @State private var showPhotoOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showingModal = false
    @Namespace private var namespace
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem
    
    var currentSystem: PreferencesView.MeasurementSystem {
        PreferencesView.MeasurementSystem(rawValue: measurementSystem) ?? .imperial
    }
    
    var currentMetric: BodyMetrics? {
        guard !bodyMetrics.isEmpty && selectedIndex >= 0 && selectedIndex < bodyMetrics.count else { return nil }
        return bodyMetrics[selectedIndex]
    }
    
    var userAge: Int? {
        guard let dateOfBirth = authManager.currentUser?.profile?.dateOfBirth else { return nil }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dateOfBirth, to: Date())
        return ageComponents.year
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.appBackground
                .ignoresSafeArea()
            
            if isLoading && bodyMetrics.isEmpty {
                loadingView
            } else if bodyMetrics.isEmpty {
                emptyStateView
            } else {
                // Main content with unified header
                VStack(spacing: 0) {
                    // Unified Glass Header with Avatar & Stats
                    unifiedHeaderView
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    
                    // Main scrollable content
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 24) {
                            // Enhanced carousel with floating FAB
                            carouselSection
                            
                            // Premium slider with date label
                            if bodyMetrics.count > 1 {
                                enhancedTimelineSlider
                                    .padding(.horizontal, 24)
                            }
                            
                            // Clean metric gauges
                            metricsSection
                                .padding(.horizontal, 24)
                            
                            // Bottom padding for tab bar
                            Color.clear.frame(height: 100)
                        }
                        .padding(.top, 16)
                    }
                    .refreshable {
                        await refreshData()
                    }
                }
                
                // Floating metrics strip at bottom
                VStack {
                    Spacer()
                    floatingMetricsStrip
                }
            }
        }
        .onAppear {
            Task {
                await loadData()
            }
        }
        .onChange(of: refreshID) { _, _ in
            Task {
                await loadData()
            }
        }
        .confirmationDialog("Add Progress Photo", isPresented: $showPhotoOptions) {
            Button("Take Photo") {
                showCamera = true
            }
            Button("Choose from Library") {
                showPhotoPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                Task {
                    await saveProgressPhoto(image)
                }
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhoto,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhoto) { _, newPhoto in
            if let photo = newPhoto {
                Task {
                    if let data = try? await photo.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await saveProgressPhoto(image)
                    }
                    selectedPhoto = nil
                }
            }
        }
    }
    
    // MARK: - Unified Glass Header
    
    @ViewBuilder
    
    private var unifiedHeaderView: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                if let avatarUrl = authManager.currentUser?.avatarUrl,
                   let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } placeholder: {
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.5))
                    }
                } else {
                    Text(authManager.currentUser?.profile?.fullName?.prefix(1).uppercased() ?? "U")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                if let name = authManager.currentUser?.profile?.fullName {
                    Text(name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                HStack(spacing: 12) {
                    if let age = userAge {
                        Label("\(age)y", systemImage: "person")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    if let gender = authManager.currentUser?.profile?.gender {
                        Text(gender == "Male" ? "♂" : "♀")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    if let height = authManager.currentUser?.profile?.height, height > 0 {
                        let displayHeight = currentSystem == .imperial ?
                            formatHeightToFeetInches(height) : "\(Int(height * 2.54))cm"
                        Label(displayHeight, systemImage: "ruler")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            
            Spacer()
            
            // Sync indicator
            if syncManager.isSyncing {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .rotationEffect(.degrees(syncManager.isSyncing ? 360 : 0))
                    .animation(Animation.linear(duration: 1).repeatForever(autoreverses: false), value: syncManager.isSyncing)
            }
        }
        .padding(16)
        .background(
            Group {
                if #available(iOS 18.0, *) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                        )
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.appCard)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    // MARK: - Enhanced Carousel Section
    
    @ViewBuilder
    
    private var carouselSection: some View {
        ZStack(alignment: .bottomTrailing) {
            // Enhanced carousel with face detection
            EnhancedPhotoCarousel(
                currentMetric: currentMetric,
                historicalMetrics: bodyMetrics,
                selectedMetricsIndex: $selectedIndex
            )
            .padding(.horizontal, 16)
            
            // Floating FAB for adding photos
            if currentMetric?.photoUrl == nil {
                Button(
            action: {
                    showPhotoOptions = true
                    HapticManager.shared.buttonTapped()
                },
            label: {
                    ZStack {
                        Circle()
                            .fill(Color.appPrimary)
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
        )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.trailing, 24)
                .padding(.bottom, 16)
            }
        }
    }
    
    // MARK: - Enhanced Timeline Slider
    
    private var sliderProgress: CGFloat {
        let maxIndex = CGFloat(max(1, bodyMetrics.count - 1))
        return CGFloat(selectedIndex) / maxIndex
    }
    
    @ViewBuilder
    
    private var enhancedTimelineSlider: some View {
        VStack(spacing: 8) {
            // Floating date label above thumb
            if let date = currentMetric?.date {
                Text(formatDateForSlider(date))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                    )
                    .scaleEffect(isDraggingSlider ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: isDraggingSlider)
            }
            
            // Enhanced slider
            GeometryReader { geometry in
                let sliderWidth = geometry.size.width
                let thumbOffset = sliderWidth * sliderProgress - 12
                
                ZStack(alignment: .leading) {
                    // Track - 20% white, thicker
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)
                    
                    // Active portion
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(
                            width: sliderWidth * sliderProgress,
                            height: 4
                        )
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedIndex)
                    
                    // Enhanced thumb - 24pt
                    Circle()
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .offset(x: thumbOffset)
                        .scaleEffect(isDraggingSlider ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3), value: isDraggingSlider)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDraggingSlider = true
                                    let percent = min(max(0, value.location.x / sliderWidth), 1)
                                    let maxIndex = Double(max(1, bodyMetrics.count - 1))
                                    let newIndex = Int(round(percent * maxIndex))
                                    if newIndex != selectedIndex {
                                        selectedIndex = newIndex
                                        loadMetricsForSelectedDate()
                                        HapticManager.shared.sliderChanged()
                                    }
                                }
                                .onEnded { _ in
                                    isDraggingSlider = false
                                    HapticManager.shared.sliderChanged()
                                }
                        )
                }
            }
            .frame(height: 24)
            
            // Only show "Today" at the right
            HStack {
                Spacer()
                Text("Today")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
    
    @State private var isDraggingSlider = false
    
    // MARK: - Clean Metrics Section
    
    @ViewBuilder
    
    private var metricsSection: some View {
        HStack(spacing: 24) { // Equal 24pt padding
            // Weight gauge
            let weightValue = currentMetric?.weight ?? 0
            let weightInCurrentUnit = currentSystem == .imperial ?
                weightValue * 2.20462 : weightValue
            
            CleanMetricGauge(
                value: weightInCurrentUnit,
                maxValue: currentSystem == .imperial ? 300 : 150,
                label: "Weight",
                unit: currentSystem == .imperial ? "lbs" : "kg"
            )
            
            // Body Fat gauge
            let estimatedBF = currentMetric?.bodyFatPercentage == nil && selectedIndex < bodyMetrics.count
                ? PhotoMetadataService.shared.estimateBodyFat(for: bodyMetrics[selectedIndex].date, metrics: bodyMetrics)
                : nil
            
            let bodyFatValue = currentMetric?.bodyFatPercentage ?? estimatedBF?.value ?? 0
            
            CleanMetricGauge(
                value: bodyFatValue,
                maxValue: 50,
                label: "Body Fat",
                unit: "%",
                isEstimated: currentMetric?.bodyFatPercentage == nil && estimatedBF != nil
            )
        }
    }
    
    // MARK: - Floating Metrics Strip
    
    @ViewBuilder
    
    private var floatingMetricsStrip: some View {
        HStack(spacing: 32) { // Increased spacing to 32pt
            // BMI
            if let weight = currentMetric?.weight,
               let height = authManager.currentUser?.profile?.height,
               height > 0 {
                let heightInMeters = height * 0.0254
                let bmi = weight / (heightInMeters * heightInMeters)
                MetricStripItem(
                    icon: "speedometer",
                    value: String(format: "%.1f", bmi),
                    unit: "BMI"
                )
            } else {
                MetricStripItem(
                    icon: "speedometer",
                    value: "N/A",
                    unit: "BMI"
                )
            }
            
            // FFMI
            if let ffmi = calculateFFMI() {
                MetricStripItem(
                    icon: "figure.strengthtraining.traditional",
                    value: String(format: "%.1f", ffmi),
                    unit: "FFMI"
                )
            } else {
                MetricStripItem(
                    icon: "figure.strengthtraining.traditional",
                    value: "N/A",
                    unit: "FFMI"
                )
            }
            
            // Steps
            if let steps = selectedDateMetrics?.steps {
                MetricStripItem(
                    icon: "figure.walk",
                    value: formatNumber(steps),
                    unit: "steps"
                )
            } else {
                MetricStripItem(
                    icon: "figure.walk",
                    value: "N/A",
                    unit: "steps"
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            Group {
                if #available(iOS 18.0, *) {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Rectangle()
                                .fill(Color.appBackground.opacity(0.3))
                        )
                } else {
                    Rectangle()
                        .fill(Color.appBackground.opacity(0.95))
                }
            }
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1),
            alignment: .top
        )
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    
    private var loadingView: some View {
        DashboardEmptyStateView(
            icon: "arrow.triangle.2.circlepath",
            title: "Loading",
            message: "Fetching your data..."
        )
    }
    
    @ViewBuilder
    
    private var emptyStateView: some View {
        DashboardEmptyStateView(
            icon: "chart.line.downtrend.xyaxis",
            title: "No data yet",
            message: "Log your first measurement to get started"
        )
    }
    
    // MARK: - Helper Methods
    
    private func formatDateForSlider(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let daysDifference = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            if daysDifference <= 7 && daysDifference >= 0 {
                return "\(daysDifference)d ago"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d"
                return formatter.string(from: date)
            }
        }
    }
    
    private func formatDateShort(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
    
    private func formatHeightToFeetInches(_ inches: Double) -> String {
        let feet = Int(inches) / 12
        let remainingInches = Int(inches) % 12
        return "\(feet)'\(remainingInches)\""
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000.0)
        }
        return "\(number)"
    }
    
    private func calculateFFMI() -> Double? {
        guard let weight = currentMetric?.weight,
              let bodyFat = currentMetric?.bodyFatPercentage ?? PhotoMetadataService.shared.estimateBodyFat(for: currentMetric?.date ?? Date(), metrics: bodyMetrics)?.value,
              let height = authManager.currentUser?.profile?.height,
              height > 0 else { return nil }
        
        let heightInMeters = height * 0.0254
        let leanMass = weight * (1 - bodyFat / 100)
        let ffmi = leanMass / (heightInMeters * heightInMeters)
        
        return ffmi
    }
    
    // MARK: - Data Loading
    
    private func loadData() async {
        isLoading = true
        
        guard let userId = authManager.currentUser?.id else {
            isLoading = false
            return
        }
        
        // Load body metrics
        let cachedMetrics = CoreDataManager.shared.fetchBodyMetrics(for: userId)
        bodyMetrics = cachedMetrics.compactMap { $0.toBodyMetrics() }
            .sorted { $0.date < $1.date }
        
        if !bodyMetrics.isEmpty {
            selectedIndex = bodyMetrics.count - 1
            loadMetricsForSelectedDate()
        }
        
        // Load daily metrics
        dailyMetrics = CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())?.toDailyMetrics()
        
        isLoading = false
    }
    
    private func loadMetricsForSelectedDate() {
        guard let metric = currentMetric,
              let userId = authManager.currentUser?.id else { return }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: metric.date)
        
        selectedDateMetrics = CoreDataManager.shared.fetchDailyMetrics(
            for: userId,
            date: startOfDay
        )?.toDailyMetrics()
    }
    
    private func refreshData() async {
        refreshID = UUID()
        await loadData()
    }
    
    private func saveProgressPhoto(_ image: UIImage) async {
        guard let userId = authManager.currentUser?.id,
              let metric = currentMetric else { return }
        
        do {
            let photoUrl = try await PhotoUploadManager.shared.uploadProgressPhoto(
                for: metric,
                image: image
            )
            
            // Update metric with photo URL
            let updatedMetric = BodyMetrics(
                id: metric.id,
                userId: metric.userId,
                date: metric.date,
                weight: metric.weight,
                weightUnit: metric.weightUnit,
                bodyFatPercentage: metric.bodyFatPercentage,
                bodyFatMethod: metric.bodyFatMethod,
                muscleMass: metric.muscleMass,
                boneMass: metric.boneMass,
                notes: metric.notes,
                photoUrl: photoUrl,
                dataSource: metric.dataSource,
                createdAt: metric.createdAt,
                updatedAt: Date()
            )
            CoreDataManager.shared.saveBodyMetrics(updatedMetric, userId: userId)
            
            await refreshData()
        } catch {
            // print("Failed to upload photo: \(error)")
        }
    }
}

// MARK: - Supporting Views

struct CleanMetricGauge: View {
    let value: Double
    let maxValue: Double
    let label: String
    let unit: String
    var isEstimated: Bool = false
    
    private var normalizedValue: Double {
        min(1.0, max(0.0, value / maxValue))
    }
    
    var body: some View {
        ZStack {
            // Background circle - 1pt gray
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                .frame(width: 100, height: 100)
            
            // Progress arc - 3pt white
            Circle()
                .trim(from: 0, to: normalizedValue)
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: 3,
                        lineCap: .round
                    )
                )
                .frame(width: 100, height: 100)
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: normalizedValue)
            
            // Content
            VStack(spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text(label)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.gray)
            }
        }
    }
}

struct MetricStripItem: View {
    let icon: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.8))
            
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
            
            Text(unit)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.gray)
        }
    }
}

// Enhanced photo carousel would be in a separate file
struct EnhancedPhotoCarousel: View {
    let currentMetric: BodyMetrics?
    let historicalMetrics: [BodyMetrics]
    @Binding var selectedMetricsIndex: Int
    
    var body: some View {
        // Placeholder - would use Vision to detect faces and rotate
        ProgressPhotoCarouselView(
            currentMetric: currentMetric,
            historicalMetrics: historicalMetrics,
            selectedMetricsIndex: $selectedMetricsIndex
        )
    }
}

#Preview {
    DashboardViewV2()
        .environmentObject(AuthManager.shared)
        .environmentObject(SyncManager.shared)
        .preferredColorScheme(.dark)
}
