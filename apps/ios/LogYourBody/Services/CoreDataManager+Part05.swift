import Foundation
import CoreData
import HealthKit

extension CoreDataManager {
func markGlp1DoseLogDeleted(id: String, userId: String) async -> Bool {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedGlp1DoseLog> = CachedGlp1DoseLog.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "id == %@", id),
                NSPredicate(format: "userId == %@", userId)
            ])
            request.fetchLimit = 1

            guard let cached = try? context.fetch(request).first else {
                return false
            }

            let now = Date()
            cached.isMarkedDeleted = true
            cached.updatedAt = now
            cached.isSynced = false
            cached.syncStatus = "pending"

            do {
                if context.hasChanges {
                    try context.save()
                }
                return true
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "markGlp1DoseLogDeleted", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "markGlp1DoseLogDeleted",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return false
            }
        }
    }

func fetchGlp1Medications(for userId: String) async -> [Glp1Medication] {
        let context = viewContext

        return await context.perform {
            let request: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@", userId)
            request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: true)]

            do {
                let cached = try context.fetch(request)
                return cached.compactMap { $0.toGlp1Medication() }
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "fetchGlp1Medications", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "fetchGlp1Medications",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
                return []
            }
        }
    }

func saveGlp1Medications(
        _ medications: [Glp1Medication],
        userId: String,
        markAsSynced: Bool = true
    ) {
        guard !medications.isEmpty else { return }

        let context = viewContext

        context.perform {
            for medication in medications {
                let request: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", medication.id)
                request.fetchLimit = 1

                let cached: CachedGlp1Medication

                if let existing = try? context.fetch(request).first {
                    cached = existing
                } else {
                    cached = CachedGlp1Medication(context: context)
                    cached.id = medication.id
                    cached.createdAt = medication.createdAt
                }

                cached.userId = userId
                cached.displayName = medication.displayName
                cached.genericName = medication.genericName
                cached.drugClass = medication.drugClass
                cached.brand = medication.brand
                cached.route = medication.route
                cached.frequency = medication.frequency
                cached.doseUnit = medication.doseUnit
                cached.isCompounded = medication.isCompounded
                cached.hkIdentifier = medication.hkIdentifier
                cached.startedAt = medication.startedAt
                cached.endedAt = medication.endedAt
                cached.notes = medication.notes
                cached.updatedAt = medication.updatedAt
                cached.isSynced = markAsSynced
                cached.syncStatus = markAsSynced ? "synced" : "pending"
            }

            do {
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "saveGlp1Medications", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "saveGlp1Medications",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
            }
        }
    }

func endActiveGlp1Medications(for userId: String, endedAt: Date) {
        let context = viewContext

        context.perform {
            let request: NSFetchRequest<CachedGlp1Medication> = CachedGlp1Medication.fetchRequest()
            request.predicate = NSPredicate(format: "userId == %@ AND endedAt == nil", userId)

            do {
                let medications = try context.fetch(request)
                for medication in medications {
                    medication.endedAt = endedAt
                    medication.updatedAt = endedAt
                    medication.isSynced = false
                    medication.syncStatus = "pending"
                }

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                #if DEBUG
                let appError = AppError.coreData(operation: "endActiveGlp1Medications", underlying: error)
                let contextInfo = ErrorContext(
                    feature: "coreData",
                    operation: "endActiveGlp1Medications",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.capture(appError, context: contextInfo)
                #endif
            }
        }
    }
}
