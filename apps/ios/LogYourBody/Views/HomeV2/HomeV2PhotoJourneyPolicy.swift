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

    struct CalendarLabel: Equatable {
        let date: Date
        let text: String
        /// Logical left-to-right display position after edge clamping. The view
        /// mirrors this once for RTL; spacing is verified in this same space.
        let position: CGFloat
    }

    /// A display projection only: every original date remains in the selection
    /// array. Density depends on available points, never the history's age/count.
    struct RenderPlan {
        let entryIndices: [Int]
        let minorTicks: [Date]
        let majorTicks: [Date]
        let labels: [CalendarLabel]
    }

    static func renderPlan(
        dates: [Date],
        selected: Int,
        span: DateInterval,
        width: CGFloat,
        minimumTickSpacing: CGFloat = 6,
        minimumLabelSpacing: CGFloat = 72,
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> RenderPlan {
        // Invalid/transient layout sizes must not create an unbounded allocation.
        // Cap the density budget, while label positions use the actual valid
        // drawing width so unusually wide containers still align with their ticks.
        let drawingWidth = width.isFinite ? max(width, 0) : 0
        let width = min(drawingWidth, 4_096)
        let tickSpacing = minimumTickSpacing.isFinite ? max(minimumTickSpacing, 2) : 6
        let labelSpacing = minimumLabelSpacing.isFinite ? max(minimumLabelSpacing, 24) : 72
        let entryBudget = max(1, Int(width / tickSpacing))
        var buckets: [Int: Int] = [:]
        for index in dates.indices {
            let bucket = min(entryBudget - 1, Int(fraction(of: dates[index], in: span) * CGFloat(entryBudget)))
            // Keep the original input order for coincident observations. The
            // selected observation always owns its bucket, even in dense history.
            if buckets[bucket] == nil || index == selected { buckets[bucket] = index }
        }

        let major = calendarTicks(in: span, budget: Int(width / 48), startsAtWeek: false, calendar: calendar)
        let majorSet = Set(major.dates)
        let minor = calendarTicks(in: span, budget: Int(width / 12), startsAtWeek: true, calendar: calendar)
        let labels = calendarTicks(in: span, budget: Int(width / labelSpacing), startsAtWeek: false, calendar: calendar)
        let crossesYear = calendar.component(.year, from: span.start) != calendar.component(.year, from: span.end)
        let dateTemplate = labels.isYear ? "yyyy" : (crossesYear ? "MMM yyyy" : "MMM")
        return RenderPlan(
            entryIndices: buckets.keys.sorted().compactMap { buckets[$0] },
            minorTicks: minor.dates.filter { !majorSet.contains($0) },
            majorTicks: major.dates,
            labels: positionedLabels(
                dates: labels.dates, span: span, width: drawingWidth, minimumLabelSpacing: labelSpacing,
                dateTemplate: dateTemplate, calendar: calendar, locale: locale
            )
        )
    }

    /// Candidate dates can be well spaced before an edge label is clamped into
    /// view. Retain labels only when their actual displayed centers remain apart
    /// by a complete label frame. All dates remain available for tick selection.
    static func positionedLabels(
        dates: [Date],
        span: DateInterval,
        width: CGFloat,
        minimumLabelSpacing: CGFloat,
        dateTemplate: String = "MMM",
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [CalendarLabel] {
        let width = width.isFinite ? max(width, 0) : 0
        guard width > 0 else { return [] }
        let spacing = minimumLabelSpacing.isFinite ? max(minimumLabelSpacing, 24) : 72
        let halfWidth = min(spacing, width) / 2
        var labels: [CalendarLabel] = []
        for date in dates.sorted() {
            let rawPosition = fraction(of: date, in: span) * width
            let position = min(max(rawPosition, halfWidth), max(halfWidth, width - halfWidth))
            if let previous = labels.last, position - previous.position < spacing { continue }
            labels.append(CalendarLabel(
                date: date,
                text: labelFormatters.string(from: date, template: dateTemplate, calendar: calendar, locale: locale),
                position: position
            ))
        }
        return labels
    }

    /// A fixed-size cache avoids formatter allocation on every scrub. Access and
    /// formatting share a lock so mutable DateFormatter instances never escape.
    private static let labelFormatters = LabelFormatterCache()

    private final class LabelFormatterCache: @unchecked Sendable {
        private struct Key: Hashable {
            let template: String
            let calendar: Calendar
            let localeIdentifier: String
        }

        private let lock = NSLock()
        private var formatters: [Key: DateFormatter] = [:]
        private var insertionOrder: [Key] = []
        private let capacity = 8

        func string(from date: Date, template: String, calendar: Calendar, locale: Locale) -> String {
            lock.lock()
            defer { lock.unlock() }
            let key = Key(template: template, calendar: calendar, localeIdentifier: locale.identifier)
            if let formatter = formatters[key] { return formatter.string(from: date) }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
            formatter.setLocalizedDateFormatFromTemplate(template)
            if insertionOrder.count == capacity {
                formatters.removeValue(forKey: insertionOrder.removeFirst())
            }
            insertionOrder.append(key)
            formatters[key] = formatter
            return formatter.string(from: date)
        }
    }

    /// Gesture coordinates and visual positions use the same direction. VoiceOver
    /// increment/decrement still walks the complete chronological source array.
    static func logicalFraction(at position: CGFloat, width: CGFloat, isRightToLeft: Bool = false) -> CGFloat {
        guard width.isFinite, width > 0, position.isFinite else { return 0 }
        let fraction = min(max(position / width, 0), 1)
        return isRightToLeft ? 1 - fraction : fraction
    }

    private struct CalendarStride {
        let component: Calendar.Component
        let count: Int
    }

    /// Choose the calendar stride before iterating. We never construct thousands
    /// of weeks/months and then discard most of them after layout.
    private static func calendarTicks(
        in span: DateInterval, budget: Int, startsAtWeek: Bool, calendar: Calendar
    ) -> (dates: [Date], isYear: Bool) {
        guard budget > 0 else { return ([], false) }
        let candidates = (startsAtWeek ? [CalendarStride(component: .weekOfYear, count: 1),
                                          CalendarStride(component: .weekOfYear, count: 2)
                ] : []) + [1, 2, 3, 6].map { CalendarStride(component: .month, count: $0) } +
            [1, 2, 5, 10, 20, 50, 100, 200, 500, 1_000, 10_000].map { CalendarStride(component: .year, count: $0) }
        let stride = candidates.first {
                let units =
                    calendar.dateComponents([$0.component], from: span.start, to: span.end).value(for: $0.component)
                    ?? Int.max
                return units >= 0 && units / $0.count < max(1, budget - 1)
        } ?? CalendarStride(component: .year, count: 10_000)
        guard var cursor = calendar.dateInterval(of: stride.component, for: span.start)?.start else {
            return ([], stride.component == .year)
        }
        if cursor < span.start {
            guard let next = calendar.date(byAdding: stride.component, value: stride.count, to: cursor), next > cursor else {
                return ([], stride.component == .year)
            }
            cursor = next
        }
        var ticks: [Date] = []
        while cursor <= span.end, ticks.count < budget {
            ticks.append(cursor)
            guard let next = calendar.date(byAdding: stride.component, value: stride.count, to: cursor), next > cursor
            else { break }
            cursor = next
        }
        return (ticks, stride.component == .year)
    }

    static func span(for dates: [Date], calendar: Calendar = .current, now: Date = Date()) -> DateInterval {
        let end = dates.max() ?? now
        let first = dates.min() ?? end
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

enum HomeV2TimelapsePolicy {
    static let speeds: [Double] = [0.5, 1, 2]
    static let baseFrameSeconds = 0.6

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
