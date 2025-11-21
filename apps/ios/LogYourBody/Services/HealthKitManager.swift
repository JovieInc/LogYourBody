//
// HealthKitManager.swift
// LogYourBody
//
import Foundation
import HealthKit

enum HealthKitDefaultsKey: String {
    case lastObserverSyncDate = "lastHealthKitObserverSyncDate"
    case fullSyncCompleted = "hasPerformedFullHealthKitSync"

    func scoped(with userId: String?) -> String {
        guard let userId = userId, !userId.isEmpty else {
            return rawValue
        }
        return "\(rawValue)_\(userId)"
    }
}

class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    private let healthStore = HKHealthStore()
    private let userDefaults = UserDefaults.standard

    @Published var isAuthorized = false
    @Published var latestWeight: Double?
    @Published var latestWeightDate: Date?
    @Published var latestBodyFatPercentage: Double?
    @Published var latestBodyFatDate: Date?
    @Published var todayStepCount: Int = 0
    @Published var latestStepCount: Int?
    @Published var latestStepCountDate: Date?

    // Import progress tracking
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0  // 0.0 to 1.0
    @Published var importStatus: String = ""
    @Published var importedCount: Int = 0
    @Published var totalToImport: Int = 0

    // Health types - using computed properties to avoid crashes if HealthKit types fail to initialize
    private var weightType: HKQuantityType {
        return HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    }
    private var bodyFatType: HKQuantityType {
        return HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!
    }
    private var heightType: HKQuantityType {
        return HKQuantityType.quantityType(forIdentifier: .height)!
    }
    private var dateOfBirthType: HKCharacteristicType {
        return HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth)!
    }
    private var stepCountType: HKQuantityType {
        return HKQuantityType.quantityType(forIdentifier: .stepCount)!
    }

    // Sync management
    private var isSyncingWeight = false
    private var syncDebounceTimer: Timer?
    private var weightObserverQuery: HKObserverQuery?
    private var stepObserverQuery: HKObserverQuery?
    private var activeQueries: [HKQuery] = []
    private var activeUserId: String?

    // Check if HealthKit is available
    var isHealthKitAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }

    // Check authorization status
    func checkAuthorizationStatus() {
        guard isHealthKitAvailable else {
            isAuthorized = false
            return
        }

        // Check if we have any permissions for weight data
        // Note: We can't check read permissions directly, but we can check write permissions
        let writeStatus = healthStore.authorizationStatus(for: weightType)

        // If we have write permission, we're authorized
        // If not, we check if we can read by trying to query
        if writeStatus == .sharingAuthorized {
            isAuthorized = true
        } else {
            // Try to read to check if we have read permission
            Task {
                do {
                    _ = try await fetchLatestWeight()
                    await MainActor.run {
                        self.isAuthorized = true
                    }
                } catch {
                    await MainActor.run {
                        self.isAuthorized = false
                    }
                }
            }
        }
    }

    // Fetch latest height from HealthKit
    func fetchLatestHeight() async throws -> (value: Double?, date: Date?) {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let heightInMeters = sample.quantity.doubleValue(for: HKUnit.meter())
                    let heightInCentimeters = heightInMeters * 100
                    continuation.resume(returning: (heightInCentimeters, sample.startDate))
                } else {
                    continuation.resume(returning: (nil, nil))
                }
            }

            healthStore.execute(query)
        }
    }

    private func persistHealthKitSamples(_ samples: [HKQuantitySample], unit: HKUnit) {
        guard !samples.isEmpty else { return }

        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else { return }

            for sample in samples {
                let metadata = self.metadataDictionary(from: sample.metadata)
                let hkSample = HKRawSample(
                    id: UUID().uuidString,
                    userId: userId,
                    hkUUID: sample.uuid.uuidString,
                    quantityType: sample.quantityType.identifier,
                    value: sample.quantity.doubleValue(for: unit),
                    unit: unit.unitString,
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    sourceName: sample.sourceRevision.source.name,
                    sourceBundleId: sample.sourceRevision.source.bundleIdentifier,
                    deviceManufacturer: sample.device?.manufacturer,
                    deviceModel: sample.device?.model,
                    deviceHardwareVersion: sample.device?.hardwareVersion,
                    deviceFirmwareVersion: sample.device?.firmwareVersion,
                    deviceSoftwareVersion: sample.device?.softwareVersion,
                    deviceLocalIdentifier: sample.device?.localIdentifier,
                    deviceUDI: sample.device?.udiDeviceIdentifier,
                    metadata: metadata,
                    createdAt: Date(),
                    updatedAt: Date()
                )

                await CoreDataManager.shared.saveHKSample(hkSample)
            }
        }
    }

    private func metadataDictionary(from metadata: [String: Any]?) -> [String: String]? {
        guard let metadata = metadata else { return nil }
        var result: [String: String] = [:]

        let formatter = ISO8601DateFormatter()

        for (key, value) in metadata {
            switch value {
            case let string as String:
                result[key] = string
            case let number as NSNumber:
                result[key] = number.stringValue
            case let date as Date:
                result[key] = formatter.string(from: date)
            case let bool as Bool:
                result[key] = bool ? "true" : "false"
            default:
                result[key] = "\(value)"
            }
        }

        return result.isEmpty ? nil : result
    }

    // Request authorization
    func requestAuthorization() async -> Bool {
        guard isHealthKitAvailable else { return false }

        let typesToRead: Set<HKObjectType> = [weightType, bodyFatType, heightType, dateOfBirthType, stepCountType]
        let typesToWrite: Set<HKQuantityType> = [weightType, bodyFatType]

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)

            // Check if we got permission
            let status = healthStore.authorizationStatus(for: weightType)
            await MainActor.run {
                self.isAuthorized = (status == .sharingAuthorized)
            }

            return isAuthorized
        } catch {
            // print("HealthKit authorization failed: \(error)")
            return false
        }
    }

    // Save weight to HealthKit
    func saveWeight(_ weight: Double, date: Date = Date()) async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        // Convert to kg (HealthKit uses kg internally)
        let weightInKg = weight * 0.453592 // Convert lbs to kg
        let quantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: weightInKg)

        let sample = HKQuantitySample(
            type: weightType,
            quantity: quantity,
            start: date,
            end: date
        )

        try await healthStore.save(sample)
    }

    // Fetch latest weight from HealthKit
    func fetchLatestWeight() async throws -> (weight: Double?, date: Date?) {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

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
                    let weightInKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                    let weightInLbs = weightInKg * 2.20462 // Convert kg to lbs

                    Task {
                        await MainActor.run {
                            self.latestWeight = weightInLbs
                            self.latestWeightDate = sample.startDate
                        }
                    }

                    continuation.resume(returning: (weightInLbs, sample.startDate))
                } else {
                    continuation.resume(returning: (nil, nil))
                }
            }

            healthStore.execute(query)
        }
    }

    // Fetch weight history
    func fetchWeightHistory(days: Int = 30) async throws -> [(weight: Double, date: Date)] {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let endDate = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) else {
            return []
        }

        return try await fetchWeightHistoryInRange(startDate: startDate, endDate: endDate)
    }

    // New function to fetch weight history in a specific date range
    func fetchWeightHistoryInRange(startDate: Date, endDate: Date) async throws -> [(weight: Double, date: Date)] {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(returning: [])
                return
            }
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let hkSamples = samples as? [HKQuantitySample] ?? []
                self.persistHealthKitSamples(hkSamples, unit: HKUnit.gramUnit(with: .kilo))

                let results = hkSamples.map { sample in
                    let weightInKg = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                    return (weight: weightInKg, date: sample.startDate)  // Return in kg
                }

                continuation.resume(returning: results)
            }

            healthStore.execute(query)
        }
    }

    // Fetch latest body fat percentage from HealthKit
    func fetchLatestBodyFatPercentage() async throws -> (percentage: Double?, date: Date?) {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(returning: (nil, nil))
                return
            }
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: bodyFatType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    self.persistHealthKitSamples([sample], unit: HKUnit.percent())
                    let percentage = sample.quantity.doubleValue(for: HKUnit.percent()) * 100 // Convert to percentage
                    continuation.resume(returning: (percentage, sample.startDate))
                } else {
                    continuation.resume(returning: (nil, nil))
                }
            }

            healthStore.execute(query)
        }
    }

    // Fetch body fat percentage history
    func fetchBodyFatHistory(startDate: Date) async throws -> [(percentage: Double, date: Date)] {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: Date(),
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(returning: [])
                return
            }
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

            let query = HKSampleQuery(
                sampleType: bodyFatType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let hkSamples = samples as? [HKQuantitySample] ?? []
                self.persistHealthKitSamples(hkSamples, unit: HKUnit.percent())

                let results = hkSamples.map { sample in
                    let percentage = sample.quantity.doubleValue(for: HKUnit.percent()) * 100
                    return (percentage: percentage, date: sample.startDate)
                }

                continuation.resume(returning: results)
            }

            healthStore.execute(query)
        }
    }

    // Save body fat percentage to HealthKit
    func saveBodyFatPercentage(_ percentage: Double, date: Date = Date()) async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        // Convert percentage to decimal (HealthKit uses 0-1 range)
        let decimal = percentage / 100.0
        let quantity = HKQuantity(unit: HKUnit.percent(), doubleValue: decimal)

        let sample = HKQuantitySample(
            type: bodyFatType,
            quantity: quantity,
            start: date,
            end: date
        )

        try await healthStore.save(sample)
    }

    // Setup background delivery for weight and body fat changes
    func setupBackgroundDelivery() async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        try await healthStore.enableBackgroundDelivery(
            for: weightType,
            frequency: .immediate
        )

        try await healthStore.enableBackgroundDelivery(
            for: bodyFatType,
            frequency: .immediate
        )
    }

    // Sync weight data with backend
    func syncWeightWithBackend(weight: Double, date: Date) async throws {
        guard let url = URL(string: "\(Constants.baseURL)/api/weight") else {
            throw HealthKitError.syncFailed
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard await AuthManager.shared.isAuthenticated,
              let token = await AuthManager.shared.getAccessToken() else {
            throw HealthKitError.notAuthorized
        }

        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Convert weight to kg for backend (matching web app)
        let weightInKg = weight * 0.453592

        let body: [String: Any] = [
            "weight": weightInKg,
            "unit": "kg",
            "date": ISO8601DateFormatter().string(from: date)
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HealthKitError.syncFailed
        }
    }

    // Fetch user's height from HealthKit
    func fetchHeight() async throws -> Double? {
        guard isHealthKitAvailable else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let sample = samples?.first as? HKQuantitySample {
                    let heightInMeters = sample.quantity.doubleValue(for: HKUnit.meter())
                    let heightInInches = heightInMeters * 39.3701 // Convert meters to inches
                    continuation.resume(returning: heightInInches)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            healthStore.execute(query)
        }
    }

    // Fetch user's date of birth from HealthKit
    func fetchDateOfBirth() -> Date? {
        guard isHealthKitAvailable else { return nil }

        do {
            let dateOfBirth = try healthStore.dateOfBirthComponents()
            return Calendar.current.date(from: dateOfBirth)
        } catch {
            // print("Failed to fetch date of birth: \(error)")
            return nil
        }
    }

    // Fetch user's biological sex from HealthKit
    func fetchBiologicalSex() -> String? {
        guard isHealthKitAvailable else { return nil }

        do {
            let biologicalSex = try healthStore.biologicalSex()
            switch biologicalSex.biologicalSex {
            case .male:
                return "Male"
            case .female:
                return "Female"
            case .other, .notSet:
                return nil
            @unknown default:
                return nil
            }
        } catch {
            // print("Failed to fetch biological sex: \(error)")
            return nil
        }
    }

    // Fetch today's step count
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

    // Fetch step count for a specific date
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

    // Fetch weight data from HealthKit
    func fetchWeightData(days: Int = 30) async throws -> [WeightEntry] {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self else {
                continuation.resume(returning: [])
                return
            }

            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { [weak self] _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                var weightEntries: [WeightEntry] = []

                if let samples = samples as? [HKQuantitySample], let self {
                    let storageUnit = HKUnit.gramUnit(with: .kilo)
                    self.persistHealthKitSamples(samples, unit: storageUnit)

                    for sample in samples {
                        let usesMetric = UserDefaults.standard.string(forKey: Constants.preferredWeightUnitKey) == "kg"
                        let preferredUnit = usesMetric ? HKUnit.gramUnit(with: .kilo) : HKUnit.pound()
                        let weight = sample.quantity.doubleValue(for: preferredUnit)
                        let entry = WeightEntry(
                            id: UUID().uuidString,
                            userId: "", // Will be filled by SyncManager
                            weight: weight,
                            weightUnit: UserDefaults.standard.string(forKey: Constants.preferredWeightUnitKey) ?? "lbs",
                            notes: nil,
                            loggedAt: sample.startDate
                        )
                        weightEntries.append(entry)
                    }
                }

                continuation.resume(returning: weightEntries)
            }

            healthStore.execute(query)
        }
    }

    // Sync ALL weight and body fat data from HealthKit to app
    func syncWeightFromHealthKit() async throws {
        // Prevent concurrent syncs
        guard !isSyncingWeight else {
            // print("⚠️ Weight sync already in progress, skipping")
            return
        }

        // print("📊 Starting comprehensive weight sync from HealthKit...")
        isSyncingWeight = true
        defer {
            isSyncingWeight = false
            // print("✅ Weight sync completed")
        }

        // First, do a quick sync of recent data (last 30 days) for immediate UI update
        let endDate = Date()
        let recentStartDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!

        // print("📅 Phase 1: Fetching recent data (30 days)")

        // Fetch recent weight and body fat data
        let recentWeightHistory = try await fetchWeightHistory(days: 30)
        let recentBodyFatHistory = try await fetchBodyFatHistory(startDate: recentStartDate)

        // print("📈 Found \(recentWeightHistory.count) weight entries and \(recentBodyFatHistory.count) body fat entries")

        if !recentWeightHistory.isEmpty {
            // print("  📅 Weight entries date range: \(recentWeightHistory.first?.date ?? Date()) to \(recentWeightHistory.last?.date ?? Date())")
            for (index, (weight, date)) in recentWeightHistory.enumerated() {
                if index < 5 {  // Show first 5 entries
                    // print("    - \(date): \(weight)kg")
                }
            }
        }

        // Process recent data for immediate UI update
        let (imported, skipped) = await processBatchHealthKitData(
            weightHistory: recentWeightHistory,
            bodyFatHistory: recentBodyFatHistory
        )

        // print("📊 Recent sync: \(imported) imported, \(skipped) skipped")

        // Only trigger full historical sync if this is truly the first time and we have very little data
        let hasPerformedFullSync = UserDefaults.standard.bool(forKey: "hasPerformedFullHealthKitSync")
        let totalCachedEntries: Int
        let userId = await MainActor.run { AuthManager.shared.currentUser?.id }
        if let userId = userId {
            totalCachedEntries = await CoreDataManager.shared.fetchBodyMetrics(for: userId).count
        } else {
            totalCachedEntries = 0
        }

        if !hasPerformedFullSync {
            // print("📊 First time sync detected, scheduling full historical sync...")
            // print("📊 Current cached entries: \(totalCachedEntries)")
            Task.detached(priority: .background) {
                await self.syncAllHistoricalHealthKitData()
                UserDefaults.standard.set(true, forKey: "hasPerformedFullHealthKitSync")
            }
        } else if totalCachedEntries < 50 && imported > 0 {
            // Also trigger if we have very few entries despite having done a sync before
            // print("📊 Low entry count detected (\(totalCachedEntries)), triggering full sync...")
            Task.detached(priority: .background) {
                await self.syncAllHistoricalHealthKitData()
            }
        }
    }

    // Background incremental sync for longer time periods (30 days at a time)
    func syncWeightFromHealthKitIncremental(days: Int = 30, startDate: Date? = nil) async throws {
        // Prevent concurrent syncs
        guard !isSyncingWeight else {
            // print("⚠️ Weight sync already in progress, skipping incremental sync")
            return
        }

        // print("📊 Starting incremental weight sync from HealthKit (\(days) days)...")
        isSyncingWeight = true
        defer {
            isSyncingWeight = false
            // print("✅ Incremental weight sync completed")
        }

        let endDate = startDate ?? Date()
        let batchStartDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

        // print("📅 Fetching data from \(batchStartDate) to \(endDate)")

        // Fetch weight and body fat data for the specified period
        // Calculate days between dates
        let daysBetween = Calendar.current.dateComponents([.day], from: batchStartDate, to: endDate).day ?? 30
        let weightHistory = try await fetchWeightHistory(days: daysBetween)
            .filter { $0.date >= batchStartDate && $0.date <= endDate }
        let bodyFatHistory = try await fetchBodyFatHistory(startDate: batchStartDate)
            .filter { $0.date <= endDate }

        // print("📈 Found \(weightHistory.count) weight entries and \(bodyFatHistory.count) body fat entries")

        if !weightHistory.isEmpty {
            // print("  📅 Weight entries date range: \(weightHistory.first?.date ?? Date()) to \(weightHistory.last?.date ?? Date())")
            for (index, (weight, date)) in weightHistory.enumerated() {
                if index < 5 {  // Show first 5 entries
                    // print("    - \(date): \(weight)kg")
                }
            }
        }

        // Create a dictionary of body fat data by date for easy lookup
        var bodyFatByDate: [Date: Double] = [:]
        for (percentage, date) in bodyFatHistory {
            let normalizedDate = Calendar.current.startOfDay(for: date)
            bodyFatByDate[normalizedDate] = percentage
        }

        // Process weight entries and match with body fat if available
        var newEntriesCount = 0
        var skippedEntriesCount = 0

        for (weight, date) in weightHistory {
            // Check if this entry already exists (by date)
            let exists = await weightEntryExists(for: date)

            if !exists {
                newEntriesCount += 1
                // Check if we have body fat data for the same day
                let normalizedDate = Calendar.current.startOfDay(for: date)
                let bodyFatPercentage = bodyFatByDate[normalizedDate]

                // Create body metrics with both weight and body fat
                let metrics = BodyMetrics(
                    id: UUID().uuidString,
                    userId: "", // Will be filled by SyncManager
                    date: date,
                    weight: weight,  // Already in kg from fetchWeightHistory
                    weightUnit: "kg",  // Always store in kg
                    bodyFatPercentage: bodyFatPercentage,
                    bodyFatMethod: bodyFatPercentage != nil ? "HealthKit" : nil,
                    muscleMass: nil,
                    boneMass: nil,
                    notes: "Imported from HealthKit (incremental)",
                    photoUrl: nil,
                    dataSource: "HealthKit",
                    createdAt: Date(),
                    updatedAt: Date()
                )

                // Save to local storage and sync to backend
                try await saveBodyMetrics(metrics)
            }
        }

        // Also check for standalone body fat entries (without weight)
        for (percentage, date) in bodyFatHistory {
            let normalizedDate = Calendar.current.startOfDay(for: date)

            // Check if we already processed this with weight data
            let alreadyProcessed = weightHistory.contains { _, weightDate in
                Calendar.current.startOfDay(for: weightDate) == normalizedDate
            }

            if !alreadyProcessed {
                let exists = await dailyMetricsExists(for: date)

                if !exists {
                    // Create body metrics with just body fat
                    let metrics = BodyMetrics(
                        id: UUID().uuidString,
                        userId: "", // Will be filled by SyncManager
                        date: date,
                        weight: nil,
                        weightUnit: nil,
                        bodyFatPercentage: percentage,
                        bodyFatMethod: "HealthKit",
                        muscleMass: nil,
                        boneMass: nil,
                        notes: "Body fat imported from HealthKit (incremental)",
                        photoUrl: nil,
                        dataSource: "HealthKit",
                        createdAt: Date(),
                        updatedAt: Date()
                    )

                    try await saveBodyMetrics(metrics)
                }
            }
        }
    }

    // Sync ALL historical HealthKit data efficiently
    func syncAllHistoricalHealthKitData() async {
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
            importStatus = "Starting import..."
            importedCount = 0
            totalToImport = 0
        }

        do {
            // Get the earliest available weight data date
            let defaultHistoricalRange = TimeInterval(10 * 365 * 24 * 60 * 60)
            let earliestDate = try await getEarliestWeightDate()
                ?? Date().addingTimeInterval(-defaultHistoricalRange) // Default to 10 years ago
            let endDate = Date()

            // Calculate total months to process
            let calendar = Calendar.current
            let components = calendar.dateComponents([.month], from: earliestDate, to: endDate)
            let totalMonths = Double(components.month ?? 0)

            await MainActor.run {
                importStatus = "Preparing to import \(Int(totalMonths)) months of data..."
            }

            // Process in larger batches (3 months at a time) for faster sync
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
                let weightBatch = try await fetchWeightHistoryInRange(startDate: currentDate, endDate: actualBatchEndDate)
                let bodyFatBatch = try await fetchBodyFatHistory(startDate: currentDate)
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
        } catch {
            await MainActor.run {
                importProgress = 0.0
                importStatus = "Import failed: \(error.localizedDescription)"
                isImporting = false
            }
        }
    }

    // Get the earliest weight entry date from HealthKit
    private func getEarliestWeightDate() async throws -> Date? {
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

    // Process a batch of HealthKit data and return (imported, skipped) counts
    private func processBatchHealthKitData(
        weightHistory: [(weight: Double, date: Date)],
        bodyFatHistory: [(percentage: Double, date: Date)]
    ) async -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0

        // Create a dictionary of body fat data by date
        var bodyFatByDate: [Date: Double] = [:]
        for (percentage, date) in bodyFatHistory {
            let normalizedDate = Calendar.current.startOfDay(for: date)
            bodyFatByDate[normalizedDate] = percentage
        }

        // Get existing entries for this date range to check for duplicates
        guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else {
            return (0, 0)
        }

        let dateRange = weightHistory.map { $0.date } + bodyFatHistory.map { $0.date }
        let minDate = dateRange.min() ?? Date()
        let maxDate = dateRange.max() ?? Date()

        let existingMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId, from: minDate, to: maxDate)

        // Create a set of existing entries by date and hour for efficient lookup
        var existingEntriesByHour = Set<String>()
        for metric in existingMetrics {
            if let date = metric.date {
                let calendar = Calendar.current
                let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
                if let roundedDate = calendar.date(from: components) {
                    let key = ISO8601DateFormatter().string(from: roundedDate)
                    existingEntriesByHour.insert(key)
                }
            }
        }

        for (weight, date) in weightHistory {
            // Check if entry exists within the same hour
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
            let roundedDate = calendar.date(from: components) ?? date
            let hourKey = ISO8601DateFormatter().string(from: roundedDate)

            if !existingEntriesByHour.contains(hourKey) {
                let normalizedDate = calendar.startOfDay(for: date)
                let bodyFatPercentage = bodyFatByDate[normalizedDate]

                let metrics = BodyMetrics(
                    id: UUID().uuidString,
                    userId: userId,
                    date: date,
                    weight: weight,
                    weightUnit: "kg",
                    bodyFatPercentage: bodyFatPercentage,
                    bodyFatMethod: bodyFatPercentage != nil ? "HealthKit" : nil,
                    muscleMass: nil,
                    boneMass: nil,
                    notes: "Imported from HealthKit",
                    photoUrl: nil,
                    dataSource: "HealthKit",
                    createdAt: Date(),
                    updatedAt: Date()
                )

                do {
                    try await saveBodyMetrics(metrics)
                    imported += 1
                    existingEntriesByHour.insert(hourKey) // Add to set to prevent duplicates in same batch
                } catch {
                    // print("Failed to save entry: \(error)")
                }
            } else {
                skipped += 1
            }
        }

        return (imported, skipped)
    }

    // Helper function to save body metrics
    private func saveBodyMetrics(_ metrics: BodyMetrics) async throws {
        guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else {
            throw HealthKitError.notAuthorized
        }

        // Create a new metrics instance with the correct user ID
        let metricsWithUserId = BodyMetrics(
            id: metrics.id,
            userId: userId,
            date: metrics.date,
            weight: metrics.weight,
            weightUnit: metrics.weightUnit,
            bodyFatPercentage: metrics.bodyFatPercentage,
            bodyFatMethod: metrics.bodyFatMethod,
            muscleMass: metrics.muscleMass,
            boneMass: metrics.boneMass,
            notes: metrics.notes,
            photoUrl: metrics.photoUrl,
            dataSource: metrics.dataSource,
            createdAt: metrics.createdAt,
            updatedAt: metrics.updatedAt
        )

        // Save to CoreData and trigger realtime sync to Supabase
        await MainActor.run {
            CoreDataManager.shared.saveBodyMetrics(metricsWithUserId, userId: userId, markAsSynced: false)
        }
        await RealtimeSyncManager.shared.syncIfNeeded()
    }

    // Sync step count data from HealthKit to app
    func syncStepsFromHealthKit() async throws {
        let stepHistory = try await fetchStepCountHistory(days: 365) // Get last year of data

        for (stepCount, date) in stepHistory {
            // Only sync if steps > 0 and entry doesn't exist
            if stepCount > 0 {
                let exists = await dailyMetricsExists(for: date)
                if !exists {
                    try await saveDailySteps(steps: stepCount, date: date)
                }
            }
        }
    }

    // Setup observer for new weight entries in HealthKit
    func observeWeightChanges() {
        guard isAuthorized else { return }

        let query = HKObserverQuery(sampleType: weightType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                // Check if we should sync (not more than once per hour)
                let lastSyncKey = "lastHealthKitObserverSyncDate"
                let shouldSync: Bool = {
                    if let lastSync = UserDefaults.standard.object(forKey: lastSyncKey) as? Date {
                        let minutesSinceLastSync = Date().timeIntervalSince(lastSync) / 60
                        return minutesSinceLastSync >= 60 // Only sync if more than 60 minutes have passed
                    }
                    return true
                }()

                if shouldSync {
                    // Debounce sync requests to prevent multiple concurrent syncs
                    DispatchQueue.main.async { [weak self] in
                        self?.syncDebounceTimer?.invalidate()
                        self?.syncDebounceTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                            UserDefaults.standard.set(Date(), forKey: lastSyncKey)
                            Task { [weak self] in
                                // Only sync recent data (last 7 days) when observer triggers
                                try? await self?.syncWeightFromHealthKitIncremental(days: 7)
                            }
                        }
                    }
                }
            }
            completionHandler()
        }

        healthStore.execute(query)
    }

    // Setup observer for new step count entries in HealthKit
    func observeStepChanges() {
        guard isAuthorized else { return }

        // Stop any existing step observer queries
        activeQueries.filter { $0 is HKObserverQuery && ($0 as? HKObserverQuery)?.sampleType == stepCountType }.forEach {
            healthStore.stop($0)
        }
        activeQueries.removeAll { $0 is HKObserverQuery && ($0 as? HKObserverQuery)?.sampleType == stepCountType }

        let query = HKObserverQuery(sampleType: stepCountType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                // New step data available, sync it
                Task { @MainActor [weak self] in
                    guard let self = self else { return }

                    // Sync today's steps
                    try? await self.syncStepsFromHealthKit()

                    // Notify sync manager to sync with remote
                    if let userId = AuthManager.shared.currentUser?.id {
                        await self.syncStepsToSupabase(userId: userId)
                    }
                }
            }
            completionHandler()
        }

        healthStore.execute(query)
        activeQueries.append(query)

        // Enable background delivery for real-time updates
        Task {
            await enableBackgroundStepDelivery()
        }
    }

    // Enable background delivery for steps
    private func enableBackgroundStepDelivery() async {
        guard isAuthorized else { return }

        do {
            try await healthStore.enableBackgroundDelivery(
                for: stepCountType,
                frequency: .immediate
            )
            // print("✅ Enabled background step delivery")
        } catch {
            // print("❌ Failed to enable background step delivery: \(error)")
        }
    }

    // Fetch step count history
    func fetchStepCountHistory(days: Int = 30) async throws -> [(stepCount: Int, date: Date)] {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
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

    // Setup background delivery for step count changes
    func setupStepCountBackgroundDelivery() async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        try await healthStore.enableBackgroundDelivery(
            for: stepCountType,
            frequency: .immediate
        )
    }

    // MARK: - Step Syncing to Supabase

    func syncStepsToSupabase(userId: String) async {
        // Get today's steps
        let todaySteps = self.todayStepCount
        guard todaySteps > 0 else { return }

        // Get or create today's daily metrics
        let today = Date()
        var metrics = await Task.detached {
            await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: today)?.toDailyMetrics()
        }.value

        if metrics == nil {
            // Create new daily metrics
            metrics = DailyMetrics(
                id: UUID().uuidString,
                userId: userId,
                date: today,
                steps: todaySteps,
                notes: nil,
                createdAt: today,
                updatedAt: today
            )
        } else if var existingMetrics = metrics {
            // Update existing metrics with new step count
            metrics = DailyMetrics(
                id: existingMetrics.id,
                userId: existingMetrics.userId,
                date: existingMetrics.date,
                steps: todaySteps,
                notes: existingMetrics.notes,
                createdAt: existingMetrics.createdAt,
                updatedAt: Date()
            )
        }

        // Save to Core Data
        if let metrics = metrics {
            await CoreDataManager.shared.saveDailyMetrics(metrics, userId: userId)

            // Trigger sync to remote
            Task.detached {
                await RealtimeSyncManager.shared.syncIfNeeded()
            }
        }
    }

    // Force a full HealthKit sync
    func forceFullHealthKitSync() async {
        // print("🔄 Force full HealthKit sync requested")
        // Clear the flag to force a full sync
        UserDefaults.standard.set(false, forKey: "hasPerformedFullHealthKitSync")

        // Trigger the sync
        do {
            try await syncWeightFromHealthKit()
        } catch {
            // print("❌ Force sync failed: \(error)")
        }
    }

    // Sync historical step data
    func syncHistoricalSteps(userId: String, days: Int = 30) async throws {
        let historicalData = try await fetchStepCountHistory(days: days)

        for (stepCount, date) in historicalData {
            guard stepCount > 0 else { continue }

            // Check if we already have data for this date
            var metrics = await Task.detached {
                await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: date)?.toDailyMetrics()
            }.value

            if metrics == nil {
                // Create new daily metrics for historical date
                metrics = DailyMetrics(
                    id: UUID().uuidString,
                    userId: userId,
                    date: date,
                    steps: stepCount,
                    notes: nil,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            } else if var existingMetrics = metrics, existingMetrics.steps != stepCount {
                // Update if step count is different
                metrics = DailyMetrics(
                    id: existingMetrics.id,
                    userId: existingMetrics.userId,
                    date: existingMetrics.date,
                    steps: stepCount,
                    notes: existingMetrics.notes,
                    createdAt: existingMetrics.createdAt,
                    updatedAt: Date()
                )
            } else {
                // Skip if data is already up to date
                continue
            }

            // Save to Core Data
            if let metrics = metrics {
                await CoreDataManager.shared.saveDailyMetrics(metrics, userId: userId)
            }
        }

        // Sync all historical data to remote
        Task.detached {
            await RealtimeSyncManager.shared.syncAll()
        }
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

    func dailyMetricsExists(for date: Date) async -> Bool {
        guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else { return false }

        return await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: date) != nil
    }

    func saveDailySteps(steps: Int, date: Date) async throws {
        guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else {
            throw HealthKitError.notAuthorized
        }

        let metrics = DailyMetrics(
            id: UUID().uuidString,
            userId: userId,
            date: date,
            steps: steps,
            notes: "Imported from HealthKit",
            createdAt: Date(),
            updatedAt: Date()
        )

        await CoreDataManager.shared.saveDailyMetrics(metrics, userId: userId)
        await RealtimeSyncManager.shared.syncIfNeeded()
    }
}

enum HealthKitError: Error, LocalizedError {
    case notAuthorized
    case syncFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "HealthKit access not authorized"
        case .syncFailed:
            return "Failed to sync weight data"
        }
    }
}
