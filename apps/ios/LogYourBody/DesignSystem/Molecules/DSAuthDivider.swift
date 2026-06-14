//
// DSAuthDivider.swift
// LogYourBody
//
import SwiftUI

// MARK: - DSAuthDivider Molecule

struct DSAuthDivider: View {
    @Environment(\.theme)
    private var theme

    let text: String

    init(text: String = "or") {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)

            Text(text)
                .font(theme.typography.captionLarge)
                .foregroundColor(theme.colors.textSecondary)

            Rectangle()
                .fill(theme.colors.border)
                .frame(height: 1)
        }
        .padding(.vertical, 20)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        DSAuthDivider()

        DSAuthDivider(text: "or continue with")

        VStack(spacing: 16) {
            BaseButton(
                "Sign In",
                configuration: ButtonConfiguration(
                    style: .custom(background: .white, foreground: .black),
                    fullWidth: true
                ),
                action: {}
            )
            DSAuthDivider()
            SocialLoginButton(provider: .apple, action: {})
        }
    }
    .padding()
    .background(Color.appBackground)
}
