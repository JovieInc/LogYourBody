import XCTest
@testable import LogYourBody

@MainActor
final class LegalConsentPolicyTests: XCTestCase {
    private let defaultsSuiteName = "LegalConsentPolicyTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        LegalConsentStubURLProtocol.reset()
    }

    override func tearDown() {
        LegalConsentStubURLProtocol.reset()
        UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        super.tearDown()
    }

    // MARK: - Continue-gate policy

    func testContinueStartsDisabled() {
        XCTAssertFalse(
            LegalConsentPolicy.canContinue(acceptedTerms: false, acceptedPrivacy: false, isLoading: false)
        )
    }

    func testContinueRequiresBothDocuments() {
        XCTAssertFalse(
            LegalConsentPolicy.canContinue(acceptedTerms: true, acceptedPrivacy: false, isLoading: false)
        )
        XCTAssertFalse(
            LegalConsentPolicy.canContinue(acceptedTerms: false, acceptedPrivacy: true, isLoading: false)
        )
    }

    func testContinueEnabledWhenBothDocumentsAccepted() {
        XCTAssertTrue(
            LegalConsentPolicy.canContinue(acceptedTerms: true, acceptedPrivacy: true, isLoading: false)
        )
    }

    func testContinueDisabledWhileAcceptInFlight() {
        XCTAssertFalse(
            LegalConsentPolicy.canContinue(acceptedTerms: true, acceptedPrivacy: true, isLoading: true)
        )
    }

    // MARK: - Persistence through the stubbed profile endpoint

    func testAcceptSuccessPersistsConsentAndClearsGate() async throws {
        let store = StubbedConsentStore()
        let manager = try makeManager(store: store)

        let consentBeforeAccept = await manager.checkLegalConsent(userId: "consent-user")
        XCTAssertFalse(consentBeforeAccept)
        XCTAssertTrue(manager.needsLegalConsent)

        await manager.acceptLegalConsent(userId: "consent-user")

        XCTAssertFalse(manager.needsLegalConsent)
        let patch = try XCTUnwrap(LegalConsentStubURLProtocol.requests.first { $0.httpMethod == "PATCH" })
        XCTAssertEqual(patch.url?.path, "/api/auth/mobile/profile")
        XCTAssertEqual(patch.value(forHTTPHeaderField: "Authorization"), "Bearer stub-access-token")
        let body = try XCTUnwrap(LegalConsentStubURLProtocol.bodyData(of: patch))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["legalAccepted"] as? Bool, true)

        let consentAfterAccept = await manager.checkLegalConsent(userId: "consent-user")
        XCTAssertTrue(consentAfterAccept)
    }

    func testAcceptFailureKeepsGateEngagedAndPersistsNothing() async throws {
        let store = StubbedConsentStore(patchBehavior: .reject)
        let manager = try makeManager(store: store)

        await manager.acceptLegalConsent(userId: "consent-user")

        XCTAssertTrue(manager.needsLegalConsent)
        let consentAfterFailure = await manager.checkLegalConsent(userId: "consent-user")
        XCTAssertFalse(consentAfterFailure)
    }

    func testAcceptForMismatchedUserDoesNotPersist() async throws {
        let store = StubbedConsentStore()
        let manager = try makeManager(store: store)

        await manager.acceptLegalConsent(userId: "someone-else")

        XCTAssertTrue(manager.needsLegalConsent)
        XCTAssertTrue(LegalConsentStubURLProtocol.requests.isEmpty)
    }

    func testCheckLegalConsentFailsClosedOnServerError() async throws {
        let store = StubbedConsentStore(readsFail: true)
        let manager = try makeManager(store: store)

        let consentOnError = await manager.checkLegalConsent(userId: "consent-user")
        XCTAssertFalse(consentOnError)
        XCTAssertTrue(manager.needsLegalConsent)
    }

    // MARK: - Helpers

    private func makeManager(store: StubbedConsentStore) throws -> AuthManager {
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            throw TestSetupError.userDefaultsUnavailable
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LegalConsentStubURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let manager = AuthManager(
            userDefaults: defaults,
            urlSession: URLSession(configuration: configuration)
        )
        manager.currentUser = LocalUser(
            id: "consent-user",
            email: "consent@example.com",
            name: nil,
            avatarUrl: nil,
            profile: nil
        )
        manager.authSession = ProductAuthSession(
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 3_600),
            subject: "consent-user",
            email: "consent@example.com",
            name: nil,
            issuedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        manager.needsLegalConsent = true
        LegalConsentStubURLProtocol.install { request in
            store.response(for: request)
        }
        return manager
    }
}

private enum TestSetupError: Error {
    case userDefaultsUnavailable
}

private struct StubbedHTTPResponse {
    let statusCode: Int
    let body: Data
}

private final class StubbedConsentStore {
    enum PatchBehavior {
        case accept
        case reject
    }

    private let lock = NSLock()
    private let patchBehavior: PatchBehavior
    private let readsFail: Bool
    private var accepted = false

    init(patchBehavior: PatchBehavior = .accept, readsFail: Bool = false) {
        self.patchBehavior = patchBehavior
        self.readsFail = readsFail
    }

    func response(for request: URLRequest) -> StubbedHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        if request.httpMethod == "PATCH" {
            switch patchBehavior {
            case .accept:
                accepted = true
                return StubbedHTTPResponse(statusCode: 204, body: Data())
            case .reject:
                return StubbedHTTPResponse(statusCode: 500, body: Data())
            }
        }
        if readsFail {
            return StubbedHTTPResponse(statusCode: 500, body: Data())
        }
        let acceptedAt = accepted ? "\"2025-07-11\"" : "null"
        let payload = """
        {"profile": {"id": "consent-user", "legal_accepted_at": \(acceptedAt)}}
        """
        return StubbedHTTPResponse(statusCode: 200, body: Data(payload.utf8))
    }
}

private final class LegalConsentStubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requestHandler: ((URLRequest) -> StubbedHTTPResponse)?
    private static var recordedRequests: [URLRequest] = []

    static func install(handler: @escaping (URLRequest) -> StubbedHTTPResponse) {
        lock.lock()
        recordedRequests = []
        requestHandler = handler
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        recordedRequests = []
        requestHandler = nil
        lock.unlock()
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1_024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1_024)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data.isEmpty ? nil : data
    }

    override static func canInit(with request: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.requestHandler
        Self.recordedRequests.append(request)
        Self.lock.unlock()

        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let stub = handler(request)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "Cache-Control": "no-store"
            ]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() { }
}
