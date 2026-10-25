import XCTest
@testable import LogYourBody

final class GymRegistryTests: XCTestCase {
    private var directory: URL!
    private var extraDirectories: [URL] = []
    private var clock: TestClock!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LYB-GymRegistry-" + UUID().uuidString, isDirectory: true)
        clock = TestClock(date: Date(timeIntervalSince1970: 1_700_000_000))
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        extraDirectories.forEach { try? FileManager.default.removeItem(at: $0) }
        directory = nil
        extraDirectories = []
        clock = nil
        super.tearDown()
    }

    func testNoGymIsSelectedUntilTheUserChoosesOne() throws {
        let registry = makeRegistry()
        let library = sampleLibrary()

        XCTAssertTrue(try registry.gyms().isEmpty)
        XCTAssertNil(try registry.activeGym())
        XCTAssertNil(try registry.equipmentFilter())
        XCTAssertEqual(ExerciseLibrary.query(library, equipment: try registry.equipmentFilter()), library)

        let home = try registry.create(
            name: "  Home  ",
            region: "  ",
            equipment: [.dumbbells],
            preferredMachines: [" Smith ", "Smith", " "]
        )

        XCTAssertEqual(home.name, "Home")
        XCTAssertNil(home.region)
        XCTAssertEqual(home.preferredMachines, ["Smith"])
        XCTAssertNil(try registry.activeGym())
        XCTAssertEqual(ExerciseLibrary.query(library, equipment: try registry.equipmentFilter()), library)
    }

    func testManualSwitchPersistsAcrossLaunchesAndFiltersEquipment() throws {
        let registry = makeRegistry()
        let library = sampleLibrary()
        let north = try registry.create(
            name: "North",
            region: "north",
            equipment: [.dumbbells, .bench],
            preferredMachines: ["lat pulldown"]
        )
        clock.advance()
        let south = try registry.create(
            name: "South",
            region: nil,
            equipment: [.cable, .machine],
            preferredMachines: []
        )

        try registry.select(id: north.id)
        XCTAssertEqual(try registry.activeGym()?.id, north.id)
        XCTAssertEqual(try registry.equipmentFilter(), [.bench, .dumbbells])
        let withNorth = ExerciseLibrary.query(library, equipment: try registry.equipmentFilter())
        XCTAssertEqual(withNorth.map(\.id), ["curl", "press"])

        clock.advance()
        try registry.select(id: south.id)
        let relaunched = makeRegistry()
        XCTAssertEqual(try relaunched.gyms().map(\.id), [north.id, south.id])
        XCTAssertEqual(try relaunched.activeGym()?.id, south.id)
        XCTAssertEqual(try relaunched.activeGym()?.region, nil)
        let withSouth = ExerciseLibrary.query(library, equipment: try relaunched.equipmentFilter())
        XCTAssertEqual(withSouth.map(\.id), ["row"])
        XCTAssertFalse(try relaunched.equipmentFilter()?.contains(.smith) ?? true)
        XCTAssertEqual(try relaunched.activeGym()?.preferredMachines, [])
    }

    func testPreferredMachinesDoNotAddEquipment() throws {
        let registry = makeRegistry()
        let gym = try registry.create(
            name: "North",
            region: "north",
            equipment: [.dumbbells],
            preferredMachines: ["Smith machine"]
        )
        try registry.select(id: gym.id)

        XCTAssertEqual(try registry.equipmentFilter(), [.dumbbells])
        let matches = ExerciseLibrary.query(sampleLibrary(), equipment: try registry.equipmentFilter())
        XCTAssertEqual(matches.map(\.id), ["curl"])
    }

    func testClearingTheChoiceAllowsEveryExerciseAgain() throws {
        let registry = makeRegistry()
        let gym = try registry.create(
            name: "North",
            region: nil,
            equipment: [],
            preferredMachines: []
        )
        try registry.select(id: gym.id)
        XCTAssertEqual(try registry.equipmentFilter(), [])
        XCTAssertTrue(ExerciseLibrary.query(sampleLibrary(), equipment: try registry.equipmentFilter()).isEmpty)

        try registry.clearSelection()
        XCTAssertNil(try registry.equipmentFilter())
        XCTAssertEqual(
            ExerciseLibrary.query(sampleLibrary(), equipment: try registry.equipmentFilter()),
            sampleLibrary()
        )
    }

    func testDeletingTheActiveGymDoesNotSelectAnother() throws {
        let registry = makeRegistry()
        let north = try registry.create(name: "North", region: nil, equipment: [.dumbbells], preferredMachines: [])
        clock.advance()
        let south = try registry.create(name: "South", region: nil, equipment: [.cable], preferredMachines: [])
        try registry.select(id: north.id)
        clock.advance()
        try registry.delete(id: north.id)

        XCTAssertEqual(try registry.gyms().map(\.id), [south.id])
        XCTAssertNil(try registry.activeGym())
        XCTAssertNil(try makeRegistry().activeGym())
        XCTAssertNil(try registry.equipmentFilter())
    }

    func testSyncedGymsStayUnselectedAndOwnersStaySeparate() throws {
        let alice = makeRegistry(ownerId: "alice")
        let north = try alice.create(name: "North", region: "north", equipment: [.dumbbells], preferredMachines: [])
        try alice.select(id: north.id)
        let remote = MemoryGymRemote()
        try alice.sync(with: remote)

        XCTAssertEqual(try alice.activeGym()?.id, north.id)
        let otherPhone = GymRegistry(ownerId: "alice", rootURL: otherDirectory(), now: { self.clock.date })
        try otherPhone.sync(with: remote)
        XCTAssertEqual(try otherPhone.gyms().map(\.id), [north.id])
        XCTAssertNil(try otherPhone.activeGym())
        XCTAssertNil(try otherPhone.equipmentFilter())

        let bob = makeRegistry(ownerId: "bob", rootURL: otherDirectory())
        try bob.sync(with: remote)
        XCTAssertTrue(try bob.gyms().isEmpty)
        XCTAssertEqual(try alice.gyms().map(\.id), [north.id])
    }

    func testImportRejectsUnknownEquipmentWithoutChangingTheRegistry() throws {
        let registry = makeRegistry()
        let kept = try registry.create(name: "North", region: nil, equipment: [.dumbbells], preferredMachines: [])
        let record = GymSyncRecord(
            id: UUID(),
            name: "East",
            region: nil,
            equipment: ["teleporter"],
            preferredMachines: [],
            updatedAt: clock.date.addingTimeInterval(10),
            deletedAt: nil
        )

        XCTAssertThrowsError(try registry.importSyncRecords([record])) { error in
            XCTAssertEqual(error as? GymRegistryError, .unavailable)
        }
        XCTAssertEqual(try registry.gyms().map(\.id), [kept.id])
    }

    func testInvalidNameIsRejected() throws {
        let registry = makeRegistry()
        XCTAssertThrowsError(
            try registry.create(name: "   ", region: nil, equipment: [], preferredMachines: [])
        ) { error in
            XCTAssertEqual(error as? GymRegistryError, .invalidName)
        }
        XCTAssertTrue(try registry.gyms().isEmpty)
    }

    func testSyncRecordDoesNotCarryLocationOrASelection() throws {
        let registry = makeRegistry()
        _ = try registry.create(name: "North", region: "north", equipment: [.smith], preferredMachines: ["Smith"])
        let record = try XCTUnwrap(try registry.exportSyncRecords().first)
        let data = try JSONEncoder().encode(record)
        let json = try JSONSerialization.jsonObject(with: data)
        let object = try XCTUnwrap(json as? [String: Any])

        XCTAssertNil(object["latitude"])
        XCTAssertNil(object["longitude"])
        XCTAssertNil(object["location"])
        XCTAssertNil(object["activeGymID"])
        XCTAssertEqual(object["region"] as? String, "north")
    }

    private func makeRegistry(ownerId: String = "owner-a", rootURL: URL? = nil) -> GymRegistry {
        GymRegistry(ownerId: ownerId, rootURL: rootURL ?? directory, now: { self.clock.date })
    }

    private func otherDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LYB-GymRegistry-" + UUID().uuidString, isDirectory: true)
        extraDirectories.append(url)
        return url
    }

    private func sampleLibrary() -> [LibraryExercise] {
        [
            LibraryExercise(id: "curl", name: "Dumbbell curl", requiredEquipment: [.dumbbells]),
            LibraryExercise(id: "press", name: "Dumbbell press", requiredEquipment: [.dumbbells, .bench]),
            LibraryExercise(id: "row", name: "Cable row", requiredEquipment: [.cable]),
            LibraryExercise(id: "smith", name: "Smith press", requiredEquipment: [.smith, .adjustableBench])
        ]
    }
}

private final class TestClock {
    var date: Date

    init(date: Date) {
        self.date = date
    }

    func advance(_ seconds: TimeInterval = 1) {
        date = date.addingTimeInterval(seconds)
    }
}

private final class MemoryGymRemote: GymRemoteStore {
    private var records: [String: [GymSyncRecord]] = [:]

    func pull(ownerId: String) throws -> [GymSyncRecord] {
        records[ownerId] ?? []
    }

    func push(ownerId: String, records: [GymSyncRecord]) throws {
        self.records[ownerId] = records
    }
}
