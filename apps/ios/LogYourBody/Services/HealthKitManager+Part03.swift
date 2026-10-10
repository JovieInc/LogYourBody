import Foundation
import HealthKit

extension HealthKitManager {
func observeStepChanges() {
        guard isAuthorized else { return }

        // Stop any existing step observer queries
        if let existingQuery = stepObserverQuery {
            healthStore.stop(existingQuery)
            stepObserverQuery = nil
        }

        activeQueries.filter { $0 is HKObserverQuery && ($0 as? HKObserverQuery)?.objectType == stepCountType }.forEach {
            healthStore.stop($0)
        }
        activeQueries.removeAll { $0 is HKObserverQuery && ($0 as? HKObserverQuery)?.objectType == stepCountType }

        let query = HKObserverQuery(sampleType: stepCountType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                // New step data available, sync it
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    let owner = self.importAuthManager ?? .shared
                    guard let ownership = owner.captureAccountSession() else { return }

                    // Sync today's steps for the session that observed them.
                    try? await self.syncStepsFromHealthKit()

                    guard owner.ownsAccountSession(ownership) else { return }
                    await self.syncStepsToProductAPI(userId: ownership.subject)
                }
            }
            completionHandler()
        }

        stepObserverQuery = query
        healthStore.execute(query)
        activeQueries.append(query)

        // Enable background delivery for real-time updates
        Task {
            await enableBackgroundStepDelivery()
        }
    }

func enableBackgroundStepDelivery() async {
        guard isAuthorized else { return }

        do {
            try await healthStore.enableBackgroundDelivery(
                for: stepCountType,
                frequency: .immediate
            )
            // print("✅ Enabled background step delivery")
        } catch {
            await captureHealthKitError(
                error,
                operation: "enableBackgroundStepDelivery",
                contextDescription: "enableBackgroundStepDelivery"
            )
            // print("❌ Failed to enable background step delivery: \(error)")
        }
    }

func fetchStepCountHistory(days: Int = 30) async throws -> [(stepCount: Int, date: Date)] {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        if let stepHistoryQuery {
            return try await stepHistoryQuery(days)
        }

        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -days, to: endDate)!

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let anchorDate = calendar.startOfDay(for: startDate)
            let interval = DateComponents(day: 1)

            let query = HKStatisticsCollectionQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, statisticsCollection, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                var results: [(stepCount: Int, date: Date)] = []

                statisticsCollection?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    let stepCount = statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                    results.append((stepCount: Int(stepCount), date: statistics.startDate))
                }

                continuation.resume(returning: results)
            }

            healthStore.execute(query)
        }
    }

func setupStepCountBackgroundDelivery() async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        try await healthStore.enableBackgroundDelivery(
            for: stepCountType,
            frequency: .immediate
        )
    }

// MARK: - Step Syncing to ProductAPI

    func syncStepsToProductAPI(userId: String) async {
        guard let ownership = await captureImportOwnership(), ownership.subject == userId else { return }
        // Get today's steps
        let todaySteps = todayStepCount
        guard todaySteps > 0 else { return }
        guard await ownsImport(ownership) else { return }

        // Get or create today's daily metrics
        let today = Date()
        let store = importCoreDataManager ?? .shared
        var metrics = await store.fetchDailyMetrics(for: ownership.subject, date: today)?.toDailyMetrics()

        if metrics == nil {
            // Create new daily metrics
            metrics = makeNewDailyMetrics(
                userId: ownership.subject,
                date: today,
                steps: todaySteps,
                createdAt: today,
                notes: nil
            )
        } else if let existingMetrics = metrics {
            // Update existing metrics with new step count
            metrics = makeUpdatedDailyMetrics(
                from: existingMetrics,
                steps: todaySteps,
                updatedAt: Date()
            )
        }

        // Save to Core Data only while the observing session still owns the account.
        if let metrics = metrics {
            guard await ownsImport(ownership) else { return }
            let cancellation = HealthKitImportCancellation()
            let admission: CoreDataManager.WriteAdmission = { [self] in
                guard !cancellation.isCancelled,
                      (importAuthManager ?? .shared).ownsAccountSession(ownership) else {
                    throw HealthKitError.notAuthorized
                }
            }
            try? await withTaskCancellationHandler {
                try await store.saveDailyMetricsAndWait(
                    metrics, userId: ownership.subject, writeAdmission: admission
                )
            } onCancel: {
                cancellation.cancel()
            }
            guard await ownsImport(ownership) else { return }
            await MainActor.run {
                guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership) else { return }
                if let importSyncTrigger {
                    importSyncTrigger()
                } else {
                    RealtimeSyncManager.shared.syncIfNeeded()
                }
            }
        }
    }

func syncHistoricalSteps(userId: String, days: Int = 30) async throws {
        guard let ownership = await captureImportOwnership(), ownership.subject == userId else {
            throw HealthKitError.notAuthorized
        }
        let historicalData = try await fetchStepCountHistory(days: days)
        try await requireImportOwnership(ownership)
        let store = importCoreDataManager ?? .shared

        for (stepCount, date) in historicalData {
            guard stepCount > 0 else { continue }
            try await requireImportOwnership(ownership)

            // Check if we already have data for this date
            var metrics = await store.fetchDailyMetrics(for: ownership.subject, date: date)?.toDailyMetrics()

            if metrics == nil {
                // Create new daily metrics for historical date
                metrics = makeNewDailyMetrics(
                    userId: ownership.subject,
                    date: date,
                    steps: stepCount,
                    createdAt: Date(),
                    notes: nil
                )
            } else if let existingMetrics = metrics, existingMetrics.steps != stepCount {
                // Update if step count is different
                metrics = makeUpdatedDailyMetrics(
                    from: existingMetrics,
                    steps: stepCount,
                    updatedAt: Date()
                )
            } else {
                // Skip if data is already up to date
                continue
            }

            // Save to Core Data
            if let metrics = metrics {
                try await requireImportOwnership(ownership)
                try await store.saveDailyMetricsAndWait(metrics, userId: ownership.subject)
            }
        }

        guard await ownsImport(ownership) else { return }
        await MainActor.run {
            guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership) else { return }
            if let importSyncTrigger {
                importSyncTrigger()
            } else {
                Task.detached {
                    await RealtimeSyncManager.shared.syncAll()
                }
            }
        }
    }

func makeNewDailyMetrics(
        userId: String,
        date: Date,
        steps: Int,
        createdAt: Date,
        notes: String?
    ) -> DailyMetrics {
        DailyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            steps: steps,
            notes: notes,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

func makeUpdatedDailyMetrics(
        from existingMetrics: DailyMetrics,
        steps: Int,
        updatedAt: Date
    ) -> DailyMetrics {
        DailyMetrics(
            id: existingMetrics.id,
            userId: existingMetrics.userId,
            date: existingMetrics.date,
            steps: steps,
            notes: existingMetrics.notes,
            createdAt: existingMetrics.createdAt,
            updatedAt: updatedAt
        )
    }

// MARK: - Local existence helpers

    func weightEntryExists(for date: Date) async -> Bool {
        guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else { return false }

        let calendar = Calendar.current
        let hourBefore = calendar.date(byAdding: .hour, value: -1, to: date) ?? date
        let hourAfter = calendar.date(byAdding: .hour, value: 1, to: date) ?? date

        let metrics = await CoreDataManager.shared.fetchBodyMetrics(
            for: userId,
            from: hourBefore,
            to: hourAfter
        )
        return !metrics.isEmpty
    }

func dailyMetricsExists(for date: Date, userId: String) async -> Bool {
        await (importCoreDataManager ?? .shared).fetchDailyMetrics(for: userId, date: date) != nil
    }

func saveDailySteps(
        steps: Int,
        date: Date,
        ownership: AuthManager.ProfileSessionOwnership? = nil
    ) async throws {
        guard let ownership = await captureImportOwnership(ownership) else {
            throw HealthKitError.notAuthorized
        }
        try await requireImportOwnership(ownership)

        let metrics = DailyMetrics(
            id: UUID().uuidString,
            userId: ownership.subject,
            date: date,
            steps: steps,
            notes: "Imported from HealthKit",
            createdAt: Date(),
            updatedAt: Date()
        )
        let cancellation = HealthKitImportCancellation()
        let admission: CoreDataManager.WriteAdmission = { [self] in
            guard !cancellation.isCancelled,
                  (importAuthManager ?? .shared).ownsAccountSession(ownership) else {
                throw HealthKitError.notAuthorized
            }
        }
        try await withTaskCancellationHandler {
            try await (importCoreDataManager ?? .shared).saveDailyMetricsAndWait(
                metrics, userId: ownership.subject, writeAdmission: admission
            )
        } onCancel: {
            cancellation.cancel()
        }
        guard await ownsImport(ownership) else { return }
        await MainActor.run {
            guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership) else { return }
            if let importSyncTrigger {
                importSyncTrigger()
            } else {
                RealtimeSyncManager.shared.syncIfNeeded()
            }
        }
    }

func captureHealthKitError(
        _ error: Error,
        operation: String,
        contextDescription: String,
        userIdOverride: String? = nil
    ) async {
        let appError: AppError
        if let hkError = error as? HealthKitError {
            appError = .healthKit(hkError)
        } else {
            appError = .unexpected(context: contextDescription, underlying: error)
        }

        let resolvedUserId: String?
        if let userIdOverride {
            resolvedUserId = userIdOverride
        } else {
            resolvedUserId = await MainActor.run { AuthManager.shared.currentUser?.id }
        }

        let context = ErrorContext(
            feature: "healthKit",
            operation: operation,
            screen: nil,
            userId: resolvedUserId
        )

        ErrorReporter.shared.capture(appError, context: context)
    }
}
