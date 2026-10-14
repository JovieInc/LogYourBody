import AuthenticationServices
import Foundation

struct BodySpecStoredToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let userId: String?
    let email: String?
    let lybOwnerId: String?

    func owned(by subject: String) -> Self {
        Self(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt,
             userId: userId, email: email, lybOwnerId: subject)
    }
}

@MainActor
protocol BodySpecTokenStoring {
    func load() throws -> BodySpecStoredToken?
    func save(_ token: BodySpecStoredToken) throws
    func delete() throws
}

@MainActor
struct KeychainBodySpecTokenStore: BodySpecTokenStoring {
    private let key = "BodySpecAuthToken"
    func load() throws -> BodySpecStoredToken? { try KeychainManager.shared.get(forKey: key, as: BodySpecStoredToken.self) }
    func save(_ token: BodySpecStoredToken) throws { try KeychainManager.shared.save(token, forKey: key) }
    func delete() throws { try KeychainManager.shared.delete(forKey: key) }
}

@MainActor
struct BodySpecAccountAccess {
    var capture: () -> AuthManager.ProfileSessionOwnership?
    var owns: (AuthManager.ProfileSessionOwnership) -> Bool

    static var live: Self {
        Self(capture: { AuthManager.shared.captureAccountSession() }, owns: { AuthManager.shared.ownsAccountSession($0) })
    }
}

/// The token is immutable for the lifetime of a request/import. Validation never substitutes a newer connection.
struct BodySpecConnectionSnapshot: Sendable {
    private let token: String
    private let admission: @MainActor @Sendable () throws -> Void

    init(token: String, admission: @escaping @MainActor @Sendable () throws -> Void) {
        self.token = token
        self.admission = admission
    }

    @MainActor
    func validate() throws {
        try Task.checkCancellation()
        try admission()
    }

    @MainActor
    func admittedToken() throws -> String {
        try validate()
        return token
    }
}

@MainActor
protocol BodySpecAuthorizationSession: AnyObject {
    func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession: BodySpecAuthorizationSession {}

typealias BodySpecAuthorizationFactory = @MainActor (
    URL, String, ASWebAuthenticationPresentationContextProviding,
    @escaping (URL?, Error?) -> Void
) -> BodySpecAuthorizationSession

/// Browser callbacks and task cancellation can race; neither may resume a continuation twice.
final class BodySpecAuthorizationContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }

    func resume(_ result: Result<String, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
