//
// HomeV2ContextPolicy.swift
// LogYourBody
//
import Combine
import Foundation
import CoreData

/// Present the editorial editor only after explicit rollout or an authenticated test override.
enum HomeV2EntryBodyFatPrimaryPolicy {
    static let gateKey = "home_v2_entry_body_fat_primary_v1"
    static let fixtureArgument = "-lybUITestEntryBodyFatPrimary"
    static let disabledFixtureArgument = "-lybUITestEntryBodyFatPrimaryDisabled"

    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        let enabled = arguments.filter { $0 == fixtureArgument }.count
        let disabled = arguments.filter { $0 == disabledFixtureArgument }.count
        if enabled + disabled == 1,
           arguments.contains("-lybUITestPhotoTimelineHUDFixture"),
           arguments.contains(HomeV2Policy.photoFixtureArgument),
           !arguments.contains(HomeV2Policy.rollbackFixtureArgument),
           UUID(uuidString: environment["XCTestSessionIdentifier"] ?? "") != nil,
           environment["XCTestBundlePath"]?.hasSuffix("/LogYourBodyUITests.xctest") == true {
            return enabled == 1
        }
        #endif
        let check = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return check(gateKey)
    }
}

/// Editing an imported record must not turn a missing or untouched reading into a new measurement.
enum HomeV2EntryEditPolicy {
    static let gateKey = "home_v2_entry_edit_preservation_v1"
    static let fixtureArgument = "-lybUITestHomeEntryEditPreservation"

    @MainActor
    static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isGateEnabled: ((String) -> Bool)? = nil
    ) -> Bool {
        #if DEBUG
        if arguments.filter({ $0 == fixtureArgument }).count == 1,
           arguments.contains("-lybUITestPhotoTimelineHUDFixture"),
           arguments.contains(HomeV2Policy.photoFixtureArgument),
           !arguments.contains(HomeV2Policy.rollbackFixtureArgument),
           UUID(uuidString: environment["XCTestSessionIdentifier"] ?? "") != nil,
           environment["XCTestBundlePath"]?.hasSuffix("/LogYourBodyUITests.xctest") == true {
            return true
        }
        #endif
        let check = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return check(gateKey)
    }

    static func weight(text: String, initialValue: Double?, unit: String, preserving: Bool) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if preserving, initialValue == nil, trimmed.isEmpty { return nil }
        guard let value = HomeV2WeightStepPolicy.parse(trimmed), value.isFinite else {
            throw ValidationError.invalidWeight(HomeV2Copy.weightRangeError(unit: unit))
        }
        if preserving, let initialValue, initialValue.isFinite,
           value == HomeV2WeightStepPolicy.parse(HomeV2WeightStepPolicy.text(initialValue)) {
            return value
        }
        guard HomeV2WeightStepPolicy.range(unit: unit).contains(value) else {
            throw ValidationError.invalidWeight(HomeV2Copy.weightRangeError(unit: unit))
        }
        return value
    }

    static func bodyFat(text: String, initialValue: Double?, preserving: Bool) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if preserving {
            if let initialValue, initialValue.isFinite,
               let value = HomeV2WeightStepPolicy.parse(trimmed),
               value == HomeV2WeightStepPolicy.parse(String(format: "%.1f", initialValue)) {
                return value
            }
            return try ValidationService.shared.validateBodyFat(trimmed)
        }
        guard let value = HomeV2WeightStepPolicy.parse(trimmed),
              HomeV2WeightStepPolicy.bodyFatRange.contains(value) else {
            throw ValidationError.invalidBodyFat(HomeV2Copy.bodyFatRangeError)
        }
        return value
    }
}

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

    static func label(for metric: BodyMetrics, field: BodyMetricField? = nil) -> String {
        let named = metric.sourceMetadata?.sourceName?.trimmingCharacters(in: .whitespaces)
        switch field.map({ metric.measurementSource(for: $0) }) ?? metric.metricSource {
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

    static func detailedLabel(for metric: BodyMetrics, field: BodyMetricField? = nil) -> String {
        if let field, metric.sourceMetadata?.entrySource(for: field) == .manual {
            return HomeV2ContextCopy.typed
        }
        let named = metric.sourceMetadata?.sourceName?.trimmingCharacters(in: .whitespaces)
        if metric.metricSource == .manual, let named, !named.isEmpty {
            // An arbitrary bundle or quantity name does not establish an Apple
            // Health import. Preserve the explicit vendor's recorded lineage.
            let cameThroughHealth = metric.sourceMetadata?.vendor?.lowercased() == "healthkit"
            let original = cameThroughHealth ? "\(named) via \(HomeV2ContextCopy.appleHealth)" : named
            return "\(original) · corrected in LogYourBody"
        }

        let label = label(for: metric, field: field)
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
    static func subline(
        for metric: BodyMetrics, field: BodyMetricField? = nil, calendar: Calendar = .current
    ) -> String {
        let source = detailedLabel(for: metric, field: field)
        guard let time = timeText(for: metric.date, calendar: calendar) else { return source }
        return "\(source), \(time)"
    }

    static func weightSubline(for metric: BodyMetrics, calendar: Calendar = .current) -> String {
        let provenance = subline(for: metric, field: .weight, calendar: calendar)
        guard !HomeV2WeightQuality.isWithinSupportedLoggingRange(metric.weight) else { return provenance }
        return "\(provenance). \(HomeV2WeightQuality.reviewMessage)"
    }

    static func weightText(displayValue: Double, metric: BodyMetrics, unit: String) -> String {
        guard displayValue.isFinite else { return "— \(unit)" }
        let value = HomeV2WeightQuality.isWithinSupportedLoggingRange(metric.weight)
            ? HomeV2WeightStepPolicy.text(displayValue)
            : String(format: "%.2f", displayValue)
        return "\(value) \(unit)"
    }

    /// Body fat names its method when that is more specific than the source.
    static func bodyFatSubline(for metric: BodyMetrics, calendar: Calendar = .current) -> String {
        switch metric.attributedBodyFatMethod {
        case "dexa": return "DEXA"
        case "caliper": return "Calipers"
        default: return subline(for: metric, field: .bodyFat, calendar: calendar)
        }
    }
}

/// Explicit edits preserve untouched raw precision and the existing selected method.
/// No inferred Presentation value is accepted here.
enum HomeV2CorrectionPolicy {
    enum WeightEdit: Equatable { case unchanged, kilograms(Double) }
    enum BodyFatEdit: Equatable { case unchanged, reading(Double, method: String?), clear }
    struct Changes: Equatable {
        var weight: WeightEdit = .unchanged
        var bodyFat: BodyFatEdit = .unchanged
        var isEmpty: Bool { weight == .unchanged && bodyFat == .unchanged }
    }
    enum EditError: Error { case weight, bodyFat, staleRecord }

    static func isEditorCurrent(
        original: AuthManager.ProfileSessionOwnership?, current: AuthManager.ProfileSessionOwnership?
    ) -> Bool {
        guard let original, !original.subject.isEmpty else { return false }
        return current == original
    }

    struct BodyFatInput {
        let text: String
        let wasEdited: Bool
        let original: Double?
        let method: String?
        let originalMethod: String?
    }

    static func changes(
        weightText: String, weightWasEdited: Bool, unit: String, bodyFat input: BodyFatInput
    ) throws -> Changes {
        let bodyFatText = input.text
        let bodyFatWasEdited = input.wasEdited
        let originalBodyFat = input.original
        let method = input.method
        let originalMethod = input.originalMethod
        var result = Changes()
        if weightWasEdited {
            guard let value = HomeV2WeightStepPolicy.parse(weightText), value.isFinite,
                  HomeV2WeightStepPolicy.range(unit: unit).contains(value) else { throw EditError.weight }
            result.weight = .kilograms(unit == "lb" ? value.lbsToKg : value)
        }
        if bodyFatWasEdited {
            if bodyFatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if originalBodyFat != nil { result.bodyFat = .clear }
            } else {
                guard let value = HomeV2WeightStepPolicy.parse(bodyFatText), value.isFinite,
                      HomeV2WeightStepPolicy.bodyFatRange.contains(value) else { throw EditError.bodyFat }
                result.bodyFat = .reading(value, method: method)
            }
        } else if method != originalMethod, let originalBodyFat {
            result.bodyFat = .reading(originalBodyFat, method: method)
        }
        return result
    }

    static func correctedMetric(
        _ metric: BodyMetrics, changes: Changes, updatedAt: Date = Date()
    ) -> BodyMetrics {
        guard !changes.isEmpty else { return metric }
        let weight: Double?
        switch changes.weight {
        case .unchanged: weight = metric.weight
        case .kilograms(let value): weight = value
        }
        let bodyFat: Double?
        let method: String?
        switch changes.bodyFat {
        case .unchanged: bodyFat = metric.bodyFatPercentage; method = metric.bodyFatMethod
        case .reading(let value, let selectedMethod): bodyFat = value; method = selectedMethod
        case .clear: bodyFat = nil; method = nil
        }
        var changedFields: Set<BodyMetricField> = []
        if case .kilograms(let value) = changes.weight, value != metric.weight { changedFields.insert(.weight) }
        switch changes.bodyFat {
        case .unchanged: break
        case .clear:
            if metric.bodyFatPercentage != nil || metric.bodyFatMethod != nil { changedFields.insert(.bodyFat) }
        case .reading(let value, let selectedMethod):
            if value != metric.bodyFatPercentage || selectedMethod != metric.bodyFatMethod ||
                selectedMethod != metric.attributedBodyFatMethod { changedFields.insert(.bodyFat) }
        }
        let metadata = changedFields.isEmpty ? metric.sourceMetadata :
            (metric.sourceMetadata ?? BodyMetricSourceMetadata()).settingEntrySource(
                .manual, fields: changedFields, bodyFatMethod: method
            )
        return BodyMetrics(
            id: metric.id, userId: metric.userId, date: metric.date, localDate: metric.localDate,
            weight: weight,
            weightUnit: changedFields.contains(.weight) ? "kg" : metric.weightUnit,
            bodyFatPercentage: bodyFat, bodyFatMethod: method,
            muscleMass: metric.muscleMass, boneMass: metric.boneMass,
            waistCm: metric.waistCm, hipCm: metric.hipCm, waistUnit: metric.waistUnit,
            notes: metric.notes, photoUrl: metric.photoUrl,
            dataSource: metric.dataSource,
            sourceMetadata: metadata, createdAt: metric.createdAt, updatedAt: updatedAt
        )
    }

    /// Compatibility for current-main callers; explicit editor intent uses Changes above.
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

        var changedFields: Set<BodyMetricField> = []
        if kilograms != metric.weight { changedFields.insert(.weight) }
        if bodyFatPercentage != metric.bodyFatPercentage { changedFields.insert(.bodyFat) }
        let metadata = changedFields.isEmpty ? metric.sourceMetadata :
            (metric.sourceMetadata ?? BodyMetricSourceMetadata()).settingEntrySource(.manual, fields: changedFields)
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
            dataSource: metric.dataSource,
            sourceMetadata: metadata,
            createdAt: metric.createdAt,
            updatedAt: updatedAt
        )
    }

    /// Compatibility entry point using the same existing-record transaction writer.
    @MainActor
    static func persistCorrection(
        _ corrected: BodyMetrics, replacing original: BodyMetrics,
        store: CoreDataManager, admission: @escaping CoreDataManager.WriteAdmission
    ) async throws {
        var changes = Changes()
        if corrected.weight != original.weight {
            guard let kilograms = corrected.weight else { throw EditError.weight }
            changes.weight = .kilograms(kilograms)
        }
        if corrected.bodyFatPercentage != original.bodyFatPercentage ||
            corrected.bodyFatMethod != original.bodyFatMethod ||
            corrected.attributedBodyFatMethod != original.attributedBodyFatMethod {
            changes.bodyFat = corrected.bodyFatPercentage.map { .reading($0, method: corrected.bodyFatMethod) } ?? .clear
        }
        _ = try await persistCorrectionReturningStored(
            corrected, replacing: original, changes: changes, store: store,
            admission: admission, onStored: { _ in }
        )
    }

    /// Read on the existing main-queue viewContext, with the writer's id-only candidate set.
    @MainActor
    static func storedMetric(
        _ expected: BodyMetrics, store: CoreDataManager
    ) throws -> BodyMetrics {
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", expected.id)
        let rows = try store.viewContext.fetch(request)
        guard rows.count == 1, let row = rows.first, !row.isMarkedDeleted,
              !row.isDeleted, !row.isInserted, !row.isUpdated,
              let stored = row.toBodyMetrics(), stored == expected else { throw EditError.staleRecord }
        return stored
    }

    /// Map explicit Home intent into the maintained separate-transaction writer.
    /// The writer validates the actual full preimage and both admissions inside
    /// its queue, then supplies actual committed DTOs before returning.
    @MainActor
    static func persistCorrectionReturningStored(
        _ corrected: BodyMetrics, replacing original: BodyMetrics, changes: Changes,
        store: CoreDataManager, admission: @escaping CoreDataManager.WriteAdmission,
        onStored: @escaping @MainActor (BodyMetrics) throws -> Void,
        onCommitted: (@MainActor (PhotoMetricsUpdateResult) throws -> Void)? = nil,
        onWriterAdmission: (@MainActor (Result<Void, Error>) -> Void)? = nil
    ) async throws -> BodyMetrics {
        let kilograms: Double?
        switch changes.weight {
        case .unchanged: kilograms = nil
        case .kilograms(let value): kilograms = value
        }
        let bodyFat: Double?
        let method: String?
        let clearBodyFat: Bool
        let replaceBodyFatMethod: Bool
        switch changes.bodyFat {
        case .unchanged:
            bodyFat = nil; method = nil; clearBodyFat = false; replaceBodyFatMethod = false
        case .reading(let value, let selectedMethod):
            bodyFat = value; method = selectedMethod; clearBodyFat = false; replaceBodyFatMethod = true
        case .clear:
            bodyFat = nil; method = nil; clearBodyFat = true; replaceBodyFatMethod = true
        }
        // No outer pre-admission hides a resumed held request from the writer's
        // one final observer. The writer owns expectedOriginal and cancellation.
        let result = try await store.updateExistingMetricMeasurementsAndWait(
            id: original.id, userId: original.userId, weight: kilograms,
            bodyFatPercentage: bodyFat, bodyFatMethod: method, clearBodyFat: clearBodyFat,
            markManualCorrection: !changes.isEmpty, replaceBodyFatMethod: replaceBodyFatMethod,
            expectedOriginal: original, writeAdmission: admission,
            onStored: { result in
                let stored = result.metrics
                guard !result.createdNewEntry, result.previousMetric == original,
                      stored == correctedMetric(original, changes: changes, updatedAt: stored.updatedAt) else {
                    throw EditError.staleRecord
                }
                try onStored(stored)
                try onCommitted?(result)
            }, onWriterAdmission: onWriterAdmission
        )
        _ = corrected // A proposed DTO never substitutes for the writer's stored result.
        return result.metrics
    }

    /// The one original receipt and cancellation latch fence the queued write AND later completion.
    @MainActor
    static func save(
        _ original: BodyMetrics, changes: Changes,
        ownership: AuthManager.ProfileSessionOwnership?,
        ownsSession: @escaping @MainActor (AuthManager.ProfileSessionOwnership) -> Bool,
        persist: @escaping @MainActor (BodyMetrics, @escaping CoreDataManager.WriteAdmission) async throws -> Void,
        didSave: @escaping @MainActor (BodyMetrics, @escaping @MainActor () -> Bool) async -> Void
    ) async -> Bool {
        guard let ownership, !ownership.subject.isEmpty, original.userId == ownership.subject,
              !Task.isCancelled, ownsSession(ownership) else { return false }
        if changes.isEmpty { return true }
        // Explicit intent can still retain every raw value and attribution. A
        // new timestamp alone must not trigger persistence or save side effects.
        if correctedMetric(original, changes: changes, updatedAt: original.updatedAt) == original { return true }
        let cancellation = HealthKitImportCancellation()
        let canPublish: @MainActor () -> Bool = {
            !cancellation.isCancelled && !Task.isCancelled && ownsSession(ownership)
        }
        let admission: CoreDataManager.WriteAdmission = {
            guard canPublish() else { throw CancellationError() }
        }
        let corrected = correctedMetric(original, changes: changes)
        return await withTaskCancellationHandler {
            do {
                try admission()
                try await persist(corrected, admission)
                guard canPublish() else { return false }
                await didSave(corrected, canPublish)
                return canPublish()
            } catch {
                return false
            }
        } onCancel: {
            cancellation.cancel()
        }
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
struct HomeV2ContextRoute: Equatable {
    let id: UUID
    let metric: BodyMetrics?
    let ownership: AuthManager.ProfileSessionOwnership

    init(id: UUID = UUID(), metric: BodyMetrics?, ownership: AuthManager.ProfileSessionOwnership) {
        self.id = id
        self.metric = metric
        self.ownership = ownership
    }
}

/// Frozen by the mounted editor, not recaptured from a re-evaluated parent Save closure.
struct HomeV2CorrectionReturnReceipt: Equatable {
    let destination: HomeV2ContextRoute
    let editorLifetime: UUID
}

/// Only the actual writer-completion postimage may bridge the old and refreshed arrays.
struct HomeV2CorrectionReturnBridge {
    let receipt: HomeV2CorrectionReturnReceipt
    let stored: BodyMetrics

    func owns(_ candidate: HomeV2CorrectionReturnReceipt) -> Bool { receipt == candidate }

    var destination: HomeV2ContextRoute {
        HomeV2ContextRoute(id: receipt.destination.id, metric: stored, ownership: receipt.destination.ownership)
    }

    func admits(
        current: HomeV2ContextRoute?, metrics: [BodyMetrics],
        currentOwnership: AuthManager.ProfileSessionOwnership?
    ) -> Bool {
        guard let original = receipt.destination.metric, current == destination,
              currentOwnership == receipt.destination.ownership,
              !receipt.destination.ownership.subject.isEmpty,
              stored.id == original.id, stored.userId == original.userId, stored.date == original.date else { return false }
        let matches = metrics.filter { $0.id == stored.id }
        return matches.count == 1 && (matches[0] == original || matches[0] == stored)
    }

    func completed(
        current: HomeV2ContextRoute?, metrics: [BodyMetrics],
        currentOwnership: AuthManager.ProfileSessionOwnership?
    ) -> Bool {
        admits(current: current, metrics: metrics, currentOwnership: currentOwnership)
            && metrics.filter { $0.id == stored.id } == [stored]
    }
}

/// Entries rows retain immutable actual raw records, never Presentation values.
struct HomeV2EntriesRow: Identifiable, Equatable {
    let id: String
    let date: Date
    let dayText: String
    let source: String
    let valueText: String
    let photoURL: String?
    /// The immutable raw record chosen by this row, including owner/date/revision and metadata.
    let metric: BodyMetrics
}

struct HomeV2EntriesSection: Identifiable, Equatable {
    let id: String
    let title: String
    let delta: String?
    let rows: [HomeV2EntriesRow]
}

enum HomeV2EntriesPolicy {
    static func admittedDestination(
        _ original: HomeV2ContextRoute, current: HomeV2ContextRoute?,
        metrics: [BodyMetrics], currentOwnership: AuthManager.ProfileSessionOwnership?
    ) -> BodyMetrics? {
        guard original.id == current?.id, let metric = original.metric else { return nil }
        return admittedMetric(
            metric, metrics: metrics, ownership: original.ownership, currentOwnership: currentOwnership
        )
    }

    /// Id-only uniqueness matches the underlying record identity boundary. No date-only retarget.
    static func admittedMetric(
        _ captured: BodyMetrics, metrics: [BodyMetrics],
        ownership: AuthManager.ProfileSessionOwnership?,
        currentOwnership: AuthManager.ProfileSessionOwnership?
    ) -> BodyMetrics? {
        guard let ownership, !ownership.subject.isEmpty, ownership == currentOwnership,
              captured.userId == ownership.subject else { return nil }
        let matches = metrics.filter { $0.id == captured.id }
        guard matches.count == 1, matches[0] == captured else { return nil }
        return matches[0]
    }

    /// An explicit parent selection wins. Calendar-only navigation has a stable newest-record tie.
    static func contextMetric(
        on date: Date, selected: HomeV2TimelinePolicy.Selection?, metrics: [BodyMetrics],
        ownership: AuthManager.ProfileSessionOwnership?,
        currentOwnership: AuthManager.ProfileSessionOwnership?, calendar: Calendar = .current
    ) -> BodyMetrics? {
        guard let ownership, !ownership.subject.isEmpty, ownership == currentOwnership else { return nil }
        let localDate = BodyMetricLocalDate.key(for: date, calendar: calendar)
        let sameDay = metrics.filter { $0.userId == ownership.subject && $0.localDate == localDate }
        if let selected, calendar.isDate(selected.date, inSameDayAs: date) {
            guard selected.id.owner == ownership.subject,
                  let captured = sameDay.first(where: {
                      HomeV2TimelinePolicy.EntryID($0) == selected.id && $0.date == selected.date
                  }) else { return nil }
            return admittedMetric(captured, metrics: metrics, ownership: ownership, currentOwnership: currentOwnership)
        }
        guard let latest = sameDay.max(by: {
            $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        }) else { return nil }
        return admittedMetric(latest, metrics: metrics, ownership: ownership, currentOwnership: currentOwnership)
    }

    static func sections(
        metrics: [BodyMetrics],
        unit: String,
        weightValue: (BodyMetrics) -> Double?,
        hasPhoto: (BodyMetrics) -> Bool,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> [HomeV2EntriesSection] {
        let shown = metrics
            .filter { $0.weight != nil || $0.bodyFatPercentage != nil || hasPhoto($0) }
            .sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
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
                }
                    ?? metric.bodyFatPercentage.map { String(format: "%.1f%%", $0) } ?? "—"
                return HomeV2EntriesRow(
                    id: metric.id,
                    date: metric.date,
                    dayText: HomeV2ContextCopy.entryDateText(metric.date, calendar: calendar),
                    source: metric.weight != nil ? HomeV2Provenance.weightSubline(for: metric, calendar: calendar)
                        : (metric.bodyFatPercentage != nil ? HomeV2Provenance.bodyFatSubline(for: metric, calendar: calendar)
                            : HomeV2Provenance.subline(for: metric, calendar: calendar)),
                    valueText: value,
                    photoURL: hasPhoto(metric) ? metric.photoUrl : nil,
                    metric: metric
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
