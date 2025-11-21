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

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 4) {
                Text("Need help unlocking?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.linearTextSecondary)

                Text("\(biometricType.title) fell back to your passcode")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.linearText)
            }

            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .fill(Color.linearBorder.opacity(0.25))
                        .frame(width: 130, height: 130)

                    Circle()
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.appPrimary, Color.linearBlue]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 12
                        )
                        .frame(width: 130, height: 130)

                    Image(systemName: biometricType.icon)
                        .font(.system(size: 40))
                        .foregroundColor(Color.linearText)
                        .scaleEffect(pulse ? 1.05 : 0.95)
                        .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                }
                .onAppear {
                    pulse = true
                }

                VStack(spacing: 6) {
                    Text("Try \(biometricType.title) again")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.linearText)

                    Text("Make sure the TrueDepth camera is clean and visible.")
                        .font(.system(size: 15))
                        .foregroundColor(.linearTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                BaseButton(
                    "Retry \(biometricType.title)",
                    configuration: ButtonConfiguration(
                        style: .primary,
                        fullWidth: true,
                        icon: biometricType.icon
                    ),
                    action: onAuthenticate
                )
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.liquidBg.opacity(0.85))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(Color.appPrimary.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.linearBlue.opacity(0.35), radius: 25, x: 0, y: 15)
            )

            VStack(spacing: 8) {
                Text("Use your passcode if Face ID still doesn't recognize you.")
                    .font(.system(size: 13))
                    .foregroundColor(.linearTextTertiary)
                    .multilineTextAlignment(.center)

                DSAuthLink(
                    title: "Use Password Instead",
                    action: onUsePassword
                )
            }
        }
        .padding(.horizontal, 20)
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
