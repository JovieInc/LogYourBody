import Foundation

enum GymEquipment: String, Codable, CaseIterable, Sendable {
    case dumbbells, barbell, machine, cable, bench, bodyweight, smith
    case ezBar = "ez_bar"
    case adjustableBench = "adjustable_bench"

    var title: String {
        switch self {
        case .dumbbells: "Dumbbells"
        case .barbell: "Barbell"
        case .machine: "Machines"
        case .cable: "Cable"
        case .bench: "Bench"
        case .bodyweight: "Bodyweight"
        case .smith: "Smith machine"
        case .ezBar: "EZ bar"
        case .adjustableBench: "Adjustable bench"
        }
    }
}

struct Gym: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var region: String?
    var equipment: Set<GymEquipment>
    var preferredMachines: [String]

    func validated() throws -> Gym {
        var value = self
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.region = region?.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.region?.isEmpty == true { value.region = nil }
        value.preferredMachines = preferredMachines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !value.name.isEmpty, value.name.count <= 100, (value.region?.count ?? 0) <= 100,
              value.preferredMachines.count <= 50,
              value.preferredMachines.allSatisfy({ !$0.isEmpty && $0.count <= 100 })
        else { throw GymRegistryError.invalidGym }
        return value
    }
}

enum GymRegistryError: LocalizedError {
    case invalidGym, unavailable, accountChanged

    var errorDescription: String? {
        switch self {
        case .invalidGym: "Enter a gym name and review your equipment and machine preferences."
        case .unavailable: "Gyms couldn’t be loaded or saved. Try again."
        case .accountChanged: "Your account changed. Reopen Gyms to continue."
        }
    }
}

struct GymRegistrySnapshot: Codable, Equatable {
    var gyms: [Gym] = []
    var activeGymId: UUID?
    var pending: Set<UUID> = []
    var removed: Set<UUID> = []

    var activeGym: Gym? { gyms.first { $0.id == activeGymId } }
    /// nil means unrestricted, not an assumed inventory. [] means explicitly no equipment.
    var equipmentFilter: Set<GymEquipment>? { activeGym?.equipment }
}
