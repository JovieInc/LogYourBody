import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

@MainActor
final class BodySpecAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = BodySpecAuthManager()

    private struct Token: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
        let userId: String?
        let email: String?
    }

    private enum AuthError: Error {
        case notConfigured
        case userCancelled
        case missingCode
        case tokenExchangeFailed
        case invalidRedirectURL
    }

    private let keychain = KeychainManager.shared
    private var currentToken: Token?
    private var authSession: ASWebAuthenticationSession?

    private let tokenStorageKey = "BodySpecAuthToken"
    private let authorizationEndpoint = URL(
        string: "https://auth.bodyspec.com/realms/bodyspec/protocol/openid-connect/auth"
    )!
    private let tokenEndpoint = URL(
        string: "https://auth.bodyspec.com/realms/bodyspec/protocol/openid-connect/token"
    )!

    override init() {
        super.init()

        do {
            if let stored: Token = try keychain.get(forKey: tokenStorageKey, as: Token.self) {
                currentToken = stored
            }
        } catch {
            currentToken = nil
        }
    }

    var isConfigured: Bool {
        !Configuration.bodySpecClientId.isEmpty && !Configuration.bodySpecRedirectURI.isEmpty
    }

    var isConnected: Bool {
        guard let token = currentToken else { return false }
        return token.expiresAt > Date()
    }

    var connectedEmail: String? {
        currentToken?.email
    }

    func disconnect() {
        currentToken = nil

        do {
            try keychain.delete(forKey: tokenStorageKey)
        } catch {
        }
    }

    func ensureValidToken() async throws -> String? {
        guard isConfigured else { return nil }

        if let token = currentToken, token.expiresAt > Date() {
            return token.accessToken
        }

        return nil
    }

    func connect() async throws {
        guard isConfigured else {
            throw AuthError.notConfigured
        }

        guard let redirectURL = URL(string: Configuration.bodySpecRedirectURI) else {
            throw AuthError.invalidRedirectURL
        }

        let verifier = generateCodeVerifier()
        let challenge = codeChallenge(for: verifier)
        let state = UUID().uuidString

        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "response_type", value: "code"))
        queryItems.append(URLQueryItem(name: "client_id", value: Configuration.bodySpecClientId))
        queryItems.append(URLQueryItem(name: "redirect_uri", value: redirectURL.absoluteString))
        queryItems.append(URLQueryItem(name: "scope", value: "openid profile email"))
        queryItems.append(URLQueryItem(name: "code_challenge", value: challenge))
        queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        queryItems.append(URLQueryItem(name: "state", value: state))
        components?.queryItems = queryItems

        guard let authURL = components?.url,
              let callbackScheme = redirectURL.scheme else {
            throw AuthError.invalidRedirectURL
        }

        let code = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                guard let self = self else { return }

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.userCancelled)
                    self.authSession = nil
                    return
                }

                if let error = error {
                    continuation.resume(throwing: error)
                    self.authSession = nil
                    return
                }

                guard let callbackURL else {
                    continuation.resume(throwing: AuthError.missingCode)
                    self.authSession = nil
                    return
                }

                guard let components = URLComponents(
                    url: callbackURL,
                    resolvingAgainstBaseURL: false
                ),
                    let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
                    returnedState == state,
                    let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: AuthError.missingCode)
                    self.authSession = nil
                    return
                }

                continuation.resume(returning: code)
                self.authSession = nil
            }

            session.prefersEphemeralWebBrowserSession = true
            session.presentationContextProvider = self
            self.authSession = session
            _ = session.start()
        }

        let token = try await exchangeCodeForToken(code: code, verifier: verifier, redirectURI: redirectURL)
        currentToken = token

        do {
            try keychain.save(token, forKey: tokenStorageKey)
        } catch {
        }
    }

    private func exchangeCodeForToken(
        code: String,
        verifier: String,
        redirectURI: URL
    ) async throws -> Token {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyItems: [URLQueryItem] = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: Configuration.bodySpecClientId),
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
        let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))

        return Token(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: expiryDate,
            userId: nil,
            email: nil
        )
    }

    private func generateCodeVerifier() -> String {
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

    private func codeChallenge(for verifier: String) -> String {
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
