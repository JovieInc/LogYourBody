//
// AuthHeader.swift
// LogYourBody
//
import SwiftUI

// MARK: - AuthHeader Molecule

struct AuthHeader: View {
    @Environment(\.theme)
    private var theme

    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(theme.typography.displayMedium)
                .foregroundColor(theme.colors.text)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.textSecondary)
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
