/// Supplies a snapshot for one day. Adapters own consent and signal quality;
/// revoked or unavailable evidence must not be supplied as a possible workout.
protocol WorkoutAttendanceSignalProviding {
    var attendanceSignals: [WorkoutAttendancePolicy.CircumstantialSignal] { get }
}

/// Classifies evidence already scoped to the same user and day, without fetching
/// records, interpreting location, or changing a training prescription.
enum WorkoutAttendancePolicy {
    enum State: Equatable, Sendable {
        case confirmed
        case probable
        case unknown
        case missed
    }

    enum UserStatement: CaseIterable, Sendable {
        case attended
        case didNotAttend
    }

    enum CircumstantialSignal: CaseIterable, Sendable {
        case possibleWorkout
        case unreliable
    }

    struct Record: Equatable, Sendable {
        enum Source: CaseIterable, Sendable {
            case explicitSession
            case verifiedWorkout
        }

        let source: Source
        /// Actual recorded sets only, never prescribed sets or inferred volume.
        var confirmedSets: [TrainingSavedSet] = []
    }

    struct Input: Equatable, Sendable {
        /// Attendance records, not planned sessions or unverified workout drafts.
        var records: [Record] = []
        /// The user's current statement about this day's attendance.
        var userStatement: UserStatement?
    }

    struct Assessment: Equatable, Sendable {
        let state: State
        /// Nil means unknown volume, including confirmed attendance without sets.
        /// It must not be interpreted as zero completed sets.
        let confirmedVolume: [TrainingSavedSet]?

        /// Attendance evidence may inform adherence without supplying set volume.
        /// Use `state` to distinguish unknown days from explicitly missed days.
        var unrecordedAttendance: Bool {
            (state == .confirmed || state == .probable) && confirmedVolume == nil
        }
    }

    static func classify(
        _ input: Input,
        signals: any WorkoutAttendanceSignalProviding
    ) -> Assessment {
        // An explicit correction takes precedence over stale or conflicting evidence.
        if input.userStatement == .didNotAttend {
            return Assessment(state: .missed, confirmedVolume: nil)
        }

        if input.userStatement == .attended || !input.records.isEmpty {
            let sets = input.records.flatMap(\.confirmedSets)
            return Assessment(state: .confirmed, confirmedVolume: sets.isEmpty ? nil : sets)
        }

        if signals.attendanceSignals.contains(.possibleWorkout) {
            return Assessment(state: .probable, confirmedVolume: nil)
        }

        return Assessment(state: .unknown, confirmedVolume: nil)
    }
}
