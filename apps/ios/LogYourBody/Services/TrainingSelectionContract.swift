import Foundation

enum TrainingSelectionPolicy {
    static let featureGate = "exercise_selection_v1"
}

struct TrainingSelectionContext: Codable, Equatable, Sendable {
    var gymId: String
    var availableEquipment: [String]
    var excludedConcerns: [String]
    var setupNote: String?
}

struct TrainingSelectionRequest: Encodable, Equatable, Sendable {
    let sessionId: String
    let exerciseId: String
    let context: TrainingSelectionContext
}

struct TrainingSelectionResponse: Decodable, Equatable, Sendable {
    struct Review: Decodable, Equatable, Sendable {
        struct Option: Decodable, Equatable, Identifiable, Sendable {
            let variantId: String
            let reason: String
            let name: String
            let setup: TrainingVariantSetup
            var id: String { variantId }
            var reasonText: String {
                switch reason {
                case "supported_exercise_previously_tolerated": "Different exercise · repeatedly tolerated in this gym"
                case "supported_setup_previously_tolerated": "Same exercise setup · repeatedly tolerated in this gym"
                case "supported_exercise_trial": "Different exercise · supported option to try"
                default: "Same exercise setup · supported option to try"
                }
            }
        }
        let sessionId: String
        let exerciseId: String
        let revision: Int
        let status: String
        let context: TrainingSelectionContext
        let preferredContext: TrainingSelectionContext?
        let options: [Option]
        let message: String
    }
    let version: Int
    let review: Review
}

struct TrainingVariantSetup: Codable, Equatable, Sendable {
    struct Metadata: Codable, Equatable, Sendable {
        let targetRegion: String
        let support: String
        let romSetupCaveat: String
    }
    struct Demand: Codable, Equatable, Sendable {
        let level: String
        let basis: String
        let note: String
    }
    struct Pulley: Codable, Equatable, Sendable {
        let height: String
        let attachment: String
    }
    let requires: [String]
    let bodyPosition: String
    let torsoSupport: String
    let trunkDemand: Demand
    let benchAngleDeg: Double?
    let pulley: Pulley?
    let cues: [String]
    var variantMetadata: Metadata?
}

struct TrainingFeedbackContext: Codable, Equatable, Sendable {
    let exerciseId: String
    let setNumber: Int
    var reps: Int?
    var loadKg: Double?
    var rir: Int?
    var gymId: String?
    var availableEquipment: [String]?
    var setup: String?
    var romRestriction: String?
}

struct TrainingWorkoutActionRequest: Encodable, Equatable, Sendable {
    let sessionId: String
    let eventId: String
    let expectedRevision: Int
    let action: TrainingWorkoutAction
}
