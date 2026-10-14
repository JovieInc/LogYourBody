import XCTest
@testable import LogYourBody

@MainActor
final class MesocycleCanvasTests: XCTestCase {
    func testCanvasGateIsDefaultOffUntilTheFlagIsEnabled() {
        var checked: String?
        XCTAssertFalse(MesocycleCanvasPolicy.isEnabled { checked = $0; return false })
        XCTAssertEqual(checked, "mesocycle_canvas_v1")
        XCTAssertTrue(MesocycleCanvasPolicy.isEnabled { $0 == "mesocycle_canvas_v1" })
    }

    func testRejectsReadbackThatDisagreesOrArrivesWithoutAMatchingPlan() async {
        let exercise = CanvasExercise(
            instanceId: "a", variantId: "a", name: "Press", sets: 3, targetReps: 10, priority: "standard"
        )
        let session = CanvasSession(
            id: "session:monday:single", day: "monday", slot: "single", title: "Monday", exercises: [exercise]
        )
        let performed = CanvasPerformedExercise(instanceId: "a", variantId: "a", name: "Press", sets: 9, targetReps: 10)
        let workout = CanvasExecutionSession(
            sessionId: session.id, day: session.day, slot: session.slot, title: session.title, exercises: [performed]
        )
        let disagreed = CanvasReadback(
            version: 1, write: 1, generation: 1, plan: CanvasPlan(revision: 1, sessions: [session]),
            goals: [], weeklyTotals: [:], execution: [workout], proposal: nil, narration: "Saved."
        )
        let service = FixedCanvasService(
            response: CanvasCommandResponse(version: 1, kind: "read", readback: disagreed, missing: nil)
        )
        let model = MesocycleCanvasModel(
            service: service, store: MemoryCanvasStore(), accessToken: { "token" }, reduceMotion: true
        )
        await model.refresh()
        XCTAssertNil(model.readback?.plan)
        XCTAssertEqual(model.narration, "The plan could not be read.")

        let other = CanvasReadback(
            version: 1, write: 2, generation: 1, plan: CanvasPlan(revision: 2, sessions: [session]),
            goals: [], weeklyTotals: [:], execution: [], proposal: nil, narration: "Saved."
        )
        service.response = CanvasCommandResponse(version: 1, kind: "missed_update", readback: other, missing: nil)
        await model.refresh()
        XCTAssertNil(model.readback?.plan)
        XCTAssertEqual(model.narration, "The plan could not be updated.")
    }

    func testCorruptStoreDoesNotReplaceTheVisiblePlan() async {
        let store = MemoryCanvasStore()
        store.save(Data("not-a-plan".utf8))
        let model = MesocycleCanvasModel(
            service: FixedCanvasService(
                response: CanvasCommandResponse(version: 1, kind: "read", readback: .empty, missing: nil)
            ),
            store: store, accessToken: { "token" }, reduceMotion: false
        )
        model.reloadFromStore()
        XCTAssertNil(model.readback)
        XCTAssertEqual(model.narration, "The saved plan could not be read.")
    }

    func testReplayAgreesAcrossCanvasStorageAndExecution() async throws {
        let steps = try MesocycleCanvasSequence.loadOrThrow()
        let service = ScriptedCanvasService(steps: steps)
        let store = MemoryCanvasStore()
        let model = MesocycleCanvasModel(service: service, store: store, accessToken: { "fixture" }, reduceMotion: false)
        await model.refresh()
        XCTAssertNil(model.readback?.plan)
        XCTAssertTrue(CanvasAgreement.agrees(model.readback ?? .empty))

        await model.submit("Build a 4-week hypertrophy plan for a full gym")
        XCTAssertTrue(model.narration.localizedCaseInsensitiveContains("not saved"))
        XCTAssertNil(model.readback?.plan)
        await model.decide("apply")
        let drafted = try XCTUnwrap(model.readback?.plan)
        XCTAssertEqual(drafted.revision, 1)
        XCTAssertTrue(CanvasAgreement.agrees(try XCTUnwrap(model.readback)))
        XCTAssertNotNil(exercise(drafted, "Leg press"))

        await model.submit("Prioritize upper chest and triceps")
        XCTAssertEqual(model.readback?.plan?.revision, 1)
        await model.decide("reject")
        XCTAssertEqual(model.readback?.plan, drafted)
        XCTAssertTrue(model.narration.localizedCaseInsensitiveContains("unchanged"))

        await model.submit("Prioritize upper chest and triceps")
        await model.amend(instanceId: "incline_dumbbell_press:monday:single:0", sets: 6)
        await model.decide("apply")
        XCTAssertEqual(exercise(try XCTUnwrap(model.readback?.plan), "Incline dumbbell press")?.sets, 6)
        let revisionAfterPriority = model.readback?.plan?.revision
        await model.decide("apply")
        await model.resendLast()
        XCTAssertEqual(model.readback?.plan?.revision, revisionAfterPriority)
        XCTAssertEqual(exercise(try XCTUnwrap(model.readback?.plan), "Incline dumbbell press")?.sets, 6)

        await model.submit("five training days")
        await model.decide("apply")
        await model.submit("Split Wednesday into AM/PM")
        await model.decide("apply")
        let wednesday = try XCTUnwrap(model.readback?.plan).sessions.filter { $0.day == "wednesday" }.map(\.slot)
        XCTAssertEqual(wednesday, ["am", "pm"])

        await model.proposeSwap(exerciseName: "Incline dumbbell press", toVariantId: "smith_incline_press", declareEquipment: [])
        XCTAssertNotNil(exercise(try XCTUnwrap(model.readback?.plan), "Incline dumbbell press"))
        XCTAssertNil(exercise(try XCTUnwrap(model.readback?.plan), "Smith machine incline press"))
        XCTAssertTrue(model.narration.localizedCaseInsensitiveContains("unsupported equipment"))
        XCTAssertTrue(CanvasAgreement.agrees(try XCTUnwrap(model.readback)))

        model.stageVoice("Swap incline dumbbell press for the Smith machine incline press")
        let consumedAtVoice = service.consumedCount
        XCTAssertNotNil(model.stagedVoice)
        XCTAssertEqual(service.consumedCount, consumedAtVoice)
        await model.confirmVoice()
        XCTAssertGreaterThan(service.consumedCount, consumedAtVoice)
        XCTAssertEqual(model.readback?.proposal?.status, "proposed")
        XCTAssertNotNil(exercise(try XCTUnwrap(model.readback?.plan), "Incline dumbbell press"))
        XCTAssertNil(exercise(try XCTUnwrap(model.readback?.plan), "Smith machine incline press"))
        await model.decide("apply")
        let swapped = try XCTUnwrap(model.readback?.plan)
        XCTAssertNil(exercise(swapped, "Incline dumbbell press"))
        XCTAssertEqual(exercise(swapped, "Smith machine incline press")?.instanceId, "incline_dumbbell_press:monday:single:0")
        XCTAssertNotNil(exercise(swapped, "Leg press"))

        await model.move(instanceId: "standing_calf_raise:tuesday:single:3", toDay: "friday", toSlot: "single")
        await model.decide("apply")
        XCTAssertEqual(session(try XCTUnwrap(model.readback?.plan), "standing_calf_raise:tuesday:single:3")?.day, "friday")
        let moved = try XCTUnwrap(model.readback)
        XCTAssertTrue(CanvasAgreement.agrees(moved))

        let restored = MesocycleCanvasModel(service: service, store: store, accessToken: { "fixture" }, reduceMotion: true)
        restored.reloadFromStore()
        XCTAssertEqual(restored.readback?.plan, moved.plan)
        XCTAssertEqual(restored.readback?.execution, moved.execution)
        XCTAssertTrue(restored.reduceMotion)

        await model.submit("undo")
        await model.decide("apply")
        XCTAssertEqual(session(try XCTUnwrap(model.readback?.plan), "standing_calf_raise:tuesday:single:3")?.day, "tuesday")
        XCTAssertNotNil(exercise(try XCTUnwrap(model.readback?.plan), "Leg press"))
        XCTAssertTrue(CanvasAgreement.agrees(try XCTUnwrap(model.readback)))

        await model.proposeSets(instanceId: "standing_calf_raise:tuesday:single:3", sets: 8)
        XCTAssertEqual(exercise(try XCTUnwrap(model.readback?.plan), "Standing calf raise")?.sets, 2)
        XCTAssertTrue(model.narration.localizedCaseInsensitiveContains("unchanged"))
        XCTAssertEqual(service.consumedCount, steps.count)
    }
}

private final class FixedCanvasService: MesocycleCanvasServicing {
    var response: CanvasCommandResponse
    init(response: CanvasCommandResponse) { self.response = response }
    func perform(_ request: CanvasClientRequest, accessToken: String) async throws -> CanvasCommandResponse {
        _ = (request, accessToken)
        return response
    }
}

private func exercise(_ plan: CanvasPlan, _ name: String) -> CanvasExercise? {
    plan.sessions.flatMap(\.exercises).first { $0.name == name }
}

private func session(_ plan: CanvasPlan, _ instanceId: String) -> CanvasSession? {
    plan.sessions.first { $0.exercises.contains { $0.instanceId == instanceId } }
}
