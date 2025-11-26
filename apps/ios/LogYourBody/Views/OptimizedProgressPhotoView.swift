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
            loadImage()
        }
        .onChange(of: photoUrl) { _, _ in
            loadImage()
        }
    }

    private func loadImage() {
        guard let photoUrl = photoUrl, !photoUrl.isEmpty else {
            isLoading = false
            return
        }

        // Check cache first
        let cacheKey = NSString(string: photoUrl)
        if let cachedImage = Self.imageCache.object(forKey: cacheKey) {
            self.loadedImage = cachedImage
            self.isLoading = false
            return
        }

        // Load from network
        Task {
            await loadFromNetwork(urlString: photoUrl)
        }
    }

    @MainActor
    private func loadFromNetwork(urlString: String) async {
        guard let url = URL(string: urlString) else {
            isLoading = false
            loadError = true
            return
        }

        // Check if it's a local file URL
        if url.isFileURL {
            await loadLocalFile(url: url, urlString: urlString)
            return
        }

        do {
            // Configure URLSession for optimal image loading
            let config = URLSessionConfiguration.default
            config.urlCache = URLCache(
                memoryCapacity: 50 * 1_024 * 1_024,  // 50MB memory cache
                diskCapacity: 200 * 1_024 * 1_024,   // 200MB disk cache
                diskPath: "progress_photos"
            )
            config.requestCachePolicy = .returnCacheDataElseLoad

            let session = URLSession(configuration: config)
            let (data, response) = try await session.data(from: url)

            // Verify response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                isLoading = false
                loadError = true
                return
            }

            // Process image on background queue
            let processedImage = await Task.detached(priority: .userInitiated) {
                return optimizeImage(image)
            }.value

            // Cache the processed image
            let cost = processedImage.pngData()?.count ?? 0
            Self.imageCache.setObject(processedImage, forKey: NSString(string: urlString), cost: cost)

            // Update UI
            withAnimation(.easeInOut(duration: 0.3)) {
                self.loadedImage = processedImage
                self.isLoading = false
            }
        } catch {
            // print("❌ Failed to load progress photo: \(error)")
            isLoading = false
            loadError = true
        }
    }

    @MainActor
    private func loadLocalFile(url: URL, urlString: String) async {
        do {
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else {
                isLoading = false
                loadError = true
                return
            }

            // Process image on background queue
            let processedImage = await Task.detached(priority: .userInitiated) {
                return optimizeImage(image)
            }.value

            // Cache the processed image
            let cost = processedImage.pngData()?.count ?? 0
            Self.imageCache.setObject(processedImage, forKey: NSString(string: urlString), cost: cost)

            // Update UI
            withAnimation(.easeInOut(duration: 0.3)) {
                self.loadedImage = processedImage
                self.isLoading = false
            }
        } catch {
            // print("❌ Failed to load local photo: \(error)")
            isLoading = false
            loadError = true
        }
    }

    private func optimizeImage(_ image: UIImage) -> UIImage {
        // First fix orientation if needed
        let orientedImage = image.fixedOrientation()

        // Optimize for display
        // Use fixed dimensions for typical device screens to avoid UIScreen.main deprecation
        // Assumes iPhone width ~390-430pt with 3x scale = ~1170-1290px
        let maxDimension: CGFloat = 1_200.0
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

            // Load in background
            Task.detached(priority: .background) {
                guard let url = URL(string: urlString),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data) else { return }

                let cost = data.count
                await MainActor.run {
                    imageCache.setObject(image, forKey: cacheKey, cost: cost)
                }
            }
        }
    }
}
