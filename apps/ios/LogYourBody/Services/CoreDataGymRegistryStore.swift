import CoreData
import Foundation

/// One account-scoped journal in the canonical device store, including pending
/// mutations and the manually chosen active gym. No UserDefaults inventory.
@MainActor
final class CoreDataGymRegistryStore: GymRegistryPersisting {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load(ownerID: String) throws -> GymRegistryState {
        try context.performAndWait {
            guard let row = try row(ownerID: ownerID) else { return GymRegistryState() }
            guard let data = row.value(forKey: "payload") as? Data else { throw GymRegistryError.invalidResponse }
            return try JSONDecoder().decode(GymRegistryState.self, from: data)
        }
    }

    func save(_ state: GymRegistryState, ownerID: String) throws {
        let data = try JSONEncoder().encode(state)
        try context.performAndWait {
            let object = try row(ownerID: ownerID) ?? NSEntityDescription.insertNewObject(
                forEntityName: "GymRegistryJournal", into: context
            )
            object.setValue(ownerID, forKey: "ownerID")
            object.setValue(data, forKey: "payload")
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    private func row(ownerID: String) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: "GymRegistryJournal")
        request.predicate = NSPredicate(format: "ownerID == %@", ownerID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
