import XCTest
@testable import LogYourBody

/// Regression: the last onboarding profile step calls `consolidateNameUpdate`,
/// which must PATCH `/api/auth/mobile/profile` with camelCase `fullName`.
/// The server schema is `.strict()` and rejects snake_case `full_name` with 400.
@MainActor
final class MobileProfileNamePayloadTests: XCTestCase {
    private let defaultsSuiteName = "MobileProfileNamePayloadTests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        NamePayloadStubURLProtocol.reset()
    }

    override func tearDown() {
        NamePayloadStubURLProtocol.reset()
        UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        super.tearDown()
    }

    func testConsolidateNameUpdateSendsCamelCaseFullNameKey() async throws {
        NamePayloadStubURLProtocol.install { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/auth/mobile/profile")
            return StubbedHTTPResponse(
                statusCode: 200,
                body: Data(
                    #"""
                    {"profile":{"id":"name-user","full_name":"Tim White","onboarding_completed":false}}
                    """#.utf8
                )
            )
        }

        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            return XCTFail("UserDefaults suite unavailable")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NamePayloadStubURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        let manager = AuthManager(
            userDefaults: defaults,
            urlSession: URLSession(configuration: configuration)
        )
        manager.currentUser = LocalUser(
            id: "name-user",
            email: "name@example.com",
            name: nil,
            avatarUrl: nil,
            profile: nil,
            onboardingCompleted: false
        )
        manager.authSession = ProductAuthSession(
            accessToken: "stub-access-token",
            refreshToken: "stub-refresh-token",
            expiresAt: Date(timeIntervalSinceNow: 3_600),
            subject: "name-user",
            email: "name@example.com",
            name: nil,
            issuedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        try await manager.consolidateNameUpdate("Tim White")

        let patch = try XCTUnwrap(
            NamePayloadStubURLProtocol.requests.first { $0.httpMethod == "PATCH" }
        )
        let body = try XCTUnwrap(NamePayloadStubURLProtocol.bodyData(of: patch))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["fullName"] as? String, "Tim White")
        XCTAssertNil(json["full_name"], "snake_case full_name is rejected by the strict mobile profile schema")
        XCTAssertEqual(manager.currentUser?.name, "Tim White")
    }
}

// MARK: - Minimal stub infra (mirrors LegalConsentPolicyTests)

private struct StubbedHTTPResponse {
    let statusCode: Int
    let body: Data
}

private final class NamePayloadStubURLProtocol: URLProtocol {
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

    override func stopLoading() {}
}
