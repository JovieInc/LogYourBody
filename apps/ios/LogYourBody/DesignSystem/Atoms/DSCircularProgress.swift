//
// DSCircularProgress.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSCircularProgress Atom

/// A circular progress indicator with optimized performance
struct DSCircularProgress: View {
    let progress: Double
    var size: CGFloat = 100
    var lineWidth: CGFloat = 3
    var backgroundColor: Color = .white.opacity(0.2)
    var foregroundColor: Color = .white
    var animationDuration: Double = 0.6
    var showPercentage: Bool = false
    var percentageFontSize: CGFloat = 14
    
    @State private var animatedProgress: Double = 0
    
    private var normalizedProgress: Double {
        min(1.0, max(0.0, progress))
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(backgroundColor, lineWidth: lineWidth * 0.3)
                .frame(width: size, height: size)
            
            // Progress arc
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    foregroundColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(
                    .spring(response: animationDuration, dampingFraction: 0.8),
                    value: animatedProgress
                )
            
            // Optional percentage display
            if showPercentage {
                Text("\(Int(animatedProgress * 100))%")
                    .font(.system(size: percentageFontSize, weight: .semibold))
                    .foregroundColor(foregroundColor)
            }
        }
        .onAppear {
            animatedProgress = normalizedProgress
        }
        .onChange(of: normalizedProgress) { newValue in
            animatedProgress = newValue
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        HStack(spacing: 40) {
            // Different sizes
            DSCircularProgress(progress: 0.75, size: 60)
            DSCircularProgress(progress: 0.5, size: 80)
            DSCircularProgress(progress: 0.25, size: 100)
        }
        
        HStack(spacing: 40) {
            // With percentage display
            DSCircularProgress(
                progress: 0.6,
                showPercentage: true,
                percentageFontSize: 12
            )
            DSCircularProgress(
                progress: 0.85,
                size: 120,
                lineWidth: 6,
                showPercentage: true,
                percentageFontSize: 20
            )
            DSCircularProgress(
                progress: 0.3,
                size: 80,
                showPercentage: true
            )
        }
        
        HStack(spacing: 40) {
            // Different colors
            DSCircularProgress(
                progress: 0.8,
                backgroundColor: .gray.opacity(0.3),
                foregroundColor: .appPrimary,
                showPercentage: true
            )
            DSCircularProgress(
                progress: 0.4,
                backgroundColor: .red.opacity(0.2),
                foregroundColor: .red
            )
            DSCircularProgress(
                progress: 0.9,
                backgroundColor: .green.opacity(0.2),
                foregroundColor: .green
            )
        }
    }
    .padding()
    .background(Color.appBackground)
}
