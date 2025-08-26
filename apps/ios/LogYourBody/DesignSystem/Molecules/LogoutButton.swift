//
// LogoutButton.swift
// LogYourBody
//
import SwiftUI

// MARK: - Logout Button Molecule

struct LogoutButton: View {
    let action: () -> Void
    
    var body: some View {
        BaseButton(configuration: ButtonConfiguration(
            style: .custom(background: Color(.systemBackground), foreground: .red),
            size: .medium,
            fullWidth: true,
            icon: "rectangle.portrait.and.arrow.right"
        ), action: action) {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 16))
                Text("Log Out")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            .foregroundColor(.red)
        }
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
