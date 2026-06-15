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

        if let cachedImage = ImageCacheService.shared.cachedImage(for: photoUrl) {
            self.loadedImage = cachedImage
            self.isLoading = false
            self.loadError = false
            return
        }

        isLoading = true
        loadError = false
        loadedImage = nil

        loadTask = Task {
            guard let processedImage = await ImageCacheService.shared.loadImage(from: photoUrl) else {
                guard !Task.isCancelled else { return }
                guard self.photoUrl == photoUrl else { return }
                self.isLoading = false
                self.loadError = true
                return
            }

            guard !Task.isCancelled else { return }
            guard self.photoUrl == photoUrl else { return }

            withAnimation(.easeInOut(duration: 0.22)) {
                self.loadedImage = processedImage
                self.isLoading = false
                self.loadError = false
            }
        }
    }
}

// Extension to preload images for smooth scrolling
extension OptimizedProgressPhotoView {
    @MainActor
    static func cachedImage(for urlString: String?) -> UIImage? {
        ImageCacheService.shared.cachedImage(for: urlString)
    }

    static func resolvedImage(for urlString: String?) async -> UIImage? {
        guard let urlString, !urlString.isEmpty else { return nil }
        return await ImageCacheService.shared.loadImage(from: urlString)
    }

    @MainActor
    static func preloadImages(urls: [String]) {
        ImageCacheService.shared.preloadImages(urls)
    }
}
