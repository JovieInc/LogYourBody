import CoreData
import Foundation

@MainActor
protocol GymRegistryStoring {
    func load(ownerId: String) throws -> GymRegistrySnapshot
    func save(_ snapshot: GymRegistrySnapshot, ownerId: String) throws
}

/// Uses a private context so a failed registry save cannot commit or roll back other app edits.
@MainActor
final class CoreDataGymRegistryStore: GymRegistryStoring {
    private let context: NSManagedObjectContext

    init(container: NSPersistentContainer = CoreDataManager.shared.persistentContainer) {
        context = container.newBackgroundContext()
    }

    private func request(_ ownerId: String) -> NSFetchRequest<NSManagedObject> {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedGymRegistry")
        request.predicate = NSPredicate(format: "ownerId == %@", ownerId)
        request.fetchLimit = 1
        return request
    }

    func load(ownerId: String) throws -> GymRegistrySnapshot {
        try context.performAndWait {
            context.reset()
            guard let row = try context.fetch(request(ownerId)).first else { return GymRegistrySnapshot() }
            guard let data = row.value(forKey: "payload") as? Data else { throw GymRegistryError.unavailable }
            let snapshot = try JSONDecoder().decode(GymRegistrySnapshot.self, from: data)
            guard Set(snapshot.gyms.map(\.id)).count == snapshot.gyms.count,
                  snapshot.gyms.allSatisfy({ (try? $0.validated()) == $0 }),
                  snapshot.activeGymId == nil || snapshot.activeGym != nil,
                  snapshot.pending.isSubset(of: Set(snapshot.gyms.map(\.id))),
                  snapshot.removed.isDisjoint(with: Set(snapshot.gyms.map(\.id)))
            else { throw GymRegistryError.unavailable }
            return snapshot
        }
    }

    func save(_ snapshot: GymRegistrySnapshot, ownerId: String) throws {
        let data = try JSONEncoder().encode(snapshot)
        try context.performAndWait {
            do {
                let row = try context.fetch(request(ownerId)).first ??
                    NSEntityDescription.insertNewObject(forEntityName: "CachedGymRegistry", into: context)
                row.setValue(ownerId, forKey: "ownerId")
                row.setValue(data, forKey: "payload")
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}
