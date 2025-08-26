//
// DSTrendIndicator.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSTrendIndicator Atom

/// Displays a trend with an arrow and value
struct DSTrendIndicator: View {
    let trend: Double?
    let trendType: TrendType
    var showSign: Bool = true
    var size: Font = .system(size: 12)
    
    enum TrendType {
        case positive  // Up is good (e.g., steps, FFMI)
        case negative  // Down is good (e.g., body fat)
        case neutral   // No preference (e.g., weight)
        
        func color(for trend: Double) -> Color {
            switch self {
            case .positive:
                return trend > 0 ? .green : (trend < 0 ? .red : .appTextSecondary)
            case .negative:
                return trend < 0 ? .green : (trend > 0 ? .red : .appTextSecondary)
            case .neutral:
                return .appTextSecondary
            }
        }
        
        func icon(for trend: Double) -> String {
            if trend > 0 {
                return "arrow.up"
            } else if trend < 0 {
                return "arrow.down"
            } else {
                return "minus"
            }
        }
    }
    
    var body: some View {
        if let trend = trend, trend != 0 {
            HStack(spacing: 4) {
                Image(systemName: trendType.icon(for: trend))
                    .font(size.weight(.medium))
                
                Text(formatTrend(trend))
                    .font(size.weight(.medium))
            }
            .foregroundColor(trendType.color(for: trend))
        }
    }
    
    private func formatTrend(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        
        if showSign && value > 0 {
            formatter.positivePrefix = "+"
        }
        
        return formatter.string(from: NSNumber(value: abs(value))) ?? ""
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Positive trends
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Steps (positive)").font(.caption)
                DSTrendIndicator(trend: 2_500, trendType: .positive)
                DSTrendIndicator(trend: -1_000, trendType: .positive)
                DSTrendIndicator(trend: 0, trendType: .positive)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Body Fat (negative)").font(.caption)
                DSTrendIndicator(trend: 0.5, trendType: .negative)
                DSTrendIndicator(trend: -1.2, trendType: .negative)
                DSTrendIndicator(trend: 0, trendType: .negative)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Weight (neutral)").font(.caption)
                DSTrendIndicator(trend: 2.3, trendType: .neutral)
                DSTrendIndicator(trend: -1.5, trendType: .neutral)
                DSTrendIndicator(trend: 0, trendType: .neutral)
            }
        }
    }
    .padding()
    .background(Color.appBackground)
}
