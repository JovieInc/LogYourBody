//
// PreferencesView+TrackingGoalsSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var trackingGoalsSection: some View {
        SettingsSection(
            header: "Tracking & goals",
            footer: "Set custom targets or use defaults."
        ) {
            VStack(spacing: 0) {
                measurementSystemSection
                stepGoalRow

                DSDivider().insetted(16)
                goalRow(for: .weight)
                DSDivider().insetted(16)
                goalRow(for: .bodyFat)
                DSDivider().insetted(16)
                goalRow(for: .ffmi)
            }
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
            isCustom: isGoalCustom(goal),
            edit: {
                activeGoalEditor = goal
            },
            reset: {
                resetGoal(goal)
            }
        )
    }

    func goalEditorSheet(for goal: PreferenceGoalKind) -> some View {
        PreferenceGoalEditorSheet(
            goal: goal,
            initialText: initialGoalEditorText(for: goal),
            unitLabel: goalUnitLabel(for: goal)
        ) { value in
            saveGoal(value, for: goal)
        }
    }

    var userGender: String {
        cachedUserGender
    }

    var isFemale: Bool {
        cachedIsFemale
    }

    var defaultBodyFatGoal: Double {
        cachedDefaultBodyFatGoal
    }

    var defaultFFMIGoal: Double {
        cachedDefaultFFMIGoal
    }

    var currentBodyFatGoal: Double {
        customBodyFatGoal ?? defaultBodyFatGoal
    }

    var currentFFMIGoal: Double {
        customFFMIGoal ?? defaultFFMIGoal
    }

    func updateCachedValues() {
        cachedUserGender = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
        cachedIsFemale = cachedUserGender.contains("female") || cachedUserGender.contains("woman")
        cachedDefaultBodyFatGoal = cachedIsFemale ? Constants.BodyComposition.BodyFat.femaleIdealValue :
            Constants.BodyComposition.BodyFat.maleIdealValue
        cachedDefaultFFMIGoal = cachedIsFemale ? Constants.BodyComposition.FFMI.femaleIdealValue :
            Constants.BodyComposition.FFMI.maleIdealValue
    }

    func resetToDefaults() {
        customWeightGoal = nil
        customBodyFatGoal = nil
        customFFMIGoal = nil
    }

    func goalValueText(for goal: PreferenceGoalKind) -> String {
        switch goal {
        case .weight:
            return customWeightGoal.map {
                "\(String(format: "%.1f", $0)) \(currentSystem.weightUnit)"
            } ?? "Not set"
        case .bodyFat:
            return String(format: "%.1f%%", currentBodyFatGoal) + (customBodyFatGoal == nil ? " (default)" : "")
        case .ffmi:
            return String(format: "%.1f", currentFFMIGoal) + (customFFMIGoal == nil ? " (default)" : "")
        }
    }

    func isGoalCustom(_ goal: PreferenceGoalKind) -> Bool {
        switch goal {
        case .weight:
            return customWeightGoal != nil
        case .bodyFat:
            return customBodyFatGoal != nil
        case .ffmi:
            return customFFMIGoal != nil
        }
    }

    func resetGoal(_ goal: PreferenceGoalKind) {
        switch goal {
        case .weight:
            customWeightGoal = nil
        case .bodyFat:
            customBodyFatGoal = nil
        case .ffmi:
            customFFMIGoal = nil
        }
    }

    func initialGoalEditorText(for goal: PreferenceGoalKind) -> String {
        switch goal {
        case .weight:
            return customWeightGoal.map { String(format: "%.1f", $0) } ?? ""
        case .bodyFat:
            return customBodyFatGoal.map { String(format: "%.1f", $0) } ?? String(format: "%.1f", defaultBodyFatGoal)
        case .ffmi:
            return customFFMIGoal.map { String(format: "%.1f", $0) } ?? String(format: "%.1f", defaultFFMIGoal)
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
            customWeightGoal = value
        case .bodyFat:
            customBodyFatGoal = value
        case .ffmi:
            customFFMIGoal = value
        }
    }
}
