//
// SecondaryMetricsRow.swift
// LogYourBody
//
import SwiftUI

// MARK: - SecondaryMetricsRow Organism

/// Displays secondary metrics (Steps, FFMI, Lean Mass)
struct SecondaryMetricsRow: View {
    let steps: Int?
    let ffmi: Double?
    let leanMass: Double?
    let stepsTrend: Int?
    let ffmiTrend: Double?
    let leanMassTrend: Double?
    let weightUnit: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Steps
            DSCompactMetricCard(
                icon: "figure.walk",
                value: formatSteps(steps),
                label: "Steps",
                trend: stepsTrend.map { Double($0) },
                trendType: .positive
            )
            
            // FFMI
            DSCompactMetricCard(
                icon: "figure.arms.open",
                value: ffmi != nil ? String(format: "%.1f", ffmi!) : "––",
                label: "FFMI",
                trend: ffmiTrend,
                trendType: .positive
            )
            
            // Lean Mass
            DSCompactMetricCard(
                icon: "figure.arms.open",
                value: leanMass != nil ? "\(Int(leanMass!))" : "––",
                label: "Lean \(weightUnit)",
                trend: leanMassTrend,
                trendType: .positive
            )
        }
        .padding(.horizontal, 20)
    }
    
    private func formatSteps(_ steps: Int?) -> String {
        guard let steps = steps else { return "––" }
        
        if steps >= 10_000 {
            return String(format: "%.1fK", Double(steps) / 1_000)
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = ","
            return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // With all data
        SecondaryMetricsRow(
            steps: 8_421,
            ffmi: 21.8,
            leanMass: 145,
            stepsTrend: 2_500,
            ffmiTrend: 0.3,
            leanMassTrend: 2.1,
            weightUnit: "lbs"
        )
        
        // Partial data
        SecondaryMetricsRow(
            steps: 12_532,
            ffmi: nil,
            leanMass: 65.5,
            stepsTrend: -1_000,
            ffmiTrend: nil,
            leanMassTrend: nil,
            weightUnit: "kg"
        )
        
        // Empty state
        SecondaryMetricsRow(
            steps: nil,
            ffmi: nil,
            leanMass: nil,
            stepsTrend: nil,
            ffmiTrend: nil,
            leanMassTrend: nil,
            weightUnit: "lbs"
        )
    }
    .background(Color.appBackground)
}
