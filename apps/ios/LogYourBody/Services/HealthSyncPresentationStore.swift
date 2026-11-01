import Foundation
import Observation

enum HealthSyncPresentationPolicy {
    static let gateKey = "health_sync_receipt_v1"
    static let receiptDuration: TimeInterval = 6

    @MainActor
    static func isEnabled(isGateEnabled: ((String) -> Bool)? = nil) -> Bool {
        let check = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return check(gateKey)
    }

    static func caption(state: HealthSyncState, lastSync: Date?, locale: Locale = .current,
                        timeZone: TimeZone = .current) -> String {
        switch state {
        case .checking: return "Checking Apple Health…"
        case .updated:
            guard let lastSync else { return "Updated from Apple Health" }
            let style = Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute()
            return "Updated from Apple Health, \(lastSync.formatted(style))"
        case .unavailable: return "Apple Health update unavailable"
        case .permissionNeeded: return "Apple Health access needed"
        case .offline: return "Offline · showing saved readings"
        }
    }
}

struct HealthWeightReceipt: Equatable, Identifiable {
    let id: UUID
    let metric: BodyMetrics
    let expiresAt: Date

    func text(unit: String, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let value = unit == "lb" ? (metric.weight ?? 0).kgToLbs : metric.weight ?? 0
        let weight = value.formatted(.number.locale(locale).precision(.fractionLength(1)))
        let date = metric.date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day())
        let time = metric.date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute())
        return "New weight from Apple Health · \(date), \(time) · \(weight) \(unit)"
    }
}

/// Collection work and provenance parsing happen once per publication, away from the UI actor.
actor HealthReadingObserver {
    struct Snapshot {
        let readings: [BodyMetrics]
        let receipt: HealthWeightReceipt?
    }

    private struct ReadingIdentity: Hashable {
        let record: String
        let sample: String?
        let date: Date
        let weight: UInt64?

        init(_ metric: BodyMetrics) {
            record = metric.id
            sample = metric.sourceMetadata?.sampleId
            date = metric.date
            weight = metric.originalWeight?.bitPattern
        }
    }

    private var sequence = 0
    private var owner: AuthManager.ProfileSessionOwnership?
    private var startedAt = Date.distantFuture
    private var seenReadings = Set<ReadingIdentity>()
    private var receipt: HealthWeightReceipt?

    func update(_ metrics: [BodyMetrics], owner: AuthManager.ProfileSessionOwnership,
                sequence: Int, now: Date) -> Snapshot? {
        guard sequence > self.sequence else { return nil }
        self.sequence = sequence
        if self.owner != owner {
            self.owner = owner
            // Import metadata serializes whole seconds; do not drop a live same-second sample.
            startedAt = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
            seenReadings = Set(metrics.filter { $0.userId == owner.subject }.map(ReadingIdentity.init))
            receipt = nil
        }
        let readings = metrics.filter {
            $0.userId == owner.subject && $0.metricSource == .healthKit &&
                $0.originalWeight.map { $0.isFinite && $0 > 0 } == true
        }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        let newest = readings.first {
            !seenReadings.contains(ReadingIdentity($0)) && !$0.isExcluded &&
                $0.measurementSource(for: .weight) == .healthKit &&
                $0.provenance.importedAt >= startedAt
        }
        seenReadings.formUnion(metrics.filter { $0.userId == owner.subject }.map(ReadingIdentity.init))
        if let newest {
            receipt = HealthWeightReceipt(
                id: UUID(), metric: newest, expiresAt: now.addingTimeInterval(HealthSyncPresentationPolicy.receiptDuration)
            )
        } else if let current = receipt, !readings.contains(where: {
            $0.id == current.metric.id && !$0.isExcluded && $0.weight == current.metric.weight &&
                $0.measurementSource(for: .weight) == .healthKit
        }) {
            receipt = nil
        }
        var recent = Array(readings.prefix(20))
        // A late-arriving reading must still be reachable from its own receipt.
        if let receipt, receipt.expiresAt > now, !recent.contains(where: { $0.id == receipt.metric.id }) {
            recent = [receipt.metric] + recent.prefix(19)
        }
        return Snapshot(readings: recent, receipt: receipt)
    }
}

@MainActor @Observable
final class HealthSyncPresentationStore {
    private(set) var syncStatus = HealthSyncStateReducer()
    private(set) var readings: [BodyMetrics] = []
    private(set) var receipt: HealthWeightReceipt?
    private(set) var lastChange: PhotoMetricsUpdateResult?
    private(set) var isSaving = false
    private(set) var changeRevision = 0
    private(set) var error: String?

    private let observer = HealthReadingObserver()
    private var owner: AuthManager.ProfileSessionOwnership?
    private var sequence = 0
    private var dismissedReceiptID: UUID?
    private var dismissal: Task<Void, Never>?
    private var saveID: UUID?

    func updateSyncStatus(_ status: HealthSyncStateReducer) {
        syncStatus = status
    }

    func reset() {
        sequence += 1
        owner = nil
        syncStatus = HealthSyncStateReducer()
        readings = []
        receipt = nil
        lastChange = nil
        error = nil
        saveID = nil
        isSaving = false
        dismissedReceiptID = nil
        dismissal?.cancel()
    }

    @discardableResult
    func observe(_ metrics: [BodyMetrics], owner: AuthManager.ProfileSessionOwnership?) -> Task<Void, Never> {
        guard let owner else { reset(); return Task {} }
        if self.owner != owner {
            let status = syncStatus
            reset()
            self.owner = owner
            syncStatus = status
        }
        sequence += 1
        let request = sequence
        return Task {
            guard let snapshot = await observer.update(metrics, owner: owner, sequence: request, now: Date()),
                  self.owner == owner, self.sequence == request else { return }
            readings = snapshot.readings
            let next = snapshot.receipt.flatMap {
                $0.expiresAt > Date() && $0.id != dismissedReceiptID ? $0 : nil
            }
            guard next != receipt else { return }
            dismissal?.cancel()
            receipt = next
            if let next {
                dismissal = Task {
                    do { try await Task.sleep(for: .seconds(max(0, next.expiresAt.timeIntervalSinceNow))) }
                    catch { return }
                    dismissReceipt(id: next.id)
                }
            }
        }
    }

    func dismissReceipt(id: UUID) {
        guard receipt?.id == id else { return }
        dismissedReceiptID = id
        receipt = nil
        dismissal?.cancel()
    }

    /// The existing correction service owns persistence, admission and optimistic concurrency.
    @discardableResult
    func change(ownsSession: (AuthManager.ProfileSessionOwnership) -> Bool,
                undoing: Bool = false,
                operation: () async throws -> PhotoMetricsUpdateResult) async -> Bool {
        guard !isSaving, let owner, ownsSession(owner) else { return false }
        let attempt = UUID()
        saveID = attempt
        isSaving = true
        error = nil
        defer { if saveID == attempt { isSaving = false } }
        do {
            let result = try await operation()
            guard self.owner == owner, ownsSession(owner), saveID == attempt,
                  result.metrics.userId == owner.subject else { return false }
            sequence += 1 // A pre-save publication must not replace the finished local change.
            if let index = readings.firstIndex(where: { $0.id == result.metrics.id }) {
                readings[index] = result.metrics
            }
            if receipt?.metric.id == result.metrics.id, let id = receipt?.id { dismissReceipt(id: id) }
            lastChange = undoing ? nil : result
            changeRevision += 1
            return true
        } catch {
            guard self.owner == owner, ownsSession(owner), saveID == attempt else { return false }
            self.error = "Couldn’t save this change. Try again."
            return false
        }
    }
}
