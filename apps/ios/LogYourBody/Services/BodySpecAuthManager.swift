import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

@MainActor
final class BodySpecAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = BodySpecAuthManager()

    enum AuthError: Error {
        case notConfigured, notSignedIn, userCancelled, missingCode, tokenExchangeFailed, invalidRedirectURL
        case browserDidNotStart, connectionReplaced
    }

    typealias TokenExchange = @MainActor (String, String, URL) async throws -> BodySpecStoredToken
    private let tokenStore: BodySpecTokenStoring
    private let account: BodySpecAccountAccess
    private let makeAuthorizationSession: BodySpecAuthorizationFactory
    private let tokenExchange: TokenExchange?
    private let configuration: () -> (clientID: String, redirectURI: String)
    private let now: () -> Date
    private var currentToken: BodySpecStoredToken?
    private var generation = UUID()
    private var activeConnectID: UUID?
    private var pendingAuthorization: (
        id: UUID, session: BodySpecAuthorizationSession, continuation: BodySpecAuthorizationContinuation
    )?

    override convenience init() {
        self.init(tokenStore: KeychainBodySpecTokenStore(), account: .live)
    }

    init(
        tokenStore: BodySpecTokenStoring,
        account: BodySpecAccountAccess,
        makeAuthorizationSession: @escaping BodySpecAuthorizationFactory = { url, scheme, context, completion in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme, completionHandler: completion)
            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = context
            return session
        },
        tokenExchange: TokenExchange? = nil,
        configuration: @escaping () -> (clientID: String, redirectURI: String) = {
            (Configuration.bodySpecClientId, Configuration.bodySpecRedirectURI)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.tokenStore = tokenStore
        self.account = account
        self.makeAuthorizationSession = makeAuthorizationSession
        self.tokenExchange = tokenExchange
        self.configuration = configuration
        self.now = now
        self.currentToken = try? tokenStore.load()
        super.init()
    }

    var isConfigured: Bool {
        let config = configuration()
        return !config.clientID.isEmpty && !config.redirectURI.isEmpty
    }

    var isConnected: Bool { admittedStoredToken() != nil }
    var connectedEmail: String? { admittedStoredToken()?.email }

    private func admittedStoredToken() -> BodySpecStoredToken? {
        guard activeConnectID == nil, let ownership = account.capture(), account.owns(ownership),
              let token = currentToken, token.lybOwnerId == ownership.subject,
              !token.accessToken.isEmpty, token.expiresAt > now() else { return nil }
        return token
    }

    func connectionSnapshot(for expectedOwner: AuthManager.ProfileSessionOwnership? = nil) throws -> BodySpecConnectionSnapshot {
        guard isConfigured, let ownership = account.capture(), expectedOwner == nil || expectedOwner == ownership,
              let token = admittedStoredToken() else { throw BodySpecAPIError.notConnected }
        let capturedGeneration = generation
        return BodySpecConnectionSnapshot(token: token.accessToken) { [weak self] in
            guard let self, self.generation == capturedGeneration, self.account.owns(ownership),
                  self.activeConnectID == nil, token.expiresAt > self.now(),
                  self.currentToken?.lybOwnerId == ownership.subject else { throw CancellationError() }
        }
    }

    func ensureValidToken() async throws -> String? {
        guard let snapshot = try? connectionSnapshot() else { return nil }
        return try snapshot.admittedToken()
    }

    func disconnect() throws {
        generation = UUID()
        activeConnectID = nil
        abortPendingAuthorization()
        currentToken = nil
        try tokenStore.delete()
    }

    func connect() async throws {
        guard isConfigured else { throw AuthError.notConfigured }
        guard let ownership = account.capture(), account.owns(ownership) else { throw AuthError.notSignedIn }
        let config = configuration()
        guard let redirect = URL(string: config.redirectURI), let scheme = redirect.scheme else {
            throw AuthError.invalidRedirectURL
        }
        let operationID = UUID()
        generation = operationID
        activeConnectID = operationID
        abortPendingAuthorization()
        defer { if activeConnectID == operationID { activeConnectID = nil } }
        let verifier = generateCodeVerifier()
        let state = UUID().uuidString
        let url = try authorizationURL(clientID: config.clientID, redirect: redirect, verifier: verifier, state: state)
        let code = try await authorize(url: url, scheme: scheme, state: state, operationID: operationID)
        try requireConnectionAttempt(operationID, ownership: ownership)
        let token: BodySpecStoredToken
        if let tokenExchange {
            token = try await tokenExchange(code, verifier, redirect)
        } else {
            token = try await exchangeCodeForToken(code: code, verifier: verifier, redirectURI: redirect)
        }
        try requireConnectionAttempt(operationID, ownership: ownership)
        guard !token.accessToken.isEmpty, token.expiresAt > now() else { throw AuthError.tokenExchangeFailed }
        let ownedToken = token.owned(by: ownership.subject)
        // Durable installation must succeed before any connected state can be published.
        try tokenStore.save(ownedToken)
        currentToken = ownedToken
    }

    private func requireConnectionAttempt(_ id: UUID, ownership: AuthManager.ProfileSessionOwnership) throws {
        try Task.checkCancellation()
        guard generation == id, activeConnectID == id, account.owns(ownership) else { throw AuthError.connectionReplaced }
    }

    private func authorizationURL(clientID: String, redirect: URL, verifier: String, state: String) throws -> URL {
        var components = URLComponents(string: "https://auth.bodyspec.com/realms/bodyspec/protocol/openid-connect/auth")
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
            URLQueryItem(name: "scope", value: "openid profile email"),
            URLQueryItem(name: "code_challenge", value: codeChallenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "state", value: state)
        ]
        guard let url = components?.url else { throw AuthError.invalidRedirectURL }
        return url
    }

    private func authorize(url: URL, scheme: String, state: String, operationID: UUID) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let once = BodySpecAuthorizationContinuation(continuation)
                let session = makeAuthorizationSession(url, scheme, self) { [weak self] callback, error in
                    guard let self else { once.resume(.failure(CancellationError())); return }
                    Task { @MainActor in
                        guard self.pendingAuthorization?.id == operationID else {
                            once.resume(.failure(AuthError.connectionReplaced)); return
                        }
                        self.pendingAuthorization = nil
                        if let error { once.resume(.failure(error)); return }
                        let query = callback.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
                        guard query?.first(where: { $0.name == "state" })?.value == state,
                              let code = query?.first(where: { $0.name == "code" })?.value else {
                            once.resume(.failure(AuthError.missingCode)); return
                        }
                        once.resume(.success(code))
                    }
                }
                pendingAuthorization = (operationID, session, once)
                if !session.start() {
                    pendingAuthorization = nil
                    once.resume(.failure(AuthError.browserDidNotStart))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                guard self?.pendingAuthorization?.id == operationID else { return }
                self?.abortPendingAuthorization()
            }
        }
    }

    private func abortPendingAuthorization() {
        let pending = pendingAuthorization
        pendingAuthorization = nil
        pending?.continuation.resume(.failure(CancellationError()))
        pending?.session.cancel()
    }

    private func exchangeCodeForToken(
        code: String,
        verifier: String,
        redirectURI: URL
    ) async throws -> BodySpecStoredToken {
        let endpoint = URL(string: "https://auth.bodyspec.com/realms/bodyspec/protocol/openid-connect/token")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyItems: [URLQueryItem] = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: configuration().clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]

        var bodyComponents = URLComponents()
        bodyComponents.queryItems = bodyItems
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.tokenExchangeFailed
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Int?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
            }
        }

        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(TokenResponse.self, from: data)

        let expiresIn = tokenResponse.expiresIn ?? 3_600
        let expiryDate = now().addingTimeInterval(TimeInterval(expiresIn))

        return BodySpecStoredToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: expiryDate,
            userId: nil,
            email: nil,
            lybOwnerId: nil
        )
    }

    // Internal (not private) so deterministic PKCE behavior is unit-testable.
    func generateCodeVerifier() -> String {
        let length = 64
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
        var result = ""
        result.reserveCapacity(length)

        for _ in 0..<length {
            if let random = characters.randomElement() {
                result.append(random)
            }
        }

        return result
    }

    // Internal (not private) so deterministic PKCE behavior is unit-testable.
    func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            if let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return window
            }
            return UIWindow(windowScene: windowScene)
        }

        return UIWindow(frame: .zero)
    }
}
