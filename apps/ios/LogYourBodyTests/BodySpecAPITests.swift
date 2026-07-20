//
// BodySpecAPITests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

/// Stubs the BodySpec REST boundary for `BodySpecAPI` contract tests.
/// Registered on a per-test URLSessionConfiguration, so no global state leaks
/// into other suites.
private final class BodySpecStubURLProtocol: URLProtocol {
    enum Stub {
        case http(statusCode: Int, body: Data)
        case nonHTTPResponse
        case networkError(URLError.Code)
    }

    static var stub: Stub = .http(statusCode: 200, body: Data())
    static var recordedRequests: [URLRequest] = []

    // swiftlint:disable:next static_over_final_class
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    // swiftlint:disable:next static_over_final_class
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let client else {
            return
        }

        Self.recordedRequests.append(request)

        switch Self.stub {
        case .http(let statusCode, let body):
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) ?? HTTPURLResponse()
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
        case .nonHTTPResponse:
            let response = URLResponse(
                url: url,
                mimeType: nil,
                expectedContentLength: 0,
                textEncodingName: nil
            )
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocolDidFinishLoading(self)
        case .networkError(let code):
            client.urlProtocol(self, didFailWithError: URLError(code))
        }
    }

    override func stopLoading() {}

    static func reset() {
        stub = .http(statusCode: 200, body: Data())
        recordedRequests = []
    }
}

private struct StubBodySpecAuthProvider: BodySpecAuthTokenProviding {
    let token: String?

    func ensureValidToken() async throws -> String? {
        token
    }
}

private enum BodySpecAPIFixture {
    static let userJSON = """
        {"user_id":"user-123","email":"dexa@example.com","first_name":"Alex","last_name":"Rivera"}
        """

    static let userMinimalJSON = """
        {"user_id":"user-123","email":"dexa@example.com"}
        """

    static let resultsJSON = """
        {
          "results": [
            {
              "result_id": "result-123",
              "start_time": "2025-01-15T10:30:00Z",
              "location": { "location_id": "loc-1", "name": "Santa Monica" },
              "service": {
                "name": "DEXA Scan",
                "description": "Full body composition",
                "service_id": "svc-1",
                "service_code": "DXA"
              }
            }
          ]
        }
        """

    static let resultsNullOptionalsJSON = """
        {
          "results": [
            {
              "result_id": "result-9",
              "start_time": "2024-11-02T07:15:44Z",
              "location": { "location_id": "loc-2", "name": null },
              "service": { "name": "DEXA Scan", "description": "Composition scan" }
            }
          ]
        }
        """

    static let scanInfoJSON = """
        {
          "result_id": "result-123",
          "scanner_model": "Hologic Horizon W",
          "acquire_time": "2025-01-15T10:30:00Z",
          "analyze_time": "2025-01-15T10:31:12Z"
        }
        """

    static let compositionJSON = """
        {
          "result_id": "result-123",
          "total": {
            "fat_mass_kg": 14.02,
            "lean_mass_kg": 61.85,
            "bone_mass_kg": 3.11,
            "total_mass_kg": 78.98,
            "tissue_fat_pct": 18.4,
            "region_fat_pct": 17.7
          }
        }
        """

    static let emptyResultsJSON = """
        {"results":[]}
        """
}

@MainActor
final class BodySpecAPITests: XCTestCase {
    private let baseURL = URL(string: "https://bodyspec.test")!
    private let accessToken = "test-access-token"

    override func setUp() {
        super.setUp()
        BodySpecStubURLProtocol.reset()
    }

    override func tearDown() {
        BodySpecStubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Request construction

    func testGetUserBuildsAuthorizedGETRequest() async throws {
        stubJSON(BodySpecAPIFixture.userJSON)

        _ = try await makeAPI(authToken: accessToken).getUser()

        let request = try recordedRequest()
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://bodyspec.test/api/v1/users/me")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(accessToken)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.httpBody)
    }

    func testListResultsBuildsPaginatedPathAndQuery() async throws {
        stubJSON(BodySpecAPIFixture.emptyResultsJSON)

        _ = try await makeAPI(authToken: accessToken).listResults(page: 3, pageSize: 50)

        let request = try recordedRequest()
        XCTAssertEqual(request.httpMethod, "GET")
        // URL.appendingPathComponent normalizes away the source literal's
        // trailing slash; this pins the actual wire path.
        XCTAssertEqual(request.url?.path, "/api/v1/users/me/results")
        let queryItems = try queryItems(of: request)
        XCTAssertEqual(queryItems.count, 2)
        XCTAssertEqual(queryItems.first(where: { $0.name == "page" })?.value, "3")
        XCTAssertEqual(queryItems.first(where: { $0.name == "page_size" })?.value, "50")
    }

    func testListResultsUsesDefaultPagination() async throws {
        stubJSON(BodySpecAPIFixture.emptyResultsJSON)

        _ = try await makeAPI(authToken: accessToken).listResults()

        let request = try recordedRequest()
        let queryItems = try queryItems(of: request)
        XCTAssertEqual(queryItems.first(where: { $0.name == "page" })?.value, "1")
        XCTAssertEqual(queryItems.first(where: { $0.name == "page_size" })?.value, "20")
    }

    func testGetDexaScanInfoBuildsResultScopedRequest() async throws {
        stubJSON(BodySpecAPIFixture.scanInfoJSON)

        _ = try await makeAPI(authToken: accessToken).getDexaScanInfo(resultId: "result-123")

        let request = try recordedRequest()
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://bodyspec.test/api/v1/users/me/results/result-123/dexa/scan-info"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(accessToken)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testGetDexaCompositionBuildsResultScopedRequest() async throws {
        stubJSON(BodySpecAPIFixture.compositionJSON)

        _ = try await makeAPI(authToken: accessToken).getDexaComposition(resultId: "result-123")

        let request = try recordedRequest()
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://bodyspec.test/api/v1/users/me/results/result-123/dexa/composition"
        )
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(accessToken)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    // MARK: - Response decoding

    func testGetUserDecodesAllFields() async throws {
        stubJSON(BodySpecAPIFixture.userJSON)

        let user = try await makeAPI(authToken: accessToken).getUser()

        XCTAssertEqual(user.userId, "user-123")
        XCTAssertEqual(user.email, "dexa@example.com")
        XCTAssertEqual(user.firstName, "Alex")
        XCTAssertEqual(user.lastName, "Rivera")
    }

    func testGetUserDecodesMissingOptionalNamesAsNil() async throws {
        stubJSON(BodySpecAPIFixture.userMinimalJSON)

        let user = try await makeAPI(authToken: accessToken).getUser()

        XCTAssertEqual(user.userId, "user-123")
        XCTAssertEqual(user.email, "dexa@example.com")
        XCTAssertNil(user.firstName)
        XCTAssertNil(user.lastName)
    }

    func testListResultsDecodesSummaries() async throws {
        stubJSON(BodySpecAPIFixture.resultsJSON)

        let response = try await makeAPI(authToken: accessToken).listResults()

        XCTAssertEqual(response.results.count, 1)
        let summary = try XCTUnwrap(response.results.first)
        XCTAssertEqual(summary.resultId, "result-123")
        XCTAssertEqual(summary.startTime, Date(timeIntervalSince1970: 1_736_937_000))
        XCTAssertEqual(summary.location.locationId, "loc-1")
        XCTAssertEqual(summary.location.name, "Santa Monica")
        XCTAssertEqual(summary.service.name, "DEXA Scan")
        XCTAssertEqual(summary.service.description, "Full body composition")
        XCTAssertEqual(summary.service.serviceId, "svc-1")
        XCTAssertEqual(summary.service.serviceCode, "DXA")
    }

    func testListResultsDecodesNullAndMissingOptionalFields() async throws {
        stubJSON(BodySpecAPIFixture.resultsNullOptionalsJSON)

        let response = try await makeAPI(authToken: accessToken).listResults()

        let summary = try XCTUnwrap(response.results.first)
        XCTAssertEqual(summary.resultId, "result-9")
        XCTAssertEqual(summary.startTime, Date(timeIntervalSince1970: 1_730_531_744))
        XCTAssertEqual(summary.location.locationId, "loc-2")
        XCTAssertNil(summary.location.name)
        XCTAssertEqual(summary.service.name, "DEXA Scan")
        XCTAssertNil(summary.service.serviceId)
        XCTAssertNil(summary.service.serviceCode)
    }

    func testListResultsDecodesEmptyResults() async throws {
        stubJSON(BodySpecAPIFixture.emptyResultsJSON)

        let response = try await makeAPI(authToken: accessToken).listResults()

        XCTAssertTrue(response.results.isEmpty)
    }

    func testGetDexaScanInfoDecodesResponse() async throws {
        stubJSON(BodySpecAPIFixture.scanInfoJSON)

        let scanInfo = try await makeAPI(authToken: accessToken).getDexaScanInfo(resultId: "result-123")

        XCTAssertEqual(scanInfo.resultId, "result-123")
        XCTAssertEqual(scanInfo.scannerModel, "Hologic Horizon W")
        XCTAssertEqual(scanInfo.acquireTime, Date(timeIntervalSince1970: 1_736_937_000))
        XCTAssertEqual(scanInfo.analyzeTime, Date(timeIntervalSince1970: 1_736_937_072))
    }

    func testGetDexaCompositionDecodesResponse() async throws {
        stubJSON(BodySpecAPIFixture.compositionJSON)

        let composition = try await makeAPI(authToken: accessToken).getDexaComposition(resultId: "result-123")

        XCTAssertEqual(composition.resultId, "result-123")
        XCTAssertEqual(composition.total.fatMassKg, 14.02, accuracy: 0.0001)
        XCTAssertEqual(composition.total.leanMassKg, 61.85, accuracy: 0.0001)
        XCTAssertEqual(composition.total.boneMassKg, 3.11, accuracy: 0.0001)
        XCTAssertEqual(composition.total.totalMassKg, 78.98, accuracy: 0.0001)
        XCTAssertEqual(composition.total.tissueFatPct, 18.4, accuracy: 0.0001)
        XCTAssertEqual(composition.total.regionFatPct, 17.7, accuracy: 0.0001)
    }

    // MARK: - Error mapping

    func testMissingTokenThrowsNotConnectedWithoutNetworkCall() async {
        await expectAPIError(.notConnected) {
            try await self.makeAPI(authToken: nil).getUser()
        }
        XCTAssertTrue(BodySpecStubURLProtocol.recordedRequests.isEmpty)
    }

    func testNonSuccessStatusCodesThrowHTTPErrorWithStatusCode() async {
        for statusCode in [401, 403, 404, 500] {
            stubJSON(BodySpecAPIFixture.emptyResultsJSON, statusCode: statusCode)
            await expectAPIError(.httpError(statusCode)) {
                try await self.makeAPI(authToken: self.accessToken).listResults()
            }
        }
    }

    func testNonHTTPResponseThrowsInvalidResponse() async {
        BodySpecStubURLProtocol.stub = .nonHTTPResponse

        await expectAPIError(.invalidResponse) {
            try await self.makeAPI(authToken: self.accessToken).getUser()
        }
    }

    func testMalformedJSONThrowsDecodingError() async {
        stubJSON("not-json")

        let error = await captureError {
            try await self.makeAPI(authToken: self.accessToken).getUser()
        }

        XCTAssertTrue(
            error is DecodingError,
            "Expected DecodingError, got \(String(describing: error))"
        )
    }

    func testNetworkFailurePropagatesURLError() async {
        BodySpecStubURLProtocol.stub = .networkError(.notConnectedToInternet)

        let error = await captureError {
            try await self.makeAPI(authToken: self.accessToken).getUser()
        }

        guard let urlError = error as? URLError else {
            XCTFail("Expected URLError, got \(String(describing: error))")
            return
        }
        XCTAssertEqual(urlError.code, .notConnectedToInternet)
    }

    // MARK: - Helpers

    private func makeAPI(authToken: String?) -> BodySpecAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BodySpecStubURLProtocol.self]
        return BodySpecAPI(
            baseURL: baseURL,
            urlSession: URLSession(configuration: configuration),
            authManager: StubBodySpecAuthProvider(token: authToken)
        )
    }

    private func stubJSON(_ json: String, statusCode: Int = 200) {
        BodySpecStubURLProtocol.stub = .http(statusCode: statusCode, body: Data(json.utf8))
    }

    private func recordedRequest(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URLRequest {
        XCTAssertEqual(BodySpecStubURLProtocol.recordedRequests.count, 1, file: file, line: line)
        return try XCTUnwrap(BodySpecStubURLProtocol.recordedRequests.first, file: file, line: line)
    }

    private func queryItems(
        of request: URLRequest,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [URLQueryItem] {
        let url = try XCTUnwrap(request.url, file: file, line: line)
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false),
            file: file,
            line: line
        )
        return components.queryItems ?? []
    }

    private func expectAPIError<T>(
        _ expected: BodySpecAPIError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected) but the request succeeded", file: file, line: line)
        } catch let error as BodySpecAPIError {
            switch (error, expected) {
            case (.notConnected, .notConnected), (.invalidResponse, .invalidResponse):
                break
            case (.httpError(let actualCode), .httpError(let expectedCode)):
                XCTAssertEqual(actualCode, expectedCode, file: file, line: line)
            default:
                XCTFail("Expected \(expected), got \(error)", file: file, line: line)
            }
        } catch {
            XCTFail("Expected \(expected), got \(error)", file: file, line: line)
        }
    }

    private func captureError<T>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> T
    ) async -> Error? {
        do {
            _ = try await operation()
            XCTFail("Expected the request to throw", file: file, line: line)
            return nil
        } catch {
            return error
        }
    }
}
