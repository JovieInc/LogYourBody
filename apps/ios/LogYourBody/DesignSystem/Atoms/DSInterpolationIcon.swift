//
// DSInterpolationIcon.swift
// LogYourBody
//
// Icon indicator for interpolated/estimated metric values
// Shows ~ icon with optional tooltip explaining confidence level
//

import SwiftUI

struct DSInterpolationIcon: View {
    let confidenceLevel: InterpolatedMetric.ConfidenceLevel?
    let isLastKnown: Bool
    @State private var showTooltip = false

    var body: some View {
        Button(action: {
            showTooltip.toggle()
        }) {
            Image(systemName: isLastKnown ? "clock.arrow.circlepath" : "waveform.path")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(iconColor)
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $showTooltip, arrowEdge: .top) {
            tooltipContent
                .presentationCompactAdaptation(.popover)
        }
    }

    private var iconColor: Color {
        if isLastKnown {
            return Color(hex: "#6EE7F0").opacity(0.7)  // Accent color, dimmed
        }

        guard let level = confidenceLevel else {
            return .orange
        }

        switch level {
        case .high:
            return .green.opacity(0.8)
        case .medium:
            return .orange.opacity(0.8)
        case .low:
            return .red.opacity(0.7)
        }
    }

    private var tooltipContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isLastKnown {
                Text("Last Known Value")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                Text("This is your most recent logged measurement. No data exists for this date.")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Estimated Value")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)

                if let level = confidenceLevel {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(iconColor)
                            .frame(width: 8, height: 8)

                        Text("\(level.rawValue.capitalized) Confidence")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    Text(confidenceDescription(for: level))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 280)
        .background(Color.black.opacity(0.9))
        .cornerRadius(12)
    }

    private func confidenceDescription(for level: InterpolatedMetric.ConfidenceLevel) -> String {
        switch level {
        case .high:
            return "Estimated from data logged within the past week. High accuracy."
        case .medium:
            return "Estimated from data logged 8-14 days away. Moderate accuracy."
        case .low:
            return "Estimated from data logged 15-30 days away. Lower accuracy."
        }
    }
}

#Preview {
    ZStack {
        Color(hex: "#0B0D10")
            .ignoresSafeArea()

        VStack(spacing: 30) {
            HStack {
                Text("18.5%")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                DSInterpolationIcon(confidenceLevel: .high, isLastKnown: false)
            }

            HStack {
                Text("82.3 kg")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                DSInterpolationIcon(confidenceLevel: .medium, isLastKnown: false)
            }

            HStack {
                Text("19.2")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                DSInterpolationIcon(confidenceLevel: .low, isLastKnown: false)
            }

            HStack {
                Text("75.0 kg")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(.white)
                DSInterpolationIcon(confidenceLevel: nil, isLastKnown: true)
            }
        }
    }
}
