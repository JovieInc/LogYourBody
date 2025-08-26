//
// DSProgressBar.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSProgressBar Atom

/// A linear progress bar with optimized performance
struct DSProgressBar: View {
    let progress: Double
    var height: CGFloat = 8
    var backgroundColor: Color = .white.opacity(0.2)
    var foregroundColor: Color = .white
    var cornerRadius: CGFloat = 4
    var animationDuration: Double = 0.4
    
    @State private var animatedProgress: Double = 0
    
    private var normalizedProgress: Double {
        min(1.0, max(0.0, progress))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(backgroundColor)
                    .frame(height: height)
                
                // Progress
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(foregroundColor)
                    .frame(width: geometry.size.width * animatedProgress, height: height)
                    .animation(
                        .spring(response: animationDuration, dampingFraction: 0.8),
                        value: animatedProgress
                    )
            }
        }
        .frame(height: height)
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
    VStack(spacing: 30) {
        VStack(spacing: 16) {
            Text("Different Progress Values")
                .font(.headline)
                .foregroundColor(.appText)
            
            DSProgressBar(progress: 0.1)
            DSProgressBar(progress: 0.3)
            DSProgressBar(progress: 0.5)
            DSProgressBar(progress: 0.75)
            DSProgressBar(progress: 1.0)
        }
        
        VStack(spacing: 16) {
            Text("Different Heights")
                .font(.headline)
                .foregroundColor(.appText)
            
            DSProgressBar(progress: 0.6, height: 4)
            DSProgressBar(progress: 0.6, height: 8)
            DSProgressBar(progress: 0.6, height: 12)
            DSProgressBar(progress: 0.6, height: 16)
        }
        
        VStack(spacing: 16) {
            Text("Different Colors")
                .font(.headline)
                .foregroundColor(.appText)
            
            DSProgressBar(
                progress: 0.7,
                backgroundColor: .appBorder,
                foregroundColor: .appPrimary
            )
            DSProgressBar(
                progress: 0.5,
                backgroundColor: .red.opacity(0.2),
                foregroundColor: .red
            )
            DSProgressBar(
                progress: 0.9,
                backgroundColor: .green.opacity(0.2),
                foregroundColor: .green
            )
        }
    }
    .padding()
    .background(Color.appBackground)
}