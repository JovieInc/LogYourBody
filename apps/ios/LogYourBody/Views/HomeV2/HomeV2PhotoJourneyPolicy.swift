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
    static let cropAboveShoulders = "Crop above shoulders"
    static let faceVisible = "Your face is visible in this card."
    static let faceCropped = "Cropped above the shoulders. Your face is not in this card."
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
        guard let delta, abs(delta) >= 0.05 else { return "No change \(period)" }
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
        "Body fat estimated by your \(source)."
    }

    static func bodyFatEstimated(_ text: String) -> String {
        "\(text) estimated"
    }

    static func bodyFatChange(_ points: Double?) -> String {
        guard let points, abs(points) >= 0.05 else { return "Body fat · no change" }
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

    static func span(for dates: [Date], calendar: Calendar = .current) -> DateInterval {
        let sorted = dates.sorted()
        let start = calendar.startOfDay(for: sorted.first ?? Date())
        let last = calendar.startOfDay(for: sorted.last ?? start)
        let minimumEnd = calendar.date(byAdding: .day, value: minimumSpanDays, to: start) ?? last
        let end = max(last, minimumEnd)
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

enum HomeV2TimelapsePolicy {
    static let speeds: [Double] = [0.5, 1, 2]
    static let baseFrameSeconds = 0.6

    static func frameInterval(speed: Double) -> TimeInterval {
        baseFrameSeconds / max(speed, 0.1)
    }

    /// The frame after `index`; nil when the run ends and does not loop.
    static func next(after index: Int, count: Int, loops: Bool) -> Int? {
        guard count > 0 else { return nil }
        if index + 1 < count { return index + 1 }
        return loops ? 0 : nil
    }
}

/// Which two photos a share or compare is about.
struct HomeV2PhotoPair: Identifiable, Equatable {
    let before: Int
    let after: Int
    var id: String { "\(before)-\(after)" }
}
