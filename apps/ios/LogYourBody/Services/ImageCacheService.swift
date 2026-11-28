//
// ImageCacheService.swift
// LogYourBody
//
// Centralized image caching service with memory pressure handling
// and request deduplication for optimal performance
//

import SwiftUI
import UIKit
import ImageIO

protocol ProgressPhotoImageLoading {
    func loadImage(urlString: String) async throws -> UIImage
    func loadImage(urlString: String, maxPixelSize: Int) async throws -> UIImage
}

struct ProgressPhotoImagePipelineLoader: ProgressPhotoImageLoading {
    func loadImage(urlString: String) async throws -> UIImage {
        try await ProgressPhotoImagePipeline.loadImage(urlString: urlString)
    }

    func loadImage(urlString: String, maxPixelSize: Int) async throws -> UIImage {
        try await ProgressPhotoImagePipeline.loadImage(urlString: urlString, maxPixelSize: maxPixelSize)
    }
}

@MainActor
class ImageCacheService: ObservableObject {
    static let shared = ImageCacheService()

    // MARK: - Cache Storage

    private let cache = NSCache<NSString, UIImage>()
    private var flights: [String: InFlight] = [:]
    private var keysByURL: [String: Set<String>] = [:]
    private var cacheEpoch = 0
    private let imageLoader: ProgressPhotoImageLoading
    private let notificationCenter: NotificationCenter

    // MARK: - Configuration

    /// Count and byte budgets stay fixed. Sized thumbnails share this cache; they do not raise it.
    static let cacheCountLimit = 100
    static let cacheCostLimit = 100 * 1_024 * 1_024
    static let thumbnailMaxPixelSize = 160

    var cacheCountLimitForTests: Int { cache.countLimit }
    var cacheCostLimitForTests: Int { cache.totalCostLimit }

    // MARK: - Initialization

    init(
        imageLoader: ProgressPhotoImageLoading = ProgressPhotoImagePipelineLoader(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.imageLoader = imageLoader
        self.notificationCenter = notificationCenter

        // Configure cache limits
        cache.totalCostLimit = Self.cacheCostLimit
        cache.countLimit = Self.cacheCountLimit

        // Handle memory pressure
        notificationCenter.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    // MARK: - Memory Management

    @objc private func handleMemoryWarning() {
        discardCachedImages()
    }

    // MARK: - Public API

    /// Return a cached image without starting network or disk work.
    func cachedImage(for urlString: String?) -> UIImage? {
        cachedImage(for: urlString, maxPixelSize: nil)
    }

    /// Sized and unsized bitmaps are different cache entries.
    func cachedImage(for urlString: String?, maxPixelSize: Int?) -> UIImage? {
        guard let urlString, !urlString.isEmpty else { return nil }
        let key = Self.cacheKey(for: urlString, maxPixelSize: maxPixelSize)
        return cache.object(forKey: key as NSString)
    }

    /// Load image from URL with automatic caching and deduplication.
    ///
    /// A pixel size requests a CGImageSource thumbnail at that destination size.
    /// Omitting it keeps the full-frame decode for share, compare, and camera.
    func loadImage(from urlString: String, maxPixelSize: Int? = nil) async -> UIImage? {
        guard !urlString.isEmpty, !Task.isCancelled else { return nil }
        let key = Self.cacheKey(for: urlString, maxPixelSize: maxPixelSize)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        let (flight, task) = startOrJoin(key: key, urlString: urlString, maxPixelSize: maxPixelSize)
        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            flight.cancelIfAbandoned()
        }
        // Cancellation is terminal for this caller. A shared decode may still
        // finish for a neighbor that is still waiting, but this slot must not
        // publish the late bitmap.
        guard !Task.isCancelled else { return nil }
        return image
    }

    /// Filmstrip thumbnails are the 160px sized entry, not a second cache namespace.
    func loadThumbnail(from urlString: String) async -> UIImage? {
        await loadImage(from: urlString, maxPixelSize: Self.thumbnailMaxPixelSize)
    }

    /// Preload images in the background with bounded concurrency.
    ///
    /// Adjacent photos decode in parallel — so timeline scrubbing lands on an
    /// already-cached image instead of stalling on a serial decode chain — while
    /// the concurrency cap avoids firing every request at once. In-flight work
    /// deduplicates per URL and pixel size.
    func preloadImages(_ urlStrings: [String], maxPixelSize: Int? = nil) {
        var seen = Set<String>()
        let urls = urlStrings.filter { url in
            guard !url.isEmpty else { return false }
            return seen.insert(Self.cacheKey(for: url, maxPixelSize: maxPixelSize)).inserted
        }
        guard !urls.isEmpty else { return }

        Task {
            let maxConcurrent = min(4, urls.count)
            await withTaskGroup(of: Void.self) { group in
                for (offset, urlString) in urls.enumerated() {
                    // Keep at most `maxConcurrent` decodes in flight: once the
                    // window is full, wait for one to finish before starting the next.
                    if offset >= maxConcurrent {
                        await group.next()
                    }
                    if Task.isCancelled { break }
                    group.addTask {
                        _ = await self.loadImage(from: urlString, maxPixelSize: maxPixelSize)
                    }
                }
            }
        }
    }

    /// Clear specific image from cache, including every sized variant.
    func clearImage(_ urlString: String) {
        var keys = keysByURL.removeValue(forKey: urlString) ?? []
        keys.insert(urlString)
        keys.insert("thumbnail:\(urlString)")
        keys.insert(Self.cacheKey(for: urlString, maxPixelSize: Self.thumbnailMaxPixelSize))
        for key in keys {
            cache.removeObject(forKey: key as NSString)
            flights[key]?.abandon()
            flights[key] = nil
        }
    }

    /// Clear all cached images
    func clearAll() {
        discardCachedImages()
    }

    // MARK: - Private Helpers

    private func discardCachedImages() {
        cacheEpoch += 1
        cache.removeAllObjects()
        keysByURL.removeAll()
        for flight in flights.values {
            flight.abandon()
        }
        flights.removeAll()
    }

    private func startOrJoin(
        key: String,
        urlString: String,
        maxPixelSize: Int?
    ) -> (InFlight, Task<UIImage?, Never>) {
        if let existing = flights[key], let task = existing.retainIfActive() {
            return (existing, task)
        }

        let flight = InFlight()
        let epoch = cacheEpoch
        let task = Task<UIImage?, Never> {
            let image = await self.fetchAndCache(
                from: urlString,
                maxPixelSize: maxPixelSize,
                key: key,
                epoch: epoch,
                flight: flight
            )
            flight.markFinished()
            self.removeFlight(key, matching: flight)
            return image
        }
        flight.bind(task)
        flights[key] = flight
        return (flight, task)
    }

    private func removeFlight(_ key: String, matching flight: InFlight) {
        if flights[key] === flight {
            flights[key] = nil
        }
    }

    private func fetchAndCache(
        from urlString: String,
        maxPixelSize: Int?,
        key: String,
        epoch: Int,
        flight: InFlight
    ) async -> UIImage? {
        if Task.isCancelled { return nil }
        let loaded: UIImage?
        do {
            if let maxPixelSize {
                loaded = try await imageLoader.loadImage(urlString: urlString, maxPixelSize: maxPixelSize)
            } else {
                loaded = try await imageLoader.loadImage(urlString: urlString)
            }
        } catch {
            loaded = nil
        }
        guard let loaded, flight.beginPublish(epoch: epoch, currentEpoch: cacheEpoch) else {
            return nil
        }
        cache.setObject(loaded, forKey: key as NSString, cost: ProgressPhotoImagePipeline.cacheCost(for: loaded))
        keysByURL[urlString, default: []].insert(key)
        return loaded
    }

    static func cacheKey(for urlString: String, maxPixelSize: Int?) -> String {
        guard let maxPixelSize else { return urlString }
        return "\(urlString)#px=\(maxPixelSize)"
    }
}

/// One decode shared by every caller of the same URL and pixel size.
/// Cancellation drops a waiter. The decode is cancelled only when nobody is left,
/// and a cancelled decode does not publish into the cache.
private final class InFlight: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters = 1
    private var finished = false
    private var publishing = false
    private var task: Task<UIImage?, Never>?

    func bind(_ task: Task<UIImage?, Never>) {
        lock.lock()
        self.task = task
        lock.unlock()
    }

    /// Join this decode. `nil` when it is already finished or cancelled.
    func retainIfActive() -> Task<UIImage?, Never>? {
        lock.lock()
        defer { lock.unlock() }
        guard let task, !finished, !task.isCancelled, waiters > 0 else { return nil }
        waiters += 1
        return task
    }

    func cancelIfAbandoned() {
        lock.lock()
        waiters -= 1
        let taskToCancel = waiters <= 0 && !publishing ? task : nil
        if waiters <= 0 { finished = true }
        lock.unlock()
        taskToCancel?.cancel()
    }

    func abandon() {
        lock.lock()
        waiters = 0
        finished = true
        let taskToCancel = task
        lock.unlock()
        taskToCancel?.cancel()
    }

    func markFinished() {
        lock.lock()
        finished = true
        lock.unlock()
    }

    /// True only when a caller still wants the bitmap and the cache generation matches.
    func beginPublish(epoch: Int, currentEpoch: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard epoch == currentEpoch, waiters > 0, !finished, !publishing, task?.isCancelled != true else {
            return false
        }
        publishing = true
        return true
    }
}

enum ProgressPhotoImagePipeline {
    enum ImageLoadError: Error {
        case invalidURL
        case invalidResponse
        case decodeFailed
    }

    static func loadImage(urlString: String, maxPixelSize: Int? = nil) async throws -> UIImage {
        guard let url = URL(string: urlString) else {
            throw ImageLoadError.invalidURL
        }

        let data: Data
        if url.isFileURL {
            data = try await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
        } else {
            let (responseData, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw ImageLoadError.invalidResponse
            }
            data = responseData
        }

        guard let image = await decodeAndOptimizeImage(from: data, maxPixelSize: maxPixelSize) else {
            throw ImageLoadError.decodeFailed
        }

        return image
    }

    /// Longest side, in pixels, of a thumbnail that matches a view's point size.
    static func targetMaxPixelSize(points: CGSize, scale: CGFloat) -> Int? {
        guard points.width.isFinite, points.height.isFinite, points.width > 0, points.height > 0 else {
            return nil
        }
        let resolvedScale = (scale.isFinite && scale > 0) ? scale : 1
        let longest = max(points.width, points.height) * resolvedScale
        guard longest.isFinite, longest >= 1 else { return nil }
        return Int(longest.rounded(.up))
    }

    /// Options passed to `CGImageSourceCreateThumbnailAtIndex` for a destination pixel size.
    static func thumbnailSourceOptions(maxPixelSize: Int) -> [CFString: Any] {
        [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
    }

    static func decodeAndOptimizeImage(from data: Data, maxPixelSize: Int? = nil) async -> UIImage? {
        let token = PerfSignpost.begin("timeline_photo_decode")
        defer { PerfSignpost.end(token) }
        return await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                if let maxPixelSize {
                    return thumbnailImage(from: data, maxPixelSize: maxPixelSize)
                }
                guard let image = UIImage(data: data) else {
                    return nil
                }
                return optimizeImage(image)
            }
        }.value
    }

    private static func thumbnailImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailSourceOptions(maxPixelSize: maxPixelSize) as CFDictionary
              ) else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    static func optimizeImage(_ image: UIImage, maxDimension: CGFloat = 1_200.0) -> UIImage {
        let orientedImage = image.fixedOrientation()
        let size = orientedImage.size

        guard size.width > maxDimension || size.height > maxDimension else {
            return orientedImage
        }

        let scale = min(maxDimension / size.width, maxDimension / size.height)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            orientedImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func cacheCost(for image: UIImage) -> Int {
        let scale = max(image.scale, 1)
        return Int(image.size.width * scale * image.size.height * scale * 4)
    }
}

// MARK: - SwiftUI View Component

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let urlString: String?
    var usesThumbnail = false
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = loadedImage {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: urlString) {
            await loadImage()
        }
    }

    private func loadImage() async {
        if usesThumbnail { loadedImage = nil }
        guard let urlString = urlString, !urlString.isEmpty else {
            loadedImage = nil
            return
        }

        isLoading = true
        let image = usesThumbnail
            ? await ImageCacheService.shared.loadThumbnail(from: urlString)
            : await ImageCacheService.shared.loadImage(from: urlString)
        guard !Task.isCancelled else { return }
        loadedImage = image
        isLoading = false
    }
}

// MARK: - Convenience Initializers

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(urlString: String?) {
        self.urlString = urlString
        self.content = { $0 }
        self.placeholder = { Color.gray.opacity(0.2) }
    }
}

extension CachedAsyncImage where Placeholder == Color {
    init(
        urlString: String?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.urlString = urlString
        self.content = content
        self.placeholder = { Color.gray.opacity(0.2) }
    }
}
