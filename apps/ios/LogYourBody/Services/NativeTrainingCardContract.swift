import CryptoKit
import Foundation

/// Approved native training-card contract, schema version 1.
///
/// json-render is not a supported consumer. These values map to owned SwiftUI
/// views in `NativeTrainingCards.swift`. The catalog does not execute generated
/// code or accept transcript-only state.
enum NativeTrainingCardPolicy {
    static let featureGate = "native_training_cards_v1"
    static let schemaVersion = 1
    static let jsonRenderSupported = false
    static let renderConsumer = "swiftui-owned-views"

    static func isEnabled(checkGate: (String) -> Bool) -> Bool {
        checkGate(featureGate)
    }
}

enum NativeTrainingCardInteractionPolicy {
    /// Logging and workout navigation stay available while chat is busy or offline.
    static func loggingEnabled(chatBusy: Bool, offline: Bool) -> Bool {
        _ = (chatBusy, offline)
        return true
    }

    static func planWriteEnabled(pending: Bool) -> Bool {
        !pending
    }
}

enum NativeTrainingCardRejection: String, Equatable {
    case unknownComponent = "unknown_component"
    case invalidId = "invalid_id"
    case unauthorized
    case generatedCode = "generated_code"
    case unsupportedAction = "unsupported_action"
    case transcriptOnly = "transcript_only"
    case inventedScore = "invented_score"
    case invalidSchema = "invalid_schema"
}

struct ApprovedNativeTrainingAction: Equatable {
    let kind: String
    let operation: String
    let targetId: String
}

struct ApprovedNativeTrainingCard: Equatable {
    let component: String
    let objectId: String
    let revision: String
    let ownerSubject: String
    let actions: [ApprovedNativeTrainingAction]
}

struct NativeTrainingCardValidation: Equatable {
    let card: ApprovedNativeTrainingCard?
    let reason: NativeTrainingCardRejection?

    var ok: Bool { card != nil }
}

enum NativeTrainingCardDispatch {
    static func savedRevisionDecision(_ kind: String) -> String? {
        switch kind {
        case "apply_saved_revision": "apply"
        case "reject_saved_revision": "reject"
        case "adjust_saved_revision": "adjust"
        default: nil
        }
    }

    static func adjustmentUtteranceIsValid(_ utterance: String) -> Bool {
        guard !utterance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              utterance.count <= 240 else { return false }
        return NativeTrainingCardContract.scan(utterance) == nil
    }
}

enum NativeTrainingCardContract {
    static let components = [
        "MesoPlanCard", "PlanChangeCard", "WorkoutSessionCard",
        "ExerciseSwapCard", "TrainingFeedbackCard", "ProgressReviewCard"
    ]

    static func validate(_ input: Any, ownerSubject: String) -> NativeTrainingCardValidation {
        if let scanned = scan(input) { return fail(scanned) }
        guard ownerAllowed(ownerSubject), let record = dictionary(input),
              intValue(record["schemaVersion"]) == NativeTrainingCardPolicy.schemaVersion else {
            return fail(.invalidSchema)
        }
        guard let component = record["component"] as? String, components.contains(component) else {
            return fail(.unknownComponent)
        }
        guard let objectId = record["objectId"] as? String, isUUID(objectId),
              let revision = record["revision"] as? String, isRevision(revision) else {
            return fail(.invalidId)
        }
        guard record["ownerSubject"] as? String == ownerSubject, actorMatches(record, ownerSubject) else {
            return fail(.unauthorized)
        }
        guard let props = dictionary(record["props"]) else { return fail(.invalidSchema) }
        if let problem = propsValid(component: component, props: props, objectId: objectId) {
            return fail(problem)
        }
        guard let rawActions = anyArray(record["actions"]) else { return fail(.invalidSchema) }
        var actions: [ApprovedNativeTrainingAction] = []
        for value in rawActions {
            guard let action = dictionary(value), actorMatches(action, ownerSubject) else {
                return fail(.unauthorized)
            }
            switch validateAction(
                component: component, objectId: objectId, revision: revision, props: props, action: action
            ) {
            case .failure(let reason):
                return fail(reason)
            case .success(let approved):
                actions.append(approved)
            }
        }
        return NativeTrainingCardValidation(
            card: ApprovedNativeTrainingCard(
                component: component, objectId: objectId, revision: revision,
                ownerSubject: ownerSubject, actions: actions
            ),
            reason: nil
        )
    }

    static func approveTranscript(
        _ input: Any, ownerSubject: String, durable: [ApprovedNativeTrainingCard]
    ) -> NativeTrainingCardValidation {
        let validated = validate(input, ownerSubject: ownerSubject)
        guard let card = validated.card else { return validated }
        guard let match = durable.first(where: {
            $0.component == card.component && $0.objectId == card.objectId &&
                $0.revision == card.revision && $0.ownerSubject == ownerSubject
        }) else { return fail(.transcriptOnly) }
        let allowed = Set(match.actions.map(\.kind))
        if card.actions.contains(where: { !allowed.contains($0.kind) }) { return fail(.unauthorized) }
        return NativeTrainingCardValidation(card: match, reason: nil)
    }

    static func approveTranscriptText(
        _ text: String, ownerSubject: String, durable: [ApprovedNativeTrainingCard]
    ) -> NativeTrainingCardValidation? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return approveTranscript(json, ownerSubject: ownerSubject, durable: durable)
    }

    static func scan(_ value: Any) -> NativeTrainingCardRejection? {
        if let text = value as? String { return codeText(text) ? .generatedCode : nil }
        // [[String: Any]] does not bridge to [Any]. anyArray covers both shapes.
        if let items = anyArray(value) {
            for item in items {
                if let found = scan(item) { return found }
            }
            return nil
        }
        guard let record = dictionary(value) else { return nil }
        if record["root"] != nil && record["elements"] != nil { return .generatedCode }
        for (key, child) in record {
            let normalized = key.lowercased()
            if key.hasPrefix("$") || codeKeys.contains(normalized) { return .generatedCode }
            if scoreKeys.contains(normalized) { return .inventedScore }
            if let found = scan(child) { return found }
        }
        return nil
    }

    private static let codeKeys: Set<String> = [
        "code", "script", "html", "javascript", "eval", "function", "generatedcode", "sourcecode"
    ]
    private static let scoreKeys: Set<String> = ["fatiguescore", "readinessscore", "recoveryscore"]
    private static let readActions: [String: Set<String>] = [
        "MesoPlanCard": ["open_week"],
        "WorkoutSessionCard": ["open_session"],
        "ProgressReviewCard": ["refresh"]
    ]
    private static let writeActions: [String: Set<String>] = [
        "PlanChangeCard": ["apply_saved_revision", "adjust_saved_revision", "reject_saved_revision"],
        "WorkoutSessionCard": ["log_set", "correct_set"],
        "ExerciseSwapCard": ["select_swap"],
        "TrainingFeedbackCard": ["submit_feedback"]
    ]

    private static func validateAction(
        component: String, objectId: String, revision: String,
        props: [String: Any], action: [String: Any]
    ) -> Result<ApprovedNativeTrainingAction, NativeTrainingCardRejection> {
        guard let kind = action["kind"] as? String else { return .failure(.unsupportedAction) }
        if readActions[component]?.contains(kind) == true {
            if let operation = action["operation"] as? String, operation != "read" {
                return .failure(.unsupportedAction)
            }
            return .success(ApprovedNativeTrainingAction(kind: kind, operation: "read", targetId: objectId))
        }
        guard writeActions[component]?.contains(kind) == true else { return .failure(.unsupportedAction) }
        switch component {
        case "PlanChangeCard":
            guard action["operation"] as? String == "saved_revision",
                  action["proposalId"] as? String == objectId,
                  action["expectedRevision"] as? String == revision else { return .failure(.unauthorized) }
            if kind == "adjust_saved_revision", action["utterance"] != nil {
                guard let utterance = action["utterance"] as? String,
                      NativeTrainingCardDispatch.adjustmentUtteranceIsValid(utterance) else {
                    return .failure(.invalidSchema)
                }
            }
            return .success(ApprovedNativeTrainingAction(kind: kind, operation: "saved_revision", targetId: objectId))
        case "WorkoutSessionCard":
            guard action["operation"] as? String == "session_log",
                  action["sessionId"] as? String == objectId else { return .failure(.unauthorized) }
            guard let exerciseId = action["exerciseId"] as? String, isCatalogId(exerciseId),
                  records(props["exercises"]).contains(where: { $0["id"] as? String == exerciseId }) else {
                return .failure(.invalidId)
            }
            guard let setNumber = intValue(action["setNumber"]), setNumber >= 1 else {
                return .failure(.invalidSchema)
            }
            return .success(ApprovedNativeTrainingAction(kind: kind, operation: "session_log", targetId: objectId))
        case "ExerciseSwapCard":
            guard action["operation"] as? String == "exercise_swap",
                  action["sessionId"] as? String == props["sessionId"] as? String else {
                return .failure(.unauthorized)
            }
            guard let variantId = action["toVariantId"] as? String, isCatalogId(variantId),
                  records(props["alternatives"]).contains(where: { $0["id"] as? String == variantId }) else {
                return .failure(.invalidId)
            }
            let target = props["sessionId"] as? String ?? objectId
            return .success(ApprovedNativeTrainingAction(kind: kind, operation: "exercise_swap", targetId: target))
        default:
            guard action["operation"] as? String == "session_feedback",
                  action["sessionId"] as? String == props["sessionId"] as? String else {
                return .failure(.unauthorized)
            }
            if action["performance"] != nil {
                guard let performance = action["performance"] as? String,
                      ["up", "stable", "down"].contains(performance) else {
                    return .failure(.invalidSchema)
                }
            }
            let target = props["sessionId"] as? String ?? objectId
            return .success(ApprovedNativeTrainingAction(
                kind: kind, operation: "session_feedback", targetId: target
            ))
        }
    }

    private static func propsValid(
        component: String, props: [String: Any], objectId: String
    ) -> NativeTrainingCardRejection? {
        switch component {
        case "PlanChangeCard":
            return props["proposalId"] as? String == objectId ? nil : .invalidId
        case "ExerciseSwapCard", "WorkoutSessionCard", "TrainingFeedbackCard":
            return props["sessionId"] as? String == objectId ? nil : .invalidId
        case "ProgressReviewCard":
            guard let cited = props["citedResultIds"] as? [String], cited.allSatisfy(isUUID) else {
                return .invalidId
            }
            if props["proposal"] != nil && cited.isEmpty { return .invalidSchema }
            if let proposal = dictionary(props["proposal"]),
               proposal["before"] as? String == proposal["after"] as? String {
                return .invalidSchema
            }
            return nil
        case "MesoPlanCard":
            return anyArray(props["sessions"]) == nil ? .invalidSchema : nil
        default:
            return nil
        }
    }

    private static func fail(_ reason: NativeTrainingCardRejection) -> NativeTrainingCardValidation {
        NativeTrainingCardValidation(card: nil, reason: reason)
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func anyArray(_ value: Any?) -> [Any]? {
        if let items = value as? [Any] { return items }
        if let items = value as? [[String: Any]] { return items.map { $0 as Any } }
        if let items = value as? [String] { return items }
        return nil
    }

    private static func records(_ value: Any?) -> [[String: Any]] {
        if let items = value as? [[String: Any]] { return items }
        return (value as? [Any])?.compactMap { dictionary($0) } ?? []
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func actorMatches(_ record: [String: Any], _ ownerSubject: String) -> Bool {
        for key in ["ownerSubject", "actorSubject", "subject", "actor"] {
            if let value = record[key] as? String, value != ownerSubject { return false }
        }
        return true
    }

    private static func ownerAllowed(_ value: String) -> Bool {
        matches(value, #"^[A-Za-z0-9._:@+-]{1,200}$"#)
    }

    private static func isUUID(_ value: String) -> Bool {
        matches(value, #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#)
    }

    private static func isCatalogId(_ value: String) -> Bool {
        isUUID(value) || matches(value, #"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$"#)
    }

    private static func isRevision(_ value: String) -> Bool {
        isUUID(value) || matches(value, #"^(0|[1-9][0-9]{0,8})$"#)
    }

    private static func codeText(_ value: String) -> Bool {
        matches(value, #"(?i)javascript:|<script|\beval\s*\(|\bfunction\s*\("#)
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

enum NativeTrainingCardProjector {
    static func renderable(
        response: TrainingNextResponse?,
        plan: CanvasPlan?,
        planRevisionId: String?,
        ownerSubject: String,
        transcriptText: String
    ) -> [ApprovedNativeTrainingCard] {
        let durable = project(
            response: response, plan: plan, planRevisionId: planRevisionId, ownerSubject: ownerSubject
        )
        _ = NativeTrainingCardContract.approveTranscriptText(
            transcriptText, ownerSubject: ownerSubject, durable: durable
        )
        return durable
    }

    static func project(
        response: TrainingNextResponse?,
        plan: CanvasPlan?,
        planRevisionId: String?,
        ownerSubject: String
    ) -> [ApprovedNativeTrainingCard] {
        guard let response else { return [] }
        return [
            mesoCard(response: response, plan: plan, planRevisionId: planRevisionId, owner: ownerSubject),
            planChangeCard(response: response, owner: ownerSubject),
            workoutCard(response: response, owner: ownerSubject),
            feedbackCard(response: response, owner: ownerSubject),
            reviewCard(response: response, owner: ownerSubject)
        ].compactMap { $0 } + swapCards(response: response, owner: ownerSubject)
    }

    static func tradeoffs(
        current: TrainingExercisePrescription, alternative: TrainingExerciseSubstitution
    ) -> [String] {
        var lines = ["\(current.name) -> \(alternative.name)"]
        let muscles = Set(current.muscleContribution.keys).union(alternative.muscleContribution.keys)
        for muscle in muscles.sorted() {
            let before = current.muscleContribution[muscle] ?? 0
            let after = alternative.muscleContribution[muscle] ?? 0
            if before != after { lines.append("\(muscle) contribution: \(before) -> \(after)") }
        }
        if current.sets != alternative.sets {
            lines.append("sets: \(current.sets) -> \(alternative.sets)")
        }
        return lines
    }

    private static func mesoCard(
        response: TrainingNextResponse, plan: CanvasPlan?, planRevisionId: String?, owner: String
    ) -> ApprovedNativeTrainingCard? {
        let sessions: [Any]
        let objectId: String
        let revision: String
        if let plan, let planRevisionId, isIdentity(planRevisionId) {
            objectId = planRevisionId
            revision = String(plan.revision)
            sessions = plan.sessions.map { session in
                [
                    "id": session.id,
                    "title": session.title,
                    "exercises": session.exercises.map { exercise in
                        ["id": exercise.variantId, "name": exercise.name, "sets": exercise.sets] as [String: Any]
                    }
                ] as [String: Any]
            }
        } else if let session = response.session, isIdentity(session.id) {
            objectId = session.id
            revision = String(session.executionRevision ?? 0)
            sessions = [[
                "id": session.id,
                "title": session.title,
                "exercises": session.exercises.map { exercise in
                    ["id": exercise.id, "name": exercise.name, "sets": exercise.sets] as [String: Any]
                }
            ] as [String: Any]]
        } else {
            return nil
        }
        return approve(
            component: "MesoPlanCard", objectId: objectId, revision: revision, owner: owner,
            props: ["sessions": sessions],
            actions: [["kind": "open_week", "operation": "read"]]
        )
    }

    private static func planChangeCard(
        response: TrainingNextResponse, owner: String
    ) -> ApprovedNativeTrainingCard? {
        guard let stored = response.nextBlock, stored.status == "proposed", isIdentity(stored.proposal.id) else {
            return nil
        }
        let proposal = stored.proposal
        let revision = proposal.plan.revision
        var reasons = proposal.assumptions + proposal.summary
        if let transition = proposal.transition {
            reasons.append(transition.why)
            reasons.append(contentsOf: transition.changing)
        }
        let action = [
            "kind": "apply_saved_revision", "operation": "saved_revision",
            "proposalId": proposal.id, "expectedRevision": String(revision)
        ]
        let reject = [
            "kind": "reject_saved_revision", "operation": "saved_revision",
            "proposalId": proposal.id, "expectedRevision": String(revision)
        ]
        let adjust = [
            "kind": "adjust_saved_revision", "operation": "saved_revision",
            "proposalId": proposal.id, "expectedRevision": String(revision)
        ]
        return approve(
            component: "PlanChangeCard", objectId: proposal.id, revision: String(revision), owner: owner,
            props: [
                "proposalId": proposal.id,
                "reasons": reasons
            ],
            actions: [action, reject, adjust]
        )
    }

    private static func workoutCard(
        response: TrainingNextResponse, owner: String
    ) -> ApprovedNativeTrainingCard? {
        guard let session = response.session, isIdentity(session.id) else { return nil }
        let exercises: [[String: Any]] = session.exercises.compactMap { exercise in
            guard isIdentity(exercise.id) || catalogId(exercise.id) else { return nil }
            return ["id": exercise.id, "name": exercise.name]
        }
        guard let first = exercises.first, let exerciseId = first["id"] as? String else { return nil }
        let revision = String(session.executionRevision ?? 0)
        return approve(
            component: "WorkoutSessionCard", objectId: session.id, revision: revision, owner: owner,
            props: ["sessionId": session.id, "exercises": exercises],
            actions: [
                ["kind": "open_session", "operation": "read"],
                [
                    "kind": "log_set", "operation": "session_log", "sessionId": session.id,
                    "exerciseId": exerciseId, "setNumber": 1
                ]
            ]
        )
    }

    private static func swapCards(
        response: TrainingNextResponse, owner: String
    ) -> [ApprovedNativeTrainingCard] {
        guard let session = response.session, isIdentity(session.id) else { return [] }
        var alternatives: [[String: Any]] = []
        for exercise in session.exercises where catalogId(exercise.id) {
            for alternative in exercise.substitutions ?? [] where catalogId(alternative.id) {
                alternatives.append([
                    "id": alternative.id,
                    "name": alternative.name,
                    "tradeoffs": tradeoffs(current: exercise, alternative: alternative)
                ])
            }
        }
        guard !alternatives.isEmpty else { return [] }
        let card = approve(
            component: "ExerciseSwapCard", objectId: session.id,
            revision: String(session.executionRevision ?? 0), owner: owner,
            props: ["sessionId": session.id, "alternatives": alternatives],
            actions: alternatives.map { alternative in
                [
                    "kind": "select_swap", "operation": "exercise_swap",
                    "sessionId": session.id, "toVariantId": alternative["id"] as? String ?? ""
                ]
            }
        )
        return card.map { [$0] } ?? []
    }

    private static func feedbackCard(
        response: TrainingNextResponse, owner: String
    ) -> ApprovedNativeTrainingCard? {
        guard let session = response.session, isIdentity(session.id) else { return nil }
        let revision = String(session.executionRevision ?? 0)
        return approve(
            component: "TrainingFeedbackCard", objectId: session.id, revision: revision, owner: owner,
            props: ["sessionId": session.id],
            actions: [[
                "kind": "submit_feedback", "operation": "session_feedback",
                "sessionId": session.id, "performance": "stable"
            ]]
        )
    }

    private static func reviewCard(
        response: TrainingNextResponse, owner: String
    ) -> ApprovedNativeTrainingCard? {
        guard let session = response.session, isIdentity(session.id) else { return nil }
        let recorded = !(session.loggedSets ?? []).isEmpty
        var props: [String: Any] = ["citedResultIds": recorded ? [session.id] : []]
        if recorded, let decision = response.decision, decision.hasMeaningfulChange {
            props["proposal"] = [
                "before": decision.before,
                "after": decision.after,
                "rationale": decision.rationale
            ]
        }
        return approve(
            component: "ProgressReviewCard", objectId: session.id,
            revision: String(session.executionRevision ?? 0), owner: owner,
            props: props, actions: [["kind": "refresh", "operation": "read"]]
        )
    }

    private static func approve(
        component: String, objectId: String, revision: String, owner: String,
        props: [String: Any], actions: [[String: Any]]
    ) -> ApprovedNativeTrainingCard? {
        let envelope: [String: Any] = [
            "schemaVersion": NativeTrainingCardPolicy.schemaVersion,
            "component": component,
            "objectId": objectId,
            "revision": revision,
            "ownerSubject": owner,
            "props": props,
            "actions": actions
        ]
        return NativeTrainingCardContract.validate(envelope, ownerSubject: owner).card
    }

    private static func isIdentity(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func catalogId(_ value: String) -> Bool {
        isIdentity(value) || value.range(
            of: #"^[A-Za-z0-9][A-Za-z0-9_.:-]{0,63}$"#,
            options: .regularExpression
        ) != nil
    }
}

struct NativeTrainingCardSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let ownerSubject: String
    let response: TrainingNextResponse
    var plan: CanvasPlan?
    var planRevisionId: String?
}

enum NativeTrainingCardStoreError: Error {
    case unavailable
}

@MainActor
final class NativeTrainingCardStore {
    static let shared = NativeTrainingCardStore(
        rootURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NativeTrainingCards", isDirectory: true)
    )

    private let rootURL: URL

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func load(ownerSubject: String) -> NativeTrainingCardSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(ownerSubject)),
              let snapshot = try? JSONDecoder().decode(NativeTrainingCardSnapshot.self, from: data),
              snapshot.schemaVersion == NativeTrainingCardPolicy.schemaVersion,
              snapshot.ownerSubject == ownerSubject else { return nil }
        return snapshot
    }

    func save(_ snapshot: NativeTrainingCardSnapshot) throws {
        guard snapshot.schemaVersion == NativeTrainingCardPolicy.schemaVersion else {
            throw NativeTrainingCardStoreError.unavailable
        }
        let url = fileURL(snapshot.ownerSubject)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        var root = rootURL
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try root.setResourceValues(resources)
        try JSONEncoder().encode(snapshot).write(
            to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func remove(ownerSubject: String) {
        try? FileManager.default.removeItem(at: fileURL(ownerSubject))
    }

    private func fileURL(_ ownerSubject: String) -> URL {
        let digest = SHA256.hash(data: Data(ownerSubject.utf8)).map { String(format: "%02x", $0) }.joined()
        return rootURL.appendingPathComponent(digest + ".json")
    }
}
