import XCTest
@testable import LogYourBody

final class MesocycleCanvasRevisionTests: XCTestCase {
    func testGoalSplitSwapDragReloadUndoFailsClosed() {
        var evidence: [String: Bool] = [
            "draft": false, "rejected": false, "priority": false, "selective": false,
            "fiveDays": false, "split": false, "unsupported": false, "duplicate": false,
            "missed": false, "swap": false, "drag": false, "sets": false,
            "persisted": false, "execution": false, "undo": false, "redo": false,
            "lowerBody": false, "voice": false, "ambiguous": false, "flag": false
        ]
        var journal = CanvasJournal.empty
        let draft = propose("Build a hypertrophy plan", &journal, "req-draft")
        XCTAssertEqual(draft.kind, "proposed")
        journal = draft.journal
        XCTAssertNil(journal.persistedPlan)
        journal = decide(journal, draft.journal.proposals[0].id, "req-draft-apply").journal
        let drafted = journal.persistedPlan
        let draftedDays = drafted?.days.map(\.id)
        let draftedNames = drafted.map { MesocycleCanvasRevision.executionNames($0) } ?? []
        evidence["draft"] = draftedDays == ["mon", "tue", "wed", "fri"] &&
            draftedNames.contains("Incline dumbbell press")

        let priority = propose("Prioritize upper chest and triceps", &journal, "req-priority")
        let priorityId = priority.journal.proposals.last!.id
        let rejected = decide(priority.journal, priorityId, "req-priority-reject", decision: "reject")
        journal = rejected.journal
        let wedStandard = journal.persistedPlan?.days.first { $0.id == "wed" }?
            .sessions[0].exercises.allSatisfy { $0.priority == "standard" }
        evidence["rejected"] = rejected.kind == "decided" && wedStandard == true

        let again = propose("Prioritize upper chest and triceps", &journal, "req-priority-2")
        let selective = decide(
            again.journal,
            again.journal.proposals.last!.id,
            "req-selective",
            accepted: ["priority-triceps"]
        )
        journal = selective.journal
        let wed = journal.persistedPlan?.days.first { $0.id == "wed" }?.sessions[0].exercises
        let inclineStandard = wed?.first { $0.variantId == "incline_dumbbell_press" }?.priority == "standard"
        let tricepsPriority = wed?.first { $0.primaryMuscle == "triceps" }?.priority == "priority"
        let keptLower = MesocycleCanvasRevision.lowerBodyPreserved(drafted!, journal.persistedPlan!)
        evidence["selective"] = inclineStandard && tricepsPriority && keptLower

        let full = propose("Prioritize upper chest and triceps", &journal, "req-priority-3")
        journal = decide(full.journal, full.journal.proposals.last!.id, "req-priority-apply").journal
        let incline = exercises(in: journal).first { $0.variantId == "incline_dumbbell_press" }
        let upperRole = journal.persistedPlan?.goals.first { $0.id == "upper_chest" }?.role
        let quadRole = journal.persistedPlan?.goals.first { $0.id == "quads" }?.role
        evidence["priority"] = incline?.priority == "priority" && incline?.sets == 4 &&
            upperRole == "priority" && quadRole == "maintenance"

        let beforeFive = journal
        let five = propose("Make it five training days", &journal, "req-five")
        let sibling = MesocycleCanvasRevision.reduce(
            journal: beforeFive,
            command: .propose(CanvasPropose(
                requestId: "req-split-early",
                expectedGeneration: beforeFive.generation,
                baseRevisionId: beforeFive.revisionId,
                source: "chat",
                text: "Split Wednesday AM/PM into stacked sessions",
                ops: nil
            ))
        )
        journal = decide(five.journal, five.journal.proposals.last!.id, "req-five-apply").journal
        var staleJournal = journal
        staleJournal.proposals.append(sibling.journal.proposals.last!)
        let missed = MesocycleCanvasRevision.reduce(
            journal: staleJournal,
            command: .decide(CanvasDecide(
                requestId: "req-split-early-apply",
                proposalId: sibling.journal.proposals.last!.id,
                expectedGeneration: beforeFive.generation,
                decision: "apply",
                acceptedOpIds: ["split-wed"],
                setEdits: nil
            ))
        )
        let wedSessions = journal.persistedPlan?.days.first { $0.id == "wed" }?.sessions
        evidence["fiveDays"] = journal.persistedPlan?.days.contains { $0.id == "thu" } == true
        evidence["missed"] = missed.kind == "stale_context" && missed.persist == false &&
            wedSessions?.contains { $0.period == "pm" } != true
        evidence["lowerBody"] = MesocycleCanvasRevision.lowerBodyPreserved(drafted!, journal.persistedPlan!)

        let split = propose("Split Wednesday AM/PM into stacked sessions", &journal, "req-split")
        journal = decide(split.journal, split.journal.proposals.last!.id, "req-split-apply").journal
        let wedTitles = journal.persistedPlan?.days.first { $0.id == "wed" }?.sessions.map(\.title)
        evidence["split"] = wedTitles == ["Wednesday AM", "Wednesday PM"]

        let proposalsBeforeSwap = journal.proposals.count
        let swapText = "Swap incline dumbbell press for the Smith machine incline press"
        let unsupported = propose(swapText, &journal, "req-swap-unsupported")
        evidence["unsupported"] = unsupported.kind == "unsupported_equipment" &&
            unsupported.missing == ["smith_machine"] &&
            unsupported.persist == false &&
            journal.proposals.count == proposalsBeforeSwap

        let declared = propose("I have a Smith machine", &journal, "req-declare")
        journal = decide(declared.journal, declared.journal.proposals.last!.id, "req-declare-apply").journal
        let voice = propose(swapText, &journal, "req-swap", source: "voice")
        let voiceProposal = voice.journal.proposals.last
        evidence["voice"] = voiceProposal?.source == "voice" && voiceProposal?.ops.first?.kind == "swap_variant"
        let appliedSwap = decide(voice.journal, voice.journal.proposals.last!.id, "req-swap-apply")
        journal = appliedSwap.journal
        let duplicate = MesocycleCanvasRevision.reduce(
            journal: journal,
            command: .decide(CanvasDecide(
                requestId: "req-swap-apply",
                proposalId: voice.journal.proposals.last!.id,
                expectedGeneration: voice.journal.generation,
                decision: "apply",
                acceptedOpIds: nil,
                setEdits: nil
            ))
        )
        let smith = exercises(in: journal).first { $0.instanceId == "ex:wed:incline_dumbbell_press" }
        let appliedOnce = journal.applied.filter { $0.proposalId == voice.journal.proposals.last!.id }.count
        evidence["swap"] = smith?.name == "Smith machine incline press"
        evidence["duplicate"] = duplicate.kind == "decided" && duplicate.replay &&
            duplicate.persist == false && appliedOnce == 1

        let drag = MesocycleCanvasRevision.reduce(
            journal: journal,
            command: .propose(CanvasPropose(
                requestId: "req-drag",
                expectedGeneration: journal.generation,
                baseRevisionId: journal.revisionId,
                source: "direct",
                text: nil,
                ops: [moveCurl]
            ))
        )
        let dragged = MesocycleCanvasRevision.reduce(
            journal: drag.journal,
            command: .decide(CanvasDecide(
                requestId: "req-drag-apply",
                proposalId: drag.journal.proposals.last!.id,
                expectedGeneration: journal.generation,
                decision: "apply",
                acceptedOpIds: ["drag-curl"],
                setEdits: [(instanceId: "ex:tue:dumbbell_curl", sets: 4)]
            ))
        )
        journal = dragged.journal
        let moved = journal.persistedPlan?.days.first { $0.id == "mon" }?
            .sessions[0].exercises.first { $0.instanceId == "ex:tue:dumbbell_curl" }
        evidence["drag"] = moved?.name == "Dumbbell curl"
        evidence["sets"] = moved?.sets == 4

        let data = try? JSONEncoder().encode(journal)
        let restored = data.flatMap { try? JSONDecoder().decode(CanvasJournal.self, from: $0) }
        let firstExercise = restored?.persistedPlan?.days[0].sessions[0].exercises[0]
        let wedName = restored?.persistedPlan?.days.first { $0.id == "wed" }?.sessions[0].exercises[0].name
        let restoredPlan = restored?.persistedPlan
        let restoredNames = restoredPlan.map { MesocycleCanvasRevision.executionNames($0) } ?? []
        evidence["persisted"] = wedName == "Smith machine incline press"
        evidence["execution"] = firstExercise.map { exercise in
            MesocycleCanvasRevision.setLogIsValid(setNumber: 1, reps: 10, rir: 3, exercise: exercise) &&
                restoredNames.first == exercise.name
        } ?? false
        let lowerNames = [
            "Goblet squat", "Dumbbell Romanian deadlift", "Dumbbell hip thrust", "Split squat"
        ]
        evidence["lowerBody"] = evidence["lowerBody"] == true && lowerNames.allSatisfy { restoredNames.contains($0) }

        let undo = propose("undo", &journal, "req-undo")
        journal = decide(undo.journal, undo.journal.proposals.last!.id, "req-undo-apply").journal
        let monday = journal.persistedPlan?.days.first { $0.id == "mon" }?.sessions[0].exercises
        evidence["undo"] = monday?.contains { $0.instanceId == "ex:tue:dumbbell_curl" } == false
        let redo = propose("redo", &journal, "req-redo")
        journal = decide(redo.journal, redo.journal.proposals.last!.id, "req-redo-apply").journal
        let mondayAgain = journal.persistedPlan?.days.first { $0.id == "mon" }?.sessions[0].exercises
        evidence["redo"] = mondayAgain?.contains { $0.instanceId == "ex:tue:dumbbell_curl" && $0.sets == 4 } == true
        evidence["ambiguous"] = MesocycleCanvasRevision.parse(ambiguousUtterance) == nil
        evidence["flag"] = MesocycleCanvasPolicy.isEnabled { $0 == "mesocycle_canvas_v1" } &&
            !MesocycleCanvasPolicy.isEnabled { _ in false }

        let missing = evidence.filter { !$0.value }.map(\.key).sorted()
        XCTAssertEqual(missing, [], missing.joined(separator: ","))
    }

    private var ambiguousUtterance: String {
        "prioritize upper chest and also five training days"
    }

    private var moveCurl: CanvasOp {
        CanvasOp(
            id: "drag-curl",
            kind: "move",
            target: nil,
            count: nil,
            day: nil,
            toVariantId: nil,
            item: nil,
            instanceId: "ex:tue:dumbbell_curl",
            toDay: "mon",
            toSessionId: "mon:day",
            toIndex: 0,
            sets: nil
        )
    }

    private func exercises(in journal: CanvasJournal) -> [CanvasExercise] {
        journal.persistedPlan?.days.flatMap { $0.sessions.flatMap(\.exercises) } ?? []
    }

    private func propose(
        _ text: String,
        _ journal: inout CanvasJournal,
        _ requestId: String,
        source: String = "chat"
    ) -> CanvasRevisionResult {
        let result = MesocycleCanvasRevision.reduce(
            journal: journal,
            command: .propose(CanvasPropose(
                requestId: requestId,
                expectedGeneration: journal.generation,
                baseRevisionId: journal.revisionId,
                source: source,
                text: text,
                ops: nil
            ))
        )
        if result.persist { journal = result.journal }
        return result
    }

    private func decide(
        _ journal: CanvasJournal,
        _ proposalId: String,
        _ requestId: String,
        decision: String = "apply",
        accepted: [String]? = nil
    ) -> CanvasRevisionResult {
        MesocycleCanvasRevision.reduce(
            journal: journal,
            command: .decide(CanvasDecide(
                requestId: requestId,
                proposalId: proposalId,
                expectedGeneration: journal.generation,
                decision: decision,
                acceptedOpIds: accepted,
                setEdits: nil
            ))
        )
    }
}
