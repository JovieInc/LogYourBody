//
// ProfileSettingsEditorSheets.swift
// LogYourBody
//
import SwiftUI

/// Shared toolbar chrome for the live PreferencesView profile sheets.
enum ProfileEditorSheetChrome {
    static func cancelButton(action: @escaping () -> Void) -> some View {
        Button("Cancel", action: action)
            .jovieTouchTarget()
            .accessibilityIdentifier(SettingsSurfacePolicy.profileEditorCancelIdentifier)
    }

    static func doneButton(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button("Done", action: action)
            .fontWeight(.medium)
            .disabled(!isEnabled)
            .jovieTouchTarget()
    }
}

/// Height editor used by `PreferencesView` profile sheets.
struct ProfileHeightPickerSheet: View {
    @Binding var heightCm: Int
    @Binding var useMetric: Bool
    @Binding var hasChanges: Bool
    @Environment(\.dismiss)
    var dismiss
    var onCommit: (() -> Void)?
    var body: some View {
        NavigationStack {
            Form {
                Picker("Unit", selection: $useMetric) {
                    Text("Imperial (ft/in)").tag(false)
                    Text("Metric (cm)").tag(true)
                }
                .pickerStyle(.menu)
                .frame(minHeight: JovieTokens.minimumHitTarget)

                Section {
                    VStack(spacing: JovieTokens.tightGap) {
                        Text(formattedHeight)
                            .font(.title.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text(alternateHeight)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .padding(.vertical, JovieTokens.tightGap)
                    .accessibilityElement(children: .combine)
                }

                Section {
                    heightPicker
                }
            }
            .navigationTitle("Set Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ProfileEditorSheetChrome.cancelButton(action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    ProfileEditorSheetChrome.doneButton {
                        hasChanges = true
                        onCommit?()
                        dismiss()
                    }
                }
            }
            .accessibilityIdentifier(SettingsSurfacePolicy.profileHeightEditorIdentifier)
        }
        .worldClassScreen(.editProfile)
    }

    private var heightPicker: some View {
        Group {
            if useMetric {
                Picker("Height", selection: $heightCm) {
                    ForEach(100...250, id: \.self) { cm in
                        Text("\(cm) cm").tag(cm)
                    }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            } else {
                imperialHeightPicker
            }
        }
    }

    private var imperialHeightPicker: some View {
        let components = ProfileSettingsPolicy.imperialHeightComponents(heightCm: heightCm)
        let feet = components.feet
        let inches = components.inches

        let feetBinding = Binding<Int>(
            get: { feet },
            set: { newFeet in
                heightCm = ProfileSettingsPolicy.heightCm(feet: newFeet, inches: inches)
            }
        )

        let inchesBinding = Binding<Int>(
            get: { inches },
            set: { newInches in
                heightCm = ProfileSettingsPolicy.heightCm(feet: feet, inches: newInches)
            }
        )

        return HStack(spacing: JovieTokens.itemGap) {
            Picker("Feet", selection: feetBinding) {
                ForEach(3...8, id: \.self) { value in
                    Text("\(value) ft").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)

            Picker("Inches", selection: inchesBinding) {
                ForEach(0...11, id: \.self) { value in
                    Text("\(value) in").tag(value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
        }
    }

    private var formattedHeight: String {
        ProfileSettingsPolicy.formattedHeight(heightCm: heightCm, useMetric: useMetric)
    }

    private var alternateHeight: String {
        if useMetric {
            return ProfileSettingsPolicy.formattedHeight(heightCm: heightCm, useMetric: false) + " in imperial"
        }
        return "\(heightCm) cm in metric"
    }
}

/// Date-of-birth editor used by `PreferencesView` profile sheets.
struct DatePickerSheet: View {
    @Binding var date: Date
    @Binding var hasChanges: Bool
    @Environment(\.dismiss)
    var dismiss
    var onCommit: (() -> Void)?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(date.formatted(date: .long, time: .omitted))
                        .font(.title.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, JovieTokens.tightGap)
                }

                Section {
                    DatePicker(
                        "Date of Birth",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                }
            }
            .navigationTitle("Date of Birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ProfileEditorSheetChrome.cancelButton(action: dismiss.callAsFunction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    ProfileEditorSheetChrome.doneButton {
                        hasChanges = true
                        onCommit?()
                        dismiss()
                    }
                }
            }
            .accessibilityIdentifier(SettingsSurfacePolicy.profileDateOfBirthEditorIdentifier)
        }
        .worldClassScreen(.editProfile)
    }
}
