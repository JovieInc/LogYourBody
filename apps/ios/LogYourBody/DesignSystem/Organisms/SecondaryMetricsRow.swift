//
// SecondaryMetricsRow.swift
// LogYourBody
//
import SwiftUI

// MARK: - SecondaryMetricsRow Organism

/// Displays secondary metrics (Steps, FFMI, Lean Mass) with FFMI being interactive
struct SecondaryMetricsRow: View {
    let steps: Int?
    let ffmi: Double?
    let leanMass: Double?
    let stepsTrend: Int?
    let ffmiTrend: Double?
    let leanMassTrend: Double?
    let weightUnit: String

    @Binding var displayMode: DashboardDisplayMode

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

            // FFMI - Tappable
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    displayMode = .ffmiChart
                }
                // Haptic feedback
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            } label: {
                DSCompactMetricCard(
                    icon: "figure.arms.open",
                    value: ffmi != nil ? String(format: "%.1f", ffmi!) : "––",
                    label: "FFMI",
                    trend: ffmiTrend,
                    trendType: .positive
                )
                .scaleEffect(displayMode == .ffmiChart ? 1.05 : 1.0)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(displayMode == .ffmiChart ? Color.liquidAccent : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())

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
            weightUnit: "lbs",
            displayMode: .constant(.photo)
        )

        // Partial data - FFMI selected
        SecondaryMetricsRow(
            steps: 12_532,
            ffmi: 19.5,
            leanMass: 65.5,
            stepsTrend: -1_000,
            ffmiTrend: nil,
            leanMassTrend: nil,
            weightUnit: "kg",
            displayMode: .constant(.ffmiChart)
        )

        // Empty state
        SecondaryMetricsRow(
            steps: nil,
            ffmi: nil,
            leanMass: nil,
            stepsTrend: nil,
            ffmiTrend: nil,
            leanMassTrend: nil,
            weightUnit: "lbs",
            displayMode: .constant(.photo)
        )
    }
    .background(Color.appBackground)
}
