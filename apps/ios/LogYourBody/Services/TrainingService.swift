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

enum TrainingRecoveryCopy {
    /// Matches `APPLIED_RECOVERY_NEXT_ACTION_PREFIX` in the training service.
    static let appliedPrefix = "Applied recovery trial:"

    static func appliedNextAction(_ explanation: String?) -> String? {
        guard let explanation, explanation.hasPrefix(appliedPrefix) else { return nil }
        return explanation
    }
}

struct TrainingExercisePrescription: Codable, Equatable, Identifiable, Sendable {
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
    var setup: TrainingVariantSetup?

    struct RepRange: Codable, Equatable, Sendable {
        let min: Int
        let max: Int
    }
}

struct TrainingExerciseSubstitution: Codable, Equatable, Identifiable, Sendable {
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
    var setup: TrainingVariantSetup?
}

struct TrainingVariantSetup: Codable, Equatable, Sendable {
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
}

struct TrainingWorkoutEvent: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: String
    let createdAt: String
    let exerciseId: String?
    let replacementExerciseId: String?
    let minutes: Int?
}

struct TrainingSession: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let week: Int
    let slot: Int
    let pattern: String
    let title: String
    let exercises: [TrainingExercisePrescription]
    let safetyStop: Bool
    let explanation: String?
    let evidenceIds: [String]
    var loggedSets: [TrainingSavedSet]?
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
    var replacementExerciseId: String?

    static func equipmentUnavailable(_ exerciseId: String) -> Self {
        Self(kind: "equipment_unavailable", exerciseId: exerciseId, minutes: nil)
    }

    static func swap(_ exerciseId: String, with replacementId: String) -> Self {
        Self(kind: "swap", exerciseId: exerciseId, minutes: nil, replacementExerciseId: replacementId)
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
            if code == "delayed_active_workout" {
                return "Finish or end your current workout before applying this plan."
            }
            if code == "stale_context" {
                return "Your training changed. Refresh the draft before applying it."
            }
            return code == "not_found"
                ? "Training coaching is not enabled for this account yet."
                : "Training is temporarily unavailable. Please try again."
        }
    }
}

protocol TrainingServicing {
    func loadNext(accessToken: String) async throws -> TrainingNextResponse
    func loadProgress(accessToken: String) async throws -> TrainingProgressResponse
    func enroll(accessToken: String, sessionsPerWeek: Int, equipment: String) async throws -> TrainingProgramResponse
    func logSet(accessToken: String, request: TrainingSetLogRequest) async throws
    func correctSet(accessToken: String, request: TrainingSetCorrectionRequest) async throws -> TrainingSavedSet
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

    func logSet(accessToken: String, request: TrainingSetLogRequest) async throws {
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
        var baseRevision: String?
        var proposedDiff: [TrainingPlanDiff]?
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

enum TrainingNativeCardsPolicy {
    static let featureGate = "native_training_cards_v1"

    static func isEnabled(checkGate: (String) -> Bool) -> Bool {
        checkGate(TrainingCoachPolicy.featureGate) && checkGate(featureGate)
    }
}

/// A closed vocabulary of compiled, LYB-owned views. Text from chat cannot create a view or a write.
enum TrainingCardComponent: String, Codable, CaseIterable, Sendable {
    case mesoPlan = "MesoPlanCard"
    case planChange = "PlanChangeCard"
    case workoutSession = "WorkoutSessionCard"
    case exerciseSwap = "ExerciseSwapCard"
    case trainingFeedback = "TrainingFeedbackCard"
    case progressReview = "ProgressReviewCard"
}

enum TrainingCardActionName: String, Codable, CaseIterable, Sendable {
    case expand, adjust, apply, reject, logSet, correctSet, swap, feedback, review
}

enum TrainingCardContractError: Error, Equatable {
    case invalidSchema, invalidIdentity, unauthorized, staleReference, unsupportedAction
}

/// Properties are references to authenticated domain objects, never model-supplied prescriptions.
struct TrainingCardReference: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    let version: Int
    let component: TrainingCardComponent
    let objectId: String
    let revision: Int
    let exerciseId: String?

    init(component: TrainingCardComponent, objectId: String, revision: Int, exerciseId: String? = nil) {
        self.version = Self.schemaVersion
        self.component = component
        self.objectId = objectId
        self.revision = revision
        self.exerciseId = exerciseId
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, component, objectId, revision, exerciseId
    }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        component = try values.decode(TrainingCardComponent.self, forKey: .component)
        objectId = try values.decode(String.self, forKey: .objectId)
        revision = try values.decode(Int.self, forKey: .revision)
        exerciseId = try values.decodeIfPresent(String.self, forKey: .exerciseId)
        try validate()
    }

    func validate() throws {
        guard version == Self.schemaVersion else { throw TrainingCardContractError.invalidSchema }
        guard UUID(uuidString: objectId) != nil, revision >= 0 else {
            throw TrainingCardContractError.invalidIdentity
        }
        if component == .exerciseSwap {
            guard let exerciseId, Self.validExerciseId(exerciseId) else {
                throw TrainingCardContractError.invalidIdentity
            }
        } else if exerciseId != nil {
            throw TrainingCardContractError.invalidSchema
        }
    }

    static func validExerciseId(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")).contains($0)
        }
    }
}

struct TrainingCardAction: Codable, Equatable, Sendable {
    let reference: TrainingCardReference
    let name: TrainingCardActionName
    let alternativeId: String?

    init(reference: TrainingCardReference, name: TrainingCardActionName, alternativeId: String? = nil) {
        self.reference = reference
        self.name = name
        self.alternativeId = alternativeId
    }

    private enum CodingKeys: String, CodingKey, CaseIterable { case reference, name, alternativeId }

    init(from decoder: Decoder) throws {
        try rejectUnknownKeys(decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        reference = try values.decode(TrainingCardReference.self, forKey: .reference)
        name = try values.decode(TrainingCardActionName.self, forKey: .name)
        alternativeId = try values.decodeIfPresent(String.self, forKey: .alternativeId)
        try validate()
    }

    func validate() throws {
        try reference.validate()
        let allowed: [TrainingCardComponent: Set<TrainingCardActionName>] = [
            .mesoPlan: [.expand, .adjust],
            .planChange: [.expand, .adjust, .apply, .reject],
            .workoutSession: [.expand, .logSet, .correctSet],
            .exerciseSwap: [.swap],
            .trainingFeedback: [.feedback],
            .progressReview: [.review]
        ]
        guard allowed[reference.component]?.contains(name) == true else {
            throw TrainingCardContractError.unsupportedAction
        }
        if name == .swap {
            guard let alternativeId, TrainingCardReference.validExerciseId(alternativeId) else {
                throw TrainingCardContractError.invalidIdentity
            }
        } else if alternativeId != nil {
            throw TrainingCardContractError.invalidSchema
        }
    }
}

enum TrainingCardAdapter {
    /// Local admission supplements (and never replaces) the canonical API's owner/consent/CAS checks.
    static func authorize(
        _ action: TrainingCardAction, current: TrainingCardReference,
        ownsSession: Bool, canWrite: Bool, eligibleAlternativeIds: Set<String> = []
    ) throws {
        try action.validate()
        guard ownsSession else { throw TrainingCardContractError.unauthorized }
        guard action.reference == current else { throw TrainingCardContractError.staleReference }
        if ![.expand, .review].contains(action.name), !canWrite {
            throw TrainingCardContractError.unauthorized
        }
        if let alternativeId = action.alternativeId, !eligibleAlternativeIds.contains(alternativeId) {
            throw TrainingCardContractError.unsupportedAction
        }
    }

    static func workout(_ session: TrainingSession, component: TrainingCardComponent = .workoutSession) -> TrainingCardReference {
        TrainingCardReference(component: component, objectId: session.id, revision: session.executionRevision ?? 0)
    }
}

private struct TrainingCardKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func rejectUnknownKeys(_ decoder: Decoder, allowed: [String]) throws {
    let values = try decoder.container(keyedBy: TrainingCardKey.self)
    guard values.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
        throw TrainingCardContractError.invalidSchema
    }
}

struct TrainingPlanDiff: Decodable, Equatable, Sendable {
    let field: String
    let before: TrainingPlanDiffValue
    let after: TrainingPlanDiffValue
}

/// Engine diff values are inert text. They are never interpreted as actions, HTML or code.
indirect enum TrainingPlanDiffValue: Decodable, Equatable, Sendable {
    case null, text(String), number(Double), bool(Bool)
    case array([TrainingPlanDiffValue]), object([String: TrainingPlanDiffValue])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let text = try? value.decode(String.self) { self = .text(text) }
        else if let array = try? value.decode([Self].self) { self = .array(array) }
        else { self = .object(try value.decode([String: Self].self)) }
    }

    var displayText: String {
        switch self {
        case .null: "None"
        case .text(let text): text
        case .number(let number): number.formatted()
        case .bool(let bool): bool ? "Yes" : "No"
        case .array(let array): array.map(\.displayText).joined(separator: ", ")
        case .object(let object): object.keys.sorted().map { "\($0): \(object[$0]?.displayText ?? "")" }.joined(separator: "; ")
        }
    }
}
