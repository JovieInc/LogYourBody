//
// PreferenceGoalRows.swift
// LogYourBody
//
import SwiftUI

struct PreferenceMeasurementSystemRow: View {
    @Binding var measurementSystem: String
    let currentSystem: MeasurementSystem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: SettingsDesign.iconSize))
                .foregroundColor(.appText)
                .frame(width: SettingsDesign.iconFrame)

            VStack(alignment: .leading, spacing: 4) {
                Text("Units")
                    .font(SettingsDesign.titleFont)
                    .foregroundColor(.appText)

                Text(currentSystem == .metric ? "Metric (kg, cm)" : "Imperial (lbs, ft)")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }

            Spacer(minLength: 12)

            Picker("Units", selection: $measurementSystem) {
                Text("Metric").tag(MeasurementSystem.metric.rawValue)
                Text("Imperial").tag(MeasurementSystem.imperial.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 210)
        }
        .padding(.horizontal, SettingsDesign.horizontalPadding)
        .padding(.vertical, SettingsDesign.verticalPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings_units_row")
    }
}

struct PreferenceStepGoalRow: View {
    @Binding var stepGoal: Int
    let formattedValue: String

    var body: some View {
        Stepper(value: $stepGoal, in: 0...100_000, step: 1_000) {
            HStack(spacing: 12) {
                Image(systemName: "figure.walk")
                    .font(.system(size: SettingsDesign.iconSize))
                    .foregroundColor(.appText)
                    .frame(width: SettingsDesign.iconFrame)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily step goal")
                        .font(SettingsDesign.titleFont)
                        .foregroundColor(.appText)

                    Text(formattedValue)
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding(.horizontal, SettingsDesign.horizontalPadding)
        .padding(.vertical, SettingsDesign.verticalPadding)
        .accessibilityIdentifier("settings_step_goal_row")
    }
}

struct PreferenceGoalRow: View {
    let goal: PreferenceGoalKind
    let valueText: String
    let isCustom: Bool
    let edit: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: edit) {
                HStack(spacing: 12) {
                    Image(systemName: goal.icon)
                        .font(.system(size: SettingsDesign.iconSize))
                        .foregroundColor(.appTextSecondary)
                        .frame(width: SettingsDesign.iconFrame)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.title)
                            .font(SettingsDesign.titleFont)
                            .foregroundColor(.appText)

                        Text(valueText)
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.appTextSecondary.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_\(goal.rawValue)_goal_edit_button")

            if isCustom {
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.appTextSecondary.opacity(0.7))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset \(goal.title)")
                .accessibilityIdentifier("settings_\(goal.rawValue)_goal_reset_button")
            }
        }
        .padding(.horizontal, SettingsDesign.horizontalPadding)
        .padding(.vertical, SettingsDesign.verticalPadding)
    }
}
