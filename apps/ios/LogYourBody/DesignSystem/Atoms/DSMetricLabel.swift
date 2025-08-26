//
// DSMetricLabel.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSMetricLabel Atom

/// A simple label for metrics
struct DSMetricLabel: View {
    let text: String
    var size: Font = .system(size: 14)
    var weight: Font.Weight = .regular
    var color: Color = .appTextSecondary
    
    var body: some View {
        Text(text)
            .font(size.weight(weight))
            .foregroundColor(color)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        DSMetricLabel(text: "Weight")
        
        DSMetricLabel(
            text: "Body Fat",
            weight: .medium
        )
        
        DSMetricLabel(
            text: "FFMI",
            size: .system(size: 12),
            color: .appTextTertiary
        )
        
        DSMetricLabel(
            text: "Steps",
            size: .system(size: 16),
            weight: .semibold,
            color: .appText
        )
    }
    .padding()
    .background(Color.appBackground)
}
