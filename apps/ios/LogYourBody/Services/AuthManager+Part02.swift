import Combine
import AuthenticationServices
import UIKit
import CryptoKit
import Clerk

extension AuthManager {
func verifySignInEmail(code: String) async throws {
        guard let signIn = currentSignIn else {
            throw AuthError.invalidCredentials
        }

        let updated = try await signIn.attemptFirstFactor(
            strategy: .emailCode(code: code)
        )

        if updated.status == .complete {
            if let sessionId = updated.createdSessionId {
                try await clerk.setActive(sessionId: sessionId)
            }

            updateSessionState()

            needsEmailVerification = false
            currentSignIn = nil
            pendingSignInEmail = nil
            emailVerificationFlow = nil
        } else {
            throw AuthError.invalidCredentials
        }
    }

func resendSignInEmailCode() async throws {
        guard let signIn = currentSignIn else {
            throw AuthError.invalidCredentials
        }

        _ = try await signIn.prepareFirstFactor(strategy: .emailCode())
    }

// MARK: - Apple Sign In
    @MainActor
    func signInWithAppleOAuth() async {
        logAuthDiagnostic("apple_start", details: ["clerkLoaded": boolString(isClerkLoaded)])
        clerkInitError = nil

        guard isClerkLoaded else {
            showAuthError("Please wait for app to initialize and try again")
            return
        }

        do {
            let credential = try await SignInWithAppleHelper.getAppleIdCredential(
                requestedScopes: [.email, .fullName]
            )
            logAuthDiagnostic(
                "apple_credential",
                details: [
                    "emailPresent": boolString(credential.email != nil),
                    "fullNamePresent": boolString(credential.fullName != nil),
                    "identityTokenPresent": boolString(credential.identityToken != nil)
                ]
            )
            try await authenticateWithAppleCredential(credential)
        } catch {
            let errorString = String(describing: error)
            logAuthDiagnostic(
                "apple_error",
                details: [
                    "type": String(describing: type(of: error))
                ]
            )

            if errorString.contains("oauth_provider_not_enabled") {
                showAuthError("Apple Sign In is not configured. Please contact support.")
            } else if errorString.contains("network") || errorString.contains("connection") {
                showAuthError("Network error. Please check your connection and try again.")
            } else {
                showAuthError("Apple Sign In failed. Please try email sign in instead.")
            }

            AnalyticsService.shared.track(
                event: "login_failed",
                properties: [
                    "method": "apple"
                ]
            )
        }
    }

@MainActor
    func signInWithAppleCredentials(_ credential: ASAuthorizationAppleIDCredential) async throws {
        try await authenticateWithAppleCredential(credential)
    }

@MainActor
    func authenticateWithAppleCredential(_ credential: ASAuthorizationAppleIDCredential) async throws {
        cacheAppleDisplayName(from: credential)

        guard let idToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw AuthError.invalidCredentials
        }

        logAuthDiagnostic("clerk_id_token_start")
        let result = try await SignIn.authenticateWithIdToken(provider: .apple, idToken: idToken)
        try await activateCompletedTransfer(result)
    }

@MainActor
    func activateCompletedTransfer(_ result: TransferFlowResult) async throws {
        let sessionId: String?

        switch result {
        case .signIn(let signIn):
            guard signIn.status == .complete else {
                logAuthDiagnostic(
                    "clerk_transfer_incomplete",
                    details: [
                        "flow": "sign_in",
                        "status": String(describing: signIn.status)
                    ]
                )
                throw AuthError.invalidCredentials
            }
            sessionId = signIn.createdSessionId
            logAuthDiagnostic(
                "clerk_transfer_complete",
                details: [
                    "flow": "sign_in",
                    "hasSessionId": boolString(sessionId != nil),
                    "status": String(describing: signIn.status)
                ]
            )

        case .signUp(let signUp):
            guard signUp.status == .complete else {
                logAuthDiagnostic(
                    "clerk_transfer_incomplete",
                    details: [
                        "flow": "sign_up",
                        "status": String(describing: signUp.status)
                    ]
                )
                throw AuthError.invalidCredentials
            }
            sessionId = signUp.createdSessionId
            logAuthDiagnostic(
                "clerk_transfer_complete",
                details: [
                    "flow": "sign_up",
                    "hasSessionId": boolString(sessionId != nil),
                    "status": String(describing: signUp.status)
                ]
            )
        }

        guard let sessionId else {
            throw AuthError.invalidCredentials
        }

        logAuthDiagnostic("clerk_set_active_start")
        try await clerk.setActive(sessionId: sessionId)
        logSessionDiagnostic("clerk_set_active_done", expectedSessionId: sessionId)
        await reconcileActiveSession(sessionId: sessionId)
        logSessionDiagnostic("clerk_reconcile_done", expectedSessionId: sessionId)
        updateSessionState(force: true)
        logSessionDiagnostic("local_auth_state_updated", expectedSessionId: sessionId)

        guard isAuthenticated else {
            throw AuthError.syncError(
                "Authentication session was created, but the app could not load the user profile."
            )
        }

        clerkInitError = nil
        await bootstrapAuthenticatedProfileIfNeeded(sessionId: clerk.session?.id)
    }

@MainActor
    func reconcileActiveSession(sessionId: String) async {
        for attempt in 0..<20 {
            if clerk.session?.id == sessionId,
               clerk.user != nil || clerk.session?.publicUserData != nil {
                return
            }

            if attempt % 4 == 3 {
                do {
                    _ = try await Client.get()
                } catch {
                    ErrorReporter.shared.captureNonFatal(
                        error,
                        context: ErrorContext(
                            feature: "auth",
                            operation: "refreshActiveClient",
                            screen: nil,
                            userId: nil
                        )
                    )
                }
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        do {
            _ = try await Client.get()
            try? await Task.sleep(nanoseconds: 250_000_000)

            if clerk.session?.id == sessionId,
               clerk.user != nil || clerk.session?.publicUserData != nil {
                return
            }

            try await clerk.load()
            try? await Task.sleep(nanoseconds: 250_000_000)
        } catch {
            ErrorReporter.shared.captureNonFatal(
                error,
                context: ErrorContext(
                    feature: "auth",
                    operation: "reconcileActiveSession",
                    screen: nil,
                    userId: nil
                )
            )
        }
    }

func cacheAppleDisplayName(from credential: ASAuthorizationAppleIDCredential) {
        guard let fullName = credential.fullName else { return }

        let formatter = PersonNameComponentsFormatter()
        let name = formatter
            .string(from: fullName)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if !name.isEmpty {
            UserDefaults.standard.set(name, forKey: "appleSignInName")
        }
    }

// MARK: - Unified Apple Sign In Handler
    @MainActor
    func handleAppleSignIn() async {
        AnalyticsService.shared.track(
            event: "login_attempt",
            properties: [
                "method": "apple"
            ]
        )

        await signInWithAppleOAuth()
    }

// MARK: - Name Management (Single Source of Truth)

    /// Single source of truth for getting the user's display name
    /// Priority: 1. Clerk user name, 2. Pending update, 3. Apple Sign In name, 4. Email prefix
    func getUserDisplayName() -> String {
        // First check if we have a Clerk user with a name
        if let clerkUser = clerk.user {
            let firstName = clerkUser.firstName ?? ""
            let lastName = clerkUser.lastName ?? ""
            let clerkName = [firstName, lastName]
                .compactMap { $0 }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)

            if !clerkName.isEmpty {
                return clerkName
            }
        }

        // Check for pending name update (in case Clerk update failed)
        if let pendingName = UserDefaults.standard.string(forKey: "pendingNameUpdate"),
           !pendingName.isEmpty {
            return pendingName
        }

        // Check for Apple Sign In name (temporary storage during onboarding)
        if let appleSignInName = UserDefaults.standard.string(forKey: "appleSignInName"),
           !appleSignInName.isEmpty {
            return appleSignInName
        }

        // Fall back to email prefix (but not for relay emails)
        if let email = currentUser?.email ?? clerk.user?.emailAddresses.first?.emailAddress {
            // Don't use email prefix for Apple relay or other privacy-focused emails
            if email.contains("@privaterelay.appleid.com") ||
                email.contains("@icloud.com") ||
                email.hasPrefix("no-reply") {
                return "User"
            }
            return email.components(separatedBy: "@").first ?? "User"
        }

        return "User"
    }

/// Consolidates name updates across all systems
    func consolidateNameUpdate(_ fullName: String) async throws {
        let trimmedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw AuthError.nameUpdateFailed("Name cannot be empty")
        }

        // Update using our method (which handles local, Supabase, and Core Data)
        try await updateClerkUserName(trimmedName)

        // Clean up temporary storage after successful update
        UserDefaults.standard.removeObject(forKey: "appleSignInName")

        // Sync to Core Data (if not already done in updateClerkUserName)
        if let userId = currentUser?.id,
           let email = currentUser?.email,
           let profile = currentUser?.profile {
            CoreDataManager.shared.saveProfile(profile, userId: userId, email: email)
        }

        // Post notification for UI updates
        NotificationCenter.default.post(name: .profileUpdated, object: nil)
    }

/// Check and resolve any pending name updates on app launch
    func resolvePendingNameUpdates() async {
        guard let pendingName = UserDefaults.standard.string(forKey: "pendingNameUpdate"),
              !pendingName.isEmpty else {
            return
        }

        do {
            // print("📝 Resolving pending name update: \(pendingName)")
            try await consolidateNameUpdate(pendingName)
            // print("✅ Pending name update resolved")
        } catch {
            // print("❌ Failed to resolve pending name update: \(error)")
            // Keep the pending update for next attempt
        }
    }

@MainActor
    func uploadProfilePicture(_ image: UIImage) async throws -> String? {
        // Profile picture upload is not implemented for this build.
        return nil
    }

// MARK: - Session Termination

    func logout() async {
        await performLogout(exitReason: .userInitiated)
    }

func performLogout(exitReason: AuthExitReason) async {
        do {
            try await clerk.signOut()
        } catch {
            // Ignore sign-out failures; we'll still clear local state
        }

        if exitReason == .userInitiated {
            AnalyticsService.shared.track(event: "logout")
        }

        await MainActor.run {
            self.lastExitReason = exitReason
            self.clerkSession = nil
            self.currentUser = nil
            self.isAuthenticated = false
            self.currentSignUp = nil
            self.pendingSignUpEmail = nil
            self.needsEmailVerification = false
            self.currentSignIn = nil
            self.pendingSignInEmail = nil
            self.emailVerificationFlow = nil
            self.bootstrappedProfileSessionIds.removeAll()
        }

        await RevenueCatManager.shared.logoutUser()

        Self.migrateLegacyAuthStorage(in: userDefaults)
        try? KeychainManager.shared.clearAll()
        BodyMetricSpotlightIndexer.deleteAllIndexedMetrics()
        ErrorTrackingService.shared.updateUserId(nil)
        AnalyticsService.shared.reset()

        UserDefaults.standard.removeObject(forKey: "HasSyncedHistoricalSteps")
        UserDefaults.standard.removeObject(forKey: "lastSupabaseSyncDate")
        UserDefaults.standard.removeObject(forKey: "lastHealthKitWeightSyncDate")
    }

func loginErrorMessage(for error: Error) -> String {
        if let authError = error as? AuthError {
            switch authError {
            case .invalidCredentials:
                return "Invalid email or code. Please try again."
            case .clerkNotInitialized:
                return authServiceNotReadyMessage
            default:
                return authError.errorDescription ?? "An unknown error occurred. Please try again."
            }
        }

        return "Invalid email or code. Please try again."
    }

func signUpErrorMessage(for error: Error) -> String {
        let description = error.localizedDescription

        if description.contains("not strong enough") {
            return (
                "Please choose a stronger password. Use at least 8 characters " +
                    "with a mix of uppercase, lowercase, and numbers or symbols."
            )
        }

        if let authError = error as? AuthError {
            switch authError {
            case .clerkNotInitialized:
                return authServiceNotReadyMessage
            default:
                return authError.errorDescription ?? description
            }
        }

        return description
    }

var authServiceNotReadyMessage: String {
        "Authentication service is not ready. Please wait or tap retry."
    }
}
