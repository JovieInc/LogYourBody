//
// MetricCard.swift
// LogYourBody
//
import SwiftUI
import Charts

// MARK: - MetricCard Molecule

/// **DEPRECATED**: Use `MetricSummaryCard` from `DesignSystem/Organisms/MetricSummaryCard.swift` instead.
///
/// This component has been replaced with a fully polished Apple Health-style component with:
/// - Material backgrounds (glassmorphism)
/// - Proper state management (loading, empty, error, data)
/// - Better accessibility support
/// - Larger, more visible charts
/// - Consistent spacing and typography
///
/// Migration guide:
/// - Replace `DSMetricCard` with `MetricSummaryCard`
/// - Use the `.data(Content(...))` state with proper data binding
/// - Set `isButtonContext: true` if used inside a Button
@available(*, deprecated, message: "Use MetricSummaryCard from DesignSystem/Organisms/MetricSummaryCard.swift instead")
struct DSMetricCard: View {
    let value: String
    let unit: String?
    let label: String

    // Legacy trend display (vertical layout)
    var trend: Double?
    var trendType: DSTrendIndicator.TrendType = .neutral

    // Apple Health-style additions (horizontal layout)
    var icon: String?
    var iconColor: Color?
    var timestamp: String?
    var chartData: [SparklineDataPoint]?
    var showChevron: Bool = false

    var height: CGFloat = 140 // Apple Health cards are slightly taller
    var isInteractive: Bool = false
    var onTap: (() -> Void)?

    @State private var isPressed = false

    // Determine which layout to use
    private var useAppleHealthLayout: Bool {
        icon != nil || timestamp != nil || chartData != nil || showChevron
    }

    var body: some View {
        Group {
            if useAppleHealthLayout {
                appleHealthLayout
            } else {
                legacyLayout
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.appCard)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .opacity(isPressed ? 0.9 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .onTapGesture {
            if isInteractive || onTap != nil {
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPressed = false
                    onTap?()
                }
            }
        }
    }

    // MARK: - Apple Health-Style Layout

    private var appleHealthLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Icon + Label + Time + Chevron
            HStack(alignment: .center, spacing: 8) {
                if let icon = icon, let iconColor = iconColor {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                Text(label)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.appText)

                Spacer()

                if let time = timestamp {
                    Text(time)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                }

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.appTextSecondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Value + Chart Row
            HStack(alignment: .bottom, spacing: 16) {
                // Large Value Display
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(.system(size: 56, weight: .bold))
                        .foregroundColor(.appText)

                    if let unit = unit {
                        Text(unit)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.appTextSecondary)
                    }
                }

                Spacer()

                // Inline Sparkline Chart
                if let chartData = chartData, !chartData.isEmpty {
                    Chart {
                        ForEach(chartData) { point in
                            LineMark(
                                x: .value("Index", point.index),
                                y: .value("Value", point.value)
                            )
                            .foregroundStyle((iconColor ?? .blue).gradient)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(width: 120, height: 50)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Legacy Layout (Vertical)

    private var legacyLayout: some View {
        VStack(spacing: 0) {
            // Top section with value and trend
            VStack(spacing: 4) {
                DSMetricValue(
                    value: value,
                    unit: unit,
                    size: .system(size: 40, weight: .bold, design: .rounded),
                    unitSize: .system(size: 18, weight: .medium, design: .rounded)
                )

                if trend != nil {
                    DSTrendIndicator(
                        trend: trend,
                        trendType: trendType
                    )
                }
            }
            .frame(maxHeight: .infinity)

            // Bottom label
            DSMetricLabel(
                text: label,
                size: .system(size: 14),
                weight: .medium,
                color: .appTextSecondary
            )
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Sparkline Data Point

/// Data point for sparkline charts (simplified with just index and value)
struct SparklineDataPoint: Identifiable {
    let id = UUID()
    let index: Int
    let value: Double
    var isEstimated: Bool = false
}

// MARK: - EmptyMetricCard

/// A placeholder card for when metric data is not available
struct DSEmptyMetricCard: View {
    let label: String
    let unit: String
    var height: CGFloat = 120 // Increased to match metric card
    
    var body: some View {
        VStack(spacing: 0) {
            // Empty value placeholder
            VStack(spacing: 4) {
                DSMetricValue(
                    value: "––",
                    unit: unit,
                    size: .system(size: 40, weight: .bold, design: .rounded),
                    color: .appTextTertiary,
                    unitSize: .system(size: 18, weight: .medium, design: .rounded)
                )
            }
            .frame(maxHeight: .infinity)
            
            // Bottom label
            DSMetricLabel(
                text: label,
                size: .system(size: 14),
                weight: .medium,
                color: .appTextSecondary
            )
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.appCard)
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview("Apple Health Style") {
    ScrollView {
        VStack(spacing: 16) {
            // Steps card with sparkline
            DSMetricCard(
                value: "8,432",
                unit: "steps",
                label: "Steps",
                icon: "figure.walk",
                iconColor: .orange,
                timestamp: "6:15 PM",
                chartData: [
                    SparklineDataPoint(index: 0, value: 5200),
                    SparklineDataPoint(index: 1, value: 7800),
                    SparklineDataPoint(index: 2, value: 6400),
                    SparklineDataPoint(index: 3, value: 9100),
                    SparklineDataPoint(index: 4, value: 7200),
                    SparklineDataPoint(index: 5, value: 8900),
                    SparklineDataPoint(index: 6, value: 8432)
                ],
                showChevron: true,
                isInteractive: true,
                onTap: { print("Steps tapped") }
            )

            // Weight card with sparkline
            DSMetricCard(
                value: "165.2",
                unit: "lbs",
                label: "Weight",
                icon: "figure.stand",
                iconColor: .purple,
                timestamp: "8:30 AM",
                chartData: [
                    SparklineDataPoint(index: 0, value: 168.5),
                    SparklineDataPoint(index: 1, value: 167.8),
                    SparklineDataPoint(index: 2, value: 167.0),
                    SparklineDataPoint(index: 3, value: 166.5),
                    SparklineDataPoint(index: 4, value: 166.0),
                    SparklineDataPoint(index: 5, value: 165.2)
                ],
                showChevron: true,
                isInteractive: true,
                onTap: { print("Weight tapped") }
            )

            // Body Fat card with sparkline
            DSMetricCard(
                value: "18.2",
                unit: "%",
                label: "Body Fat Percentage",
                icon: "percent",
                iconColor: .purple,
                timestamp: "8:30 AM",
                chartData: [
                    SparklineDataPoint(index: 0, value: 20.5),
                    SparklineDataPoint(index: 1, value: 19.8),
                    SparklineDataPoint(index: 2, value: 19.2),
                    SparklineDataPoint(index: 3, value: 18.9),
                    SparklineDataPoint(index: 4, value: 18.5),
                    SparklineDataPoint(index: 5, value: 18.2)
                ],
                showChevron: true,
                isInteractive: true,
                onTap: { print("Body Fat tapped") }
            )

            // FFMI card with sparkline
            DSMetricCard(
                value: "21.4",
                unit: "",
                label: "Fat Free Mass Index",
                icon: "figure.arms.open",
                iconColor: .purple,
                timestamp: "8:30 AM",
                chartData: [
                    SparklineDataPoint(index: 0, value: 20.2),
                    SparklineDataPoint(index: 1, value: 20.5),
                    SparklineDataPoint(index: 2, value: 20.8),
                    SparklineDataPoint(index: 3, value: 21.0),
                    SparklineDataPoint(index: 4, value: 21.2),
                    SparklineDataPoint(index: 5, value: 21.4)
                ],
                showChevron: true,
                isInteractive: true,
                onTap: { print("FFMI tapped") }
            )
        }
        .padding(20)
    }
    .background(Color.appBackground)
}

#Preview("Legacy Style") {
    VStack(spacing: 16) {
        HStack(spacing: 16) {
            // Weight with downward trend (interactive)
            DSMetricCard(
                value: "165.5",
                unit: "lbs",
                label: "Weight",
                trend: -2.3,
                trendType: .neutral,
                isInteractive: true,
                onTap: {
                    // Weight card tapped
                }
            )

            // Body fat with upward trend (bad)
            DSMetricCard(
                value: "22.5",
                unit: "%",
                label: "Body Fat",
                trend: 0.8,
                trendType: .negative
            )
        }

        HStack(spacing: 16) {
            // FFMI with no trend (interactive)
            DSMetricCard(
                value: "21.8",
                unit: nil,
                label: "FFMI",
                isInteractive: true,
                onTap: {
                    // FFMI card tapped
                }
            )

            // Empty metric
            DSEmptyMetricCard(
                label: "Lean Mass",
                unit: "kg"
            )
        }
    }
    .padding()
    .background(Color.appBackground)
}
