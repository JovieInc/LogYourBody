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
    @Binding var displayMode: DashboardDisplayMode
    @State private var isDragging = false
    @State private var preloadTask: Task<Void, Never>?
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
                // TabView carousel - photos only
                TabView(selection: $selectedMetricsIndex) {
                    ForEach(Array(displayMetrics.enumerated()), id: \.element.id) { index, metric in
                        PhotoCard(metric: metric)
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
                .onChange(of: selectedMetricsIndex) { _, _ in
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

    /// The clamped ±`window` index range to preload around `index` for a
    /// collection of `count` items. Returns `nil` when there is nothing safe to
    /// preload so callers never construct an inverted `ClosedRange` (which traps
    /// with "Range requires lowerBound <= upperBound").
    ///
    /// `selectedMetricsIndex` is an externally-shared binding that can legitimately
    /// exceed `displayMetrics.count` — the TabView tags in-flight processing
    /// placeholders as `count + i`, and the index can go stale when metrics shrink
    /// after a sync/delete. Clamping here keeps preloading crash-safe for those cases.
    static func preloadIndexRange(around index: Int, count: Int, window: Int = 2) -> ClosedRange<Int>? {
        let lastIndex = count - 1
        guard lastIndex >= 0 else { return nil }
        let clamped = min(max(index, 0), lastIndex)
        let lower = max(0, clamped - window)
        let upper = min(lastIndex, clamped + window)
        guard lower <= upper else { return nil }
        return lower...upper
    }

    private func preloadAdjacentPhotos() {
        // Cancel previous preload task to prevent accumulation
        preloadTask?.cancel()

        // Debounce: Create new task with delay
        preloadTask = Task {
            // 500ms debounce to avoid excessive preloading on rapid scrolling
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Check if task was cancelled during sleep
            guard !Task.isCancelled else { return }

            // Preload photos around current selection (±2 indices), clamped so a
            // stale/oversized index can never form an inverted range.
            guard let range = Self.preloadIndexRange(
                around: selectedMetricsIndex,
                count: displayMetrics.count
            ) else { return }

            let urlsToPreload = range.compactMap { index -> String? in
                guard index < displayMetrics.count else { return nil }
                return displayMetrics[index].photoUrl
            }.filter { !$0.isEmpty }

            // Use centralized ImageCacheService for preloading
            ImageCacheService.shared.preloadImages(urlsToPreload)
        }
    }
}

// MARK: - Photo Card with Face-Centered Crop
struct PhotoCard: View {
    let metric: BodyMetrics

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.appBackground

                // Photo content
                if let photoUrl = metric.photoUrl {
                    CachedAsyncImage(urlString: photoUrl) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                    } placeholder: {
                        ProgressView()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    .id(photoUrl) // Stable ID prevents unnecessary reloads
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

// ImageLoader removed - now using centralized ImageCacheService

#Preview {
    ProgressPhotoCarouselView(
        currentMetric: nil,
        historicalMetrics: [],
        selectedMetricsIndex: .constant(0),
        displayMode: .constant(DashboardDisplayMode.photo)
    )
    .environmentObject(AuthManager.shared)
    .frame(height: 400)
    .padding()
    .background(Color.appBackground)
}
//
