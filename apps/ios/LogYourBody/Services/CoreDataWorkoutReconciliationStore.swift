import CoreData
import Foundation

@MainActor
final class CoreDataWorkoutReconciliationStore: WorkoutReconciliationStoring {
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer) {
        context = container.newBackgroundContext()
    }

    func load(ownerId: String, day: String) throws -> WorkoutReconciliationDay? {
        try context.performAndWait {
            guard let row = try context.fetch(request(ownerId: ownerId, day: day)).first else { return nil }
            guard let data = row.value(forKey: "payload") as? Data else {
                throw WorkoutReconciliationError.invalidStoredRecord
            }
            let record = try JSONDecoder().decode(WorkoutReconciliationDay.self, from: data)
            guard record.session?.setLevelVolume == nil,
                  (record.response == .confirmed) == (record.session != nil) else {
                throw WorkoutReconciliationError.invalidStoredRecord
            }
            if let session = record.session {
                try WorkoutReconciliationPolicy.validate(start: session.userConfirmedStart, end: session.userConfirmedEnd)
            }
            return record
        }
    }

    func save(_ record: WorkoutReconciliationDay, ownerId: String, day: String) throws {
        try context.performAndWait {
            do {
                let row = try context.fetch(request(ownerId: ownerId, day: day)).first ??
                    NSEntityDescription.insertNewObject(forEntityName: "CachedWorkoutReconciliationDay", into: context)
                row.setValue(ownerId, forKey: "ownerId")
                row.setValue(day, forKey: "day")
                row.setValue(try JSONEncoder().encode(record), forKey: "payload")
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func request(ownerId: String, day: String) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedWorkoutReconciliationDay")
        request.predicate = NSPredicate(format: "ownerId == %@ AND day == %@", ownerId, day)
        request.fetchLimit = 1
        request.shouldRefreshRefetchedObjects = true
        return request
    }
}
