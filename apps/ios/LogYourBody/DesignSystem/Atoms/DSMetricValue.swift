//
// DSMetricValue.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSMetricValue Atom

/// Displays a metric value with optional unit
struct DSMetricValue: View {
    let value: String
    let unit: String?
    var size: Font = .system(size: 28, weight: .bold)
    var color: Color = .appText
    var unitSize: Font = .system(size: 16, weight: .medium)
    var spacing: CGFloat = 2
    
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: spacing) {
            Text(value)
                .font(size)
                .foregroundColor(color)
            
            if let unit = unit {
                Text(unit)
                    .font(unitSize)
                    .foregroundColor(color.opacity(0.7))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        DSMetricValue(value: "165", unit: "lbs")
        
        DSMetricValue(
            value: "22.5",
            unit: "%",
            size: .system(size: 36, weight: .bold)
        )
        
        DSMetricValue(
            value: "10,532",
            unit: "steps",
            size: .system(size: 24, weight: .semibold),
            color: .appPrimary
        )
        
        DSMetricValue(value: "––", unit: "kg")
    }
    .padding()
    .background(Color.appBackground)
}
