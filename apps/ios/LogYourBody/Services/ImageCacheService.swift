//
// ImageCacheService.swift
// LogYourBody
//
// Centralized image caching service with memory pressure handling
// and request deduplication for optimal performance
//

import SwiftUI
import UIKit

protocol ProgressPhotoImageLoading {
    func loadImage(urlString: String) async throws -> UIImage
}

struct ProgressPhotoImagePipelineLoader: ProgressPhotoImageLoading {
    func loadImage(urlString: String) async throws -> UIImage {
        try await ProgressPhotoImagePipeline.loadImage(urlString: urlString)
    }
}

@MainActor
class ImageCacheService: ObservableObject {
    static let shared = ImageCacheService()

    // MARK: - Cache Storage

    private let cache = NSCache<NSString, UIImage>()
    private var loadingTasks: [String: Task<UIImage?, Never>] = [:]
    private let imageLoader: ProgressPhotoImageLoading
    private let notificationCenter: NotificationCenter

    // MARK: - Configuration

    private let maxCacheSizeMB = 100

    // MARK: - Initialization

    init(
        imageLoader: ProgressPhotoImageLoading = ProgressPhotoImagePipelineLoader(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.imageLoader = imageLoader
        self.notificationCenter = notificationCenter

        // Configure cache limits
        cache.totalCostLimit = maxCacheSizeMB * 1_024 * 1_024
        cache.countLimit = 100

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
        cache.removeAllObjects()
        loadingTasks.removeAll()
    }

    // MARK: - Public API

    /// Return a cached image without starting network or disk work.
    func cachedImage(for urlString: String?) -> UIImage? {
        guard let urlString, !urlString.isEmpty else { return nil }
        return cache.object(forKey: NSString(string: urlString))
    }

    /// Load image from URL with automatic caching and deduplication
    func loadImage(from urlString: String) async -> UIImage? {
        let cacheKey = NSString(string: urlString)

        // Check cache first
        if let cachedImage = cachedImage(for: urlString) {
            return cachedImage
        }

        // Check if already loading
        if let existingTask = loadingTasks[urlString] {
            return await existingTask.value
        }

        // Create new loading task
        let task = Task<UIImage?, Never> {
            await fetchAndCacheImage(from: urlString, cacheKey: cacheKey)
        }

        loadingTasks[urlString] = task

        let image = await task.value

        // Clean up task
        loadingTasks.removeValue(forKey: urlString)

        return image
    }

    /// Preload images in the background with bounded concurrency.
    ///
    /// Adjacent photos decode in parallel — so timeline scrubbing lands on an
    /// already-cached image instead of stalling on a serial decode chain — while
    /// the concurrency cap avoids firing every request at once. `loadImage`'s
    /// per-URL deduplication still prevents redundant work.
    func preloadImages(_ urlStrings: [String]) {
        let urls = urlStrings.filter { !$0.isEmpty }
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
                    group.addTask { _ = await self.loadImage(from: urlString) }
                }
            }
        }
    }

    /// Clear specific image from cache
    func clearImage(_ urlString: String) {
        let cacheKey = NSString(string: urlString)
        cache.removeObject(forKey: cacheKey)
        loadingTasks.removeValue(forKey: urlString)
    }

    /// Clear all cached images
    func clearAll() {
        cache.removeAllObjects()
        loadingTasks.removeAll()
    }

    // MARK: - Private Helpers

    private func fetchAndCacheImage(from urlString: String, cacheKey: NSString) async -> UIImage? {
        guard let optimizedImage = try? await imageLoader.loadImage(urlString: urlString) else {
            return nil
        }

        let cost = ProgressPhotoImagePipeline.cacheCost(for: optimizedImage)
        cache.setObject(optimizedImage, forKey: cacheKey, cost: cost)
        return optimizedImage
    }
}

enum ProgressPhotoImagePipeline {
    enum ImageLoadError: Error {
        case invalidURL
        case invalidResponse
        case decodeFailed
    }

    static func loadImage(urlString: String) async throws -> UIImage {
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

        guard let image = await decodeAndOptimizeImage(from: data) else {
            throw ImageLoadError.decodeFailed
        }

        return image
    }

    static func decodeAndOptimizeImage(from data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                guard let image = UIImage(data: data) else {
                    return nil
                }
                return optimizeImage(image)
            }
        }.value
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
        guard let urlString = urlString, !urlString.isEmpty else {
            loadedImage = nil
            return
        }

        isLoading = true
        loadedImage = await ImageCacheService.shared.loadImage(from: urlString)
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
