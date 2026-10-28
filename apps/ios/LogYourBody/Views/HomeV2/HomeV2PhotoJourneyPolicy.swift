//
// HomeV2PhotoJourneyPolicy.swift
// LogYourBody
//
import CoreGraphics
import Foundation

/// Copy for the photo journey (Pencil P2–P8).
enum HomeV2PhotoCopy {
    static let tools = "Tools"
    static let photoTools = "Photo tools"
    static let done = "Done"
    static let comparePhotos = "Compare photos"
    static let browseTimeline = "Browse timeline"
    static let playTimelapse = "Play timelapse"
    static let allPhotos = "All photos"
    static let shareProgress = "Share progress"
    static let shareBoundary = "Share progress opens a preview. Review what is included before sharing."
    static let photos = "Photos"
    static let tapToOpen = "Tap a photo to open"
    static let chooseBefore = "Choose the before photo"
    static let chooseAfter = "Choose the after photo"
    static let compare = "Compare"
    static let timelapse = "Timelapse"
    static let all = "All"
    static let share = "Share"
    static let cancel = "Cancel"
    static let hideDetails = "Hide details"
    static let cardOptions = "Card options"
    static let showNumbers = "Show numbers"
    static let showDates = "Show dates"
    static let cropPhotoTop = "Crop top of photos"
    static let reviewPhotos = "Check the preview for faces and details you don’t want to share."
    static let croppedPhotoNote = "Top of each photo cropped. Your face may still be visible; check the preview."
    static let brand = "LogYourBody"
    static let changeDates = "Change dates"
    static let slider = "Slider"
    static let sideBySide = "Side by side"
    static let overlay = "Overlay"
    static let weight = "Weight"
    static let estimatedBodyFat = "Est. body fat"
    static let derivedFFMI = "Derived FFMI"
    static let measurementsSeparate = "Measurements are separate from the photo."
    static let speed = "Speed"
    static let loopOff = "Loop off"
    static let loopOn = "Loop on"
    static let preparing = "Preparing photos…"
    static let notEnoughPhotos = "Two photos are needed to compare."
    static let needsAnotherPhoto = "Add another progress photo from Home, then try again."
    static let shareLoadFailed = "Couldn’t load both photos. Try again, or choose different photos."
    static let shareRenderFailed = "Couldn’t prepare the share card. Try again."
    static let retryPhotos = "Retry photos"

    static func insufficientPhotos(for tool: HomeV2PhotoTool) -> String {
        tool == .share ? "Two photos are needed to share progress." : notEnoughPhotos
    }

    static func photoDetails(weight: String) -> String {
        "Photo details · \(weight)"
    }

    static func compareTitle(days: Int) -> String {
        "Compare · \(days) day\(days == 1 ? "" : "s")"
    }

    static func timelapseSubtitle(from: String, to: String, count: Int) -> String {
        "\(from) to \(to), \(count) photo\(count == 1 ? "" : "s")"
    }

    /// "−12.8 lb in 176 days".
    static func cardHeadline(delta: Double?, unit: String, days: Int) -> String {
        let period = "in \(days) day\(days == 1 ? "" : "s")"
        guard let delta, delta.isFinite else { return "Weight change unavailable" }
        guard abs(delta) >= 0.05 else { return "No change \(period)" }
        return "\(signed(delta)) \(unit) \(period)"
    }

    static func bodyFatDeltaLine(_ points: Double?) -> String? {
        guard let points, abs(points) >= 0.05 else { return nil }
        return "\(estimatedBodyFat) \(signed(points)) pts"
    }

    static func bodyFatTransition(from: Double?, to: Double?) -> String? {
        guard let from, let to else { return nil }
        return "Body fat: \(String(format: "%.1f", from))% → \(String(format: "%.1f", to))%"
    }

    static func estimatedBySource(_ source: String) -> String {
        source == HomeV2ContextCopy.typed
            ? "Body fat estimate entered by you."
            : "Body fat estimated by your \(source)."
    }

    static func bodyFatEstimated(_ text: String) -> String {
        "\(text) estimated"
    }

    static func bodyFatChange(_ points: Double?) -> String {
        guard let points, points.isFinite else { return "Body fat · no comparison" }
        guard abs(points) >= 0.05 else { return "Body fat · no change" }
        return "Body fat · \(signed(points)) pts"
    }

    static func playbackSummary(speed: Double, loops: Bool) -> String {
        "Playback · \(speedText(speed)) · \(loops ? loopOn : loopOff)"
    }

    static func speedText(_ speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))×" : "\(speed)×"
    }

    /// "−12.8", "+0.4"; the design's minus is the true minus sign.
    static func signed(_ value: Double, decimals: Int = 1) -> String {
        let magnitude = String(format: "%.\(decimals)f", abs(value))
        return "\(value < 0 ? "−" : "+")\(magnitude)"
    }
}

/// The tools a photo opens (Pencil P8).
enum HomeV2PhotoTool: String, CaseIterable, Identifiable {
    case compare
    case timeline
    case timelapse
    case allPhotos
    case share

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compare: return HomeV2PhotoCopy.comparePhotos
        case .timeline: return HomeV2PhotoCopy.browseTimeline
        case .timelapse: return HomeV2PhotoCopy.playTimelapse
        case .allPhotos: return HomeV2PhotoCopy.allPhotos
        case .share: return HomeV2PhotoCopy.shareProgress
        }
    }

    var shortTitle: String {
        switch self {
        case .compare: return HomeV2PhotoCopy.compare
        case .timeline: return HomeV2PhotoCopy.browseTimeline
        case .timelapse: return HomeV2PhotoCopy.timelapse
        case .allPhotos: return HomeV2PhotoCopy.all
        case .share: return HomeV2PhotoCopy.share
        }
    }

    var systemImage: String {
        switch self {
        case .compare: return "rectangle.split.2x1"
        case .timeline: return "slider.horizontal.below.rectangle"
        case .timelapse: return "play"
        case .allPhotos: return "square.grid.2x2"
        case .share: return "square.and.arrow.up"
        }
    }

    var identifier: String {
        switch self {
        case .compare: return "compare"
        case .timeline: return "timeline"
        case .timelapse: return "timelapse"
        case .allPhotos: return "all_photos"
        case .share: return "share"
        }
    }
}

/// Geometry of the timeline ruler (Pencil P3): weekly ticks across the span
/// of photos, taller ticks at month starts, a tick per photo, one selected.
enum HomeV2PhotoRulerPolicy {
    static let minimumSpanDays = 56

    static func span(for dates: [Date], calendar: Calendar = .current, now: Date = Date()) -> DateInterval {
        let sorted = dates.sorted()
        let end = sorted.last ?? now
        let first = sorted.first ?? end
        // Pad short histories backward; the latest timestamp is never future axis space.
        let minimumStart = calendar.date(byAdding: .day, value: -minimumSpanDays, to: end) ?? first
        let start = calendar.startOfDay(for: min(first, minimumStart))
        return DateInterval(start: start, end: max(end, start.addingTimeInterval(1)))
    }

    static func fraction(of date: Date, in span: DateInterval) -> CGFloat {
        guard span.duration > 0 else { return 0 }
        let raw = date.timeIntervalSince(span.start) / span.duration
        return CGFloat(min(max(raw, 0), 1))
    }

    static func weekTicks(in span: DateInterval, calendar: Calendar = .current) -> [Date] {
        var ticks: [Date] = []
        var cursor = span.start
        while cursor <= span.end {
            ticks.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return ticks
    }

    static func monthStarts(in span: DateInterval, calendar: Calendar = .current) -> [Date] {
        var starts: [Date] = []
        var components = calendar.dateComponents([.year, .month], from: span.start)
        components.day = 1
        guard var cursor = calendar.date(from: components) else { return [] }
        if cursor < span.start, let next = calendar.date(byAdding: .month, value: 1, to: cursor) {
            cursor = next
        }
        while cursor <= span.end {
            starts.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return starts
    }

    /// The photo nearest a scrub position.
    static func nearestIndex(to fraction: CGFloat, dates: [Date], span: DateInterval) -> Int? {
        guard !dates.isEmpty else { return nil }
        let target = span.start.addingTimeInterval(Double(fraction) * span.duration)
        return dates.indices.min { abs(dates[$0].timeIntervalSince(target)) < abs(dates[$1].timeIntervalSince(target)) }
    }
}

/// Appearance and hit geometry only; the ruler owns all selection callbacks.
enum HomeV2FilmstripPolicy {
    static let gateKey = "home_v2_glass_filmstrip_v1"
    static let fixtureArgument = "-lybUITestGlassFilmstrip"

    static func canRender(photoURLs: [String?], dateCount: Int) -> Bool {
        photoURLs.count == dateCount && photoURLs.contains {
            !($0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        checkGate: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.contains(fixtureArgument),
           arguments.contains("-lybUITestPhotoTimelineHUDFixture"),
           UUID(uuidString: environment["XCTestSessionIdentifier"] ?? "") != nil,
           environment["XCTestBundlePath"]?.hasSuffix("/LogYourBodyUITests.xctest") == true {
            return true
        }
        #endif
        let check = checkGate ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return check(gateKey)
    }

    struct Layout {
        let count: Int
        let width: CGFloat
        let visibleCount: Int
        let stripWidth: CGFloat

        init?(count: Int, width: CGFloat) {
            guard count > 0, width.isFinite, width > 0 else { return nil }
            self.count = count
            self.width = width
            visibleCount = min(count, Int(min(14, max(1, width / 20))))
            stripWidth = min(width, CGFloat(count) * 28)
        }

        var cellWidth: CGFloat { stripWidth / CGFloat(visibleCount) }
        private var travel: CGFloat { stripWidth - cellWidth }

        /// Bound image work for long histories, retaining both endpoints.
        var indices: [Int] {
            guard visibleCount > 1 else { return [0] }
            return (0..<visibleCount).map {
                Int((Double($0) * Double(count - 1) / Double(visibleCount - 1)).rounded())
            }
        }

        func center(for index: Int, rightToLeft: Bool) -> CGFloat {
            guard count > 1 else { return width / 2 }
            let fraction = CGFloat(min(max(index, 0), count - 1)) / CGFloat(count - 1)
            return (width - travel) / 2 + (rightToLeft ? 1 - fraction : fraction) * travel
        }

        func index(at position: CGFloat, rightToLeft: Bool) -> Int? {
            guard position.isFinite else { return nil }
            guard travel > 0 else { return 0 }
            let fraction = min(max((position - (width - travel) / 2) / travel, 0), 1)
            return Int(((rightToLeft ? 1 - fraction : fraction) * CGFloat(count - 1)).rounded())
        }
    }
}

enum HomeV2TimelapsePolicy {
    static let speeds: [Double] = [0.5, 1, 2]
    static let baseFrameSeconds = 0.6
    static let prefetchGateKey = "home_v2_timelapse_bounded_prefetch_v1"
    static let prefetchFixtureArgument = "-lybUITestTimelapseBoundedPrefetch"

    @MainActor
    static func usesBoundedPrefetch(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.filter({ $0 == prefetchFixtureArgument }).count == 1,
           arguments.contains("-lybUITestPhotoTimelineHUDFixture"),
           arguments.contains(HomeV2Policy.photoFixtureArgument),
           !arguments.contains(HomeV2Policy.rollbackFixtureArgument),
           UUID(uuidString: environment["XCTestSessionIdentifier"] ?? "") != nil,
           environment["XCTestBundlePath"]?.hasSuffix("/LogYourBodyUITests.xctest") == true {
            return true
        }
        #endif
        let check = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return check(prefetchGateKey)
    }

    /// Current photo plus two successors, well below the rendered-plate cache limit.
    static func prefetchFrames(from index: Int, count: Int, loops: Bool) -> [Int] {
        guard (0..<max(0, count)).contains(index) else { return [] }
        var frames = [index]
        while frames.count < min(3, count),
              let following = next(after: frames[frames.count - 1], count: count, loops: loops) {
            frames.append(following)
        }
        return frames
    }

    /// Publish readiness before warming successors. Shared image loads may finish
    /// after cancellation, so never start another load or publish stale readiness.
    @MainActor
    static func prepareWindow(
        from index: Int,
        count: Int,
        loops: Bool,
        load: (Int) async -> Void,
        currentReady: () -> Void
    ) async {
        for frame in prefetchFrames(from: index, count: count, loops: loops) {
            guard !Task.isCancelled else { return }
            await load(frame)
            guard !Task.isCancelled else { return }
            if frame == index { currentReady() }
        }
    }

    static func frameInterval(speed: Double) -> TimeInterval {
        baseFrameSeconds / max(speed, 0.1)
    }

    /// The frame after `index`; nil when the run ends and does not loop.
    static func next(after index: Int, count: Int, loops: Bool) -> Int? {
        guard count >= 1 else { return nil }
        if index + 1 < count { return index + 1 }
        return loops ? 0 : nil
    }
}

/// Preparation must not override a pause or scrub while a shared load finishes.
struct HomeV2TimelapsePlaybackState {
    var frame = 0
    var isPlaying = false
    private(set) var isReady = false
    private var allowsInitialAutoplay = true

    mutating func select(_ selected: Int, needsPreparation: Bool = true) {
        if needsPreparation, frame != selected { isReady = false }
        frame = selected
        isPlaying = false
        allowsInitialAutoplay = false
    }

    mutating func prepared(frame preparedFrame: Int, count: Int) {
        guard preparedFrame == frame else { return }
        isReady = count >= 1
        if allowsInitialAutoplay {
            allowsInitialAutoplay = false
            isPlaying = count > 1
        }
    }

    mutating func togglePlayback() {
        guard isReady else { return }
        allowsInitialAutoplay = false
        isPlaying.toggle()
    }
}

/// Which two photos a share or compare is about.
struct HomeV2PhotoPair: Identifiable, Equatable {
    let before: Int
    let after: Int
    var id: String { "\(before)-\(after)" }
}

/// Removes the top portion before aspect-filling the pane. Scaling the
/// remaining image avoids the empty strip left by translating a fitted image.
enum HomeV2ShareCropPolicy {
    static let topFraction: CGFloat = 0.22

    static func drawRect(imageSize: CGSize, in target: CGSize, cropsTop: Bool) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, target.width > 0, target.height > 0 else {
            return CGRect(origin: .zero, size: target)
        }
        let removedHeight = cropsTop ? imageSize.height * topFraction : 0
        let remainingHeight = imageSize.height - removedHeight
        let scale = max(target.width / imageSize.width, target.height / remainingHeight)
        return CGRect(
            x: (target.width - imageSize.width * scale) / 2,
            y: (target.height - remainingHeight * scale) / 2 - removedHeight * scale,
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }
}
