//
//  ProgressRing.swift
//  LogYourBody
//
//  Animated circular progress ring for goals
//

import SwiftUI

struct ProgressRing: View {
    let progress: Double  // 0.0 to 1.0
    let size: CGFloat
    let lineWidth: CGFloat
    let accentColor: Color
    let showPercentage: Bool

    @State private var animatedProgress: Double = 0

    init(
        progress: Double,
        size: CGFloat = 80,
        lineWidth: CGFloat = 8,
        accentColor: Color = Color(hex: "#6EE7F0"),
        showPercentage: Bool = false
    ) {
        self.progress = min(max(progress, 0), 1.0)  // Clamp 0-1
        self.size = size
        self.lineWidth = lineWidth
        self.accentColor = accentColor
        self.showPercentage = showPercentage
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(
                    Color.white.opacity(0.1),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)

            // Progress ring with gradient
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            accentColor,
                            accentColor.opacity(0.7),
                            accentColor
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .shadow(
                    color: accentColor.opacity(0.3),
                    radius: 4,
                    x: 0,
                    y: 0
                )

            // Percentage text (optional)
            if showPercentage {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.25, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                animatedProgress = newValue
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(hex: "#0B0D10")
            .ignoresSafeArea()

        VStack(spacing: 40) {
            ProgressRing(progress: 0.65, size: 100, lineWidth: 10)

            ProgressRing(
                progress: 0.45,
                size: 80,
                lineWidth: 8,
                showPercentage: true
            )

            ProgressRing(
                progress: 0.92,
                size: 60,
                lineWidth: 6,
                accentColor: .green
            )
        }
    }
}
