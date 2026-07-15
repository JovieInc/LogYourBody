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
        VStack(spacing: 8) {
            Text(title)
                .font(theme.typography.displayMedium)
                .foregroundColor(theme.colors.text)
                .multilineTextAlignment(.center)

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(theme.typography.bodyMedium)
                    .foregroundColor(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Auth service status

/// A single recovery surface for authentication-provider availability. Keeping this
/// shared prevents Login and Sign Up from drifting into different failure states.
struct AuthServiceStatusBanner: View {
    @Environment(\.theme)
    private var theme

    let errorMessage: String?
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Label("Connection unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(theme.typography.labelMedium)
                    .foregroundColor(theme.colors.text)
                    .accessibilityLabel("Connection unavailable")

                Text(errorMessage)
                    .font(theme.typography.captionLarge)
                    .foregroundColor(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                BaseButton(
                    isRetrying ? "Retrying connection" : "Retry connection",
                    configuration: ButtonConfiguration(
                        style: .custom(background: .jovieSurfaceElevated, foreground: .jovieText),
                        isLoading: isRetrying,
                        fullWidth: true,
                        cornerRadius: JovieTokens.controlRadius
                    ),
                    action: onRetry
                )
                .accessibilityHint("Tries to reconnect to the sign-in service.")
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: theme.colors.info))
                        .accessibilityHidden(true)

                    Text("Connecting to sign-in service")
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Connecting to sign-in service")
            }
        }
        .padding(16)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.cardRadius,
            tint: errorMessage == nil ? theme.colors.info : theme.colors.error,
            tintOpacity: 0.08,
            borderColor: errorMessage == nil ? theme.colors.info : theme.colors.error,
            borderOpacity: 0.3
        )
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
