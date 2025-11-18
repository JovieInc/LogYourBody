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

    @Published var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var scannedPhotos: [ScannedPhoto] = []
    @Published var photoGroups: [PhotoGroup] = []

    private let imageManager = PHCachingImageManager()
    private var scanTask: Task<Void, Never>?

    private init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    func checkAuthorizationStatus() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            self.authorizationStatus = status
        }
        return status == .authorized || status == .limited
    }

    // MARK: - Scanning

    func scanPhotoLibrary(with criteria: PhotoScanCriteria = .default) async {
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
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

    private func analyzePhotos(_ assets: [PHAsset], criteria: PhotoScanCriteria) async -> [ScannedPhoto] {
        var analyzed: [ScannedPhoto] = []
        let totalCount = assets.count

        // Process in batches to avoid memory issues
        let batchSize = 20
        for (index, asset) in assets.enumerated() {
            if Task.isCancelled { break }

            // Update progress
            await MainActor.run {
                self.scanProgress = Double(index) / Double(totalCount)
            }

            // Get metadata
            let metadata = extractMetadata(from: asset)

            // Skip if doesn't meet basic criteria
            if criteria.excludeScreenshots && metadata.isScreenshot { continue }
            if criteria.excludeEdited && metadata.hasBeenEdited { continue }
            let minSize = criteria.minimumResolution
            if asset.pixelWidth < Int(minSize.width) || asset.pixelHeight < Int(minSize.height) {
                continue
            }

            // Skip landscape photos if preferred
            if criteria.excludeLandscape && criteria.preferPortraitOrientation {
                let isLandscape = asset.pixelWidth > asset.pixelHeight
                if isLandscape { continue }
            }

            // Analyze image content
            if let confidence = await analyzeImageContent(asset: asset) {
                if confidence >= criteria.minimumConfidence {
                    let scannedPhoto = ScannedPhoto(
                        asset: asset,
                        date: asset.creationDate ?? Date(),
                        confidence: confidence,
                        metadata: metadata
                    )
                    analyzed.append(scannedPhoto)
                }
            }

            // Yield to prevent blocking
            if index.isMultiple(of: batchSize) {
                await Task.yield()
            }
        }

        return analyzed
    }

    private func extractMetadata(from asset: PHAsset) -> ScannedPhoto.PhotoMetadata {
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

                // For now, return a mock confidence based on heuristics
                // TODO: Integrate actual CoreML model for progress photo detection

                // Calculate mock confidence based on typical progress photo characteristics
                var confidence: Float = 0.5

                // Portrait orientation photos get higher score
                if image.size.height > image.size.width {
                    confidence += 0.2
                }

                // Photos taken in the morning or evening (typical workout times) get higher score
                if let creationDate = asset.creationDate {
                    let hour = Calendar.current.component(.hour, from: creationDate)
                    if (6...9).contains(hour) || (17...21).contains(hour) {
                        confidence += 0.1
                    }
                }

                // Indoor photos (no location) often indicate gym or home photos
                if asset.location == nil {
                    confidence += 0.1
                }

                // Add some randomness for demo purposes
                confidence += Float.random(in: -0.1...0.1)
                confidence = max(0.0, min(1.0, confidence))

                continuation.resume(returning: confidence)
            }
        }
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
