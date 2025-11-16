//
// ImageCacheService.swift
// LogYourBody
//
// Centralized image caching service with memory pressure handling
// and request deduplication for optimal performance
//

import SwiftUI
import UIKit

@MainActor
class ImageCacheService: ObservableObject {
    static let shared = ImageCacheService()

    // MARK: - Cache Storage

    private let cache = NSCache<NSString, UIImage>()
    private var loadingTasks: [String: Task<UIImage?, Never>] = [:]

    // MARK: - Configuration

    private let maxCacheSizeMB = 100
    private let maxImageDimension: CGFloat = 1200
    private let compressionQuality: CGFloat = 0.8

    // MARK: - Initialization

    private init() {
        // Configure cache limits
        cache.totalCostLimit = maxCacheSizeMB * 1024 * 1024
        cache.countLimit = 100

        // Handle memory pressure
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Memory Management

    @objc private func handleMemoryWarning() {
        cache.removeAllObjects()
        loadingTasks.removeAll()
    }

    // MARK: - Public API

    /// Load image from URL with automatic caching and deduplication
    func loadImage(from urlString: String) async -> UIImage? {
        let cacheKey = NSString(string: urlString)

        // Check cache first
        if let cachedImage = cache.object(forKey: cacheKey) {
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

    /// Preload images in background
    func preloadImages(_ urlStrings: [String]) {
        Task {
            for urlString in urlStrings {
                _ = await loadImage(from: urlString)
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
        guard let url = URL(string: urlString) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            guard let originalImage = UIImage(data: data) else {
                return nil
            }

            // Optimize image size
            let optimizedImage = optimizeImage(originalImage)

            // Calculate memory cost (4 bytes per pixel for RGBA)
            let cost = Int(optimizedImage.size.width * optimizedImage.size.height * 4)

            // Cache with cost
            cache.setObject(optimizedImage, forKey: cacheKey, cost: cost)

            return optimizedImage

        } catch {
        // print("[ImageCacheService] Failed to load image from \(urlString): \(error)")
            return nil
        }
    }

    private func optimizeImage(_ image: UIImage) -> UIImage {
        let size = image.size

        // Check if resize needed
        let maxDimension = max(size.width, size.height)
        if maxDimension <= maxImageDimension {
            return image
        }

        // Calculate new size maintaining aspect ratio
        let scale = maxImageDimension / maxDimension
        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        // Resize using high-quality rendering
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resizedImage = renderer.image { context in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }

        return resizedImage
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
