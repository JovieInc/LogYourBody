//
// PhotoUploadManagerTests.swift
// LogYourBodyTests
//
import XCTest
import CoreData
import UIKit
@testable import LogYourBody

@MainActor
final class PhotoUploadManagerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try await CoreDataManager.shared.deleteAllDataAndWait()
        AuthManager.shared.currentUser = nil
        PhotoUploadStubURLProtocol.reset()
    }

    override func tearDown() async throws {
        PhotoUploadStubURLProtocol.reset()
        AuthManager.shared.currentUser = nil
        try await CoreDataManager.shared.deleteAllDataAndWait()
        try await super.tearDown()
    }

    // MARK: - Error contract

    func testPhotoErrorDescriptionsMatchDocumentedContract() {
        XCTAssertEqual(
            PhotoUploadManager.PhotoError.notAuthenticated.errorDescription,
            "Please log in to upload photos"
        )
        XCTAssertEqual(
            PhotoUploadManager.PhotoError.imageConversionFailed.errorDescription,
            "Failed to process the image"
        )
        XCTAssertEqual(
            PhotoUploadManager.PhotoError.uploadFailed("server said no").errorDescription,
            "server said no"
        )
        XCTAssertEqual(
            PhotoUploadManager.PhotoError.processingFailed("broken pipe").errorDescription,
            "broken pipe"
        )
        XCTAssertEqual(
            PhotoUploadManager.PhotoError.networkError.errorDescription,
            "Network connection error. Check your connection and try again."
        )
    }

    // MARK: - Authentication guard

    func testImageDataUploadWithoutUserThrowsNotAuthenticatedBeforeAnyWork() async throws {
        let manager = makeManager(token: "stub-jwt")
        let metrics = makeMetrics(id: UUID().uuidString, userId: "anonymous")
        PhotoUploadStubURLProtocol.install { _ in .http(200, body: Data()) }

        await assertThrowsPhotoError(.notAuthenticated) {
            _ = try await manager.uploadProgressPhoto(for: metrics, imageData: try makePNGData())
        }

        XCTAssertFalse(manager.isUploading)
        XCTAssertNil(manager.uploadError)
        XCTAssertNil(manager.currentUploadTask)
        XCTAssertTrue(PhotoUploadStubURLProtocol.requests.isEmpty)
    }

    func testImageUploadWithoutUserThrowsNotAuthenticatedBeforeVisionProcessing() async throws {
        let manager = makeManager(token: "stub-jwt")
        let metrics = makeMetrics(id: UUID().uuidString, userId: "anonymous")

        await assertThrowsPhotoError(.notAuthenticated) {
            _ = try await manager.uploadProgressPhoto(for: metrics, image: makeSolidImage())
        }

        XCTAssertFalse(manager.isUploading)
        XCTAssertTrue(PhotoUploadStubURLProtocol.requests.isEmpty)
    }

    // MARK: - First-party photo store fail-closed

    func testRemotePhotoStoreUnavailableFailsClosedWithoutProductAPIStorage() async throws {
        let userId = "photo_upload_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let metrics = try await seedPhotoPlaceholder(id: metricId, userId: userId)
        authenticate(userId: userId)

        let stayOnDevice =
            "Progress photo cloud storage is not available. " +
            "Photos stay on this device until Cloudflare R2 is configured on the first-party API."
        PhotoUploadStubURLProtocol.install { _ in
            .http(
                503,
                body: Data(#"{"error":"photo_store_unavailable","message":"\#(stayOnDevice)"}"#.utf8)
            )
        }

        let manager = makeManager(token: "stub-jwt")
        await assertThrowsPhotoError(.uploadFailed(stayOnDevice)) {
            _ = try await manager.uploadProgressPhoto(for: metrics, imageData: try makePNGData())
        }

        XCTAssertEqual(manager.uploadError, stayOnDevice)
        XCTAssertFalse(manager.isUploading)
        XCTAssertNil(manager.currentUploadTask)

        let requests = PhotoUploadStubURLProtocol.requests
        XCTAssertEqual(requests.count, 1)
        let photoRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(photoRequest.httpMethod, "POST")
        XCTAssertEqual(photoRequest.url?.path, "/api/auth/mobile/photos")
        XCTAssertEqual(photoRequest.value(forHTTPHeaderField: "Authorization"), "Bearer stub-jwt")
        XCTAssertNil(photoRequest.value(forHTTPHeaderField: "apikey"))
        XCTAssertFalse(photoRequest.url?.path.contains("/storage/v1/") ?? false)

        let cached = try await cachedPhotoState(metricId: metricId)
        XCTAssertNil(cached.originalPhotoUrl)
        XCTAssertNil(cached.photoUrl)
    }

    func testImageUploadFailsClosedAtPhotoStoreBeforeVision() async throws {
        let userId = "photo_vision_user_\(UUID().uuidString)"
        authenticate(userId: userId)
        let manager = makeManager(token: "stub-jwt")
        let metrics = makeMetrics(id: UUID().uuidString, userId: userId)
        PhotoUploadStubURLProtocol.install { _ in
            .http(503, body: Data(#"{"error":"photo_store_unavailable","message":"stay on this device"}"#.utf8))
        }

        await assertThrowsPhotoError(.uploadFailed("stay on this device")) {
            _ = try await manager.uploadProgressPhoto(for: metrics, image: makeSolidImage())
        }

        XCTAssertEqual(PhotoUploadStubURLProtocol.requests.count, 1)
        XCTAssertEqual(PhotoUploadStubURLProtocol.requests.first?.url?.path, "/api/auth/mobile/photos")
    }

    func testPhotoStoreHTTPErrorSurfacesServerMessage() async throws {
        let userId = "photo_http_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let metrics = try await seedPhotoPlaceholder(id: metricId, userId: userId)
        authenticate(userId: userId)

        PhotoUploadStubURLProtocol.install { _ in
            .http(400, body: Data("row level security violated".utf8))
        }

        let manager = makeManager(token: "stub-jwt")
        await assertThrowsPhotoError(.uploadFailed("row level security violated")) {
            _ = try await manager.uploadProgressPhoto(for: metrics, imageData: try makePNGData())
        }

        XCTAssertEqual(PhotoUploadStubURLProtocol.requests.count, 1)
        XCTAssertEqual(PhotoUploadStubURLProtocol.requests.first?.url?.path, "/api/auth/mobile/photos")

        let cached = try await cachedPhotoState(metricId: metricId)
        XCTAssertNil(cached.originalPhotoUrl)
        XCTAssertNil(cached.photoUrl)
    }

    func testPhotoStoreNetworkErrorMapsToDocumentedNetworkMessage() async throws {
        let userId = "photo_network_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let metrics = try await seedPhotoPlaceholder(id: metricId, userId: userId)
        authenticate(userId: userId)

        PhotoUploadStubURLProtocol.install { _ in .failure(URLError(.notConnectedToInternet)) }

        let manager = makeManager(token: "stub-jwt")
        await assertThrowsPhotoError(.networkError) {
            _ = try await manager.uploadProgressPhoto(for: metrics, imageData: try makePNGData())
        }

        XCTAssertEqual(
            manager.uploadError,
            "Network connection error. Check your connection and try again."
        )
        XCTAssertFalse(manager.isUploading)
    }

    // MARK: - Cloudflare R2 upload

    func testSignedR2PutPersistsPhotoURLWithoutProductAPIStorage() async throws {
        let userId = "photo_r2_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let metrics = try await seedPhotoPlaceholder(id: metricId, userId: userId)
        authenticate(userId: userId)

        let objectKey = "progress-photos/\(userId)/\(metricId)_1755453600000.jpg"
        let photoUrl = "https://photos.logyourbody.com/\(objectKey)"
        let uploadPath = "/r2/\(objectKey)"
        PhotoUploadStubURLProtocol.install { request in
            if request.httpMethod == "POST" {
                let body = PhotoUploadStubURLProtocol.bodyData(of: request).flatMap {
                    try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
                }
                XCTAssertEqual(body?["metricsId"] as? String, metricId)
                XCTAssertEqual(body?["contentType"] as? String, "image/jpeg")
                return .http(200, body: Data("""
                {
                  "uploadUrl": "https://\(PhotoUploadStubURLProtocol.stubHost)\(uploadPath)",
                  "uploadMethod": "PUT",
                  "uploadHeaders": { "Content-Type": "image/jpeg" },
                  "objectKey": "\(objectKey)",
                  "photoUrl": "\(photoUrl)",
                  "storagePath": "\(objectKey)",
                  "expiresIn": 300
                }
                """.utf8))
            }

            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, uploadPath)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
            let uploaded = PhotoUploadStubURLProtocol.bodyData(of: request)
            XCTAssertFalse(uploaded?.isEmpty ?? true)
            return .http(200, body: Data())
        }

        let manager = makeManager(token: "stub-jwt")
        let returned = try await manager.uploadProgressPhoto(
            for: metrics,
            imageData: try makePNGData()
        )

        XCTAssertEqual(returned, photoUrl)
        XCTAssertNil(manager.uploadError)
        XCTAssertFalse(manager.isUploading)

        let requests = PhotoUploadStubURLProtocol.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/api/auth/mobile/photos")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer stub-jwt")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "apikey"))
        XCTAssertEqual(requests[1].httpMethod, "PUT")
        XCTAssertFalse(requests[1].url?.path.contains("/storage/v1/") ?? true)

        let cached = try await cachedPhotoState(metricId: metricId)
        XCTAssertEqual(cached.photoUrl, photoUrl)
        XCTAssertEqual(cached.originalPhotoUrl, objectKey)
        XCTAssertFalse(cached.isSynced)
        XCTAssertEqual(cached.syncStatus, "pending")
    }

    func testSignedPutToUnexpectedHostIsRejectedBeforeUpload() async throws {
        let userId = "photo_host_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let metrics = try await seedPhotoPlaceholder(id: metricId, userId: userId)
        authenticate(userId: userId)

        PhotoUploadStubURLProtocol.install { request in
            XCTAssertEqual(request.httpMethod, "POST")
            return .http(200, body: Data("""
            {
              "uploadUrl": "https://evil.example/steal",
              "uploadMethod": "PUT",
              "uploadHeaders": { "Content-Type": "image/jpeg" },
              "objectKey": "progress-photos/\(userId)/stolen.jpg",
              "photoUrl": "https://evil.example/stolen.jpg",
              "storagePath": "progress-photos/\(userId)/stolen.jpg"
            }
            """.utf8))
        }

        let manager = makeManager(token: "stub-jwt")
        await assertThrowsPhotoError(
            .uploadFailed("Photo upload is temporarily unavailable. Please try again.")
        ) {
            _ = try await manager.uploadProgressPhoto(for: metrics, imageData: try makePNGData())
        }

        XCTAssertEqual(PhotoUploadStubURLProtocol.requests.count, 1)
        let cached = try await cachedPhotoState(metricId: metricId)
        XCTAssertNil(cached.photoUrl)
        XCTAssertNil(cached.originalPhotoUrl)
    }

    // MARK: - Helpers

    private enum PhotoErrorCase {
        case notAuthenticated
        case uploadFailed(String)
        case processingFailed(String)
        case networkError
    }

    private func assertThrowsPhotoError(
        _ expected: PhotoErrorCase,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected PhotoError.\(expected) to be thrown")
        } catch let error as PhotoUploadManager.PhotoError {
            switch (expected, error) {
            case (.notAuthenticated, .notAuthenticated),
                 (.networkError, .networkError):
                break
            case (.uploadFailed(let expectedMessage), .uploadFailed(let actualMessage)),
                 (.processingFailed(let expectedMessage), .processingFailed(let actualMessage)):
                XCTAssertEqual(actualMessage, expectedMessage)
            default:
                XCTFail("Expected PhotoError.\(expected), got \(error)")
            }
        } catch {
            XCTFail("Expected PhotoError.\(expected), got \(error)")
        }
    }

    private func makeManager(token: String?) -> PhotoUploadManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PhotoUploadStubURLProtocol.self]
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration)
        return PhotoUploadManager(
            accessTokenProvider: { token },
            apiBaseURL: "https://\(PhotoUploadStubURLProtocol.stubHost)",
            storageSession: session,
            functionSession: session
        )
    }

    private func authenticate(userId: String) {
        AuthManager.shared.currentUser = LocalUser(
            id: userId,
            email: "photo-upload-tests@example.com",
            name: nil,
            avatarUrl: nil,
            profile: nil
        )
    }

    private func makeMetrics(id: String, userId: String) -> BodyMetrics {
        let date = Date(timeIntervalSince1970: 1_766_000_000)
        return BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            weight: nil,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.photo.rawValue,
            createdAt: date,
            updatedAt: date
        )
    }

    private func seedPhotoPlaceholder(id: String, userId: String) async throws -> BodyMetrics {
        let metrics = makeMetrics(id: id, userId: userId)
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metrics, userId: userId, markAsSynced: false)
        return metrics
    }

    private func cachedPhotoState(metricId: String) async throws -> (
        photoUrl: String?,
        originalPhotoUrl: String?,
        isSynced: Bool,
        syncStatus: String?
    ) {
        let context = CoreDataManager.shared.viewContext

        return try await context.perform {
            let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", metricId)
            request.fetchLimit = 1

            guard let metric = try context.fetch(request).first else {
                throw PhotoUploadTestError.missingMetric
            }

            return (metric.photoUrl, metric.originalPhotoUrl, metric.isSynced, metric.syncStatus)
        }
    }

    private func makeSolidImage(size: CGSize = CGSize(width: 64, height: 64)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makePNGData() throws -> Data {
        try XCTUnwrap(makeSolidImage().pngData())
    }

    private enum PhotoUploadTestError: Error {
        case missingMetric
    }
}

private struct StubbedPhotoResponse {
    let statusCode: Int
    let body: Data
    let error: URLError?

    static func http(_ statusCode: Int, body: Data) -> StubbedPhotoResponse {
        StubbedPhotoResponse(statusCode: statusCode, body: body, error: nil)
    }

    static func failure(_ error: URLError) -> StubbedPhotoResponse {
        StubbedPhotoResponse(statusCode: 0, body: Data(), error: error)
    }
}

private final class PhotoUploadStubURLProtocol: URLProtocol {
    static let stubHost = "photo-upload-tests.example.com"

    private static let lock = NSLock()
    private static var requestHandler: ((URLRequest) -> StubbedPhotoResponse)?
    private static var recordedRequests: [URLRequest] = []

    static func install(handler: @escaping (URLRequest) -> StubbedPhotoResponse) {
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
            let bytesRead = stream.read(buffer, maxLength: 1_024)
            guard bytesRead > 0 else { break }
            data.append(buffer, count: bytesRead)
        }
        return data.isEmpty ? nil : data
    }

    override static func canInit(with request: URLRequest) -> Bool {
        request.url?.host == stubHost
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
        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

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
