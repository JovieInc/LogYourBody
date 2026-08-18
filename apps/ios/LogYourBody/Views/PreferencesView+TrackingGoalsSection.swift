//
// PreferencesView+TrackingGoalsSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var trackingGoalsSection: some View {
        SettingsSection(
            header: "Tracking & goals",
            footer: "Set targets that reflect your goals."
        ) {
            measurementSystemSection
            stepGoalRow
            goalRow(for: .weight)
            goalRow(for: .bodyFat)
            goalRow(for: .ffmi)
        }
    }

    var measurementSystemSection: some View {
        PreferenceMeasurementSystemRow(
            measurementSystem: $measurementSystem,
            currentSystem: currentSystem
        )
    }

    var stepGoalRow: some View {
        PreferenceStepGoalRow(
            stepGoal: $stepGoal,
            formattedValue: FormatterCache.stepsFormatter.string(from: NSNumber(value: stepGoal)) ?? "\(stepGoal) steps"
        )
    }

    func goalRow(for goal: PreferenceGoalKind) -> some View {
        PreferenceGoalRow(
            goal: goal,
            valueText: goalValueText(for: goal),
            edit: {
                activeGoalEditor = goal
            }
        )
    }

    func goalEditorSheet(for goal: PreferenceGoalKind) -> some View {
        PreferenceGoalEditorSheet(
            goal: goal,
            initialText: initialGoalEditorText(for: goal),
            unitLabel: goalUnitLabel(for: goal),
            resetTitle: isGoalCustom(goal) ? goal.resetActionTitle : nil,
            reset: isGoalCustom(goal) ? {
                resetGoal(goal)
            } : nil
        ) { value in
            saveGoal(value, for: goal)
        }
    }

    var currentBodyFatGoal: Double? {
        AestheticGoalPolicy.resolvedGoal(explicitGoal: customBodyFatGoal)
    }

    var currentFFMIGoal: Double? {
        AestheticGoalPolicy.resolvedGoal(explicitGoal: customFFMIGoal)
    }

    func resetToDefaults() {
        customWeightGoalKilograms = nil
        legacyCustomWeightGoal = nil
        customBodyFatGoal = nil
        customFFMIGoal = nil
    }

    func goalValueText(for goal: PreferenceGoalKind) -> String {
        switch goal {
        case .weight:
            return currentWeightGoal?.displayText(in: currentSystem) ?? "Not set"
        case .bodyFat:
            guard let currentBodyFatGoal else { return "Not set" }
            return String(format: "%.1f%%", currentBodyFatGoal)
        case .ffmi:
            guard let currentFFMIGoal else { return "Not set" }
            return String(format: "%.1f", currentFFMIGoal)
        }
    }

    func isGoalCustom(_ goal: PreferenceGoalKind) -> Bool {
        switch goal {
        case .weight:
            return currentWeightGoal != nil
        case .bodyFat:
            return customBodyFatGoal != nil
        case .ffmi:
            return customFFMIGoal != nil
        }
    }

    func resetGoal(_ goal: PreferenceGoalKind) {
        switch goal {
        case .weight:
            customWeightGoalKilograms = nil
            legacyCustomWeightGoal = nil
        case .bodyFat:
            customBodyFatGoal = nil
        case .ffmi:
            customFFMIGoal = nil
        }
    }

    func initialGoalEditorText(for goal: PreferenceGoalKind) -> String {
        switch goal {
        case .weight:
            return currentWeightGoal.map {
                String(format: "%.1f", $0.displayValue(in: currentSystem))
            } ?? ""
        case .bodyFat:
            return customBodyFatGoal.map { String(format: "%.1f", $0) } ?? ""
        case .ffmi:
            return customFFMIGoal.map { String(format: "%.1f", $0) } ?? ""
        }
    }

    func goalUnitLabel(for goal: PreferenceGoalKind) -> String? {
        switch goal {
        case .weight:
            return currentSystem.weightUnit
        case .bodyFat:
            return "%"
        case .ffmi:
            return nil
        }
    }

    func saveGoal(_ value: Double, for goal: PreferenceGoalKind) {
        switch goal {
        case .weight:
            customWeightGoalKilograms = WeightGoal(
                displayValue: value,
                measurementSystem: currentSystem
            )?.kilograms
            legacyCustomWeightGoal = nil
        case .bodyFat:
            customBodyFatGoal = value
        case .ffmi:
            customFFMIGoal = value
        }
    }

    var currentWeightGoal: WeightGoal? {
        WeightGoal(kilograms: customWeightGoalKilograms ?? -1)
    }

    func migrateLegacyWeightGoalIfNeeded() {
        guard customWeightGoalKilograms == nil,
              let migrated = WeightGoal.migrateLegacy(
                legacyCustomWeightGoal,
                measurementSystem: currentSystem
              ) else {
            return
        }

        customWeightGoalKilograms = migrated.kilograms
        legacyCustomWeightGoal = nil
    }
}
