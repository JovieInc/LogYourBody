import Foundation

enum TrainingAPIContract {
    static let version = 1
    static let rootPath = "/api/auth/mobile/training/v1"
    static let consentVersion = "hypertrophy-coach-v1"
}

enum TrainingCoachPolicy {
    static let featureGate = "hypertrophy_coach_v1"

    static func isEnabled(checkGate: (String) -> Bool) -> Bool {
        checkGate(featureGate)
    }
}

enum TrainingReadinessPolicy {
    static let featureGate = "workout_readiness_v1"
}

struct TrainingExercisePrescription: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let primaryMuscle: String
    let muscleContribution: [String: Double]
    let sets: Int
    let repRange: RepRange
    let targetReps: Int
    let targetRir: Int
    let targetLoadKg: Double?
    let loadInstruction: String?
    let progression: String
    let evidenceIds: [String]
    var substitutions: [TrainingExerciseSubstitution]?

    struct RepRange: Decodable, Equatable, Sendable {
        let min: Int
        let max: Int
    }
}

struct TrainingExerciseSubstitution: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let primaryMuscle: String
    let muscleContribution: [String: Double]
    let sets: Int
    let repRange: TrainingExercisePrescription.RepRange
    let targetReps: Int
    let targetRir: Int
    let targetLoadKg: Double?
    let loadInstruction: String?
    let progression: String
    let evidenceIds: [String]
}

struct TrainingWorkoutEvent: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let createdAt: String
    let exerciseId: String?
    let replacementExerciseId: String?
    let minutes: Int?
}

struct TrainingSession: Decodable, Equatable, Identifiable, Sendable {
    let id: String
    let week: Int
    let slot: Int
    let pattern: String
    let title: String
    let exercises: [TrainingExercisePrescription]
    let safetyStop: Bool
    let explanation: String?
    let evidenceIds: [String]
    let loggedSets: [TrainingSavedSet]?
    var executionRevision: Int?
    var executionPaused: Bool?
    var executionEvents: [TrainingWorkoutEvent]?
}

struct TrainingSavedSet: Codable, Equatable, Sendable {
    let sessionId: String
    let exerciseId: String
    let setNumber: Int
    let reps: Int
    let loadKg: Double?
    let rir: Int
    var completedAt: String?
    var revision: Int?
    var corrections: [TrainingSetCorrectionAudit]?
}

struct TrainingSetCorrectionAudit: Codable, Equatable, Sendable {
    struct Previous: Codable, Equatable, Sendable {
        let reps: Int
        let loadKg: Double?
        let rir: Int
    }

    let id: String
    let correctedAt: String
    let previous: Previous
}

struct TrainingNextResponse: Decodable, Equatable, Sendable {
    let version: Int
    let error: String?
    let session: TrainingSession?
    let week: Int?
    let weekCount: Int?
    let weeklyFractionalVolume: [String: Double]?
    var decision: TrainingProgressDecision?
    var nextBlock: TrainingPlanStoredProposal?
}

struct TrainingProgramResponse: Decodable, Equatable, Sendable {
    let version: Int
    let program: Program

    struct Program: Decodable, Equatable, Sendable {
        let id: String
        let consentVersion: String
        let sessionsPerWeek: Int
        let equipment: String
    }
}

struct TrainingRevokeResponse: Decodable, Equatable, Sendable {
    let version: Int
    let revoked: Bool
    let deletedRecords: Int
}

struct TrainingSetLogRequest: Codable, Equatable, Sendable {
    let sessionId: String
    let exerciseId: String
    let setNumber: Int
    let reps: Int
    let loadKg: Double?
    let rir: Int
}

struct TrainingMuscleFeedbackRequest: Codable, Equatable, Sendable {
    let soreness: Int?
    let recovery: String?
    let pump: Int?
    let workload: String?
    let performance: String?
}

struct TrainingSetUndoRequest: Codable, Equatable, Sendable {
    let sessionId: String
    let exerciseId: String
    let setNumber: Int
    let undoId: String
    let expectedRevision: Int
}

struct TrainingSetCorrectionRequest: Codable, Equatable, Sendable {
    let sessionId: String
    let exerciseId: String
    let setNumber: Int
    let reps: Int
    let loadKg: Double?
    let rir: Int
    let correctionId: String
    let expectedRevision: Int
}

struct TrainingWorkoutAction: Encodable, Equatable, Sendable {
    let kind: String
    let exerciseId: String?
    let minutes: Int?

    static func equipmentUnavailable(_ exerciseId: String) -> Self {
        Self(kind: "equipment_unavailable", exerciseId: exerciseId, minutes: nil)
    }

    static func skip(_ exerciseId: String) -> Self {
        Self(kind: "skip", exerciseId: exerciseId, minutes: nil)
    }

    static func pain(_ exerciseId: String) -> Self {
        Self(kind: "pain", exerciseId: exerciseId, minutes: nil)
    }

    static func shorten(_ minutes: Int) -> Self {
        Self(kind: "shorten", exerciseId: nil, minutes: minutes)
    }

    static let pause = Self(kind: "pause", exerciseId: nil, minutes: nil)
    static let resume = Self(kind: "resume", exerciseId: nil, minutes: nil)
    static let end = Self(kind: "end", exerciseId: nil, minutes: nil)
}

struct TrainingWorkoutActionRequest: Encodable, Equatable, Sendable {
    let sessionId: String
    let eventId: String
    let expectedRevision: Int
    let action: TrainingWorkoutAction
}

struct TrainingFeedbackContext: Codable, Equatable, Sendable {
    let exerciseId: String
    let setNumber: Int
    var reps: Int?
    var loadKg: Double?
    var rir: Int?
}

struct TrainingSupportingReadiness: Codable, Equatable, Sendable {
    let grip: String?
}

struct TrainingNextSetRecommendation: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case proceed
        case extendRest = "extend_rest"
        case adjustOrSkip = "adjust_or_skip_task"
        case clarify
        case symptomSafety = "symptom_safety"
    }

    let scope: String
    let action: Action
    let reasons: [String]
    let uncertainty: String
    let observationIds: [String]
    let weeklyPlanChanged: Bool
    let safetyCertified: Bool

    var title: String {
        switch action {
        case .proceed: "Attempt the intended set when you feel ready"
        case .extendRest: "Continue resting"
        case .adjustOrSkip: "Adjust or skip this exercise today"
        case .clarify: "Keep resting or tell LYB what is limiting you"
        case .symptomSafety: "Pause and review symptoms"
        }
    }
}

struct TrainingFeedbackResponse: Codable, Equatable, Sendable {
    struct Receipt: Codable, Equatable, Sendable {
        let id: String
        let observation: TrainingFeedbackRequest

        private enum CodingKeys: CodingKey { case id }

        init(id: String, observation: TrainingFeedbackRequest) {
            self.id = id
            self.observation = observation
        }

        init(from decoder: Decoder) throws {
            id = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .id)
            observation = try TrainingFeedbackRequest(from: decoder)
        }

        func encode(to encoder: Encoder) throws {
            try observation.encode(to: encoder)
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
        }
    }

    let version: Int
    let feedback: Receipt
    let nextSetRecommendation: TrainingNextSetRecommendation

    func matches(_ request: TrainingFeedbackRequest) -> Bool {
        // The canonical command may return the original receipt for an exact duplicate observation.
        // Compare its payload, rather than treating a new client UUID as new corroboration.
        var expected = request
        var received = feedback.observation
        expected.sourceObservationId = nil
        received.sourceObservationId = nil
        expected.observedAt = nil
        received.observedAt = nil
        expected.source = "unknown"
        received.source = "unknown"
        if request.correctsObservationId == nil { received.correctsObservationId = nil }
        return version == TrainingAPIContract.version && !feedback.id.isEmpty && expected == received &&
            nextSetRecommendation.scope == "between_set" && !nextSetRecommendation.weeklyPlanChanged &&
            !nextSetRecommendation.safetyCertified
    }
}

struct TrainingWorkoutFeedback: Codable, Equatable, Sendable {
    enum Intent: String, Codable, CaseIterable, Sendable {
        case breathingLimited = "breathing_limited"
        case gripLimited = "grip_limited"
        case moreRest = "more_rest"
        case ready
        case unusuallyWeak = "unusually_weak"
        case unknown
    }

    let sessionId: String
    let exerciseId: String
    let setNumber: Int
    let intent: Intent
    let originalStatement: String
}

struct TrainingFeedbackRequest: Codable, Equatable, Sendable {
    let sessionId: String
    let soreness: Int?
    let pump: Int?
    let performance: String?
    let jointPain: Int?
    let muscles: [String: TrainingMuscleFeedbackRequest]?
    var source: String
    var sourceObservationId: String?
    var observedAt: String?
    var correctsObservationId: String?
    var context: TrainingFeedbackContext?
    var targetMuscle: String?
    var targetMuscleReadiness: String?
    var breathingReadiness: String?
    var supportingReadiness: TrainingSupportingReadiness?
    var originalStatement: String?

    init(
        sessionId: String,
        soreness: Int? = nil,
        pump: Int? = nil,
        performance: String? = nil,
        jointPain: Int? = nil,
        muscles: [String: TrainingMuscleFeedbackRequest]? = nil,
        source: String = "touch"
    ) {
        self.sessionId = sessionId
        self.soreness = soreness
        self.pump = pump
        self.performance = performance
        self.jointPain = jointPain
        self.muscles = muscles
        self.source = source
    }
}

enum TrainingServiceError: LocalizedError, Equatable {
    case authenticationExpired
    case rateLimited(retryAfterSeconds: Int)
    case invalidResponse
    case server(code: String)

    var errorDescription: String? {
        switch self {
        case .authenticationExpired:
            return "Your session expired. Sign in again to continue."
        case .rateLimited:
            return "Training is temporarily unavailable. Try again shortly."
        case .invalidResponse:
            return "The training response could not be read. Please try again."
        case .server(let code):
            switch code {
            case "not_found":
                return "Training coaching is not enabled for this account yet."
            case "set_conflict":
                return "This set changed since that action. Review it before trying again."
            case "undo_unavailable":
                return "This set cannot be undone. Correct it instead."
            case "delayed_active_workout":
                return "Finish or end your current workout before applying this plan."
            case "stale_context":
                return "Your training changed. Refresh the draft before applying it."
            default:
                return "Training is temporarily unavailable. Please try again."
            }
        }
    }
}

protocol TrainingServicing {
    func loadNext(accessToken: String) async throws -> TrainingNextResponse
    func loadProgress(accessToken: String) async throws -> TrainingProgressResponse
    func enroll(accessToken: String, sessionsPerWeek: Int, equipment: String) async throws -> TrainingProgramResponse
    func logSet(accessToken: String, request: TrainingSetLogRequest) async throws -> TrainingSavedSet
    func correctSet(accessToken: String, request: TrainingSetCorrectionRequest) async throws -> TrainingSavedSet
    func undoSet(accessToken: String, request: TrainingSetUndoRequest) async throws -> TrainingSavedSet
    func applyAction(accessToken: String, request: TrainingWorkoutActionRequest) async throws -> TrainingSession
    func recordFeedback(accessToken: String, request: TrainingFeedbackRequest) async throws -> TrainingFeedbackResponse
    func revoke(accessToken: String) async throws -> TrainingRevokeResponse
}

final class URLSessionTrainingService: TrainingServicing {
    private let urlSession: URLSession
    private let baseURL: URL

    init(urlSession: URLSession = .shared, baseURL: URL? = URL(string: Configuration.apiBaseURL)) {
        self.urlSession = urlSession
        self.baseURL = baseURL ?? URL(string: ProductRegistry.Hosts.api)!
    }

    func loadNext(accessToken: String) async throws -> TrainingNextResponse {
        try await send(path: "next", method: "GET", accessToken: accessToken)
    }

    func loadProgress(accessToken: String) async throws -> TrainingProgressResponse {
        try await send(path: "progress", method: "GET", accessToken: accessToken)
    }

    func enroll(
        accessToken: String,
        sessionsPerWeek: Int,
        equipment: String
    ) async throws -> TrainingProgramResponse {
        try await send(
            path: "enroll",
            method: "POST",
            accessToken: accessToken,
            body: EnrollmentRequest(sessionsPerWeek: sessionsPerWeek, equipment: equipment)
        )
    }

    func logSet(accessToken: String, request: TrainingSetLogRequest) async throws -> TrainingSavedSet {
        let response: TrainingSetLogResponse = try await send(
            path: "log-set",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
        guard response.sessionComplete != nil,
              let log = response.log,
              log.sessionId == request.sessionId,
              log.exerciseId == request.exerciseId,
              log.setNumber == request.setNumber,
              log.reps == request.reps,
              log.loadKg == request.loadKg,
              log.rir == request.rir
        else { throw TrainingServiceError.invalidResponse }
        return log
    }

    func undoSet(accessToken: String, request: TrainingSetUndoRequest) async throws -> TrainingSavedSet {
        let response: TrainingSetCorrectionResponse = try await send(
            path: "undo-set",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
        guard response.log.sessionId == request.sessionId,
              response.log.exerciseId == request.exerciseId,
              response.log.setNumber == request.setNumber,
              response.log.revision == request.expectedRevision + 1,
              response.log.corrections?.contains(where: { $0.id == request.undoId }) == true
        else { throw TrainingServiceError.invalidResponse }
        return response.log
    }

    func correctSet(
        accessToken: String,
        request: TrainingSetCorrectionRequest
    ) async throws -> TrainingSavedSet {
        let response: TrainingSetCorrectionResponse = try await send(
            path: "correct-set",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
        guard response.log.sessionId == request.sessionId,
              response.log.exerciseId == request.exerciseId,
              response.log.setNumber == request.setNumber,
              response.log.reps == request.reps,
              response.log.loadKg == request.loadKg,
              response.log.rir == request.rir,
              response.log.revision == request.expectedRevision + 1,
              response.log.corrections?.contains(where: { $0.id == request.correctionId }) == true
        else { throw TrainingServiceError.invalidResponse }
        return response.log
    }

    func applyAction(
        accessToken: String,
        request: TrainingWorkoutActionRequest
    ) async throws -> TrainingSession {
        let response: TrainingWorkoutActionResponse = try await send(
            path: "action",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
        guard response.session.id == request.sessionId,
              response.session.executionRevision == request.expectedRevision + 1,
              response.session.executionEvents?.contains(where: { $0.id == request.eventId }) == true
        else { throw TrainingServiceError.invalidResponse }
        return response.session
    }

    func recordFeedback(accessToken: String, request: TrainingFeedbackRequest) async throws -> TrainingFeedbackResponse {
        let response: TrainingFeedbackResponse = try await send(
            path: "feedback",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
        guard response.matches(request) else { throw TrainingServiceError.invalidResponse }
        return response
    }

    func revoke(accessToken: String) async throws -> TrainingRevokeResponse {
        try await send(path: "enroll", method: "DELETE", accessToken: accessToken)
    }

    func perform(_ request: CanvasClientRequest, accessToken: String) async throws -> CanvasCommandResponse {
        guard let url = URL(string: "\(TrainingAPIContract.rootPath)/canvas", relativeTo: baseURL)?.absoluteURL else {
            throw TrainingServiceError.invalidResponse
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: request.jsonObject())

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw TrainingServiceError.invalidResponse }
        if http.statusCode == 401 { throw TrainingServiceError.authenticationExpired }
        if http.statusCode == 429 {
            throw TrainingServiceError.rateLimited(
                retryAfterSeconds: Int(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
            )
        }
        guard http.statusCode == 200 || http.statusCode == 409 else {
            let payload = try? JSONDecoder().decode(TrainingErrorResponse.self, from: data)
            throw TrainingServiceError.server(code: payload?.error ?? "training_unavailable")
        }
        let decoded = try JSONDecoder().decode(CanvasCommandResponse.self, from: data)
        guard (decoded.version ?? 1) == TrainingAPIContract.version, decoded.readback.version == 1 else {
            throw TrainingServiceError.invalidResponse
        }
        return decoded
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        accessToken: String
    ) async throws -> Response {
        try await send(
            path: path,
            method: method,
            accessToken: accessToken,
            body: Optional<EmptyTrainingRequest>.none
        )
    }

    private func send<Response: Decodable, RequestBody: Encodable>(
        path: String,
        method: String,
        accessToken: String,
        body: RequestBody?
    ) async throws -> Response {
        guard let url = URL(string: "\(TrainingAPIContract.rootPath)/\(path)", relativeTo: baseURL)?.absoluteURL else {
            throw TrainingServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TrainingServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw TrainingServiceError.authenticationExpired }
            if http.statusCode == 429 {
                throw TrainingServiceError.rateLimited(
                    retryAfterSeconds: Int(http.value(forHTTPHeaderField: "Retry-After") ?? "60") ?? 60
                )
            }
            let payload = try? JSONDecoder().decode(TrainingErrorResponse.self, from: data)
            throw TrainingServiceError.server(code: payload?.error ?? "training_unavailable")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard (decoded as? VersionedTrainingResponse)?.version == TrainingAPIContract.version else {
            throw TrainingServiceError.invalidResponse
        }
        return decoded
    }
}

private protocol VersionedTrainingResponse {
    var version: Int { get }
}

extension TrainingNextResponse: VersionedTrainingResponse {}
extension TrainingProgressResponse: VersionedTrainingResponse {}
extension TrainingProgramResponse: VersionedTrainingResponse {}
extension TrainingRevokeResponse: VersionedTrainingResponse {}
extension TrainingFeedbackResponse: VersionedTrainingResponse {}

private struct EnrollmentRequest: Encodable {
    let adultConfirmed = true
    let safetyConfirmed = true
    let sessionsPerWeek: Int
    let equipment: String
}

private struct EmptyTrainingRequest: Encodable {}
private struct TrainingSetLogResponse: Decodable, VersionedTrainingResponse {
    let version: Int
    let log: TrainingSavedSet?
    let sessionComplete: Bool?
}
private struct TrainingSetCorrectionResponse: Decodable, VersionedTrainingResponse {
    let version: Int
    let log: TrainingSavedSet
}
private struct TrainingWorkoutActionResponse: Decodable, VersionedTrainingResponse {
    let version: Int
    let decision: String
    let session: TrainingSession
}
private struct TrainingErrorResponse: Decodable { let error: String }

struct TrainingPlanningInputs: Codable, Equatable, Sendable {
    var goal: String?
    var goalDate: String?
    var experience: String?
    var sessionsPerWeek: Int?
    var minutesPerSession: Int?
    var equipment: String?
    var excludedVariantIds: [String]?
    var limitations: [String]?
    var preferredVariantIds: [String]?
}

struct TrainingPlanStoredProposal: Decodable, Equatable, Sendable {
    struct Proposal: Decodable, Equatable, Sendable {
        struct Transition: Decodable, Equatable, Sendable {
            let staying: [String]
            let changing: [String]
            let why: String
            let expiring: [String]
        }
        struct Actor: Decodable, Equatable, Sendable {
            let kind: String
            let subject: String
        }
        let id: String
        let reason: String
        let actor: Actor
        let summary: [String]
        let assumptions: [String]
        let plan: CanvasPlan
        let transition: Transition?
    }
    let status: String
    let proposal: Proposal
}

struct TrainingPlanContext: Decodable {
    struct Revision: Decodable, Identifiable {
        var id: String { revisionId }
        let revisionId: String
        let reason: String
        let summary: [String]
    }
    struct Movement: Decodable, Identifiable {
        let id: String
        let name: String
    }
    struct Setup: Decodable {
        struct Program: Decodable {
            let plan: CanvasPlan
        }
        let programRevisionId: String?
        let delegated: Program?
    }
    let generation: Int
    let delegatedProgramming: Bool?
    let knownInputs: TrainingPlanningInputs?
    let currentSetup: Setup?
    let movements: [Movement]?
    let limitations: [String]?
    let pendingProposal: TrainingPlanStoredProposal?
    let history: [Revision]?
}

struct TrainingPlanProposalRequest: Encodable {
    struct Intent: Encodable {
        var kind: String
        var inputs: TrainingPlanningInputs?
        var adultConfirmed: Bool?
        var safetyConfirmed: Bool?
        var revisionId: String?
    }
    let requestId: String
    let expectedGeneration: Int
    let reason: String
    var intent: Intent?
    var utterance: String?
    var baseProposalId: String?
}

struct TrainingPlanProposalResponse: Decodable {
    let stored: TrainingPlanStoredProposal?
    let question: String?
}

struct TrainingPlanDecisionRequest: Encodable {
    let requestId: String
    let proposalId: String
    let decision: String
}

struct TrainingPlanDecisionResponse: Decodable {
    struct Receipt: Decodable {
        let proposalId: String
        let requestId: String
        let status: String
        let revisionId: String?
        let setup: TrainingPlanContext.Setup?
    }
    let receipt: Receipt
}

protocol DelegatedTrainingServicing {
    func planningContext(accessToken: String) async throws -> TrainingPlanContext
    func proposePlan(accessToken: String, request: TrainingPlanProposalRequest) async throws -> TrainingPlanProposalResponse
    func decidePlan(accessToken: String, request: TrainingPlanDecisionRequest) async throws -> TrainingPlanDecisionResponse
}

extension URLSessionTrainingService: DelegatedTrainingServicing {
    func planningContext(accessToken: String) async throws -> TrainingPlanContext {
        try await send(path: "program-proposals", method: "GET", accessToken: accessToken)
    }

    func proposePlan(
        accessToken: String, request: TrainingPlanProposalRequest
    ) async throws -> TrainingPlanProposalResponse {
        let response: TrainingPlanProposalResponse = try await send(
            path: "program-proposals", method: "POST", accessToken: accessToken, body: request
        )
        guard response.stored != nil || response.question != nil else { throw TrainingServiceError.invalidResponse }
        return response
    }

    func decidePlan(
        accessToken: String, request: TrainingPlanDecisionRequest
    ) async throws -> TrainingPlanDecisionResponse {
        let response: TrainingPlanDecisionResponse = try await send(
            path: "program-proposals", method: "PATCH", accessToken: accessToken, body: request
        )
        guard response.receipt.proposalId == request.proposalId,
              response.receipt.requestId == request.requestId,
              response.receipt.status == (request.decision == "apply" ? "applied" : "rejected"),
              request.decision != "apply" || (
                response.receipt.revisionId != nil &&
                response.receipt.setup?.programRevisionId == response.receipt.revisionId
              ) else { throw TrainingServiceError.invalidResponse }
        return response
    }
}
