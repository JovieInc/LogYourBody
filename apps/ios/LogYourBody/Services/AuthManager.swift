//
// AuthManager.swift
// LogYourBody
//
// First-party authentication through Jovie's Better Auth issuer.
//

import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

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

typealias LocalUser = LogYourBody.User
typealias ASPresentationAnchor = UIWindow

enum AuthError: LocalizedError {
    case providerNotReady
    case cancelled
    case invalidCallback
    case invalidToken
    case networkError
    case server(String)
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .providerNotReady:
            return "Authentication is not ready. Please try again."
        case .cancelled:
            return "Sign in was cancelled."
        case .invalidCallback:
            return "The sign-in response was invalid. Please try again."
        case .invalidToken:
            return "Your sign-in session could not be verified. Please try again."
        case .networkError:
            return "Check your connection and try again."
        case .server(let message), .unsupported(let message):
            return message
        }
    }
}

enum AuthExitReason: Equatable {
    case none
    case userInitiated
    case sessionExpired
}

enum AuthProfileBootstrapPolicy {
    static func shouldPersistProjectedProfile(_ profile: UserProfile) -> Bool {
        profile.hasAppOwnedProfileData
    }
}

enum PasswordUpdateError: LocalizedError {
    case notSupported

    var errorDescription: String? {
        "LogYourBody uses phone verification codes instead of passwords."
    }
}

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

struct ProductAuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let subject: String
    let email: String
    let name: String?
    let issuedAt: Date

    var id: String { subject }
}

struct SupabaseAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let expiresAt: TimeInterval?
    let user: SupabaseAuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

struct SupabaseAuthUser: Decodable {
    struct Metadata: Decodable {
        let fullName: String?
        let name: String?

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case name
        }
    }

    let id: String
    let email: String?
    let createdAt: Date?
    let userMetadata: Metadata?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case createdAt = "created_at"
        case userMetadata = "user_metadata"
    }

    var name: String? {
        userMetadata?.fullName ?? userMetadata?.name
    }
}

actor AsyncGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
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

@MainActor
final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var currentUser: LocalUser?
    @Published var authSession: ProductAuthSession?
    @Published var isAuthProviderLoaded = false
    @Published var authProviderInitError: String?
    @Published var needsLegalConsent = false
    @Published var lastExitReason: AuthExitReason = .none
    @Published var memberSinceDate: Date?

    let supabase = SupabaseClient.shared
    let userDefaults: UserDefaults
    let keychain: KeychainManager
    let urlSession: URLSession
    let legalConsentGate = AsyncGate()

    private let storedSessionKey = "productAuth.supabaseSession"
    private var initializationTask: Task<Void, Never>?
    private var refreshTask: Task<String?, Never>?
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private var bootstrappedProfileSessionIds = Set<String>()

    init(
        userDefaults: UserDefaults = .standard,
        keychain: KeychainManager = .shared,
        urlSession: URLSession = .shared
    ) {
        self.userDefaults = userDefaults
        self.keychain = keychain
        self.urlSession = urlSession
        super.init()
        Self.migrateLegacyAuthStorage(in: userDefaults)
    }

    var isAuthProviderReady: Bool {
        isAuthProviderLoaded && authProviderInitError == nil
    }

    var authServiceNotReadyMessage: String {
        authProviderInitError ?? "Authentication is still connecting. Please try again."
    }

    nonisolated static let legacySensitiveUserDefaultsKeys = [
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

    @discardableResult
    nonisolated static func migrateLegacyAuthStorage(in defaults: UserDefaults) -> [String] {
        legacySensitiveUserDefaultsKeys.compactMap { key in
            guard defaults.object(forKey: key) != nil else { return nil }
            defaults.removeObject(forKey: key)
            return key
        }
    }

    func ensureAuthInitializationTask(priority: TaskPriority = .userInitiated) -> Task<Void, Never> {
        if let initializationTask { return initializationTask }
        let task = Task(priority: priority) { @MainActor [weak self] in
            guard let self else { return }
            await self.initialize()
        }
        initializationTask = task
        return task
    }

    func initialize() async {
        guard !isAuthProviderLoaded else { return }
        let validation = Configuration.currentAuthEnvironmentValidation
        guard validation.isValid else {
            authProviderInitError = validation.userMessage
            isAuthProviderLoaded = false
            return
        }

        do {
            if let stored: ProductAuthSession = try keychain.get(
                forKey: storedSessionKey,
                as: ProductAuthSession.self
            ) {
                authSession = stored
                if stored.expiresAt.timeIntervalSinceNow > 60 {
                    applyAuthenticatedSession(stored)
                } else {
                    _ = await refreshAccessToken()
                }
            }
            authProviderInitError = nil
            isAuthProviderLoaded = true
        } catch {
            authProviderInitError = "Secure sign-in storage could not be opened."
            isAuthProviderLoaded = false
        }
    }

    func retryAuthProviderInitialization() async {
        initializationTask = nil
        isAuthProviderLoaded = false
        authProviderInitError = nil
        await ensureAuthInitializationTask().value
    }

    func signInWithPhone() async throws {
        guard isAuthProviderReady else { throw AuthError.providerNotReady }
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))

        var components = URLComponents(
            url: try SupabaseURLBuilder.authURL("authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "provider", value: Configuration.authProviderID),
            URLQueryItem(name: "redirect_to", value: Configuration.authRedirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256")
        ]
        guard let authorizationURL = components?.url else { throw AuthError.invalidCallback }

        let callbackURL = try await openAuthorizationSession(url: authorizationURL)
        guard let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callback.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.invalidCallback
        }

        let tokenResponse = try await exchangeSupabaseToken(
            grantType: "pkce",
            payload: ["auth_code": code, "code_verifier": verifier]
        )
        try persist(tokenResponse: tokenResponse)
        AppServicePorts.analyticsTracker.track(event: "login_completed", properties: ["method": "sms_otp"])
    }

    private func openAuthorizationSession(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Configuration.authCallbackScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in self?.webAuthenticationSession = nil }
                if let authError = error as? ASWebAuthenticationSessionError,
                   authError.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else if error != nil {
                    continuation.resume(throwing: AuthError.networkError)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: AuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webAuthenticationSession = session
            guard session.start() else {
                webAuthenticationSession = nil
                continuation.resume(throwing: AuthError.providerNotReady)
                return
            }
        }
    }

    private func exchangeSupabaseToken(
        grantType: String,
        payload: [String: String]
    ) async throws -> SupabaseAuthTokenResponse {
        var components = URLComponents(url: try SupabaseURLBuilder.authURL("token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        guard let url = components?.url else { throw AuthError.invalidCallback }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }
        guard (200...299).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["error_description"] as? String
                ?? payload?["message"] as? String
                ?? "Sign in could not be completed."
            throw AuthError.server(message)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SupabaseAuthTokenResponse.self, from: data)
    }

    private func persist(tokenResponse: SupabaseAuthTokenResponse) throws {
        let user = tokenResponse.user
        let email = user.email ?? Self.syntheticAuthEmail(userId: user.id)
        let session = ProductAuthSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: tokenResponse.expiresAt.map(Date.init(timeIntervalSince1970:))
                ?? Date().addingTimeInterval(tokenResponse.expiresIn),
            subject: user.id,
            email: email,
            name: user.name,
            issuedAt: user.createdAt ?? Date()
        )
        try keychain.save(session, forKey: storedSessionKey)
        authSession = session
        applyAuthenticatedSession(session)
    }

    private func applyAuthenticatedSession(_ session: ProductAuthSession) {
        currentUser = LocalUser(
            id: session.subject,
            email: session.email,
            name: session.name,
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        memberSinceDate = session.issuedAt
        isAuthenticated = true
        lastExitReason = .none
        Task { await bootstrapAuthenticatedProfileIfNeeded(sessionId: session.id) }
    }

    func getAccessToken() async -> String? {
        guard let session = authSession else { return nil }
        if session.expiresAt.timeIntervalSinceNow > 60 { return session.accessToken }
        return await refreshAccessToken()
    }

    func getSupabaseToken() async -> String? {
        await getAccessToken()
    }

    private func refreshAccessToken() async -> String? {
        if let refreshTask { return await refreshTask.value }
        guard let current = authSession else {
            await performLogout(exitReason: .sessionExpired)
            return nil
        }

        let task = Task<String?, Never> { @MainActor [weak self] in
            guard let self else { return nil }
            defer { self.refreshTask = nil }
            do {
                let response = try await self.exchangeSupabaseToken(
                    grantType: "refresh_token",
                    payload: ["refresh_token": current.refreshToken]
                )
                try self.persist(tokenResponse: response)
                return self.authSession?.accessToken
            } catch {
                await self.performLogout(exitReason: .sessionExpired)
                return nil
            }
        }
        refreshTask = task
        return await task.value
    }

    func logout() async {
        await performLogout(exitReason: .userInitiated)
    }

    func handleSupabaseUnauthorized() async {
        guard isAuthenticated else { return }
        if await refreshAccessToken() == nil {
            await performLogout(exitReason: .sessionExpired)
        }
    }

    func performLogout(exitReason: AuthExitReason) async {
        if let accessToken = authSession?.accessToken,
           let url = try? SupabaseURLBuilder.authURL("logout") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            _ = try? await urlSession.data(for: request)
        }
        try? keychain.delete(forKey: storedSessionKey)
        authSession = nil
        currentUser = nil
        isAuthenticated = false
        needsLegalConsent = false
        memberSinceDate = nil
        bootstrappedProfileSessionIds.removeAll()
        lastExitReason = exitReason
        AppServicePorts.analyticsTracker.reset()
    }

    func updateProfileDurably(_ updates: [String: Any]) async throws {
        guard let currentUser else { throw SupabaseError.notAuthenticated }
        var payload = updates
        payload["id"] = currentUser.id
        payload["email"] = payload["email"] ?? currentUser.email
        guard let token = await getSupabaseToken() else { throw SupabaseError.tokenGenerationFailed }
        try await SupabaseManager.shared.updateProfile(payload, token: token)
    }

    func updateProfile(_ updates: [String: Any]) async {
        do {
            try await updateProfileDurably(updates)
        } catch {
            ErrorReporter.shared.captureNonFatal(
                error,
                context: ErrorContext(
                    feature: "profile",
                    operation: "updateProfile",
                    screen: nil,
                    userId: currentUser?.id
                )
            )
        }
    }

    func consolidateNameUpdate(_ fullName: String) async throws {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await updateProfileDurably(["full_name": trimmed])
        currentUser?.name = trimmed
    }

    func uploadProfilePicture(_ image: UIImage) async throws -> String? {
        // Profile photo storage remains an app-data concern, not an identity-provider concern.
        nil
    }

    func bootstrapAuthenticatedProfileIfNeeded(sessionId: String?) async {
        guard let sessionId,
              !bootstrappedProfileSessionIds.contains(sessionId),
              let user = currentUser else { return }
        bootstrappedProfileSessionIds.insert(sessionId)

        if let cached = await CoreDataManager.shared.fetchUserProfileSnapshot(for: user.id),
           cached.hasPendingLocalChanges {
            applyAuthenticatedProfile(cached.profile, fallbackEmail: user.email)
            return
        }

        do {
            if let remote = try await SupabaseManager.shared.fetchProfile(userId: user.id) {
                applyAuthenticatedProfile(remote, fallbackEmail: user.email)
                CoreDataManager.shared.saveProfile(
                    remote,
                    userId: user.id,
                    email: remote.email ?? user.email,
                    markSynced: true
                )
            }
        } catch {
            if let cached = await CoreDataManager.shared.fetchUserProfile(for: user.id) {
                applyAuthenticatedProfile(cached, fallbackEmail: user.email)
            } else {
                bootstrappedProfileSessionIds.remove(sessionId)
            }
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
        if let completed = profile.onboardingCompleted {
            user.onboardingCompleted = completed
            OnboardingStateManager.shared.syncCompletionFlagFromProfile(completed, userId: user.id)
        }
        currentUser = user
    }

    @discardableResult
    func applySavedProfileToCurrentUser(_ profile: UserProfile) -> Bool {
        guard currentUser?.id == profile.id else { return false }
        applyAuthenticatedProfile(profile, fallbackEmail: profile.email ?? currentUser?.email ?? "")
        NotificationCenter.default.post(name: .profileUpdated, object: nil)
        return true
    }

    func checkLegalConsent(userId: String) async -> Bool {
        await legalConsentGate.wait()
        defer { Task { await legalConsentGate.signal() } }
        guard let token = await getSupabaseToken(),
              let url = try? SupabaseURLBuilder.restURL(
                  table: "profiles",
                  query: "id=eq.\(userId)&select=legal_accepted_at"
              ) else { return false }
        var request = URLRequest(url: url)
        request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await urlSession.data(for: request),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return false }
        return rows.first?["legal_accepted_at"] is String
    }

    func acceptLegalConsent(userId: String) async {
        await legalConsentGate.wait()
        defer { Task { await legalConsentGate.signal() } }
        guard let token = await getSupabaseToken(),
              let url = try? SupabaseURLBuilder.restURL(table: "profiles") else { return }
        let payload: [String: Any] = [
            "id": userId,
            "legal_accepted_at": ISO8601DateFormatter().string(from: Date()),
            "terms_accepted": true,
            "privacy_accepted": true
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [payload])
        if let (_, response) = try? await urlSession.data(for: request),
           let http = response as? HTTPURLResponse,
           (200...299).contains(http.statusCode) {
            needsLegalConsent = false
        }
    }

    func deleteProductAccount() async throws {
        guard let token = await getSupabaseToken(),
              let url = try? SupabaseURLBuilder.functionURL("delete-user-assets") else {
            throw SupabaseError.notAuthenticated
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Constants.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw SupabaseError.httpError(http.statusCode) }
    }

    func deleteCurrentAccount() async throws {
        try await deleteProductAccount()
        await performLogout(exitReason: .userInitiated)
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        throw PasswordUpdateError.notSupported
    }

    func fetchActiveSessions() async throws -> [SessionInfo] {
        guard let session = authSession else { return [] }
        return [SessionInfo(
            id: session.id,
            deviceName: UIDevice.current.name,
            deviceType: UIDevice.current.model,
            location: "Current device",
            ipAddress: "",
            lastActiveAt: Date(),
            createdAt: session.issuedAt,
            isCurrentSession: true
        )]
    }

    func revokeSession(sessionId: String) async throws {
        guard sessionId == authSession?.id else { return }
        await logout()
    }

    func loginErrorMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Sign in failed. Please try again."
    }

    #if DEBUG
    func applySignedOutUITestFixture() {
        authSession = nil
        currentUser = nil
        isAuthenticated = false
        isAuthProviderLoaded = true
        authProviderInitError = nil
    }
    #endif

    nonisolated static func normalizedAuthEmailCandidate(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), !normalized.contains(" ") else { return nil }
        return normalized
    }

    nonisolated static func syntheticAuthEmail(userId: String) -> String {
        let safe = userId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }
        return "\(String(safe))@identity.logyourbody"
    }

    nonisolated static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Secure random generation failed")
        return base64URL(Data(bytes))
    }

    nonisolated static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension AuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return window
        }
        if let scene = scenes.first { return UIWindow(windowScene: scene) }
        return UIWindow(frame: .zero)
    }
}
