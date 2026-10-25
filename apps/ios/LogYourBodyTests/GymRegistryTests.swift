import CoreData
import XCTest
@testable import LogYourBody

@MainActor
final class GymRegistryTests: XCTestCase {
    private func gym(_ name: String = "Downtown", equipment: Set<GymEquipment> = [.dumbbells]) -> Gym {
        Gym(name: name, region: "City", equipment: equipment, preferredMachines: ["Chest press"])
    }

    private func service(_ store: GymRegistryStoring, owner: String = "owner-a") -> GymRegistryService {
        GymRegistryService(ownerId: owner, store: store, isCurrent: { true })
    }

    func testNoSelectionAllowsAllAndRegistrationNeverSelectsOrInfersInventory() throws {
        let registry = service(GymMemoryStore())
        XCTAssertNil(registry.snapshot.activeGymId)
        XCTAssertNil(registry.snapshot.equipmentFilter)
        let empty = gym(equipment: [])
        try registry.save(empty)
        XCTAssertNil(registry.snapshot.equipmentFilter)
        try registry.select(empty.id)
        XCTAssertEqual(registry.snapshot.equipmentFilter, [])
        XCTAssertEqual(registry.snapshot.activeGym?.preferredMachines, ["Chest press"])
    }

    func testMultipleGymsEditManualSwitchClearAndDeletionPersist() throws {
        let store = GymMemoryStore()
        let registry = service(store)
        let first = gym()
        var second = gym("Home", equipment: [.barbell, .bench])
        try registry.save(first)
        try registry.save(second)
        try registry.select(second.id)
        XCTAssertEqual(service(store).snapshot.activeGymId, second.id)
        XCTAssertEqual(service(store).snapshot.equipmentFilter, [.barbell, .bench])
        second.name = "Home gym"
        second.equipment = [.bodyweight]
        try registry.save(second)
        XCTAssertEqual(registry.snapshot.gyms.count, 2)
        XCTAssertEqual(registry.snapshot.equipmentFilter, [.bodyweight])
        try registry.select(first.id)
        XCTAssertEqual(service(store).snapshot.activeGymId, first.id)
        try registry.remove(first.id)
        XCTAssertNil(service(store).snapshot.activeGymId)
        XCTAssertNil(registry.snapshot.equipmentFilter)
        try registry.select(second.id)
        try registry.select(nil)
        XCTAssertNil(service(store).snapshot.activeGymId)
        XCTAssertThrowsError(try registry.select(UUID()))
    }

    func testInvalidGymAndFailedWritePreservePriorStateAndOtherOwner() throws {
        let store = GymMemoryStore()
        let registry = service(store)
        try registry.save(gym())
        let before = registry.snapshot
        XCTAssertThrowsError(try registry.save(gym(" \n ")))
        store.failWrites = true
        XCTAssertThrowsError(try registry.select(before.gyms.first?.id))
        XCTAssertEqual(registry.snapshot, before)
        XCTAssertTrue(service(store, owner: "owner-b").snapshot.gyms.isEmpty)
        store.failReads = true
        let unreadable = service(store)
        XCTAssertNotNil(unreadable.errorMessage)
        XCTAssertThrowsError(try unreadable.save(gym("New")))
        XCTAssertEqual(store.values["owner-a"], before)
    }

    func testOfflineJournalRetriesUpsertsAndDeletesWithoutChangingSelection() async throws {
        let store = GymMemoryStore()
        let registry = service(store)
        let first = gym()
        let second = gym("Home", equipment: [])
        try registry.save(first)
        try registry.save(second)
        try registry.select(second.id)
        let api = GymSyncFixture()
        api.offline = true
        await registry.synchronize(api: api, getToken: { "token" })
        XCTAssertNotNil(registry.errorMessage)
        XCTAssertEqual(registry.snapshot.pending.count, 2)
        let relaunched = service(store)
        api.offline = false
        await relaunched.synchronize(api: api, getToken: { "token" })
        XCTAssertTrue(relaunched.snapshot.pending.isEmpty)
        XCTAssertEqual(relaunched.snapshot.activeGymId, second.id)
        try relaunched.remove(second.id)
        api.offline = true
        await relaunched.synchronize(api: api, getToken: { "token" })
        XCTAssertTrue(service(store).snapshot.removed.contains(second.id))
        api.offline = false
        await relaunched.synchronize(api: api, getToken: { "token" })
        XCTAssertEqual(api.gyms, [first])
        XCTAssertNil(relaunched.snapshot.activeGymId)
        XCTAssertTrue(relaunched.snapshot.removed.isEmpty)
    }

    func testRemoteGymsNeverAutoSelectAndRemoteDeletionClearsOldSelection() async throws {
        let registry = service(GymMemoryStore())
        let api = GymSyncFixture()
        api.gyms = [gym(), gym("Home")]
        await registry.synchronize(api: api, getToken: { "token" })
        XCTAssertEqual(registry.snapshot.gyms.count, 2)
        XCTAssertNil(registry.snapshot.equipmentFilter)
        try registry.select(api.gyms[0].id)
        api.gyms.removeFirst()
        await registry.synchronize(api: api, getToken: { "token" })
        XCTAssertNil(registry.snapshot.activeGymId)
        XCTAssertNil(registry.snapshot.equipmentFilter)
    }

    func testAccountSwitchDuringTokenLookupNeverSendsAndLateAcknowledgementKeepsJournal() async throws {
        let store = GymMemoryStore()
        var generation = 1
        let registry = GymRegistryService(ownerId: "owner-a", store: store, isCurrent: { generation == 1 })
        try registry.save(gym())
        let before = registry.snapshot
        let api = GymSyncFixture()
        await registry.synchronize(api: api, getToken: { generation = 2; return "other-owner-token" })
        XCTAssertEqual(api.saves, 0)
        XCTAssertEqual(registry.snapshot, before)
        generation = 1
        api.afterSave = { generation = 3 }
        await registry.synchronize(api: api, getToken: { "token" })
        XCTAssertEqual(api.saves, 1)
        XCTAssertEqual(service(store).snapshot, before)
        XCTAssertThrowsError(try registry.select(nil))
    }

    func testLateSyncCannotDiscardEditMadeWhileRequestWasRunning() async throws {
        let registry = service(GymMemoryStore())
        var value = gym()
        try registry.save(value)
        let api = GymSyncFixture()
        api.afterSave = {
            value.equipment = [.barbell]
            try registry.save(value)
        }
        await registry.synchronize(api: api, getToken: { "token" })
        XCTAssertEqual(registry.snapshot.gyms.first?.equipment, [.barbell])
        XCTAssertTrue(registry.snapshot.pending.contains(value.id))
    }

    func testCoreDataSelectionSurvivesSQLiteStoreReopenAndIsOwnerScoped() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gym-\(UUID()).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        func container() throws -> NSPersistentContainer {
            let model = CoreDataManager.makeManagedObjectModel()
            let container = NSPersistentContainer(name: "LogYourBody", managedObjectModel: model)
            try container.persistentStoreCoordinator.addPersistentStore(type: .sqlite, at: url)
            return container
        }
        let value = gym()
        var initial: NSPersistentContainer? = try container()
        do {
            let registry = service(CoreDataGymRegistryStore(container: try XCTUnwrap(initial)))
            try registry.save(value)
            try registry.select(value.id)
        }
        for store in try XCTUnwrap(initial).persistentStoreCoordinator.persistentStores {
            try initial?.persistentStoreCoordinator.remove(store)
        }
        initial = nil
        let reopened = try container()
        let store = CoreDataGymRegistryStore(container: reopened)
        XCTAssertEqual(service(store).snapshot.activeGym, value)
        XCTAssertNil(service(store, owner: "owner-b").snapshot.activeGymId)
    }
}

@MainActor
private final class GymMemoryStore: GymRegistryStoring {
    var values: [String: GymRegistrySnapshot] = [:]
    var failWrites = false
    var failReads = false
    func load(ownerId: String) throws -> GymRegistrySnapshot {
        if failReads { throw GymRegistryError.unavailable }
        return values[ownerId] ?? GymRegistrySnapshot()
    }
    func save(_ snapshot: GymRegistrySnapshot, ownerId: String) throws {
        if failWrites { throw GymRegistryError.unavailable }
        values[ownerId] = snapshot
    }
}

@MainActor
private final class GymSyncFixture: GymRegistrySyncing {
    var gyms: [Gym] = []
    var saves = 0
    var offline = false
    var afterSave: (() throws -> Void)?
    func list(token: String) async throws -> [Gym] { gyms }
    func save(_ gym: Gym, token: String) async throws {
        saves += 1
        if offline { throw URLError(.notConnectedToInternet) }
        gyms.removeAll { $0.id == gym.id }
        gyms.append(gym)
        try afterSave?()
    }
    func remove(_ id: UUID, token: String) async throws {
        if offline { throw URLError(.notConnectedToInternet) }
        gyms.removeAll { $0.id == id }
    }
}
