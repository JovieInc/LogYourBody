//
// CompactMetricCard.swift
// LogYourBody
//
import SwiftUI

// MARK: - CompactMetricCard Molecule

/// **DEPRECATED**: Use `MetricSummaryCard` from `DesignSystem/Organisms/MetricSummaryCard.swift` instead.
///
/// This component has been replaced with a unified, fully polished Apple Health-style component.
/// MetricSummaryCard automatically adapts sizing and can be used for both primary and secondary metrics.
///
/// Migration guide:
/// - Replace `DSCompactMetricCard` with `MetricSummaryCard`
/// - Use the `.data(Content(...))` state with proper data binding
/// - The new component provides better accessibility, state management, and visual polish
@available(*, deprecated, message: "Use MetricSummaryCard from DesignSystem/Organisms/MetricSummaryCard.swift instead")
struct DSCompactMetricCard: View {
    let icon: String
    let value: String
    let label: String
    var trend: Double?
    var trendType: DSTrendIndicator.TrendType = .neutral

    private var isEmptyState: Bool {
        value == "––"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(isEmptyState ? .appTextTertiary : .appTextSecondary)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(isEmptyState ? .appTextTertiary : .appText)

                    if trend != nil && !isEmptyState {
                        DSTrendIndicator(
                            trend: trend,
                            trendType: trendType,
                            size: .system(size: 12)
                        )
                    }
                }

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isEmptyState ? .appTextTertiary.opacity(0.7) : .appTextSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.appCard)
        .cornerRadius(10)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        // Steps with positive trend
        DSCompactMetricCard(
            icon: "figure.walk",
            value: "10_532",
            label: "Steps",
            trend: 2_500,
            trendType: .positive
        )
        
        // FFMI with negative trend
        DSCompactMetricCard(
            icon: "figure.arms.open",
            value: "21.8",
            label: "FFMI",
            trend: -0.3,
            trendType: .positive
        )
        
        // Lean mass with no data
        DSCompactMetricCard(
            icon: "figure.arms.open",
            value: "––",
            label: "Lean kg"
        )
        
        HStack(spacing: 12) {
            DSCompactMetricCard(
                icon: "figure.walk",
                value: "8,421",
                label: "Steps"
            )
            
            DSCompactMetricCard(
                icon: "flame.fill",
                value: "2,150",
                label: "Calories"
            )
        }
    }
    .padding()
    .background(Color.appBackground)
}
