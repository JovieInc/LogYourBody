//
// DeveloperTapIndicator.swift
// LogYourBody
//
import SwiftUI

// MARK: - Molecule: Developer Tap Indicator

struct DeveloperTapIndicator: View {
    let remainingTaps: Int
    let totalTaps: Int

    init(remainingTaps: Int, totalTaps: Int = 7) {
        self.remainingTaps = remainingTaps
        self.totalTaps = totalTaps
    }

    private var progress: Double {
        Double(totalTaps - remainingTaps) / Double(totalTaps)
    }

    var body: some View {
        if remainingTaps > 0 && remainingTaps < totalTaps {
            HStack(spacing: 4) {
                // Progress dots
                HStack(spacing: 2) {
                    ForEach(0..<totalTaps, id: \.self) { index in
                        Circle()
                            .fill(
                                index < (totalTaps - remainingTaps)
                                    ? Color.linearPurple
                                    : Color.linearBorder
                            )
                            .frame(width: 4, height: 4)
                    }
                }

                // Remaining count
                Text("\(remainingTaps)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.linearTextTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.linearCard)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.linearBorder, lineWidth: 1)
                    )
            )
            .transition(.opacity.combined(with: .scale))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        DeveloperTapIndicator(remainingTaps: 7)
        DeveloperTapIndicator(remainingTaps: 5)
        DeveloperTapIndicator(remainingTaps: 3)
        DeveloperTapIndicator(remainingTaps: 1)
        DeveloperTapIndicator(remainingTaps: 0)
    }
    .padding()
    .background(Color.black)
}
