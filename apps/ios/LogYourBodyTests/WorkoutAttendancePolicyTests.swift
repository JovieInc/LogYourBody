import XCTest
@testable import LogYourBody

final class WorkoutAttendancePolicyTests: XCTestCase {
    private typealias Policy = WorkoutAttendancePolicy

    private struct Signals: WorkoutAttendanceSignalProviding {
        let attendanceSignals: [Policy.CircumstantialSignal]
    }

    private struct Fixture {
        var input = Policy.Input()
        let signals: [Policy.CircumstantialSignal]
        let expectedState: Policy.State
        var expectedVolume: [TrainingSavedSet]?
        var expectedUnrecordedAttendance = false
    }

    private enum Fixtures {
        static let recordedSet = TrainingSavedSet(
            sessionId: "session-a", exerciseId: "squat", setNumber: 1,
            reps: 8, loadKg: 60, rir: 2
        )

        // Presence cannot distinguish training from a cafe visit or meeting.
        static let cafeOrMeetingAtGymAddress = Fixture(
            signals: [.possibleWorkout], expectedState: .probable, expectedUnrecordedAttendance: true
        )
        // The provider has rejected a noisy observation; it is not usable evidence.
        static let gpsDrift = Fixture(signals: [.unreliable], expectedState: .unknown)

        // A plausible observation follows the phone, without proving the user trained.
        static let phoneLeftAtGym = Fixture(
            signals: [.possibleWorkout], expectedState: .probable, expectedUnrecordedAttendance: true
        )
        static let incorrectVenue = Fixture(signals: [.unreliable], expectedState: .unknown)

        static let loggedWorkoutOutsideGym = Fixture(
            input: .init(records: [.init(source: .explicitSession, confirmedSets: [recordedSet])]),
            signals: [], expectedState: .confirmed, expectedVolume: [recordedSet]
        )

        // Two possible visits still provide neither confirmation nor two sessions' volume.
        static let multipleGyms = Fixture(
            signals: [.possibleWorkout, .possibleWorkout], expectedState: .probable,
            expectedUnrecordedAttendance: true
        )
        static let permissionRevoked = Fixture(signals: [], expectedState: .unknown)
        static let unloggedSessionUserDenies = Fixture(
            input: .init(userStatement: .didNotAttend), signals: [.possibleWorkout], expectedState: .missed
        )
    }

    func testCafeOrMeetingAtGymAddress() {
        assertFixture(Fixtures.cafeOrMeetingAtGymAddress)
    }

    func testGPSDrift() {
        assertFixture(Fixtures.gpsDrift)
    }

    func testPhoneLeftAtGym() {
        assertFixture(Fixtures.phoneLeftAtGym)
    }

    func testIncorrectVenue() {
        assertFixture(Fixtures.incorrectVenue)
    }

    func testLoggedWorkoutOutsideGym() {
        assertFixture(Fixtures.loggedWorkoutOutsideGym)
    }

    func testMultipleGyms() {
        assertFixture(Fixtures.multipleGyms)
    }

    func testPermissionRevoked() {
        assertFixture(Fixtures.permissionRevoked)
    }

    func testUnloggedSessionUserDenies() {
        assertFixture(Fixtures.unloggedSessionUserDenies)
    }

    func testNoSignalSetWithoutAnExplicitUserStatementYieldsMissed() {
        for records in recordCombinations {
            for signals in signalCombinations {
                let result = Policy.classify(.init(records: records), signals: Signals(attendanceSignals: signals))

                XCTAssertNotEqual(result.state, .missed, "Records: \(records), signals: \(signals)")
            }
        }
    }

    func testProbableAttendanceNeverSuppliesVolumeAndUnknownStaysUnknown() {
        for signals in signalCombinations {
            let result = Policy.classify(.init(), signals: Signals(attendanceSignals: signals))
            let expected: Policy.State = signals.contains(.possibleWorkout) ? .probable : .unknown

            XCTAssertEqual(result.state, expected)
            XCTAssertNil(result.confirmedVolume)
            XCTAssertEqual(result.unrecordedAttendance, expected == .probable)
        }
    }

    func testExplicitAndVerifiedRecordsConfirmAttendanceWithoutInventingVolume() {
        for source in Policy.Record.Source.allCases {
            let input = Policy.Input(records: [.init(source: source)])
            let result = Policy.classify(input, signals: Signals(attendanceSignals: []))

            XCTAssertEqual(result.state, .confirmed)
            XCTAssertNil(result.confirmedVolume)
            XCTAssertTrue(result.unrecordedAttendance)
        }
    }

    func testOnlyRecordedSetsSupplyConfirmedVolume() {
        for records in recordCombinations where !records.isEmpty {
            for signals in signalCombinations {
                let result = Policy.classify(.init(records: records), signals: Signals(attendanceSignals: signals))
                let expectedSets = records.flatMap(\.confirmedSets)

                XCTAssertEqual(result.state, .confirmed)
                XCTAssertEqual(result.confirmedVolume, expectedSets.isEmpty ? nil : expectedSets)
                XCTAssertEqual(result.unrecordedAttendance, expectedSets.isEmpty)
            }
        }
    }

    func testUserConfirmationDoesNotInventSets() {
        for signals in signalCombinations {
            let result = Policy.classify(
                .init(userStatement: .attended), signals: Signals(attendanceSignals: signals)
            )

            XCTAssertEqual(result.state, .confirmed)
            XCTAssertNil(result.confirmedVolume)
            XCTAssertTrue(result.unrecordedAttendance)
        }
    }

    func testExplicitDenialOverridesAllRecordAndSignalCombinations() {
        for records in recordCombinations {
            for signals in signalCombinations {
                let result = Policy.classify(
                    .init(records: records, userStatement: .didNotAttend),
                    signals: Signals(attendanceSignals: signals)
                )

                XCTAssertEqual(result.state, .missed)
                XCTAssertNil(result.confirmedVolume)
                XCTAssertFalse(result.unrecordedAttendance)
            }
        }
    }

    func testPermissionRevocationDoesNotEraseRecordedWorkout() {
        let result = Policy.classify(
            Fixtures.loggedWorkoutOutsideGym.input, signals: Signals(attendanceSignals: [])
        )

        XCTAssertEqual(result.state, .confirmed)
        XCTAssertEqual(result.confirmedVolume, [Fixtures.recordedSet])
    }

    private var recordCombinations: [[Policy.Record]] {
        let verifiedSet = TrainingSavedSet(
            sessionId: "session-b", exerciseId: "row", setNumber: 1,
            reps: 10, loadKg: nil, rir: 3
        )
        return subsets(of: [
            .init(source: .explicitSession),
            .init(source: .verifiedWorkout),
            .init(source: .explicitSession, confirmedSets: [Fixtures.recordedSet]),
            .init(source: .verifiedWorkout, confirmedSets: [verifiedSet])
        ])
    }

    private var signalCombinations: [[Policy.CircumstantialSignal]] {
        subsets(of: Policy.CircumstantialSignal.allCases) + [
            [.possibleWorkout, .possibleWorkout],
            [.unreliable, .unreliable],
            [.possibleWorkout, .unreliable, .possibleWorkout]
        ]
    }

    private func subsets<Element>(of elements: [Element]) -> [[Element]] {
        (0..<(1 << elements.count)).map { mask in
            elements.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
        }
    }

    private func assertFixture(_ fixture: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        let result = Policy.classify(fixture.input, signals: Signals(attendanceSignals: fixture.signals))

        XCTAssertEqual(result.state, fixture.expectedState, file: file, line: line)
        XCTAssertEqual(result.confirmedVolume, fixture.expectedVolume, file: file, line: line)
        XCTAssertEqual(result.unrecordedAttendance, fixture.expectedUnrecordedAttendance, file: file, line: line)
    }
}
