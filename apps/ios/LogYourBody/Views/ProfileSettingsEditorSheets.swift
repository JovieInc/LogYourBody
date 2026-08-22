//
// ProfileSettingsEditorSheets.swift
// LogYourBody
//
import SwiftUI

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

                Section {
                    Text(formattedHeight)
                        .font(.title.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(alternateHeight)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Section {
                    heightPicker
                }
            }
            .navigationTitle("Set Height")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(minWidth: 68, minHeight: JovieTokens.minimumHitTarget)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        hasChanges = true
                        onCommit?()
                        dismiss()
                    }
                    .fontWeight(.medium)
                    .jovieTouchTarget()
                }
            }
            .accessibilityIdentifier("profile_height_editor")
        }
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

        return HStack {
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
                DatePicker(
                    "Date of Birth",
                    selection: $date,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
            }
            .navigationTitle("Date of Birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(minWidth: 68, minHeight: JovieTokens.minimumHitTarget)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        hasChanges = true
                        onCommit?()
                        dismiss()
                    }
                    .fontWeight(.medium)
                    .jovieTouchTarget()
                }
            }
        }
    }
}
