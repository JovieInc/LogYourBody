import Foundation

struct TrainingCyclePriority: Codable, Equatable, Sendable {
    let muscle: String
    let reason: String
}

struct TrainingCycleConstraint: Codable, Equatable, Sendable {
    let id: String
    let reason: String
}

struct TrainingRetainedVariant: Codable, Equatable, Identifiable, Sendable {
    let fromExerciseId: String
    let toVariantId: String
    let reason: String
    var name: String?
    var id: String { fromExerciseId + ":" + toVariantId }
}

struct TrainingRevisionContextResponse: Decodable {
    let version: Int
    let generation: Int
    let cycle: Cycle?

    struct Cycle: Decodable {
        let phase: String?
        let weekCount: Int
        let priorities: [TrainingCyclePriority]
        let constraints: [TrainingCycleConstraint]
        let retainedVariants: [TrainingRetainedVariant]
        let variants: [TrainingRetainedVariant]
    }
}

struct TrainingCycleIntent: Encodable {
    let kind: String
    let weekCount: Int
    var adultConfirmed: Bool?
    var safetyConfirmed: Bool?
    var sessionsPerWeek: Int?
    var equipment: String?
    var priorities: [TrainingCyclePriority]?
    var constraints: [TrainingCycleConstraint]?
    var retainedVariants: [TrainingRetainedVariant]?
}

struct TrainingCycleProposalRequest: Encodable {
    let requestId: String
    let expectedGeneration: Int
    let intent: TrainingCycleIntent
    let reason: String
}

struct TrainingCycleProposal: Decodable {
    let id: String
    let reason: String
    let assumptions: [String]
    let plan: Plan
    struct Plan: Decodable {
        let week: Int
        let sessions: [TrainingSession]
    }
}

struct TrainingCycleProposalResponse: Decodable {
    let version: Int
    let stored: Stored
    struct Stored: Decodable {
        let proposal: TrainingCycleProposal
        let status: String
    }
}

struct TrainingCycleDecisionRequest: Encodable {
    let requestId: String
    let proposalId: String
    let decision: String
}

struct TrainingCycleDecisionResponse: Decodable {
    let version: Int
    let receipt: Receipt
    struct Receipt: Decodable {
        let proposalId: String
        let status: String
    }
}

protocol TrainingCycleReviewServicing {
    func loadRevisionContext(accessToken: String) async throws -> TrainingRevisionContextResponse
    func proposeCycle(accessToken: String, request: TrainingCycleProposalRequest) async throws -> TrainingCycleProposalResponse
    func decideCycle(accessToken: String, request: TrainingCycleDecisionRequest) async throws -> TrainingCycleDecisionResponse
}

extension URLSessionTrainingService: TrainingCycleReviewServicing {}

#if DEBUG
struct FixtureTrainingCycleReviewService: TrainingCycleReviewServicing {
    func loadRevisionContext(accessToken: String) async throws -> TrainingRevisionContextResponse {
        guard accessToken == "fixture-cycle-token" else { throw TrainingServiceError.authenticationExpired }
        let reuse = ProcessInfo.processInfo.arguments.contains("-lybUITestCycleReuse")
        let kept = TrainingRetainedVariant(
            fromExerciseId: "fixture_press", toVariantId: "fixture_press",
            reason: "Comfortable and progressed", name: "Fixture press"
        )
        return TrainingRevisionContextResponse(version: 1, generation: 0, cycle: reuse ? .init(
            phase: "review", weekCount: 4, priorities: [.init(muscle: "back", reason: "My temporary focus")],
            constraints: [], retainedVariants: [], variants: [kept]
        ) : nil)
    }

    func proposeCycle(accessToken: String, request: TrainingCycleProposalRequest) async throws -> TrainingCycleProposalResponse {
        guard accessToken == "fixture-cycle-token" else { throw TrainingServiceError.authenticationExpired }
        let reasons = (request.intent.retainedVariants ?? []).map(\.reason)
        return TrainingCycleProposalResponse(version: 1, stored: .init(proposal: .init(
            id: "fixture-cycle-proposal", reason: request.reason,
            assumptions: reasons + ["Temporary priorities expire unless renewed."], plan: .init(week: 1, sessions: [])
        ), status: "proposed"))
    }

    func decideCycle(accessToken: String, request: TrainingCycleDecisionRequest) async throws -> TrainingCycleDecisionResponse {
        guard accessToken == "fixture-cycle-token" else { throw TrainingServiceError.authenticationExpired }
        return TrainingCycleDecisionResponse(version: 1, receipt: .init(
            proposalId: request.proposalId, status: request.decision == "apply" ? "applied" : "rejected"
        ))
    }
}
#endif
