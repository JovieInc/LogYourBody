import Foundation

enum WorkoutReconciliationPolicy {
    static let featureGate = "workout_reconciliation_v1"

    /// The attendance owner supplies only its probable verdict, never inferred workout times or sets.
    struct Context {
        let ownerId: String
        let gymName: String
        let hasProbableAttendance: Bool
        let hasWorkoutLog: Bool
        let permissionGranted: Bool
    }

    static func isEligible(_ context: Context, enabled: Bool) -> Bool {
        enabled && context.permissionGranted && context.hasProbableAttendance && !context.hasWorkoutLog &&
            !context.ownerId.isEmpty && !context.gymName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(components.era ?? 0)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    static func validate(start: Date?, end: Date?) throws {
        guard start.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
              end.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
              start.flatMap({ start in end.map { $0 > start } }) ?? true
        else { throw WorkoutReconciliationError.invalidTimestamps }
    }
}

enum WorkoutReconciliationError: Error {
    case invalidTimestamps
    case invalidStoredRecord
}

/// An attendance confirmation, independent of engine prescriptions and set logs.
struct ReconciledWorkoutSession: Codable, Equatable, Identifiable {
    let id: UUID
    let gymName: String
    let confirmedAt: Date
    let userConfirmedStart: Date?
    let userConfirmedEnd: Date?
    let setLevelVolume: Double?

    init(id: UUID, gymName: String, confirmedAt: Date, userConfirmedStart: Date?, userConfirmedEnd: Date?) {
        self.id = id
        self.gymName = gymName
        self.confirmedAt = confirmedAt
        self.userConfirmedStart = userConfirmedStart
        self.userConfirmedEnd = userConfirmedEnd
        self.setLevelVolume = nil
    }

    var duration: TimeInterval? {
        guard let userConfirmedStart, let userConfirmedEnd,
              userConfirmedEnd > userConfirmedStart else { return nil }
        let seconds = userConfirmedEnd.timeIntervalSince(userConfirmedStart)
        return seconds.isFinite ? seconds : nil
    }
}

struct WorkoutReconciliationDay: Codable, Equatable {
    enum Response: String, Codable {
        case confirmed
        case denied
    }

    let promptId: UUID
    var response: Response?
    var session: ReconciledWorkoutSession?
}

@MainActor
protocol WorkoutReconciliationStoring {
    func load(ownerId: String, day: String) throws -> WorkoutReconciliationDay?
    func save(_ record: WorkoutReconciliationDay, ownerId: String, day: String) throws
}
