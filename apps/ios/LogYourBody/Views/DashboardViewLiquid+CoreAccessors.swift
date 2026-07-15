import SwiftUI

extension DashboardViewLiquid {
    // MARK: - Goal Helpers

    var usesIndividualizedAestheticGoals: Bool {
        _ = featureGateRefreshToken

        return AppServicePorts.analyticsTracker.isFeatureEnabled(
            flagKey: AppFeatureGate.individualizedAestheticGoals
        )
    }

    /// Returns an explicit FFMI goal, or the legacy reference fallback while the gate is disabled.
    var ffmiGoal: Double? {
        let gender = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
        let legacyReference = gender.contains("female") || gender.contains("woman") ?
            Constants.BodyComposition.FFMI.femaleReferenceMidpoint :
            Constants.BodyComposition.FFMI.maleReferenceMidpoint

        return AestheticGoalPolicy.resolvedGoal(
            explicitGoal: customFFMIGoal,
            legacyReferenceMidpoint: legacyReference,
            individualizedGoalsEnabled: usesIndividualizedAestheticGoals
        )
    }

    /// Returns an explicit body-fat goal, or the legacy reference fallback while the gate is disabled.
    var bodyFatGoal: Double? {
        let gender = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
        let legacyReference = gender.contains("female") || gender.contains("woman") ?
            Constants.BodyComposition.BodyFat.femaleReferenceMidpoint :
            Constants.BodyComposition.BodyFat.maleReferenceMidpoint

        return AestheticGoalPolicy.resolvedGoal(
            explicitGoal: customBodyFatGoal,
            legacyReferenceMidpoint: legacyReference,
            individualizedGoalsEnabled: usesIndividualizedAestheticGoals
        )
    }

    /// Returns the weight goal (optional, nil if not set)
    var weightGoal: Double? {
        customWeightGoal
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
