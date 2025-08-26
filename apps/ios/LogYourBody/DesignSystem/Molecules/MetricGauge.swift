//
// MetricGauge.swift
// LogYourBody
//
import SwiftUI

// MARK: - MetricGauge Molecule

/// A circular gauge displaying a metric with progress
struct DSMetricGauge: View {
    let value: Double
    let maxValue: Double
    let label: String
    let unit: String?
    var size = CGSize(width: 100, height: 100)
    var lineWidth: CGFloat = 3
    
    private var normalizedValue: Double {
        min(1.0, max(0.0, value / maxValue))
    }
    
    private var displayValue: String {
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
    
    var body: some View {
        ZStack {
            // Progress ring
            DSCircularProgress(
                progress: normalizedValue,
                size: size.width,
                lineWidth: lineWidth,
                backgroundColor: .white.opacity(0.2),
                foregroundColor: .white
            )
            
            // Content
            VStack(spacing: 2) {
                DSMetricValue(
                    value: displayValue,
                    unit: unit,
                    size: .system(size: 28, weight: .bold),
                    color: .white,
                    unitSize: .system(size: 12, weight: .regular),
                    spacing: 0
                )
                
                DSMetricLabel(
                    text: label,
                    size: .system(size: 12),
                    weight: .regular,
                    color: .white.opacity(0.6)
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        HStack(spacing: 30) {
            DSMetricGauge(
                value: 7_500,
                maxValue: 10_000,
                label: "Steps",
                unit: nil
            )
            
            DSMetricGauge(
                value: 2_150,
                maxValue: 3_000,
                label: "Calories",
                unit: "cal"
            )
            
            DSMetricGauge(
                value: 45,
                maxValue: 60,
                label: "Active",
                unit: "min"
            )
        }
        
        // Different sizes
        HStack(spacing: 20) {
            DSMetricGauge(
                value: 0.8,
                maxValue: 1.0,
                label: "Goal",
                unit: nil,
                size: CGSize(width: 60, height: 60),
                lineWidth: 2
            )
            
            DSMetricGauge(
                value: 12_500,
                maxValue: 15_000,
                label: "Steps",
                unit: nil,
                size: CGSize(width: 120, height: 120),
                lineWidth: 4
            )
        }
    }
    .padding()
    .background(Color.black)
}
