//
// BodyMetricLoggingService.swift
// LogYourBody
//
import Foundation
import Intents

enum BodyMetricLoggingError: LocalizedError {
    case notAuthenticated
    case noMetrics

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in to LogYourBody before logging body metrics."
        case .noMetrics:
            return "No body metrics have been logged yet."
        }
    }
}

struct BodyMetricLoggingResult {
    let metrics: BodyMetrics
    let dialog: String
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
        date: Date = Date()
    ) async throws -> BodyMetricLoggingResult {
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

        let metrics = BodyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            localDate: BodyMetricLocalDate.key(for: date),
            weight: finalWeight,
            weightUnit: finalWeight != nil ? "kg" : nil,
            bodyFatPercentage: validation.bodyFatValue,
            bodyFatMethod: validation.bodyFatValue != nil ? "Manual" : nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
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

        return BodyMetricLoggingResult(
            metrics: metrics,
            dialog: Self.loggedSummary(for: metrics, preferredSystem: .preferredFromDefaults)
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

    static func storedWeightInKilograms(displayWeight: Double?, unit: String) -> Double? {
        guard let displayWeight else { return nil }
        return unit == "lbs" ? displayWeight.lbsToKg : displayWeight
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
            AuthManager.shared.ensureClerkInitializationTask(priority: .userInitiated)
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
