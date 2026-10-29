//
// BodyMetricLoggingService.swift
// LogYourBody
//
import Foundation
import Intents

enum BodyMetricLoggingError: LocalizedError {
    case notAuthenticated
    case noMetrics
    case protectedDataUnavailable
    case clarificationCancelled

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to LogYourBody before logging body metrics."
        case .noMetrics:
            return "No body metrics have been logged yet."
        case .protectedDataUnavailable:
            return "Unlock LogYourBody before logging body metrics."
        case .clarificationCancelled:
            return "Weight logging was cancelled before a value was confirmed."
        }
    }
}

/// Stable record and operation ids for one weight log. A retry reuses them.
/// A deliberate second log uses a new value.
struct BodyMetricLogIdentity: Equatable {
    let recordId: String
    let operationId: String
}

enum BodyMetricDeviceEffect: String, Equatable {
    case saved
    case denied
    case failed
    case notClaimed = "not_claimed"
}

struct BodyMetricLogCompletion: Equatable {
    let local: BodyMetricDeviceEffect
    let healthKit: BodyMetricDeviceEffect
    let cloud: BodyMetricDeviceEffect

    /// Cloud completion is never inferred from a local or HealthKit result.
    static func separate(localSaved: Bool, healthKitAuthorized: Bool) -> BodyMetricLogCompletion {
        BodyMetricLogCompletion(
            local: localSaved ? .saved : .failed,
            healthKit: healthKitAuthorized ? .saved : .denied,
            cloud: .notClaimed
        )
    }
}

enum BodyMetricWeightCommandPlan: Equatable {
    case create(recordId: String, operationId: String)
    case correct(recordId: String, operationId: String, expectedRevision: Int)
    case delete(recordId: String, operationId: String, expectedRevision: Int)
    case identityRequired
}

enum BodyMetricLocalWrite: Equatable {
    case insert
    case apply
    case retryKeepingTimestamps
    case preserveTombstone
    case conflict
}

struct BodyMetricLoggingResult {
    let metrics: BodyMetrics
    let dialog: String
    let completion: BodyMetricLogCompletion
}

struct BodyMetricLatestSummary {
    let metrics: BodyMetrics
    let dialog: String
}

final class BodyMetricLoggingService {
    static let shared = BodyMetricLoggingService()

    private let coreDataManager: CoreDataManager
    private let healthKitManager: HealthKitManager

    init(
        coreDataManager: CoreDataManager = .shared,
        healthKitManager: HealthKitManager = .shared
    ) {
        self.coreDataManager = coreDataManager
        self.healthKitManager = healthKitManager
    }

    func log(
        weight weightText: String?,
        bodyFat bodyFatText: String?,
        unit: String,
        date: Date = Date(),
        timeZone: TimeZone = .current,
        identity: BodyMetricLogIdentity? = nil,
        protectedDataAvailable: Bool = true,
        clarificationCancelled: Bool = false
    ) async throws -> BodyMetricLoggingResult {
        if let gate = Self.admissionGate(
            authenticated: true,
            protectedDataAvailable: protectedDataAvailable,
            clarificationCancelled: clarificationCancelled
        ), gate != .notAuthenticated {
            throw gate
        }

        let validation = LogWeightFormValidator.validate(
            weight: weightText ?? "",
            bodyFat: bodyFatText ?? "",
            unit: unit
        )

        if let error = validation.formError ?? validation.weightError ?? validation.bodyFatError {
            throw ValidationError.invalidWeight(error)
        }

        guard validation.isValid else {
            throw ValidationError.invalidWeight("Please enter at least one measurement")
        }

        guard let userId = await currentAuthenticatedUserId() else {
            throw BodyMetricLoggingError.notAuthenticated
        }

        let weightInKg = Self.storedWeightInKilograms(
            displayWeight: validation.weightValue,
            unit: unit
        )
        let resolvedIdentity = identity ?? (
            weightInKg != nil
                ? BodyMetricLogIdentity(recordId: UUID().uuidString, operationId: UUID().uuidString)
                : nil
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        if healthKitManager.isAuthorized {
            if let weightValue = validation.weightValue {
                let weightInPounds = unit == "kg" ? weightValue.kgToLbs : weightValue
                try await healthKitManager.saveWeight(weightInPounds, date: date)
            }

            if let bodyFatValue = validation.bodyFatValue {
                try await healthKitManager.saveBodyFatPercentage(bodyFatValue, date: date)
            }
        }

        let finalWeight = await resolvedWeight(
            suppliedWeightInKg: weightInKg,
            bodyFatValue: validation.bodyFatValue,
            userId: userId,
            date: date
        )

        let lifecycleMetadata = resolvedIdentity.map {
            BodyMetricSourceMetadata().settingWeightLifecycle(operationId: $0.operationId, revision: 1)
        }
        let metrics = BodyMetrics(
            id: resolvedIdentity?.recordId ?? UUID().uuidString,
            userId: userId,
            date: date,
            localDate: BodyMetricLocalDate.key(for: date, calendar: calendar),
            weight: finalWeight,
            weightUnit: finalWeight != nil ? "kg" : nil,
            bodyFatPercentage: validation.bodyFatValue,
            bodyFatMethod: validation.bodyFatValue != nil ? "Manual" : nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            sourceMetadata: lifecycleMetadata,
            createdAt: date,
            updatedAt: date
        )

        try await coreDataManager.saveBodyMetricsAndWait(
            metrics,
            userId: userId,
            markAsSynced: false
        )

        await MainActor.run {
            RealtimeSyncManager.shared.syncIfNeeded()
        }

        Self.donateLoggedMetricActivity(metrics)
        BodyMetricSpotlightIndexer.indexLatestMetric(metrics)
        if metrics.weight != nil {
            await MainActor.run { NotificationManager.shared.recordWeighInLogged() }
        }

        return BodyMetricLoggingResult(
            metrics: metrics,
            dialog: Self.loggedSummary(for: metrics, preferredSystem: .preferredFromDefaults),
            completion: .separate(
                localSaved: true,
                healthKitAuthorized: healthKitManager.isAuthorized
            )
        )
    }

    func latestMetricsSummary() async throws -> BodyMetricLatestSummary {
        guard let userId = await currentAuthenticatedUserId() else {
            throw BodyMetricLoggingError.notAuthenticated
        }

        guard let metrics = await coreDataManager.fetchLatestBodyMetric(for: userId)?.toBodyMetrics() else {
            throw BodyMetricLoggingError.noMetrics
        }

        return BodyMetricLatestSummary(
            metrics: metrics,
            dialog: Self.latestSummary(for: metrics, preferredSystem: .preferredFromDefaults)
        )
    }

    /// Exact pounds factor shared with the agent weight contract. Display
    /// conversion elsewhere stays on `UnitConversion` and is not this write path.
    static let poundsToKilograms = 0.45359237

    static func storedWeightInKilograms(displayWeight: Double?, unit: String) -> Double? {
        guard let displayWeight else { return nil }
        if unit == "lbs" || unit == "lb" {
            return displayWeight * poundsToKilograms
        }
        return displayWeight
    }

    static func admissionGate(
        authenticated: Bool,
        protectedDataAvailable: Bool,
        clarificationCancelled: Bool
    ) -> BodyMetricLoggingError? {
        if clarificationCancelled { return .clarificationCancelled }
        if !protectedDataAvailable { return .protectedDataUnavailable }
        if !authenticated { return .notAuthenticated }
        return nil
    }

    /// Correction and delete identify an owned measurement and revision.
    /// A missing identity stays `identityRequired` and is never a create.
    static func planWeightCommand(
        kind: String,
        recordId: String?,
        operationId: String?,
        expectedRevision: Int?
    ) -> BodyMetricWeightCommandPlan {
        switch kind {
        case "create":
            return .create(
                recordId: nonempty(recordId) ?? UUID().uuidString,
                operationId: nonempty(operationId) ?? UUID().uuidString
            )
        case "correct":
            guard let recordId = nonempty(recordId),
                  let expectedRevision, expectedRevision >= 1 else {
                return .identityRequired
            }
            return .correct(
                recordId: recordId,
                operationId: nonempty(operationId) ?? UUID().uuidString,
                expectedRevision: expectedRevision
            )
        case "delete":
            guard let recordId = nonempty(recordId),
                  let expectedRevision, expectedRevision >= 1 else {
                return .identityRequired
            }
            return .delete(
                recordId: recordId,
                operationId: nonempty(operationId) ?? UUID().uuidString,
                expectedRevision: expectedRevision
            )
        default:
            return .identityRequired
        }
    }

    /// Same operation id is a retry or a conflict. A different operation is a new edit.
    static func decideLocalWrite(
        hasExisting: Bool,
        existingOperationId: String?,
        incomingOperationId: String?,
        weightsEqual: Bool,
        existingDeleted: Bool
    ) -> BodyMetricLocalWrite {
        guard hasExisting else { return .insert }
        guard let incomingOperationId,
              let existingOperationId,
              incomingOperationId == existingOperationId else {
            return .apply
        }
        if existingDeleted { return .preserveTombstone }
        if weightsEqual { return .retryKeepingTimestamps }
        return .conflict
    }

    static func canonicalWeightsEqual(_ stored: Double, _ incoming: Double?) -> Bool {
        guard let incoming else { return stored == 0 }
        return abs(stored - incoming) < 0.0000005
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func formattedWeight(_ weightKg: Double, preferredSystem: MeasurementSystem) -> String {
        let displayValue = preferredSystem.weightUnit == "lbs" ? weightKg.kgToLbs : weightKg
        return "\(formatDecimal(displayValue)) \(preferredSystem.weightUnit)"
    }

    static func loggedSummary(for metrics: BodyMetrics, preferredSystem: MeasurementSystem) -> String {
        let parts = metricParts(for: metrics, preferredSystem: preferredSystem)
        guard !parts.isEmpty else {
            return "Logged your body metrics."
        }

        return "Logged \(parts.joined(separator: " and "))."
    }

    static func latestSummary(for metrics: BodyMetrics, preferredSystem: MeasurementSystem) -> String {
        let parts = metricParts(for: metrics, preferredSystem: preferredSystem)
        guard !parts.isEmpty else {
            return "Your latest entry has no weight or body fat value."
        }

        return "Your latest metrics are \(parts.joined(separator: " and "))."
    }

    private func currentAuthenticatedUserId() async -> String? {
        let initializationTask = await MainActor.run {
            AuthManager.shared.ensureAuthInitializationTask(priority: .userInitiated)
        }

        await initializationTask.value
        await Task.yield()

        return await MainActor.run {
            AuthManager.shared.currentUser?.id
        }
    }

    private func resolvedWeight(
        suppliedWeightInKg: Double?,
        bodyFatValue: Double?,
        userId: String,
        date: Date
    ) async -> Double? {
        guard suppliedWeightInKg == nil, bodyFatValue != nil else {
            return suppliedWeightInKg
        }

        let fromDate = Calendar.current.date(byAdding: .day, value: -7, to: date) ?? date
        let cachedMetrics = await coreDataManager.fetchBodyMetrics(
            for: userId,
            from: fromDate,
            to: date
        )

        return cachedMetrics
            .compactMap { $0.toBodyMetrics() }
            .filter { !$0.isExcluded && $0.weight != nil }
            .max { $0.date < $1.date }?
            .weight
    }

    static func metricParts(for metrics: BodyMetrics, preferredSystem: MeasurementSystem) -> [String] {
        var parts: [String] = []

        if let weight = metrics.weight {
            parts.append(formattedWeight(weight, preferredSystem: preferredSystem))
        }

        if let bodyFatPercentage = metrics.bodyFatPercentage {
            parts.append("\(formatDecimal(bodyFatPercentage))% body fat")
        }

        return parts
    }

    private static func formatDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func donateLoggedMetricActivity(_ metrics: BodyMetrics) {
        let activity = NSUserActivity(activityType: "com.logyourbody.metric.logged")
        activity.title = "Log body metrics"
        activity.isEligibleForSearch = true
        activity.isEligibleForPrediction = true
        activity.suggestedInvocationPhrase = "Log my weight in LogYourBody"
        activity.persistentIdentifier = NSUserActivityPersistentIdentifier(metrics.id)
        activity.userInfo = [
            "metricId": metrics.id,
            "localDate": metrics.localDate,
            "hasWeight": metrics.weight != nil,
            "hasBodyFat": metrics.bodyFatPercentage != nil
        ]
        activity.becomeCurrent()
    }
}
