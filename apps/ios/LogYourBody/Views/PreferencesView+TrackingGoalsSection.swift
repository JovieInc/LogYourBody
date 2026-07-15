//
// PreferencesView+TrackingGoalsSection.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var trackingGoalsSection: some View {
        SettingsSection(
            header: "Tracking & goals",
            footer: usesIndividualizedAestheticGoals
                ? "Set targets that reflect your goals."
                : "Set custom targets or use defaults."
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

    var usesIndividualizedAestheticGoals: Bool {
        _ = featureGateRefreshToken

        return AppServicePorts.analyticsTracker.isFeatureEnabled(
            flagKey: AppFeatureGate.individualizedAestheticGoals
        )
    }

    var legacyBodyFatReference: Double {
        cachedLegacyBodyFatReference
    }

    var legacyFFMIReference: Double {
        cachedLegacyFFMIReference
    }

    var currentBodyFatGoal: Double? {
        AestheticGoalPolicy.resolvedGoal(
            explicitGoal: customBodyFatGoal,
            legacyReferenceMidpoint: legacyBodyFatReference,
            individualizedGoalsEnabled: usesIndividualizedAestheticGoals
        )
    }

    var currentFFMIGoal: Double? {
        AestheticGoalPolicy.resolvedGoal(
            explicitGoal: customFFMIGoal,
            legacyReferenceMidpoint: legacyFFMIReference,
            individualizedGoalsEnabled: usesIndividualizedAestheticGoals
        )
    }

    func updateCachedValues() {
        cachedUserGender = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
        cachedIsFemale = cachedUserGender.contains("female") || cachedUserGender.contains("woman")
        cachedLegacyBodyFatReference = cachedIsFemale ?
            Constants.BodyComposition.BodyFat.femaleReferenceMidpoint :
            Constants.BodyComposition.BodyFat.maleReferenceMidpoint
        cachedLegacyFFMIReference = cachedIsFemale ?
            Constants.BodyComposition.FFMI.femaleReferenceMidpoint :
            Constants.BodyComposition.FFMI.maleReferenceMidpoint
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
            guard let currentBodyFatGoal else { return "Not set" }
            let suffix = customBodyFatGoal == nil ? " (default)" : ""
            return String(format: "%.1f%%", currentBodyFatGoal) + suffix
        case .ffmi:
            guard let currentFFMIGoal else { return "Not set" }
            let suffix = customFFMIGoal == nil ? " (default)" : ""
            return String(format: "%.1f", currentFFMIGoal) + suffix
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
            if let customBodyFatGoal {
                return String(format: "%.1f", customBodyFatGoal)
            }
            return usesIndividualizedAestheticGoals ? "" : String(format: "%.1f", legacyBodyFatReference)
        case .ffmi:
            if let customFFMIGoal {
                return String(format: "%.1f", customFFMIGoal)
            }
            return usesIndividualizedAestheticGoals ? "" : String(format: "%.1f", legacyFFMIReference)
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
