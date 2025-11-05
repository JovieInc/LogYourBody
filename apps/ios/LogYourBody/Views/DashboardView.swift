//
// DashboardView.swift
// LogYourBody
//
import SwiftUI
import PhotosUI

struct DashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var syncManager: SyncManager

    // Managers - using let instead of property wrappers to avoid initialization issues
    let healthKitManager = HealthKitManager.shared

    // Core data state
    @State var dailyMetrics: DailyMetrics?
    @State var selectedDateMetrics: DailyMetrics?
    @State var bodyMetrics: [BodyMetrics] = []
    @State var selectedIndex: Int = 0
    @State var hasLoadedInitialData = false

    // UI state
    @State private var refreshID = UUID()
    @State var showPhotoOptions = false
    @State var showCamera = false
    @State var showPhotoPicker = false
    @State var selectedPhoto: PhotosPickerItem?
    @State var isUploadingPhoto = false
    @State var displayMode: BodyVisualizationMode = .photo

    // Preferences
    @AppStorage(Constants.preferredMeasurementSystemKey)
    var measurementSystem = PreferencesView.defaultMeasurementSystem

    // Computed properties
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
                Color.appBackground.ignoresSafeArea()

                if bodyMetrics.isEmpty && !hasLoadedInitialData {
                    // Loading state
                    VStack(spacing: 20) {
                        ProgressView()
                            .tint(.white)
                        Text("Loading your dashboard...")
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else if bodyMetrics.isEmpty {
                    // Empty state
                    VStack(spacing: 20) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 60))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No metrics yet")
                            .font(.title2)
                            .foregroundColor(.white)
                        Text("Tap the + button to log your first entry")
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    // Content state
                    ScrollView {
                        VStack(spacing: 20) {
                            // Greeting with sync status
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(greeting)
                                        .font(.system(size: 34, weight: .bold))
                                        .foregroundColor(.white)

                                    // Sync status pill
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text("Just now")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white.opacity(0.55))
                                        Text("·")
                                            .foregroundColor(.white.opacity(0.3))
                                        Text("Offline OK")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.white.opacity(0.55))
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                            // Latest Weight Card with Photo
                            if let metric = currentMetric {
                                VStack(spacing: 12) {
                                    // Display mode toggle
                                    HStack(spacing: 12) {
                                        Button(action: { displayMode = .photo }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "camera.fill")
                                                    .font(.caption)
                                                Text("Photo")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(displayMode == .photo ? Color.blue : Color.white.opacity(0.1))
                                            )
                                            .foregroundColor(displayMode == .photo ? .white : .white.opacity(0.6))
                                        }

                                        Button(action: { displayMode = .avatar }) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "figure.stand")
                                                    .font(.caption)
                                                Text("Avatar")
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                Capsule()
                                                    .fill(displayMode == .avatar ? Color.blue : Color.white.opacity(0.1))
                                            )
                                            .foregroundColor(displayMode == .avatar ? .white : .white.opacity(0.6))
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal)

                                    // Photo or Avatar
                                    visualView(for: metric)

                                    // Timeline navigation - moved directly under photo
                                    if bodyMetrics.count > 1 {
                                        PhotoAnchoredTimelineSlider(
                                            metrics: bodyMetrics,
                                            selectedIndex: $selectedIndex,
                                            accentColor: .blue
                                        )
                                        .frame(height: 50)
                                        .padding(.top, 8)
                                    }

                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Current Weight")
                                                .font(.subheadline)
                                                .foregroundColor(.white.opacity(0.7))

                                            if let weight = metric.weight {
                                                Text(formatWeight(weight))
                                                    .font(.system(size: 40, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }

                                        Spacer()

                                        // Weight trend indicator (if you have previous data)
                                        if bodyMetrics.count > 1, let prevWeight = bodyMetrics[safe: 1]?.weight, let currWeight = metric.weight {
                                            let change = currWeight - prevWeight
                                            let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                                            let convertedChange = convertWeight(abs(change), to: system) ?? abs(change)
                                            let unit = system.weightUnit

                                            VStack(alignment: .trailing, spacing: 4) {
                                                Image(systemName: change < 0 ? "arrow.down.circle.fill" : change > 0 ? "arrow.up.circle.fill" : "minus.circle.fill")
                                                    .font(.title2)
                                                    .foregroundColor(change < 0 ? .green : change > 0 ? .red : .gray)

                                                Text(String(format: "%.1f %@", convertedChange, unit))
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.7))
                                            }
                                        }
                                    }

                                    HStack {
                                        Text(metric.date ?? Date(), style: .date)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.6))

                                        Spacer()

                                        if let bodyFat = metric.bodyFatPercentage {
                                            Text("\(bodyFat, specifier: "%.1f")% body fat")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.1))
                                )
                                .padding(.horizontal)
                            }

                            // Today's Steps (if available)
                            if let metrics = dailyMetrics, let steps = metrics.steps, steps > 0 {
                                HStack {
                                    Image(systemName: "figure.walk")
                                        .font(.title2)
                                        .foregroundColor(.blue)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Today's Steps")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.7))
                                        Text("\(steps)")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                    }

                                    Spacer()
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color.white.opacity(0.1))
                                )
                                .padding(.horizontal)
                            }

                            // Key Metrics - FFMI & Total Change
                            HStack(spacing: 12) {
                                // FFMI (if available or interpolated)
                                if let metric = currentMetric, let weight = metric.weight {
                                    // Get body fat - use actual or interpolated
                                    let bodyFatResult = metric.bodyFatPercentage != nil ?
                                        (value: metric.bodyFatPercentage!, isEstimated: false) :
                                        PhotoMetadataService.shared.estimateBodyFat(for: metric.date, metrics: bodyMetrics)

                                    // Convert height to inches
                                    let heightInches = convertHeightToInches(
                                        height: authManager.currentUser?.profile?.height,
                                        heightUnit: authManager.currentUser?.profile?.heightUnit
                                    )

                                    // Debug logging
                                    let _ = print("🔍 FFMI Debug - Weight: \(weight)kg, BF%: \(String(describing: bodyFatResult?.value)) (estimated: \(bodyFatResult?.isEstimated ?? false)), Height: \(String(describing: heightInches))in")

                                    if let bodyFat = bodyFatResult?.value,
                                       let ffmi = calculateFFMI(
                                           weight: weight,
                                           bodyFat: bodyFat,
                                           heightInches: heightInches
                                       ) {
                                        let _ = print("✅ FFMI calculated: \(ffmi)")
                                        let isEstimated = bodyFatResult?.isEstimated ?? false

                                        VStack(spacing: 4) {
                                            Image(systemName: "figure.arms.open")
                                                .font(.title3)
                                                .foregroundColor(.purple)
                                            Text(String(format: "%@%.1f", isEstimated ? "~" : "", ffmi))
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .foregroundColor(isEstimated ? .white.opacity(0.8) : .white)
                                            Text("FFMI")
                                                .font(.caption2)
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                        .frame(maxWidth: .infinity)
                                    } else {
                                        let _ = print("❌ FFMI calculation returned nil")
                                    }
                                }

                                if let firstEntry = bodyMetrics.last, let lastEntry = bodyMetrics.first,
                                   let firstWeight = firstEntry.weight, let lastWeight = lastEntry.weight {
                                    let totalChange = lastWeight - firstWeight
                                    let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                                    let convertedChange = convertWeight(abs(totalChange), to: system) ?? abs(totalChange)
                                    let unit = system.weightUnit
                                    let sign = totalChange > 0 ? "+" : "-"
                                    let formatted = String(format: "%.1f", convertedChange)

                                    // Divider (only if FFMI is shown)
                                    if currentMetric?.bodyFatPercentage != nil && authManager.currentUser?.profile?.height != nil {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.2))
                                            .frame(width: 1)
                                            .padding(.vertical, 8)
                                    }

                                    // Total change
                                    VStack(spacing: 4) {
                                        Image(systemName: totalChange < 0 ? "arrow.down.circle" : "arrow.up.circle")
                                            .font(.title3)
                                            .foregroundColor(totalChange < 0 ? .green : .red)
                                        Text("\(sign)\(formatted) \(unit)")
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Text("Change")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.7))
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.1))
                            )
                            .padding(.horizontal)

                            // Body Composition Metrics
                            if let metric = currentMetric {
                                bodyCompositionMetrics(for: metric)
                            }

                            Spacer(minLength: 40) // Space for tab bar
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadData()
            }
            .refreshable {
                await refreshData()
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
        }
    }

    var placeholderPhotoView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            Text("Photo unavailable")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.05))
    }

    @ViewBuilder
    func visualView(for metric: BodyMetrics) -> some View {
        switch displayMode {
        case .photo:
            // Photo mode - show photo if available
            photoView(for: metric)

        case .avatar:
            // Avatar mode - show wireframe body
            AvatarBodyRenderer(
                bodyFatPercentage: metric.bodyFatPercentage,
                gender: authManager.currentUser?.profile?.gender,
                height: 160
            )
        }
    }

    @ViewBuilder
    func photoView(for metric: BodyMetrics) -> some View {
        if isUploadingPhoto {
            // Show upload progress
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.white)
                Text("Uploading photo...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
            )
        } else if let photoUrl = metric.photoUrl, !photoUrl.isEmpty {
            AsyncImage(url: URL(string: photoUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 160)
                        .clipped()
                        .cornerRadius(12)
                case .failure(let error):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.red.opacity(0.7))
                        Text("Failed to load photo")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        Text("\(error.localizedDescription)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.05))
                case .empty:
                    ProgressView()
                        .frame(height: 160)
                @unknown default:
                    placeholderPhotoView
                }
            }
        } else {
            Button(action: { showPhotoOptions = true }) {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.3))
                    Text("Add Progress Photo")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                                .foregroundColor(.white.opacity(0.2))
                        )
                )
            }
        }
    }

    @ViewBuilder
    func bodyCompositionMetrics(for metric: BodyMetrics) -> some View {
        // Compact badges layout
        HStack(spacing: 8) {
            // Body Fat Percentage badge
            if let bodyFat = metric.bodyFatPercentage {
                let color = getBodyFatColor(bodyFat: bodyFat, gender: nil)
                HStack(spacing: 6) {
                    Image(systemName: "percent")
                        .font(.caption)
                        .foregroundColor(color)
                    Text(String(format: "%.1f%% BF", bodyFat))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
            }

            // Lean Mass badge
            if let leanMass = calculateLeanMass(weight: metric.weight, bodyFat: metric.bodyFatPercentage) {
                let system = MeasurementSystem(rawValue: measurementSystem) ?? .imperial
                let convertedMass = convertWeight(leanMass, to: system) ?? leanMass
                let unit = system.weightUnit
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text(String(format: "%.1f %@ LM", convertedMass, unit))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                )
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .blue

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
}

//
//  AvatarBodyRenderer.swift
//  LogYourBody
//
//  Renders wireframe body silhouettes based on body fat percentage
//

import SwiftUI

/// Renders a white wireframe body silhouette on black background based on BF%
struct AvatarBodyRenderer: View {
    let bodyFatPercentage: Double?
    let gender: String?
    let height: CGFloat

    var body: some View {
        ZStack {
            // Black background
            Color.black

            // Wireframe body
            if let bodyFat = bodyFatPercentage {
                WireframeBody(bodyFatPercentage: bodyFat, gender: gender ?? "male")
                    .stroke(Color.white, lineWidth: 2)
                    .frame(height: height)
            } else {
                // No BF% data - show placeholder
                VStack(spacing: 12) {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No body composition data")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(height: height)
        .cornerRadius(12)
    }
}

/// Custom shape for wireframe body based on BF%
struct WireframeBody: Shape {
    let bodyFatPercentage: Double
    let gender: String

    func path(in rect: CGRect) -> Path {
        let isMale = gender.lowercased() == "male"

        // Determine body proportions based on BF%
        let bodyType = classifyBodyType(bodyFat: bodyFatPercentage, isMale: isMale)

        var path = Path()
        let centerX = rect.midX
        let width = rect.width * 0.6 // Body takes up 60% of width

        // Scale factors based on body fat
        let (shoulderWidth, waistWidth, hipWidth, neckWidth) = bodyType.dimensions

        // Calculate positions (from top to bottom)
        let headTop = rect.minY + rect.height * 0.05
        let headHeight = rect.height * 0.15
        let neckTop = headTop + headHeight
        let neckHeight = rect.height * 0.05
        let shoulderTop = neckTop + neckHeight
        let chestMid = shoulderTop + rect.height * 0.15
        let waistTop = shoulderTop + rect.height * 0.30
        let hipTop = waistTop + rect.height * 0.10
        let bottom = rect.maxY - rect.height * 0.05

        // Head (circle)
        let headRadius = width * 0.12
        path.addEllipse(in: CGRect(
            x: centerX - headRadius,
            y: headTop,
            width: headRadius * 2,
            height: headHeight
        ))

        // Neck
        let neckX = width * neckWidth / 2
        path.move(to: CGPoint(x: centerX - neckX, y: neckTop))
        path.addLine(to: CGPoint(x: centerX - neckX, y: shoulderTop))
        path.move(to: CGPoint(x: centerX + neckX, y: neckTop))
        path.addLine(to: CGPoint(x: centerX + neckX, y: shoulderTop))

        // Shoulders to waist (torso outline)
        let shoulderX = width * shoulderWidth / 2
        let waistX = width * waistWidth / 2

        // Left side of torso
        path.move(to: CGPoint(x: centerX - shoulderX, y: shoulderTop))
        path.addCurve(
            to: CGPoint(x: centerX - waistX, y: waistTop),
            control1: CGPoint(x: centerX - shoulderX, y: chestMid),
            control2: CGPoint(x: centerX - waistX, y: chestMid)
        )

        // Right side of torso
        path.move(to: CGPoint(x: centerX + shoulderX, y: shoulderTop))
        path.addCurve(
            to: CGPoint(x: centerX + waistX, y: waistTop),
            control1: CGPoint(x: centerX + shoulderX, y: chestMid),
            control2: CGPoint(x: centerX + waistX, y: chestMid)
        )

        // Waist to hips
        let hipX = width * hipWidth / 2

        // Left waist to hip
        path.move(to: CGPoint(x: centerX - waistX, y: waistTop))
        path.addLine(to: CGPoint(x: centerX - hipX, y: hipTop))
        path.addLine(to: CGPoint(x: centerX - hipX, y: bottom))

        // Right waist to hip
        path.move(to: CGPoint(x: centerX + waistX, y: waistTop))
        path.addLine(to: CGPoint(x: centerX + hipX, y: hipTop))
        path.addLine(to: CGPoint(x: centerX + hipX, y: bottom))

        // Arms (simplified straight lines from shoulders)
        let armWidth = width * 0.08
        let armEndY = waistTop

        // Left arm
        path.move(to: CGPoint(x: centerX - shoulderX, y: shoulderTop))
        path.addLine(to: CGPoint(x: centerX - shoulderX - armWidth * 2, y: armEndY))

        // Right arm
        path.move(to: CGPoint(x: centerX + shoulderX, y: shoulderTop))
        path.addLine(to: CGPoint(x: centerX + shoulderX + armWidth * 2, y: armEndY))

        return path
    }

    /// Classify body type based on body fat percentage
    private func classifyBodyType(bodyFat: Double, isMale: Bool) -> BodyType {
        if isMale {
            switch bodyFat {
            case ..<10:
                return .veryLeanMale
            case 10..<15:
                return .leanMale
            case 15..<20:
                return .averageMale
            case 20..<25:
                return .moderateMale
            default:
                return .higherMale
            }
        } else {
            switch bodyFat {
            case ..<15:
                return .veryLeanFemale
            case 15..<20:
                return .leanFemale
            case 20..<25:
                return .averageFemale
            case 25..<30:
                return .moderateFemale
            default:
                return .higherFemale
            }
        }
    }
}

/// Body type classifications with dimension ratios
enum BodyType {
    // Male body types
    case veryLeanMale
    case leanMale
    case averageMale
    case moderateMale
    case higherMale

    // Female body types
    case veryLeanFemale
    case leanFemale
    case averageFemale
    case moderateFemale
    case higherFemale

    /// Returns (shoulderWidth, waistWidth, hipWidth, neckWidth) as ratios
    var dimensions: (Double, Double, Double, Double) {
        switch self {
        // Male body types (wider shoulders, narrower hips)
        case .veryLeanMale:
            return (0.95, 0.60, 0.65, 0.20) // Very lean: wide shoulders, very narrow waist
        case .leanMale:
            return (0.90, 0.65, 0.68, 0.22) // Lean: wide shoulders, narrow waist
        case .averageMale:
            return (0.85, 0.72, 0.72, 0.24) // Average: moderate taper
        case .moderateMale:
            return (0.82, 0.78, 0.75, 0.26) // Moderate: less taper
        case .higherMale:
            return (0.80, 0.85, 0.80, 0.28) // Higher BF: minimal taper

        // Female body types (narrower shoulders, wider hips)
        case .veryLeanFemale:
            return (0.75, 0.58, 0.75, 0.18) // Very lean: narrow waist, defined
        case .leanFemale:
            return (0.72, 0.62, 0.78, 0.19) // Lean: feminine taper
        case .averageFemale:
            return (0.70, 0.68, 0.80, 0.20) // Average: balanced proportions
        case .moderateFemale:
            return (0.68, 0.74, 0.82, 0.21) // Moderate: softer curves
        case .higherFemale:
            return (0.66, 0.80, 0.85, 0.22) // Higher BF: fuller figure
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AvatarBodyRenderer(bodyFatPercentage: 12, gender: "male", height: 200)
        AvatarBodyRenderer(bodyFatPercentage: 22, gender: "female", height: 200)
        AvatarBodyRenderer(bodyFatPercentage: nil, gender: "male", height: 200)
    }
    .padding()
    .background(Color.gray)
}
