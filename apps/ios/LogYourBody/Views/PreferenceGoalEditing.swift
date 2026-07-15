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
    private enum Field: Hashable {
        case value
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let goal: PreferenceGoalKind
    let initialText: String
    let unitLabel: String?
    let save: (Double) -> Void

    @State private var draftText: String
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var errorFocused: Bool

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
            ZStack {
                Color.jovieCanvas
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: JovieTokens.sectionGap) {
                        valueCard
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, JovieTokens.screenInset)
                    .padding(.top, JovieTokens.itemGap)
                    .padding(.bottom, JovieTokens.sectionGap)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveAction
                    .padding(.horizontal, JovieTokens.screenInset)
                    .padding(.top, JovieTokens.itemGap)
                    .padding(
                        .bottom,
                        dynamicTypeSize.isAccessibilitySize ? JovieTokens.sectionGap : JovieTokens.itemGap
                    )
                    .background(Color.jovieCanvas.opacity(0.98))
            }
            .navigationTitle(goal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.jovieCanvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.jovieText)
                    .accessibilityLabel("Cancel editing")
                    .accessibilityHint("Discards changes to this goal")
                }

                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        focusedField = nil
                    }
                    .font(.body.weight(.semibold))
                    .accessibilityIdentifier("settings_goal_editor_keyboard_done_button")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            errorFocused = validation.errorMessage != nil
        }
        .onChange(of: focusedField) { _, field in
            if field == nil, validation.errorMessage != nil {
                errorFocused = true
            }
        }
        .onChange(of: draftText) { _, _ in
            if validation.isValid {
                errorFocused = false
            }
        }
        .accessibilityIdentifier("settings_goal_editor_sheet")
    }

    private var valueCard: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Text("Goal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.jovieTextSecondary)

            HStack(alignment: .center, spacing: JovieTokens.itemGap) {
                TextField(goal.placeholder, text: $draftText)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.jovieText)
                    .focused($focusedField, equals: .value)
                    .accessibilityLabel(goal.title)
                    .accessibilityValue(accessibilityValue)
                    .accessibilityHint(validation.errorMessage ?? goal.helperText)
                    .accessibilityIdentifier("settings_goal_editor_text_field")

                if let unitLabel {
                    Text(unitLabel)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.jovieTextSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, JovieTokens.compactInset)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(Color.jovieSurfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: JovieTokens.controlRadius, style: .continuous)
                    .stroke(fieldBorderColor, lineWidth: focusedField == .value ? 2 : 1)
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: JovieTokens.subtleDuration),
                value: focusedField
            )

            if let message = validation.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .accessibilityHidden(true)

                    Text(message)
                        .accessibilityIdentifier("settings_goal_editor_error")
                        .accessibilityFocused($errorFocused)
                }
                .font(.footnote)
                .foregroundStyle(Color.red)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(goal.helperText, systemImage: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.jovieTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(goal.helperText)
            }
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.controlRadius,
            tint: .white,
            tintOpacity: 0.025,
            borderColor: .jovieHairline
        )
    }

    private var saveAction: some View {
        BaseButton(
            "Save",
            configuration: ButtonConfiguration(
                style: .custom(background: .jovieAction, foreground: .jovieActionText),
                isEnabled: validation.isValid,
                fullWidth: true,
                icon: "checkmark"
            )
        ) {
            guard let value = validation.value else { return }
            save(value)
            dismiss()
        }
        .disabled(!validation.isValid)
        .accessibilityLabel("Save")
        .accessibilityHint(validation.isValid ? "Saves this goal" : validation.errorMessage ?? "Enter a valid goal")
    }

    private var accessibilityValue: String {
        let value = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "No value" }

        if let unitLabel, !unitLabel.isEmpty {
            return "\(value) \(unitLabel)"
        }
        return value
    }

    private var fieldBorderColor: Color {
        if validation.errorMessage != nil {
            return .red.opacity(0.85)
        }
        return focusedField == .value ? .jovieMetricAccent : .jovieHairline
    }
}
