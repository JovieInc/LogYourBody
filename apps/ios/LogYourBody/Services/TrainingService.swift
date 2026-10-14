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

struct TrainingFeedbackRequest: Encodable, Equatable, Sendable {
    let sessionId: String
    let soreness: Int
    let pump: Int
    let performance: String
    let jointPain: Int
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
            return code == "not_found"
                ? "Training coaching is not enabled for this account yet."
                : "Training is temporarily unavailable. Please try again."
        }
    }
}

protocol TrainingServicing {
    func loadNext(accessToken: String) async throws -> TrainingNextResponse
    func enroll(accessToken: String, sessionsPerWeek: Int, equipment: String) async throws -> TrainingProgramResponse
    func logSet(accessToken: String, request: TrainingSetLogRequest) async throws
    func correctSet(accessToken: String, request: TrainingSetCorrectionRequest) async throws -> TrainingSavedSet
    func applyAction(accessToken: String, request: TrainingWorkoutActionRequest) async throws -> TrainingSession
    func recordFeedback(accessToken: String, request: TrainingFeedbackRequest) async throws
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

    func recordFeedback(accessToken: String, request: TrainingFeedbackRequest) async throws {
        let _: EmptyTrainingResponse = try await send(
            path: "feedback",
            method: "POST",
            accessToken: accessToken,
            body: request
        )
    }

    func revoke(accessToken: String) async throws -> TrainingRevokeResponse {
        try await send(path: "enroll", method: "DELETE", accessToken: accessToken)
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
extension TrainingProgramResponse: VersionedTrainingResponse {}
extension TrainingRevokeResponse: VersionedTrainingResponse {}

private struct EnrollmentRequest: Encodable {
    let adultConfirmed = true
    let safetyConfirmed = true
    let sessionsPerWeek: Int
    let equipment: String
}

private struct EmptyTrainingRequest: Encodable {}
private struct EmptyTrainingResponse: Decodable, VersionedTrainingResponse { let version: Int }
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
