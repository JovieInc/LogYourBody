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

    var hasCurrentDashboardPublication: Bool {
        viewModel.hasCurrentPublication(for: authManager)
    }

    var hasLoadedCurrentDashboardData: Bool {
        viewModel.hasLoadedInitialData &&
            (hasCurrentDashboardPublication || authManager.captureAccountSession() == nil)
    }

    var isSyncingCurrentDashboardData: Bool {
        viewModel.hasCurrentActivity(for: authManager) && viewModel.isSyncingData
    }

    var bodyMetrics: [BodyMetrics] {
        hasCurrentDashboardPublication ? viewModel.bodyMetrics : []
    }

    var sortedBodyMetricsAscending: [BodyMetrics] {
        hasCurrentDashboardPublication ? viewModel.sortedBodyMetricsAscending : []
    }

    var recentDailyMetrics: [DailyMetrics] {
        hasCurrentDashboardPublication ? viewModel.recentDailyMetrics : []
    }

    var dailyMetrics: DailyMetrics? {
        hasCurrentDashboardPublication ? viewModel.dailyMetrics : nil
    }

    /// Calculate age from date of birth
    func calculateAge(from dateOfBirth: Date?) -> Int? {
        guard let dob = dateOfBirth else { return nil }
        return ProfileBirthDatePolicy.age(from: dob)
    }

    var currentMetric: BodyMetrics? {
        guard hasCurrentDashboardPublication else { return nil }
        if layoutMode == .photoTimelineHUD, HomeV2Policy.isEnabled() {
            guard let ownership = authManager.captureAccountSession(), homeV2Timeline.isOwned(by: ownership),
                  let selection = homeV2TimelineSelection,
                  selection.id.owner == ownership.subject else { return nil }
            return homeV2Timeline.metric(for: selection.id)
        }
        let metrics = bodyMetrics
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
