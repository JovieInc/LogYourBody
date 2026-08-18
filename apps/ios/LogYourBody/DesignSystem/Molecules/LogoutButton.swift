//
// LogoutButton.swift
// LogYourBody
//
import SwiftUI

// MARK: - Logout Button Molecule

struct LogoutButton: View {
    let action: () -> Void

    var body: some View {
        BaseButton(
            "Log Out",
            configuration: ButtonConfiguration(
                style: .destructive,
                size: .medium,
                fullWidth: true,
                icon: "rectangle.portrait.and.arrow.right"
            ),
            action: action
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        LogoutButton {
            // Logout action
        }

        LogoutButton {
            // Logout action
        }
        .disabled(true)
    }
    .padding()
    .background(Color.appBackground)
}
