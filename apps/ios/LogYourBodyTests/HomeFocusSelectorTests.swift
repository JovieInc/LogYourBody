import XCTest
@testable import LogYourBody

final class HomeFocusSelectorTests: XCTestCase {
    private typealias Selector = HomeFocusSelector
    private typealias Candidate = Selector.Candidate
    private typealias Kind = Selector.Kind
    private typealias Level = Selector.Level

    private let now = Date(timeIntervalSince1970: 1_792_915_200)
    private let day: TimeInterval = 86_400
    private let valuable = Selector.AskValue(expectedBenefit: .high, confidence: .high, userBurden: .low)
    private let lowValue = Selector.AskValue(expectedBenefit: .low, confidence: .high, userBurden: .low)

    /// LYB-173 morning check-in examples. An import receipt is provenance,
    /// not an extra candidate or permission to ask for the same weight again.
    func testMorningCheckInFixtures() {
        let win = candidate("on-track", .earnedWin(isEarned: true))
        let weight = candidate("weight", .staleMeasurementAsk(.weight, valuable))
        let photo = candidate("photo", .missingPhotoAsk(valuable))
        let workout = candidate("workout", .todaysWorkout)
        let fixtures: [(name: String, candidates: [Candidate], context: Selector.Context, primary: Selector.Primary)] = [
            ("on track + earned win", [candidate("photo", .missingPhotoAsk(lowValue)), win], context(), .candidate(win)),
            ("new weight receipt", [weight], context(weightAge: 60), .nothingToDo),
            ("new weight + win", [weight, win], context(weightAge: 60), .candidate(win)),
            ("valuable missing photo", [win, photo], context(), .candidate(photo)),
            ("today's workout", [win, photo, workout], context(), .candidate(workout))
        ]

        for fixture in fixtures {
            let selection = Selector.select(fixture.candidates, context: fixture.context)
            XCTAssertEqual(selection.primary, fixture.primary, fixture.name)
        }
    }

    func testEmptyAndFullySuppressedInputsAreCalm() {
        XCTAssertEqual(Selector.select([], context: context()), .init(primary: .nothingToDo, rest: []))
        let suppressed = [
            candidate("weight", .staleMeasurementAsk(.weight, valuable)),
            candidate("photo", .missingPhotoAsk(lowValue)),
            candidate("unearned", .earnedWin(isEarned: false))
        ]
        XCTAssertEqual(
            Selector.select(suppressed, context: context(weightAge: 0)),
            .init(primary: .nothingToDo, rest: [])
        )
    }

    func testFreshnessBoundaryForImportedOrManuallyEnteredWeight() {
        let weight = candidate("weight", .staleMeasurementAsk(.weight, valuable))
        let fixtures: [(age: TimeInterval?, shouldAsk: Bool)] = [
            (nil, true), (0, false), (60, false), (day - 1, false), (day, false), (day + 1, true), (7 * day, true)
        ]
        for fixture in fixtures {
            let selection = Selector.select([weight], context: context(weightAge: fixture.age))
            XCTAssertEqual(selection.primary, fixture.shouldAsk ? .candidate(weight) : .nothingToDo)
            XCTAssertTrue(selection.rest.isEmpty)
        }
    }

    func testCurrentWeightIsSuppressedFromRestAndDoesNotHideMissingBodyFat() {
        let weight = candidate("weight", .staleMeasurementAsk(.weight, valuable))
        let bodyFat = candidate("body-fat", .staleMeasurementAsk(.bodyFat, valuable))
        let workout = candidate("workout", .todaysWorkout)
        let selection = Selector.select([weight, bodyFat, workout], context: context(weightAge: 30))
        XCTAssertEqual(selection.primary, .candidate(workout))
        XCTAssertEqual(selection.rest, [bodyFat])
    }

    func testBodyFatFreshnessIsIndependentOfWeight() {
        let weight = candidate("weight", .staleMeasurementAsk(.weight, valuable))
        let bodyFat = candidate("body-fat", .staleMeasurementAsk(.bodyFat, valuable))
        let selection = Selector.select([weight, bodyFat], context: .init(
            now: now,
            measurements: [.bodyFat: .init(observedAt: now, freshnessWindow: day)],
            photo: .init(observedAt: nil, freshnessWindow: 7 * day)
        ))
        XCTAssertEqual(selection.primary, .candidate(weight))
        XCTAssertTrue(selection.rest.isEmpty)
    }

    func testPhotoMustBeMissingOrStaleAndValuable() {
        let photo = candidate("photo", .missingPhotoAsk(valuable))
        let fixtures: [(age: TimeInterval?, shouldAsk: Bool)] = [
            (nil, true), (0, false), (7 * day, false), (7 * day + 1, true)
        ]
        for fixture in fixtures {
            let selection = Selector.select([photo], context: context(photoAge: fixture.age))
            XCTAssertEqual(selection.primary, fixture.shouldAsk ? .candidate(photo) : .nothingToDo)
        }
    }

    func testAskValueTableAccountsForBenefitConfidenceAndBurden() {
        let fixtures: [(benefit: Level, confidence: Level, burden: Level, shouldAsk: Bool)] = [
            (.high, .high, .low, true),
            (.high, .medium, .low, true),
            (.high, .high, .medium, true),
            (.high, .medium, .medium, true),
            (.medium, .high, .low, false),
            (.low, .high, .low, false),
            (.high, .low, .low, false),
            (.high, .high, .high, false),
            (.high, .medium, .high, false)
        ]
        for fixture in fixtures {
            let value = Selector.AskValue(
                expectedBenefit: fixture.benefit, confidence: fixture.confidence, userBurden: fixture.burden
            )
            let kinds: [Kind] = [.staleMeasurementAsk(.weight, value), .missingPhotoAsk(value)]
            for kind in kinds {
                let ask = candidate("ask", kind)
                let win = candidate("win", .earnedWin(isEarned: true))
                let selection = Selector.select([ask, win], context: context())
                let label = "\(fixture), \(kind)"
                XCTAssertEqual(selection.primary, .candidate(fixture.shouldAsk ? ask : win), label)
                XCTAssertEqual(selection.rest, fixture.shouldAsk ? [win] : [], label)
            }
        }
    }

    func testSafetyPromptAlwaysOutranksEarnedWinAndEveryRoutineAction() {
        let safety = candidate("safety", .planRevision(isSafetyRelevant: true))
        let revision = candidate("revision", .planRevision(isSafetyRelevant: false))
        let workout = candidate("workout", .todaysWorkout)
        let weight = candidate("weight", .staleMeasurementAsk(.weight, valuable))
        let photo = candidate("photo", .missingPhotoAsk(valuable))
        let win = candidate("win", .earnedWin(isEarned: true))
        let selection = Selector.select([win, photo, weight, workout, revision, safety], context: context())
        XCTAssertEqual(selection.primary, .candidate(safety))
        XCTAssertEqual(selection.rest, [revision, workout, photo, weight, win])
    }

    func testExactlyOnePrimaryAndAllOtherEligibleCandidatesRemainReachable() {
        let candidates = [
            candidate("revision", .planRevision(isSafetyRelevant: false)),
            candidate("workout", .todaysWorkout),
            candidate("weight", .staleMeasurementAsk(.weight, valuable)),
            candidate("photo", .missingPhotoAsk(valuable)),
            candidate("win", .earnedWin(isEarned: true))
        ]
        for mask in 1..<(1 << candidates.count) {
            let subset = candidates.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            let selection = Selector.select(subset, context: context())
            guard case .candidate(let primary) = selection.primary else {
                XCTFail("Nonempty eligible subset \(mask) must have one primary")
                continue
            }
            XCTAssertEqual(selection.rest.count, subset.count - 1)
            XCTAssertFalse(selection.rest.contains(primary))
            XCTAssertEqual(Set(([primary] + selection.rest).map(\.id)), Set(subset.map(\.id)))
        }
    }

    func testSameInputsAreDeterministicAndStableIdentitiesBreakTies() {
        let first = candidate("a-photo", .missingPhotoAsk(valuable))
        let second = candidate("b-weight", .staleMeasurementAsk(.weight, valuable))
        let third = candidate("c-photo", .missingPhotoAsk(valuable))
        let expected = Selector.Selection(primary: .candidate(first), rest: [second, third])
        let permutations = [
            [first, second, third], [first, third, second], [second, first, third],
            [second, third, first], [third, first, second], [third, second, first]
        ]
        for input in permutations {
            for _ in 0..<10 {
                XCTAssertEqual(Selector.select(input, context: context()), expected)
            }
        }
    }

    func testDuplicateIdentitiesUseInputOrderAsFinalTieBreak() {
        let photo = candidate("same-id", .missingPhotoAsk(valuable))
        let weight = candidate("same-id", .staleMeasurementAsk(.weight, valuable))
        for _ in 0..<10 {
            XCTAssertEqual(
                Selector.select([photo, weight], context: context()),
                .init(primary: .candidate(photo), rest: [weight])
            )
        }
    }

    func testCallerSuppliesFreshnessWindowInsteadOfUsingAHiddenClockOrCadence() {
        let weight = candidate("weight", .staleMeasurementAsk(.weight, valuable))
        let observedAt = now.addingTimeInterval(-2 * day)
        for window in [day, 3 * day] {
            let supplied = Selector.Context(
                now: now,
                measurements: [.weight: .init(observedAt: observedAt, freshnessWindow: window)],
                photo: .init(observedAt: nil, freshnessWindow: 7 * day)
            )
            XCTAssertEqual(
                Selector.select([weight], context: supplied).primary,
                window == day ? .candidate(weight) : .nothingToDo
            )
        }
    }

    func testInvalidFreshnessAndFutureObservationsDoNotCreateRepeatedAsks() {
        let weight = candidate("weight", .staleMeasurementAsk(.weight, valuable))
        let photo = candidate("photo", .missingPhotoAsk(valuable))
        let invalidSignals: [Selector.Signal] = [
            .init(observedAt: now.addingTimeInterval(day), freshnessWindow: day),
            .init(observedAt: nil, freshnessWindow: -1),
            .init(observedAt: nil, freshnessWindow: .infinity),
            .init(observedAt: nil, freshnessWindow: .nan),
            .init(observedAt: Date(timeIntervalSince1970: .nan), freshnessWindow: day)
        ]
        for signal in invalidSignals {
            let supplied = Selector.Context(now: now, measurements: [.weight: signal], photo: signal)
            XCTAssertEqual(Selector.select([weight, photo], context: supplied), .init(primary: .nothingToDo, rest: []))
        }
    }

    private func candidate(_ id: String, _ kind: Kind) -> Candidate {
        Candidate(id: id, kind: kind)
    }

    private func context(weightAge: TimeInterval? = nil, photoAge: TimeInterval? = nil) -> Selector.Context {
        Selector.Context(
            now: now,
            measurements: [.weight: .init(observedAt: weightAge.map { now.addingTimeInterval(-$0) }, freshnessWindow: day)],
            photo: .init(observedAt: photoAge.map { now.addingTimeInterval(-$0) }, freshnessWindow: 7 * day)
        )
    }
}
