//
// OptimizedProgressPhotoView.swift
// LogYourBody
//
import SwiftUI
import UIKit

struct OptimizedProgressPhotoView: View {
    let photoUrl: String?
    let maxHeight: CGFloat
    @State private var isLoading = true
    @State private var loadedImage: UIImage?
    @State private var loadError = false
    @State private var loadTask: Task<Void, Never>?

    // Shared image cache
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        // Configure cache limits
        cache.countLimit = 50
        cache.totalCostLimit = 100 * 1_024 * 1_024 // 100MB
        return cache
    }()

    var body: some View {
        ZStack {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: maxHeight)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if isLoading {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appCard)
                    .frame(height: maxHeight)
                    .overlay(
                        ProgressView()
                            .scaleEffect(1.2)
                    )
            } else if loadError {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.appCard)
                    .frame(height: maxHeight)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 24))
                                .foregroundColor(.appTextTertiary)
                            Text("Failed to load image")
                                .font(.appCaption)
                                .foregroundColor(.appTextTertiary)
                        }
                    )
            }
        }
        .onAppear {
            startImageLoad()
        }
        .onChange(of: photoUrl) { _, _ in
            startImageLoad()
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    private func startImageLoad() {
        loadTask?.cancel()

        guard let photoUrl = photoUrl, !photoUrl.isEmpty else {
            isLoading = false
            loadedImage = nil
            loadError = false
            return
        }

        let cacheKey = NSString(string: photoUrl)
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            self.loadedImage = cachedImage
            self.isLoading = false
            self.loadError = false
            return
        }

        isLoading = true
        loadError = false
        loadedImage = nil

        loadTask = Task {
            do {
                let processedImage = try await ProgressPhotoImagePipeline.loadImage(urlString: photoUrl)
                guard !Task.isCancelled else { return }
                guard self.photoUrl == photoUrl else { return }

                let cost = ProgressPhotoImagePipeline.cacheCost(for: processedImage)
                Self.imageCache.setObject(processedImage, forKey: cacheKey, cost: cost)

                withAnimation(.easeInOut(duration: 0.22)) {
                    self.loadedImage = processedImage
                    self.isLoading = false
                    self.loadError = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard self.photoUrl == photoUrl else { return }
                isLoading = false
                loadError = true
                return
            }
        }
    }
}

enum ProgressPhotoImagePipeline {
    enum ImageLoadError: Error {
        case invalidURL
        case invalidResponse
        case decodeFailed
    }

    private static let imageSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 50 * 1_024 * 1_024,
            diskCapacity: 200 * 1_024 * 1_024,
            diskPath: "progress_photos"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

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
            let (responseData, response) = try await imageSession.data(from: url)
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

// Extension to preload images for smooth scrolling
extension OptimizedProgressPhotoView {
    static func preloadImages(urls: [String]) {
        for urlString in urls {
            let cacheKey = NSString(string: urlString)

            // Skip if already cached
            if imageCache.object(forKey: cacheKey) != nil {
                continue
            }

            Task.detached(priority: .background) {
                guard let image = try? await ProgressPhotoImagePipeline.loadImage(urlString: urlString) else { return }
                let cost = ProgressPhotoImagePipeline.cacheCost(for: image)
                await MainActor.run {
                    imageCache.setObject(image, forKey: cacheKey, cost: cost)
                }
            }
        }
    }
}
