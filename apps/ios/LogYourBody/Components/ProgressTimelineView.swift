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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let bodyMetrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    @Binding var mode: TimelineMode

    @State private var isDragging: Bool = false
    @State private var dragPosition: Double = 0.5
    @State private var currentDateLabel: String = ""
    @State private var renderSignature: TimelineRenderSignature
    @State private var renderData: TimelineRenderData

    private let timelineHeight: CGFloat = 50
    private let scrubberHandleSize: CGFloat = 44

    init(
        bodyMetrics: [BodyMetrics],
        selectedIndex: Binding<Int>,
        mode: Binding<TimelineMode>
    ) {
        self.bodyMetrics = bodyMetrics
        _selectedIndex = selectedIndex
        _mode = mode

        let initialSignature = TimelineRenderSignature(metrics: bodyMetrics, mode: mode.wrappedValue)
        _renderSignature = State(initialValue: initialSignature)
        _renderData = State(initialValue: TimelineRenderData.make(metrics: bodyMetrics, mode: mode.wrappedValue))
    }

    // MARK: - Body

    var body: some View {
        let currentRenderSignature = TimelineRenderSignature(metrics: bodyMetrics, mode: mode)
        let handlePosition = isDragging ? dragPosition : selectedPosition(
            in: renderData,
            selectedIndex: selectedIndex
        )

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
                    anchorsView(
                        width: geometry.size.width,
                        anchors: renderData.anchors,
                        zoomLevel: renderData.zoomLevel
                    )
                    .accessibilityHidden(true)

                    // Scrubber handle
                    scrubberHandle
                        .offset(x: handlePosition * geometry.size.width - scrubberHandleSize / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged {
                                    handleDrag($0, width: geometry.size.width, renderData: renderData)
                                }
                                .onEnded { _ in handleDragEnd() }
                        )
                }
                .frame(height: timelineHeight)
            }
            .frame(height: timelineHeight)
        }
        .accessibilityIdentifier("dashboard_timeline_scrubber")
        .onAppear {
            refreshRenderDataIfNeeded(for: currentRenderSignature)
        }
        .onChange(of: currentRenderSignature) { _, newSignature in
            refreshRenderDataIfNeeded(for: newSignature)
        }
    }

    // MARK: - Subviews

    private var dateLabel: some View {
        Text(currentDateLabel)
            .font(.footnote.weight(.medium))
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
            .accessibilityHidden(true)
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
            .accessibilityHidden(true)
    }

    private func anchorsView(
        width: CGFloat,
        anchors: [TimelineAnchor],
        zoomLevel: TimelineZoomLevel
    ) -> some View {
        ForEach(anchors) { anchor in
            anchorView(for: anchor, zoomLevel: zoomLevel)
                .position(
                    x: anchor.position * width,
                    y: timelineHeight / 2
                )
        }
    }

    @ViewBuilder
    private func anchorView(for anchor: TimelineAnchor, zoomLevel: TimelineZoomLevel) -> some View {
        switch mode {
        case .photo:
            photoModeAnchor(for: anchor, zoomLevel: zoomLevel)
        case .avatar:
            avatarModeAnchor(for: anchor)
        }
    }

    private func photoModeAnchor(for anchor: TimelineAnchor, zoomLevel: TimelineZoomLevel) -> some View {
        Group {
            if anchor.anchorType == .photo || anchor.anchorType == .photoWithMetrics {
                if let photoUrl = anchor.bodyMetrics.photoUrl,
                   !photoUrl.isEmpty,
                   let _ = URL(string: photoUrl) {
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
                    photoPlaceholder(zoomLevel: zoomLevel)
                }
            } else if zoomLevel.showMetricTicks {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 4, height: 4)
            } else {
                EmptyView()
            }
        }
    }

    private func photoPlaceholder(zoomLevel: TimelineZoomLevel) -> some View {
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
            .overlay(alignment: .top) {
                if anchor.anchorType == .photo || anchor.anchorType == .photoWithMetrics {
                    Circle()
                        .fill(Color.liquidAccent.opacity(0.4))
                        .frame(width: 6, height: 6)
                }
            }
    }

    private var scrubberHandle: some View {
        ZStack {
            Capsule()
                .fill(Color.liquidAccent)
                .frame(width: 4, height: 24)
                .shadow(color: Color.liquidAccent.opacity(0.5), radius: 4, x: 0, y: 2)

            Color.clear
        }
        .frame(width: scrubberHandleSize, height: scrubberHandleSize)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timeline scrubber")
        .accessibilityValue(accessibilityTimelineValue)
        .accessibilityHint("Swipe up or down to move between logged dates")
        .accessibilityAdjustableAction { direction in
            adjustSelection(for: direction)
        }
        .accessibilityIdentifier("dashboard_timeline_scrubber_handle")
    }

    // MARK: - Logic

    private func selectedPosition(in renderData: TimelineRenderData, selectedIndex: Int) -> Double {
        guard selectedIndex >= 0, selectedIndex < bodyMetrics.count else {
            return dragPosition
        }

        let metric = bodyMetrics[selectedIndex]
        return renderData.anchors.first(where: { $0.bodyMetrics.id == metric.id })?.position ?? dragPosition
    }

    private func handleDrag(_ value: DragGesture.Value, width: CGFloat, renderData: TimelineRenderData) {
        isDragging = true

        // Calculate position (0.0 to 1.0)
        let position = max(0, min(1, value.location.x / width))
        dragPosition = position

        // Convert position to date
        guard !renderData.metrics.isEmpty,
              let firstDate = renderData.metrics.first?.date,
              let lastDate = renderData.metrics.last?.date else {
            return
        }

        let scrubDate = renderData.provider.dateFromPosition(position, from: firstDate, to: lastDate)

        // Update based on mode
        switch mode {
        case .photo:
            handlePhotoModeScrub(scrubDate: scrubDate, provider: renderData.provider)
        case .avatar:
            handleAvatarModeScrub(scrubDate: scrubDate, provider: renderData.provider)
        }
    }

    private func handlePhotoModeScrub(scrubDate: Date, provider: TimelineDataProvider) {
        // Find data for photo mode (continuous time-based)
        let result = provider.findDataForPhotoMode(scrubDate: scrubDate)
        currentDateLabel = result.formattedDateLabel()

        // Update selected index to nearest entry
        if let photo = result.photo {
            if let index = bodyMetrics.firstIndex(where: { $0.id == photo.bodyMetrics.id }) {
                updateSelectedIndex(index)
            }
        } else if let metrics = result.metrics {
            if let index = bodyMetrics.firstIndex(where: { $0.id == metrics.bodyMetrics.id }) {
                updateSelectedIndex(index)
            }
        }
    }

    private func handleAvatarModeScrub(scrubDate: Date, provider: TimelineDataProvider) {
        // Snap to nearest data date
        guard let nearestDate = provider.findNearestDataDate(to: scrubDate) else {
            return
        }

        currentDateLabel = TimelineDateFormatterCache.string(from: nearestDate, style: .mediumDate)

        // Update selected index
        if let metric = provider.getMetric(for: nearestDate),
           let index = bodyMetrics.firstIndex(where: { $0.id == metric.id }) {
            updateSelectedIndex(index)
        }
    }

    private func handleDragEnd() {
        if reduceMotion {
            isDragging = false
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                isDragging = false
            }
        }

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }

    private var accessibilityTimelineValue: String {
        guard !bodyMetrics.isEmpty else {
            return "No logged dates"
        }

        let clampedIndex = min(max(selectedIndex, 0), bodyMetrics.count - 1)
        let date = bodyMetrics[clampedIndex].date
        let formattedDate = TimelineDateFormatterCache.string(from: date, style: .mediumDate)
        return "\(formattedDate), \(clampedIndex + 1) of \(bodyMetrics.count)"
    }

    private func adjustSelection(for direction: AccessibilityAdjustmentDirection) {
        guard !bodyMetrics.isEmpty else { return }

        let current = min(max(selectedIndex, 0), bodyMetrics.count - 1)
        let nextIndex: Int

        switch direction {
        case .increment:
            nextIndex = min(current + 1, bodyMetrics.count - 1)
        case .decrement:
            nextIndex = max(current - 1, 0)
        @unknown default:
            return
        }

        guard nextIndex != current else { return }
        updateSelectedIndex(nextIndex)
        currentDateLabel = TimelineDateFormatterCache.string(
            from: bodyMetrics[nextIndex].date,
            style: .mediumDate
        )
        HapticManager.shared.selection()
    }

    private func updateSelectedIndex(_ index: Int) {
        guard bodyMetrics.indices.contains(index), selectedIndex != index else { return }
        selectedIndex = index
    }

    private func refreshRenderDataIfNeeded(for signature: TimelineRenderSignature) {
        guard signature != renderSignature else { return }

        renderSignature = signature
        renderData = TimelineRenderData.make(metrics: bodyMetrics, mode: mode)
    }
}

/// Compact fingerprint of the inputs that affect timeline rendering.
///
/// `ProgressTimelineView.body` rebuilds this on every evaluation purely to detect when the
/// expensive `TimelineRenderData` needs regenerating, so it has to be cheap. It previously
/// allocated an `[MetricFingerprint]` array (each element retaining several `String`s) and
/// compared it field-by-field — during a drag that is an O(n) heap allocation plus ARC
/// churn *per frame*, and an O(n) `Equatable` walk on every `onChange` comparison. Folding
/// the same tracked fields into a single hash makes construction allocation-free and
/// equality O(1), while preserving exactly which fields trigger a refresh.
struct TimelineRenderSignature: Equatable {
    let modeRawValue: String
    let metricCount: Int
    let fingerprint: Int

    init(metrics: [BodyMetrics], mode: TimelineMode) {
        modeRawValue = mode.rawValue
        metricCount = metrics.count

        var hasher = Hasher()
        for metric in metrics {
            hasher.combine(metric.id)
            hasher.combine(metric.date.timeIntervalSinceReferenceDate)
            hasher.combine(metric.localDate)
            hasher.combine(metric.photoUrl)
            hasher.combine(metric.weight)
            hasher.combine(metric.bodyFatPercentage)
            hasher.combine(metric.updatedAt.timeIntervalSinceReferenceDate)
        }
        fingerprint = hasher.finalize()
    }
}

struct TimelineRenderData {
    let metrics: [BodyMetrics]
    let provider: TimelineDataProvider
    let anchors: [TimelineAnchor]
    let zoomLevel: TimelineZoomLevel

    static func make(metrics: [BodyMetrics], mode: TimelineMode) -> TimelineRenderData {
        let provider = TimelineDataProvider()
        provider.loadMetrics(metrics)
        guard !metrics.isEmpty,
              let firstDate = provider.bodyMetrics.first?.date,
              let lastDate = provider.bodyMetrics.last?.date else {
            return TimelineRenderData(
                metrics: [],
                provider: provider,
                anchors: [],
                zoomLevel: .month
            )
        }

        let zoomLevel = TimelineZoomLevel.calculate(from: firstDate, to: lastDate)
        let anchors = provider.generateAnchors(mode: mode, zoomLevel: zoomLevel)

        return TimelineRenderData(
            metrics: provider.bodyMetrics,
            provider: provider,
            anchors: anchors,
            zoomLevel: zoomLevel
        )
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
                    date: Date().addingTimeInterval(-60 * 60 * 24 * 30),
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
