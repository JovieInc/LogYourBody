import Foundation
import HealthKit

extension HealthKitManager {
var weightType: HKQuantityType {
        return HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    }

var bodyFatType: HKQuantityType {
        return HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!
    }

var heightType: HKQuantityType {
        return HKQuantityType.quantityType(forIdentifier: .height)!
    }

var dateOfBirthType: HKCharacteristicType {
        return HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth)!
    }

var stepCountType: HKQuantityType {
        return HKQuantityType.quantityType(forIdentifier: .stepCount)!
    }

func beginWeightSyncIfPossible() -> Bool {
        var canStart = false
        syncStateQueue.sync {
            if !isSyncingWeight {
                isSyncingWeight = true
                canStart = true
            }
        }
        return canStart
    }

func endWeightSync() {
        syncStateQueue.sync {
            isSyncingWeight = false
        }
    }

var isHealthKitAvailable: Bool {
        return HKHealthStore.isHealthDataAvailable()
    }

func hasConfirmedAuthorization() -> Bool {
        userDefaults.bool(forKey: HealthKitDefaultsKey.authorizationConfirmed.rawValue)
    }

func markAuthorizationConfirmed() {
        userDefaults.set(true, forKey: HealthKitDefaultsKey.authorizationConfirmed.rawValue)
    }

func checkAuthorizationStatus() {
        guard isHealthKitAvailable else {
            isAuthorized = false
            return
        }

        let writeStatus = healthStore.authorizationStatus(for: weightType)
        isAuthorized = HealthKitAuthorizationPolicy.isAuthorized(
            writeStatus: writeStatus,
            hasConfirmedReadAccess: hasConfirmedAuthorization()
        )
    }

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

func persistHealthKitSamples(_ samples: [HKQuantitySample], unit: HKUnit) {
        guard !samples.isEmpty else { return }

        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else { return }
            var rawSamples: [HKRawSample] = []

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

                rawSamples.append(hkSample)
            }

            await CoreDataManager.shared.saveHKSamples(rawSamples)
        }
    }

func metadataDictionary(from metadata: [String: Any]?) -> [String: String]? {
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

func sourceMetadata(from sample: HKQuantitySample) -> BodyMetricSourceMetadata {
        let deviceId = sample.device?.localIdentifier ?? sample.device?.udiDeviceIdentifier

        return BodyMetricSourceMetadata(
            vendor: "apple_health",
            sourceName: sample.sourceRevision.source.name,
            sourceBundleId: sample.sourceRevision.source.bundleIdentifier,
            deviceId: deviceId,
            deviceManufacturer: sample.device?.manufacturer,
            deviceModel: sample.device?.model,
            sampleId: sample.uuid.uuidString,
            quantityType: sample.quantityType.identifier
        )
    }

func combinedHealthKitMetadata(
        weightMetadata: BodyMetricSourceMetadata?,
        bodyFatMetadata: BodyMetricSourceMetadata?
    ) -> BodyMetricSourceMetadata? {
        guard weightMetadata != nil || bodyFatMetadata != nil else { return nil }

        let primary = weightMetadata ?? bodyFatMetadata

        return BodyMetricSourceMetadata(
            vendor: primary?.vendor ?? "apple_health",
            sourceName: primary?.sourceName ?? bodyFatMetadata?.sourceName,
            sourceBundleId: primary?.sourceBundleId ?? bodyFatMetadata?.sourceBundleId,
            deviceId: primary?.deviceId ?? bodyFatMetadata?.deviceId,
            deviceManufacturer: primary?.deviceManufacturer ?? bodyFatMetadata?.deviceManufacturer,
            deviceModel: primary?.deviceModel ?? bodyFatMetadata?.deviceModel,
            sampleId: primary?.sampleId ?? bodyFatMetadata?.sampleId,
            quantityType: primary?.quantityType ?? bodyFatMetadata?.quantityType,
            bodyFatSampleId: bodyFatMetadata?.sampleId
        )
    }

func requestAuthorization() async -> Bool {
        guard isHealthKitAvailable else { return false }

        let typesToRead: Set<HKObjectType> = [weightType, bodyFatType, heightType, dateOfBirthType, stepCountType]
        let typesToWrite: Set<HKQuantityType> = [weightType, bodyFatType]

        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)

            let status = healthStore.authorizationStatus(for: weightType)
            let confirmedReadAccess = status == .sharingAuthorized ? true : await probeReadableHealthKitData()
            let authorized = HealthKitAuthorizationPolicy.isAuthorized(
                writeStatus: status,
                hasConfirmedReadAccess: confirmedReadAccess
            )
            if authorized {
                markAuthorizationConfirmed()
            }
            await MainActor.run {
                self.isAuthorized = authorized
            }

            return authorized
        } catch {
            await captureHealthKitError(
                error,
                operation: "requestAuthorization",
                contextDescription: "requestAuthorization"
            )
            // print("HealthKit authorization failed: \(error)")
            return false
        }
    }

func probeReadableHealthKitData() async -> Bool {
        if await hasReadableQuantitySample(weightType) {
            return true
        }
        if await hasReadableQuantitySample(bodyFatType) {
            return true
        }
        if await hasReadableQuantitySample(heightType) {
            return true
        }
        return false
    }

func hasReadableQuantitySample(_ sampleType: HKQuantityType) async -> Bool {
        await withCheckedContinuation { continuation in
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: sampleType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                continuation.resume(returning: error == nil && !(samples?.isEmpty ?? true))
            }

            healthStore.execute(query)
        }
    }

func saveWeight(_ weight: Double, date: Date = Date()) async throws {
        guard isAuthorized else {
            throw HealthKitError.notAuthorized
        }

        // Convert to kg (HealthKit uses kg internally)
        let weightInKg = weight.lbsToKg
        let quantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: weightInKg)

        let sample = HKQuantitySample(
            type: weightType,
            quantity: quantity,
            start: date,
            end: date
        )

        try await healthStore.save(sample)
    }

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
                    let weightInLbs = weightInKg.kgToLbs

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

func fetchWeightHistoryInRange(startDate: Date, endDate: Date) async throws -> [(weight: Double, date: Date)] {
        let samples = try await fetchWeightImportSamplesInRange(startDate: startDate, endDate: endDate)
        return samples.map { (weight: $0.weight, date: $0.date) }
    }

func fetchWeightImportSamplesInRange(
        startDate: Date,
        endDate: Date
    ) async throws -> [HealthKitWeightImportSample] {
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
                    return HealthKitWeightImportSample(
                        weight: weightInKg,
                        date: sample.startDate,
                        sourceMetadata: self.sourceMetadata(from: sample)
                    )
                }

                continuation.resume(returning: results)
            }

            healthStore.execute(query)
        }
    }

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

func fetchBodyFatHistory(startDate: Date) async throws -> [(percentage: Double, date: Date)] {
        let samples = try await fetchBodyFatImportSamples(startDate: startDate)
        return samples.map { (percentage: $0.percentage, date: $0.date) }
    }

func fetchBodyFatImportSamples(startDate: Date) async throws -> [HealthKitBodyFatImportSample] {
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
                    return HealthKitBodyFatImportSample(
                        percentage: percentage,
                        date: sample.startDate,
                        sourceMetadata: self.sourceMetadata(from: sample)
                    )
                }

                continuation.resume(returning: results)
            }

            healthStore.execute(query)
        }
    }

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

func resetForCurrentUser() async {
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
                operation: "resetForCurrentUser.disableAllBackgroundDelivery",
                contextDescription: "resetForCurrentUser.disableAllBackgroundDelivery"
            )
        }

        let userId = await MainActor.run { AuthManager.shared.currentUser?.id }
        let lastObserverKey = HealthKitDefaultsKey.lastObserverSyncDate.scoped(with: userId)
        let fullSyncKey = HealthKitDefaultsKey.fullSyncCompleted.scoped(with: userId)
        userDefaults.removeObject(forKey: HealthKitDefaultsKey.authorizationConfirmed.rawValue)
        userDefaults.removeObject(forKey: lastObserverKey)
        userDefaults.removeObject(forKey: fullSyncKey)

        await MainActor.run {
            self.isAuthorized = false
            self.latestWeight = nil
            self.latestWeightDate = nil
            self.latestBodyFatPercentage = nil
            self.latestBodyFatDate = nil
            self.todayStepCount = 0
            self.latestStepCount = nil
            self.latestStepCountDate = nil

            self.isImporting = false
            self.importProgress = 0.0
            self.importStatus = ""
            self.importedCount = 0
            self.totalToImport = 0
        }
    }

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
}
