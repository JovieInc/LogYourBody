import Foundation
import HealthKit

extension HealthKitManager {
func fetchTodayStepCount() async throws -> Int {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? now

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

                let stepCount = statistics?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0

                Task {
                    await MainActor.run {
                        self.todayStepCount = Int(stepCount)
                        self.latestStepCount = Int(stepCount)
                        self.latestStepCountDate = now
                    }
                }

                continuation.resume(returning: Int(stepCount))
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

                let stepCount = statistics?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
                continuation.resume(returning: Int(stepCount))
            }

            healthStore.execute(query)
        }
    }

func syncWeightFromHealthKit() async throws {
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

        let (recentWeightHistory, recentBodyFatHistory) = try await fetchRecentWeightAndBodyFatHistory()

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
            bodyFatHistory: recentBodyFatHistory
        )

        // print("📊 Recent sync: \(imported) imported, \(skipped) skipped")

        // Only trigger full historical sync if this is truly the first time and we have very little data
        await triggerFullHealthKitSyncIfNeeded(imported: imported)
    }

func fetchRecentWeightAndBodyFatHistory() async throws
    -> (
        weightHistory: [HealthKitWeightImportSample],
        bodyFatHistory: [HealthKitBodyFatImportSample]
    ) {
        let endDate = Date()
        let recentStartDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!

        // Fetch recent weight and body fat data
        let recentWeightHistory = try await fetchWeightImportSamplesInRange(
            startDate: recentStartDate,
            endDate: endDate
        )
        let recentBodyFatHistory = try await fetchBodyFatImportSamples(startDate: recentStartDate)

        return (weightHistory: recentWeightHistory, bodyFatHistory: recentBodyFatHistory)
    }

func triggerFullHealthKitSyncIfNeeded(imported: Int) async {
        let currentUserId = await MainActor.run { AuthManager.shared.currentUser?.id }
        guard currentUserId != nil else { return }
        let fullSyncKey = HealthKitDefaultsKey.fullSyncCompleted.scoped(with: currentUserId)
        let hasPerformedFullSync = userDefaults.bool(forKey: fullSyncKey)

        let totalCachedEntries: Int
        if let userId = currentUserId {
            totalCachedEntries = await CoreDataManager.shared.fetchBodyMetrics(for: userId).count
        } else {
            totalCachedEntries = 0
        }

        if !hasPerformedFullSync {
            // print("📊 First time sync detected, scheduling full historical sync...")
            // print("📊 Current cached entries: \(totalCachedEntries)")
            Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                let importSucceeded = await self.syncAllHistoricalHealthKitData()
                if HealthKitFullSyncCompletionPolicy.shouldMarkCompleted(importSucceeded: importSucceeded) {
                    self.userDefaults.set(true, forKey: fullSyncKey)
                }
            }
        } else if totalCachedEntries < 50 && imported > 0 {
            // Also trigger if we have very few entries despite having done a sync before
            // print("📊 Low entry count detected (\(totalCachedEntries)), triggering full sync...")
            Task.detached(priority: .background) { [weak self] in
                guard let self else { return }
                await self.syncAllHistoricalHealthKitData()
            }
        }
    }

func syncWeightFromHealthKitIncremental(days: Int = 30, startDate: Date? = nil) async throws {
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
            endDate: endDate
        )
            .filter { $0.date >= batchStartDate && $0.date <= endDate }
        let bodyFatHistory = try await fetchBodyFatImportSamples(startDate: batchStartDate)
            .filter { $0.date <= endDate }

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
            bodyFatHistory: bodyFatHistory
        )
    }

@discardableResult
    func syncAllHistoricalHealthKitData() async -> Bool {
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
            importStatus = "Starting import..."
            importedCount = 0
            totalToImport = 0
        }

        ErrorTrackingService.shared.addBreadcrumb(
            message: "Starting HealthKit full history import",
            category: "healthKit",
            data: [
                "operation": "syncAllHistoricalHealthKitData"
            ]
        )

        do {
            // Get the earliest available weight data date
            let defaultHistoricalRange = TimeInterval(10 * 365 * 24 * 60 * 60)
            let earliestDate = try await getEarliestWeightDate()
                ?? Date().addingTimeInterval(-defaultHistoricalRange) // Default to 10 years ago
            let endDate = Date()

            let (totalImported, totalSkipped) = try await processHistoricalHealthKitBatches(
                earliestDate: earliestDate,
                endDate: endDate
            )

            // Complete
            await MainActor.run {
                importProgress = 1.0
                importStatus = "Import complete! Imported \(totalImported) entries"
                // Reset after a delay
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                    await MainActor.run {
                        isImporting = false
                        importStatus = ""
                    }
                }
            }

            ErrorTrackingService.shared.addBreadcrumb(
                message: "HealthKit full history import complete",
                category: "healthKit",
                data: [
                    "operation": "syncAllHistoricalHealthKitData",
                    "imported": String(totalImported),
                    "skipped": String(totalSkipped)
                ]
            )
            return true
        } catch {
            await captureHealthKitError(
                error,
                operation: "syncAllHistoricalHealthKitData",
                contextDescription: "syncAllHistoricalHealthKitData"
            )

            ErrorTrackingService.shared.addBreadcrumb(
                message: "HealthKit full history import failed: \(error.localizedDescription)",
                category: "healthKit",
                level: .error,
                data: [
                    "operation": "syncAllHistoricalHealthKitData"
                ]
            )
            await MainActor.run {
                importProgress = 0.0
                importStatus = "Import failed: \(error.localizedDescription)"
                isImporting = false
            }
            return false
        }
    }

func processHistoricalHealthKitBatches(
        earliestDate: Date,
        endDate: Date
    ) async throws -> (imported: Int, skipped: Int) {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month], from: earliestDate, to: endDate)
        let totalMonths = Double(components.month ?? 0)

        await MainActor.run {
            importStatus = "Preparing to import \(Int(totalMonths)) months of data..."
        }

        var currentDate = earliestDate
        var totalImported = 0
        var totalSkipped = 0
        var processedMonths = 0.0
        let batchSizeMonths = 3  // Process 3 months at a time

        while currentDate < endDate {
            let batchEndDate = calendar.date(byAdding: .month, value: batchSizeMonths, to: currentDate) ?? endDate
            let actualBatchEndDate = min(batchEndDate, endDate)

            // Update status
            let year = calendar.component(.year, from: currentDate)
            let month = calendar.component(.month, from: currentDate)
            await MainActor.run {
                importStatus = "Importing \(year)/\(month)..."
            }

            // Fetch weight and body fat data for this batch
            let weightBatch = try await fetchWeightImportSamplesInRange(
                startDate: currentDate,
                endDate: actualBatchEndDate
            )
            let bodyFatBatch = try await fetchBodyFatImportSamples(startDate: currentDate)
                .filter { $0.date < actualBatchEndDate }

            // Process this batch
            let (imported, skipped) = await processBatchHealthKitData(
                weightHistory: weightBatch,
                bodyFatHistory: bodyFatBatch
            )

            totalImported += imported
            totalSkipped += skipped

            // Update progress
            processedMonths += Double(batchSizeMonths)
            let progress = totalMonths > 0 ? min(processedMonths / totalMonths, 1.0) : 1.0
            await MainActor.run {
                importProgress = progress
                importedCount = totalImported
                if totalMonths > 0 {
                    let remaining = max(0, Int(totalMonths - processedMonths))
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

func forceFullHealthKitSync() async {
        _ = await syncAllHistoricalHealthKitData()
    }

func getEarliestWeightDate() async throws -> Date? {
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
        bodyFatHistory: [HealthKitBodyFatImportSample]
    ) async -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0

        // Create a dictionary of body fat data by logged local day
        var bodyFatByDate: [String: HealthKitBodyFatImportSample] = [:]
        for sample in bodyFatHistory {
            bodyFatByDate[BodyMetricLocalDate.key(for: sample.date)] = sample
        }

        // Get existing entries for this date range to check for duplicates
        guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else {
            return (0, 0)
        }

        let dateRange = weightHistory.map { $0.date } + bodyFatHistory.map { $0.date }
        let minDate = dateRange.min() ?? Date()
        let maxDate = dateRange.max() ?? Date()
        let calendar = Calendar.current
        let fetchStartDate = calendar.date(byAdding: .day, value: -1, to: minDate) ?? minDate
        let fetchEndDate = calendar.date(byAdding: .day, value: 1, to: maxDate) ?? maxDate

        let existingMetrics = await CoreDataManager.shared.fetchBodyMetrics(
            for: userId,
            from: fetchStartDate,
            to: fetchEndDate
        )

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
                    try await saveBodyMetrics(metrics)
                    imported += 1
                    existingEntriesByHour.insert(hourKey) // Add to set to prevent duplicates in same batch
                } catch {
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
            BodyScoreCache.shared.invalidate(for: userId)
            BodyScoreRecalculationService.shared.scheduleRecalculation()
        }

        return (imported, skipped)
    }

func saveBodyMetrics(_ metrics: BodyMetrics) async throws {
        guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else {
            throw HealthKitError.notAuthorized
        }

        // Create a new metrics instance with the correct user ID
        let metricsWithUserId = BodyMetrics(
            id: metrics.id,
            userId: userId,
            date: metrics.date,
            localDate: metrics.localDate,
            weight: metrics.weight,
            weightUnit: metrics.weightUnit,
            bodyFatPercentage: metrics.bodyFatPercentage,
            bodyFatMethod: metrics.bodyFatMethod,
            muscleMass: metrics.muscleMass,
            boneMass: metrics.boneMass,
            notes: metrics.notes,
            photoUrl: metrics.photoUrl,
            dataSource: metrics.dataSource,
            sourceMetadata: metrics.sourceMetadata,
            createdAt: metrics.createdAt,
            updatedAt: metrics.updatedAt
        )

        // Save to CoreData and trigger realtime sync to Supabase
        try await CoreDataManager.shared.saveBodyMetricsAndWait(metricsWithUserId, userId: userId, markAsSynced: false)
        await RealtimeSyncManager.shared.syncIfNeeded()
    }

func syncStepsFromHealthKit() async throws {
        let stepHistory = try await fetchStepCountHistory(days: 365) // Get last year of data

        for (stepCount, date) in stepHistory {
            try await syncSingleStepFromHistory(stepCount: stepCount, date: date)
        }
    }

func syncSingleStepFromHistory(stepCount: Int, date: Date) async throws {
        // Only sync if steps > 0 and entry doesn't exist
        guard stepCount > 0 else { return }

        let exists = await dailyMetricsExists(for: date)
        if !exists {
            try await saveDailySteps(steps: stepCount, date: date)
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
