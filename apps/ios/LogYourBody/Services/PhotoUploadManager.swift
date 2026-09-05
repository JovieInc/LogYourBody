//
// PhotoUploadManager.swift
// LogYourBody
//
import UIKit
import PhotosUI
import Combine

@MainActor
class PhotoUploadManager: ObservableObject {
    static let shared = PhotoUploadManager()

    @Published var isUploading = false
    @Published var uploadProgress: Double = 0.0
    @Published var uploadError: String?
    @Published var currentUploadTask: UploadTask?

    private let authManager = AuthManager.shared
    private let productAPIClient = ProductAPIClient.shared
    private let coreDataManager = CoreDataManager.shared
    private let accessTokenProvider: () async -> String?
    private let apiBaseURL: String
    private let storageSessionProvider: () -> URLSession
    private let functionSessionProvider: () -> URLSession
    private var uploadCancellables = Set<AnyCancellable>()

    struct UploadTask {
        let id: String
        let metricsId: String
        let status: UploadStatus
        let progress: Double
        let error: String?
    }

    enum UploadStatus {
        case preparing
        case uploading
        case processing
        case completed
        case failed
    }

    enum PhotoError: LocalizedError {
        case notAuthenticated
        case imageConversionFailed
        case uploadFailed(String)
        case processingFailed(String)
        case networkError

        var errorDescription: String? {
            switch self {
            case .notAuthenticated:
                return "Please log in to upload photos"
            case .imageConversionFailed:
                return "Failed to process the image"
            case .uploadFailed(let message):
                return message
            case .processingFailed(let message):
                return message
            case .networkError:
                return "Network connection error. Check your connection and try again."
            }
        }
    }

    private init() {
        accessTokenProvider = { await AuthManager.shared.getAccessToken() }
        apiBaseURL = Configuration.apiBaseURL
        storageSessionProvider = {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 60.0 // 60 seconds
            configuration.timeoutIntervalForResource = 120.0 // 2 minutes
            return URLSession(configuration: configuration)
        }
        functionSessionProvider = { .shared }
    }

    /// Test seam: injects the first-party token provider, API base URL, and URL
    /// sessions so the upload pipeline can be exercised without a live auth
    /// session. URLSession only honors custom URLProtocols via
    /// configuration.protocolClasses, so stubbing the network boundary
    /// requires session injection. Production code uses `.shared`, which
    /// wires `AuthManager`, `Configuration.apiBaseURL`, and the production
    /// sessions.
    init(
        accessTokenProvider: @escaping () async -> String?,
        apiBaseURL: String,
        storageSession: URLSession,
        functionSession: URLSession
    ) {
        self.accessTokenProvider = accessTokenProvider
        self.apiBaseURL = apiBaseURL
        storageSessionProvider = { storageSession }
        functionSessionProvider = { functionSession }
    }

    private func mapUploadEndpointError(_ error: Error, action: String) -> PhotoError {
        if error is ProductAPIError {
            return .uploadFailed("\(action) is temporarily unavailable. Please try again.")
        }

        if let networkError = mapNetworkError(error) {
            return networkError
        }

        return .uploadFailed("\(action) failed. Please try again.")
    }

    private func mapNetworkError(_ error: Error) -> PhotoError? {
        if let urlError = error as? URLError {
            return networkPhotoError(for: urlError.code)
        }

        let nsError = error as NSError
        if let urlError = nsError.userInfo[NSUnderlyingErrorKey] as? URLError {
            return networkPhotoError(for: urlError.code)
        }

        return nil
    }

    private func networkPhotoError(for code: URLError.Code) -> PhotoError? {
        switch code {
        case .cannotFindHost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .internationalRoamingOff,
             .dataNotAllowed:
            return .networkError
        default:
            return nil
        }
    }

    private func authenticatedJWT() async throws -> String {
        guard let token = await accessTokenProvider() else {
            throw PhotoError.notAuthenticated
        }

        return token
    }

    // MARK: - Public Methods

    func uploadProgressPhoto(for metrics: BodyMetrics, image: UIImage) async throws -> String {
        guard let userId = authManager.currentUser?.id else {
            throw PhotoError.notAuthenticated
        }

        ErrorTrackingService.shared.addBreadcrumb(
            message: "Starting photo upload",
            category: "photos",
            data: [
                "operation": "uploadProgressPhoto",
                "metricsId": metrics.id,
                "userId": userId
            ]
        )

        return try await performProgressPhotoUpload(
            metricsId: metrics.id,
            userId: userId,
            operation: "uploadProgressPhoto"
        ) {
            guard let imageData = self.prepareImageForUpload(image) else {
                throw PhotoError.imageConversionFailed
            }
            return imageData
        }
    }

    // Support for HEIC/HEIF format conversion
    func uploadProgressPhoto(for metrics: BodyMetrics, imageData: Data) async throws -> String {
        guard let userId = authManager.currentUser?.id else {
            throw PhotoError.notAuthenticated
        }

        ErrorTrackingService.shared.addBreadcrumb(
            message: "Starting photo upload (data)",
            category: "photos",
            data: [
                "operation": "uploadProgressPhotoData",
                "metricsId": metrics.id,
                "userId": userId
            ]
        )

        return try await performProgressPhotoUpload(
            metricsId: metrics.id,
            userId: userId,
            operation: "uploadProgressPhotoData"
        ) {
            try self.jpegDataForUpload(from: imageData)
        }
    }

    // MARK: - Private Methods

    private func performProgressPhotoUpload(
        metricsId: String,
        userId: String,
        operation: String,
        prepare: () throws -> Data
    ) async throws -> String {
        self.isUploading = true
        self.uploadProgress = 0.0
        self.uploadError = nil

        let uploadId = UUID().uuidString
        self.currentUploadTask = UploadTask(
            id: uploadId,
            metricsId: metricsId,
            status: .preparing,
            progress: 0.0,
            error: nil
        )

        defer {
            self.isUploading = false
            self.currentUploadTask = nil
        }

        do {
            updateUploadStatus(.preparing, progress: 0.1)
            let imageData = try prepare()

            updateUploadStatus(.uploading, progress: 0.25)
            let ticket = try await requestRemotePhotoStore(
                metricsId: metricsId,
                contentType: "image/jpeg",
                byteSize: imageData.count
            )

            updateUploadStatus(.uploading, progress: 0.45)
            try await putPhotoObject(ticket: ticket, imageData: imageData)

            let storagePath = ticket.storagePath
            await coreDataManager.markPhotoUploadStorageCommitted(
                id: metricsId,
                userId: userId,
                storagePath: storagePath
            )

            updateUploadStatus(.processing, progress: 0.8)
            try await updateMetricsWithPhoto(
                metricsId: metricsId,
                storagePath: storagePath,
                processedUrl: ticket.photoUrl
            )

            updateUploadStatus(.completed, progress: 1.0)
            ErrorTrackingService.shared.addBreadcrumb(
                message: "Photo upload completed",
                category: "photos",
                data: [
                    "operation": operation,
                    "metricsId": metricsId
                ]
            )
            return ticket.photoUrl
        } catch {
            self.uploadError = error.localizedDescription
            let appError: AppError
            if let photoError = error as? PhotoError {
                appError = AppError.photo(photoError)
            } else {
                appError = AppError.unexpected(
                    context: operation,
                    underlying: error
                )
            }
            let context = ErrorContext(
                feature: "photos",
                operation: operation,
                screen: nil,
                userId: userId
            )
            ErrorReporter.shared.capture(appError, context: context)

            ErrorTrackingService.shared.addBreadcrumb(
                message: "Photo upload failed: \(error.localizedDescription)",
                category: "photos",
                level: .error,
                data: [
                    "operation": operation,
                    "metricsId": metricsId
                ]
            )
            self.currentUploadTask = UploadTask(
                id: uploadId,
                metricsId: metricsId,
                status: .failed,
                progress: self.uploadProgress,
                error: error.localizedDescription
            )
            throw error
        }
    }

    private func prepareImageForUpload(_ image: UIImage) -> Data? {
        // For regular uploads, we'll use the simple orientation fix
        // Vision-based correction is used for progress photos after background removal
        let orientedImage = image.fixedOrientation()

        // Resize image if needed to max 2048px on longest side
        let maxDimension: CGFloat = 2_048
        let size = orientedImage.size

        var targetSize = size
        if size.width > maxDimension || size.height > maxDimension {
            let scale = min(maxDimension / size.width, maxDimension / size.height)
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        }

        // Use newer rendering API that supports wide color gamut
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        // Support wide color gamut for newer iPhones
        if #available(iOS 12.0, *) {
            format.preferredRange = .extended
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { _ in
            orientedImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        // Convert to JPEG with 85% quality
        return resizedImage.jpegData(compressionQuality: 0.85)
    }

    private func jpegDataForUpload(from imageData: Data) throws -> Data {
        if let image = UIImage(data: imageData),
           let jpegData = prepareImageForUpload(image) {
            return jpegData
        }
        throw PhotoError.imageConversionFailed
    }

    private func requestRemotePhotoStore(
        metricsId: String,
        contentType: String,
        byteSize: Int
    ) async throws -> RemotePhotoUploadTicket {
        let token = try await authenticatedJWT()
        let base = apiBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/auth/mobile/photos") else {
            throw PhotoError.uploadFailed("Photo upload is temporarily unavailable. Please try again.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "metricsId": metricsId,
            "contentType": contentType,
            "byteSize": byteSize
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await functionSessionProvider().data(for: request)
        } catch {
            throw mapUploadEndpointError(error, action: "Photo upload")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoError.uploadFailed("Photo upload failed. Please try again.")
        }

        if httpResponse.statusCode == 401 {
            throw PhotoError.notAuthenticated
        }

        if httpResponse.statusCode == 503 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String,
               !message.isEmpty {
                throw PhotoError.uploadFailed(message)
            }
            throw PhotoError.uploadFailed(
                "Progress photo cloud storage is not available. Photos stay on this device."
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PhotoError.uploadFailed(errorMessage)
        }

        return try RemotePhotoUploadTicket.parse(data)
    }

    private func putPhotoObject(ticket: RemotePhotoUploadTicket, imageData: Data) async throws {
        try assertAllowedUploadURL(ticket.uploadURL)

        var request = URLRequest(url: ticket.uploadURL)
        request.httpMethod = ticket.uploadMethod
        request.httpBody = imageData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        for (header, value) in ticket.uploadHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await storageSessionProvider().data(for: request)
        } catch {
            throw mapUploadEndpointError(error, action: "Photo upload")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PhotoError.uploadFailed("Photo upload failed. Please try again.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PhotoError.uploadFailed(errorMessage)
        }
    }

    private func assertAllowedUploadURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            throw PhotoError.uploadFailed("Photo upload is temporarily unavailable. Please try again.")
        }

        let apiHost = URL(string: apiBaseURL)?.host?.lowercased()
        let isCloudflareR2 = host == "r2.cloudflarestorage.com" ||
            host.hasSuffix(".r2.cloudflarestorage.com")
        let isFirstPartyAPIHost = apiHost.map { host == $0 } ?? false
        guard isCloudflareR2 || isFirstPartyAPIHost else {
            throw PhotoError.uploadFailed("Photo upload is temporarily unavailable. Please try again.")
        }
    }

    private func updateMetricsWithPhoto(
        metricsId: String,
        storagePath: String,
        processedUrl: String
    ) async throws {
        guard let userId = authManager.currentUser?.id else {
            throw PhotoError.notAuthenticated
        }

        let didUpdate = try await coreDataManager.updateBodyMetricPhoto(
            id: metricsId,
            userId: userId,
            storagePath: storagePath,
            processedUrl: processedUrl
        )

        guard didUpdate else {
            throw PhotoError.processingFailed("Could not save photo locally")
        }

        RealtimeSyncManager.shared.syncIfNeeded()
    }

    private func updateUploadStatus(_ status: UploadStatus, progress: Double) {
        self.uploadProgress = progress
        if let task = self.currentUploadTask {
            self.currentUploadTask = UploadTask(
                id: task.id,
                metricsId: task.metricsId,
                status: status,
                progress: progress,
                error: nil
            )
        }
    }
}

private struct RemotePhotoUploadTicket {
    let uploadURL: URL
    let uploadMethod: String
    let uploadHeaders: [String: String]
    let objectKey: String
    let photoUrl: String
    let storagePath: String

    static func parse(_ data: Data) throws -> RemotePhotoUploadTicket {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PhotoUploadManager.PhotoError.uploadFailed("Photo upload failed. Please try again.")
        }

        let uploadURLString = json["uploadUrl"] as? String
        let photoUrl = json["photoUrl"] as? String
        let objectKey = json["objectKey"] as? String
        let method = (json["uploadMethod"] as? String)?.uppercased() ?? "PUT"
        let headers = json["uploadHeaders"] as? [String: String] ?? [:]
        let storagePath = (json["storagePath"] as? String) ?? objectKey

        guard method == "PUT",
              let uploadURLString,
              let uploadURL = URL(string: uploadURLString),
              let photoUrl,
              !photoUrl.isEmpty,
              let objectKey,
              !objectKey.isEmpty,
              let storagePath,
              !storagePath.isEmpty else {
            throw PhotoUploadManager.PhotoError.uploadFailed("Photo upload failed. Please try again.")
        }

        return RemotePhotoUploadTicket(
            uploadURL: uploadURL,
            uploadMethod: method,
            uploadHeaders: headers,
            objectKey: objectKey,
            photoUrl: photoUrl,
            storagePath: storagePath
        )
    }
}

// MARK: - UIImage Extension for Orientation Fix
extension UIImage {
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }

        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}
