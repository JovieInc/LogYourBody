//
// ProgressPhotoCutoutView.swift
// LogYourBody
//
import SwiftUI

struct CutoutProcessingImagePlaceholder: View {
    @State private var pulseAnimation = false

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.appBorder, lineWidth: 1)
                )

            // Processing indicator
            VStack(spacing: 16) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0.6 : 1.0)

                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(.appPrimary)
                }

                VStack(spacing: 4) {
                    Text("Processing...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.appText)

                    Text("AI background removal")
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
}

struct ProgressPhotoCutoutView: View {
    let currentMetric: BodyMetrics?
    let historicalMetrics: [BodyMetrics]
    @Binding var selectedMetricsIndex: Int
    @State private var selectedPhotoIndex: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var processingService = ImageProcessingService.shared

    // Computed properties
    private var displayMetrics: [BodyMetrics] {
        historicalMetrics.filter { $0.photoUrl != nil }
    }

    private var currentBodyFat: Double {
        currentMetric?.bodyFatPercentage ?? 20.0
    }

    // Map photo index to metrics index
    private func metricsIndex(for photoIndex: Int) -> Int? {
        guard photoIndex < displayMetrics.count else { return nil }
        let photoMetric = displayMetrics[photoIndex]
        return historicalMetrics.firstIndex { $0.id == photoMetric.id }
    }

    // Map metrics index to photo index
    private func photoIndex(for metricsIndex: Int) -> Int? {
        guard metricsIndex < historicalMetrics.count else { return nil }
        let metric = historicalMetrics[metricsIndex]
        return displayMetrics.firstIndex { $0.id == metric.id }
    }

    // Accessibility label for photos
    private func accessibilityLabel(for metric: BodyMetrics) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let dateString = formatter.string(from: metric.date)

        var label = "Progress photo, \(dateString)"

        if let bodyFat = metric.bodyFatPercentage {
            label += ", body fat \(String(format: "%.1f", bodyFat)) percent"
        }

        if let weight = metric.weight {
            label += ", weight \(Int(weight)) kilograms"
        }

        return label
    }

    private var spotlightGradient: LinearGradient {
        // Dynamic gradient based on body fat percentage
        // Green (low) -> Yellow (medium) -> Orange/Red (high)
        let hue: Double = {
            if currentBodyFat < 10 {
                return 120 // Green
            } else if currentBodyFat < 15 {
                return 90 // Yellow-Green
            } else if currentBodyFat < 20 {
                return 60 // Yellow
            } else if currentBodyFat < 25 {
                return 30 // Orange
            } else {
                return 0 // Red
            }
        }()

        return LinearGradient(
            gradient: Gradient(colors: [
                Color(hue: hue / 360, saturation: 0.6, brightness: 0.8).opacity(0.3),
                Color(hue: hue / 360, saturation: 0.4, brightness: 0.6).opacity(0.1),
                Color.clear
            ]),
            startPoint: .bottom,
            endPoint: .top
        )
    }

    var body: some View {
        ZStack {
            // Unified background that covers Dynamic Island
            Color.appBackground
                .ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    // Dynamic gradient spotlight
                    Circle()
                        .fill(spotlightGradient)
                        .frame(width: geometry.size.width * 1.2, height: geometry.size.width * 1.2)
                        .blur(radius: 40)
                        .offset(y: geometry.size.height * 0.3)
                        .animation(.easeInOut(duration: 1.0), value: currentBodyFat)

                    if displayMetrics.isEmpty {
                        // Placeholder when no photos
                        PlaceholderSilhouetteView(gender: authManager.currentUser?.profile?.gender ?? "male")
                    } else {
                        // Proper carousel implementation with processing placeholders
                        TabView(selection: $selectedPhotoIndex) {
                            // Show existing photos
                            ForEach(Array(displayMetrics.enumerated()), id: \.element.id) { index, metric in
                                AnimatedPhotoContainer(
                                    metric: metric,
                                    isVisible: index == selectedPhotoIndex
                                )
                                .tag(index)
                                .accessibilityElement()
                                .accessibilityLabel(accessibilityLabel(for: metric))
                                .accessibilityHint("Swipe left or right to view other photos")
                            }

                            // Show processing placeholders
                            ForEach(processingService.processingTasks.filter { task in
                                task.status != .completed && task.status != .failed
                            }) { task in
                                CutoutProcessingImagePlaceholder()
                                    .tag(
                                        displayMetrics.count
                                            + (processingService.processingTasks.firstIndex(where: { $0.id == task.id }) ?? 0)
                                    )
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .animation(.easeInOut(duration: 0.3), value: selectedPhotoIndex)
                        .onChange(of: selectedPhotoIndex) { _, newIndex in
                            // Update timeline when photo changes
                            if !isDragging, let metricsIdx = metricsIndex(for: newIndex) {
                                // HapticManager.shared.selection()
                                selectedMetricsIndex = metricsIdx
                            }
                        }
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { _ in
                                    isDragging = true
                                }
                                .onEnded { _ in
                                    isDragging = false
                                }
                        )
                    }
                }
            }
        }
        .onAppear {
            // Initialize photo index based on current timeline selection
            if let photoIdx = photoIndex(for: selectedMetricsIndex) {
                selectedPhotoIndex = photoIdx
            }
        }
        .onChange(of: selectedMetricsIndex) { _, newIndex in
            // Update photo when timeline changes
            if !isDragging, let photoIdx = photoIndex(for: newIndex) {
                withAnimation(.spring()) {
                    selectedPhotoIndex = photoIdx
                }
            }
        }
    }
}

struct CutoutPhotoView: View {
    let photoUrl: String?
    var scale: Double = 1.0
    var offset: CGSize = .zero
    var opacity: Double = 1.0
    var blur: Double = 0
    var tintColor: Color?
    var showShadow: Bool = true

    var body: some View {
        GeometryReader { geometry in
            OptimizedProgressPhotoView(
                photoUrl: photoUrl,
                maxHeight: geometry.size.height
            )
            .frame(width: geometry.size.width, height: geometry.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .opacity(opacity)
            .blur(radius: blur)
            .overlay(tintColor)
            .if(showShadow) { view in
                view.shadow(
                    color: Color.black.opacity(0.15),
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
        }
    }
}

struct AnimatedPhotoContainer: View {
    let metric: BodyMetrics
    let isVisible: Bool
    @State private var photoOpacity: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Each photo in its own container
                CutoutPhotoView(
                    photoUrl: metric.photoUrl,
                    scale: 1.0,
                    offset: .zero,
                    opacity: 1.0,
                    showShadow: true
                )
                .frame(width: geometry.size.width * 0.9)
                .frame(maxHeight: geometry.size.height)
                .clipped()
                .opacity(photoOpacity)
                .onAppear {
                    // Fade in animation when photo appears
                    withAnimation(.easeIn(duration: 0.3)) {
                        photoOpacity = 1.0
                    }
                }
                .onChange(of: isVisible) { _, newValue in
                    if newValue {
                        // Reset and fade in when becoming visible
                        photoOpacity = 0
                        withAnimation(.easeIn(duration: 0.3)) {
                            photoOpacity = 1.0
                        }
                    }
                }
            }
        }
    }
}

struct PlaceholderSilhouetteView: View {
    let gender: String

    var body: some View {
        ZStack {
            // Background glow for better contrast
            Image(systemName: gender.lowercased() == "male" ? "figure.stand" : "figure.stand.dress")
                .font(.system(size: 200, weight: .ultraLight))
                .foregroundColor(Color.white.opacity(0.05))
                .blur(radius: 20)

            // Main silhouette with better contrast
            Image(systemName: gender.lowercased() == "male" ? "figure.stand" : "figure.stand.dress")
                .font(.system(size: 200, weight: .ultraLight))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.appTextSecondary.opacity(0.15),
                            Color.appTextSecondary.opacity(0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(
                    color: Color.black.opacity(0.2),
                    radius: 10,
                    x: 0,
                    y: 5
                )
        }
    }
}

struct MetricsOverlayView: View {
    let metric: BodyMetrics

    var body: some View {
        HStack(spacing: 20) {
            MetricPill(
                label: "Body Fat",
                value: String(format: "%.1f%%", metric.bodyFatPercentage ?? 0),
                color: colorForBodyFat(metric.bodyFatPercentage ?? 20)
            )

            if let weight = metric.weight {
                MetricPill(
                    label: "Weight",
                    value: String(format: "%.1f lbs", weight),
                    color: .appTextSecondary
                )
            }
        }
        .padding(.horizontal)
    }

    func colorForBodyFat(_ percentage: Double) -> Color {
        if percentage < 10 {
            return .green
        } else if percentage < 15 {
            return .yellow
        } else if percentage < 20 {
            return .orange
        } else {
            return .red
        }
    }
}

struct MetricPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.appTextSecondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color.appCard.opacity(0.9))
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// Helper extension for conditional modifiers
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

#Preview {
    ProgressPhotoCutoutView(
        currentMetric: BodyMetrics(
            id: "1",
            userId: "user1",
            date: Date(),
            weight: 180,
            weightUnit: "lbs",
            bodyFatPercentage: 15,
            bodyFatMethod: "Navy",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "Manual",
            createdAt: Date(),
            updatedAt: Date()
        ),
        historicalMetrics: [],
        selectedMetricsIndex: .constant(0)
    )
    .environmentObject(AuthManager.shared)
    .preferredColorScheme(.dark)
}
