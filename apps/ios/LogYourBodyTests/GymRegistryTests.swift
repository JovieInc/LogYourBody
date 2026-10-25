import CoreData
import XCTest
@testable import LogYourBody

@MainActor
final class GymRegistryTests: XCTestCase {
    private func registry(
        owner: String = "owner-a", store: GymMemoryStore? = nil, remote: GymTestRemote? = nil
    ) throws -> GymRegistry {
        try GymRegistry(ownerID: owner, persistence: store ?? GymMemoryStore(), remote: remote ?? GymTestRemote())
    }

    func testDefaultAndRegistrationNeverAssumeGymOrInventory() throws {
        let model = try registry()
        XCTAssertTrue(model.gyms.isEmpty)
        XCTAssertNil(model.activeGym)
        XCTAssertNil(model.equipmentFilter)
        let gym = try model.create(name: "Home", coarseRegion: nil, equipment: [], preferredMachines: [])
        XCTAssertNil(model.activeGym)
        try model.select(gym.id)
        XCTAssertEqual(model.equipmentFilter, [])
        try model.select(nil)
        XCTAssertNil(model.equipmentFilter)
    }

    func testMultipleGymsEditingManualSwitchAndRelaunch() throws {
        let store = GymMemoryStore()
        let model = try registry(store: store)
        let first = try model.create(name: " Home ", coarseRegion: "  ", equipment: [.dumbbells], preferredMachines: [])
        var second = try model.create(name: "Club", coarseRegion: "City", equipment: [.machine], preferredMachines: ["Leg press"])
        XCTAssertEqual(first.name, "Home")
        XCTAssertNil(first.coarseRegion)
        try model.select(first.id)
        try model.select(second.id)
        second.equipment = [.cable, .bench]
        try model.update(second)
        let reopened = try registry(store: store)
        XCTAssertEqual(reopened.gyms.count, 2)
        XCTAssertEqual(reopened.activeGym, second)
        XCTAssertEqual(reopened.equipmentFilter, [.cable, .bench])
        try reopened.select(nil)
        XCTAssertNil(try registry(store: store).activeGym)
        XCTAssertThrowsError(try reopened.select(UUID()))
    }

    func testDeletingActiveGymDoesNotSelectAnother() throws {
        let model = try registry()
        let first = try model.create(name: "Home", coarseRegion: nil, equipment: [.dumbbells], preferredMachines: [])
        let second = try model.create(name: "Club", coarseRegion: nil, equipment: [.machine], preferredMachines: [])
        try model.select(first.id)
        try model.delete(first.id)
        XCTAssertEqual(model.gyms.map(\.id), [second.id])
        XCTAssertNil(model.activeGym)
        XCTAssertNil(model.equipmentFilter)
    }

    func testAccountsHaveSeparateLocalRegistriesAndSelections() throws {
        let store = GymMemoryStore()
        let first = try registry(store: store)
        let gym = try first.create(name: "Private", coarseRegion: nil, equipment: [.smith], preferredMachines: [])
        try first.select(gym.id)
        let other = try registry(owner: "owner-b", store: store)
        XCTAssertTrue(other.gyms.isEmpty)
        XCTAssertNil(other.activeGym)
        XCTAssertEqual(try registry(store: store).activeGym?.id, gym.id)
    }

    func testInvalidInputAndFailedSaveDoNotPublishChanges() throws {
        let store = GymMemoryStore()
        let model = try registry(store: store)
        XCTAssertThrowsError(try model.create(name: " ", coarseRegion: nil, equipment: [], preferredMachines: []))
        XCTAssertThrowsError(try model.create(name: "Home", coarseRegion: nil, equipment: [], preferredMachines: [" "]))
        store.failSave = true
        XCTAssertThrowsError(try model.create(name: "Home", coarseRegion: nil, equipment: [.bench], preferredMachines: []))
        XCTAssertTrue(model.gyms.isEmpty)
        XCTAssertFalse(model.hasPendingChanges)
    }

    func testOfflineChangesSurviveRelaunchAndRetryThenPullOnAnotherDevice() async throws {
        let store = GymMemoryStore()
        let remote = GymTestRemote()
        let first = try registry(store: store, remote: remote)
        let gym = try first.create(name: "Home", coarseRegion: nil, equipment: [.dumbbells], preferredMachines: [])
        try first.select(gym.id)
        remote.fail = true
        do {
            try await first.sync(accessToken: "fixture", isCurrent: { true })
            XCTFail("Offline transport should fail")
        } catch {}
        let reopened = try registry(store: store, remote: remote)
        XCTAssertTrue(reopened.hasPendingChanges)
        XCTAssertEqual(reopened.activeGym, gym)
        remote.fail = false
        try await reopened.sync(accessToken: "fixture", isCurrent: { true })
        XCTAssertFalse(reopened.hasPendingChanges)
        let secondDevice = try registry(remote: remote)
        try await secondDevice.sync(accessToken: "fixture", isCurrent: { true })
        XCTAssertEqual(secondDevice.gyms, [gym])
        XCTAssertNil(secondDevice.activeGym)
    }

    func testSyncAcknowledgementPreservesEditsAndSwitchesMadeDuringRequest() async throws {
        let remote = GymTestRemote()
        let model = try registry(remote: remote)
        let gym = try model.create(name: "Home", coarseRegion: nil, equipment: [.dumbbells], preferredMachines: [])
        remote.duringSync = {
            var edited = gym
            edited.name = "Edited offline"
            edited.equipment = [.bench]
            try model.update(edited)
            try model.select(gym.id)
        }
        try await model.sync(accessToken: "fixture", isCurrent: { true })
        XCTAssertEqual(model.activeGym?.name, "Edited offline")
        XCTAssertTrue(model.hasPendingChanges)
        remote.duringSync = nil
        try await model.sync(accessToken: "fixture", isCurrent: { true })
        XCTAssertFalse(model.hasPendingChanges)
        XCTAssertEqual(remote.records[gym.id]?.gym.name, "Edited offline")
    }

    func testRemoteDeletionClearsSelectionAndTombstoneCannotRevive() async throws {
        let remote = GymTestRemote()
        let model = try registry(remote: remote)
        let gym = try model.create(name: "Home", coarseRegion: nil, equipment: [], preferredMachines: [])
        try model.select(gym.id)
        try await model.sync(accessToken: "fixture", isCurrent: { true })
        remote.records[gym.id]?.deleted = true
        try model.update(gym)
        try await model.sync(accessToken: "fixture", isCurrent: { true })
        XCTAssertTrue(model.gyms.isEmpty)
        XCTAssertNil(model.activeGym)
        XCTAssertFalse(model.hasPendingChanges)
    }

    func testIncompleteAcknowledgementAndFailedAcknowledgementSaveRetainPendingChanges() async throws {
        let store = GymMemoryStore()
        let remote = GymTestRemote()
        let model = try registry(store: store, remote: remote)
        _ = try model.create(name: "Home", coarseRegion: nil, equipment: [], preferredMachines: [])
        remote.omitResponse = true
        do {
            try await model.sync(accessToken: "fixture", isCurrent: { true })
            XCTFail("Missing row is not an acknowledgement")
        } catch {}
        XCTAssertTrue(model.hasPendingChanges)
        remote.omitResponse = false
        store.failSave = true
        do {
            try await model.sync(accessToken: "fixture", isCurrent: { true })
            XCTFail("A failed local acknowledgement must retain the pending mutation")
        } catch {}
        XCTAssertTrue(model.hasPendingChanges)
        store.failSave = false
        try await model.sync(accessToken: "fixture", isCurrent: { true })
        XCTAssertFalse(model.hasPendingChanges)
    }

    func testSyncChunksMoreThanOneHundredPendingGymsWithoutLosingAny() async throws {
        let remote = GymTestRemote()
        let model = try registry(remote: remote)
        for index in 0..<101 {
            _ = try model.create(name: "Gym \(index)", coarseRegion: nil, equipment: [], preferredMachines: [])
        }
        try await model.sync(accessToken: "fixture", isCurrent: { true })
        XCTAssertEqual(remote.batchSizes, [100, 1])
        XCTAssertEqual(remote.records.count, 101)
        XCTAssertFalse(model.hasPendingChanges)
        XCTAssertNil(model.activeGym)
    }

    func testAccountChangeDiscardsLateSyncAndLibraryResponses() async throws {
        let remote = GymTestRemote()
        let model = try registry(remote: remote)
        _ = try model.create(name: "Private", coarseRegion: nil, equipment: [], preferredMachines: [])
        var current = true
        remote.duringSync = { current = false }
        do {
            try await model.sync(accessToken: "fixture", isCurrent: { current })
            XCTFail("Late acknowledgement must be rejected")
        } catch {}
        XCTAssertTrue(model.hasPendingChanges)
        current = true
        remote.duringLibrary = { current = false }
        do {
            _ = try await model.exercises(accessToken: "fixture", isCurrent: { current })
            XCTFail("Late library response must be rejected")
        } catch {}
    }

    func testLibraryReceivesExactActiveEquipmentOrUnrestrictedNil() async throws {
        let remote = GymTestRemote()
        let model = try registry(remote: remote)
        _ = try await model.exercises(accessToken: "fixture", isCurrent: { true })
        XCTAssertNil(remote.equipment)
        let gym = try model.create(name: "Empty", coarseRegion: nil, equipment: [], preferredMachines: ["Favorite"])
        try model.select(gym.id)
        _ = try await model.exercises(accessToken: "fixture", isCurrent: { true })
        XCTAssertEqual(remote.equipment, [])
    }

    func testCoreDataSQLiteReopenRetainsInventoryPendingChangesAndManualChoice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("gyms.sqlite")
        let first = try container(url: url)
        let model = try GymRegistry(
            ownerID: "owner-a", persistence: CoreDataGymRegistryStore(context: first.newBackgroundContext()),
            remote: GymTestRemote()
        )
        let gym = try model.create(name: "Club", coarseRegion: "City", equipment: [.cable], preferredMachines: ["Cable row"])
        try model.select(gym.id)
        for store in first.persistentStoreCoordinator.persistentStores {
            try first.persistentStoreCoordinator.remove(store)
        }
        let second = try container(url: url)
        defer {
            for store in second.persistentStoreCoordinator.persistentStores {
                try? second.persistentStoreCoordinator.remove(store)
            }
        }
        let reopened = try GymRegistry(
            ownerID: "owner-a", persistence: CoreDataGymRegistryStore(context: second.newBackgroundContext()),
            remote: GymTestRemote()
        )
        XCTAssertEqual(reopened.activeGym, gym)
        XCTAssertTrue(reopened.hasPendingChanges)
        let other = try GymRegistry(
            ownerID: "owner-b", persistence: CoreDataGymRegistryStore(context: second.newBackgroundContext()),
            remote: GymTestRemote()
        )
        XCTAssertTrue(other.gyms.isEmpty)
    }

    func testV4StoreMigratesAdditivelyAndStartsWithoutGymSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("migration.sqlite")
        let bundle = Bundle(for: CoreDataManager.self)
        let modelBundle = try XCTUnwrap(bundle.url(forResource: "LogYourBody", withExtension: "momd"))
        let oldModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelBundle.appendingPathComponent("LogYourBodyV4.mom")))
        let old = try container(url: url, model: oldModel)
        let context = old.viewContext
        try context.performAndWait {
            let row = NSEntityDescription.insertNewObject(forEntityName: "SyncMetadata", into: context)
            row.setValue("CachedBodyMetrics", forKey: "syncEntityName")
            row.setValue("retained-record", forKey: "entityId")
            try context.save()
        }
        for store in old.persistentStoreCoordinator.persistentStores { try old.persistentStoreCoordinator.remove(store) }
        let migrated = try container(url: url)
        defer {
            for store in migrated.persistentStoreCoordinator.persistentStores {
                try? migrated.persistentStoreCoordinator.remove(store)
            }
        }
        let store = CoreDataGymRegistryStore(context: migrated.newBackgroundContext())
        let model = try GymRegistry(ownerID: "owner-a", persistence: store, remote: GymTestRemote())
        XCTAssertNil(model.activeGym)
        XCTAssertNil(model.equipmentFilter)
        let records = try migrated.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "SyncMetadata"))
        XCTAssertEqual(records.first?.value(forKey: "entityId") as? String, "retained-record")
    }

    func testFirstPartyTransportUsesNativeGymEncodingAndRejectsInvalidVersionOrAuthentication() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GymURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = GymRegistryAPI(session: session, baseURL: URL(string: ProductRegistry.Hosts.api))
        let gym = Gym(id: UUID(), name: "Home", coarseRegion: nil, equipment: [.dumbbells], preferredMachines: [])
        GymURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/api/auth/mobile/gyms/v1")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture")
            let body = try? JSONSerialization.jsonObject(with: GymURLProtocol.body(request)) as? [String: Any]
            let changes = body?["changes"] as? [[String: Any]]
            let encoded = changes?.first?["gym"] as? [String: Any]
            XCTAssertEqual(encoded?["name"] as? String, "Home")
            XCTAssertNil(encoded?["coarseRegion"])
            XCTAssertEqual(encoded?["equipment"] as? [String], ["dumbbells"])
            return (200, Data(#"{"version":1,"gyms":[]}"#.utf8))
        }
        _ = try await api.sync(changes: [.init(gym: gym, deleted: false)], accessToken: "fixture")
        GymURLProtocol.install { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertNil(request.httpBody)
            return (200, Data(#"{"version":2,"gyms":[]}"#.utf8))
        }
        do {
            _ = try await api.sync(changes: [], accessToken: "fixture")
            XCTFail("Unsupported response version must fail")
        } catch {
            XCTAssertEqual(error as? GymRegistryError, .invalidResponse)
        }
        for (status, expected) in [(401, GymRegistryError.accountChanged), (503, GymRegistryError.unavailable)] {
            GymURLProtocol.install { _ in (status, Data()) }
            do {
                _ = try await api.sync(changes: [], accessToken: "fixture")
                XCTFail("Failed transport must not acknowledge changes")
            } catch {
                XCTAssertEqual(error as? GymRegistryError, expected)
            }
        }
    }

    func testLibraryTransportDistinguishesUnrestrictedEmptyAndConfirmedEquipment() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GymURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = GymRegistryAPI(session: session, baseURL: URL(string: ProductRegistry.Hosts.api))
        let filters: [Set<GymEquipment>?] = [nil, [], [.dumbbells, .bench]]
        for filter in filters {
            GymURLProtocol.install { request in
                XCTAssertEqual(request.url?.path, "/api/auth/mobile/gyms/v1/exercises")
                let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
                if let filter {
                    XCTAssertFalse(items.isEmpty)
                    XCTAssertTrue(items.allSatisfy { $0.name == "equipment" })
                    XCTAssertEqual(
                        Set(items.compactMap(\.value).filter { !$0.isEmpty }), Set(filter.map(\.rawValue))
                    )
                } else {
                    XCTAssertTrue(items.isEmpty)
                }
                return (200, Data(#"{"version":1,"exercises":[]}"#.utf8))
            }
            _ = try await api.exercises(equipment: filter, accessToken: "fixture")
        }
    }

    private func container(url: URL, model: NSManagedObjectModel? = nil) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(
            name: "LogYourBody", managedObjectModel: model ?? CoreDataManager.makeManagedObjectModel()
        )
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        let loaded = expectation(description: "Gym store loaded")
        var failure: Error?
        container.loadPersistentStores { _, error in
            failure = error
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 10)
        if let failure { throw failure }
        return container
    }
}

@MainActor
private final class GymMemoryStore: GymRegistryPersisting {
    var data: [String: Data] = [:]
    var failSave = false
    func load(ownerID: String) throws -> GymRegistryState {
        guard let stored = data[ownerID] else { return GymRegistryState() }
        return try JSONDecoder().decode(GymRegistryState.self, from: stored)
    }
    func save(_ state: GymRegistryState, ownerID: String) throws {
        if failSave { throw GymRegistryError.unavailable }
        data[ownerID] = try JSONEncoder().encode(state)
    }
}

@MainActor
private final class GymTestRemote: GymRegistryRemote {
    var records: [UUID: GymRecord] = [:]
    var fail = false
    var omitResponse = false
    var batchSizes: [Int] = []
    var duringSync: (() throws -> Void)?
    var duringLibrary: (() -> Void)?
    var equipment: Set<GymEquipment>?
    func sync(changes: [GymRecord], accessToken: String) async throws -> [GymRecord] {
        batchSizes.append(changes.count)
        if fail { throw GymRegistryError.unavailable }
        for record in changes where records[record.gym.id]?.deleted != true { records[record.gym.id] = record }
        let result = Array(records.values)
        try duringSync?()
        return omitResponse ? [] : result
    }
    func exercises(equipment: Set<GymEquipment>?, accessToken: String) async throws -> [GymLibraryExercise] {
        self.equipment = equipment
        duringLibrary?()
        return []
    }
}

private final class GymURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handler: ((URLRequest) -> (Int, Data))?

    static func install(_ value: @escaping (URLRequest) -> (Int, Data)) {
        lock.lock()
        handler = value
        lock.unlock()
    }

    static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        let capacity = 1_024
        var buffer = [UInt8](repeating: 0, count: capacity)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: capacity)
            if count <= 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let respond = Self.handler
        Self.lock.unlock()
        guard let respond, let url = request.url else { return }
        let (status, data) = respond(request)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
