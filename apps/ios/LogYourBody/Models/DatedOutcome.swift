import Foundation

/// User-selected targets, distinct from measured values and engine prescriptions.
/// Wire fields consume JovieInc/Jovie's lyb-launch-contract/v1 required inputs.
struct DatedOutcome: Codable, Equatable, Sendable {
    enum Metric: String, Codable, CaseIterable, Sendable {
        case weightKg = "weight_kg"
        case bodyFatPercentage = "body_fat_percentage"
        case ffmi
    }

    struct Target: Codable, Equatable, Sendable {
        var metric: Metric
        var targetValue: Double
    }

    struct Interval: Codable, Equatable, Sendable {
        var start: String
        var end: String
    }

    struct Availability: Codable, Equatable, Sendable {
        var experience: String?
        var sessionsPerWeek: Int?
        var minutesPerSession: Int?
        var equipment: String?
        var excludedVariantIds: [String]?
        var limitations: [String]?
        var preferredVariantIds: [String]?
    }

    struct Constraints: Codable, Equatable, Sendable {
        var availability = Availability()
        var travel: [Interval] = []
        var maintenance: [Interval] = []
    }

    var outcome: Target
    /// Calendar date (YYYY-MM-DD). Never moved forward automatically on expiry.
    var outcomeDate: String
    var constraints = Constraints()

    var planInputs: TrainingPlanningInputs {
        let availability = constraints.availability
        let target = String(outcome.targetValue).replacingOccurrences(of: #"\.0$"#, with: "", options: .regularExpression)
        return TrainingPlanningInputs(
            goal: "\(outcome.metric.rawValue): \(target)",
            goalDate: "\(outcomeDate)T00:00:00Z",
            experience: availability.experience,
            sessionsPerWeek: availability.sessionsPerWeek,
            minutesPerSession: availability.minutesPerSession,
            equipment: availability.equipment,
            excludedVariantIds: availability.excludedVariantIds,
            limitations: availability.limitations,
            preferredVariantIds: availability.preferredVariantIds
        )
    }

    func validate() throws {
        let availability = constraints.availability
        guard outcome.targetValue.isFinite, outcome.targetValue > 0,
              Self.calendarDate(outcomeDate) != nil,
              availability.experience.map({ ["new", "returning", "experienced"].contains($0) }) ?? true,
              availability.sessionsPerWeek.map({ (2...6).contains($0) }) ?? true,
              availability.minutesPerSession.map({ (15...180).contains($0) }) ?? true,
              availability.equipment.map({ ["dumbbells", "full_gym"].contains($0) }) ?? true,
              Self.validTags(availability.excludedVariantIds, limit: 100),
              Self.validTags(availability.preferredVariantIds, limit: 100),
              Self.validTags(availability.limitations, limit: 20),
              constraints.travel.count <= 100, constraints.maintenance.count <= 100,
              (constraints.travel + constraints.maintenance).allSatisfy({
                  Self.calendarDate($0.start) != nil && Self.calendarDate($0.end) != nil && $0.start <= $0.end
              }) else { throw DatedOutcomeError.invalidValue }
    }

    private static func validTags(_ values: [String]?, limit: Int) -> Bool {
        guard let values else { return true }
        return values.count <= limit && values.allSatisfy { !$0.isEmpty && $0.count <= 100 }
    }

    static func calendarDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }
}

struct DatedOutcomeEdit: Codable, Equatable, Sendable {
    let requestId: UUID
    let previousRevision: UUID?
    let value: DatedOutcome

    enum CodingKeys: String, CodingKey { case requestId, previousRevision, value }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestId, forKey: .requestId)
        // The server distinguishes an initial revision from a missing field.
        try container.encode(previousRevision, forKey: .previousRevision)
        try container.encode(value, forKey: .value)
    }
}

struct DatedOutcomeSnapshot: Codable, Equatable, Sendable {
    let revision: UUID
    let value: DatedOutcome
}

enum DatedOutcomeError: Error {
    case unavailable, unauthenticated, invalidValue, invalidReceipt
}
