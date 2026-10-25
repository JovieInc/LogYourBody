import Foundation

enum GymRegistryPolicy {
    static let featureGate = "gym_registry_v1"
}

/// Keep raw values aligned with the server exercise catalog's concrete requirements.
enum GymEquipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case dumbbells, barbell, machine, cable, bench, bodyweight, smith
    case ezBar = "ez_bar"
    case adjustableBench = "adjustable_bench"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dumbbells: "Dumbbells"
        case .barbell: "Barbell"
        case .machine: "Machines"
        case .cable: "Cable station"
        case .bench: "Flat bench"
        case .bodyweight: "Bodyweight setup"
        case .smith: "Smith machine"
        case .ezBar: "EZ bar"
        case .adjustableBench: "Adjustable bench"
        }
    }
}

struct Gym: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var coarseRegion: String?
    var equipment: Set<GymEquipment>
    var preferredMachines: [String]

    func validated() throws -> Gym {
        var gym = self
        gym.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        gym.coarseRegion = coarseRegion?.trimmingCharacters(in: .whitespacesAndNewlines)
        if gym.coarseRegion?.isEmpty == true { gym.coarseRegion = nil }
        gym.preferredMachines = preferredMachines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard (1...120).contains(gym.name.utf16.count), (gym.coarseRegion?.utf16.count ?? 0) <= 120,
              gym.preferredMachines.count <= 30,
              gym.preferredMachines.allSatisfy({ (1...120).contains($0.utf16.count) })
        else { throw GymRegistryError.invalidGym }
        return gym
    }
}

struct GymRecord: Codable, Equatable, Sendable {
    var gym: Gym
    var deleted: Bool
}

struct GymLibraryExercise: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let requires: Set<GymEquipment>
}

enum GymRegistryError: LocalizedError, Equatable {
    case invalidGym, unavailable, accountChanged, invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidGym: "Enter a gym name and keep names and region under 120 characters. Use up to 30 preferred machines."
        case .unavailable: "Your gyms could not be saved or synced. Try again."
        case .accountChanged: "Sign in again to manage your gyms."
        case .invalidResponse: "Your gyms could not be read. Try again."
        }
    }
}
