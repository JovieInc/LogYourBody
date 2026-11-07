#if DEBUG
import Foundation

/// Synthetic arithmetic and records for mounted UI states. These bounds are
/// test-only examples and provide no production policy or certification.
enum DatedStatsUITestFixture {
    static func apply(owner: String, input: inout LaunchJourney.Input, metrics: inout [BodyMetrics]) {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-lybUITestDatedTimelineFixture"),
              let index = arguments.firstIndex(of: "-lybUITestDatedStatsState"),
              arguments.indices.contains(index + 1),
              let state = LaunchJourney.RouteState(rawValue: arguments[index + 1]),
              let now = DatedOutcome.calendarDate("2026-11-01") else { return }
        var outcome = DatedOutcome(outcome: .init(metric: .weightKg, targetValue: 76), outcomeDate: "2026-12-27")
        if state == .impossibleDate {
            outcome.outcome.targetValue = 60
            outcome.outcomeDate = "2026-11-08"
        }
        if state == .expiredDate { outcome.outcomeDate = "2026-10-01" }
        if state == .maintenance {
            outcome.constraints.maintenance = [.init(start: "2026-11-01", end: "2026-11-14")]
        }
        input = .init(now: now, outcome: outcome, offline: state == .offline,
                      permissionDenied: state == .denial, safetyAvailable: state != .unsafeDate,
                      freshnessWindow: state == .stale ? nil : 365 * 24 * 60 * 60,
                      thresholds: [.weightKg: .init(minimumTarget: 40, maximumTarget: 250,
                                                    minimumWeeklyChange: -1, maximumWeeklyChange: 1)],
                      safeWeeklyChangeKg: -1...1)
        metrics = [record("baseline", owner: owner, date: now.addingTimeInterval(-8 * 7 * 86_400), weight: 80),
                   record("latest", owner: owner, date: now.addingTimeInterval(-4 * 7 * 86_400), weight: 78)]
        if state == .conflicting {
            metrics.append(record("conflict", owner: owner, date: metrics[1].date, weight: 79))
        }
        if state == .noData || state == .denial { metrics = [] }
    }

    private static func record(_ id: String, owner: String, date: Date, weight: Double) -> BodyMetrics {
        .init(id: id, userId: owner, date: date, weight: weight, weightUnit: "kg",
              bodyFatPercentage: nil, bodyFatMethod: nil, muscleMass: nil, boneMass: nil, notes: nil, photoUrl: nil,
              dataSource: "manual", createdAt: date, updatedAt: date)
    }
}
#endif
