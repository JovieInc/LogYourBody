//
// AppleSignInButton.swift
// LogYourBody
//
import SwiftUI
import AuthenticationServices

struct AppleSignInButton: UIViewRepresentable {
    @Environment(\.isEnabled)
    var isEnabled: Bool
    @Environment(\.colorScheme)
    var colorScheme
    @EnvironmentObject var authManager: AuthManager

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        // print("🍎 Making Apple Sign In button UI view")
        let button = ASAuthorizationAppleIDButton(
            authorizationButtonType: .signIn,
            authorizationButtonStyle: colorScheme == .dark ? .white : .black
        )
        button.cornerRadius = Constants.cornerRadius

        // Ensure the button is enabled and can receive touches
        button.isEnabled = true
        button.isUserInteractionEnabled = true

        // Add the target
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleAuthorizationAppleIDButtonPress),
            for: .touchUpInside
        )

        // Also add a tap gesture recognizer as a fallback
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTapGesture)
        )
        button.addGestureRecognizer(tapGesture)

        // print("🍎 Button created - isEnabled: \(button.isEnabled), isUserInteractionEnabled: \(button.isUserInteractionEnabled)")

        return button
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        // Re-add target in case it was lost
        uiView.removeTarget(nil, action: nil, for: .allEvents)
        uiView.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleAuthorizationAppleIDButtonPress),
            for: .touchUpInside
        )
    }

    func makeCoordinator() -> Coordinator {
        // print("🍎 Making coordinator for Apple Sign In button")
        return Coordinator(self)
    }

    class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let parent: AppleSignInButton

        init(_ parent: AppleSignInButton) {
            self.parent = parent
            // print("🍎 Coordinator initialized")
        }

        @objc


        func handleAuthorizationAppleIDButtonPress() {
            // print("🍎 Apple Sign In button pressed")
            performAppleSignIn()
        }

        @objc


        func handleTapGesture() {
            // print("🍎 Tap gesture recognized")
            performAppleSignIn()
        }

        private func performAppleSignIn() {
            #if targetEnvironment(simulator)
            // print("🍎 Running in simulator")
            #else
            // print("🍎 Running on device")
            #endif

            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self

            // print("🍎 About to perform requests...")
            authorizationController.performRequests()
            // print("🍎 Authorization controller perform requests called")
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            // print("🍎 Getting presentation anchor")
            // Get the key window
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                // print("🍎 Found key window")
                return window
            }

            // Fallback to any active window
            if let windowScene = UIApplication.shared.connectedScenes
                .filter({ $0.activationState == .foregroundActive })
                .first as? UIWindowScene,
               let window = windowScene.windows.first {
                // print("🍎 Found active window (fallback)")
                return window
            }

            // Last resort: create a new window for the first available scene
            // This prevents crashes but may not show UI properly
            // print("⚠️ No active window found for Apple Sign In - creating fallback window")
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                return UIWindow(windowScene: windowScene)
            }

            // Absolute fallback: return a basic window (sign in won't work but won't crash)
            // print("❌ Critical: No window scene available - Apple Sign In will likely fail")
            return UIWindow(frame: .zero)
        }

        func authorizationController(
            controller: ASAuthorizationController,
            didCompleteWithAuthorization authorization: ASAuthorization
        ) {
            // print("🍎 Authorization completed successfully")

            if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                // print("🍎 Got Apple ID credential")
                // print("🍎 User: \(appleIDCredential.user)")
                // print("🍎 Email: \(appleIDCredential.email ?? "no email")")
                // print("🍎 Name: \(appleIDCredential.fullName?.givenName ?? "") \(appleIDCredential.fullName?.familyName ?? "")")

                Task {
                    do {
                        try await parent.authManager.signInWithAppleCredentials(appleIDCredential)
                    } catch {
                        // print("🍎 Error in signInWithAppleCredentials: \(error)")
                    }
                }
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            // print("🍎 Authorization failed: \(error)")

            // Handle error
            if let error = error as? ASAuthorizationError {
                switch error.code {
                case .canceled:
                    // User canceled authorization
                    break
                case .failed:
                    // print("🍎 Authorization failed")
                    showErrorAlert("Apple Sign In failed. Please try again.")
                case .invalidResponse:
                    // print("🍎 Invalid response")
                    showErrorAlert("Invalid response from Apple Sign In.")
                case .notHandled:
                    // print("🍎 Authorization not handled")
                    showErrorAlert("Apple Sign In request was not handled.")
                case .notInteractive:
                    showErrorAlert("Apple Sign In is not available right now. Please try again or use another sign-in method.")
                case .unknown:
                    // print("🍎 Unknown error")
                    showErrorAlert("An unknown error occurred with Apple Sign In.")
                default:
                    // print("🍎 Unknown error case")
                    showErrorAlert("An error occurred with Apple Sign In.")
                }
            }
        }

        private func showErrorAlert(_ message: String) {
            DispatchQueue.main.async {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    let alert = UIAlertController(title: "Sign In Error", message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    rootViewController.present(alert, animated: true)
                }
            }
        }
    }
}

#Preview {
    AppleSignInButton()
        .environmentObject(AuthManager.shared)
        .frame(height: 48)
        .padding()
        .background(Color.black)
}
