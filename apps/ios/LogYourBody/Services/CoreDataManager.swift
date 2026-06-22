//
// CoreDataManager.swift
// LogYourBody
//
// THREADING SAFETY: All Core Data operations MUST use context.perform() or context.performAndWait()
// to avoid threading violations. The viewContext is bound to the main thread.
//
// ✅ COMPLETE: All methods now properly use context.perform() or context.performAndWait()
// All Core Data operations are now thread-safe and prevent data corruption and crashes.
//
import Foundation
import CoreData
import HealthKit

struct CachedUserProfileSnapshot {
    let profile: UserProfile
    let isSynced: Bool
    let syncStatus: String?
    let lastModified: Date?

    var hasPendingLocalChanges: Bool {
        !isSynced || syncStatus == "pending" || syncStatus == "failed"
    }
}

struct PendingLocalSyncSnapshot {
    let bodyMetrics: [PendingBodyMetricSyncItem]
    let dailyMetrics: [PendingDailyMetricSyncItem]
    let profiles: [PendingProfileSyncItem]
    let glp1DoseLogs: [PendingGlp1DoseLogSyncItem]
    let glp1Medications: [PendingGlp1MedicationSyncItem]
    let dexaResults: [PendingDexaResultSyncItem]

    static let empty = PendingLocalSyncSnapshot(
        bodyMetrics: [],
        dailyMetrics: [],
        profiles: [],
        glp1DoseLogs: [],
        glp1Medications: [],
        dexaResults: []
    )

    var counts: PendingLocalSyncCounts {
        PendingLocalSyncCounts(
            bodyMetrics: bodyMetrics.count,
            dailyMetrics: dailyMetrics.count,
            profiles: profiles.count,
            glp1DoseLogs: glp1DoseLogs.count,
            glp1Medications: glp1Medications.count,
            dexaResults: dexaResults.count
        )
    }
}

struct PendingLocalSyncCounts {
    let bodyMetrics: Int
    let dailyMetrics: Int
    let profiles: Int
    let glp1DoseLogs: Int
    let glp1Medications: Int
    let dexaResults: Int

    static let empty = PendingLocalSyncCounts(
        bodyMetrics: 0,
        dailyMetrics: 0,
        profiles: 0,
        glp1DoseLogs: 0,
        glp1Medications: 0,
        dexaResults: 0
    )

    var total: Int {
        bodyMetrics + dailyMetrics + profiles + glp1DoseLogs + glp1Medications + dexaResults
    }
}

struct PendingBodyMetricSyncItem {
    let id: String
    let userId: String
    let date: Date
    let localDate: String?
    let weight: Double
    let weightUnit: String?
    let waistCircumference: Double
    let hipCircumference: Double
    let waistUnit: String?
    let bodyFatPercentage: Double
    let bodyFatMethod: String?
    let muscleMass: Double
    let boneMass: Double
    let photoUrl: String?
    let originalPhotoUrl: String?
    let notes: String?
    let dataSource: String?
    let sourceMetadataJSON: String?
    let syncStatus: String?
    let createdAt: Date
    let updatedAt: Date
    let isMarkedDeleted: Bool
}

struct PendingDailyMetricSyncItem {
    let id: String
    let userId: String
    let date: Date
    let steps: Int32
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct PendingProfileSyncItem {
    let id: String
    let fullName: String?
    let username: String?
    let height: Double?
    let heightUnit: String?
    let gender: String?
    let dateOfBirth: Date?
    let activityLevel: String?
}

struct PendingGlp1DoseLogSyncItem {
    let id: String
    let userId: String
    let takenAt: Date
    let medicationId: String?
    let doseAmount: Double
    let doseUnit: String?
    let drugClass: String?
    let brand: String?
    let isCompounded: Bool
    let supplierType: String?
    let supplierName: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
    let isMarkedDeleted: Bool
}

struct PendingGlp1MedicationSyncItem {
    let id: String
    let userId: String
    let displayName: String?
    let genericName: String?
    let drugClass: String?
    let brand: String?
    let route: String?
    let frequency: String?
    let doseUnit: String?
    let isCompounded: Bool
    let hkIdentifier: String?
    let startedAt: Date
    let endedAt: Date?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date
}

struct PendingDexaResultSyncItem {
    let id: String
    let userId: String
    let bodyMetricsId: String?
    let externalSource: String?
    let externalResultId: String?
    let externalUpdateTime: Date?
    let scannerModel: String?
    let locationId: String?
    let locationName: String?
    let acquireTime: Date?
    let analyzeTime: Date?
    let vatMassKg: Double
    let vatVolumeCm3: Double
    let resultPdfUrl: String?
    let resultPdfName: String?
    let createdAt: Date
    let updatedAt: Date
}

class CoreDataManager: ObservableObject {
    static let shared = CoreDataManager()
    static let photoUploadInFlightSyncStatus = "photo_upload_in_flight"
    static let photoUploadStorageCommittedSyncStatus = "photo_upload_storage_committed"

    let saveQueue = DispatchQueue(label: "com.logyourbody.coredata.save", qos: .utility)
    var isSaving = false

    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "LogYourBody")

        for description in container.persistentStoreDescriptions {
            description.setOption(
                FileProtectionType.completeUntilFirstUserAuthentication as NSObject,
                forKey: NSPersistentStoreFileProtectionKey
            )
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                let appError = AppError.coreData(operation: "loadPersistentStores", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "loadPersistentStores",
                    screen: nil,
                    userId: nil
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                // Log the error but don't crash - fallback to in-memory store
                // print("⚠️ CoreData Error: Unable to load persistent stores: \(error)")
                // print("⚠️ Falling back to in-memory store. Data will not persist.")

                // Create an in-memory store as fallback
                let inMemoryDescription = NSPersistentStoreDescription()
                inMemoryDescription.type = NSInMemoryStoreType
                container.persistentStoreDescriptions = [inMemoryDescription]

                // Attempt to load in-memory store
                container.loadPersistentStores { _, inMemoryError in
                    if let inMemoryError = inMemoryError {
                        let criticalError = AppError.coreData(operation: "loadInMemoryStore", underlying: inMemoryError)
                        let criticalContext = ErrorContext(
                            feature: "coreData",
                            operation: "loadInMemoryStore",
                            screen: nil,
                            userId: nil
                        )
                        ErrorReporter.shared.capture(criticalError, context: criticalContext)
                        // print("❌ CoreData Critical: Even in-memory store failed: \(inMemoryError)")
                    }
                }
            }

            // Enable automatic lightweight migration
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()


    init() {}


    // Async save for critical operations

    // Legacy sync save - triggers async save in background


    // Mark all HealthKit imported entries as synced

    // Optimize database (vacuum SQLite)

    // Save context helper

    // Clean up body metrics with invalid UUIDs
}

extension CachedGlp1Medication {
    func pendingSyncItem() -> PendingGlp1MedicationSyncItem {
        PendingGlp1MedicationSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            displayName: displayName,
            genericName: genericName,
            drugClass: drugClass,
            brand: brand,
            route: route,
            frequency: frequency,
            doseUnit: doseUnit,
            isCompounded: isCompounded,
            hkIdentifier: hkIdentifier,
            startedAt: startedAt ?? Date(),
            endedAt: endedAt,
            notes: notes,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    func toGlp1Medication() -> Glp1Medication? {
        guard let id = id,
              let userId = userId,
              let displayName = displayName,
              let startedAt = startedAt,
              let createdAt = createdAt,
              let updatedAt = updatedAt else {
            return nil
        }

        return Glp1Medication(
            id: id,
            userId: userId,
            displayName: displayName,
            genericName: genericName,
            drugClass: drugClass,
            brand: brand,
            route: route,
            frequency: frequency,
            doseUnit: doseUnit,
            isCompounded: isCompounded,
            hkIdentifier: hkIdentifier,
            startedAt: startedAt,
            endedAt: endedAt,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension CachedDexaResult {
    func pendingSyncItem() -> PendingDexaResultSyncItem {
        PendingDexaResultSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            bodyMetricsId: bodyMetricsId,
            externalSource: externalSource,
            externalResultId: externalResultId,
            externalUpdateTime: externalUpdateTime,
            scannerModel: scannerModel,
            locationId: locationId,
            locationName: locationName,
            acquireTime: acquireTime,
            analyzeTime: analyzeTime,
            vatMassKg: vatMassKg,
            vatVolumeCm3: vatVolumeCm3,
            resultPdfUrl: resultPdfUrl,
            resultPdfName: resultPdfName,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    func toDexaResult() -> DexaResult? {
        guard let id = id,
              let userId = userId,
              let externalSource = externalSource,
              let externalResultId = externalResultId,
              let createdAt = createdAt,
              let updatedAt = updatedAt else {
            return nil
        }

        let resolvedVatMass: Double?
        if vatMassKg > 0 {
            resolvedVatMass = vatMassKg
        } else {
            resolvedVatMass = nil
        }

        let resolvedVatVolume: Double?
        if vatVolumeCm3 > 0 {
            resolvedVatVolume = vatVolumeCm3
        } else {
            resolvedVatVolume = nil
        }

        return DexaResult(
            id: id,
            userId: userId,
            bodyMetricsId: bodyMetricsId,
            externalSource: externalSource,
            externalResultId: externalResultId,
            externalUpdateTime: externalUpdateTime,
            scannerModel: scannerModel,
            locationId: locationId,
            locationName: locationName,
            acquireTime: acquireTime,
            analyzeTime: analyzeTime,
            vatMassKg: resolvedVatMass,
            vatVolumeCm3: resolvedVatVolume,
            resultPdfUrl: resultPdfUrl,
            resultPdfName: resultPdfName,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Model Extensions for Conversion

extension CachedBodyMetrics {
    func pendingSyncItem() -> PendingBodyMetricSyncItem {
        let date = date ?? Date()
        return PendingBodyMetricSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            date: date,
            localDate: localDate,
            weight: weight,
            weightUnit: weightUnit,
            waistCircumference: waistCircumference,
            hipCircumference: hipCircumference,
            waistUnit: waistUnit,
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: bodyFatMethod,
            muscleMass: muscleMass,
            boneMass: boneMass,
            photoUrl: photoUrl,
            originalPhotoUrl: originalPhotoUrl,
            notes: notes,
            dataSource: dataSource,
            sourceMetadataJSON: sourceMetadataJSON,
            syncStatus: syncStatus,
            createdAt: createdAt ?? date,
            updatedAt: updatedAt ?? createdAt ?? date,
            isMarkedDeleted: isMarkedDeleted
        )
    }

    func toBodyMetrics() -> BodyMetrics? {
        // Skip entries with missing required fields
        guard let id = id,
              let date = date,
              let createdAt = createdAt,
              let updatedAt = updatedAt,
              let userId = userId else {
            // print("⚠️ Skipping corrupted body metric entry with missing required fields")
            return nil
        }

        return BodyMetrics(
            id: id,
            userId: userId,
            date: date,
            localDate: BodyMetricLocalDate.normalized(localDate, fallback: date),
            weight: weight > 0 ? weight : nil,
            weightUnit: weightUnit,
            bodyFatPercentage: bodyFatPercentage > 0 ? bodyFatPercentage : nil,
            bodyFatMethod: bodyFatMethod,
            muscleMass: muscleMass > 0 ? muscleMass : nil,
            boneMass: boneMass > 0 ? boneMass : nil,
            waistCm: waistCircumference > 0 ? waistCircumference : nil,
            hipCm: hipCircumference > 0 ? hipCircumference : nil,
            waistUnit: waistUnit,
            notes: notes,
            photoUrl: photoUrl,
            dataSource: BodyMetricSource.normalizedRawValue(dataSource),
            sourceMetadata: BodyMetricSourceMetadata(jsonString: sourceMetadataJSON),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension CachedDailyMetrics {
    func pendingSyncItem() -> PendingDailyMetricSyncItem {
        let date = date ?? Date()
        return PendingDailyMetricSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            date: date,
            steps: steps,
            notes: notes,
            createdAt: createdAt ?? date,
            updatedAt: updatedAt ?? createdAt ?? date
        )
    }

    func toDailyMetrics() -> DailyMetrics {
        DailyMetrics(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            date: date ?? Date(),
            steps: steps > 0 ? Int(steps) : nil,
            notes: notes,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }
}

extension CachedProfile {
    func pendingSyncItem() -> PendingProfileSyncItem {
        PendingProfileSyncItem(
            id: id ?? "",
            fullName: fullName,
            username: username,
            height: height > 0 ? height : nil,
            heightUnit: heightUnit,
            gender: gender,
            dateOfBirth: dateOfBirth,
            activityLevel: activityLevel
        )
    }

    func toUserProfile() -> UserProfile {
        let storedHeight = height
        let unit = heightUnit?.lowercased()

        let heightCm: Double?
        if storedHeight > 0 {
            if unit == "in" {
                if storedHeight >= 100 {
                    heightCm = storedHeight
                } else {
                    heightCm = storedHeight * 2.54
                }
            } else if unit == "cm" {
                heightCm = storedHeight < 100 ? storedHeight * 2.54 : storedHeight
            } else {
                heightCm = storedHeight >= 100 ? storedHeight : storedHeight * 2.54
            }
        } else {
            heightCm = nil
        }

        return UserProfile(
            id: id ?? "",
            email: email ?? "",
            username: username,
            fullName: fullName,
            dateOfBirth: dateOfBirth,
            height: heightCm,
            heightUnit: heightUnit,
            gender: gender,
            activityLevel: activityLevel,
            goalWeight: goalWeight > 0 ? goalWeight : nil,
            goalWeightUnit: goalWeightUnit,
            onboardingCompleted: nil
        )
    }
}

extension CachedGlp1DoseLog {
    func pendingSyncItem() -> PendingGlp1DoseLogSyncItem {
        PendingGlp1DoseLogSyncItem(
            id: id ?? UUID().uuidString,
            userId: userId ?? "",
            takenAt: takenAt ?? Date(),
            medicationId: medicationId,
            doseAmount: doseAmount,
            doseUnit: doseUnit,
            drugClass: drugClass,
            brand: brand,
            isCompounded: isCompounded,
            supplierType: supplierType,
            supplierName: supplierName,
            notes: notes,
            createdAt: createdAt ?? takenAt ?? Date(),
            updatedAt: updatedAt ?? createdAt ?? takenAt ?? Date(),
            isMarkedDeleted: isMarkedDeleted
        )
    }

    func toGlp1DoseLog() -> Glp1DoseLog? {
        guard let id = id,
              let userId = userId,
              let takenAt = takenAt,
              let createdAt = createdAt,
              let updatedAt = updatedAt else {
            return nil
        }

        let resolvedDoseAmount: Double?
        if doseAmount > 0 {
            resolvedDoseAmount = doseAmount
        } else {
            resolvedDoseAmount = nil
        }

        return Glp1DoseLog(
            id: id,
            userId: userId,
            takenAt: takenAt,
            medicationId: medicationId,
            doseAmount: resolvedDoseAmount,
            doseUnit: doseUnit,
            drugClass: drugClass,
            brand: brand,
            isCompounded: isCompounded,
            supplierType: supplierType,
            supplierName: supplierName,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
