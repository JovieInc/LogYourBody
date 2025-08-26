//
// CompactMetricCard.swift
// LogYourBody
//
import SwiftUI

// MARK: - CompactMetricCard Molecule

/// A compact card for secondary metrics with icon
struct DSCompactMetricCard: View {
    let icon: String
    let value: String
    let label: String
    var trend: Double?
    var trendType: DSTrendIndicator.TrendType = .neutral
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.appTextSecondary)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(value)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.appText)
                    
                    if trend != nil {
                        DSTrendIndicator(
                            trend: trend,
                            trendType: trendType,
                            size: .system(size: 11)
                        )
                    }
                }
                
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.appTextSecondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
