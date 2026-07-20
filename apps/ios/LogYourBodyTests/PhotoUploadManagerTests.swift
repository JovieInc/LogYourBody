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

    // MARK: - Vision processing stage (real Vision, synthetic image)

    func testImageUploadFailsBeforeNetworkWhenVisionRejectsSyntheticImage() async throws {
        // Real Vision on a synthetic person-less image never reaches the network:
        // the stage throws (no human detected, or Vision unavailable on this
        // platform) and the raw processing error is surfaced verbatim.
        let userId = "photo_vision_user_\(UUID().uuidString)"
        authenticate(userId: userId)
        let manager = makeManager(token: "stub-jwt")
        let metrics = makeMetrics(id: UUID().uuidString, userId: userId)
        PhotoUploadStubURLProtocol.install { _ in .http(200, body: Data()) }

        var thrownError: Error?
        do {
            _ = try await manager.uploadProgressPhoto(for: metrics, image: makeSolidImage())
            XCTFail("Expected the Vision stage to reject a person-less image")
        } catch {
            thrownError = error
        }

        let error = try XCTUnwrap(thrownError)
        XCTAssertFalse(error is PhotoUploadManager.PhotoError, "Processing errors surface raw, not as PhotoError")
        XCTAssertEqual(manager.uploadError, error.localizedDescription)
        XCTAssertFalse(manager.isUploading)
        XCTAssertNil(manager.currentUploadTask)
        XCTAssertTrue(PhotoUploadStubURLProtocol.requests.isEmpty)
    }

    // MARK: - Successful upload

    func testSuccessfulUploadStoresPhotoAndTriggersProcessing() async throws {
        let userId = "photo_upload_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let metrics = try await seedPhotoPlaceholder(id: metricId, userId: userId)
        authenticate(userId: userId)

        let processedURL = "https://cdn.example.com/processed.png"
        PhotoUploadStubURLProtocol.install { request in
            if request.url?.path.contains("/storage/v1/") == true {
                return .http(200, body: Data("{}".utf8))
            }
            return .http(200, body: Data(#"{"processedUrl": "\#(processedURL)"}"#.utf8))
        }

        let manager = makeManager(token: "stub-jwt")
        let pngData = try makePNGData()
        let returnedURL = try await manager.uploadProgressPhoto(for: metrics, imageData: pngData)

        XCTAssertEqual(returnedURL, processedURL)
        XCTAssertFalse(manager.isUploading)
        XCTAssertNil(manager.uploadError)
        XCTAssertNil(manager.currentUploadTask)
        XCTAssertEqual(manager.uploadProgress, 1.0)

        // Storage upload request construction (bucket/path/auth headers/body)
        let requests = PhotoUploadStubURLProtocol.requests
        XCTAssertEqual(requests.count, 2)
        let storageRequest = try XCTUnwrap(requests.first)
        XCTAssertEqual(storageRequest.httpMethod, "POST")
        XCTAssertEqual(storageRequest.url?.host, PhotoUploadStubURLProtocol.stubHost)
        let storagePath = try XCTUnwrap(
            storageRequest.url?.path.replacingOccurrences(of: "/storage/v1/object/photos/", with: "")
        )
        XCTAssertTrue(storagePath.hasPrefix("\(userId)/\(metricId)_"))
        XCTAssertTrue(storagePath.hasSuffix(".jpg"))
        XCTAssertEqual(storageRequest.value(forHTTPHeaderField: "apikey"), Constants.supabaseAnonKey)
        XCTAssertEqual(storageRequest.value(forHTTPHeaderField: "Authorization"), "Bearer stub-jwt")
        XCTAssertEqual(storageRequest.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(PhotoUploadStubURLProtocol.bodyData(of: storageRequest), pngData)

        // Processing trigger fires after the upload with the stored path
        let functionRequest = try XCTUnwrap(requests.last)
        XCTAssertEqual(functionRequest.httpMethod, "POST")
        XCTAssertEqual(functionRequest.url?.path, "/functions/v1/process-progress-photo")
        XCTAssertEqual(functionRequest.value(forHTTPHeaderField: "apikey"), Constants.supabaseAnonKey)
        XCTAssertEqual(functionRequest.value(forHTTPHeaderField: "Authorization"), "Bearer stub-jwt")
        XCTAssertEqual(functionRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let functionBody = try XCTUnwrap(PhotoUploadStubURLProtocol.bodyData(of: functionRequest))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: functionBody) as? [String: Any])
        XCTAssertEqual(json["storagePath"] as? String, storagePath)
        XCTAssertEqual(json["metricsId"] as? String, metricId)

        // Local Core Data record updated with both URLs and marked for sync
        let cached = try await cachedPhotoState(metricId: metricId)
        XCTAssertEqual(cached.photoUrl, processedURL)
        XCTAssertEqual(cached.originalPhotoUrl, storagePath)
        XCTAssertEqual(cached.syncStatus, "pending")
        XCTAssertFalse(cached.isSynced)
    }

    func testHEICInputIsConvertedToJPEGBeforeUpload() async throws {
        let userId = "photo_heic_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let metrics = try await seedPhotoPlaceholder(id: metricId, userId: userId)
        authenticate(userId: userId)

        let processedURL = "https://cdn.example.com/heic-processed.png"
        PhotoUploadStubURLProtocol.install { request in
            if request.url?.path.contains("/storage/v1/") == true {
                return .http(200, body: Data("{}".utf8))
            }
            return .http(200, body: Data(#"{"processedUrl": "\#(processedURL)"}"#.utf8))
        }

        let manager = makeManager(token: "stub-jwt")
        let heicData = try makeHEICData()
        let returnedURL = try await manager.uploadProgressPhoto(for: metrics, imageData: heicData)

        XCTAssertEqual(returnedURL, processedURL)
        let storageRequest = try XCTUnwrap(PhotoUploadStubURLProtocol.requests.first)
        XCTAssertTrue(storageRequest.url?.path.hasSuffix(".jpg") ?? false)
        let body = try XCTUnwrap(PhotoUploadStubURLProtocol.bodyData(of: storageRequest))
        XCTAssertTrue(body.starts(with: [0xFF, 0xD8, 0xFF]), "Expected JPEG payload after HEIC conversion")
    }

    // MARK: - Failure paths

    func testStorageHTTPErrorSurfacesServerMessageAndSkipsProcessing() async throws {
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

        XCTAssertEqual(manager.uploadError, "row level security violated")
        XCTAssertFalse(manager.isUploading)
        XCTAssertNil(manager.currentUploadTask)

        // Only the storage request was attempted; processing was never triggered
        XCTAssertEqual(PhotoUploadStubURLProtocol.requests.count, 1)
        XCTAssertTrue(PhotoUploadStubURLProtocol.requests.first?.url?.path.contains("/storage/v1/") ?? false)

        // The local record was not marked storage-committed
        let cached = try await cachedPhotoState(metricId: metricId)
        XCTAssertNil(cached.originalPhotoUrl)
        XCTAssertNil(cached.photoUrl)
    }

    func testStorageNetworkErrorMapsToDocumentedNetworkMessage() async throws {
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

    func testProcessingHTTPErrorSurfacesServerMessageAfterStorageCommit() async throws {
        let userId = "photo_processing_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let metrics = try await seedPhotoPlaceholder(id: metricId, userId: userId)
        authenticate(userId: userId)

        PhotoUploadStubURLProtocol.install { request in
            if request.url?.path.contains("/storage/v1/") == true {
                return .http(200, body: Data("{}".utf8))
            }
            return .http(500, body: Data("edge function exploded".utf8))
        }

        let manager = makeManager(token: "stub-jwt")
        await assertThrowsPhotoError(.processingFailed("edge function exploded")) {
            _ = try await manager.uploadProgressPhoto(for: metrics, imageData: try makePNGData())
        }

        XCTAssertEqual(manager.uploadError, "edge function exploded")
        XCTAssertFalse(manager.isUploading)
        XCTAssertNil(manager.currentUploadTask)

        // The storage commit survives the processing failure (retry-safe state)
        let storagePath = try XCTUnwrap(
            PhotoUploadStubURLProtocol.requests.first?.url?.path
                .replacingOccurrences(of: "/storage/v1/object/photos/", with: "")
        )
        let cached = try await cachedPhotoState(metricId: metricId)
        XCTAssertEqual(cached.originalPhotoUrl, storagePath)
        XCTAssertEqual(cached.syncStatus, CoreDataManager.photoUploadStorageCommittedSyncStatus)
        XCTAssertNil(cached.photoUrl)
    }

    func testProcessingResponseWithoutURLSurfacesFormatError() async throws {
        let userId = "photo_format_user_\(UUID().uuidString)"
        let metricId = UUID().uuidString
        let metrics = try await seedPhotoPlaceholder(id: metricId, userId: userId)
        authenticate(userId: userId)

        PhotoUploadStubURLProtocol.install { request in
            if request.url?.path.contains("/storage/v1/") == true {
                return .http(200, body: Data("{}".utf8))
            }
            return .http(200, body: Data(#"{"unexpected": true}"#.utf8))
        }

        let manager = makeManager(token: "stub-jwt")
        await assertThrowsPhotoError(.processingFailed("Invalid response format")) {
            _ = try await manager.uploadProgressPhoto(for: metrics, imageData: try makePNGData())
        }

        XCTAssertEqual(manager.uploadError, "Invalid response format")
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
            supabaseTokenProvider: { token },
            supabaseBaseURL: "https://\(PhotoUploadStubURLProtocol.stubHost)",
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

    private func makeHEICData() throws -> Data {
        let cgImage = try XCTUnwrap(makeSolidImage().cgImage)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.heic" as CFString, 1, nil) else {
            throw PhotoUploadTestError.heicEncodingUnavailable
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoUploadTestError.heicEncodingUnavailable
        }
        return data as Data
    }

    private enum PhotoUploadTestError: Error {
        case missingMetric
        case heicEncodingUnavailable
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
            let count = stream.read(buffer, maxLength: 1_024)
            guard count > 0 else { break }
            data.append(buffer, count: count)
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
