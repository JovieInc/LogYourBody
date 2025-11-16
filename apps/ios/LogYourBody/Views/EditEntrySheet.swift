import SwiftUI
import Foundation

struct EditEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let entry: MetricEntry
    let metricType: DashboardViewLiquid.DashboardMetricKind
    let useMetricUnits: Bool
    let onComplete: () async -> Void

    @State private var selectedDate: Date
    @State private var primaryValue: String
    @State private var isSaving = false
    @State private var errorMessage: String?

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
        NavigationView {
            VStack(spacing: 0) {
                if showsHealthBanner {
                    healthIntegrationBanner
                        .padding(.horizontal)
                        .padding(.top, 20)
                }

                Form {
                    Section(header: Text("Date")) {
                        DatePicker(
                            "Entry Date",
                            selection: $selectedDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }

                    Section(header: Text(primaryFieldLabel)) {
                        TextField("0.0", text: $primaryValue)
                            .keyboardType(.decimalPad)
                            .disabled(isSaving)

                        if metricType == .weight {
                            HStack {
                                Spacer()
                                Text(measurementSystem.weightUnit.uppercased())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else if metricType == .bodyFat {
                            HStack {
                                Spacer()
                                Text("%").font(.caption).foregroundColor(.secondary)
                            }
                        }

                        if let message = validationMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundColor(.red)
                        } else {
                            Text(validationHint)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let message = errorMessage {
                        Section {
                            Text(message)
                                .foregroundColor(.red)
                                .font(.footnote)
                        }
                    }
                }
                .disabled(isSaving)
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveChanges() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var primaryFieldLabel: String {
        switch metricType {
        case .weight:
            return "Weight"
        case .bodyFat:
            return "Body Fat Percentage"
        default:
            return "Value"
        }
    }

    private var validationHint: String {
        switch metricType {
        case .weight:
            return measurementSystem == .metric ? "Enter weight in kilograms" : "Enter weight in pounds"
        case .bodyFat:
            return "Enter percentage between 3 and 60"
        default:
            return ""
        }
    }

    private var validationMessage: String? {
        guard !primaryValue.isEmpty else { return "" }
        guard let value = Double(primaryValue) else { return "Enter a valid number" }

        switch metricType {
        case .weight:
            let bounds: (Double, Double) = measurementSystem == .metric ? (30, 300) : (70, 660)
            if value < bounds.0 || value > bounds.1 {
                return "Weight must be between \(Int(bounds.0)) and \(Int(bounds.1)) \(measurementSystem.weightUnit)"
            }
        case .bodyFat:
            if value < 3 || value > 60 {
                return "Body fat must be between 3% and 60%"
            }
        default:
            break
        }
        return nil
    }

    private var canSave: Bool {
        validationMessage?.isEmpty ?? false ? false : validationMessage == nil
    }

    private var showsHealthBanner: Bool {
        entry.source == .healthKit
    }

    private var healthIntegrationBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "heart.fill")
                .foregroundColor(.red)
                .font(.title2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Synced from Health")
                    .font(.headline)
                Text("This entry was imported from HealthKit. Updating it here will override the synced value.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.12))
        )
    }

    private static func initialValue(for entry: MetricEntry) -> String {
        String(format: "%.1f", entry.primaryValue)
    }

    private func saveChanges() async {
        guard errorMessage == nil else { return }
        guard let parsedValue = Double(primaryValue) else {
            errorMessage = "Enter a valid number"
            return
        }

        isSaving = true
        defer { isSaving = false }

        let calendar = Calendar.current
        let normalizedDate = calendar.startOfDay(for: selectedDate)

        var weightKg: Double?
        var bodyFat: Double?

        switch metricType {
        case .weight:
            weightKg = convertToKilograms(parsedValue)
            bodyFat = nil
        case .bodyFat:
            weightKg = nil
            bodyFat = parsedValue
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
                errorMessage = "Failed to save changes. Please try again."
            }
        }
    }

    private func convertToKilograms(_ value: Double) -> Double {
        measurementSystem == .metric ? value : value / 2.20462
    }
}
