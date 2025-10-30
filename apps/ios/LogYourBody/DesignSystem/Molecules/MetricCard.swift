//
// MetricCard.swift
// LogYourBody
//
import SwiftUI

// MARK: - MetricCard Molecule

/// A card displaying a metric value with label and optional trend
struct DSMetricCard: View {
    let value: String
    let unit: String?
    let label: String
    var trend: Double?
    var trendType: DSTrendIndicator.TrendType = .neutral
    var height: CGFloat = 120 // Increased for better visual breathing room
    var isInteractive: Bool = false
    var onTap: (() -> Void)?
    
    @State private var isPressed = false
    
    var body: some View {
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
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.appCard)
        .cornerRadius(12)
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

#Preview {
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
        
        // Custom height cards
        HStack(spacing: 16) {
            DSMetricCard(
                value: "10,234",
                unit: "steps",
                label: "Daily Steps",
                trend: 1_234,
                trendType: .positive,
                height: 120
            )
            
            DSMetricCard(
                value: "2,350",
                unit: "cal",
                label: "Calories",
                height: 120
            )
        }
    }
    .padding()
    .background(Color.appBackground)
}
