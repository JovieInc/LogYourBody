//
// AuthManager.swift
// LogYourBody
//
import Combine
import AuthenticationServices
import UIKit
import CryptoKit
import Clerk

#if !canImport(Statsig)
final class AnalyticsService {
    static let shared = AnalyticsService()

    func start() {}

    func identify(userId: String?, properties: [String: String]? = nil) {}

    func track(event: String, properties: [String: String]? = nil) {}

    func isFeatureEnabled(flagKey: String) -> Bool { false }

    func reset() {}
}
#endif

typealias LocalUser = LogYourBody.User  // Disambiguate between Clerk SDK User and our User model

typealias ASPresentationAnchor = UIWindow

typealias AppleCredentialContinuation = CheckedContinuation<ASAuthorizationAppleIDCredential, Error>

enum AuthError: LocalizedError {
    case clerkNotInitialized
    case invalidCredentials
    case nameUpdateFailed(String)
    case networkError
    case syncError(String)

    var errorDescription: String? {
        switch self {
        case .clerkNotInitialized:
            return "Authentication service is not ready. Please try again."
        case .invalidCredentials:
            return "Invalid authentication credentials"
        case .nameUpdateFailed(let reason):
            return "Failed to update name: \(reason)"
        case .networkError:
            return "Network connection error. Please check your connection."
        case .syncError(let reason):
            return "Failed to sync data: \(reason)"
        }
    }
}

enum AuthExitReason {
    case none
    case userInitiated
    case sessionExpired
}

enum EmailRegistrationStatus {
    case available
    case registered
}

enum EmailVerificationFlow: Equatable {
    case signUp
    case signIn
}

enum AuthProfileBootstrapPolicy {
    static func shouldPersistProjectedProfile(_ profile: UserProfile) -> Bool {
        profile.hasAppOwnedProfileData
    }
}

enum PasswordUpdateError: LocalizedError {
    case notAuthenticated
    case incorrectCurrentPassword
    case notStrongEnough
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to change your password"
        case .incorrectCurrentPassword:
            return "Current password is incorrect"
        case .notStrongEnough:
            return "Please choose a stronger password"
        case .failed(let message):
            return message
        }
    }
}

protocol AuthAccountManaging {
    func updatePassword(currentPassword: String, newPassword: String) async throws
    func deleteCurrentAccount() async throws
}

struct ClerkAuthAccountAdapter: AuthAccountManaging {
    func updatePassword(currentPassword: String, newPassword: String) async throws {
        guard let user = await Clerk.shared.user else {
            throw PasswordUpdateError.notAuthenticated
        }

        try await user.updatePassword(.init(
            newPassword: newPassword,
            currentPassword: currentPassword,
            signOutOfOtherSessions: true
        ))
    }

    func deleteCurrentAccount() async throws {
        guard let user = await Clerk.shared.user else {
            throw NSError(
                domain: "DeleteAccount",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No user found"]
            )
        }

        try await user.delete()
    }
}

// MARK: - AsyncGate Helper

actor AsyncGate {
    var isLocked = false
    var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            isLocked = false
        }
    }
}

// MARK: - Session Information

// Session information for active sessions management
struct SessionInfo: Identifiable {
    let id: String
    let deviceName: String
    let deviceType: String
    let location: String
    let ipAddress: String
    let lastActiveAt: Date
    let createdAt: Date
    let isCurrentSession: Bool
}

@MainActor
class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var currentUser: LocalUser?
    @Published var clerkSession: Session?
    @Published var needsEmailVerification = false
    @Published var isClerkLoaded = false
    @Published var clerkInitError: String?
    @Published var needsLegalConsent = false
    @Published var pendingAppleUserId: String?
    @Published var lastExitReason: AuthExitReason = .none
    @Published var memberSinceDate: Date?

    var currentSignUp: SignUp?
    var pendingSignUpEmail: String?
    var currentSignIn: SignIn?
    var pendingSignInEmail: String?
    @Published var emailVerificationFlow: EmailVerificationFlow?
    let clerk = Clerk.shared
    let supabase = SupabaseClient.shared  // Keep for data operations
    let accountAdapter: AuthAccountManaging
    let userDefaults = UserDefaults.standard
    let userKey = Constants.currentUserKey
    var cancellables = Set<AnyCancellable>()
    var sessionObservationTask: Task<Void, Never>?
    let legalConsentGate = AsyncGate()
    var clerkInitializationTask: Task<Void, Never>?
    var bootstrappedProfileSessionIds = Set<String>()

    init(accountAdapter: AuthAccountManaging = ClerkAuthAccountAdapter()) {
        self.accountAdapter = accountAdapter
        super.init()
        // print("🔐 AuthManager initialized")

        // Always start with no authentication until Clerk confirms session
        self.isAuthenticated = false
        self.currentUser = nil
        self.clerkSession = nil

        // Clear any stale user data
        userDefaults.removeObject(forKey: userKey)

        migrateLegacyAuthToken()
    }

    nonisolated static let legacySensitiveUserDefaultsKeys: [String] = [
        Constants.authTokenKey,
        Constants.currentUserKey,
        "accessToken",
        "authSession",
        "clerkJWT",
        "clerkSession",
        "clerkToken",
        "jwt",
        "refreshToken",
        "session",
        "supabaseAccessToken",
        "supabaseRefreshToken",
        "userSession"
    ]


    #if DEBUG

    #endif
}

// MARK: - Sign Up & Profile Management

extension AuthManager {
    func getSupabaseToken() async -> String? {
        do {
            guard let session = clerk.session else {
                return nil
            }

            let tokenResource = try await session.getToken()
            return tokenResource?.jwt
        } catch {
            return nil
        }
    }

    func getAccessToken() async -> String? {
        await getSupabaseToken()
    }

    func signUp(email: String, password _: String, name: String) async throws {
        guard isClerkLoaded else {
            throw AuthError.clerkNotInitialized
        }

        let strategy = SignUp.CreateStrategy.standard(
            emailAddress: email,
            password: nil,
            firstName: name.isEmpty ? nil : name,
            lastName: nil,
            username: nil,
            phoneNumber: nil
        )

        let signUp = try await SignUp.create(strategy: strategy)
        currentSignUp = signUp
        pendingSignUpEmail = email
        emailVerificationFlow = .signUp

        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            UserDefaults.standard.set(name, forKey: "appleSignInName")
        }

        _ = try await signUp.prepareVerification(strategy: .emailCode)
        needsEmailVerification = true
    }

    func verifyEmail(code: String) async throws {
        guard let signUp = currentSignUp else {
            throw AuthError.invalidCredentials
        }

        let updated = try await signUp.attemptVerification(strategy: .emailCode(code: code))
        currentSignUp = updated

        if updated.status == .complete {
            if let sessionId = updated.createdSessionId {
                try await clerk.setActive(sessionId: sessionId)
            }

            updateSessionState()
            await bootstrapAuthenticatedProfileIfNeeded(sessionId: clerk.session?.id)

            needsEmailVerification = false
            currentSignUp = nil
            pendingSignUpEmail = nil
            emailVerificationFlow = nil
        } else {
            throw AuthError.invalidCredentials
        }
    }

    func resendVerificationEmail() async throws {
        guard let signUp = currentSignUp else {
            throw AuthError.invalidCredentials
        }

        _ = try await signUp.prepareVerification(strategy: .emailCode)
    }

    func updateProfileDurably(_ updates: [String: Any]) async throws {
        guard let currentUser else { throw SupabaseError.notAuthenticated }

        var payload = updates
        payload["id"] = currentUser.id
        if payload["email"] == nil {
            payload["email"] = currentUser.email
        }

        guard let token = await getSupabaseToken() else {
            throw SupabaseError.tokenGenerationFailed
        }

        try await SupabaseManager.shared.updateProfile(payload, token: token)
    }

    func updateProfile(_ updates: [String: Any]) async {
        do {
            try await updateProfileDurably(updates)
        } catch {
            let context = ErrorContext(
                feature: "profile",
                operation: "updateProfile",
                screen: nil,
                userId: currentUser?.id
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
        }
    }

    func bootstrapAuthenticatedProfileIfNeeded(sessionId: String?) async {
        guard let sessionId,
              !bootstrappedProfileSessionIds.contains(sessionId),
              let user = currentUser,
              let profile = user.profile else {
            return
        }

        bootstrappedProfileSessionIds.insert(sessionId)

        if let cachedProfile = await CoreDataManager.shared.fetchUserProfileSnapshot(for: user.id),
           cachedProfile.hasPendingLocalChanges {
            applyAuthenticatedProfile(cachedProfile.profile, fallbackEmail: user.email)
            return
        }

        do {
            if let remoteProfile = try await SupabaseManager.shared.fetchProfile(userId: user.id) {
                applyAuthenticatedProfile(remoteProfile, fallbackEmail: user.email)
                CoreDataManager.shared.saveProfile(
                    remoteProfile,
                    userId: user.id,
                    email: remoteProfile.email ?? user.email,
                    markSynced: true
                )
                return
            }

            guard AuthProfileBootstrapPolicy.shouldPersistProjectedProfile(profile) else {
                bootstrappedProfileSessionIds.remove(sessionId)
                return
            }

            try await SupabaseManager.shared.upsertProfile(profile)
            CoreDataManager.shared.saveProfile(profile, userId: user.id, email: user.email, markSynced: true)
        } catch {
            if let cachedProfile = await CoreDataManager.shared.fetchUserProfile(for: user.id) {
                applyAuthenticatedProfile(cachedProfile, fallbackEmail: user.email)
                return
            }

            bootstrappedProfileSessionIds.remove(sessionId)
            let context = ErrorContext(
                feature: "auth",
                operation: "bootstrapAuthenticatedProfile",
                screen: nil,
                userId: user.id
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
        }
    }

    func applyAuthenticatedProfile(_ profile: UserProfile, fallbackEmail: String) {
        guard var user = currentUser else { return }

        user.profile = profile

        if let fullName = profile.fullName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fullName.isEmpty {
            user.name = fullName
        } else if user.name == nil {
            user.name = fallbackEmail.components(separatedBy: "@").first ?? "User"
        }

        if let onboardingCompleted = profile.onboardingCompleted {
            user.onboardingCompleted = onboardingCompleted
            OnboardingStateManager.shared.syncCompletionFlagFromProfile(onboardingCompleted, userId: user.id)
        }

        currentUser = user
    }

    @discardableResult
    func applySavedProfileToCurrentUser(_ profile: UserProfile) -> Bool {
        guard currentUser?.id == profile.id else { return false }

        applyAuthenticatedProfile(
            profile,
            fallbackEmail: profile.email ?? currentUser?.email ?? ""
        )
        NotificationCenter.default.post(name: .profileUpdated, object: nil)
        return true
    }

    // MARK: - Account Deletion Helpers

    /// Best-effort call to backend delete-account pipeline.
    /// This mirrors the web app's behavior of cleaning up Supabase data and assets.
    func notifyBackendOfAccountDeletion() async {
        guard let token = await getSupabaseToken(),
              !token.isEmpty else {
            return
        }

        guard let url = URL(string: "\(Constants.supabaseURL)/functions/v1/delete-user-assets") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            let context = ErrorContext(
                feature: "auth",
                operation: "notifyBackendOfAccountDeletion",
                screen: nil,
                userId: currentUser?.id
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
        }
    }

    // MARK: - Legal Consent Management

    func checkLegalConsent(userId: String) async -> Bool {
        await legalConsentGate.wait()
        defer { Task { await legalConsentGate.signal() } }

        // ...
        // Check if user has accepted legal terms in backend
        guard let token = await getSupabaseToken() else {
            return false
        }

        do {
            // Query the profiles table for legal consent status
            let url = URL(string: "\(Constants.supabaseURL)/rest/v1/profiles?id=eq.\(userId)&select=legal_accepted_at")!
            var request = URLRequest(url: url)
            request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, _) = try await URLSession.shared.data(for: request)

            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let profile = json.first,
               let _ = profile["legal_accepted_at"] as? String {
                return true // User has accepted legal terms
            }
        } catch {
            // print("❌ Failed to check legal consent: \(error)")
        }

        return false
    }

    func acceptLegalConsent(userId: String) async {
        await legalConsentGate.wait()
        defer { Task { await legalConsentGate.signal() } }

        // Save legal consent to backend
        guard let token = await getSupabaseToken() else {
            return
        }

        do {
            let consentData: [String: Any] = [
                "id": userId,
                "legal_accepted_at": ISO8601DateFormatter().string(from: Date()),
                "terms_accepted": true,
                "privacy_accepted": true
            ]

            let url = URL(string: "\(Constants.supabaseURL)/rest/v1/profiles")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

            let jsonData = try JSONSerialization.data(withJSONObject: [consentData])
            request.httpBody = jsonData

            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    // print("✅ Legal consent saved")

                    // Now complete the sign in process
                    self.needsLegalConsent = false
                    self.pendingAppleUserId = nil

                    // Force session update to complete authentication
                    self.updateSessionState()
                } else {
                    // print("❌ Failed to save consent: Status \(httpResponse.statusCode)")
                }
            }
        } catch {
            // print("❌ Failed to save legal consent: \(error)")
        }
    }
}

extension AuthManager {
    var isAuthProviderReady: Bool {
        isClerkLoaded
    }

    var authProviderInitError: String? {
        clerkInitError
    }

    func retryAuthProviderInitialization() async {
        await retryClerkInitialization()
    }
}

// MARK: - Apple Sign In Delegate
class AppleSignInDelegate: NSObject,
                                   ASAuthorizationControllerDelegate,
                                   ASAuthorizationControllerPresentationContextProviding {
    let continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>

    init(continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>) {
        self.continuation = continuation
        super.init()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation.resume(returning: appleIDCredential)
        } else {
            continuation.resume(throwing: ASAuthorizationError(.invalidResponse))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the key window
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }

        // Fallback to any active window
        if let windowScene = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .first as? UIWindowScene,
           let window = windowScene.windows.first {
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
}
