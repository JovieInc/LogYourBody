//
// ProgressTimelineView.swift
// LogYourBody
//
// Dual-mode timeline component for navigating progress photos and metrics
// Inspired by iOS Photos timeline scrubber with time-weighted positioning
//

import SwiftUI

struct ProgressTimelineView: View {
    // MARK: - Properties

    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    @Binding var mode: TimelineMode

    @StateObject private var dataProvider = TimelineDataProvider()
    @State private var anchors: [TimelineAnchor] = []
    @State private var zoomLevel: TimelineZoomLevel = .month
    @State private var isDragging: Bool = false
    @State private var dragPosition: Double = 0.5
    @State private var currentDateLabel: String = ""

    private let timelineHeight: CGFloat = 50
    private let scrubberHandleSize: CGFloat = 44

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Date label (shows when dragging)
            if isDragging {
                dateLabel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Timeline strip
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    timelineTrack

                    // Anchors (photos/metrics)
                    anchorsView(width: geometry.size.width)

                    // Scrubber handle
                    scrubberHandle
                        .offset(x: dragPosition * geometry.size.width - scrubberHandleSize / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { handleDrag($0, width: geometry.size.width) }
                                .onEnded { _ in handleDragEnd() }
                        )
                }
                .frame(height: timelineHeight)
            }
            .frame(height: timelineHeight)
        }
        .onAppear {
            setupTimeline()
        }
        .onChange(of: bodyMetrics) { _, _ in
            setupTimeline()
        }
        .onChange(of: mode) { _, _ in
            setupTimeline()
        }
    }

    // MARK: - Subviews

    private var dateLabel: some View {
        Text(currentDateLabel)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Color.liquidTextPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            )
            .padding(.bottom, 4)
    }

    private var timelineTrack: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .frame(height: 6)
            .padding(.vertical, (timelineHeight - 6) / 2)
    }

    private func anchorsView(width: CGFloat) -> some View {
        ForEach(anchors) { anchor in
            anchorView(for: anchor)
                .position(
                    x: anchor.position * width,
                    y: timelineHeight / 2
                )
        }
    }

    @ViewBuilder
    private func anchorView(for anchor: TimelineAnchor) -> some View {
        switch mode {
        case .photo:
            photoModeAnchor(for: anchor)
        case .avatar:
            avatarModeAnchor(for: anchor)
        }
    }

    private func photoModeAnchor(for anchor: TimelineAnchor) -> some View {
        Group {
            if anchor.anchorType == .photo || anchor.anchorType == .photoWithMetrics {
                // Photo thumbnail (circular)
                if let photoUrl = anchor.bodyMetrics.photoUrl, !photoUrl.isEmpty {
                    // Debug logging
                    _ = // print("[Timeline] Loading photo for anchor: \(anchor.id), URL: \(photoUrl)")

                    // Validate URL before attempting to load
                    if URL(string: photoUrl) != nil {
                        OptimizedProgressPhotoView(
                            photoUrl: photoUrl,
                            maxHeight: zoomLevel.thumbnailSize
                        )
                        .frame(width: zoomLevel.thumbnailSize, height: zoomLevel.thumbnailSize)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        )
                    } else {
                        _ = // print("[Timeline] Invalid URL format: \(photoUrl)")
                        photoPlaceholder
                    }
                } else {
                    photoPlaceholder
                }
            } else {
                // Metrics-only tick (subtle)
                if zoomLevel.showMetricTicks {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 4, height: 4)
                }
            }
        }
    }

    private var photoPlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.2))
            .frame(width: zoomLevel.thumbnailSize, height: zoomLevel.thumbnailSize)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: zoomLevel.thumbnailSize * 0.4))
                    .foregroundColor(Color.white.opacity(0.5))
            )
    }

    private func avatarModeAnchor(for anchor: TimelineAnchor) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.8))
            .frame(width: 2, height: 12)
            .overlay(
                // Show faint photo indicator if photo exists
                anchor.anchorType == .photo || anchor.anchorType == .photoWithMetrics ?
                    Circle()
                        .fill(Color.liquidAccent.opacity(0.4))
                        .frame(width: 6, height: 6)
                    : nil
            )
    }

    private var scrubberHandle: some View {
        VStack(spacing: 2) {
            // Pill handle
            Capsule()
                .fill(Color.liquidAccent)
                .frame(width: 4, height: 24)
                .shadow(color: Color.liquidAccent.opacity(0.5), radius: 4, x: 0, y: 2)

            // Touch target (invisible but tappable)
            Color.clear
                .frame(width: scrubberHandleSize, height: scrubberHandleSize)
        }
        .frame(width: scrubberHandleSize, height: scrubberHandleSize)
    }

    // MARK: - Logic

    private func setupTimeline() {
        dataProvider.loadMetrics(bodyMetrics)

        guard !bodyMetrics.isEmpty else {
            anchors = []
            return
        }

        let sortedMetrics = bodyMetrics.sorted { $0.date < $1.date }
        guard let firstDate = sortedMetrics.first?.date,
              let lastDate = sortedMetrics.last?.date else {
            return
        }

        // Calculate zoom level
        zoomLevel = TimelineZoomLevel.calculate(from: firstDate, to: lastDate)

        // Generate anchors
        anchors = dataProvider.generateAnchors(mode: mode, zoomLevel: zoomLevel)

        // Set initial position
        updateDragPosition(for: selectedIndex)
    }

    private func updateDragPosition(for index: Int) {
        guard index >= 0, index < bodyMetrics.count else { return }
        let metric = bodyMetrics[index]

        guard let anchor = anchors.first(where: { $0.bodyMetrics.id == metric.id }) else {
            // If not an anchor, calculate position manually
            guard let firstDate = bodyMetrics.first?.date,
                  let lastDate = bodyMetrics.last?.date else {
                return
            }
            dragPosition = dataProvider.dateFromPosition(0.5, from: firstDate, to: lastDate).timeIntervalSince1970 / metric.date.timeIntervalSince1970
            return
        }

        dragPosition = anchor.position
    }

    private func handleDrag(_ value: DragGesture.Value, width: CGFloat) {
        isDragging = true

        // Calculate position (0.0 to 1.0)
        let position = max(0, min(1, value.location.x / width))
        dragPosition = position

        // Convert position to date
        guard !bodyMetrics.isEmpty,
              let firstDate = bodyMetrics.first?.date,
              let lastDate = bodyMetrics.last?.date else {
            return
        }

        let scrubDate = dataProvider.dateFromPosition(position, from: firstDate, to: lastDate)

        // Update based on mode
        switch mode {
        case .photo:
            handlePhotoModeScrub(scrubDate: scrubDate)
        case .avatar:
            handleAvatarModeScrub(scrubDate: scrubDate)
        }
    }

    private func handlePhotoModeScrub(scrubDate: Date) {
        // Find data for photo mode (continuous time-based)
        let result = dataProvider.findDataForPhotoMode(scrubDate: scrubDate)
        currentDateLabel = result.formattedDateLabel()

        // Update selected index to nearest entry
        if let photo = result.photo {
            if let index = bodyMetrics.firstIndex(where: { $0.id == photo.bodyMetrics.id }) {
                selectedIndex = index
            }
        } else if let metrics = result.metrics {
            if let index = bodyMetrics.firstIndex(where: { $0.id == metrics.bodyMetrics.id }) {
                selectedIndex = index
            }
        }
    }

    private func handleAvatarModeScrub(scrubDate: Date) {
        // Snap to nearest data date
        guard let nearestDate = dataProvider.findNearestDataDate(to: scrubDate) else {
            return
        }

        // Format date
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        currentDateLabel = formatter.string(from: nearestDate)

        // Update selected index
        if let metric = dataProvider.getMetric(for: nearestDate),
           let index = bodyMetrics.firstIndex(where: { $0.id == metric.id }) {
            selectedIndex = index
        }
    }

    private func handleDragEnd() {
        withAnimation(.easeOut(duration: 0.2)) {
            isDragging = false
        }

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()

        ProgressTimelineView(
            bodyMetrics: [
                // Sample data for preview
                BodyMetrics(
                    id: "1",
                    userId: "user1",
                    date: Date().addingTimeInterval(-60*60*24*30),
                    weight: 180,
                    weightUnit: "lbs",
                    bodyFatPercentage: 20,
                    bodyFatMethod: "scale",
                    muscleMass: nil,
                    boneMass: nil,
                    notes: nil,
                    photoUrl: nil,
                    dataSource: "manual",
                    createdAt: Date(),
                    updatedAt: Date()
                ),
                BodyMetrics(
                    id: "2",
                    userId: "user1",
                    date: Date(),
                    weight: 175,
                    weightUnit: "lbs",
                    bodyFatPercentage: 18,
                    bodyFatMethod: "scale",
                    muscleMass: nil,
                    boneMass: nil,
                    notes: nil,
                    photoUrl: nil,
                    dataSource: "manual",
                    createdAt: Date(),
                    updatedAt: Date()
                )
            ],
            selectedIndex: .constant(0),
            mode: .constant(.photo)
        )
        .frame(height: 80)
        .padding()
        .background(Color.liquidBg)
    }
    .background(Color.liquidBg)
}
