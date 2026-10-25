import Combine
import Foundation

enum TrainingProgressPolicy {
    static let featureGate = "training_progress_history_v1"
}

struct TrainingProgressResponse: Decodable, Equatable, Sendable {
    let version: Int
    let progress: TrainingProgress
}

struct TrainingProgress: Decodable, Equatable, Sendable {
    let enrolled: Bool
    let completedSessions: Int
    let setsLast7Days: Int
    let exercises: [Exercise]
    let latestCheckIn: Feedback?
    let sessions: [SessionHistory]

    struct Exercise: Decodable, Equatable, Identifiable, Sendable {
        var id: String { exerciseId }
        let exerciseId: String
        let name: String
        let lastPerformedAt: String
        let lastSession: [RecordedSet]
        let heaviestSet: RecordedSet?
        let totalSets: Int
    }

    struct RecordedSet: Decodable, Equatable, Identifiable, Sendable {
        let id: String
        let sessionId: String
        let exerciseId: String
        let setNumber: Int
        let reps: Int
        let loadKg: Double?
        let rir: Int
        let completedAt: String
        let revision: Int?
        let corrections: [TrainingSetCorrectionAudit]?

        var performanceText: String {
            let load = loadKg.map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) kg" }
                ?? "bodyweight"
            return "\(reps) reps · \(load) · \(rir) RIR"
        }
    }

    struct SessionHistory: Decodable, Equatable, Identifiable, Sendable {
        var id: String { sessionId }
        let sessionId: String
        let programSetupId: String
        let programRevisionId: String?
        let blockId: String?
        let status: String
        let startedAt: String?
        let completedAt: String?
        let initialPrescription: TrainingSession?
        let prescription: TrainingSession?
        let sets: [RecordedSet]
        let feedback: [Feedback]

        var statusText: String {
            switch status {
            case "completed": "Session completed"
            case "paused": "Session paused"
            case "in_progress": "Session in progress"
            default: "Session status unknown"
            }
        }

        var skippedExerciseNames: [String] {
            (prescription?.executionEvents ?? []).filter { $0.kind == "skipped" }.compactMap { event in
                guard let exerciseId = event.exerciseId else { return nil }
                return initialPrescription?.exercises.first { $0.id == exerciseId }?.name ?? exerciseId
            }
        }
    }

    struct Feedback: Decodable, Equatable, Identifiable, Sendable {
        let id: String
        let sessionId: String
        let soreness: Int?
        let pump: Int?
        let performance: String?
        let jointPain: Int?
        let muscles: [String: TrainingMuscleFeedbackRequest]?
        let targetMuscle: String?
        let targetMuscleReadiness: String?
        let breathingReadiness: String?
        let generalReadiness: String?
        let supportingReadiness: SupportingReadiness?
        let trunkFatigue: Int?
        let generalExhaustion: Int?
        let symptomFlags: [String]?
        let symptomNote: String?
        let originalStatement: String?
        let transcriptionUncertain: Bool?
        let source: String?
        let observedAt: String?
        let sourceObservationId: String?
        let correctsObservationId: String?
        let context: Context?
        let interpretations: [Interpretation]?
        let createdAt: String

        struct Context: Decodable, Equatable, Sendable {
            let exerciseId: String?
            let setId: String?
            let setNumber: Int?
            let setOrder: Int?
            let reps: Int?
            let loadKg: Double?
            let rir: Int?
            let restSeconds: Int?
            let setup: String?
            let rangeOfMotion: String?
            let setFormat: String?
        }

        struct SupportingReadiness: Decodable, Equatable, Sendable {
            let grip: String?
            let trunk: String?
            let muscles: [String: String]?
        }

        struct Interpretation: Decodable, Equatable, Sendable {
            let claim: String
            let timeframe: String
            let confidence: String
            let corroboratesObservationIds: [String]?
            let conflictsWithObservationIds: [String]?
            let proposedExplanation: String?
        }
    }
}

/// An engine receipt already returned by /next. The native surface only renders it.
struct TrainingProgressDecision: Codable, Equatable, Sendable {
    struct Decision: Codable, Equatable, Sendable {
        let kind: String
        let requiresConfirmation: Bool?
    }

    let decision: Decision
    let rationale: String
    let evidenceIds: [String]
    let before: String
    let after: String
    let reviewPoint: String
    let nextAction: String

    var hasMeaningfulChange: Bool {
        ["adjust_training", "adjust_activity", "recovery_proposal", "reschedule"].contains(decision.kind)
            && before != after
    }
}

@MainActor
final class TrainingProgressModel: ObservableObject {
    @Published private(set) var response: TrainingProgressResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var requestId: UUID?
    private let isCurrent: () -> Bool

    init(isCurrent: @escaping () -> Bool) {
        self.isCurrent = isCurrent
    }

    func load(using fetch: () async throws -> TrainingProgressResponse) async {
        let identifier = UUID()
        requestId = identifier
        guard isCurrent() else {
            response = nil
            errorMessage = nil
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { if requestId == identifier { isLoading = false } }
        do {
            let result = try await fetch()
            guard requestId == identifier else { return }
            guard isCurrent() else { response = nil; return }
            guard result.version == TrainingAPIContract.version else { throw TrainingServiceError.invalidResponse }
            response = result
        } catch {
            guard requestId == identifier else { return }
            guard isCurrent() else { response = nil; return }
            errorMessage = "History could not be refreshed. Your workout is still available."
        }
    }
}
