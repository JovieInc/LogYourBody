import CryptoKit
import Foundation

/// Closed schema for native training cards. json-render is not a supported
/// consumer; owned SwiftUI views render these values and do not evaluate code.
enum NativeTrainingCardContract {
    static let schemaVersion = 1
    static let runtimeConsumer = "owned-swiftui"

    static func parseList(_ value: Any) -> Result<[NativeTrainingCard], NativeTrainingCardRejection> {
        guard let items = value as? [Any] else {
            return parse(value).map { [$0] }
        }
        var cards: [NativeTrainingCard] = []
        for item in items {
            switch parse(item) {
            case .success(let card): cards.append(card)
            case .failure(let reason): return .failure(reason)
            }
        }
        return .success(cards)
    }

    static func parse(_ value: Any) -> Result<NativeTrainingCard, NativeTrainingCardRejection> {
        if let text = value as? String {
            return .failure(generatedCode(text) ? .generatedCode : .invalidCard)
        }
        if let reason = walk(value) { return .failure(reason) }
        guard let object = jsonObject(value) else { return .failure(.invalidCard) }
        guard Set(object.keys) == ["schemaVersion", "component", "object", "properties"] else {
            return .failure(.unknownField)
        }
        guard jsonInt(object["schemaVersion"]) == schemaVersion else { return .failure(.invalidCard) }
        guard let component = object["component"] as? String else { return .failure(.invalidCard) }
        guard components.contains(component) else { return .failure(.unknownComponent) }
        guard let body = jsonObject(object["object"]), let properties = jsonObject(object["properties"]) else {
            return .failure(.invalidCard)
        }
        switch component {
        case "MesoPlanCard":
            return meso(body, properties)
        case "PlanChangeCard":
            return planChange(body, properties)
        case "WorkoutSessionCard":
            return workout(body, properties)
        case "ExerciseSwapCard":
            return swap(body, properties)
        case "TrainingFeedbackCard":
            return feedback(body, properties)
        case "ProgressReviewCard":
            return review(body, properties)
        default:
            return .failure(.unknownComponent)
        }
    }

    static func admit(
        card: NativeTrainingCard,
        request: Any,
        ownerSubject: String
    ) -> Result<AdmittedNativeTrainingAction, NativeTrainingCardRejection> {
        if let reason = walk(request) { return .failure(reason) }
        guard let object = jsonObject(request) else { return .failure(.invalidPayload) }
        guard Set(object.keys) == ["schemaVersion", "action", "component", "object", "actorSubject", "payload"] else {
            return .failure(.unknownField)
        }
        guard jsonInt(object["schemaVersion"]) == schemaVersion else { return .failure(.invalidPayload) }
        guard let action = object["action"] as? String, let component = object["component"] as? String else {
            return .failure(.invalidPayload)
        }
        guard component == card.component else { return .failure(.objectMismatch) }
        guard actions(for: card.component).contains(action) else { return .failure(.unknownAction) }
        guard let actor = object["actorSubject"] as? String, !ownerSubject.isEmpty, actor == ownerSubject else {
            return .failure(.unauthorized)
        }
        guard let rawObject = jsonObject(object["object"]),
              let parsedObject = parseObject(rawObject, component: component),
              parsedObject == card.object else {
            return .failure(.objectMismatch)
        }
        guard let payload = jsonObject(object["payload"]) else { return .failure(.invalidPayload) }
        return admitPayload(action, payload: payload, card: card)
    }

    static func admit(
        card: NativeTrainingCard,
        action: String,
        ownerSubject: String,
        payload: [String: Any] = [:]
    ) -> Result<AdmittedNativeTrainingAction, NativeTrainingCardRejection> {
        admit(
            card: card,
            request: [
                "schemaVersion": schemaVersion,
                "action": action,
                "component": card.component,
                "object": card.object.jsonObject(),
                "actorSubject": ownerSubject,
                "payload": payload
            ],
            ownerSubject: ownerSubject
        )
    }

    private static let components: Set<String> = [
        "MesoPlanCard", "PlanChangeCard", "WorkoutSessionCard",
        "ExerciseSwapCard", "TrainingFeedbackCard", "ProgressReviewCard"
    ]

    private static func actions(for component: String) -> Set<String> {
        switch component {
        case "MesoPlanCard": ["apply_revision", "adjust_revision", "reject_revision", "expand_program"]
        case "PlanChangeCard": ["apply_revision", "adjust_revision", "reject_revision"]
        case "WorkoutSessionCard": ["log_set", "correct_set", "navigate_exercise", "expand_session"]
        case "ExerciseSwapCard": ["swap_exercise"]
        case "TrainingFeedbackCard": ["record_feedback"]
        case "ProgressReviewCard": ["propose_change"]
        default: []
        }
    }

    private static func admitPayload(
        _ action: String,
        payload: [String: Any],
        card: NativeTrainingCard
    ) -> Result<AdmittedNativeTrainingAction, NativeTrainingCardRejection> {
        switch action {
        case "apply_revision", "reject_revision":
            guard payload.isEmpty else { return .failure(.unknownField) }
            guard let proposalId = card.pendingProposalId else { return .failure(.invalidPayload) }
            return .success(.decideRevision(
                proposalId: proposalId,
                decision: action == "apply_revision" ? "apply" : "reject"
            ))
        case "adjust_revision":
            guard Set(payload.keys) == ["utterance"] else { return .failure(.unknownField) }
            guard let utterance = short(payload["utterance"], max: 500),
                  let proposalId = card.pendingProposalId else { return .failure(.invalidPayload) }
            return .success(.adjustRevision(baseProposalId: proposalId, utterance: utterance))
        case "expand_program":
            guard payload.isEmpty else { return .failure(.unknownField) }
            guard case .programRevision(let id, _, _) = card.object else { return .failure(.invalidPayload) }
            return .success(.expandProgram(programId: id))
        case "expand_session":
            guard payload.isEmpty else { return .failure(.unknownField) }
            guard case .session(let id, _) = card.object else { return .failure(.invalidPayload) }
            return .success(.expandSession(sessionId: id))
        case "navigate_exercise":
            guard Set(payload.keys) == ["exerciseIndex"] else { return .failure(.unknownField) }
            guard let index = jsonInt(payload["exerciseIndex"]),
                  case .workout(let workout) = card.properties,
                  case .session(let id, _) = card.object, (0..<workout.exercises.count).contains(index) else {
                return .failure(.invalidPayload)
            }
            return .success(.navigate(sessionId: id, exerciseIndex: index))
        case "log_set":
            guard Set(payload.keys) == ["exerciseId", "setNumber", "reps", "loadKg", "rir"] else {
                return .failure(.unknownField)
            }
            guard let log = readLog(payload, extra: []),
                  case .workout(let workout) = card.properties,
                  case .session(let id, _) = card.object,
                  let exercise = workout.exercises.first(where: { $0.id == log.exerciseId }),
                  log.setNumber == exercise.completedSets + 1, log.setNumber <= exercise.sets else {
                return .failure(.invalidPayload)
            }
            return .success(.logSet(TrainingSetLogRequest(
                sessionId: id, exerciseId: log.exerciseId, setNumber: log.setNumber,
                reps: log.reps, loadKg: log.loadKg, rir: log.rir
            )))
        case "correct_set":
            guard Set(payload.keys) == [
                "exerciseId", "setNumber", "reps", "loadKg", "rir", "correctionId", "expectedRevision"
            ] else { return .failure(.unknownField) }
            guard let log = readLog(payload, extra: ["correctionId", "expectedRevision"]),
                  let correctionId = payload["correctionId"] as? String, isUUID(correctionId),
                  let expected = jsonInt(payload["expectedRevision"]), expected >= 0,
                  case .workout(let workout) = card.properties,
                  case .session(let id, _) = card.object,
                  workout.exercises.contains(where: { $0.id == log.exerciseId }),
                  let prior = workout.previous.first(where: { $0.exerciseId == log.exerciseId }),
                  prior.revision == expected, prior.setNumber == log.setNumber else {
                return .failure(.invalidPayload)
            }
            return .success(.correctSet(TrainingSetCorrectionRequest(
                sessionId: id, exerciseId: log.exerciseId, setNumber: log.setNumber,
                reps: log.reps, loadKg: log.loadKg, rir: log.rir,
                correctionId: correctionId, expectedRevision: expected
            )))
        case "swap_exercise":
            guard Set(payload.keys) == ["toVariantId"] else { return .failure(.unknownField) }
            guard let variant = payload["toVariantId"] as? String, isCatalog(variant),
                  case .swap(let sessionId, let exerciseId, let alternatives) = card.properties,
                  alternatives.contains(where: { $0.id == variant }) else { return .failure(.invalidPayload) }
            return .success(.swapExercise(sessionId: sessionId, exerciseId: exerciseId, toVariantId: variant))
        case "record_feedback":
            guard Set(payload.keys) == ["statement"] else { return .failure(.unknownField) }
            guard let statement = short(payload["statement"], max: 280),
                  case .feedback(let sessionId, _) = card.properties,
                  case .feedback(let feedbackId, _) = card.object else { return .failure(.invalidPayload) }
            return .success(.recordFeedback(sessionId: sessionId, feedbackId: feedbackId, statement: statement))
        case "propose_change":
            guard payload.isEmpty else { return .failure(.unknownField) }
            guard case .review(let resultIds, _, let change) = card.properties, let change else {
                return .failure(.invalidPayload)
            }
            return .success(.proposeChange(
                intent: change.intent, evidenceIds: change.evidenceIds,
                recordedResultIds: resultIds, utterance: change.intent
            ))
        default:
            return .failure(.unknownAction)
        }
    }
}

enum NativeTrainingCardRejection: Equatable, Sendable {
    case unknownComponent
    case invalidId
    case unknownField
    case forbiddenField
    case generatedCode
    case invalidCard
    case unknownAction
    case unauthorized
    case objectMismatch
    case invalidPayload
}

enum NativeTrainingObject: Equatable, Sendable {
    case programRevision(id: String, revisionId: String, proposalId: String?)
    case proposal(id: String, revisionId: String?)
    case session(id: String, revisionId: String?)
    case exerciseSwap(id: String, revisionId: String?)
    case feedback(id: String, revisionId: String?)
    case progressReview(id: String, revisionId: String?)

    var id: String {
        switch self {
        case .programRevision(let id, _, _), .proposal(let id, _), .session(let id, _),
             .exerciseSwap(let id, _), .feedback(let id, _), .progressReview(let id, _):
            id
        }
    }

    fileprivate func jsonObject() -> [String: Any] {
        switch self {
        case .programRevision(let id, let revisionId, let proposalId):
            ["kind": "program_revision", "id": id, "revisionId": revisionId, "proposalId": jsonOptional(proposalId)]
        case .proposal(let id, let revisionId):
            ["kind": "proposal", "id": id, "revisionId": jsonOptional(revisionId)]
        case .session(let id, let revisionId):
            ["kind": "session", "id": id, "revisionId": jsonOptional(revisionId)]
        case .exerciseSwap(let id, let revisionId):
            ["kind": "exercise_swap", "id": id, "revisionId": jsonOptional(revisionId)]
        case .feedback(let id, let revisionId):
            ["kind": "feedback", "id": id, "revisionId": jsonOptional(revisionId)]
        case .progressReview(let id, let revisionId):
            ["kind": "progress_review", "id": id, "revisionId": jsonOptional(revisionId)]
        }
    }
}

struct NativeMesoPlanBody: Equatable, Sendable {
    let title: String
    let weekCount: Int
    let weeks: [NativePlanWeek]
    let diff: [NativePlanDiff]
    let reasons: [String]
    let evidenceIds: [String]
}

struct NativePlanChangeBody: Equatable, Sendable {
    let reason: String
    let diff: [NativePlanDiff]
    let reasons: [String]
    let evidenceIds: [String]
    let status: String
}

struct NativeWorkoutBody: Equatable, Sendable {
    let title: String
    let week: Int
    let slot: Int
    let exercises: [NativeWorkoutExercise]
    let previous: [NativePreviousSet]
}

enum NativeTrainingCardProperties: Equatable, Sendable {
    case mesoPlan(NativeMesoPlanBody)
    case planChange(NativePlanChangeBody)
    case workout(NativeWorkoutBody)
    case swap(sessionId: String, exerciseId: String, alternatives: [NativeSwapAlternative])
    case feedback(sessionId: String, prompt: String)
    case review(
        recordedResultIds: [String], citations: [NativeReviewCitation], proposedChange: NativeProposedChange?
    )
}

struct NativeTrainingCard: Equatable, Sendable {
    let component: String
    let object: NativeTrainingObject
    let properties: NativeTrainingCardProperties

    var identity: String { "\(component):\(object.id)" }
    var pendingProposalId: String? {
        switch (component, object, properties) {
        case ("PlanChangeCard", .proposal(let id, _), .planChange(let change)) where change.status == "pending":
            id
        case ("MesoPlanCard", .programRevision(_, _, let proposalId), _):
            proposalId
        default:
            nil
        }
    }

    fileprivate func jsonObject() -> [String: Any] {
        [
            "schemaVersion": NativeTrainingCardContract.schemaVersion,
            "component": component,
            "object": object.jsonObject(),
            "properties": properties.jsonObject()
        ]
    }
}

struct NativePlanDiff: Equatable, Sendable {
    let label: String
    let from: String
    let to: String
}

struct NativePlanWeek: Equatable, Sendable {
    let week: Int
    let sessions: [NativePlanSession]
}

struct NativePlanSession: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let slot: Int
}

struct NativeWorkoutExercise: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let setup: String
    let sets: Int
    let repMin: Int
    let repMax: Int
    let targetReps: Int
    let targetRir: Int
    let targetLoadKg: Double?
    let completedSets: Int
}

struct NativePreviousSet: Equatable, Sendable {
    let exerciseId: String
    let setNumber: Int
    let reps: Int
    let loadKg: Double?
    let rir: Int
    let revision: Int?
}

struct NativeSwapAlternative: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let tradeoff: String
}

struct NativeReviewCitation: Equatable, Sendable, Identifiable {
    var id: String { resultId }
    let resultId: String
    let statement: String
}

struct NativeProposedChange: Equatable, Sendable {
    let intent: String
    let evidenceIds: [String]
}

enum AdmittedNativeTrainingAction: Equatable, Sendable {
    case decideRevision(proposalId: String, decision: String)
    case adjustRevision(baseProposalId: String, utterance: String)
    case proposeChange(intent: String, evidenceIds: [String], recordedResultIds: [String], utterance: String)
    case logSet(TrainingSetLogRequest)
    case correctSet(TrainingSetCorrectionRequest)
    case swapExercise(sessionId: String, exerciseId: String, toVariantId: String)
    case recordFeedback(sessionId: String, feedbackId: String, statement: String)
    case navigate(sessionId: String, exerciseIndex: Int)
    case expandSession(sessionId: String)
    case expandProgram(programId: String)
}

enum NativeTrainingCardPhase: Equatable, Sendable {
    case ready(receipt: String?)
    case loading
    case pending(String)
    case offline(String)
    case failed(String)
}

enum NativeTrainingCardProjection {
    static func cards(session: TrainingSession?, proposal: TrainingPlanStoredProposal?) -> [NativeTrainingCard] {
        [workout(from: session), planChange(from: proposal)].compactMap { $0 } + swaps(from: session)
    }

    static func workout(from session: TrainingSession?) -> NativeTrainingCard? {
        guard let session else { return nil }
        let logs = session.loggedSets ?? []
        let exercises: [[String: Any]] = session.exercises.map { exercise in
            let completed = logs.filter { $0.exerciseId == exercise.id }.count
            let setup = exercise.loadInstruction?.trimmingCharacters(in: .whitespacesAndNewlines)
            return [
                "id": exercise.id,
                "name": exercise.name,
                "setup": (setup?.isEmpty == false ? setup! : "Use the prescribed setup for \(exercise.name)."),
                "sets": exercise.sets,
                "repRange": ["min": exercise.repRange.min, "max": exercise.repRange.max],
                "targetReps": exercise.targetReps,
                "targetRir": exercise.targetRir,
                "targetLoadKg": jsonOptional(exercise.targetLoadKg),
                "completedSets": min(completed, exercise.sets)
            ]
        }
        let previous: [[String: Any]] = session.exercises.compactMap { exercise in
            guard let latest = logs.filter({ $0.exerciseId == exercise.id }).max(by: { $0.setNumber < $1.setNumber })
            else { return nil }
            return [
                "exerciseId": exercise.id,
                "setNumber": latest.setNumber,
                "reps": latest.reps,
                "loadKg": jsonOptional(latest.loadKg),
                "rir": latest.rir,
                "revision": jsonOptional(latest.revision)
            ]
        }
        return NativeTrainingCardContract.parse([
            "schemaVersion": NativeTrainingCardContract.schemaVersion,
            "component": "WorkoutSessionCard",
            "object": ["kind": "session", "id": session.id, "revisionId": NSNull()],
            "properties": [
                "title": session.title, "week": session.week, "slot": session.slot,
                "exercises": exercises, "previous": previous
            ]
        ]).value
    }

    static func planChange(from stored: TrainingPlanStoredProposal?) -> NativeTrainingCard? {
        guard let stored else { return nil }
        let status: String
        switch stored.status {
        case "applied": status = "applied"
        case "rejected": status = "rejected"
        case "proposed", "pending": status = "pending"
        default: return nil
        }
        let reason = stored.proposal.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let changing = stored.proposal.transition?.changing ?? []
        let diff: [[String: String]] = changing.compactMap { item in
            let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count <= 120 else { return nil }
            return ["label": "Change", "from": "", "to": text]
        }
        let reasons = stored.proposal.summary.compactMap { item -> String? in
            let text = item.trimmingCharacters(in: .whitespacesAndNewlines)
            return (1...160).contains(text.count) ? text : nil
        }
        return NativeTrainingCardContract.parse([
            "schemaVersion": NativeTrainingCardContract.schemaVersion,
            "component": "PlanChangeCard",
            "object": ["kind": "proposal", "id": stored.proposal.id, "revisionId": NSNull()],
            "properties": [
                "reason": reason.isEmpty ? "Review this saved change before it starts." : reason,
                "diff": diff,
                "reasons": reasons,
                "evidenceIds": [],
                "status": status
            ]
        ]).value
    }

    static func swaps(from session: TrainingSession?) -> [NativeTrainingCard] {
        guard let session, isUUID(session.id) else { return [] }
        return session.exercises.compactMap { exercise in
            guard isCatalog(exercise.id) else { return nil }
            let alternatives: [[String: String]] = (exercise.substitutions ?? []).compactMap { substitution in
                guard isCatalog(substitution.id) else { return nil }
                let name = substitution.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let tradeoff = swapTradeoff(substitution)
                guard (1...80).contains(name.count), (1...160).contains(tradeoff.count) else { return nil }
                return ["id": substitution.id, "name": name, "tradeoff": tradeoff]
            }
            guard (1...6).contains(alternatives.count) else { return nil }
            return NativeTrainingCardContract.parse([
                "schemaVersion": NativeTrainingCardContract.schemaVersion,
                "component": "ExerciseSwapCard",
                "object": [
                    "kind": "exercise_swap",
                    "id": stableTrainingCardUuid([session.id, exercise.id, "eligible-swap"]),
                    "revisionId": NSNull()
                ],
                "properties": [
                    "sessionId": session.id,
                    "exerciseId": exercise.id,
                    "alternatives": Array(alternatives.prefix(6))
                ]
            ]).value
        }
    }
}

private func swapTradeoff(_ substitution: TrainingExerciseSubstitution) -> String {
    if let instruction = substitution.loadInstruction?.trimmingCharacters(in: .whitespacesAndNewlines),
       (1...160).contains(instruction.count), !generatedCode(instruction) {
        return instruction
    }
    let text = "Eligible \(substitution.primaryMuscle) alternative. This session keeps its sets and reps."
    return text.count <= 160 ? text : "Eligible alternative for this session."
}

private func stableTrainingCardUuid(_ parts: [String]) -> String {
    let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{0}").utf8))
    var hex = ""
    for byte in digest.prefix(16) {
        hex += String(format: "%02x", byte)
    }
    var chars = Array(hex)
    chars[12] = Character("5")
    let nibble = Int(String(chars[16]), radix: 16) ?? 0
    let variant = String((nibble & 0x3) | 0x8, radix: 16)
    chars[16] = Array(variant)[0]
    let value = String(chars)
    return "\(value.prefix(8))-\(value.dropFirst(8).prefix(4))-\(value.dropFirst(12).prefix(4))-\(value.dropFirst(16).prefix(4))-\(value.dropFirst(20))"
}

struct NativeTrainingCardRecord: Equatable {
    var cards: [NativeTrainingCard] = []
    var exerciseIndexes: [String: Int] = [:]
    var sessions: [String: TrainingSession] = [:]
}

@MainActor
final class NativeTrainingCardShelf {
    static let shared = NativeTrainingCardShelf(
        rootURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NativeTrainingCards", isDirectory: true)
    )

    private let rootURL: URL
    init(rootURL: URL) { self.rootURL = rootURL }

    func load(ownerId: String) -> NativeTrainingCardRecord {
        guard let data = try? Data(contentsOf: fileURL(ownerId)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              jsonInt(object["schemaVersion"]) == 1,
              let cardValues = object["cards"] as? [Any] else { return NativeTrainingCardRecord() }
        let cards = cardValues.compactMap { NativeTrainingCardContract.parse($0).value }
        var record = NativeTrainingCardRecord(cards: cards)
        if let indexes = object["exerciseIndexes"] as? [String: Any] {
            for (key, value) in indexes {
                guard let index = jsonInt(value),
                      let card = cards.first(where: { $0.object.id == key }),
                      case .workout(let workout) = card.properties,
                      (0..<workout.exercises.count).contains(index) else { continue }
                record.exerciseIndexes[key] = index
            }
        }
        if let sessions = object["sessions"] as? [String: Any] {
            for (key, value) in sessions {
                guard cards.contains(where: { $0.object.id == key }),
                      let sessionObject = jsonObject(value),
                      let data = try? JSONSerialization.data(withJSONObject: sessionObject),
                      let session = try? JSONDecoder().decode(TrainingSession.self, from: data) else { continue }
                record.sessions[key] = session
            }
        }
        return record
    }

    func save(ownerId: String, record: NativeTrainingCardRecord) throws {
        let sessions = try record.sessions.mapValues { session -> [String: Any] in
            let data = try JSONEncoder().encode(session)
            let object = try JSONSerialization.jsonObject(with: data)
            return jsonObject(object) ?? [:]
        }
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "cards": record.cards.map { $0.jsonObject() },
            "exerciseIndexes": record.exerciseIndexes,
            "sessions": sessions
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try FileManager.default.createDirectory(
            at: rootURL, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var excluded = rootURL
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try excluded.setResourceValues(resources)
        try data.write(to: fileURL(ownerId), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func purge(ownerId: String) {
        try? FileManager.default.removeItem(at: fileURL(ownerId))
    }

    private func fileURL(_ ownerId: String) -> URL {
        let digest = SHA256.hash(data: Data(ownerId.utf8)).map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(digest + ".json")
    }
}

private extension Result where Success == NativeTrainingCard {
    var value: NativeTrainingCard? {
        if case .success(let card) = self { return card }
        return nil
    }
}

private struct ParsedLog {
    let exerciseId: String
    let setNumber: Int
    let reps: Int
    let loadKg: Double?
    let rir: Int
}

private extension NativeTrainingCardContract {
    static func meso(
        _ body: [String: Any], _ properties: [String: Any]
    ) -> Result<NativeTrainingCard, NativeTrainingCardRejection> {
        guard Set(body.keys) == ["kind", "id", "revisionId", "proposalId"], body["kind"] as? String == "program_revision",
              let id = uuid(body["id"]), let revision = uuid(body["revisionId"]),
              let proposalId = optionalUUID(body["proposalId"]) else { return .failure(.invalidId) }
        guard Set(properties.keys) == ["title", "weekCount", "compact", "weeks", "diff", "reasons", "evidenceIds"],
              jsonBool(properties["compact"]) == true,
              let title = short(properties["title"], max: 80),
              let weekCount = jsonInt(properties["weekCount"]), (1...8).contains(weekCount),
              let weeks = weeks(properties["weeks"]), weeks.count == weekCount,
              let diff = diffs(properties["diff"]), let reasons = texts(properties["reasons"], max: 160, limit: 8),
              let evidence = evidenceIds(properties["evidenceIds"]) else { return .failure(.invalidCard) }
        return .success(NativeTrainingCard(
            component: "MesoPlanCard",
            object: .programRevision(id: id, revisionId: revision, proposalId: proposalId),
            properties: .mesoPlan(NativeMesoPlanBody(
                title: title, weekCount: weekCount, weeks: weeks, diff: diff, reasons: reasons, evidenceIds: evidence
            ))
        ))
    }

    static func planChange(
        _ body: [String: Any], _ properties: [String: Any]
    ) -> Result<NativeTrainingCard, NativeTrainingCardRejection> {
        guard let object = reference(body, kind: "proposal") else { return .failure(.invalidId) }
        guard Set(properties.keys) == ["reason", "diff", "reasons", "evidenceIds", "status"],
              let reason = short(properties["reason"], max: 500),
              let diff = diffs(properties["diff"]), let reasons = texts(properties["reasons"], max: 160, limit: 8),
              let evidence = evidenceIds(properties["evidenceIds"]),
              let status = properties["status"] as? String, ["pending", "applied", "rejected"].contains(status) else {
            return .failure(.invalidCard)
        }
        return .success(NativeTrainingCard(
            component: "PlanChangeCard", object: object,
            properties: .planChange(NativePlanChangeBody(
                reason: reason, diff: diff, reasons: reasons, evidenceIds: evidence, status: status
            ))
        ))
    }

    static func workout(
        _ body: [String: Any], _ properties: [String: Any]
    ) -> Result<NativeTrainingCard, NativeTrainingCardRejection> {
        guard let object = reference(body, kind: "session") else { return .failure(.invalidId) }
        guard Set(properties.keys) == ["title", "week", "slot", "exercises", "previous"],
              let title = short(properties["title"], max: 80),
              let week = jsonInt(properties["week"]), (1...52).contains(week),
              let slot = jsonInt(properties["slot"]), (0...6).contains(slot),
              let exercises = exercises(properties["exercises"]),
              let previous = previousSets(properties["previous"]) else { return .failure(.invalidCard) }
        return .success(NativeTrainingCard(
            component: "WorkoutSessionCard", object: object,
            properties: .workout(NativeWorkoutBody(
                title: title, week: week, slot: slot, exercises: exercises, previous: previous
            ))
        ))
    }

    static func swap(
        _ body: [String: Any], _ properties: [String: Any]
    ) -> Result<NativeTrainingCard, NativeTrainingCardRejection> {
        guard let object = reference(body, kind: "exercise_swap") else { return .failure(.invalidId) }
        guard Set(properties.keys) == ["sessionId", "exerciseId", "alternatives"],
              let sessionId = uuid(properties["sessionId"]),
              let exerciseId = properties["exerciseId"] as? String, isCatalog(exerciseId),
              let alternatives = alternatives(properties["alternatives"]) else { return .failure(.invalidCard) }
        return .success(NativeTrainingCard(
            component: "ExerciseSwapCard", object: object,
            properties: .swap(sessionId: sessionId, exerciseId: exerciseId, alternatives: alternatives)
        ))
    }

    static func feedback(
        _ body: [String: Any], _ properties: [String: Any]
    ) -> Result<NativeTrainingCard, NativeTrainingCardRejection> {
        guard let object = reference(body, kind: "feedback") else { return .failure(.invalidId) }
        guard Set(properties.keys) == ["sessionId", "prompt"],
              let sessionId = uuid(properties["sessionId"]),
              let prompt = short(properties["prompt"], max: 120) else { return .failure(.invalidCard) }
        return .success(NativeTrainingCard(
            component: "TrainingFeedbackCard", object: object,
            properties: .feedback(sessionId: sessionId, prompt: prompt)
        ))
    }

    static func review(
        _ body: [String: Any], _ properties: [String: Any]
    ) -> Result<NativeTrainingCard, NativeTrainingCardRejection> {
        guard let object = reference(body, kind: "progress_review") else { return .failure(.invalidId) }
        guard Set(properties.keys) == ["recordedResultIds", "citations", "proposedChange"],
              let resultIds = uuidList(properties["recordedResultIds"], min: 1, max: 12),
              let citations = citations(properties["citations"]),
              citations.allSatisfy({ resultIds.contains($0.resultId) }),
              let change = proposedChange(properties["proposedChange"]) else { return .failure(.invalidCard) }
        return .success(NativeTrainingCard(
            component: "ProgressReviewCard", object: object,
            properties: .review(recordedResultIds: resultIds, citations: citations, proposedChange: change)
        ))
    }

    static func reference(_ body: [String: Any], kind: String) -> NativeTrainingObject? {
        guard Set(body.keys) == ["kind", "id", "revisionId"], body["kind"] as? String == kind,
              let id = uuid(body["id"]), let revision = optionalUUID(body["revisionId"]) else { return nil }
        switch kind {
        case "proposal": return .proposal(id: id, revisionId: revision)
        case "session": return .session(id: id, revisionId: revision)
        case "exercise_swap": return .exerciseSwap(id: id, revisionId: revision)
        case "feedback": return .feedback(id: id, revisionId: revision)
        case "progress_review": return .progressReview(id: id, revisionId: revision)
        default: return nil
        }
    }

    static func parseObject(_ body: [String: Any], component: String) -> NativeTrainingObject? {
        if component == "MesoPlanCard" {
            guard Set(body.keys) == ["kind", "id", "revisionId", "proposalId"],
                  body["kind"] as? String == "program_revision",
                  let id = uuid(body["id"]), let revision = uuid(body["revisionId"]),
                  let proposal = optionalUUID(body["proposalId"]) else { return nil }
            return .programRevision(id: id, revisionId: revision, proposalId: proposal)
        }
        let kind: String
        switch component {
        case "PlanChangeCard": kind = "proposal"
        case "WorkoutSessionCard": kind = "session"
        case "ExerciseSwapCard": kind = "exercise_swap"
        case "TrainingFeedbackCard": kind = "feedback"
        case "ProgressReviewCard": kind = "progress_review"
        default: return nil
        }
        return reference(body, kind: kind)
    }
}

private extension NativeTrainingCardProperties {
    func jsonObject() -> [String: Any] {
        switch self {
        case .mesoPlan(let plan):
            let title = plan.title
            let weekCount = plan.weekCount
            let weeks = plan.weeks
            let diff = plan.diff
            let reasons = plan.reasons
            let evidenceIds = plan.evidenceIds
            [
                "title": title, "weekCount": weekCount, "compact": true,
                "weeks": weeks.map { week in
                    [
                        "week": week.week,
                        "sessions": week.sessions.map { ["id": $0.id, "title": $0.title, "slot": $0.slot] }
                    ]
                },
                "diff": diff.map { ["label": $0.label, "from": $0.from, "to": $0.to] },
                "reasons": reasons, "evidenceIds": evidenceIds
            ]
        case .planChange(let change):
            let reason = change.reason
            let diff = change.diff
            let reasons = change.reasons
            let evidenceIds = change.evidenceIds
            let status = change.status
            [
                "reason": reason,
                "diff": diff.map { ["label": $0.label, "from": $0.from, "to": $0.to] },
                "reasons": reasons, "evidenceIds": evidenceIds, "status": status
            ]
        case .workout(let workout):
            let title = workout.title
            let week = workout.week
            let slot = workout.slot
            let exercises = workout.exercises
            let previous = workout.previous
            [
                "title": title, "week": week, "slot": slot,
                "exercises": exercises.map { exercise in
                    [
                        "id": exercise.id, "name": exercise.name, "setup": exercise.setup, "sets": exercise.sets,
                        "repRange": ["min": exercise.repMin, "max": exercise.repMax],
                        "targetReps": exercise.targetReps, "targetRir": exercise.targetRir,
                        "targetLoadKg": jsonOptional(exercise.targetLoadKg), "completedSets": exercise.completedSets
                    ]
                },
                "previous": previous.map { prior in
                    [
                        "exerciseId": prior.exerciseId, "setNumber": prior.setNumber, "reps": prior.reps,
                        "loadKg": jsonOptional(prior.loadKg), "rir": prior.rir, "revision": jsonOptional(prior.revision)
                    ]
                }
            ]
        case .swap(let sessionId, let exerciseId, let alternatives):
            [
                "sessionId": sessionId, "exerciseId": exerciseId,
                "alternatives": alternatives.map { ["id": $0.id, "name": $0.name, "tradeoff": $0.tradeoff] }
            ]
        case .feedback(let sessionId, let prompt):
            ["sessionId": sessionId, "prompt": prompt]
        case .review(let resultIds, let citations, let change):
            [
                "recordedResultIds": resultIds,
                "citations": citations.map { ["resultId": $0.resultId, "statement": $0.statement] },
                "proposedChange": change.map {
                    ["intent": $0.intent, "evidenceIds": $0.evidenceIds] as Any
                } ?? NSNull()
            ]
        }
    }
}

private func readLog(_ payload: [String: Any], extra: Set<String>) -> ParsedLog? {
    guard Set(payload.keys) == ["exerciseId", "setNumber", "reps", "loadKg", "rir"].union(extra),
          let exerciseId = payload["exerciseId"] as? String, isCatalog(exerciseId),
          let setNumber = jsonInt(payload["setNumber"]), (1...20).contains(setNumber),
          let reps = jsonInt(payload["reps"]), (1...50).contains(reps),
          let load = optionalLoad(payload["loadKg"]),
          let rir = jsonInt(payload["rir"]), (0...6).contains(rir) else { return nil }
    return ParsedLog(exerciseId: exerciseId, setNumber: setNumber, reps: reps, loadKg: load, rir: rir)
}

private func weeks(_ value: Any?) -> [NativePlanWeek]? {
    guard let rows = value as? [Any], (1...8).contains(rows.count) else { return nil }
    var weeks: [NativePlanWeek] = []
    for row in rows {
        guard let object = jsonObject(row), Set(object.keys) == ["week", "sessions"],
              let week = jsonInt(object["week"]), (1...8).contains(week),
              let sessions = object["sessions"] as? [Any], (1...6).contains(sessions.count) else { return nil }
        var parsed: [NativePlanSession] = []
        for session in sessions {
            guard let item = jsonObject(session), Set(item.keys) == ["id", "title", "slot"],
                  let id = uuid(item["id"]), let title = short(item["title"], max: 80),
                  let slot = jsonInt(item["slot"]), (0...6).contains(slot) else { return nil }
            parsed.append(NativePlanSession(id: id, title: title, slot: slot))
        }
        weeks.append(NativePlanWeek(week: week, sessions: parsed))
    }
    return weeks
}

private func diffs(_ value: Any?) -> [NativePlanDiff]? {
    guard let rows = value as? [Any], rows.count <= 12 else { return nil }
    let parsed: [NativePlanDiff] = rows.compactMap { row in
        guard let object = jsonObject(row), Set(object.keys) == ["label", "from", "to"],
              let label = short(object["label"], max: 80),
              let from = object["from"] as? String, from.count <= 120,
              let to = object["to"] as? String, to.count <= 120 else { return nil }
        return NativePlanDiff(label: label, from: from, to: to)
    }
    return parsed.count == rows.count ? parsed : nil
}

private func texts(_ value: Any?, max: Int, limit: Int) -> [String]? {
    guard let rows = value as? [String], rows.count <= limit else { return nil }
    let parsed = rows.compactMap { short($0, max: max) }
    return parsed.count == rows.count ? parsed : nil
}

private func evidenceIds(_ value: Any?) -> [String]? {
    guard let rows = value as? [String], rows.count <= 12, rows.allSatisfy(isEvidence) else { return nil }
    return rows
}

private func exercises(_ value: Any?) -> [NativeWorkoutExercise]? {
    guard let rows = value as? [Any], (1...12).contains(rows.count) else { return nil }
    var exercises: [NativeWorkoutExercise] = []
    for row in rows {
        guard let object = jsonObject(row),
              Set(object.keys) == [
                "id", "name", "setup", "sets", "repRange", "targetReps", "targetRir", "targetLoadKg", "completedSets"
              ],
              let id = object["id"] as? String, isCatalog(id),
              let name = short(object["name"], max: 80), let setup = short(object["setup"], max: 200),
              let sets = jsonInt(object["sets"]), (1...10).contains(sets),
              let range = jsonObject(object["repRange"]), Set(range.keys) == ["min", "max"],
              let repMin = jsonInt(range["min"]), let repMax = jsonInt(range["max"]),
              (1...50).contains(repMin), (1...50).contains(repMax), repMin <= repMax,
              let targetReps = jsonInt(object["targetReps"]), (1...50).contains(targetReps),
              let targetRir = jsonInt(object["targetRir"]), (0...6).contains(targetRir),
              let load = optionalLoad(object["targetLoadKg"]),
              let completed = jsonInt(object["completedSets"]), (0...10).contains(completed) else { return nil }
        exercises.append(NativeWorkoutExercise(
            id: id, name: name, setup: setup, sets: sets, repMin: repMin, repMax: repMax,
            targetReps: targetReps, targetRir: targetRir, targetLoadKg: load, completedSets: completed
        ))
    }
    return exercises
}

private func previousSets(_ value: Any?) -> [NativePreviousSet]? {
    guard let rows = value as? [Any], rows.count <= 12 else { return nil }
    var sets: [NativePreviousSet] = []
    for row in rows {
        guard let object = jsonObject(row),
              Set(object.keys) == ["exerciseId", "setNumber", "reps", "loadKg", "rir", "revision"],
              let exerciseId = object["exerciseId"] as? String, isCatalog(exerciseId),
              let setNumber = jsonInt(object["setNumber"]), (1...20).contains(setNumber),
              let reps = jsonInt(object["reps"]), (1...50).contains(reps),
              let load = optionalLoad(object["loadKg"]),
              let rir = jsonInt(object["rir"]), (0...6).contains(rir),
              let revision = optionalInt(object["revision"]) else { return nil }
        sets.append(NativePreviousSet(
            exerciseId: exerciseId, setNumber: setNumber, reps: reps, loadKg: load, rir: rir, revision: revision
        ))
    }
    return sets
}

private func alternatives(_ value: Any?) -> [NativeSwapAlternative]? {
    guard let rows = value as? [Any], (1...6).contains(rows.count) else { return nil }
    var alternatives: [NativeSwapAlternative] = []
    for row in rows {
        guard let object = jsonObject(row), Set(object.keys) == ["id", "name", "tradeoff"],
              let id = object["id"] as? String, isCatalog(id),
              let name = short(object["name"], max: 80),
              let tradeoff = short(object["tradeoff"], max: 160) else { return nil }
        alternatives.append(NativeSwapAlternative(id: id, name: name, tradeoff: tradeoff))
    }
    return alternatives
}

private func citations(_ value: Any?) -> [NativeReviewCitation]? {
    guard let rows = value as? [Any], (1...8).contains(rows.count) else { return nil }
    var citations: [NativeReviewCitation] = []
    for row in rows {
        guard let object = jsonObject(row), Set(object.keys) == ["resultId", "statement"],
              let resultId = uuid(object["resultId"]),
              let statement = short(object["statement"], max: 200) else { return nil }
        citations.append(NativeReviewCitation(resultId: resultId, statement: statement))
    }
    return citations
}

private func proposedChange(_ value: Any?) -> NativeProposedChange?? {
    if value is NSNull { return .some(nil) }
    guard let object = jsonObject(value), Set(object.keys) == ["intent", "evidenceIds"],
          let intent = object["intent"] as? String,
          ["keep", "exclude", "prioritize", "schedule", "next_block"].contains(intent),
          let evidence = evidenceIds(object["evidenceIds"]), !evidence.isEmpty else { return nil }
    return .some(NativeProposedChange(intent: intent, evidenceIds: evidence))
}

private func uuidList(_ value: Any?, min: Int, max: Int) -> [String]? {
    guard let rows = value as? [String], (min...max).contains(rows.count), rows.allSatisfy(isUUID) else { return nil }
    return rows
}

private func walk(_ value: Any) -> NativeTrainingCardRejection? {
    if let text = value as? String { return generatedCode(text) ? .generatedCode : nil }
    if let rows = value as? [Any] {
        for row in rows {
            if let reason = walk(row) { return reason }
        }
        return nil
    }
    guard let object = jsonObject(value) else { return nil }
    for (key, child) in object {
        if forbiddenKey(key) { return .forbiddenField }
        if let reason = walk(child) { return reason }
    }
    return nil
}

private func forbiddenKey(_ key: String) -> Bool {
    ["code", "script", "eval", "javascript", "html", "function", "generatedcode", "swiftsource",
     "fatiguescore", "readinessscore"].contains(key.lowercased())
}

private func generatedCode(_ text: String) -> Bool {
    text.range(
        of: #"(?:function\s*\(|<script|javascript:|eval\s*\(|</|import\s+|export\s+|=>\s*\{|```)"#,
        options: [.regularExpression, .caseInsensitive]
    ) != nil
}

private func short(_ value: Any?, max: Int) -> String? {
    guard let text = value as? String else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...max).contains(trimmed.count), !generatedCode(trimmed) else { return nil }
    return trimmed
}

private func jsonObject(_ value: Any?) -> [String: Any]? {
    value as? [String: Any]
}

private func jsonOptional<T>(_ value: T?) -> Any {
    value.map { $0 as Any } ?? NSNull()
}

private func jsonInt(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let double = number.doubleValue
    guard double.rounded() == double, double >= Double(Int.min), double <= Double(Int.max) else { return nil }
    return number.intValue
}

private func jsonBool(_ value: Any?) -> Bool? {
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
    return number.boolValue
}

private func optionalInt(_ value: Any?) -> Int?? {
    if value is NSNull { return .some(nil) }
    guard let int = jsonInt(value), int >= 0 else { return nil }
    return .some(int)
}

private func optionalLoad(_ value: Any?) -> Double?? {
    if value is NSNull { return .some(nil) }
    guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let load = number.doubleValue
    guard load.isFinite, (0...500).contains(load) else { return nil }
    return .some(load)
}

private func optionalUUID(_ value: Any?) -> String?? {
    if value is NSNull { return .some(nil) }
    guard let text = value as? String, isUUID(text) else { return nil }
    return .some(text)
}

private func uuid(_ value: Any?) -> String? {
    guard let text = value as? String, isUUID(text) else { return nil }
    return text
}

private func isUUID(_ value: String) -> Bool {
    value.range(
        of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#,
        options: .regularExpression
    ) != nil
}

private func isCatalog(_ value: String) -> Bool {
    value.range(of: #"^[a-z0-9_]{1,64}$"#, options: .regularExpression) != nil
}

private func isEvidence(_ value: String) -> Bool {
    value.range(of: #"^k:[0-9a-f]{8}$"#, options: .regularExpression) != nil
}
