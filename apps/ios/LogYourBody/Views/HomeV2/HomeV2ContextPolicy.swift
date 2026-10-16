//
// HomeV2ContextPolicy.swift
// LogYourBody
//
import Combine
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

    static func detailedLabel(for metric: BodyMetrics) -> String {
        let named = metric.sourceMetadata?.sourceName?.trimmingCharacters(in: .whitespaces)
        if metric.metricSource == .manual, let named, !named.isEmpty {
            let cameThroughHealth = metric.sourceMetadata?.sourceBundleId != nil ||
                metric.sourceMetadata?.quantityType != nil ||
                metric.sourceMetadata?.vendor?.lowercased() == "healthkit"
            let original = cameThroughHealth ? "\(named) via \(HomeV2ContextCopy.appleHealth)" : named
            return "\(original) · corrected in LogYourBody"
        }

        let label = label(for: metric)
        guard metric.metricSource == .healthKit,
              label != HomeV2ContextCopy.appleHealth else { return label }
        return "\(label) via \(HomeV2ContextCopy.appleHealth)"
    }

    /// The time of day an entry was stored, or nil for midnight (a date-only entry).
    static func timeText(for date: Date, calendar: Calendar = .current) -> String? {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        guard (components.hour ?? 0) != 0 || (components.minute ?? 0) != 0 else { return nil }
        return timeFormatter.string(from: date)
    }

    /// "Apple Health, 7:02 AM" or just "Apple Health".
    static func subline(for metric: BodyMetrics, calendar: Calendar = .current) -> String {
        let source = detailedLabel(for: metric)
        guard let time = timeText(for: metric.date, calendar: calendar) else { return source }
        return "\(source), \(time)"
    }

    static func weightSubline(for metric: BodyMetrics, calendar: Calendar = .current) -> String {
        let provenance = subline(for: metric, calendar: calendar)
        guard !HomeV2WeightQuality.isWithinSupportedLoggingRange(metric.weight) else { return provenance }
        return "\(provenance). \(HomeV2WeightQuality.reviewMessage)"
    }

    static func weightText(displayValue: Double, metric: BodyMetrics, unit: String) -> String {
        let value = HomeV2WeightQuality.isWithinSupportedLoggingRange(metric.weight)
            ? HomeV2WeightStepPolicy.text(displayValue)
            : String(format: "%.2f", displayValue)
        return "\(value) \(unit)"
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

/// A correction replaces only the selected record's measurements. Its stable
/// identity, original timestamp, and import lineage remain available in Context.
enum HomeV2CorrectionPolicy {
    static func correctedMetric(
        _ metric: BodyMetrics,
        kilograms: Double,
        bodyFatPercentage: Double?,
        updatedAt: Date = Date()
    ) -> BodyMetrics {
        let bodyFatMethod: String? = if bodyFatPercentage == nil {
            nil
        } else if metric.bodyFatPercentage != nil {
            metric.bodyFatMethod
        } else {
            BodyFatEntryMethod.bioelectrical.rawValue
        }

        return BodyMetrics(
            id: metric.id,
            userId: metric.userId,
            date: metric.date,
            localDate: metric.localDate,
            weight: kilograms,
            weightUnit: metric.weightUnit,
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatMethod,
            muscleMass: metric.muscleMass,
            boneMass: metric.boneMass,
            waistCm: metric.waistCm,
            hipCm: metric.hipCm,
            waistUnit: metric.waistUnit,
            notes: metric.notes,
            photoUrl: metric.photoUrl,
            dataSource: metric.metricSource == .manual ? metric.dataSource : BodyMetricSource.manual.rawValue,
            sourceMetadata: metric.sourceMetadata,
            createdAt: metric.createdAt,
            updatedAt: updatedAt
        )
    }
}

/// One row in Context's entries table.
struct HomeV2DayEntryRow: Identifiable, Equatable {
    let id: String
    let label: String
    let subline: String
    let value: String

    /// A recorded zero is a value; absent and invalid counts do not create a row.
    static func steps(_ value: Int?) -> HomeV2DayEntryRow? {
        guard let value, value >= 0 else { return nil }
        return HomeV2DayEntryRow(
            id: "steps",
            label: HomeV2ContextCopy.steps,
            subline: HomeV2ContextCopy.appleHealth,
            value: FormatterCache.stepsFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
        )
    }
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
        let monthsNewestFirst = grouped.keys.sorted {
            $0.compare($1, options: .numeric) == .orderedDescending
        }
        return monthsNewestFirst.compactMap { key -> HomeV2EntriesSection? in
            guard let monthMetrics = grouped[key], let newest = monthMetrics.first else { return nil }
            let chronological: [Double] = monthMetrics.reversed().compactMap { metric -> Double? in
                guard HomeV2WeightQuality.isWithinSupportedLoggingRange(metric.weight) else { return nil }
                return weightValue(metric)
            }
            let rows = monthMetrics.map { metric -> HomeV2EntriesRow in
                let value = weightValue(metric).map {
                    HomeV2Provenance.weightText(displayValue: $0, metric: metric, unit: unit)
                } ?? "—"
                return HomeV2EntriesRow(
                    id: metric.id,
                    date: metric.date,
                    dayText: HomeV2ContextCopy.entryDateText(metric.date, calendar: calendar),
                    source: metric.weight == nil
                        ? HomeV2Provenance.subline(for: metric, calendar: calendar)
                        : HomeV2Provenance.weightSubline(for: metric, calendar: calendar),
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

/// Reads the selected calendar day independently of the dashboard's recent-history cache.
@MainActor
final class HomeV2DailyStepsReader: ObservableObject {
    struct Key: Hashable {
        let ownership: AuthManager.ProfileSessionOwnership
        let day: Date
    }

    enum State: Equatable {
        case loading
        case missing
        case value(Int)
    }

    struct Snapshot: Equatable {
        let key: Key
        let state: State
    }

    typealias Fetch = @MainActor (String, Date, Date) async -> [DailyMetrics]
    typealias OwnsSession = @MainActor (AuthManager.ProfileSessionOwnership) -> Bool

    @Published private(set) var snapshot: Snapshot?
    private let calendar: Calendar
    private let fetch: Fetch
    private var requestID: UUID?

    init(calendar: Calendar = .current, fetch: Fetch? = nil) {
        self.calendar = calendar
        self.fetch = fetch ?? { owner, start, end in
            await Self.readStoredMetrics(for: owner, from: start, to: end)
        }
    }

    func key(for metric: BodyMetrics, ownership: AuthManager.ProfileSessionOwnership?) -> Key? {
        guard let ownership, metric.userId == ownership.subject else { return nil }
        return key(for: metric.date, ownership: ownership)
    }

    func key(for date: Date, ownership: AuthManager.ProfileSessionOwnership?) -> Key? {
        ownership.map { Key(ownership: $0, day: calendar.startOfDay(for: date)) }
    }

    /// Rechecks ownership at render time, before a replacement task necessarily starts.
    func state(
        for metric: BodyMetrics,
        ownership: AuthManager.ProfileSessionOwnership?,
        ownsSession: OwnsSession
    ) -> State {
        guard key(for: metric, ownership: ownership) != nil else { return .missing }
        return state(for: metric.date, ownership: ownership, ownsSession: ownsSession)
    }

    func state(
        for date: Date,
        ownership: AuthManager.ProfileSessionOwnership?,
        ownsSession: OwnsSession
    ) -> State {
        guard let key = key(for: date, ownership: ownership), ownsSession(key.ownership) else { return .missing }
        guard snapshot?.key == key else { return .loading }
        return snapshot?.state ?? .loading
    }

    func load(
        metric: BodyMetrics,
        ownership: AuthManager.ProfileSessionOwnership,
        ownsSession: OwnsSession
    ) async {
        guard metric.userId == ownership.subject else { return }
        await load(date: metric.date, ownership: ownership, ownsSession: ownsSession)
    }

    func load(
        date: Date,
        ownership: AuthManager.ProfileSessionOwnership,
        ownsSession: OwnsSession
    ) async {
        guard !Task.isCancelled,
              let key = key(for: date, ownership: ownership),
              ownsSession(ownership),
              let end = calendar.date(byAdding: .day, value: 1, to: key.day) else { return }
        let request = UUID()
        requestID = request
        snapshot = Snapshot(key: key, state: .loading)
        let rows = await fetch(ownership.subject, key.day, end)
        guard !Task.isCancelled, requestID == request, ownsSession(ownership) else { return }

        // The range API includes its upper bound; exclude the following day's midnight.
        let newest = rows.filter {
            $0.userId == ownership.subject && $0.date >= key.day && $0.date < end
        }.max {
            $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt < $1.updatedAt
        }
        let state: State
        if let steps = newest?.steps, steps >= 0 {
            state = .value(steps)
        } else {
            state = .missing
        }
        snapshot = Snapshot(key: key, state: state)
    }

    static func readStoredMetrics(
        for owner: String,
        from start: Date,
        to end: Date,
        coreDataManager: CoreDataManager = .shared
    ) async -> [DailyMetrics] {
        let rows = await coreDataManager.fetchDailyMetrics(for: owner, from: start, to: end)
        return rows.compactMap { row in
            guard let id = row.id, let userId = row.userId, let date = row.date else { return nil }
            // Legacy writers store both nil and a real zero as 0. Preserve the
            // canonical missing-value interpretation until storage records presence.
            return DailyMetrics(
                id: id,
                userId: userId,
                date: date,
                steps: row.steps > 0 ? Int(row.steps) : nil,
                notes: row.notes,
                createdAt: row.createdAt ?? date,
                updatedAt: row.updatedAt ?? row.createdAt ?? date
            )
        }
    }
}
