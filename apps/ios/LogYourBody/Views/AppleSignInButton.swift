//
// AppleSignInButton.swift
// LogYourBody
//
import SwiftUI

struct AppleSignInButton: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        PlatformAppleSignInButton(authManager: authManager)
            .accessibilityIdentifier("apple_sign_in_button")
    }
}

#Preview {
    AppleSignInButton()
        .environmentObject(AuthManager.shared)
        .frame(height: 48)
        .padding()
        .background(Color.black)
}
