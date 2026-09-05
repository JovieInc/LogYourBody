//
// PhotoLibraryScanner.swift
// LogYourBody
//
import Photos
import SwiftUI
import Vision

// MARK: - Photo Scan Result

struct ScannedPhoto: Identifiable {
    let id = UUID()
    let asset: PHAsset
    let date: Date
    let confidence: Float
    let metadata: PhotoMetadata

    struct PhotoMetadata {
        let location: CLLocation?
        let cameraType: CameraType?
        let isScreenshot: Bool
        let hasBeenEdited: Bool
    }

    enum CameraType {
        case front
        case back
        case unknown
    }
}

// MARK: - Photo Group

struct PhotoGroup {
    let date: Date
    let photos: [ScannedPhoto]
    let averageConfidence: Float

    var suggestedPrimary: ScannedPhoto? {
        photos.max(by: { $0.confidence < $1.confidence })
    }
}

// MARK: - Scan Criteria

struct PhotoScanCriteria {
    // Time-based filters
    let dateRange: DateInterval?
    let minimumDaysBetween: Int = 3

    // Technical filters
    let minimumResolution = CGSize(width: 1_000, height: 1_000)
    let preferredCameraType: ScannedPhoto.CameraType? = nil // No preference - mirror selfies use back camera
    let preferPortraitOrientation: Bool = true

    // Content filters
    let minimumConfidence: Float = 0.7
    let excludeScreenshots: Bool = true
    let excludeEdited: Bool = false
    let excludeLandscape: Bool = true // Most progress photos are portrait

    // Default: last 2 years
    static var `default`: PhotoScanCriteria {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .year, value: -2, to: endDate) ?? endDate
        return PhotoScanCriteria(
            dateRange: DateInterval(start: startDate, end: endDate)
        )
    }
}

// MARK: - Photo Library Scanner

class PhotoLibraryScanner: ObservableObject {
    static let shared = PhotoLibraryScanner()

    @Published var authorizationStatus: AppAuthorizationState = .notDetermined
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var scannedPhotos: [ScannedPhoto] = []
    @Published var photoGroups: [PhotoGroup] = []

    private let imageManager: PHImageManager
    private let metadataProvider: ((PHAsset) -> ScannedPhoto.PhotoMetadata)?
    private let metadataScanEnabled: @MainActor () -> Bool
    private let monotonicTime: () -> TimeInterval
    private var scanTask: Task<Void, Never>?

    init(
        imageManager: PHImageManager = PHCachingImageManager(),
        metadataProvider: ((PHAsset) -> ScannedPhoto.PhotoMetadata)? = nil,
        metadataScanEnabled: @escaping @MainActor () -> Bool = {
            AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: "photo_scan_metadata_v1")
        },
        monotonicTime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.imageManager = imageManager
        self.metadataProvider = metadataProvider
        self.metadataScanEnabled = metadataScanEnabled
        self.monotonicTime = monotonicTime
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() {
        authorizationStatus = Self.appAuthorizationState(
            from: PHPhotoLibrary.authorizationStatus(for: .readWrite)
        )
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = Self.appAuthorizationState(from: status)
        }
        return status == .authorized || status == .limited
    }

    // MARK: - Scanning

    func scanPhotoLibrary(with criteria: PhotoScanCriteria = .default) async {
        guard authorizationStatus == .authorized else {
            // print("❌ Photo library access not authorized")
            return
        }

        // Prevent multiple concurrent scans
        guard await MainActor.run(body: { !isScanning }) else {
            // print("⚠️ Scan already in progress")
            return
        }

        await MainActor.run {
            isScanning = true
            scanProgress = 0
            scannedPhotos = []
            photoGroups = []
        }

        scanTask = Task {
            do {
                // Fetch photos matching initial criteria
                let photos = try await fetchPhotos(matching: criteria)

                // Analyze photos for progress photo likelihood
                let analyzed = await analyzePhotos(photos, criteria: criteria)

                // Group photos by date
                let grouped = groupPhotosByDate(analyzed, minimumDaysBetween: criteria.minimumDaysBetween)

                await MainActor.run {
                    self.scannedPhotos = analyzed
                    self.photoGroups = grouped
                    self.isScanning = false
                    self.scanProgress = 1.0
                }
            } catch {
                // print("❌ Error scanning photo library: \(error)")
                await MainActor.run {
                    self.isScanning = false
                    self.scanProgress = 0
                }
            }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanProgress = 0
    }

    static func appAuthorizationState(from status: PHAuthorizationStatus) -> AppAuthorizationState {
        switch status {
        case .authorized, .limited:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    // MARK: - Private Methods

    private func fetchPhotos(matching criteria: PhotoScanCriteria) async throws -> [PHAsset] {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        // Build predicate
        var predicates: [NSPredicate] = [
            NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        ]

        if let dateRange = criteria.dateRange {
            predicates.append(NSPredicate(format: "creationDate >= %@ AND creationDate <= %@",
                                          dateRange.start as NSDate,
                                          dateRange.end as NSDate))
        }

        fetchOptions.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        let results = PHAsset.fetchAssets(with: fetchOptions)
        var assets: [PHAsset] = []

        results.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }

        return assets
    }

    func analyzePhotos(_ assets: [PHAsset], criteria: PhotoScanCriteria) async -> [ScannedPhoto] {
        var analyzed: [ScannedPhoto] = []
        let usesMetadata = await metadataScanEnabled()
        var lastProgressUpdate = monotonicTime()

        for (index, asset) in assets.enumerated() {
            if Task.isCancelled { break }
            let now = monotonicTime()
            if !usesMetadata || now - lastProgressUpdate >= 0.1 {
                lastProgressUpdate = now
                await MainActor.run {
                    self.scanProgress = Double(index) / Double(assets.count)
                }
            }

            let metadata = extractMetadata(from: asset)
            if matchesCriteria(asset, metadata: metadata, criteria: criteria),
               let confidence = await photoConfidence(asset, usesMetadata: usesMetadata),
               confidence >= criteria.minimumConfidence {
                analyzed.append(ScannedPhoto(
                    asset: asset, date: asset.creationDate ?? Date(),
                    confidence: confidence, metadata: metadata
                ))
            }
            // Yield even when every candidate is filtered out.
            if index.isMultiple(of: 20) { await Task.yield() }
        }
        return analyzed
    }

    private func matchesCriteria(
        _ asset: PHAsset, metadata: ScannedPhoto.PhotoMetadata, criteria: PhotoScanCriteria
    ) -> Bool {
        if criteria.excludeScreenshots && metadata.isScreenshot { return false }
        if criteria.excludeEdited && metadata.hasBeenEdited { return false }
        if asset.pixelWidth < Int(criteria.minimumResolution.width) ||
            asset.pixelHeight < Int(criteria.minimumResolution.height) { return false }
        return !(criteria.excludeLandscape && criteria.preferPortraitOrientation &&
                 asset.pixelWidth > asset.pixelHeight)
    }

    private func photoConfidence(_ asset: PHAsset, usesMetadata: Bool) async -> Float? {
        if usesMetadata {
            return Self.heuristicConfidence(
                isPortrait: asset.pixelHeight > asset.pixelWidth,
                creationDate: asset.creationDate, hasLocation: asset.location != nil
            )
        }
        return await analyzeImageContent(asset: asset)
    }

    private func extractMetadata(from asset: PHAsset) -> ScannedPhoto.PhotoMetadata {
        if let metadataProvider { return metadataProvider(asset) }
        // Check if screenshot
        let isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)

        // Check if edited
        let hasBeenEdited = asset.mediaSubtypes.contains(.photoLive) ||
            asset.hasAdjustments

        // Try to determine camera type
        // Note: Most mirror selfies are taken with the back camera
        // We can't reliably detect mirror selfies from metadata alone
        var cameraType: ScannedPhoto.CameraType = .unknown

        // Check EXIF data if available
        let resources = PHAssetResource.assetResources(for: asset)
        for resource in resources {
            if resource.type == .photo {
                // Check filename hints
                let filename = resource.originalFilename.lowercased()
                if filename.contains("selfie") || filename.contains("front") {
                    cameraType = .front
                } else if filename.contains("img_") || filename.contains("photo") {
                    // Generic photo names often indicate back camera
                    cameraType = .back
                }
                break
            }
        }

        return ScannedPhoto.PhotoMetadata(
            location: asset.location,
            cameraType: cameraType,
            isScreenshot: isScreenshot,
            hasBeenEdited: hasBeenEdited
        )
    }

    private func analyzeImageContent(asset: PHAsset) async -> Float? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .fastFormat

        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                guard let image = image else {
                    continuation.resume(returning: nil)
                    return
                }

                let confidence = Self.heuristicConfidence(
                    isPortrait: image.size.height > image.size.width,
                    creationDate: asset.creationDate, hasLocation: asset.location != nil,
                    variation: Float.random(in: -0.1...0.1)
                )
                continuation.resume(returning: confidence)
            }
        }
    }

    /// A metadata ranking heuristic, not an image-content or calibrated probability model.
    private static func heuristicConfidence(
        isPortrait: Bool, creationDate: Date?, hasLocation: Bool, variation: Float = 0
    ) -> Float {
        var confidence: Float = 0.5
        if isPortrait { confidence += 0.2 }
        if let creationDate {
            let hour = Calendar.current.component(.hour, from: creationDate)
            if (6...9).contains(hour) || (17...21).contains(hour) { confidence += 0.1 }
        }
        if !hasLocation { confidence += 0.1 }
        return max(0, min(1, confidence + variation))
    }

    private func groupPhotosByDate(_ photos: [ScannedPhoto], minimumDaysBetween: Int) -> [PhotoGroup] {
        guard !photos.isEmpty else { return [] }

        // Sort by date
        let sorted = photos.sorted { $0.date < $1.date }

        var groups: [PhotoGroup] = []
        var currentGroup: [ScannedPhoto] = []
        var currentGroupDate: Date?

        for photo in sorted {
            if let groupDate = currentGroupDate,
               let daysDiff = Calendar.current.dateComponents([.day], from: groupDate, to: photo.date).day,
               daysDiff < minimumDaysBetween {
                // Add to current group
                currentGroup.append(photo)
            } else {
                // Start new group
                if !currentGroup.isEmpty {
                    let avgConfidence = currentGroup.reduce(0) { $0 + $1.confidence } / Float(currentGroup.count)
                    groups.append(PhotoGroup(
                        date: currentGroupDate ?? Date(),
                        photos: currentGroup,
                        averageConfidence: avgConfidence
                    ))
                }
                currentGroup = [photo]
                currentGroupDate = photo.date
            }
        }

        // Add final group
        if !currentGroup.isEmpty, let groupDate = currentGroupDate {
            let avgConfidence = currentGroup.reduce(0) { $0 + $1.confidence } / Float(currentGroup.count)
            groups.append(PhotoGroup(
                date: groupDate,
                photos: currentGroup,
                averageConfidence: avgConfidence
            ))
        }

        return groups.reversed() // Most recent first
    }

    // MARK: - Image Loading

    func loadThumbnail(for asset: PHAsset, size: CGSize = CGSize(width: 400, height: 400)) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: size,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // Check if this is the final result
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !isDegraded {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    func loadFullImage(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            imageManager.requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
