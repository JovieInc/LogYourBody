import Foundation

/// Canonical kg and percentage overrides. Nil fields retain their imported value.
struct MetricCorrectedValue: Codable, Equatable {
    let weight: Double?
    let bodyFatPercentage: Double?

    init(weight: Double? = nil, bodyFatPercentage: Double? = nil) {
        self.weight = weight
        self.bodyFatPercentage = bodyFatPercentage
    }

    enum CodingKeys: String, CodingKey {
        case weight
        case bodyFatPercentage = "body_fat_percentage"
    }

    var isValid: Bool {
        (weight != nil || bodyFatPercentage != nil) &&
            weight.map { $0.isFinite && (32...300).contains($0) } != false &&
            bodyFatPercentage.map { $0.isFinite && (3...60).contains($0) } != false
    }

    var jsonObject: [String: Any] {
        var result: [String: Any] = [:]
        if let weight { result["weight"] = weight }
        if let bodyFatPercentage { result["body_fat_percentage"] = bodyFatPercentage }
        return result
    }

    var jsonString: String? {
        guard isValid, let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    init?(jsonString: String?) {
        guard let data = jsonString?.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        self = value
    }

    init?(jsonObject: Any?) {
        guard let jsonObject, JSONSerialization.isValidJSONObject(jsonObject),
              let data = try? JSONSerialization.data(withJSONObject: jsonObject),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        self = value
    }
}

enum MetricCorrectionError: Error {
    case featureDisabled
    case notAuthorized
    case notImported
    case invalidValue
    case entryChanged
}

/// Device-owned overlays only. This service has no health-store dependency.
@MainActor
final class MetricCorrectionService {
    static let shared = MetricCorrectionService()
    static let featureGate = "imported_metric_corrections"

    private let coreDataManager: CoreDataManager
    private let isEnabled: @MainActor () -> Bool
    private let admission: @MainActor (String) throws -> CoreDataManager.WriteAdmission
    private let syncTrigger: @MainActor () -> Void

    init(
        coreDataManager: CoreDataManager = .shared,
        isEnabled: @escaping @MainActor () -> Bool = {
            AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: MetricCorrectionService.featureGate)
        },
        admission: @escaping @MainActor (String) throws -> CoreDataManager.WriteAdmission = { userId in
            guard let session = AuthManager.shared.captureAccountSession(), session.subject == userId else {
                throw MetricCorrectionError.notAuthorized
            }
            return {
                guard AuthManager.shared.ownsAccountSession(session) else { throw MetricCorrectionError.notAuthorized }
            }
        },
        syncTrigger: @escaping @MainActor () -> Void = {
            RealtimeSyncManager.shared.updatePendingSyncCount()
            RealtimeSyncManager.shared.syncIfNeeded()
        }
    ) {
        self.coreDataManager = coreDataManager
        self.isEnabled = isEnabled
        self.admission = admission
        self.syncTrigger = syncTrigger
    }

    func exclude(_ metric: BodyMetrics) async throws -> PhotoMetricsUpdateResult {
        try await apply(metric, excluded: true, correctedValue: metric.correctedValue)
    }

    func correct(_ metric: BodyMetrics, to value: MetricCorrectedValue) async throws -> PhotoMetricsUpdateResult {
        guard value.isValid,
              value.weight == nil || metric.originalWeight != nil,
              value.bodyFatPercentage == nil || metric.originalBodyFatPercentage != nil else {
            throw MetricCorrectionError.invalidValue
        }
        // A patch changes only supplied fields, including corrections made earlier.
        let merged = MetricCorrectedValue(
            weight: value.weight ?? metric.correctedValue?.weight,
            bodyFatPercentage: value.bodyFatPercentage ?? metric.correctedValue?.bodyFatPercentage
        )
        return try await apply(metric, excluded: metric.isExcluded, correctedValue: merged)
    }

    /// Reuse LYB-162's receipt shape. Restore only overlay state; keep sync clocks monotonic.
    /// Undo remains available after a rollout is disabled.
    func undo(_ receipt: PhotoMetricsUpdateResult) async throws -> PhotoMetricsUpdateResult {
        guard let previous = receipt.previousMetric,
              previous.id == receipt.metrics.id, previous.userId == receipt.metrics.userId else {
            throw MetricCorrectionError.entryChanged
        }
        return try await persist(
            receipt.metrics, excluded: previous.isExcluded, correctedValue: previous.correctedValue
        )
    }

    private func apply(
        _ metric: BodyMetrics, excluded: Bool, correctedValue: MetricCorrectedValue?
    ) async throws -> PhotoMetricsUpdateResult {
        guard isEnabled() else { throw MetricCorrectionError.featureDisabled }
        guard metric.metricSource != .manual, metric.metricSource != .photo else {
            throw MetricCorrectionError.notImported
        }
        return try await persist(metric, excluded: excluded, correctedValue: correctedValue)
    }

    private func persist(
        _ metric: BodyMetrics, excluded: Bool, correctedValue: MetricCorrectedValue?
    ) async throws -> PhotoMetricsUpdateResult {
        let writeAdmission = try admission(metric.userId)
        let result = try await coreDataManager.updateMetricOverlayAndWait(
            expected: metric, excluded: excluded, correctedValue: correctedValue, writeAdmission: writeAdmission
        )
        syncTrigger()
        return result
    }
}
