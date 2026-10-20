import XCTest
@testable import LogYourBody

final class WorkoutSessionControllerTests: XCTestCase {
    private func exercise(
        _ id: String, name: String? = nil, muscle: String = "chest", sets: Int = 2
    ) -> TrainingExercisePrescription {
        TrainingExercisePrescription(
            id: id, name: name ?? id, primaryMuscle: muscle, muscleContribution: [muscle: 1],
            sets: sets, repRange: .init(min: 8, max: 12), targetReps: 10, targetRir: 3,
            targetLoadKg: 60, loadInstruction: nil, progression: "hold", evidenceIds: []
        )
    }

    private func session(
        id: String = "s1",
        exercises: [TrainingExercisePrescription]? = nil
    ) -> TrainingSession {
        TrainingSession(
            id: id, week: 1, slot: 0, pattern: "A", title: "Session",
            exercises: exercises ?? [
                exercise("a", name: "Press"), exercise("b", name: "Row", muscle: "back"),
                exercise("c", name: "Squat", muscle: "quads")
            ],
            safetyStop: false, explanation: nil, evidenceIds: [], loggedSets: nil
        )
    }

    private func key(_ exerciseId: String, _ set: Int) -> String {
        "\(exerciseId)-\(set)"
    }

    func testNowAndUpNextDeriveFromLoggedSets() {
        var controller = WorkoutSessionController(session: session(), loggedSetKeys: [])
        XCTAssertEqual(controller.now?.exercise.id, "a")
        XCTAssertEqual(controller.now?.setNumber, 1)
        XCTAssertEqual(controller.upNext?.exercise.id, "a")
        XCTAssertEqual(controller.upNext?.setNumber, 2)

        controller.refresh(loggedSetKeys: [key("a", 1), key("a", 2)])
        XCTAssertEqual(controller.now?.exercise.id, "b")
        XCTAssertEqual(controller.now?.setNumber, 1)
        XCTAssertEqual(controller.upNext?.exercise.id, "b")
        XCTAssertEqual(controller.upNext?.setNumber, 2)
    }

    func testResumeAfterRelaunchLandsOnExactSet() {
        // Mid-session relaunch: durable set identity alone determines the resume point.
        let logged: Set<String> = [key("a", 1), key("a", 2), key("b", 1)]
        let controller = WorkoutSessionController(session: session(), loggedSetKeys: logged)
        XCTAssertEqual(controller.now?.exercise.id, "b")
        XCTAssertEqual(controller.now?.setNumber, 2)
        XCTAssertEqual(controller.upNext?.exercise.id, "c")
        XCTAssertEqual(controller.upNext?.setNumber, 1)
    }

    func testCompletionWhenAllSetsLogged() {
        let logged: Set<String> = [
            key("a", 1), key("a", 2), key("b", 1), key("b", 2), key("c", 1), key("c", 2)
        ]
        let controller = WorkoutSessionController(session: session(), loggedSetKeys: logged)
        XCTAssertNil(controller.now)
        XCTAssertNil(controller.upNext)
        XCTAssertTrue(controller.isComplete)
    }

    func testOccupiedReordersWhenLaterWorkRemains() {
        var controller = WorkoutSessionController(session: session(), loggedSetKeys: [])
        let outcome = controller.markOccupied(exerciseId: "a")
        XCTAssertEqual(outcome, .reordered)
        XCTAssertEqual(controller.now?.exercise.id, "b")
        XCTAssertEqual(controller.order, ["b", "c", "a"])
    }

    func testOccupiedRequiresSubstitutionWhenNothingLaterRemains() {
        let logged: Set<String> = [key("a", 1), key("a", 2), key("b", 1), key("b", 2)]
        var controller = WorkoutSessionController(session: session(), loggedSetKeys: logged)
        let outcome = controller.markOccupied(exerciseId: "c")
        XCTAssertEqual(outcome, .requiresSubstitution)
        XCTAssertEqual(controller.now?.exercise.id, "c")
    }

    func testOccupiedNotActionableForFinishedExercise() {
        var controller = WorkoutSessionController(session: session(), loggedSetKeys: [key("a", 1), key("a", 2)])
        let outcome = controller.markOccupied(exerciseId: "a")
        XCTAssertEqual(outcome, .notActionable)
    }

    func testSubstitutionRequiresEligibilityAndNeverInventsLoad() {
        var controller = WorkoutSessionController(session: session(), loggedSetKeys: [])
        let invalid = exercise("a", name: "Duplicate", muscle: "legs") // already in session + wrong muscle
        let rejected = controller.substitute(exerciseId: "c", with: invalid, session: session())
        XCTAssertFalse(rejected)

        var candidate = exercise("d", name: "Leg press", muscle: "quads", sets: 3)
        let swapped = controller.substitute(exerciseId: "c", with: candidate, session: session())
        XCTAssertTrue(swapped)
        XCTAssertEqual(controller.exercise(for: "c")?.id, "d")
        // The substitute's queue position and target load come only from the candidate.
        XCTAssertEqual(controller.exercise(for: "c")?.targetLoadKg, 60)

        candidate = exercise("e", name: "Bodyweight squat", muscle: "quads")
        let bodyweight = TrainingExercisePrescription(
            id: candidate.id, name: candidate.name, primaryMuscle: candidate.primaryMuscle,
            muscleContribution: candidate.muscleContribution, sets: candidate.sets,
            repRange: candidate.repRange, targetReps: candidate.targetReps,
            targetRir: candidate.targetRir, targetLoadKg: nil, loadInstruction: nil,
            progression: candidate.progression, evidenceIds: candidate.evidenceIds
        )
        let swappedBodyweight = controller.substitute(exerciseId: "a", with: bodyweight, session: session())
        XCTAssertTrue(swappedBodyweight)
        XCTAssertNil(controller.exercise(for: "a")?.targetLoadKg)
    }

    func testSituationalSkipExpiresWithSessionAndNeverPersists() {
        var controller = WorkoutSessionController(session: session(), loggedSetKeys: [])
        controller.skipForToday(exerciseId: "a")
        XCTAssertEqual(controller.now?.exercise.id, "b")

        // A new controller for the same or next session starts clean: no durable dislike.
        let fresh = WorkoutSessionController(session: session(), loggedSetKeys: [])
        XCTAssertEqual(fresh.now?.exercise.id, "a")
        let nextSession = WorkoutSessionController(session: session(id: "s2"), loggedSetKeys: [])
        XCTAssertEqual(nextSession.now?.exercise.id, "a")

        controller.undoSkip(exerciseId: "a")
        XCTAssertEqual(controller.now?.exercise.id, "a")
    }

    func testShortenSessionPreservesPriorityWithinBounds() {
        var controller = WorkoutSessionController(session: session(), loggedSetKeys: [])
        // 3 exercises × 2 sets × ~4 min = ~24 min; a 10-minute budget keeps only the first.
        let kept = controller.shortenSession(remainingMinutes: 10)
        XCTAssertEqual(kept, 1)
        XCTAssertEqual(controller.now?.exercise.id, "a")
        XCTAssertEqual(controller.upNext?.exercise.id, "a")
        XCTAssertEqual(controller.upNext?.setNumber, 2)

        controller.restoreFullSession()
        XCTAssertEqual(controller.upNext?.setNumber, 2)
        XCTAssertEqual(controller.actionableIds, ["a", "b", "c"])
    }

    func testShortenSessionAlwaysKeepsOneExercise() {
        var controller = WorkoutSessionController(session: session(), loggedSetKeys: [])
        let kept = controller.shortenSession(remainingMinutes: 1)
        XCTAssertEqual(kept, 1)
        XCTAssertEqual(controller.now?.exercise.id, "a")
    }

    func testPainReportRoutesToSafetyWithoutMutation() {
        let controller = WorkoutSessionController(session: session(), loggedSetKeys: [])
        let orderBefore = controller.order
        let route = controller.routePainReport(exerciseId: "a")
        XCTAssertEqual(route, .safetyReview)
        XCTAssertEqual(controller.order, orderBefore)
        XCTAssertEqual(controller.now?.exercise.id, "a")
    }

    func testWrongSetIdentityDoesNotAdvance() {
        // A logged key for a set outside the prescription must not mark the exercise done.
        var controller = WorkoutSessionController(session: session(), loggedSetKeys: [key("a", 99)])
        XCTAssertEqual(controller.now?.exercise.id, "a")
        XCTAssertEqual(controller.now?.setNumber, 1)
        controller.refresh(loggedSetKeys: [key("zz", 1)])
        XCTAssertEqual(controller.now?.exercise.id, "a")
    }
}
