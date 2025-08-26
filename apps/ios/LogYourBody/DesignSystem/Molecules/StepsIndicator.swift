//
// StepsIndicator.swift
// LogYourBody
//
import SwiftUI

// MARK: - StepsIndicator Molecule

/// A compact steps indicator for headers
struct StepsIndicator: View {
    let steps: Int
    var showIcon: Bool = true
    
    private var formattedSteps: String {
        if steps >= 10_000 {
            return String(format: "%.1fK", Double(steps) / 1_000)
        } else if steps >= 1_000 {
            return String(format: "%.1fK", Double(steps) / 1_000)
        } else {
            return "\(steps)"
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            if showIcon {
                Image(systemName: "figure.walk")
                    .font(.system(size: 14))
                    .foregroundColor(.appTextSecondary)
            }
            
            Text(formattedSteps)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.appText)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        StepsIndicator(steps: 0)
        StepsIndicator(steps: 999)
        StepsIndicator(steps: 1_234)
        StepsIndicator(steps: 10_532)
        StepsIndicator(steps: 25_000)
        
        HStack {
            StepsIndicator(steps: 8_421, showIcon: false)
            Text("steps today")
                .font(.system(size: 14))
                .foregroundColor(.appTextSecondary)
        }
    }
    .padding()
    .background(Color.appBackground)
}
