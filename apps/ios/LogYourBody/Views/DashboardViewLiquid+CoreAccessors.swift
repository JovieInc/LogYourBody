import SwiftUI

extension DashboardViewLiquid {
    // MARK: - Goal Helpers

    /// Returns the user-selected FFMI goal. Population references never become
    /// personal targets without explicit user input.
    var ffmiGoal: Double? {
        AestheticGoalPolicy.resolvedGoal(explicitGoal: customFFMIGoal)
    }

    /// Returns the user-selected body-fat goal.
    var bodyFatGoal: Double? {
        AestheticGoalPolicy.resolvedGoal(explicitGoal: customBodyFatGoal)
    }

    /// Returns the weight goal (optional, nil if not set)
    var weightGoal: Double? {
        WeightGoal(kilograms: customWeightGoalKilograms ?? -1)?.kilograms
    }

    var currentMeasurementSystem: MeasurementSystem {
        MeasurementSystem.fromStored(rawValue: measurementSystem)
    }

    var weightUnit: String {
        currentMeasurementSystem.weightUnit
    }

    var bodyMetrics: [BodyMetrics] {
        viewModel.bodyMetrics
    }

    var sortedBodyMetricsAscending: [BodyMetrics] {
        viewModel.sortedBodyMetricsAscending
    }

    var recentDailyMetrics: [DailyMetrics] {
        viewModel.recentDailyMetrics
    }

    var dailyMetrics: DailyMetrics? {
        viewModel.dailyMetrics
    }

    /// Calculate age from date of birth
    func calculateAge(from dateOfBirth: Date?) -> Int? {
        guard let dob = dateOfBirth else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let ageComponents = calendar.dateComponents([.year], from: dob, to: now)
        return ageComponents.year
    }

    var currentMetric: BodyMetrics? {
        let metrics = viewModel.bodyMetrics
        guard !metrics.isEmpty, selectedIndex >= 0, selectedIndex < metrics.count else { return nil }
        return metrics[selectedIndex]
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}
