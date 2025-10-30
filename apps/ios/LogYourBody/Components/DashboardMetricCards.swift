//
// DashboardMetricCards.swift
// LogYourBody
//
import SwiftUI

// MARK: - Empty Metric Card

struct EmptyMetricCard: View {
    let label: String
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.appBorder, lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Text("--")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.appTextTertiary)
            }
            
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.appTextSecondary)
        }
        .frame(maxWidth: CGFloat.infinity)
        .frame(height: 140)
        .background(Color.appCard)
        .cornerRadius(12)
    }
}

// MARK: - Weight Metric Card

struct WeightMetricCard: View {
    let value: Double
    let unit: String
    let trend: Double?
    let trendUnit: String
    let isInHealthyRange: Bool
    
    private func formatWeightValue(_ value: Double) -> String {
        // If the value is a whole number, don't show decimal places
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            // Show one decimal place for fractional values
            return String(format: "%.1f", value)
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "scalemass")
                    .font(.system(size: 18))
                    .foregroundColor(isInHealthyRange ? .green : .white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                
                VStack(spacing: 8) {
                    Text(formatWeightValue(value))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(unit)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    if let trend = trend {
                        HStack(spacing: 4) {
                            Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 12, weight: .medium))
                            Text("\(String(format: "%.1f", abs(trend))) \(trendUnit)")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(trend > 0 ? .red : .green)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: CGFloat.infinity)
        .frame(height: 140)
        .background(Color.appCard)
        .cornerRadius(12)
    }
}

// MARK: - Photo Options Sheet

struct PhotoOptionsSheet: View {
    @Binding var showCamera: Bool
    @Binding var showPhotoPicker: Bool
    @Environment(\.dismiss)
    var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle
            Capsule()
                .fill(Color.appTextTertiary.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)
            
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.appPrimary.opacity(0.1))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 28))
                        .foregroundColor(.appPrimary)
                }
                
                Text("Add Progress Photo")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.appText)
                
                Text("Capture your transformation")
                    .font(.system(size: 14))
                    .foregroundColor(.appTextSecondary)
            }
            .padding(.vertical, 16)
            
            VStack(spacing: 0) {
                // Take Photo
                Button(
                    action: {
                        dismiss()
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            await MainActor.run {
                                showCamera = true
                            }
                        }
                    },
                    label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Take Photo")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.appText)
                                
                                Text("Use camera for best results")
                                    .font(.system(size: 13))
                                    .foregroundColor(.appTextSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.appTextTertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                )
                
                Divider()
                    .padding(.leading, 80)
                
                // Choose from Library
                Button(
                    action: {
                        dismiss()
                        Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            await MainActor.run {
                                showPhotoPicker = true
                            }
                        }
                    },
                    label: {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.1))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.green)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Choose from Library")
                                    .font(.system(size: 17, weight: .medium))
                                    .foregroundColor(.appText)
                                
                                Text("Select existing photo")
                                    .font(.system(size: 13))
                                    .foregroundColor(.appTextSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.appTextTertiary)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                )
            }
            
            Button(
                action: { dismiss() },
                label: {
                    Text("Cancel")
                        .font(.system(size: 17))
                        .foregroundColor(.appTextSecondary)
                        .frame(maxWidth: CGFloat.infinity)
                        .frame(height: 50)
                }
            )
            .padding(.top, 16)
            .padding(.horizontal, 20)
            
            Spacer()
                .frame(height: 20)
        }
        .background(Color.appCard)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.hidden)
    }
}

// MARK: - Metric Value Display

struct MetricValueDisplay: View {
    let value: Double
    let unit: String
    let label: String
    let trend: Double?
    let trendType: TrendType
    
    enum TrendType {
        case positive // Higher is better (steps, muscle mass)
        case negative // Lower is better (body fat)
        case neutral  // No good/bad direction (weight)
    }
    
    @State private var animatedValue: Double = 0
    
    private func formatValue(_ value: Double) -> String {
        // If the value is a whole number, don't show decimal places
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else {
            // Show one decimal place for fractional values
            return String(format: "%.1f", value)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Value and trend
            HStack(alignment: .bottom, spacing: 6) {
                Text(formatValue(value))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.bottom, 6)
                }
                
                Spacer()
                
                if let trend = trend, abs(trend) > 0.01 {
                    HStack(spacing: 2) {
                        Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.1f", abs(trend)))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(trendColor(for: trend))
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Progress bar with enhanced visibility
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 6)

                    // Target zone indicator
                    let targetStart = 0.3
                    let targetEnd = 0.7
                    let targetWidth = CGFloat(targetEnd - targetStart)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.appPrimary.opacity(0.25))
                        .frame(width: targetWidth * geometry.size.width, height: 6)
                        .offset(x: targetStart * geometry.size.width)

                    // Active progress with glow
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isInTargetZone ? Color.appPrimary : Color.white.opacity(0.7))
                        .frame(width: max(6, normalizedValue * geometry.size.width), height: 6)
                        .shadow(
                            color: isInTargetZone ? Color.appPrimary.opacity(0.5) : Color.clear,
                            radius: 4,
                            x: 0,
                            y: 0
                        )
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: normalizedValue)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            // Label
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            animatedValue = value
        }
        .onChange(of: value) { _, newValue in
            animatedValue = newValue
        }
    }
    
    private var normalizedValue: Double {
        // Normalize based on expected ranges
        switch label.lowercased() {
        case "body fat":
            return min(1.0, max(0, value / 40.0)) // 0-40% range
        case "weight":
            return 0.5 // Always center for weight
        default:
            return 0.5
        }
    }
    
    private var isInTargetZone: Bool {
        // Define target zones
        switch label.lowercased() {
        case "body fat":
            return value >= 10 && value <= 20
        case "weight":
            return true // Always in zone for weight
        default:
            return true
        }
    }
    
    private func trendColor(for trend: Double) -> Color {
        switch trendType {
        case .positive:
            return trend > 0 ? .green : .red
        case .negative:
            return trend > 0 ? .red : .green
        case .neutral:
            return .white.opacity(0.6)
        }
    }
}

// MARK: - Empty Metric Placeholder

struct EmptyMetricPlaceholder: View {
    let label: String
    let unit: String
    
    var body: some View {
        VStack(spacing: 0) {
            // Value placeholder
            HStack(alignment: .bottom, spacing: 6) {
                Text("––")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.2))
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white.opacity(0.15))
                        .padding(.bottom, 6)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Empty progress bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.1))
                .frame(height: 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            
            // Label
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Compact Metric Card

struct CompactMetricCard: View {
    let icon: String
    let value: String
    let label: String
    let trend: Double?
    let trendType: MetricValueDisplay.TrendType
    var isPlaceholder: Bool = false
    
    private var accessibilityLabel: String {
        if isPlaceholder {
            return "\(label): No data available"
        } else {
            var result = "\(label): \(value)"
            if let trend = trend {
                let direction = trend > 0 ? "up" : "down"
                result += ", \(direction) \(abs(trend))"
            }
            return result
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isPlaceholder ? .appTextTertiary : .appTextSecondary)
                .frame(height: 20)
            
            // Value with trend
            HStack(spacing: 4) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(isPlaceholder ? .appTextTertiary : .white)
                
                if let trend = trend, !isPlaceholder {
                    Image(systemName: trend > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(trendColor(for: trend))
                }
            }
            
            // Label
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.appTextSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80) // Smaller than main cards
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appCard)
        .cornerRadius(8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
    
    private func trendColor(for trend: Double) -> Color {
        switch trendType {
        case .positive:
            return trend > 0 ? .green : .red
        case .negative:
            return trend > 0 ? .red : .green
        case .neutral:
            return .appTextSecondary
        }
    }
}
