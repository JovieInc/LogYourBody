import Foundation

enum MesocycleCanvasPolicy {
    static let featureGate = "mesocycle_canvas_v1"

    static func isEnabled(checkGate: (String) -> Bool) -> Bool {
        checkGate(featureGate)
    }
}

struct CanvasExercise: Codable, Equatable, Identifiable {
    var instanceId: String
    var variantId: String
    var name: String
    var primaryMuscle: String
    var muscleContribution: [String: Double]
    var sets: Int
    var repRange: RepRange
    var targetReps: Int
    var targetRir: Int
    var priority: String
    var evidenceIds: [String]
    var id: String { instanceId }

    struct RepRange: Codable, Equatable {
        var min: Int
        var max: Int
    }
}

struct CanvasSession: Codable, Equatable, Identifiable {
    var id: String
    var period: String
    var title: String
    var exercises: [CanvasExercise]
}

struct CanvasDay: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var sessions: [CanvasSession]
}

struct CanvasGoal: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var role: String
    var weeklySets: Double
}

struct CanvasPlan: Codable, Equatable {
    var version: Int
    var policyVersion: String
    var weekCount: Int
    var currentWeek: Int
    var equipmentProfile: String
    var availableEquipment: [String]
    var goals: [CanvasGoal]
    var days: [CanvasDay]
    var weeklyTotals: [String: Double]
}

struct CanvasHighlight: Codable, Equatable {
    var instanceId: String
    var change: String
    var reason: String
}

struct CanvasOp: Codable, Equatable {
    var id: String
    var kind: String
    var target: String?
    var count: Int?
    var day: String?
    var toVariantId: String?
    var item: String?
    var instanceId: String?
    var toDay: String?
    var toSessionId: String?
    var toIndex: Int?
    var sets: Int?
}

struct CanvasProposal: Codable, Equatable, Identifiable {
    var id: String
    var requestId: String
    var requestHash: String
    var generation: Int
    var baseRevisionId: String?
    var source: String
    var utterance: String?
    var ops: [CanvasOp]
    var preview: CanvasPlan
    var highlights: [CanvasHighlight]
    var status: String
    var decisionRequestId: String?
    var decisionHash: String?
}

struct CanvasRevision: Codable, Equatable, Identifiable {
    var id: String
    var proposalId: String
    var plan: CanvasPlan
}

struct CanvasJournal: Codable, Equatable {
    var version: Int
    var generation: Int
    var applied: [CanvasRevision]
    var head: Int
    var proposals: [CanvasProposal]

    static var empty: CanvasJournal {
        CanvasJournal(version: 1, generation: 0, applied: [], head: -1, proposals: [])
    }

    var persistedPlan: CanvasPlan? {
        guard head >= 0, applied.indices.contains(head) else { return nil }
        return applied[head].plan
    }

    var revisionId: String? {
        guard head >= 0, applied.indices.contains(head) else { return nil }
        return applied[head].id
    }
}

struct CanvasPropose: Equatable {
    var requestId: String
    var expectedGeneration: Int
    var baseRevisionId: String?
    var source: String
    var text: String?
    var ops: [CanvasOp]?
}

struct CanvasDecide: Equatable {
    var requestId: String
    var proposalId: String
    var expectedGeneration: Int
    var decision: String
    var acceptedOpIds: [String]?
    var setEdits: [(instanceId: String, sets: Int)]?
}

enum CanvasCommand: Equatable {
    case propose(CanvasPropose)
    case decide(CanvasDecide)

    static func == (lhs: CanvasCommand, rhs: CanvasCommand) -> Bool {
        switch (lhs, rhs) {
        case let (.propose(left), .propose(right)):
            return left == right
        case let (.decide(left), .decide(right)):
            return left.requestId == right.requestId && left.proposalId == right.proposalId &&
                left.expectedGeneration == right.expectedGeneration && left.decision == right.decision &&
                left.acceptedOpIds == right.acceptedOpIds &&
                (left.setEdits?.map { "\($0.instanceId):\($0.sets)" } ?? []) ==
                (right.setEdits?.map { "\($0.instanceId):\($0.sets)" } ?? [])
        default:
            return false
        }
    }
}

struct CanvasRevisionResult: Equatable {
    var journal: CanvasJournal
    var persist: Bool
    var kind: String
    var replay: Bool
    var missing: [String]
    var plan: CanvasPlan?
    var narration: String
}

enum MesocycleCanvasRevision {
    private static let weekdays = ["mon", "tue", "wed", "thu", "fri"]
    private static let order = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
    private static let labels = [
        "mon": "Monday", "tue": "Tuesday", "wed": "Wednesday",
        "thu": "Thursday", "fri": "Friday", "sat": "Saturday",
        "sun": "Sunday"
    ]
    private static let lowerMuscles: Set<String> = ["quads", "hamstrings", "glutes", "calves"]
    private static let guarded: Set<String> = ["prioritize", "training_days", "split_day", "swap_variant", "declare_equipment"]

    static func reduce(journal: CanvasJournal, command: CanvasCommand) -> CanvasRevisionResult {
        switch command {
        case let .propose(propose):
            return reducePropose(journal, propose)
        case let .decide(decide):
            return reduceDecide(journal, decide)
        }
    }

    static func parse(_ text: String) -> [CanvasOp]? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
        if normalized.isEmpty { return nil }
        var slots: [[CanvasOp]?] = []
        if matches("\\bundo\\b", normalized) {
            slots.append(normalized == "undo" ? [op("undo", "undo")] : nil)
        }
        if matches("\\bredo\\b", normalized) {
            slots.append(normalized == "redo" ? [op("redo", "redo")] : nil)
        }
        if (matches("\\b(build|draft|make|start)\\b", normalized) && matches("\\b(plan|mesocycle)\\b", normalized)) ||
            matches("\\bhypertrophy plan\\b", normalized) {
            slots.append([op("draft", "draft")])
        }
        if matches("\\bprioriti[sz]e\\b", normalized) || matches("\\bupper chest\\b", normalized) {
            let complete = matches("\\bprioriti[sz]e\\b", normalized) &&
                matches("\\bupper chest\\b", normalized) && matches("\\btriceps\\b", normalized)
            slots.append(complete ? [
                op("priority-upper-chest", "prioritize", target: "upper_chest"),
                op("priority-triceps", "prioritize", target: "triceps")
            ] : nil)
        }
        if matches("\\btraining days\\b", normalized) {
            let fiveDays = matches("\\b(5|five) training days\\b", normalized)
            slots.append(fiveDays ? [op("training-days-5", "training_days", count: 5)] : nil)
        }
        if matches("\\bsplit\\b", normalized) ||
            (matches("\\bwednesday\\b", normalized) &&
                (matches("\\bam\\b", normalized) || matches("\\bpm\\b", normalized))) {
            let stacked = matches("\\bam\\s*/\\s*pm\\b", normalized) ||
                matches("\\bam and pm\\b", normalized) ||
                matches("\\bstacked\\b", normalized)
            let complete = matches("\\bsplit\\b", normalized) &&
                matches("\\bwednesday\\b", normalized) && stacked
            slots.append(complete ? [op("split-wed", "split_day", day: "wed")] : nil)
        }
        if matches("\\bswap\\b", normalized) {
            let complete = matches("\\bincline dumbbell press\\b", normalized) &&
                matches("\\bsmith\\b", normalized)
            let swap = op(
                "swap-incline-smith",
                "swap_variant",
                toVariantId: "smith_machine_incline_press"
            )
            slots.append(complete ? [swap] : nil)
        }
        if matches("\\bi have\\b", normalized) {
            let declared = matches("\\bsmith\\b", normalized)
            let equipment = op("declare-smith-machine", "declare_equipment", item: "smith_machine")
            slots.append(declared ? [equipment] : nil)
        }
        guard slots.count == 1, let ops = slots[0] else { return nil }
        return ops
    }

    static func executionNames(_ plan: CanvasPlan) -> [String] {
        plan.days.flatMap { day in day.sessions.flatMap { session in session.exercises.map(\.name) } }
    }

    static func setLogIsValid(setNumber: Int, reps: Int, rir: Int, exercise: CanvasExercise) -> Bool {
        (1...exercise.sets).contains(setNumber) && (1...50).contains(reps) && (0...6).contains(rir)
    }

    static func coachDraft() -> CanvasPlan {
        finish(CanvasPlan(
            version: 1, policyVersion: "mesocycle-canvas-v1", weekCount: 4, currentWeek: 1,
            equipmentProfile: "dumbbells",
            availableEquipment: ["dumbbells", "bench", "adjustable_bench", "bodyweight"],
            goals: [],
            days: [
                column("mon", "Lower body", [
                    exercise("mon", "goblet_squat", "Goblet squat", "quads", ["quads": 1, "glutes": 0.5]),
                    exercise(
                        "mon",
                        "dumbbell_romanian_deadlift",
                        "Dumbbell Romanian deadlift",
                        "hamstrings",
                        ["hamstrings": 1, "glutes": 0.5]
                    )
                ]),
                column("tue", "Pull", [
                    exercise("tue", "one_arm_dumbbell_row", "One-arm dumbbell row", "back", ["back": 1, "biceps": 0.5]),
                    exercise("tue", "dumbbell_curl", "Dumbbell curl", "biceps", ["biceps": 1])
                ]),
                column("wed", "Push", [
                    exercise(
                        "wed",
                        "incline_dumbbell_press",
                        "Incline dumbbell press",
                        "chest",
                        ["chest": 1, "triceps": 0.5, "shoulders": 0.5]
                    ),
                    exercise(
                        "wed",
                        "overhead_dumbbell_triceps_extension",
                        "Overhead dumbbell triceps extension",
                        "triceps",
                        ["triceps": 1]
                    ),
                    exercise("wed", "dumbbell_lateral_raise", "Dumbbell lateral raise", "shoulders", ["shoulders": 1])
                ]),
                column("fri", "Lower maintenance", [
                    exercise(
                        "fri",
                        "dumbbell_hip_thrust",
                        "Dumbbell hip thrust",
                        "glutes",
                        ["glutes": 1, "hamstrings": 0.25]
                    ),
                    exercise("fri", "split_squat", "Split squat", "quads", ["quads": 1, "glutes": 0.5])
                ])
            ],
            weeklyTotals: [:]
        ))
    }

    private static func reducePropose(_ journal: CanvasJournal, _ command: CanvasPropose) -> CanvasRevisionResult {
        let hash = hashPropose(command)
        if let existing = journal.proposals.first(where: { $0.requestId == command.requestId }) {
            if existing.requestHash == hash {
                let narration = narrate(existing.highlights, existing.preview)
                return CanvasRevisionResult(
                    journal: journal,
                    persist: false,
                    kind: "proposed",
                    replay: true,
                    missing: [],
                    plan: existing.preview,
                    narration: narration
                )
            }
            return failure(journal, "request_conflict")
        }
        if command.expectedGeneration != journal.generation || command.baseRevisionId != journal.revisionId {
            return failure(journal, "stale_context")
        }
        let ops: [CanvasOp]
        if command.source == "direct" {
            guard let direct = command.ops, command.text == nil else { return failure(journal, "unsupported_command") }
            ops = direct
        } else {
            guard let text = command.text, let parsed = parse(text) else { return failure(journal, "unsupported_command") }
            ops = parsed
        }
        let base = journal.persistedPlan
        let applied: (plan: CanvasPlan, highlights: [CanvasHighlight])
        if ops.count == 1 && ops[0].kind == "undo" {
            guard journal.head > 0 else { return failure(journal, "nothing_to_undo") }
            applied = (
                journal.applied[journal.head - 1].plan,
                [CanvasHighlight(instanceId: "*", change: "updated", reason: "Undo the last accepted edit")]
            )
        } else if ops.count == 1 && ops[0].kind == "redo" {
            guard journal.head >= 0, journal.head < journal.applied.count - 1 else {
                return failure(journal, "nothing_to_redo")
            }
            applied = (
                journal.applied[journal.head + 1].plan,
                [CanvasHighlight(instanceId: "*", change: "updated", reason: "Redo the undone edit")]
            )
        } else {
            switch applyOps(base, ops) {
            case let .success(value):
                if let base, ops.contains(where: { guarded.contains($0.kind) }), !lowerBodyPreserved(base, value.plan) {
                    return failure(journal, "dropped_lower_body")
                }
                applied = value
            case let .failure(kind, missing):
                return failure(journal, kind, missing: missing)
            }
        }
        var next = journal
        let proposal = CanvasProposal(
            id: "proposal:\(command.requestId)", requestId: command.requestId, requestHash: hash,
            generation: journal.generation, baseRevisionId: journal.revisionId, source: command.source,
            utterance: command.text, ops: ops, preview: applied.plan, highlights: applied.highlights,
            status: "proposed", decisionRequestId: nil, decisionHash: nil
        )
        next.proposals.append(proposal)
        let narration = narrate(applied.highlights, applied.plan)
        return CanvasRevisionResult(
            journal: next,
            persist: true,
            kind: "proposed",
            replay: false,
            missing: [],
            plan: applied.plan,
            narration: narration
        )
    }

    private static func reduceDecide(_ journal: CanvasJournal, _ command: CanvasDecide) -> CanvasRevisionResult {
        guard let index = journal.proposals.firstIndex(where: { $0.id == command.proposalId }) else {
            return failure(journal, "proposal_not_found")
        }
        let hash = hashDecide(command)
        let proposal = journal.proposals[index]
        if let decisionId = proposal.decisionRequestId {
            if decisionId == command.requestId && proposal.decisionHash == hash {
                let narration = narrate(proposal.highlights, journal.persistedPlan)
                return CanvasRevisionResult(
                    journal: journal,
                    persist: false,
                    kind: "decided",
                    replay: true,
                    missing: [],
                    plan: journal.persistedPlan,
                    narration: narration
                )
            }
            let conflict = decisionId == command.requestId ? "request_conflict" : "already_decided"
            return failure(journal, conflict)
        }
        let staleGeneration = command.expectedGeneration != journal.generation
        let staleProposal = proposal.generation != journal.generation
        let staleBase = proposal.baseRevisionId != journal.revisionId
        if staleGeneration || staleProposal || staleBase {
            return failure(journal, "stale_context")
        }
        var next = journal
        if command.decision == "reject" {
            next.proposals[index].status = "rejected"
            next.proposals[index].decisionRequestId = command.requestId
            next.proposals[index].decisionHash = hash
            let narration = "Rejected the preview. The saved plan is unchanged."
            return CanvasRevisionResult(
                journal: next,
                persist: true,
                kind: "decided",
                replay: false,
                missing: [],
                plan: next.persistedPlan,
                narration: narration
            )
        }
        let selected = command.acceptedOpIds.map { ids in proposal.ops.filter { ids.contains($0.id) } } ?? proposal.ops
        if let ids = command.acceptedOpIds, selected.count != ids.count || selected.isEmpty {
            return failure(journal, selected.isEmpty ? "empty_edit" : "unknown_operation")
        }
        let undo = selected.count == 1 && selected[0].kind == "undo"
        let redo = selected.count == 1 && selected[0].kind == "redo"
        var plan: CanvasPlan
        var highlights = proposal.highlights
        if undo {
            guard next.head > 0 else { return failure(journal, "nothing_to_undo") }
            next.head -= 1
            plan = next.applied[next.head].plan
        } else if redo {
            guard next.head >= 0 && next.head < next.applied.count - 1 else { return failure(journal, "nothing_to_redo") }
            next.head += 1
            plan = next.applied[next.head].plan
        } else {
            switch applyOps(proposalBase(journal, proposal), selected) {
            case let .success(value):
                plan = value.plan
                highlights = value.highlights
            case let .failure(kind, missing):
                return failure(journal, kind, missing: missing)
            }
            if let edits = command.setEdits, !edits.isEmpty {
                switch applySetEdits(plan, edits) {
                case let .success(value):
                    plan = value.plan
                    highlights.append(contentsOf: value.highlights)
                case let .failure(kind, missing):
                    return failure(journal, kind, missing: missing)
                }
            }
            if let base = proposalBase(journal, proposal),
               selected.contains(where: { guarded.contains($0.kind) }),
               !lowerBodyPreserved(base, plan) {
                return failure(journal, "dropped_lower_body")
            }
            let revision = CanvasRevision(id: "revision:\(command.requestId)", proposalId: proposal.id, plan: plan)
            next.applied = Array(next.applied.prefix(next.head + 1))
            next.applied.append(revision)
            next.head = next.applied.count - 1
        }
        next.generation += 1
        next.proposals[index].status = "applied"
        next.proposals[index].highlights = highlights
        next.proposals[index].preview = plan
        next.proposals[index].decisionRequestId = command.requestId
        next.proposals[index].decisionHash = hash
        let narration = narrate(highlights, plan)
        return CanvasRevisionResult(
            journal: next,
            persist: true,
            kind: "decided",
            replay: false,
            missing: [],
            plan: plan,
            narration: narration
        )
    }

    private static func proposalBase(_ journal: CanvasJournal, _ proposal: CanvasProposal) -> CanvasPlan? {
        guard let id = proposal.baseRevisionId else { return nil }
        return journal.applied.first { $0.id == id }?.plan
    }

    private enum Step {
        case success(plan: CanvasPlan, highlights: [CanvasHighlight])
        case failure(String, [String])
    }

    private static func applyOps(_ plan: CanvasPlan?, _ ops: [CanvasOp]) -> Step {
        if ops.isEmpty { return .failure("empty_edit", []) }
        if ops.contains(where: { $0.kind == "undo" || $0.kind == "redo" }) { return .failure("undo_is_separate", []) }
        var current = plan
        var highlights: [CanvasHighlight] = []
        for op in ops {
            let step: Step
            if op.kind == "draft" {
                let draft = coachDraft()
                let marks = draft.days.flatMap { $0.sessions.flatMap(\.exercises) }.map { exercise in
                    CanvasHighlight(
                        instanceId: exercise.instanceId,
                        change: "added",
                        reason: "Coach draft for a 4-week hypertrophy mesocycle"
                    )
                }
                step = current == nil
                    ? .success(plan: draft, highlights: marks)
                    : .failure("already_drafted", [])
            } else if let current {
                step = apply(current, op)
            } else {
                step = .failure("no_plan", [])
            }
            switch step {
            case let .success(plan, marks):
                current = plan
                highlights.append(contentsOf: marks)
            case let .failure(kind, missing):
                return .failure(kind, missing)
            }
        }
        guard let current else { return .failure("no_plan", []) }
        return .success(plan: current, highlights: highlights)
    }

    private static func apply(_ plan: CanvasPlan, _ op: CanvasOp) -> Step {
        switch op.kind {
        case "prioritize":
            return applyPriority(plan, op.target ?? "")
        case "training_days":
            return applyFiveDays(plan)
        case "split_day":
            return applySplit(plan)
        case "swap_variant":
            return applySwap(plan)
        case "declare_equipment":
            return applyDeclare(plan, op.item ?? "")
        case "move":
            return applyMove(plan, op)
        case "set_sets":
            return applySets(plan, op.instanceId ?? "", op.sets ?? 0)
        default:
            return .failure("unknown_operation", [])
        }
    }

    private static func applyPriority(_ plan: CanvasPlan, _ target: String) -> Step {
        var highlights: [CanvasHighlight] = []
        let next = mapExercises(plan) { exercise in
            if target == "upper_chest" && isUpper(exercise) {
                highlights.append(CanvasHighlight(
                    instanceId: exercise.instanceId,
                    change: "updated",
                    reason: "Prioritize upper chest"
                ))
                var copy = exercise
                copy.priority = "priority"
                copy.sets = min(6, exercise.sets + 1)
                return copy
            }
            if target == "triceps" && exercise.primaryMuscle == "triceps" {
                highlights.append(CanvasHighlight(
                    instanceId: exercise.instanceId,
                    change: "updated",
                    reason: "Prioritize triceps"
                ))
                var copy = exercise
                copy.priority = "priority"
                copy.sets = min(6, exercise.sets + 1)
                return copy
            }
            if lowerMuscles.contains(exercise.primaryMuscle) && exercise.priority != "maintenance" {
                highlights.append(CanvasHighlight(
                    instanceId: exercise.instanceId,
                    change: "kept",
                    reason: "Keep lower-body maintenance"
                ))
                var copy = exercise
                copy.priority = "maintenance"
                return copy
            }
            return exercise
        }
        return .success(plan: finish(next), highlights: highlights)
    }

    private static func applyFiveDays(_ plan: CanvasPlan) -> Step {
        var days = plan.days
        for id in weekdays where !days.contains(where: { $0.id == id }) {
            days.append(column(id, labels[id] ?? id, []))
        }
        days.sort { order.firstIndex(of: $0.id) ?? 0 < order.firstIndex(of: $1.id) ?? 0 }
        var highlights: [CanvasHighlight] = []
        for index in days.indices where weekdays.contains(days[index].id) {
            let count = days[index].sessions.reduce(0) { $0 + $1.exercises.count }
            if count > 0 { continue }
            guard let moved = takeLastMovable(&days, days[index].id) else { return .failure("cannot_fill_day", []) }
            days[index].sessions[0].exercises.append(moved)
            highlights.append(CanvasHighlight(instanceId: moved.instanceId, change: "moved", reason: "Open \(days[index].label) so this mesocycle has five training days"))
        }
        var next = plan
        next.days = days
        return .success(plan: finish(next), highlights: highlights)
    }

    private static func takeLastMovable(_ days: inout [CanvasDay], _ target: String) -> CanvasExercise? {
        let donors = days.enumerated().filter { $0.element.id != target }.sorted { lhs, rhs in
            let left = lhs.element.sessions.flatMap(\.exercises).filter { !lowerMuscles.contains($0.primaryMuscle) }.count
            let right = rhs.element.sessions.flatMap(\.exercises).filter { !lowerMuscles.contains($0.primaryMuscle) }.count
            if left != right { return left > right }
            return (order.firstIndex(of: lhs.element.id) ?? 0) < (order.firstIndex(of: rhs.element.id) ?? 0)
        }
        guard let donor = donors.first else { return nil }
        let total = donor.element.sessions.reduce(0) { $0 + $1.exercises.count }
        if total < 2 { return nil }
        for sessionIndex in donor.element.sessions.indices.reversed() {
            let exercises = days[donor.offset].sessions[sessionIndex].exercises
            let movable = exercises.lastIndex(where: { !lowerMuscles.contains($0.primaryMuscle) })
            if let exerciseIndex = movable {
                return days[donor.offset].sessions[sessionIndex].exercises.remove(at: exerciseIndex)
            }
        }
        return nil
    }

    private static func applySplit(_ plan: CanvasPlan) -> Step {
        guard let dayIndex = plan.days.firstIndex(where: { $0.id == "wed" }) else { return .failure("missing_day", []) }
        let day = plan.days[dayIndex]
        guard day.sessions.count == 1, let session = day.sessions.first, session.exercises.count >= 2 else {
            return .failure(day.sessions.count == 1 ? "nothing_to_split" : "already_split", [])
        }
        let mid = Int((Double(session.exercises.count) / 2).rounded(.up))
        let am = Array(session.exercises.prefix(mid))
        let pm = Array(session.exercises.dropFirst(mid))
        var next = plan
        next.days[dayIndex].sessions = [
            CanvasSession(id: "wed:am", period: "am", title: "Wednesday AM", exercises: am),
            CanvasSession(id: "wed:pm", period: "pm", title: "Wednesday PM", exercises: pm)
        ]
        let amMarks = am.map { exercise in
            CanvasHighlight(
                instanceId: exercise.instanceId,
                change: "updated",
                reason: "Keep this exercise in the Wednesday AM session"
            )
        }
        let pmMarks = pm.map { exercise in
            CanvasHighlight(
                instanceId: exercise.instanceId,
                change: "moved",
                reason: "Split Wednesday into stacked AM and PM sessions"
            )
        }
        let highlights = amMarks + pmMarks
        return .success(plan: finish(next), highlights: highlights)
    }

    private static func applySwap(_ plan: CanvasPlan) -> Step {
        let missing = ["smith_machine", "adjustable_bench"].filter { !plan.availableEquipment.contains($0) }
        if !missing.isEmpty { return .failure("unsupported_equipment", missing) }
        var found = false
        var highlights: [CanvasHighlight] = []
        let next = mapExercises(plan) { exercise in
            guard exercise.variantId == "incline_dumbbell_press" else { return exercise }
            found = true
            highlights.append(CanvasHighlight(
                instanceId: exercise.instanceId,
                change: "replaced",
                reason: "Swap incline dumbbell press for Smith machine incline press"
            ))
            var copy = exercise
            copy.variantId = "smith_machine_incline_press"
            copy.name = "Smith machine incline press"
            return copy
        }
        if !found { return .failure("missing_exercise", []) }
        return .success(plan: finish(next), highlights: highlights)
    }

    private static func applyDeclare(_ plan: CanvasPlan, _ item: String) -> Step {
        let known = [
            "dumbbells", "bench", "adjustable_bench", "bodyweight",
            "barbell", "cable", "machine", "ez_bar"
        ]
        guard item == "smith_machine" || known.contains(item) else {
            return .failure("unknown_equipment", [])
        }
        if plan.availableEquipment.contains(item) { return .success(plan: plan, highlights: []) }
        var next = plan
        next.availableEquipment.append(item)
        return .success(plan: finish(next), highlights: [])
    }

    private static func applyMove(_ plan: CanvasPlan, _ op: CanvasOp) -> Step {
        guard let instanceId = op.instanceId,
              let toDay = op.toDay,
              let toSession = op.toSessionId,
              let toIndex = op.toIndex else {
            return .failure("bad_target", [])
        }
        var next = plan
        var lifted: CanvasExercise?
        for day in next.days.indices {
            for session in next.days[day].sessions.indices {
                if let index = next.days[day].sessions[session].exercises.firstIndex(where: { $0.instanceId == instanceId }) {
                    lifted = next.days[day].sessions[session].exercises.remove(at: index)
                }
            }
        }
        guard let exercise = lifted,
              let dayIndex = next.days.firstIndex(where: { $0.id == toDay }),
              let sessionIndex = next.days[dayIndex].sessions.firstIndex(where: { $0.id == toSession }) else {
            return .failure(lifted == nil ? "missing_exercise" : "bad_target", [])
        }
        let index = min(max(0, toIndex), next.days[dayIndex].sessions[sessionIndex].exercises.count)
        next.days[dayIndex].sessions[sessionIndex].exercises.insert(exercise, at: index)
        let reason = "Move \(exercise.name) to \(next.days[dayIndex].label)"
        return .success(plan: finish(next), highlights: [CanvasHighlight(
            instanceId: exercise.instanceId,
            change: "moved",
            reason: reason
        )])
    }

    private static func applySets(_ plan: CanvasPlan, _ instanceId: String, _ sets: Int) -> Step {
        guard (1...6).contains(sets) else { return .failure("bad_sets", []) }
        guard let current = all(plan).first(where: { $0.instanceId == instanceId }) else {
            return .failure("missing_exercise", [])
        }
        if current.sets == sets { return .failure("no_change", []) }
        let next = mapExercises(plan) { exercise in
            guard exercise.instanceId == instanceId else { return exercise }
            var copy = exercise
            copy.sets = sets
            return copy
        }
        return .success(plan: finish(next), highlights: [CanvasHighlight(instanceId: instanceId, change: "updated", reason: "Set \(current.name) to \(sets) sets")])
    }

    private static func applySetEdits(_ plan: CanvasPlan, _ edits: [(instanceId: String, sets: Int)]) -> Step {
        var current = plan
        var highlights: [CanvasHighlight] = []
        for edit in edits {
            switch applySets(current, edit.instanceId, edit.sets) {
            case let .success(plan, marks):
                current = plan
                highlights.append(contentsOf: marks)
            case let .failure(kind, missing):
                return .failure(kind, missing)
            }
        }
        return .success(plan: current, highlights: highlights)
    }

    static func lowerBodyPreserved(_ before: CanvasPlan, _ after: CanvasPlan) -> Bool {
        let previous = all(before).filter { lowerMuscles.contains($0.primaryMuscle) }
        if previous.isEmpty { return false }
        let lower = all(after).filter { lowerMuscles.contains($0.primaryMuscle) }
        let next = Dictionary(uniqueKeysWithValues: lower.map { ($0.instanceId, $0.sets) })
        return previous.allSatisfy { exercise in
            guard let sets = next[exercise.instanceId] else { return false }
            return sets >= exercise.sets
        }
    }

    private static func failure(_ journal: CanvasJournal, _ kind: String, missing: [String] = []) -> CanvasRevisionResult {
        CanvasRevisionResult(
            journal: journal,
            persist: false,
            kind: kind,
            replay: false,
            missing: missing,
            plan: journal.persistedPlan,
            narration: kind
        )
    }

    private static func narrate(_ highlights: [CanvasHighlight], _ plan: CanvasPlan?) -> String {
        guard !highlights.isEmpty else { return "No exercises changed." }
        let names = Dictionary(uniqueKeysWithValues: all(plan ?? coachDraft()).map { ($0.instanceId, $0.name) })
        return highlights.map { highlight in
            let name = names[highlight.instanceId] ?? "Exercise"
            let verb = highlight.change.prefix(1).uppercased() + highlight.change.dropFirst()
            let change = highlight.change == "kept" ? "Kept" : verb
            return "\(change) \(name). \(highlight.reason)."
        }.joined(separator: " ")
    }

    private static func finish(_ plan: CanvasPlan) -> CanvasPlan {
        var next = plan
        next.days.sort { (order.firstIndex(of: $0.id) ?? 0) < (order.firstIndex(of: $1.id) ?? 0) }
        var totals: [String: Double] = [:]
        for exercise in all(next) {
            for (muscle, fraction) in exercise.muscleContribution {
                totals[muscle, default: 0] += Double(exercise.sets) * fraction
            }
            if isUpper(exercise) { totals["upper_chest", default: 0] += Double(exercise.sets) }
        }
        next.weeklyTotals = totals.mapValues { ( $0 * 100 ).rounded() / 100 }
        let labels = [
            "upper_chest": "Upper chest", "chest": "Chest", "back": "Back",
            "shoulders": "Shoulders", "biceps": "Biceps", "triceps": "Triceps",
            "quads": "Quads", "hamstrings": "Hamstrings", "glutes": "Glutes",
            "calves": "Calves", "core": "Core"
        ]
        let muscleIds = [
            "upper_chest", "chest", "back", "shoulders", "biceps", "triceps",
            "quads", "hamstrings", "glutes", "calves", "core"
        ]
        next.goals = muscleIds.compactMap { id in
            guard (next.weeklyTotals[id] ?? 0) > 0 else { return nil }
            let matching = all(next).filter { id == "upper_chest" ? isUpper($0) : $0.primaryMuscle == id }
            let role: String
            if matching.allSatisfy({ $0.priority == "maintenance" }) { role = "maintenance" }
            else if matching.contains(where: { $0.priority == "priority" }) { role = "priority" }
            else { role = "standard" }
            return CanvasGoal(id: id, label: labels[id] ?? id, role: role, weeklySets: next.weeklyTotals[id] ?? 0)
        }
        return next
    }

    private static func all(_ plan: CanvasPlan) -> [CanvasExercise] {
        plan.days.flatMap { $0.sessions.flatMap(\.exercises) }
    }

    private static func isUpper(_ exercise: CanvasExercise) -> Bool {
        exercise.primaryMuscle == "chest" &&
            (exercise.variantId == "incline_dumbbell_press" || exercise.variantId == "smith_machine_incline_press")
    }

    private static func mapExercises(_ plan: CanvasPlan, _ visit: (CanvasExercise) -> CanvasExercise) -> CanvasPlan {
        var next = plan
        for day in next.days.indices {
            for session in next.days[day].sessions.indices {
                next.days[day].sessions[session].exercises = next.days[day].sessions[session].exercises.map(visit)
            }
        }
        return next
    }

    private static func column(_ day: String, _ title: String, _ exercises: [CanvasExercise]) -> CanvasDay {
        CanvasDay(
            id: day,
            label: labels[day] ?? day,
            sessions: [CanvasSession(
                id: "\(day):day",
                period: "day",
                title: title,
                exercises: exercises
            )]
        )
    }

    private static func exercise(
        _ day: String,
        _ variant: String,
        _ name: String,
        _ muscle: String,
        _ contribution: [String: Double]
    ) -> CanvasExercise {
        CanvasExercise(
            instanceId: "ex:\(day):\(variant)",
            variantId: variant,
            name: name,
            primaryMuscle: muscle,
            muscleContribution: contribution,
            sets: 3,
            repRange: .init(min: 8, max: 12),
            targetReps: 10,
            targetRir: 4,
            priority: "standard",
            evidenceIds: ["k:81c218db"]
        )
    }

    private static func op(
        _ id: String,
        _ kind: String,
        target: String? = nil,
        count: Int? = nil,
        day: String? = nil,
        toVariantId: String? = nil,
        item: String? = nil
    ) -> CanvasOp {
        CanvasOp(
            id: id,
            kind: kind,
            target: target,
            count: count,
            day: day,
            toVariantId: toVariantId,
            item: item,
            instanceId: nil,
            toDay: nil,
            toSessionId: nil,
            toIndex: nil,
            sets: nil
        )
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func hashPropose(_ command: CanvasPropose) -> String {
        hashParts([
            command.requestId,
            String(command.expectedGeneration),
            command.baseRevisionId ?? "",
            command.source,
            command.text ?? "",
            command.ops?.map(\.id).joined(separator: ",") ?? ""
        ])
    }

    private static func hashDecide(_ command: CanvasDecide) -> String {
        hashParts([
            command.requestId,
            command.proposalId,
            String(command.expectedGeneration),
            command.decision,
            command.acceptedOpIds?.joined(separator: ",") ?? "",
            command.setEdits?.map { "\($0.instanceId):\($0.sets)" }.joined(separator: ",") ?? ""
        ])
    }

    private static func hashParts(_ parts: [String]) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in parts.joined(separator: "\u{1f}").utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(hash, radix: 16)
    }
}

struct CanvasReadbackResponse: Decodable {
    var version: Int
    var readback: Body

    struct Body: Decodable {
        var plan: CanvasPlan?
    }
}

struct MesocycleCanvasClient {
    var urlSession: URLSession = .shared
    var baseURL: URL

    init(urlSession: URLSession = .shared, baseURL: URL? = URL(string: Configuration.apiBaseURL)) {
        self.urlSession = urlSession
        self.baseURL = baseURL ?? URL(string: ProductRegistry.Hosts.api)!
    }

    func loadPlan(accessToken: String) async throws -> CanvasPlan? {
        guard let url = URL(string: "\(TrainingAPIContract.rootPath)/mesocycle-canvas", relativeTo: baseURL)?.absoluteURL else {
            throw TrainingServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw TrainingServiceError.server(code: "training_unavailable")
        }
        let decoded = try JSONDecoder().decode(CanvasReadbackResponse.self, from: data)
        guard decoded.version == TrainingAPIContract.version else { throw TrainingServiceError.invalidResponse }
        return decoded.readback.plan
    }
}
