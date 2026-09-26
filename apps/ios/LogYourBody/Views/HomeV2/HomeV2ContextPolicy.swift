//
// HomeV2ContextPolicy.swift
// LogYourBody
//
import Foundation

/// Copy for Context (Pencil N2), Entries (E0), Edit entry (E1) and the
/// delete confirmation (E2). Deletion scope is always spelled out.
enum HomeV2ContextCopy {
    static let editEntry = "Edit entry"
    static let saveChanges = "Save changes"
    static let deleteEntry = "Delete entry"
    static let deleteTitle = "Delete this entry?"
    static let deleteFailed = "The entry could not be deleted. Try again."
    static let cancel = "Cancel"
    static let entries = "Entries"
    static let addPhoto = "Add"
    static let nothingLogged = "Nothing logged this day"
    static let estimated = "Estimated"
    static let typed = "Typed"
    static let appleHealth = "Apple Health"
    static let weight = "Weight"
    static let bodyFat = "Body fat"
    static let ffmi = "FFMI"
    static let leanMass = "Lean mass"
    static let steps = "Steps"

    static func deleteBody(date: String, includesPhoto: Bool) -> String {
        let scope = includesPhoto
            ? "Removes this day's entry for \(date), including its photo."
            : "Removes the weight and body fat logged for \(date)."
        return "\(scope) Nothing is deleted from Apple Health."
    }

    /// Month summary in Entries: "Down 2.5 lb". Nil when the month has one weight or none.
    static func monthDelta(first: Double?, last: Double?, unit: String) -> String? {
        guard let first, let last else { return nil }
        let delta = last - first
        guard abs(delta) >= 0.05 else { return "No change" }
        return "\(delta < 0 ? "Down" : "Up") \(String(format: "%.1f", abs(delta))) \(unit)"
    }

    /// "Thu, Sep 25, 7:02 AM", or "Thu, Sep 25" for an entry stored at midnight.
    static func entryDateText(_ date: Date, calendar: Calendar = .current) -> String {
        let dayText = dayFormatter.string(from: date)
        guard let time = HomeV2Provenance.timeText(for: date, calendar: calendar) else { return dayText }
        return "\(dayText), \(time)"
    }

    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    static let monthYearTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    static let weekdayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter
    }()

    static func monthTitle(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        calendar.isDate(date, equalTo: now, toGranularity: .year)
            ? monthTitle.string(from: date)
            : monthYearTitle.string(from: date)
    }
}

/// Where a number came from, in the words the design uses: measured
/// sources by name, typed values as "Typed", derived values as "Estimated".
enum HomeV2Provenance {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    static func label(for metric: BodyMetrics) -> String {
        let named = metric.sourceMetadata?.sourceName?.trimmingCharacters(in: .whitespaces)
        switch metric.metricSource {
        case .healthKit:
            return (named?.isEmpty == false ? named : nil) ?? HomeV2ContextCopy.appleHealth
        case .smartScale:
            return (named?.isEmpty == false ? named : nil) ?? "Smart scale"
        case .bodySpecDexa:
            return "BodySpec DEXA"
        case .caliper:
            return "Calipers"
        case .photo:
            return "Photo"
        default:
            return HomeV2ContextCopy.typed
        }
    }

    /// The time of day an entry was stored, or nil for midnight (a date-only entry).
    static func timeText(for date: Date, calendar: Calendar = .current) -> String? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 else { return nil }
        return timeFormatter.string(from: date)
    }

    /// "Apple Health, 7:02 AM" or just "Apple Health".
    static func subline(for metric: BodyMetrics, calendar: Calendar = .current) -> String {
        let source = label(for: metric)
        guard let time = timeText(for: metric.date, calendar: calendar) else { return source }
        return "\(source), \(time)"
    }

    /// Body fat names its method when that is more specific than the source.
    static func bodyFatSubline(for metric: BodyMetrics, calendar: Calendar = .current) -> String {
        switch metric.bodyFatMethod {
        case "dexa": return "DEXA"
        case "caliper": return "Calipers"
        default: return subline(for: metric, calendar: calendar)
        }
    }
}

/// One row in Context's entries table.
struct HomeV2DayEntryRow: Identifiable, Equatable {
    let id: String
    let label: String
    let subline: String
    let value: String
}

/// Everything Context shows for one day.
struct HomeV2DayDetail {
    let date: Date
    let metric: BodyMetrics?
    let rows: [HomeV2DayEntryRow]
    let note: String?
    let photoURL: String?
}

/// The week strip: the seven days of the week containing a date, in the
/// calendar's week order.
enum HomeV2WeekStrip {
    static func days(containing date: Date, calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: date)
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: start) else { return [start] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    static func weekdayLetter(for date: Date, calendar: Calendar = .current) -> String {
        let index = calendar.component(.weekday, from: date) - 1
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}

/// Entries (E0): one section per month, newest first, with the month's change.
struct HomeV2EntriesRow: Identifiable, Equatable {
    let id: String
    let date: Date
    let dayText: String
    let source: String
    let valueText: String
    let photoURL: String?
}

struct HomeV2EntriesSection: Identifiable, Equatable {
    let id: String
    let title: String
    let delta: String?
    let rows: [HomeV2EntriesRow]
}

enum HomeV2EntriesPolicy {
    static func sections(
        metrics: [BodyMetrics],
        unit: String,
        weightValue: (BodyMetrics) -> Double?,
        hasPhoto: (BodyMetrics) -> Bool,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [HomeV2EntriesSection] {
        let shown = metrics
            .filter { $0.weight != nil || hasPhoto($0) }
            .sorted { $0.date > $1.date }
        let grouped = Dictionary(grouping: shown) { metric -> String in
            let parts = calendar.dateComponents([.year, .month], from: metric.date)
            return "\(parts.year ?? 0)-\(parts.month ?? 0)"
        }
        return grouped.keys.sorted(by: >).compactMap { key -> HomeV2EntriesSection? in
            guard let monthMetrics = grouped[key], let newest = monthMetrics.first else { return nil }
            let chronological = monthMetrics.reversed().compactMap(weightValue)
            let rows = monthMetrics.map { metric -> HomeV2EntriesRow in
                let value = weightValue(metric).map { "\(HomeV2WeightStepPolicy.text($0)) \(unit)" } ?? "—"
                return HomeV2EntriesRow(
                    id: metric.id,
                    date: metric.date,
                    dayText: HomeV2ContextCopy.weekdayDayFormatter.string(from: metric.date),
                    source: HomeV2Provenance.label(for: metric),
                    valueText: value,
                    photoURL: hasPhoto(metric) ? metric.photoUrl : nil
                )
            }
            return HomeV2EntriesSection(
                id: key,
                title: HomeV2ContextCopy.monthTitle(for: newest.date, now: now, calendar: calendar),
                delta: chronological.count > 1
                    ? HomeV2ContextCopy.monthDelta(first: chronological.first, last: chronological.last, unit: unit)
                    : nil,
                rows: rows
            )
        }
    }
}
