//
// DSLogo.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSLogo Atom

/// The app logo with customizable size and color
struct DSLogo: View {
    var size: CGFloat = 80
    var color: Color = .white
    var showText: Bool = true
    var textSize: CGFloat = 28
    var textWeight: Font.Weight = .semibold
    var spacing: CGFloat = 8
    
    var body: some View {
        VStack(spacing: spacing) {
            Image(systemName: "figure.walk.circle.fill")
                .font(.system(size: size))
                .foregroundColor(color)
            
            if showText {
                Text("LogYourBody")
                    .font(.system(size: textSize, weight: textWeight))
                    .foregroundColor(color)
            }
        }
    }
}

// MARK: - DSLogoAnimated

/// An animated version of the logo with scale and fade effects
struct DSLogoAnimated: View {
    var size: CGFloat = 80
    var color: Color = .white
    var showText: Bool = true
    var textSize: CGFloat = 28
    var animationDuration: Double = 0.6
    
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    
    var body: some View {
        DSLogo(
            size: size,
            color: color,
            showText: showText,
            textSize: textSize
        )
        .scaleEffect(logoScale)
        .opacity(logoOpacity)
        .onAppear {
            withAnimation(.easeOut(duration: animationDuration)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // Different sizes
        HStack(spacing: 40) {
            DSLogo(size: 40, textSize: 14)
            DSLogo(size: 60, textSize: 20)
            DSLogo(size: 80, textSize: 28)
        }
        
        // Without text
        HStack(spacing: 40) {
            DSLogo(size: 50, showText: false)
            DSLogo(size: 80, showText: false)
            DSLogo(size: 120, showText: false)
        }
        
        // Different colors
        HStack(spacing: 40) {
            DSLogo(size: 60, color: .appPrimary, textSize: 20)
            DSLogo(size: 60, color: .orange, textSize: 20)
            DSLogo(size: 60, color: .green, textSize: 20)
        }
        
        // Animated version
        DSLogoAnimated()
            .padding()
            .background(Color.appCard)
            .cornerRadius(12)
    }
    .padding()
    .background(Color.appBackground)
}