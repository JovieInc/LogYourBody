import CryptoKit
import Foundation

/// Equipment the exercise library can filter on. Values match the reviewed catalog.
enum GymEquipment: String, Codable, CaseIterable, Equatable, Sendable {
    case dumbbells
    case barbell
    case ezBar = "ez_bar"
    case machine
    case cable
    case bench
    case adjustableBench = "adjustable_bench"
    case bodyweight
    case smith
}

struct LibraryExercise: Equatable, Sendable {
    let id: String
    let name: String
    let requiredEquipment: Set<GymEquipment>
}

/// `equipment == nil` means no gym is confirmed, so every exercise stays available.
/// An empty set is a confirmed gym that saved no equipment.
enum ExerciseLibrary {
    static func query(
        _ exercises: [LibraryExercise],
        equipment: Set<GymEquipment>?
    ) -> [LibraryExercise] {
        guard let equipment else { return exercises }
        return exercises.filter { $0.requiredEquipment.isSubset(of: equipment) }
    }
}

struct Gym: Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    /// User-typed coarse label such as "north". Never a device location.
    var region: String?
    var equipment: Set<GymEquipment>
    var preferredMachines: [String]
    var updatedAt: Date
    var deletedAt: Date?
}

struct GymSyncRecord: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var region: String?
    var equipment: [String]
    var preferredMachines: [String]
    var updatedAt: Date
    var deletedAt: Date?
}

enum GymRegistryError: Error, Equatable {
    case invalidName
    case invalidRegion
    case invalidMachine
    case missingGym
    case unavailable
}

protocol GymRemoteStore {
    func pull(ownerId: String) throws -> [GymSyncRecord]
    func push(ownerId: String, records: [GymSyncRecord]) throws
}

/// Local gym registry. Creating or syncing a gym never selects it.
/// The active gym is only the one the user last chose on this device.
final class GymRegistry {
    private struct Snapshot: Codable {
        var version: Int
        var ownerId: String
        var activeGymID: UUID?
        var gyms: [StoredGym]
    }

    private struct StoredGym: Codable, Equatable {
        var id: UUID
        var name: String
        var region: String?
        var equipment: [String]
        var preferredMachines: [String]
        var updatedAt: Date
        var deletedAt: Date?

        var gym: Gym {
            Gym(
                id: id,
                name: name,
                region: region,
                equipment: Set(equipment.compactMap(GymEquipment.init(rawValue:))),
                preferredMachines: preferredMachines,
                updatedAt: updatedAt,
                deletedAt: deletedAt
            )
        }
    }

    private let ownerId: String
    private let rootURL: URL
    private let now: () -> Date
    private let fileManager: FileManager

    init(ownerId: String, rootURL: URL, now: @escaping () -> Date = Date.init, fileManager: FileManager = .default) {
        self.ownerId = ownerId
        self.rootURL = rootURL
        self.now = now
        self.fileManager = fileManager
    }

    func gyms() throws -> [Gym] {
        try load().gyms
            .filter { $0.deletedAt == nil }
            .sorted { lhs, rhs in
                if lhs.name == rhs.name { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.name < rhs.name
            }
            .map(\.gym)
    }

    func activeGym() throws -> Gym? {
        let snapshot = try load()
        guard let id = snapshot.activeGymID else { return nil }
        return snapshot.gyms.first { $0.id == id && $0.deletedAt == nil }?.gym
    }

    /// Nil means no gym is confirmed and exercise queries should allow every item.
    func equipmentFilter() throws -> Set<GymEquipment>? {
        try activeGym()?.equipment
    }

    @discardableResult
    func create(
        name: String,
        region: String?,
        equipment: Set<GymEquipment>,
        preferredMachines: [String]
    ) throws -> Gym {
        let draft = try validated(name: name, region: region, equipment: equipment, machines: preferredMachines)
        var snapshot = try load()
        let stored = StoredGym(
            id: UUID(),
            name: draft.name,
            region: draft.region,
            equipment: draft.equipment,
            preferredMachines: draft.machines,
            updatedAt: now(),
            deletedAt: nil
        )
        snapshot.gyms.append(stored)
        try persist(snapshot)
        return stored.gym
    }

    @discardableResult
    func update(
        id: UUID,
        name: String,
        region: String?,
        equipment: Set<GymEquipment>,
        preferredMachines: [String]
    ) throws -> Gym {
        let draft = try validated(name: name, region: region, equipment: equipment, machines: preferredMachines)
        var snapshot = try load()
        guard let index = snapshot.gyms.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw GymRegistryError.missingGym
        }
        snapshot.gyms[index].name = draft.name
        snapshot.gyms[index].region = draft.region
        snapshot.gyms[index].equipment = draft.equipment
        snapshot.gyms[index].preferredMachines = draft.machines
        snapshot.gyms[index].updatedAt = now()
        try persist(snapshot)
        return snapshot.gyms[index].gym
    }

    func delete(id: UUID) throws {
        var snapshot = try load()
        guard let index = snapshot.gyms.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw GymRegistryError.missingGym
        }
        let timestamp = now()
        snapshot.gyms[index].deletedAt = timestamp
        snapshot.gyms[index].updatedAt = timestamp
        if snapshot.activeGymID == id {
            snapshot.activeGymID = nil
        }
        try persist(snapshot)
    }

    func select(id: UUID) throws {
        var snapshot = try load()
        guard snapshot.gyms.contains(where: { $0.id == id && $0.deletedAt == nil }) else {
            throw GymRegistryError.missingGym
        }
        snapshot.activeGymID = id
        try persist(snapshot)
    }

    func clearSelection() throws {
        var snapshot = try load()
        snapshot.activeGymID = nil
        try persist(snapshot)
    }

    func exportSyncRecords() throws -> [GymSyncRecord] {
        try load().gyms.map { stored in
            GymSyncRecord(
                id: stored.id,
                name: stored.name,
                region: stored.region,
                equipment: stored.equipment.sorted(),
                preferredMachines: stored.preferredMachines,
                updatedAt: stored.updatedAt,
                deletedAt: stored.deletedAt
            )
        }
    }

    /// Merges server rows. A synced gym is never selected. A deleted active gym clears the choice.
    func importSyncRecords(_ records: [GymSyncRecord]) throws {
        var snapshot = try load()
        for record in records {
            let incoming = try stored(from: record)
            if let index = snapshot.gyms.firstIndex(where: { $0.id == incoming.id }) {
                if incoming.updatedAt > snapshot.gyms[index].updatedAt {
                    snapshot.gyms[index] = incoming
                }
            } else {
                snapshot.gyms.append(incoming)
            }
        }
        if let active = snapshot.activeGymID,
           !snapshot.gyms.contains(where: { $0.id == active && $0.deletedAt == nil }) {
            snapshot.activeGymID = nil
        }
        try persist(snapshot)
    }

    func sync(with remote: GymRemoteStore) throws {
        try importSyncRecords(try remote.pull(ownerId: ownerId))
        try remote.push(ownerId: ownerId, records: try exportSyncRecords())
    }

    private struct Draft {
        var name: String
        var region: String?
        var equipment: [String]
        var machines: [String]
    }

    private func validated(
        name: String,
        region: String?,
        equipment: Set<GymEquipment>,
        machines: [String]
    ) throws -> Draft {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(trimmedName.count) else { throw GymRegistryError.invalidName }
        let trimmedRegion = region?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let storedRegion: String?
        if trimmedRegion.isEmpty {
            storedRegion = nil
        } else if trimmedRegion.count <= 80 {
            storedRegion = trimmedRegion
        } else {
            throw GymRegistryError.invalidRegion
        }
        var seen: Set<String> = []
        var storedMachines: [String] = []
        for machine in machines {
            let trimmed = machine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard trimmed.count <= 80 else { throw GymRegistryError.invalidMachine }
            guard seen.insert(trimmed).inserted else { continue }
            guard storedMachines.count < 24 else { throw GymRegistryError.invalidMachine }
            storedMachines.append(trimmed)
        }
        return Draft(
            name: trimmedName,
            region: storedRegion,
            equipment: equipment.map(\.rawValue).sorted(),
            machines: storedMachines
        )
    }

    private func stored(from record: GymSyncRecord) throws -> StoredGym {
        guard record.equipment.allSatisfy({ GymEquipment(rawValue: $0) != nil }) else {
            throw GymRegistryError.unavailable
        }
        let draft = try validated(
            name: record.name,
            region: record.region,
            equipment: Set(record.equipment.compactMap(GymEquipment.init(rawValue:))),
            machines: record.preferredMachines
        )
        return StoredGym(
            id: record.id,
            name: draft.name,
            region: draft.region,
            equipment: draft.equipment,
            preferredMachines: draft.machines,
            updatedAt: record.updatedAt,
            deletedAt: record.deletedAt
        )
    }

    private func load() throws -> Snapshot {
        let url = fileURL()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Snapshot(version: 1, ownerId: ownerId, activeGymID: nil, gyms: [])
        } catch {
            throw GymRegistryError.unavailable
        }
        let snapshot: Snapshot
        do {
            snapshot = try GymCoding.decoder().decode(Snapshot.self, from: data)
        } catch {
            throw GymRegistryError.unavailable
        }
        guard snapshot.version == 1, snapshot.ownerId == ownerId else { throw GymRegistryError.unavailable }
        let known = snapshot.gyms.allSatisfy { gym in
            gym.equipment.allSatisfy { GymEquipment(rawValue: $0) != nil }
        }
        guard known else { throw GymRegistryError.unavailable }
        return snapshot
    }

    private func persist(_ snapshot: Snapshot) throws {
        do {
            let directory = ownerURL()
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
            var root = rootURL
            var resources = URLResourceValues()
            resources.isExcludedFromBackup = true
            try root.setResourceValues(resources)
            let data = try GymCoding.encoder().encode(snapshot)
            try data.write(
                to: fileURL(),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
        } catch {
            throw GymRegistryError.unavailable
        }
    }

    private func ownerURL() -> URL {
        rootURL.appendingPathComponent(digest(ownerId), isDirectory: true)
    }

    private func fileURL() -> URL {
        ownerURL().appendingPathComponent("gyms.json")
    }

    private func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private enum GymCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid gym timestamp")
            }
            return date
        }
        return decoder
    }

    private static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
