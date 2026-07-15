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

struct OAuthTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }
}

struct OAuthUserInfo: Decodable {
    let subject: String
    let email: String?
    let name: String?
    let phoneNumber: String?

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case email
        case name
        case phoneNumber = "phone_number"
    }
}

private struct ProductProfileEnvelope: Decodable {
    let profile: ProductProfilePayload
}

private struct ProductProfilePayload: Decodable {
    let id: String
    let email: String?
    let username: String?
    let fullName: String?
    let dateOfBirth: Date?
    let height: Double?
    let heightUnit: String?
    let gender: String?
    let activityLevel: String?
    let goalWeight: Double?
    let goalWeightUnit: String?
    let onboardingCompleted: Bool?
    let legalAcceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, email, username, height, gender
        case fullName = "full_name"
        case dateOfBirth = "date_of_birth"
        case heightUnit = "height_unit"
        case activityLevel = "activity_level"
        case goalWeight = "goal_weight"
        case goalWeightUnit = "goal_weight_unit"
        case onboardingCompleted = "onboarding_completed"
        case legalAcceptedAt = "legal_accepted_at"
    }

    var userProfile: UserProfile {
        UserProfile(
            id: id,
            email: email,
            username: username,
            fullName: fullName,
            dateOfBirth: dateOfBirth,
            height: height,
            heightUnit: heightUnit,
            gender: gender,
            activityLevel: activityLevel,
            goalWeight: goalWeight,
            goalWeightUnit: goalWeightUnit,
            onboardingCompleted: onboardingCompleted
        )
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

    let userDefaults: UserDefaults
    let keychain: KeychainManager
    let urlSession: URLSession
    let legalConsentGate = AsyncGate()

    private let storedSessionKey = "productAuth.jovieOAuthSession"
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

    func signInWithApple() async throws {
        guard isAuthProviderReady else { throw AuthError.providerNotReady }
        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafeString(byteCount: 32)

        var components = URLComponents(
            url: try oauthURL(path: "oauth2/authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: Configuration.authClientID),
            URLQueryItem(name: "redirect_uri", value: Configuration.authRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid profile email offline_access"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components?.url else { throw AuthError.invalidCallback }

        let callbackURL = try await openAuthorizationSession(url: authorizationURL)
        guard let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              callback.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = callback.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.invalidCallback
        }

        let tokenResponse = try await exchangeOAuthToken(
            parameters: [
                "grant_type": "authorization_code",
                "client_id": Configuration.authClientID,
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": Configuration.authRedirectURI
            ]
        )
        let userInfo = try await fetchOAuthUserInfo(accessToken: tokenResponse.accessToken)
        try await registerProductSession(accessToken: tokenResponse.accessToken)
        try persist(tokenResponse: tokenResponse, userInfo: userInfo)
        AppServicePorts.analyticsTracker.track(event: "login_completed", properties: ["method": "apple"])
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

    private func oauthURL(path: String) throws -> URL {
        guard let issuer = URL(string: Configuration.authIssuer),
              issuer.scheme == "https" else { throw AuthError.providerNotReady }
        return issuer.appendingPathComponent(path)
    }

    private func exchangeOAuthToken(parameters: [String: String]) async throws -> OAuthTokenResponse {
        let url = try oauthURL(path: "oauth2/token")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var form = URLComponents()
        form.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }
        guard (200...299).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = payload?["error_description"] as? String
                ?? payload?["message"] as? String
                ?? "Sign in could not be completed."
            throw AuthError.server(message)
        }
        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    private func fetchOAuthUserInfo(accessToken: String) async throws -> OAuthUserInfo {
        var request = URLRequest(url: try oauthURL(path: "oauth2/userinfo"))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }
        guard (200...299).contains(http.statusCode) else { throw AuthError.invalidToken }
        return try JSONDecoder().decode(OAuthUserInfo.self, from: data)
    }

    private func registerProductSession(accessToken: String) async throws {
        guard let baseURL = URL(string: Configuration.apiBaseURL),
              let url = URL(string: "/api/auth/mobile/session", relativeTo: baseURL)?.absoluteURL else {
            throw AuthError.providerNotReady
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }
        guard (200...299).contains(http.statusCode) else {
            throw AuthError.server("Your LogYourBody account could not be initialized.")
        }
    }

    private func persist(
        tokenResponse: OAuthTokenResponse,
        userInfo: OAuthUserInfo,
        fallbackRefreshToken: String? = nil
    ) throws {
        guard let refreshToken = tokenResponse.refreshToken ?? fallbackRefreshToken else {
            throw AuthError.invalidToken
        }
        let email = userInfo.email ?? Self.syntheticAuthEmail(userId: userInfo.subject)
        let session = ProductAuthSession(
            accessToken: tokenResponse.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(tokenResponse.expiresIn),
            subject: userInfo.subject,
            email: email,
            name: userInfo.name,
            issuedAt: Date()
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
        // The Jovie OAuth access token is scoped to LYB's first-party APIs and
        // must never be forwarded to the retired Supabase data plane. Keep
        // legacy sync fail-closed until those endpoints move behind LYB's
        // server-side Neon adapter.
        nil
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
                let response = try await self.exchangeOAuthToken(
                    parameters: [
                        "grant_type": "refresh_token",
                        "client_id": Configuration.authClientID,
                        "refresh_token": current.refreshToken
                    ]
                )
                let userInfo = try await self.fetchOAuthUserInfo(accessToken: response.accessToken)
                try self.persist(
                    tokenResponse: response,
                    userInfo: userInfo,
                    fallbackRefreshToken: current.refreshToken
                )
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
        guard currentUser != nil else { throw AuthError.invalidToken }
        let payload = try Self.normalizedProductProfilePayload(updates)
        _ = try await requestProductProfile(method: "PATCH", body: payload)
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
            let remote = try await requestProductProfile(method: "GET").profile.userProfile
            applyAuthenticatedProfile(remote, fallbackEmail: user.email)
            if AuthProfileBootstrapPolicy.shouldPersistProjectedProfile(remote) {
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
        guard currentUser?.id == userId,
              let response = try? await requestProductProfile(method: "GET") else { return false }
        return response.profile.legalAcceptedAt != nil
    }

    func acceptLegalConsent(userId: String) async {
        await legalConsentGate.wait()
        defer { Task { await legalConsentGate.signal() } }
        guard currentUser?.id == userId else { return }
        if (try? await requestProductProfile(
            method: "PATCH",
            body: ["legalAccepted": true]
        )) != nil {
            needsLegalConsent = false
        }
    }

    func deleteProductAccount() async throws {
        _ = try await requestProductProfile(method: "DELETE")
    }

    private func requestProductProfile(
        method: String,
        body: [String: Any]? = nil
    ) async throws -> ProductProfileEnvelope {
        guard let accessToken = await getAccessToken(),
              let baseURL = URL(string: Configuration.apiBaseURL),
              let url = URL(string: "/api/auth/mobile/profile", relativeTo: baseURL)?.absoluteURL else {
            throw AuthError.invalidToken
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AuthError.networkError }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw AuthError.invalidToken }
            throw AuthError.server("Your LogYourBody profile could not be updated.")
        }

        if http.statusCode == 204 {
            return ProductProfileEnvelope(profile: ProductProfilePayload(
                id: currentUser?.id ?? "",
                email: currentUser?.email,
                username: nil,
                fullName: currentUser?.name,
                dateOfBirth: nil,
                height: nil,
                heightUnit: nil,
                gender: nil,
                activityLevel: nil,
                goalWeight: nil,
                goalWeightUnit: nil,
                onboardingCompleted: nil,
                legalAcceptedAt: nil
            ))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(Self.productDateFormatter)
        return try decoder.decode(ProductProfileEnvelope.self, from: data)
    }

    nonisolated private static let productDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    nonisolated private static func normalizedProductProfilePayload(
        _ updates: [String: Any]
    ) throws -> [String: Any] {
        var payload: [String: Any] = [:]
        for (key, value) in updates {
            if let date = value as? Date {
                payload[key] = productDateFormatter.string(from: date)
            } else if JSONSerialization.isValidJSONObject([key: value]) {
                payload[key] = value
            }
        }
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw AuthError.server("Your profile details could not be saved.")
        }
        return payload
    }

    func deleteCurrentAccount() async throws {
        try await deleteProductAccount()
        await performLogout(exitReason: .userInitiated)
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
