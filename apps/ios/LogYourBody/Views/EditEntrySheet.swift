import SwiftUI
import Foundation
import UIKit

/// A focused editor for an existing weight or body-fat log.
///
/// The sheet deliberately keeps the task to two decisions: when the entry belongs
/// and what its value is. The save action stays above the keyboard so a user does
/// not need to hunt through a long form to finish editing.
struct EditEntrySheet: View {
    private enum Field: Hashable {
        case value
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let entry: MetricEntry
    let metricType: DashboardViewLiquid.DashboardMetricKind
    let useMetricUnits: Bool
    let onComplete: () async -> Void

    @State private var selectedDate: Date
    @State private var primaryValue: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?
    @AccessibilityFocusState private var feedbackFocused: Bool

    private var measurementSystem: MeasurementSystem {
        useMetricUnits ? .metric : .imperial
    }

    init(
        entry: MetricEntry,
        metricType: DashboardViewLiquid.DashboardMetricKind,
        useMetricUnits: Bool,
        onComplete: @escaping () async -> Void
    ) {
        self.entry = entry
        self.metricType = metricType
        self.useMetricUnits = useMetricUnits
        self.onComplete = onComplete
        _selectedDate = State(initialValue: entry.date)
        _primaryValue = State(initialValue: Self.initialValue(for: entry))
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: JovieTokens.sectionGap) {
                    if showsHealthBanner {
                        healthIntegrationBanner
                    }

                    dateField
                    valueField

                    if let message = errorMessage {
                        feedbackCallout(message, isError: true)
                            .accessibilityFocused($feedbackFocused)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.top, JovieTokens.itemGap)
                .padding(.bottom, JovieTokens.sectionGap)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(isSaving)
            .background(Color.jovieCanvas)
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
            .navigationTitle("Edit \(metricName)")
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
                    .disabled(isSaving)
                    .accessibilityLabel("Cancel editing")
                    .accessibilityHint("Discards changes to this entry")
                }

                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        focusedField = nil
                    }
                    .font(.body.weight(.semibold))
                    .disabled(isSaving)
                    .accessibilityIdentifier("edit_entry_keyboard_done_button")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
        .accessibilityIdentifier("edit_entry_sheet")
    }

    private var dateField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.jovieTextSecondary)

            DatePicker(
                "Entry date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .tint(Color.jovieMetricAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: JovieTokens.minimumHitTarget)
            .accessibilityLabel("Entry date")
            .accessibilityHint("Choose the date for this \(metricName.lowercased()) entry")
            .onChange(of: selectedDate) { _, _ in
                errorMessage = nil
                feedbackFocused = false
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

    private var valueField: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Text(primaryFieldLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.jovieTextSecondary)

            HStack(alignment: .center, spacing: JovieTokens.itemGap) {
                TextField("0.0", text: $primaryValue)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color.jovieText)
                    .focused($focusedField, equals: .value)
                    .accessibilityLabel("\(primaryFieldLabel) value")
                    .accessibilityHint(validationHint)
                    .accessibilityIdentifier("edit_entry_value_field")
                    .onChange(of: primaryValue) { _, _ in
                        handleValueChange()
                    }

                Text(unitLabel)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.jovieTextSecondary)
                    .accessibilityHidden(true)
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

            feedbackCallout(validationMessage ?? validationHint, isError: validationMessage != nil)
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
            "Save changes",
            configuration: ButtonConfiguration(
                style: .custom(background: .jovieAction, foreground: .jovieActionText),
                isLoading: isSaving,
                isEnabled: canSave,
                fullWidth: true,
                icon: "checkmark"
            )
        ) {
            focusedField = nil
            Task { await saveChanges() }
        }
        .disabled(!canSave)
        .accessibilityIdentifier("edit_entry_save_button")
        .accessibilityHint(canSave ? "Saves the changes to this entry" : saveDisabledHint)
    }

    private func feedbackCallout(_ message: String, isError: Bool) -> some View {
        Label(message, systemImage: isError ? "exclamationmark.circle.fill" : "info.circle.fill")
            .font(.footnote)
            .foregroundStyle(isError ? Color.red : Color.jovieTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
            .accessibilityIdentifier(isError ? "edit_entry_validation_message" : "edit_entry_validation_hint")
    }

    private var fieldBorderColor: Color {
        if validationMessage != nil {
            return .red.opacity(0.85)
        }
        return focusedField == .value ? .jovieMetricAccent : .jovieHairline
    }

    private var metricName: String {
        switch metricType {
        case .weight:
            return "Weight"
        case .bodyFat:
            return "Body Fat"
        case .steps:
            return "Steps"
        case .ffmi:
            return "FFMI"
        case .waist:
            return "Waist"
        }
    }

    private var primaryFieldLabel: String {
        switch metricType {
        case .weight:
            return "Weight"
        case .bodyFat:
            return "Body fat percentage"
        default:
            return "Value"
        }
    }

    private var unitLabel: String {
        switch metricType {
        case .weight:
            return measurementSystem.weightUnit
        case .bodyFat:
            return "%"
        default:
            return entry.primaryUnit
        }
    }

    private var validationHint: String {
        switch metricType {
        case .weight:
            return measurementSystem == .metric ? "Enter weight in kilograms" : "Enter weight in pounds"
        case .bodyFat:
            return "Enter a percentage between 3 and 60"
        default:
            return "Enter a value"
        }
    }

    private var saveDisabledHint: String {
        if isSaving {
            return "Saving changes"
        }
        return validationMessage ?? "Enter a value before saving"
    }

    private var validationMessage: String? {
        guard !primaryValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        switch metricType {
        case .weight:
            return validationErrorDescription {
                _ = try ValidationService.shared.validateWeight(primaryValue, unit: measurementSystem.weightUnit)
            }
        case .bodyFat:
            return validationErrorDescription {
                _ = try ValidationService.shared.validateBodyFat(primaryValue)
            }
        default:
            return nil
        }
    }

    private var canSave: Bool {
        EditEntrySavePolicy.canAttemptSave(
            isSaving: isSaving,
            validationMessage: validationMessage,
            value: primaryValue
        )
    }

    private var showsHealthBanner: Bool {
        entry.source == .healthKit
    }

    private var healthIntegrationBanner: some View {
        HStack(alignment: .top, spacing: JovieTokens.itemGap) {
            Image(systemName: "heart.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.red)
                .frame(width: JovieTokens.minimumHitTarget, height: JovieTokens.minimumHitTarget)
                .background(Color.red.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Synced from Apple Health")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.jovieText)

                Text("Saving here replaces the synced value for this date.")
                    .font(.footnote)
                    .foregroundStyle(Color.jovieTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemBGlassSurface(
            cornerRadius: JovieTokens.controlRadius,
            tint: Color.red,
            tintOpacity: 0.07,
            borderColor: Color.red.opacity(0.45)
        )
        .accessibilityElement(children: .combine)
    }

    private static func initialValue(for entry: MetricEntry) -> String {
        String(format: "%.1f", entry.primaryValue)
    }

    private func handleValueChange() {
        errorMessage = nil
        feedbackFocused = false
    }

    private func saveChanges() async {
        guard canSave else { return }

        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: selectedDate)

        var weightKg: Double?
        var bodyFat: Double?

        switch metricType {
        case .weight:
            do {
                let validatedWeight = try ValidationService.shared.validateWeight(
                    primaryValue,
                    unit: measurementSystem.weightUnit
                )
                weightKg = convertToKilograms(validatedWeight)
                bodyFat = nil
            } catch {
                presentError(error.localizedDescription)
                return
            }
        case .bodyFat:
            do {
                weightKg = nil
                bodyFat = try ValidationService.shared.validateBodyFat(primaryValue)
            } catch {
                presentError(error.localizedDescription)
                return
            }
        default:
            break
        }

        let updated = await CoreDataManager.shared.updateBodyMetric(
            id: entry.id,
            date: normalizedDate,
            weight: weightKg,
            bodyFatPercentage: bodyFat
        )

        await MainActor.run {
            if updated != nil {
                Task {
                    await onComplete()
                    await MainActor.run { dismiss() }
                }
            } else {
                presentError("Couldn’t save changes. Try again.")
            }
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        feedbackFocused = true
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    private func convertToKilograms(_ value: Double) -> Double {
        measurementSystem == .metric ? value : value / 2.20462
    }

    private func validationErrorDescription(_ expression: () throws -> Void) -> String? {
        do {
            try expression()
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum EditEntrySavePolicy {
    static func canAttemptSave(isSaving: Bool, validationMessage: String?, value: String) -> Bool {
        !isSaving
            && validationMessage == nil
            && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
