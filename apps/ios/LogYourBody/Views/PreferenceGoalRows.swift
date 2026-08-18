//
// PreferenceGoalRows.swift
// LogYourBody
//
import SwiftUI

struct PreferenceMeasurementSystemRow: View {
    @Binding var measurementSystem: String
    let currentSystem: MeasurementSystem

    var body: some View {
        Picker(selection: $measurementSystem) {
            Text("Metric").tag(MeasurementSystem.metric.rawValue)
            Text("Imperial").tag(MeasurementSystem.imperial.rawValue)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Units")
                    Text(currentSystem == .metric ? "Metric (kg, cm)" : "Imperial (lbs, ft)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "globe")
            }
        }
        .pickerStyle(.menu)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings_units_row")
    }
}

struct PreferenceStepGoalRow: View {
    @Binding var stepGoal: Int
    let formattedValue: String

    var body: some View {
        Stepper(value: $stepGoal, in: 0...100_000, step: 1_000) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily step goal")
                    Text(formattedValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "figure.walk")
            }
        }
        .accessibilityIdentifier("settings_step_goal_row")
    }
}

struct PreferenceGoalRow: View {
    let goal: PreferenceGoalKind
    let valueText: String
    let edit: () -> Void

    var body: some View {
        Button(action: edit) {
            Label {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal.title)
                            .foregroundStyle(.primary)
                        Text(valueText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } icon: {
                Image(systemName: goal.icon)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("settings_\(goal.rawValue)_goal_edit_button")
    }
}
