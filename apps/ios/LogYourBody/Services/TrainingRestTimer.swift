import Foundation

enum TrainingRestPolicy {
    static let featureGate = "training_rest_timer_v1"
    static let durationRange = 15...600

    /// Editable timer conveniences, not a readiness assessment or training prescription.
    static func defaultDuration(for exercise: TrainingExercisePrescription) -> Int {
        exercise.muscleContribution.values.filter { $0 > 0 }.count > 1 ? 120 : 90
    }
}

struct TrainingRestCountdown: Codable, Equatable, Identifiable {
    let id: UUID
    let exerciseId: String
    let startedAt: Date
    var duration: Int

    var endsAt: Date { startedAt.addingTimeInterval(TimeInterval(duration)) }

    func remaining(at date: Date) -> Int {
        max(0, Int(endsAt.timeIntervalSince(date).rounded(.up)))
    }

    /// Changing the duration preserves elapsed time rather than restarting the rest.
    func adjusted(by seconds: Int) -> Self {
        var result = self
        result.duration = min(max(duration + seconds, TrainingRestPolicy.durationRange.lowerBound),
                              TrainingRestPolicy.durationRange.upperBound)
        return result
    }
}

struct TrainingRestDraft: Codable, Equatable {
    var durations: [String: Int] = [:]
    var lastSetKey: String?
    var countdown: TrainingRestCountdown?
}
