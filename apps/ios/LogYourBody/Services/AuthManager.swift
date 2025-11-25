//
// AuthManager.swift
// LogYourBody
//
import Combine
import AuthenticationServices
import UIKit
import CryptoKit
import Clerk

#if !canImport(PostHog)
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

// MARK: - AsyncGate Helper

actor AsyncGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

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

    private var currentSignUp: SignUp?
    private var pendingSignUpCredentials: (email: String, password: String)?
    var pendingVerificationEmail: String? {
        pendingSignUpCredentials?.email
    }
    private let clerk = Clerk.shared
    private let supabase = SupabaseClient.shared  // Keep for data operations
    private let userDefaults = UserDefaults.standard
    private let userKey = Constants.currentUserKey
    private var cancellables = Set<AnyCancellable>()
    private var sessionObservationTask: Task<Void, Never>?
    private let legalConsentGate = AsyncGate()
    private var clerkInitializationTask: Task<Void, Never>?

    override init() {
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

    private func migrateLegacyAuthToken() {
        // Legacy auth token migration is no longer required.
    }

    private func showAuthError(_ message: String) {
        clerkInitError = message
    }

    func updateClerkUserName(_ name: String) async throws {
        // Store pending name locally; full Clerk profile sync is handled elsewhere.
        UserDefaults.standard.set(name, forKey: "pendingNameUpdate")
    }

    func handleSupabaseUnauthorized() async {
        await logout()
    }

    func initializeClerk() async {
        // print("🔧 Initializing Clerk SDK")

        let pubKey = Constants.clerkPublishableKey
        // print("🔧 Publishable Key Length: \(pubKey.count)")
        // print("🔧 Publishable Key: \(pubKey.isEmpty ? "EMPTY ❌" : String(pubKey.prefix(20)) + "...")")
        // print("🔧 Frontend API: \(Constants.clerkFrontendAPI)")
        // print("🔧 Is Configured: \(Constants.isClerkConfigured)")

        // Clear any previous error
        await MainActor.run {
            self.clerkInitError = nil
        }

        // Validate publishable key before attempting to configure
        guard !pubKey.isEmpty else {
            let error = "Clerk publishable key is empty. Check Config.xcconfig and Xcode project configuration."
            // print("❌ \(error)")
            await MainActor.run {
                self.isClerkLoaded = false
                self.clerkInitError = error
            }
            return
        }

        guard pubKey.hasPrefix("pk_") else {
            let error = "Invalid Clerk key format (should start with 'pk_'). Current: '\(String(pubKey.prefix(10)))...'"
            // print("❌ \(error)")
            await MainActor.run {
                self.isClerkLoaded = false
                self.clerkInitError = error
            }
            return
        }

        // Configure Clerk with publishable key
        // print("🔧 Configuring Clerk with valid publishable key...")
        clerk.configure(publishableKey: pubKey)

        // Load Clerk
        do {
            // print("🔧 Attempting to load Clerk...")
            let startTime = Date()
            try await clerk.load()
            let duration = Date().timeIntervalSince(startTime)
            // print("✅ Clerk SDK loaded successfully in \(String(format: "%.2f", duration))s")

            await MainActor.run {
                self.isClerkLoaded = true
                self.clerkInitError = nil
                self.observeSessionChanges()
            }
        } catch {
            let errorMessage = error.localizedDescription
            let context = ErrorContext(
                feature: "auth",
                operation: "initializeClerk",
                screen: nil,
                userId: nil
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
            // print("❌ Failed to load Clerk: \(error)")
            // print("❌ Error type: \(type(of: error))")
            // print("❌ Error details: \(String(describing: error))")
            // print("❌ Localized: \(errorMessage)")

            await MainActor.run {
                self.isClerkLoaded = false
                self.clerkInitError = "Failed to connect to authentication service: \(errorMessage)"
            }
        }
    }

    @discardableResult
    func ensureClerkInitializationTask(priority: TaskPriority = .userInitiated) -> Task<Void, Never> {
        if let existingTask = clerkInitializationTask, !existingTask.isCancelled {
            return existingTask
        }

        let task = Task(priority: priority) { [weak self] in
            guard let self else { return }
            await self.initializeClerk()
        }

        clerkInitializationTask = task
        return task
    }

    /// Retry Clerk initialization after a failure
    func retryClerkInitialization() async {
        // print("🔄 Retrying Clerk initialization...")
        clerkInitializationTask?.cancel()
        clerkInitializationTask = nil

        let task = ensureClerkInitializationTask()
        await task.value
    }

    private func observeSessionChanges() {
        // Cancel any existing observation
        sessionObservationTask?.cancel()

        // Clear any existing timer subscriptions before creating a new one
        cancellables.removeAll()

        // Observe Clerk instance for changes
        sessionObservationTask = Task { @MainActor in
            // Initial check
            self.updateSessionState()

            // Check for pending name updates when session is established
            if self.clerkSession != nil {
                Task {
                    await self.resolvePendingNameUpdates()
                }
            }

            // Periodically check for session changes (reduced frequency for performance)
            // Only check every 5 minutes to minimize background activity
            Timer.publish(every: 300.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    self?.updateSessionState()
                }
                .store(in: &cancellables)
        }
    }

    @MainActor
    private func updateSessionState() {
        _ = clerk.session != nil
        let previousSessionId = self.clerkSession?.id
        let currentSessionId = clerk.session?.id

        // Only update if session actually changed
        if previousSessionId != currentSessionId {
            // print("🔄 Session change detected: \(previousSessionId ?? "nil") -> \(currentSessionId ?? "nil")")

            self.clerkSession = clerk.session

            if let _ = clerk.session, let user = clerk.user {
                // Only authenticate if we have both a valid session AND user
                // print("🔄 Clerk session state: signed in with user \(user.id)")
                self.updateLocalUser(clerkUser: user)
                // isAuthenticated will be set by updateLocalUser if successful

                // Clear any remaining sign up state
                self.currentSignUp = nil
                self.pendingSignUpCredentials = nil
                self.needsEmailVerification = false

                // Notify RevenueCat of authenticated user for correct entitlement handling
                if let localUserId = self.currentUser?.id {
                    Task {
                        await RevenueCatManager.shared.identifyUser(userId: localUserId)
                    }
                }
            } else {
                // No valid session or user
                // print("🔄 Clerk session state: signed out")
                if previousSessionId != nil && currentSessionId == nil && lastExitReason == .none {
                    lastExitReason = .sessionExpired
                }
                self.isAuthenticated = false
                self.currentUser = nil
                userDefaults.removeObject(forKey: userKey)
                ErrorTrackingService.shared.updateUserId(nil)
                AnalyticsService.shared.reset()
            }
        }
    }

    // MARK: - Session Management

    func fetchActiveSessions() async throws -> [SessionInfo] {
        guard let session = clerk.session else {
            return []
        }

        let deviceName = UIDevice.current.name
        #if os(iOS)
        let deviceType = "iPhone"
        #else
        let deviceType = "Unknown"
        #endif

        let now = Date()

        let info = SessionInfo(
            id: session.id,
            deviceName: deviceName,
            deviceType: deviceType,
            location: "Unknown",
            ipAddress: "",
            lastActiveAt: now,
            createdAt: now,
            isCurrentSession: true
        )

        return [info]
    }

    func revokeSession(sessionId: String) async throws {
        do {
            try await clerk.signOut(sessionId: sessionId)
        } catch {
            throw error
        }

        if clerk.session == nil || clerk.session?.id == sessionId {
            isAuthenticated = false
            currentUser = nil
            userDefaults.removeObject(forKey: userKey)
        }
    }

    func updateLocalUser(clerkUser: Any) {
        // Use Mirror to access properties dynamically due to type naming conflict
        let mirror = Mirror(reflecting: clerkUser)

        // Extract properties using Mirror
        var userId = ""
        var emailAddresses: [Any] = []
        var firstName: String?
        var lastName: String?
        var username: String?
        var imageUrl: String?

        for child in mirror.children {
            switch child.label {
            case "id":
                userId = child.value as? String ?? ""
            case "emailAddresses":
                emailAddresses = child.value as? [Any] ?? []
            case "firstName":
                firstName = child.value as? String
            case "lastName":
                lastName = child.value as? String
            case "username":
                username = child.value as? String
            case "imageUrl":
                imageUrl = child.value as? String
            default:
                break
            }
        }

        // Extract email from first email address
        var email = ""
        if let firstEmailAddress = emailAddresses.first {
            let emailMirror = Mirror(reflecting: firstEmailAddress)
            for child in emailMirror.children {
                if child.label == "emailAddress" {
                    email = child.value as? String ?? ""
                    break
                }
            }
        }

        // Use single source of truth for display name
        let displayName = getUserDisplayName()

        // Don't proceed if we don't have a valid email
        guard !email.isEmpty else {
            self.currentUser = nil
            self.isAuthenticated = false
            return
        }

        // Create user object with Clerk data
        let localUser = LocalUser(
            id: userId,
            email: email,
            name: displayName.isEmpty ? email.components(separatedBy: "@").first ?? "User" : displayName,
            avatarUrl: imageUrl,
            profile: UserProfile(
                id: userId,
                email: email,
                username: username,
                fullName: displayName.isEmpty ? email.components(separatedBy: "@").first ?? "User" : displayName,
                dateOfBirth: nil,
                height: nil,
                heightUnit: "cm",
                gender: nil,
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: "kg",
                onboardingCompleted: nil
            )
        )

        self.currentUser = localUser
        self.isAuthenticated = true  // Set authenticated only after successful user creation
        self.lastExitReason = .none

        ErrorTrackingService.shared.updateUserId(localUser.id)

        var traits: [String: String] = [
            "email": email,
            "name": localUser.displayName,
            "platform": "ios",
            "app_version": AppVersion.current,
            "build_number": AppVersion.build,
            "environment": Configuration.sentryEnvironment
        ]

        if let username, !username.isEmpty {
            traits["username"] = username
        }

        if let imageUrl, !imageUrl.isEmpty {
            traits["has_avatar"] = "true"
        }

        if let profile = localUser.profile,
           let fullName = profile.fullName,
           !fullName.isEmpty {
            traits["full_name"] = fullName
        }

        AnalyticsService.shared.identify(
            userId: localUser.id,
            properties: traits
        )
    }

    func login(email: String, password: String) async throws {
        // Mock authentication for development
        if Constants.useMockAuth {
            // print("🧪 Using mock authentication for development")

            // Create mock user
            let mockUser = LocalUser(
                id: "mock_user_123",
                email: email,
                name: "Test User",
                avatarUrl: nil,
                profile: UserProfile(
                    id: "mock_user_123",
                    email: email,
                    username: nil,
                    fullName: "Test User",
                    dateOfBirth: nil,
                    height: nil,
                    heightUnit: "cm",
                    gender: nil,
                    activityLevel: nil,
                    goalWeight: nil,
                    goalWeightUnit: "kg",
                    onboardingCompleted: nil
                )
            )

            await MainActor.run {
                self.currentUser = mockUser
                self.isAuthenticated = true
                // print("✅ Mock authentication successful")
            }
            return
        }

        // Real authentication using Clerk SDK is not yet implemented for email/password.
        // For now, treat any non-mock login as invalid credentials.
        throw AuthError.invalidCredentials
    }

    // MARK: - Apple Sign In with OAuth
    @MainActor
    func signInWithAppleOAuth() async {
        guard isClerkLoaded else {
            showAuthError("Please wait for app to initialize and try again")
            return
        }

        do {
            // Create OAuth sign in
            let signIn = try await SignIn.create(strategy: .oauth(provider: .apple))

            // Open Safari for authentication
            try await signIn.authenticateWithRedirect()
        } catch {
            // Handle specific error cases
            let errorString = String(describing: error)

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
        // For now, reuse the OAuth-based Apple sign-in flow.
        await signInWithAppleOAuth()
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

        // Fall back to email prefix (but not for private relay emails)
        if let email = currentUser?.email ?? clerk.user?.emailAddresses.first?.emailAddress {
            // Don't use email prefix for Apple private relay or other privacy-focused emails
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
        do {
            try await clerk.signOut()
        } catch {
            // Ignore sign-out failures; we'll still clear local state
        }

        AnalyticsService.shared.track(event: "logout")

        await MainActor.run {
            self.lastExitReason = .userInitiated
            self.clerkSession = nil
            self.currentUser = nil
            self.isAuthenticated = false
            self.currentSignUp = nil
            self.pendingSignUpCredentials = nil
            self.needsEmailVerification = false
        }

        await RevenueCatManager.shared.logoutUser()

        userDefaults.removeObject(forKey: userKey)
        userDefaults.removeObject(forKey: Constants.currentUserKey)
        userDefaults.removeObject(forKey: Constants.authTokenKey)
        try? KeychainManager.shared.clearAll()

        UserDefaults.standard.removeObject(forKey: "HasSyncedHistoricalSteps")
        UserDefaults.standard.removeObject(forKey: "lastSupabaseSyncDate")
        UserDefaults.standard.removeObject(forKey: "lastHealthKitWeightSyncDate")
    }

    func loginErrorMessage(for error: Error) -> String {
        if let authError = error as? AuthError {
            switch authError {
            case .invalidCredentials:
                return "Invalid email or password. Please try again."
            case .clerkNotInitialized:
                return authServiceNotReadyMessage
            default:
                return authError.errorDescription ?? "An unknown error occurred. Please try again."
            }
        }

        return "Invalid email or password. Please try again."
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

// MARK: - Sign Up & Profile Management

extension AuthManager {
    private func getSupabaseToken() async -> String? {
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

    func signUp(email: String, password: String, name: String) async throws {
        guard isClerkLoaded else {
            throw AuthError.clerkNotInitialized
        }

        let strategy = SignUp.CreateStrategy.standard(
            emailAddress: email,
            password: password,
            firstName: name.isEmpty ? nil : name,
            lastName: nil,
            username: nil,
            phoneNumber: nil
        )

        let signUp = try await SignUp.create(strategy: strategy)
        currentSignUp = signUp
        pendingSignUpCredentials = (email: email, password: password)

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
            needsEmailVerification = false
            currentSignUp = nil
            pendingSignUpCredentials = nil
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

    func updateProfile(_ updates: [String: Any]) async {
        guard let userId = currentUser?.id else { return }

        var payload = updates
        payload["id"] = userId

        guard let token = await getSupabaseToken() else { return }

        do {
            try await SupabaseManager.shared.updateProfile(payload, token: token)
        } catch {
            let context = ErrorContext(
                feature: "profile",
                operation: "updateProfile",
                screen: nil,
                userId: userId
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
        }
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

// MARK: - Apple Sign In Delegate
private class AppleSignInDelegate: NSObject,
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
        return UIWindow(frame: UIScreen.main.bounds)
    }
}
