//
// PreferenceGoalRows.swift
// LogYourBody
//
import SwiftUI

struct PreferenceMeasurementSystemRow: View {
    @Environment(\.theme)
    private var theme

    @Binding var measurementSystem: String
    let currentSystem: MeasurementSystem

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            Image(systemName: "globe")
                .font(theme.typography.headlineSmall)
                .foregroundColor(theme.colors.text)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                Text("Units")
                    .font(theme.typography.labelLarge)
                    .foregroundColor(theme.colors.text)

                Text(currentSystem == .metric ? "Metric (kg, cm)" : "Imperial (lbs, ft)")
                    .font(theme.typography.captionLarge)
                    .foregroundColor(theme.colors.textSecondary)
            }

            Spacer(minLength: theme.spacing.sm)

            Picker("Units", selection: $measurementSystem) {
                Text("Metric").tag(MeasurementSystem.metric.rawValue)
                Text("Imperial").tag(MeasurementSystem.imperial.rawValue)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 210)
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings_units_row")
    }
}

struct PreferenceStepGoalRow: View {
    @Environment(\.theme)
    private var theme

    @Binding var stepGoal: Int
    let formattedValue: String

    var body: some View {
        Stepper(value: $stepGoal, in: 0...100_000, step: 1_000) {
            HStack(spacing: theme.spacing.sm) {
                Image(systemName: "figure.walk")
                    .font(theme.typography.headlineSmall)
                    .foregroundColor(theme.colors.text)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                    Text("Daily step goal")
                        .font(theme.typography.labelLarge)
                        .foregroundColor(theme.colors.text)

                    Text(formattedValue)
                        .font(theme.typography.captionLarge)
                        .foregroundColor(theme.colors.textSecondary)
                }
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
        .accessibilityIdentifier("settings_step_goal_row")
    }
}

struct PreferenceGoalRow: View {
    @Environment(\.theme)
    private var theme

    let goal: PreferenceGoalKind
    let valueText: String
    let isCustom: Bool
    let edit: () -> Void
    let reset: () -> Void

    var body: some View {
        HStack(spacing: theme.spacing.sm) {
            Button(action: edit) {
                HStack(spacing: theme.spacing.sm) {
                    Image(systemName: goal.icon)
                        .font(theme.typography.headlineSmall)
                        .foregroundColor(theme.colors.textSecondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: theme.spacing.xxs) {
                        Text(goal.title)
                            .font(theme.typography.labelLarge)
                            .foregroundColor(theme.colors.text)

                        Text(valueText)
                            .font(theme.typography.captionLarge)
                            .foregroundColor(theme.colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(theme.colors.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings_\(goal.rawValue)_goal_edit_button")

            if isCustom {
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(theme.typography.headlineSmall)
                        .foregroundColor(theme.colors.textSecondary)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset \(goal.title)")
                .accessibilityIdentifier("settings_\(goal.rawValue)_goal_reset_button")
            }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.sm)
    }
}
