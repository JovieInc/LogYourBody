//
// BiometricAuthView.swift
// LogYourBody
//
import SwiftUI

// MARK: - BiometricAuthView Organism

struct BiometricAuthView: View {
    enum BiometricType {
        case faceID
        case touchID
        
        var icon: String {
            switch self {
            case .faceID:
                return "faceid"
            case .touchID:
                return "touchid"
            }
        }
        
        var title: String {
            switch self {
            case .faceID:
                return "Face ID"
            case .touchID:
                return "Touch ID"
            }
        }
    }
    
    let biometricType: BiometricType
    let onAuthenticate: () -> Void
    let onUsePassword: () -> Void
    
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 40) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.appPrimary.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: biometricType.icon)
                    .font(.system(size: 50))
                    .foregroundColor(.appPrimary)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
            }
            .onAppear {
                isAnimating = true
            }
            
            // Title & Instructions
            VStack(spacing: 16) {
                Text("Unlock with \(biometricType.title)")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.appText)
                
                Text("Authenticate to access your account")
                    .font(.system(size: 16))
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
            }
            
            // Actions
            VStack(spacing: 16) {
                DSAuthButton(
                    title: "Use \(biometricType.title)",
                    style: .primary,
                    icon: biometricType.icon,
                    action: onAuthenticate
                )
                
                DSAuthLink(
                    title: "Use Password Instead",
                    action: onUsePassword
                )
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        
        BiometricAuthView(
            biometricType: .faceID,
            onAuthenticate: {},
            onUsePassword: {}
        )
        
        Spacer()
    }
    .background(Color.appBackground)
}
