//
// ProgressPhotoCarouselView.swift
// LogYourBody
//
import SwiftUI
import Vision
import UIKit

// MARK: - Temporary Glass Card (until UIComponents.swift is added to project)
struct ProgressPhotoGlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat = 16
    var padding: CGFloat = 16
    
    init(cornerRadius: CGFloat = 16, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(padding)
            .background(
                Group {
                    if #available(iOS 18.0, *) {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(Color.white.opacity(0.05))
                            )
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Color.appCard)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.appBorder, lineWidth: 1)
            )
    }
}

struct ProgressPhotoCarouselView: View {
    let currentMetric: BodyMetrics?
    let historicalMetrics: [BodyMetrics]
    @Binding var selectedMetricsIndex: Int
    @Binding var displayMode: BodyVisualizationMode
    @State private var isDragging = false
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var processingService = ImageProcessingService.shared

    // Now displayMetrics is ALL metrics, not just those with photos
    private var displayMetrics: [BodyMetrics] {
        historicalMetrics
    }
    
    var body: some View {
        ZStack {
            // Background - edge to edge
            Color.appBackground

            if displayMetrics.isEmpty {
                // Empty state
                EmptyDataState()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // TabView carousel - all metrics (photo or avatar)
                TabView(selection: $selectedMetricsIndex) {
                    ForEach(Array(displayMetrics.enumerated()), id: \.element.id) { index, metric in
                        VisualCard(
                            metric: metric,
                            displayMode: displayMode,
                            gender: authManager.currentUser?.profile?.gender
                        )
                        .tag(index)
                    }

                    // Processing placeholders
                    let processingTasks = processingService.processingTasks.filter { task in
                        task.status != .completed && task.status != .failed
                    }
                    ForEach(processingTasks) { task in
                        ProcessingCard()
                            .tag(displayMetrics.count + (processingTasks.firstIndex(where: { $0.id == task.id }) ?? 0))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: selectedMetricsIndex) { _, newIndex in
                    if !isDragging {
                        // HapticManager.shared.selection()
                    }
                }
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { _ in isDragging = true }
                        .onEnded { _ in isDragging = false }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            // Preload adjacent photos for smooth scrolling
            preloadAdjacentPhotos()
        }
        .onChange(of: selectedMetricsIndex) { _, _ in
            // Preload adjacent photos when selection changes
            preloadAdjacentPhotos()
        }
    }
    
    // MARK: - Photo Preloading for Smooth Experience

    private func preloadAdjacentPhotos() {
        // Preload photos around current selection for smooth scrolling
        let currentIndex = selectedMetricsIndex
        let range = max(0, currentIndex - 2)...min(displayMetrics.count - 1, currentIndex + 2)

        let urlsToPreload = range.compactMap { index -> String? in
            guard index < displayMetrics.count else { return nil }
            return displayMetrics[index].photoUrl
        }

        // Preload in background without blocking UI
        Task.detached(priority: .background) {
            for urlString in urlsToPreload {
                // Use ImageLoader cache to preload
                _ = await ImageLoader.shared.loadImage(from: urlString)
            }
        }
    }
}

// MARK: - Visual Card (Photo or Avatar)
struct VisualCard: View {
    let metric: BodyMetrics
    let displayMode: BodyVisualizationMode
    let gender: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.appBackground

                // Display based on mode
                switch displayMode {
                case .photo:
                    // Photo mode - show photo if available, otherwise avatar
                    if let photoUrl = metric.photoUrl {
                        PhotoCard(metric: metric)
                    } else {
                        // No photo - show avatar
                        AvatarBodyRenderer(
                            bodyFatPercentage: metric.bodyFatPercentage,
                            gender: gender,
                            height: geometry.size.height
                        )
                    }

                case .avatar:
                    // Avatar mode - always show avatar
                    AvatarBodyRenderer(
                        bodyFatPercentage: metric.bodyFatPercentage,
                        gender: gender,
                        height: geometry.size.height
                    )
                }
            }
        }
    }
}

// MARK: - Photo Card with Face-Centered Crop
struct PhotoCard: View {
    let metric: BodyMetrics
    @State private var loadedImage: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.appBackground

                // Photo content
                if let photoUrl = metric.photoUrl {
                    if let loadedImage = loadedImage {
                        Image(uiImage: loadedImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit) // Show full image, centered
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } else {
                        // Use the optimized photo view directly
                        OptimizedProgressPhotoView(
                            photoUrl: photoUrl,
                            maxHeight: geometry.size.height
                        )
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .onAppear {
                            loadImage(from: photoUrl)
                        }
                    }
                }
            }
        }
    }

    private func loadImage(from urlString: String) {
        Task.detached(priority: .userInitiated) {
            // Load image on background thread to avoid UI blocking
            if let image = await ImageLoader.shared.loadImage(from: urlString) {
                await MainActor.run {
                    self.loadedImage = image
                }
            }
        }
    }
}

// MARK: - Empty Data State
struct EmptyDataState: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))

            Text("No data yet")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.5))

            Text("Log your first entry to start tracking")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Processing Card
struct ProcessingCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 3)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.appPrimary, lineWidth: 3)
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(isAnimating ? 360 : 0))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
            }
            
            VStack(spacing: 8) {
                Text("Processing...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                
                Text("AI background removal in progress")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Image Loader
class ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSString, UIImage>()
    
    func loadImage(from urlString: String) async -> UIImage? {
        // Check cache first
        if let cached = cache.object(forKey: urlString as NSString) {
            return cached
        }
        
        // Download image
        guard let url = URL(string: urlString) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                cache.setObject(image, forKey: urlString as NSString)
                return image
            }
        } catch {
            // print("Failed to load image: \(error)")
        }
        
        return nil
    }
}

#Preview {
    ProgressPhotoCarouselView(
        currentMetric: nil,
        historicalMetrics: [],
        selectedMetricsIndex: .constant(0),
        displayMode: .constant(.photo)
    )
    .environmentObject(AuthManager.shared)
    .frame(height: 400)
    .padding()
    .background(Color.appBackground)
}
//
