//
// DashboardContent.swift
// LogYourBody
//
import SwiftUI

// MARK: - DashboardContent Organism

/// The main content area of the dashboard
struct DashboardContent: View {
    let bodyMetrics: [BodyMetrics]
    let selectedIndex: Int
    let dailyMetrics: DailyMetrics?
    let selectedDateMetrics: DailyMetrics?
    let currentSystem: MeasurementSystem
    let userAge: Int?
    let userHeight: Double?
    let userHeightUnit: String?
    let onPhotoAction: () -> Void
    @Binding var selectedMetricsIndex: Int
    @State private var displayMode: DashboardDisplayMode = .photo
    @State private var timelineMode: TimelineMode = .photo
    @State private var selectedChartDate: Date?

    // Computed properties for current metric
    private var currentMetric: BodyMetrics? {
        guard !bodyMetrics.isEmpty && selectedIndex >= 0 && selectedIndex < bodyMetrics.count else { return nil }
        return bodyMetrics[selectedIndex]
    }

    var body: some View {
        if bodyMetrics.isEmpty {
            DashboardEmptyState()
        } else {
            VStack(spacing: 0) {
                // Main Content Area - Photo or Chart
                mainContentSection
                    .frame(maxHeight: .infinity)

                // Fixed height content at bottom
                VStack(spacing: 16) {
                    // Timeline Slider
                    if bodyMetrics.count > 1 {
                        timelineSection
                    }

                    // Core Metrics
                    CoreMetricsRow(
                        bodyFatPercentage: getBodyFatValue(),
                        weight: getWeightValue(),
                        bodyFatTrend: calculateBodyFatTrend(),
                        weightTrend: calculateWeightTrend(),
                        weightUnit: currentSystem.weightUnit,
                        isEstimated: currentMetric?.bodyFatPercentage == nil && getBodyFatValue() != nil,
                        displayMode: $displayMode
                    )

                    // Secondary Metrics
                    SecondaryMetricsRow(
                        steps: selectedDateMetrics?.steps,
                        ffmi: calculateFFMI(),
                        leanMass: getLeanMassValue(),
                        stepsTrend: calculateStepsTrend(),
                        ffmiTrend: calculateFFMITrend(),
                        leanMassTrend: calculateLeanMassTrend(),
                        weightUnit: currentSystem.weightUnit,
                        displayMode: $displayMode
                    )

                    // Bottom padding for floating tab bar
                    Color.clear.frame(height: 90)
                }
            }
            .onChange(of: displayMode) { _, newMode in
                // When switching to chart mode, sync date with current index
                if newMode.isChartMode && selectedIndex < bodyMetrics.count {
                    selectedChartDate = bodyMetrics[selectedIndex].date
                }
            }
        }
    }

    // MARK: - Subviews

    private var mainContentSection: some View {
        ZStack {
            // Content based on display mode
            if displayMode == .photo {
                progressPhotoSection
            } else {
                chartSection
            }

            // Photo button overlay (top-right corner)
            VStack {
                HStack {
                    Spacer()

                    photoModeButton
                        .padding(.trailing, 20)
                        .padding(.top, 20)
                }
                Spacer()
            }

            // Camera button overlay (bottom-right, only in photo mode)
            if displayMode == .photo {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        photoActionButton
                            .padding(.trailing, 20)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    private var progressPhotoSection: some View {
        ProgressPhotoCarouselView(
            currentMetric: currentMetric,
            historicalMetrics: bodyMetrics,
            selectedMetricsIndex: $selectedMetricsIndex,
            displayMode: $displayMode
        )
    }

    private var chartSection: some View {
        MetricChartView(
            bodyMetrics: bodyMetrics,
            displayMode: displayMode,
            selectedDate: $selectedChartDate
        )
        .padding(.top, 60) // Space for photo button
        .onChange(of: selectedMetricsIndex) { _, newIndex in
            // Sync chart date with timeline
            if newIndex < bodyMetrics.count {
                selectedChartDate = bodyMetrics[newIndex].date
            }
        }
    }

    private var photoModeButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                displayMode = .photo
            }
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        } label: {
            Image(systemName: "photo.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(displayMode == .photo ? .white : .white.opacity(0.4))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(displayMode == .photo ? Color.appPrimary : Color.black.opacity(0.3))
                )
                .overlay(
                    Circle()
                        .strokeBorder(displayMode == .photo ? Color.liquidAccent : Color.clear, lineWidth: 2)
                )
        }
    }

    private var photoActionButton: some View {
        Button(action: onPhotoAction) {
            if currentMetric?.photoUrl == nil || currentMetric?.photoUrl?.isEmpty == true {
                // Full button when no photo
                HStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                    Text("Add Photo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.appPrimary))
            } else {
                // Icon only when photo exists
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.5)))
            }
        }
    }

    private var timelineSection: some View {
        VStack(spacing: 0) {
            ProgressTimelineView(
                bodyMetrics: bodyMetrics,
                selectedIndex: $selectedMetricsIndex,
                mode: $timelineMode
            )
            .frame(height: 80)
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .background(Color.appCard.opacity(0.5))
    }

    // MARK: - Calculations

    private func getBodyFatValue() -> Double? {
        if let bf = currentMetric?.bodyFatPercentage {
            return bf
        } else if selectedIndex < bodyMetrics.count {
            return PhotoMetadataService.shared.estimateBodyFat(
                for: bodyMetrics[selectedIndex].date,
                metrics: bodyMetrics
            )?.value
        }
        return nil
    }

    private func getWeightValue() -> Double? {
        guard let weight = currentMetric?.weight else { return nil }
        return convertWeight(weight, from: "kg", to: currentSystem.weightUnit)
    }

    private func getLeanMassValue() -> Double? {
        guard let weight = currentMetric?.weight,
              let bf = getBodyFatValue() else { return nil }
        let leanMass = weight * (1 - bf / 100)
        return convertWeight(leanMass, from: "kg", to: currentSystem.weightUnit)
    }

    private func calculateFFMI() -> Double? {
        guard let weight = currentMetric?.weight,
              let userHeightValue = userHeight,
              let bf = getBodyFatValue() else { return nil }

        // Convert height to cm if stored in inches
        let heightInCm: Double
        if userHeightUnit == "in" {
            heightInCm = userHeightValue * 2.54
        } else {
            heightInCm = userHeightValue
        }

        let leanMass = weight * (1 - bf / 100)
        let heightInMeters = heightInCm / 100
        return leanMass / (heightInMeters * heightInMeters)
    }

    // Stub calculation methods - implement based on your logic
    private func calculateBodyFatTrend() -> Double? { nil }
    private func calculateWeightTrend() -> Double? { nil }
    private func calculateStepsTrend() -> Int? { nil }
    private func calculateFFMITrend() -> Double? { nil }
    private func calculateLeanMassTrend() -> Double? { nil }

    private func convertWeight(_ weight: Double, from: String, to: String) -> Double {
        if from == to { return weight }
        if from == "kg" && to == "lbs" {
            return weight * 2.20462
        } else if from == "lbs" && to == "kg" {
            return weight / 2.20462
        }
        return weight
    }
}

// MARK: - DashboardEmptyState

private struct DashboardEmptyState: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 64, weight: .light))
                .foregroundColor(.appTextSecondary)

            VStack(spacing: 12) {
                Text("No data yet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.appText)

                Text("Log your first measurement to get started")
                    .font(.system(size: 16))
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}
