//
//  BiometricAuthView.swift
//  LogYourBody
//
//  Focused recovery state for the app lock.
//
import SwiftUI

struct BiometricAuthView: View {
    enum BiometricType {
        case faceID
        case touchID

        var icon: String {
            switch self {
            case .faceID: "faceid"
            case .touchID: "touchid"
            }
        }

        var title: String {
            switch self {
            case .faceID: "Face ID"
            case .touchID: "Touch ID"
            }
        }

        var recoveryGuidance: String {
            switch self {
            case .faceID: "Keep the TrueDepth camera visible, then try again."
            case .touchID: "Keep your finger on the sensor, then try again."
            }
        }
    }

    let biometricType: BiometricType
    let onAuthenticate: () -> Void
    let onUsePassword: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: JovieTokens.sectionGap) {
            Image(systemName: biometricType.icon)
                .font(.system(.largeTitle, design: .default).weight(.medium))
                .foregroundStyle(Color.jovieText)
                .frame(width: 72, height: 72)
                .background(Color.jovieSurfaceElevated, in: Circle())
                .overlay(Circle().stroke(Color.jovieHairline, lineWidth: 1))
                .symbolEffect(.pulse, options: reduceMotion ? .nonRepeating : .repeating)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("\(biometricType.title) didn’t complete")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.jovieText)
                    .multilineTextAlignment(.center)

                Text(biometricType.recoveryGuidance)
                    .font(.body)
                    .foregroundStyle(Color.jovieTextSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: JovieTokens.itemGap) {
                BaseButton(
                    "Try \(biometricType.title) again",
                    configuration: ButtonConfiguration(
                        style: .custom(background: .jovieAction, foreground: .jovieActionText),
                        fullWidth: true,
                        icon: biometricType.icon
                    ),
                    action: onAuthenticate
                )
                .accessibilityHint("Starts \(biometricType.title) authentication again")

                Button(action: onUsePassword) {
                    Text("Continue without \(biometricType.title)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.jovieTextSecondary)
                        .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .jovieTouchTarget()
                .accessibilityHint("Closes the biometric lock")
            }
        }
        .padding(JovieTokens.sectionGap)
        .frame(maxWidth: 440)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.cardRadius,
            tint: .white,
            tintOpacity: 0.025,
            borderColor: .jovieHairline
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    BiometricAuthView(
        biometricType: .faceID,
        onAuthenticate: {},
        onUsePassword: {}
    )
    .padding()
    .background(Color.jovieCanvas)
    .preferredColorScheme(.dark)
}
