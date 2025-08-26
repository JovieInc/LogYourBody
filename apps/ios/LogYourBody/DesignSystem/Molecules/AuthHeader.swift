//
// AuthHeader.swift
// LogYourBody
//
import SwiftUI

// MARK: - AuthHeader Molecule

struct AuthHeader: View {
    let title: String
    let subtitle: String?
    
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 36, weight: .bold, design: .default))
                .foregroundColor(.appText)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundColor(.appTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        AuthHeader(
            title: "LogYourBody",
            subtitle: "Track your fitness journey"
        )
        
        AuthHeader(
            title: "Welcome Back",
            subtitle: "Sign in to continue tracking your progress"
        )
        
        AuthHeader(
            title: "Create Account"
        )
    }
    .padding()
    .background(Color.appBackground)
}
