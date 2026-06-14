//
// PreferenceGoalEditing.swift
// LogYourBody
//
import SwiftUI

enum PreferenceGoalKind: String, Identifiable, CaseIterable {
    case weight
    case bodyFat
    case ffmi

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight:
            return "Weight goal"
        case .bodyFat:
            return "Body fat goal"
        case .ffmi:
            return "FFMI goal"
        }
    }

    var icon: String {
        switch self {
        case .weight:
            return "target"
        case .bodyFat:
            return "percent"
        case .ffmi:
            return "figure.arms.open"
        }
    }

    var placeholder: String {
        switch self {
        case .weight:
            return "180.0"
        case .bodyFat:
            return "15.0"
        case .ffmi:
            return "22.0"
        }
    }

    var helperText: String {
        switch self {
        case .weight:
            return "Enter a target greater than 0."
        case .bodyFat:
            return "Valid range: 3-60%."
        case .ffmi:
            return "Valid range: 10-30."
        }
    }
}

struct PreferenceGoalValidationResult: Equatable {
    let value: Double?
    let errorMessage: String?

    var isValid: Bool {
        value != nil && errorMessage == nil
    }
}

enum PreferenceGoalValidator {
    static func validate(_ text: String, for goal: PreferenceGoalKind) -> PreferenceGoalValidationResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return PreferenceGoalValidationResult(value: nil, errorMessage: "Enter a value.")
        }

        guard let value = Double(trimmed), value.isFinite else {
            return PreferenceGoalValidationResult(value: nil, errorMessage: "Enter a valid number.")
        }

        switch goal {
        case .weight:
            guard value > 0 else {
                return PreferenceGoalValidationResult(value: nil, errorMessage: "Weight goal must be greater than 0.")
            }
        case .bodyFat:
            guard (3...60).contains(value) else {
                return PreferenceGoalValidationResult(value: nil, errorMessage: "Body fat goal must be between 3-60%.")
            }
        case .ffmi:
            guard (10...30).contains(value) else {
                return PreferenceGoalValidationResult(value: nil, errorMessage: "FFMI goal must be between 10-30.")
            }
        }

        return PreferenceGoalValidationResult(value: value, errorMessage: nil)
    }
}

struct PreferenceGoalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let goal: PreferenceGoalKind
    let initialText: String
    let unitLabel: String?
    let save: (Double) -> Void
    @State private var draftText: String

    init(
        goal: PreferenceGoalKind,
        initialText: String,
        unitLabel: String? = nil,
        save: @escaping (Double) -> Void
    ) {
        self.goal = goal
        self.initialText = initialText
        self.unitLabel = unitLabel
        self.save = save
        self._draftText = State(initialValue: initialText)
    }

    private var validation: PreferenceGoalValidationResult {
        PreferenceGoalValidator.validate(draftText, for: goal)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(goal.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.appText)

                    Text(goal.helperText)
                        .font(.subheadline)
                        .foregroundColor(.appTextSecondary)
                }

                HStack(spacing: 10) {
                    TextField(goal.placeholder, text: $draftText)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.system(size: 20, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color.appCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                        .accessibilityIdentifier("settings_goal_editor_text_field")

                    if let unitLabel {
                        Text(unitLabel)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.appTextSecondary)
                    }
                }

                if let message = validation.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .accessibilityIdentifier("settings_goal_editor_error")
                }

                Spacer()
            }
            .padding(20)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle(goal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = validation.value {
                            save(value)
                            dismiss()
                        }
                    }
                    .disabled(!validation.isValid)
                }
            }
        }
    }
}
