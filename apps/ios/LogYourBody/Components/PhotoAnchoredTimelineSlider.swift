//
// PhotoAnchoredTimelineSlider.swift
// LogYourBody
//
import SwiftUI
import Foundation

// MARK: - Timeline Data Models

struct TimelineTick {
    let index: Int
    let date: Date
    let position: CGFloat
    let isMinor: Bool
    let hasPhoto: Bool
    let photoUrl: String?
    let isPhotoAnchor: Bool // True if this is a primary photo checkpoint
}

/// Represents a data point on the timeline with weighted position
struct TimelineDataPoint: Identifiable {
    let id: String
    let index: Int                  // Index in original bodyMetrics array
    let date: Date                  // Actual date of this entry
    let position: Double            // Weighted position (0.0 = oldest, 1.0 = newest)
    let displayLabel: String        // Human-readable label for this point
    let importance: TimelineImportance

    enum TimelineImportance {
        case daily      // Individual day (last 7 days)
        case weekly     // Week checkpoint (8-30 days)
        case monthly    // Month checkpoint (1-12 months)
        case yearly     // Year checkpoint (>1 year)
    }
}

/// Calculates smart time-weighted positions for timeline entries
class TimelineCalculator {
    /// Calculate weighted timeline positions for body metrics
    static func calculateTimelinePoints(from metrics: [BodyMetrics]) -> [TimelineDataPoint] {
        guard !metrics.isEmpty else { return [] }

        let sortedMetrics = metrics.sorted { $0.date < $1.date }
        guard let newestDate = sortedMetrics.last?.date else { return [] }

        let now = Date()
        var timelinePoints: [TimelineDataPoint] = []
        let calendar = Calendar.current

        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now

        for (index, metric) in sortedMetrics.enumerated() {
            let importance: TimelineDataPoint.TimelineImportance

            if metric.date >= sevenDaysAgo {
                importance = .daily
            } else if metric.date >= thirtyDaysAgo {
                importance = .weekly
            } else if metric.date >= oneYearAgo {
                importance = .monthly
            } else {
                importance = .yearly
            }

            timelinePoints.append(TimelineDataPoint(
                id: metric.id,
                index: index,
                date: metric.date,
                position: 0.0,
                displayLabel: formatLabel(for: metric.date, importance: importance),
                importance: importance
            ))
        }

        return calculateWeightedPositions(points: timelinePoints, newestDate: newestDate)
    }

    private static func calculateWeightedPositions(points: [TimelineDataPoint], newestDate: Date) -> [TimelineDataPoint] {
        let calendar = Calendar.current
        let now = Date()

        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now

        return points.map { point in
            let position: Double

            if point.date >= thirtyDaysAgo {
                let daysAgo = calendar.dateComponents([.day], from: point.date, to: now).day ?? 0
                let normalizedPosition = 1.0 - (Double(daysAgo) / 30.0)
                position = 0.3 + (normalizedPosition * 0.7)
            } else if point.date >= oneYearAgo {
                let daysAgo = calendar.dateComponents([.day], from: point.date, to: now).day ?? 0
                let daysSinceThirty = Double(daysAgo - 30)
                let normalizedPosition = 1.0 - (daysSinceThirty / 335.0)
                position = 0.1 + (normalizedPosition * 0.2)
            } else {
                guard let oldestPoint = points.first else {
                    position = 0.0
                    return point
                }

                let totalOldTime = oneYearAgo.timeIntervalSince(oldestPoint.date)
                guard totalOldTime > 0 else {
                    position = 0.0
                    return point
                }

                let timeFromOldest = point.date.timeIntervalSince(oldestPoint.date)
                let normalizedPosition = timeFromOldest / totalOldTime
                position = normalizedPosition * 0.1
            }

            return TimelineDataPoint(
                id: point.id,
                index: point.index,
                date: point.date,
                position: max(0.0, min(1.0, position)),
                displayLabel: point.displayLabel,
                importance: point.importance
            )
        }
    }

    private static func formatLabel(for date: Date, importance: TimelineDataPoint.TimelineImportance) -> String {
        let calendar = Calendar.current
        let now = Date()

        // Check if date is today
        if calendar.isDateInToday(date) {
            return "Today"
        }

        // Check if date is yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        // Check if date is in the last 7 days - use day name
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        if date >= sevenDaysAgo && date < now {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Full day name (Monday, Tuesday, etc)
            return formatter.string(from: date)
        }

        // Get current year for comparison
        let currentYear = calendar.component(.year, from: now)
        let dateYear = calendar.component(.year, from: date)

        // Check if date is in current month
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d" // e.g., "Nov 4"
            return formatter.string(from: date)
        }

        // Check if date is in current year (but different month)
        if dateYear == currentYear {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d" // e.g., "Oct 21"
            return formatter.string(from: date)
        }

        // Date is in a past year
        let formatter = DateFormatter()

        // For dates more than 1 year ago, show just the year
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        if date < oneYearAgo {
            formatter.dateFormat = "yyyy" // e.g., "2023"
        } else {
            // For dates in past year but within last 12 months, show month and year
            formatter.dateFormat = "MMM yyyy" // e.g., "Nov 2023"
        }

        return formatter.string(from: date)
    }

    static func findNearestPoint(to position: Double, in points: [TimelineDataPoint]) -> TimelineDataPoint? {
        guard !points.isEmpty else { return nil }

        return points.min { point1, point2 in
            abs(point1.position - position) < abs(point2.position - position)
        }
    }
}

// MARK: - Photo-Anchored Timeline Slider

struct PhotoAnchoredTimelineSlider: View {
    let metrics: [BodyMetrics]
    @Binding var selectedIndex: Int
    let accentColor: Color

    @State private var isDragging = false
    @State private var thumbScale: CGFloat = 1.0
    @State private var timelinePoints: [TimelineDataPoint] = []

    private var progress: Double {
        guard !timelinePoints.isEmpty else { return 0 }

        // Find the timeline point for current selectedIndex
        if let point = timelinePoints.first(where: { $0.index == selectedIndex }) {
            return point.position
        }

        // Fallback to linear if point not found
        guard metrics.count > 1 else { return 0 }
        return Double(selectedIndex) / Double(metrics.count - 1)
    }

    private func calculateSmartTicks() -> [TimelineTick] {
        guard !timelinePoints.isEmpty else { return [] }

        var ticks: [TimelineTick] = []

        // Find metrics with photos for anchoring
        let photoIndices = metrics.enumerated().compactMap { index, metric in
            metric.photoUrl != nil ? index : nil
        }

        // Create ticks for photo metrics (always visible) using weighted positions
        for photoIndex in photoIndices {
            if let point = timelinePoints.first(where: { $0.index == photoIndex }) {
                ticks.append(TimelineTick(
                    index: photoIndex,
                    date: metrics[photoIndex].date,
                    position: CGFloat(point.position),
                    isMinor: false,
                    hasPhoto: true,
                    photoUrl: metrics[photoIndex].photoUrl,
                    isPhotoAnchor: true
                ))
            }
        }

        // Add important timeline points (daily/weekly checkpoints) as minor ticks
        for point in timelinePoints {
            let hasPhoto = metrics[point.index].photoUrl != nil

            // Add as minor tick if it's an important checkpoint and doesn't have a photo
            if !hasPhoto && (point.importance == .daily || point.importance == .weekly) {
                ticks.append(TimelineTick(
                    index: point.index,
                    date: point.date,
                    position: CGFloat(point.position),
                    isMinor: true,
                    hasPhoto: false,
                    photoUrl: nil,
                    isPhotoAnchor: false
                ))
            }
        }

        return ticks.sorted { $0.position < $1.position }
    }

    /// Get milestone ticks for year/month labels
    private func getMilestoneTicks() -> [TimelineDataPoint] {
        guard !timelinePoints.isEmpty else { return [] }

        var milestones: [TimelineDataPoint] = []
        var lastYear: Int?
        var lastMonth: Int?

        let calendar = Calendar.current

        for point in timelinePoints {
            let components = calendar.dateComponents([.year, .month], from: point.date)

            // Add yearly milestones
            if point.importance == .yearly {
                if let year = components.year, year != lastYear {
                    milestones.append(point)
                    lastYear = year
                }
            }
            // Add monthly milestones (for data within last year)
            else if point.importance == .monthly || point.importance == .weekly {
                if let year = components.year, let month = components.month {
                    let monthKey = year * 12 + month
                    if monthKey != lastMonth {
                        milestones.append(point)
                        lastMonth = monthKey
                    }
                }
            }
        }

        return milestones
    }

    /// Get milestone notches (visual markers for time boundaries)
    private func getMilestoneNotches() -> [TimelineDataPoint] {
        guard !timelinePoints.isEmpty else { return [] }

        var notches: [TimelineDataPoint] = []
        var lastYear: Int?
        var lastMonth: Int?
        var lastWeek: Int?

        let calendar = Calendar.current

        for point in timelinePoints {
            let components = calendar.dateComponents([.year, .month, .weekOfYear], from: point.date)

            // Add yearly notches
            if let year = components.year, year != lastYear {
                notches.append(point)
                lastYear = year
            }
            // Add monthly notches
            else if let year = components.year, let month = components.month {
                let monthKey = year * 12 + month
                if monthKey != lastMonth {
                    notches.append(point)
                    lastMonth = monthKey
                }
            }
            // Add weekly notches for recent data
            else if point.importance == .daily || point.importance == .weekly {
                if let year = components.year, let week = components.weekOfYear {
                    let weekKey = year * 53 + week
                    if weekKey != lastWeek {
                        notches.append(point)
                        lastWeek = weekKey
                    }
                }
            }
        }

        return notches
    }

    /// Get visible milestone labels with collision detection
    private func getVisibleMilestoneLabels(in trackWidth: CGFloat) -> [TimelineDataPoint] {
        let allMilestones = getMilestoneTicks()
        guard !allMilestones.isEmpty else { return [] }

        var visibleMilestones: [TimelineDataPoint] = []
        let minimumSpacing: CGFloat = 50 // Minimum pixels between labels

        // Estimate text width (rough approximation)
        func estimatedWidth(for text: String) -> CGFloat {
            // Approximate 10pt font: ~6px per character average
            return CGFloat(text.count) * 6 + 8 // Add padding
        }

        // Reserve space for "First" and "Now" labels at endpoints
        let firstLabelWidth: CGFloat = estimatedWidth(for: "First")
        let nowLabelWidth: CGFloat = estimatedWidth(for: "Now")

        for milestone in allMilestones {
            let xPosition = CGFloat(milestone.position) * trackWidth
            let labelWidth = estimatedWidth(for: milestone.displayLabel)

            // Check if too close to "First" label
            if xPosition < (firstLabelWidth + minimumSpacing) {
                continue
            }

            // Check if too close to "Now" label
            if xPosition > (trackWidth - nowLabelWidth - minimumSpacing) {
                continue
            }

            // Check collision with already-added labels
            var hasCollision = false
            for existingMilestone in visibleMilestones {
                let existingX = CGFloat(existingMilestone.position) * trackWidth
                let existingWidth = estimatedWidth(for: existingMilestone.displayLabel)

                // Calculate actual overlap
                let leftEdge = xPosition - labelWidth / 2
                let rightEdge = xPosition + labelWidth / 2
                let existingLeft = existingX - existingWidth / 2
                let existingRight = existingX + existingWidth / 2

                if leftEdge < existingRight && rightEdge > existingLeft {
                    hasCollision = true
                    break
                }
            }

            if !hasCollision {
                visibleMilestones.append(milestone)
            }
        }

        return visibleMilestones
    }

    var body: some View {
        VStack(spacing: 12) {
            // Photo navigation buttons
            if hasPhotos {
                HStack(spacing: 16) {
                    // Previous photo button
                    Button(action: navigateToPreviousPhoto) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(hasPreviousPhoto ? .white : .white.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(hasPreviousPhoto ? 0.1 : 0.05))
                            )
                    }
                    .disabled(!hasPreviousPhoto)

                    Spacer()

                    // Current date display
                    if let date = metrics[safe: selectedIndex]?.date {
                        VStack(spacing: 2) {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            Text(date, format: .dateTime.year())
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }

                    Spacer()

                    // Next photo button
                    Button(action: navigateToNextPhoto) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(hasNextPhoto ? .white : .white.opacity(0.3))
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(hasNextPhoto ? 0.1 : 0.05))
                            )
                    }
                    .disabled(!hasNextPhoto)
                }
                .padding(.horizontal, 4)
            }

            // Timeline slider with enhanced polish
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.25))
                        .frame(height: 4)

                    // Active track with subtle glow
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: max(4, geometry.size.width * CGFloat(progress)), height: 4)
                        .shadow(color: Color.white.opacity(0.3), radius: 2, x: 0, y: 0)
                        .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: progress)
                }
                .frame(height: 20, alignment: .center)

                // Photo thumbnails only (no tick lines)
                ForEach(calculateSmartTicks().filter { $0.hasPhoto }, id: \.index) { tick in
                    PhotoThumbnailTick(photoUrl: tick.photoUrl, isSelected: tick.index == selectedIndex)
                        .position(x: tick.position * geometry.size.width, y: 10)
                }

                // Milestone notches with varying heights
                ForEach(getMilestoneNotches(), id: \.index) { milestone in
                    Rectangle()
                        .fill(Color.white.opacity(milestone.importance == .yearly ? 0.6 : 0.4))
                        .frame(
                            width: 2,
                            height: milestone.importance == .yearly ? 12 : (milestone.importance == .monthly ? 8 : 6)
                        )
                        .position(x: CGFloat(milestone.position) * geometry.size.width, y: 2)
                }

                // Milestone labels with collision detection
                ForEach(getVisibleMilestoneLabels(in: geometry.size.width), id: \.index) { milestone in
                    Text(milestone.displayLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))
                        .position(x: CGFloat(milestone.position) * geometry.size.width, y: 35)
                }

                // First Photo label (pinned to start)
                if let firstPoint = timelinePoints.first {
                    Text("First")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))
                        .position(x: 20, y: 35)
                }

                // Now label (pinned to end)
                if let lastPoint = timelinePoints.last {
                    Text("Now")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.70))
                        .position(x: geometry.size.width - 20, y: 35)
                }

                // Enhanced thumb with glow
                Circle()
                    .fill(Color.white)
                    .frame(width: 24, height: 24)
                    .scaleEffect(thumbScale)
                    .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
                    .shadow(color: isDragging ? Color.white.opacity(0.4) : Color.clear, radius: 8, x: 0, y: 0)
                    .position(x: geometry.size.width * CGFloat(progress), y: 10)
                    .animation(isDragging ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: progress)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: thumbScale)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        thumbScale = 1.2

                        let geometry = value.translation.width
                        guard geometry > 0 else { return }

                        let position = value.location.x / geometry
                        let clampedPosition = min(max(0, position), 1)

                        // Find nearest timeline point to this position
                        if let nearestPoint = TimelineCalculator.findNearestPoint(to: clampedPosition, in: timelinePoints) {
                            if nearestPoint.index != selectedIndex {
                                selectedIndex = nearestPoint.index
                                // HapticManager.shared.buttonTap()
                            }
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        thumbScale = 1.0
                        // HapticManager.shared.buttonTap()
                    }
            )
        }
        .onAppear {
            calculateTimelinePoints()
        }
        .onChange(of: metrics) { _ in
            calculateTimelinePoints()
        }
    }

    // MARK: - Timeline Calculation

    private func calculateTimelinePoints() {
        timelinePoints = TimelineCalculator.calculateTimelinePoints(from: metrics)
    }

    // MARK: - Helper Properties

    private var hasPhotos: Bool {
        metrics.contains { $0.photoUrl != nil }
    }

    private var hasPreviousPhoto: Bool {
        guard selectedIndex > 0 else { return false }
        return metrics[0..<selectedIndex].contains { $0.photoUrl != nil }
    }

    private var hasNextPhoto: Bool {
        guard selectedIndex < metrics.count - 1 else { return false }
        return metrics[(selectedIndex + 1)...].contains { $0.photoUrl != nil }
    }

    // MARK: - Navigation Methods

    private func navigateToPreviousPhoto() {
        guard selectedIndex > 0 else { return }

        for i in stride(from: selectedIndex - 1, through: 0, by: -1) {
            if metrics[i].photoUrl != nil {
                selectedIndex = i
                // HapticManager.shared.buttonTap()
                break
            }
        }
    }

    private func navigateToNextPhoto() {
        guard selectedIndex < metrics.count - 1 else { return }

        for i in (selectedIndex + 1)..<metrics.count {
            if metrics[i].photoUrl != nil {
                selectedIndex = i
                // HapticManager.shared.buttonTap()
                break
            }
        }
    }
}

// MARK: - Photo Thumbnail Tick

struct PhotoThumbnailTick: View {
    let photoUrl: String?
    let isSelected: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            // Thumbnail container with enhanced size
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 18, height: 18)

            // Photo thumbnail
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())
            } else {
                // Loading indicator
                Circle()
                    .fill(Color.appPrimary.opacity(0.3))
                    .frame(width: 16, height: 16)
            }

            // Selection indicator with glow
            if isSelected {
                Circle()
                    .stroke(Color.appPrimary, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .shadow(color: Color.appPrimary.opacity(0.5), radius: 4, x: 0, y: 0)
            }
        }
        .onAppear {
            loadThumbnail()
        }
    }

    private func loadThumbnail() {
        Task.detached(priority: .userInitiated) {
            guard let url = photoUrl, let thumbnail = await ImageLoader.shared.loadImage(from: url) else { return }

            let thumbnailSize = CGSize(width: 28, height: 28)
            let thumbnailImage = thumbnail.resized(to: thumbnailSize)

            await MainActor.run {
                self.image = thumbnailImage
            }
        }
    }
}

// Helper extension for safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

// Helper extension for image resizing
extension UIImage {
    func resized(to size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
