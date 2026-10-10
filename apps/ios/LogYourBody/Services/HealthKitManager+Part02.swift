import Foundation
import HealthKit

extension HealthKitManager {
    func captureImportOwnership(
        _ ownership: AuthManager.ProfileSessionOwnership? = nil
    ) async -> AuthManager.ProfileSessionOwnership? {
        if let ownership { return ownership }
        return await MainActor.run {
            let auth = self.importAuthManager ?? .shared
            guard let session = auth.captureAccountSession() else { return nil }
            let bound = self.userDefaults.string(forKey: HealthKitAccountSyncPolicy.accountIdKey)
            guard HealthKitAccountSyncPolicy.admitsImport(
                currentUserId: session.subject,
                boundAccountId: bound
            ) else { return nil }
            if bound == nil || bound?.isEmpty == true {
                self.userDefaults.set(session.subject, forKey: HealthKitAccountSyncPolicy.accountIdKey)
            }
            return session
        }
    }

    func admitsAutomaticImportForCurrentAccount() -> Bool {
        let userId = MainActor.assumeIsolated {
            (self.importAuthManager ?? .shared).currentUser?.id ?? ""
        }
        guard !userId.isEmpty else { return false }
        let bound = userDefaults.string(forKey: HealthKitAccountSyncPolicy.accountIdKey)
        return HealthKitAccountSyncPolicy.admitsImport(currentUserId: userId, boundAccountId: bound)
    }

    func claimAutomaticImportAccount() async {
        let defaults = userDefaults
        let auth = importAuthManager ?? .shared
        await MainActor.run {
            HealthKitAccountSyncPolicy.claim(userId: auth.currentUser?.id, defaults: defaults)
        }
    }

    func suspendAutomaticImportAfterSignOut() async {
        syncDebounceTimer?.invalidate()
        syncDebounceTimer = nil

        if let weightObserverQuery {
            healthStore.stop(weightObserverQuery)
            self.weightObserverQuery = nil
        }
        if let bodyFatObserverQuery {
            healthStore.stop(bodyFatObserverQuery)
            self.bodyFatObserverQuery = nil
        }
        if let stepObserverQuery {
            healthStore.stop(stepObserverQuery)
            self.stepObserverQuery = nil
        }
        if !activeQueries.isEmpty {
            for query in activeQueries {
                healthStore.stop(query)
            }
            activeQueries.removeAll()
        }

        do {
            try await healthStore.disableAllBackgroundDelivery()
        } catch {
            await captureHealthKitError(
                error,
                operation: "suspendAutomaticImportAfterSignOut",
                contextDescription: "suspendAutomaticImportAfterSignOut"
            )
        }

        await MainActor.run {
            self.isAuthorized = false
        }
    }

    func ownsImport(_ ownership: AuthManager.ProfileSessionOwnership) async -> Bool {
        guard !Task.isCancelled else { return false }
        return await MainActor.run { (self.importAuthManager ?? .shared).ownsAccountSession(ownership) }
    }

    func requireImportOwnership(_ ownership: AuthManager.ProfileSessionOwnership) async throws {
        if Task.isCancelled { throw CancellationError() }
        guard await ownsImport(ownership) else { throw HealthKitError.notAuthorized }
    }

func fetchTodayStepCount() async throws -> Int {
        guard isAuthorized, let ownership = await captureImportOwnership() else {
            throw HealthKitError.notAuthorized
        }
        try await requireImportOwnership(ownership)

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now
        let stepCount: Int
        do {
            let quantity: Double?
            if let todayStepQuantityQuery {
                quantity = try await todayStepQuantityQuery(startOfDay, endOfDay)
            } else {
                quantity = try await queryTodayStepQuantity(from: startOfDay, to: endOfDay)
            }
            stepCount = try HealthKitStepCountPolicy.stepCount(from: quantity)
        } catch {
            guard let noData = HealthKitStepCountPolicy.stepCount(forNoData: error) else { throw error }
            stepCount = noData
        }

        try Task.checkCancellation()
        return try await MainActor.run {
            try Task.checkCancellation()
            guard self.isAuthorized,
                  (self.importAuthManager ?? .shared).ownsAccountSession(ownership),
                  self.admitsAutomaticImportForCurrentAccount() else {
                throw HealthKitError.notAuthorized
            }
            self.todayStepCountOwner = ownership
            self.todayStepCount = stepCount
            self.latestStepCount = stepCount
            self.latestStepCountDate = now
            return stepCount
        }
    }

    private func queryTodayStepQuantity(from startDate: Date, to endDate: Date) async throws -> Double? {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate, end: endDate, options: .strictStartDate
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: HKUnit.count()))
                }
            }
            healthStore.execute(query)
        }
    }

func fetchStepCount(for date: Date) async throws -> Int {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                do {
                    let stepCount = try HealthKitStepCountPolicy.stepCount(
                        from: statistics?.sumQuantity()?.doubleValue(for: HKUnit.count())
                    )
                    continuation.resume(returning: stepCount)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            healthStore.execute(query)
        }
    }

func syncWeightFromHealthKit() async throws {
        guard let ownership = await captureImportOwnership() else { throw HealthKitError.notAuthorized }
        try await requireImportOwnership(ownership)
        // Prevent concurrent syncs
        guard beginWeightSyncIfPossible() else {
            // print("⚠️ Weight sync already in progress, skipping")
            return
        }

        // print("📊 Starting comprehensive weight sync from HealthKit...")
        defer {
            endWeightSync()
            // print("✅ Weight sync completed")
        }

        // First, do a quick sync of recent data (last 30 days) for immediate UI update
        // print("📅 Phase 1: Fetching recent data (30 days)")

        let (recentWeightHistory, recentBodyFatHistory) = try await fetchRecentWeightAndBodyFatHistory(
            ownership: ownership
        )
        try await requireImportOwnership(ownership)

        // print("📈 Found \(recentWeightHistory.count) weight entries and \(recentBodyFatHistory.count) body fat entries")

        if !recentWeightHistory.isEmpty {
            // print("  📅 Weight entries date range: \(recentWeightHistory.first?.date ?? Date()) to \(recentWeightHistory.last?.date ?? Date())")
            if let firstEntry = recentWeightHistory.first {
                _ = firstEntry
                // Show first 5 entries
                // print("    - \(date): \(weight)kg")
            }
        }

        // Process recent data for immediate UI update
        let (imported, _) = await processBatchHealthKitData(
            weightHistory: recentWeightHistory,
            bodyFatHistory: recentBodyFatHistory, ownership: ownership
        )

        // print("📊 Recent sync: \(imported) imported, \(skipped) skipped")

        // Only trigger full historical sync if this is truly the first time and we have very little data
        try await requireImportOwnership(ownership)
        await triggerFullHealthKitSyncIfNeeded(imported: imported, ownership: ownership)
    }

func fetchRecentWeightAndBodyFatHistory(ownership: AuthManager.ProfileSessionOwnership? = nil) async throws
    -> (
        weightHistory: [HealthKitWeightImportSample],
        bodyFatHistory: [HealthKitBodyFatImportSample]
    ) {
        let ownership = await captureImportOwnership(ownership)
        let endDate = Date()
        let recentStartDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!

        // Fetch recent weight and body fat data
        let recentWeightHistory = try await fetchWeightImportSamplesInRange(
            startDate: recentStartDate,
            endDate: endDate, ownership: ownership
        )
        let recentBodyFatHistory = try await fetchBodyFatImportSamples(
            startDate: recentStartDate, ownership: ownership
        )

        return (weightHistory: recentWeightHistory, bodyFatHistory: recentBodyFatHistory)
    }

@discardableResult
func triggerFullHealthKitSyncIfNeeded(
        imported: Int, ownership: AuthManager.ProfileSessionOwnership? = nil
    ) async -> Task<Void, Never>? {
        guard let ownership = await captureImportOwnership(ownership), await ownsImport(ownership) else { return nil }
        let fullSyncKey = HealthKitDefaultsKey.fullSyncCompleted.scoped(with: ownership.subject)
        let hasPerformedFullSync = userDefaults.bool(forKey: fullSyncKey)
        let totalCachedEntries = await (importCoreDataManager ?? .shared).fetchBodyMetrics(for: ownership.subject).count
        guard await ownsImport(ownership) else { return nil }
        guard !hasPerformedFullSync || (totalCachedEntries < 50 && imported > 0) else { return nil }
        return Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            let importSucceeded = await self.syncAllHistoricalHealthKitData(ownership: ownership)
            await MainActor.run {
                guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership),
                      HealthKitFullSyncCompletionPolicy.shouldMarkCompleted(importSucceeded: importSucceeded) else {
                    return
                }
                self.userDefaults.set(true, forKey: fullSyncKey)
            }
        }
    }

func syncWeightFromHealthKitIncremental(days: Int = 30, startDate: Date? = nil) async throws {
        guard let ownership = await captureImportOwnership() else { throw HealthKitError.notAuthorized }
        try await requireImportOwnership(ownership)
        // Prevent concurrent syncs
        guard beginWeightSyncIfPossible() else {
            // print("⚠️ Weight sync already in progress, skipping incremental sync")
            return
        }

        // print("📊 Starting incremental weight sync from HealthKit (\(days) days)...")
        defer {
            endWeightSync()
            // print("✅ Incremental weight sync completed")
        }

        let endDate = startDate ?? Date()
        let batchStartDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

        // print("📅 Fetching data from \(batchStartDate) to \(endDate)")

        // Fetch weight and body fat data for the specified period
        let weightHistory = try await fetchWeightImportSamplesInRange(
            startDate: batchStartDate,
            endDate: endDate, ownership: ownership
        )
            .filter { $0.date >= batchStartDate && $0.date <= endDate }
        let bodyFatHistory = try await fetchBodyFatImportSamples(startDate: batchStartDate, ownership: ownership)
            .filter { $0.date <= endDate }
        try await requireImportOwnership(ownership)

        // print("📈 Found \(weightHistory.count) weight entries and \(bodyFatHistory.count) body fat entries")

        if !weightHistory.isEmpty {
            // print("  📅 Weight entries date range: \(weightHistory.first?.date ?? Date()) to \(weightHistory.last?.date ?? Date())")
            if let firstEntry = weightHistory.first {
                _ = firstEntry
                // Show first 5 entries
                // print("    - \(date): \(weight)kg")
            }
        }

        // Process weight and body fat entries using shared batch logic
        _ = await processBatchHealthKitData(
            weightHistory: weightHistory,
            bodyFatHistory: bodyFatHistory, ownership: ownership
        )
        try await requireImportOwnership(ownership)
    }

@discardableResult
    func syncAllHistoricalHealthKitData(ownership: AuthManager.ProfileSessionOwnership? = nil) async -> Bool {
        if ownership == nil {
            await claimAutomaticImportAccount()
        }
        guard let ownership = await captureImportOwnership(ownership), await ownsImport(ownership) else { return false }
        let operation = UUID()
        let admitted = await MainActor.run {
            guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership) else { return false }
            historicalImportOperation = operation
            isImporting = true
            importProgress = 0.0
            importStatus = "Starting import..."
            importedCount = 0
            totalToImport = 0
            // The vendor can lazily read UIApplication while creating its first breadcrumb.
            ErrorTrackingService.shared.addBreadcrumb(
                message: "Starting HealthKit full history import", category: "healthKit",
                data: ["operation": "syncAllHistoricalHealthKitData"]
            )
            return true
        }
        guard admitted else { return false }

        do {
            let defaultHistoricalRange = TimeInterval(10 * 365 * 24 * 60 * 60)
            let earliestDate = try await getEarliestWeightDate()
                ?? Date().addingTimeInterval(-defaultHistoricalRange)
            try await requireImportOwnership(ownership)
            let (totalImported, totalSkipped) = try await processHistoricalHealthKitBatches(
                earliestDate: earliestDate, endDate: Date(), ownership: ownership, operation: operation
            )
            try await requireImportOwnership(ownership)
            let completed = await MainActor.run {
                guard self.ownsHistoricalImport(ownership, operation: operation) else { return false }
                importProgress = 1.0
                importStatus = "Import complete! Imported \(totalImported) entries"
                ErrorTrackingService.shared.addBreadcrumb(
                    message: "HealthKit full history import complete", category: "healthKit",
                    data: [
                        "operation": "syncAllHistoricalHealthKitData",
                        "imported": String(totalImported), "skipped": String(totalSkipped)
                    ]
                )
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard self.ownsHistoricalImport(ownership, operation: operation) else { return }
                    historicalImportOperation = nil
                    isImporting = false
                    importStatus = ""
                }
                return true
            }
            if !completed { await clearHistoricalImport(ownership, operation: operation) }
            return completed
        } catch {
            // Cancellation must release its own UI, but never an import that started later.
            var failureStatus = ""
            if !Task.isCancelled, await ownsImport(ownership) {
                await captureHealthKitError(
                    error, operation: "syncAllHistoricalHealthKitData",
                    contextDescription: "syncAllHistoricalHealthKitData", userIdOverride: ownership.subject
                )
                failureStatus = "Import failed: \(error.localizedDescription)"
                await MainActor.run {
                    guard self.ownsHistoricalImport(ownership, operation: operation) else { return }
                    ErrorTrackingService.shared.addBreadcrumb(
                        message: "HealthKit full history import failed: \(error.localizedDescription)",
                        category: "healthKit", level: .error,
                        data: ["operation": "syncAllHistoricalHealthKitData"]
                    )
                }
            }
            await clearHistoricalImport(ownership, operation: operation, status: failureStatus)
            return false
        }
    }

    @MainActor
    private func ownsHistoricalImport(_ ownership: AuthManager.ProfileSessionOwnership, operation: UUID) -> Bool {
        historicalImportOperation == operation && (importAuthManager ?? .shared).ownsAccountSession(ownership)
    }

    @MainActor
    private func clearHistoricalImport(
        _ ownership: AuthManager.ProfileSessionOwnership, operation: UUID, status: String = ""
    ) {
        // Compare lifetime directly so a cancelled task can still clean up its own state.
        guard historicalImportOperation == operation,
              (importAuthManager ?? .shared).captureAccountSession() == ownership else { return }
        historicalImportOperation = nil
        importProgress = 0.0
        importStatus = status
        isImporting = false
    }

func processHistoricalHealthKitBatches(
        earliestDate: Date, endDate: Date, ownership: AuthManager.ProfileSessionOwnership? = nil,
        operation: UUID? = nil
    ) async throws -> (imported: Int, skipped: Int) {
        guard let ownership = await captureImportOwnership(ownership) else { throw HealthKitError.notAuthorized }
        try await requireImportOwnership(ownership)
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: earliestDate, to: endDate)
        let totalMonths = Double(components.month ?? 0)

        await MainActor.run {
            guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership),
                  operation == nil || self.historicalImportOperation == operation else { return }
            importStatus = "Preparing to import \(Int(totalMonths)) months of data..."
        }

        var currentDate = earliestDate
        var totalImported = 0
        var totalSkipped = 0
        var processedMonths = 0.0
        let batchSizeMonths = 3  // Process 3 months at a time

        while currentDate < endDate {
            try await requireImportOwnership(ownership)
            let batchEndDate = calendar.date(byAdding: .month, value: batchSizeMonths, to: currentDate) ?? endDate
            let actualBatchEndDate = min(batchEndDate, endDate)

            // Update status
            let year = calendar.component(.year, from: currentDate)
            let month = calendar.component(.month, from: currentDate)
            await MainActor.run {
            guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership),
                  operation == nil || self.historicalImportOperation == operation else { return }
                importStatus = "Importing \(year)/\(month)..."
            }

            // Fetch weight and body fat data for this batch
            let weightBatch = try await fetchWeightImportSamplesInRange(
                startDate: currentDate,
                endDate: actualBatchEndDate, ownership: ownership
            )
            let bodyFatBatch = try await fetchBodyFatImportSamples(startDate: currentDate, ownership: ownership)
                .filter { $0.date < actualBatchEndDate }

            // Process this batch
            let (imported, skipped) = await processBatchHealthKitData(
                weightHistory: weightBatch,
                bodyFatHistory: bodyFatBatch, ownership: ownership
            )

            try await requireImportOwnership(ownership)
            totalImported += imported
            totalSkipped += skipped

            // Update progress
            processedMonths += Double(batchSizeMonths)
            let progress = totalMonths > 0 ? min(processedMonths / totalMonths, 1.0) : 1.0
            let importedCountSnapshot = totalImported
            let processedMonthsSnapshot = processedMonths
            await MainActor.run {
            guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership),
                  operation == nil || self.historicalImportOperation == operation else { return }
                importProgress = progress
                importedCount = importedCountSnapshot
                if totalMonths > 0 {
                    let remaining = max(0, Int(totalMonths - processedMonthsSnapshot))
                    importStatus = remaining > 0 ? "Importing... \(remaining) months remaining" : "Finalizing..."
                }
            }

            // Move to next batch
            currentDate = actualBatchEndDate

            // Very small delay to avoid overwhelming the system
            try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
        }

        return (imported: totalImported, skipped: totalSkipped)
    }

func forceFullHealthKitSync() async -> Bool {
        await syncAllHistoricalHealthKitData()
    }

func getEarliestWeightDate() async throws -> Date? {
        if let earliestImportDateQuery { return try await earliestImportDateQuery() }
        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    continuation.resume(returning: sample.startDate)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

func processBatchHealthKitData(
        weightHistory: [(weight: Double, date: Date)],
        bodyFatHistory: [(percentage: Double, date: Date)]
    ) async -> (imported: Int, skipped: Int) {
        await processBatchHealthKitData(
            weightHistory: weightHistory.map {
                HealthKitWeightImportSample(weight: $0.weight, date: $0.date)
            },
            bodyFatHistory: bodyFatHistory.map {
                HealthKitBodyFatImportSample(percentage: $0.percentage, date: $0.date)
            }
        )
    }

func processBatchHealthKitData(
        weightHistory: [HealthKitWeightImportSample],
        bodyFatHistory: [HealthKitBodyFatImportSample],
        ownership: AuthManager.ProfileSessionOwnership? = nil
    ) async -> (imported: Int, skipped: Int) {
        guard let ownership = await captureImportOwnership(ownership), await ownsImport(ownership) else {
            return (0, 0)
        }
        var imported = 0
        var skipped = 0

        // Create a dictionary of body fat data by logged local day
        var bodyFatByDate: [String: HealthKitBodyFatImportSample] = [:]
        for sample in bodyFatHistory {
            bodyFatByDate[BodyMetricLocalDate.key(for: sample.date)] = sample
        }

        // Get existing entries for this date range to check for duplicates
        let userId = ownership.subject

        let dateRange = weightHistory.map { $0.date } + bodyFatHistory.map { $0.date }
        let minDate = dateRange.min() ?? Date()
        let maxDate = dateRange.max() ?? Date()
        let calendar = Calendar.current
        let fetchStartDate = calendar.date(byAdding: .day, value: -1, to: minDate) ?? minDate
        let fetchEndDate = calendar.date(byAdding: .day, value: 1, to: maxDate) ?? maxDate

        let existingMetrics = await (importCoreDataManager ?? .shared).fetchBodyMetrics(
            for: userId,
            from: fetchStartDate,
            to: fetchEndDate
        )
        guard await ownsImport(ownership) else { return (0, 0) }

        // Create a set of existing entries by original logged local day and hour for efficient lookup
        var existingEntriesByHour = Set<String>()
        for metric in existingMetrics {
            if let date = metric.date {
                let localDate = BodyMetricLocalDate.normalized(metric.localDate, fallback: date)
                let key = "\(localDate)-\(BodyMetricLocalDate.hourKey(for: date))"
                existingEntriesByHour.insert(key)
            }
        }

        for sample in weightHistory {
            guard await ownsImport(ownership) else { return (imported, skipped) }
            // Check if entry exists within the same hour
            let localDate = BodyMetricLocalDate.key(for: sample.date)
            let hourKey = "\(localDate)-\(BodyMetricLocalDate.hourKey(for: sample.date))"

            if !existingEntriesByHour.contains(hourKey) {
                let bodyFatSample = bodyFatByDate[localDate]
                let bodyFatPercentage = bodyFatSample?.percentage

                let metrics = BodyMetrics(
                    id: UUID().uuidString,
                    userId: userId,
                    date: sample.date,
                    localDate: localDate,
                    weight: sample.weight,
                    weightUnit: "kg",
                    bodyFatPercentage: bodyFatPercentage,
                    bodyFatMethod: bodyFatPercentage != nil ? "HealthKit" : nil,
                    muscleMass: nil,
                    boneMass: nil,
                    notes: "Imported from HealthKit",
                    photoUrl: nil,
                    dataSource: BodyMetricSource.healthKit.rawValue,
                    sourceMetadata: combinedHealthKitMetadata(
                        weightMetadata: sample.sourceMetadata,
                        bodyFatMetadata: bodyFatSample?.sourceMetadata
                    ),
                    createdAt: Date(),
                    updatedAt: Date()
                )

                do {
                    try await saveBodyMetrics(metrics, ownership: ownership)
                    imported += 1
                    existingEntriesByHour.insert(hourKey) // Add to set to prevent duplicates in same batch
                } catch {
                    guard await ownsImport(ownership) else { return (imported, skipped) }
                    await captureHealthKitError(
                        error,
                        operation: "processBatchHealthKitData",
                        contextDescription: "processBatchHealthKitData.saveBodyMetrics",
                        userIdOverride: userId
                    )
                    // print("Failed to save entry: \(error)")
                }
            } else {
                skipped += 1
            }
        }

        if imported > 0 {
            // Trigger a background body score recalculation now that metrics have changed.
            await MainActor.run {
                guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership) else { return }
                if let importCompletion = self.importCompletion {
                    importCompletion(userId)
                } else {
                    BodyScoreCache.shared.invalidate(for: userId)
                    if let trigger = self.bodyScoreRecalculationTrigger {
                        trigger()
                    } else {
                        BodyScoreRecalculationService.shared.scheduleRecalculation()
                    }
                }
            }
        }

        return (imported, skipped)
    }

func saveBodyMetrics(
        _ metrics: BodyMetrics, ownership: AuthManager.ProfileSessionOwnership? = nil
    ) async throws {
        guard let ownership = await captureImportOwnership(ownership), metrics.userId == ownership.subject else {
            throw HealthKitError.notAuthorized
        }
        try await requireImportOwnership(ownership)
        let cancellation = HealthKitImportCancellation()
        let admission: CoreDataManager.WriteAdmission = { [self] in
            guard !cancellation.isCancelled,
                  (importAuthManager ?? .shared).ownsAccountSession(ownership) else {
                throw HealthKitError.notAuthorized
            }
        }
        try await withTaskCancellationHandler {
            if let metricImportStore {
                try await metricImportStore(metrics, admission)
            } else {
                try await (importCoreDataManager ?? .shared).saveBodyMetricsAndWait(
                    metrics, userId: ownership.subject, markAsSynced: false, writeAdmission: admission
                )
            }
        } onCancel: {
            cancellation.cancel()
        }
        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard (self.importAuthManager ?? .shared).ownsAccountSession(ownership) else { return }
            if let importSyncTrigger = self.importSyncTrigger {
                importSyncTrigger()
            } else {
                RealtimeSyncManager.shared.syncIfNeeded()
            }
        }
    }

func syncStepsFromHealthKit() async throws {
        guard let ownership = await captureImportOwnership() else {
            throw HealthKitError.notAuthorized
        }
        let stepHistory = try await fetchStepCountHistory(days: 365)
        try await requireImportOwnership(ownership)

        for (stepCount, date) in stepHistory {
            try await syncSingleStepFromHistory(stepCount: stepCount, date: date, ownership: ownership)
        }
    }

func syncSingleStepFromHistory(
        stepCount: Int,
        date: Date,
        ownership: AuthManager.ProfileSessionOwnership? = nil
    ) async throws {
        guard stepCount > 0 else { return }
        guard let ownership = await captureImportOwnership(ownership) else {
            throw HealthKitError.notAuthorized
        }
        try await requireImportOwnership(ownership)

        let exists = await dailyMetricsExists(for: date, userId: ownership.subject)
        if !exists {
            try await saveDailySteps(steps: stepCount, date: date, ownership: ownership)
        }
    }

func observeWeightChanges() {
        guard isAuthorized else { return }

        if let existingQuery = weightObserverQuery {
            healthStore.stop(existingQuery)
            weightObserverQuery = nil
        }

        let query = HKObserverQuery(sampleType: weightType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                self?.scheduleObservedBodyMetricSync()
            }
            completionHandler()
        }

        weightObserverQuery = query
        healthStore.execute(query)
        activeQueries.append(query)
    }

func observeBodyFatChanges() {
        guard isAuthorized else { return }

        if let existingQuery = bodyFatObserverQuery {
            healthStore.stop(existingQuery)
            bodyFatObserverQuery = nil
        }

        let query = HKObserverQuery(sampleType: bodyFatType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                self?.scheduleObservedBodyMetricSync()
            }
            completionHandler()
        }

        bodyFatObserverQuery = query
        healthStore.execute(query)
        activeQueries.append(query)
    }

func scheduleObservedBodyMetricSync() {
        Task { @MainActor [weak self] in
            let currentUserId = AuthManager.shared.currentUser?.id
            self?.scheduleObservedBodyMetricSync(for: currentUserId)
        }
    }

@MainActor
    func scheduleObservedBodyMetricSync(for currentUserId: String?) {
        // Check if we should sync (not more than once per hour)
        let lastSyncKey = HealthKitDefaultsKey.lastObserverSyncDate.scoped(with: currentUserId)
        let shouldSync: Bool = {
            if let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
                let minutesSinceLastSync = Date().timeIntervalSince(lastSync) / 60
                return minutesSinceLastSync >= 60
            }
            return true
        }()

        guard shouldSync else { return }

        // Debounce sync requests to prevent multiple concurrent syncs.
        DispatchQueue.main.async { [weak self] in
            self?.syncDebounceTimer?.invalidate()
            self?.syncDebounceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                UserDefaults.standard.set(Date(), forKey: lastSyncKey)
                Task { [weak self] in
                    // Weight sync imports both weight and body fat for the recent window.
                    try? await self?.syncWeightFromHealthKitIncremental(days: 7)
                }
            }
        }
    }
}

/// HealthKit answers a cumulative-sum query with `HKError.errorNoData` when
/// nothing has been recorded for the predicate yet. For today's steps that is
/// zero, not a failure, so it must not reach Sentry as a non-fatal error.
enum HealthKitStepCountPolicy {
    enum QuantityError: Error, LocalizedError {
        case invalidStepCount

        var errorDescription: String? { "Apple Health returned an invalid step count." }
    }

    /// Preserve HealthKit's existing truncation to a stored Int32 count, with
    /// validation before conversion or publication. Missing data still means zero.
    static func stepCount(from quantity: Double?) throws -> Int {
        guard let quantity else { return 0 }
        guard quantity.isFinite, quantity >= 0 else { throw QuantityError.invalidStepCount }
        let wholeCount = quantity.rounded(.towardZero)
        guard wholeCount <= Double(Int32.max), let count = Int(exactly: wholeCount) else {
            throw QuantityError.invalidStepCount
        }
        return count
    }

    static func stepCount(forNoData error: Error) -> Int? {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain, nsError.code == HKError.Code.errorNoData.rawValue else {
            return nil
        }
        return 0
    }
}
