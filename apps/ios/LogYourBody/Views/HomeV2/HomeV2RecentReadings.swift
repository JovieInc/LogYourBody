import SwiftUI

struct HomeV2RecentReadings: View {
    let store: HealthSyncPresentationStore
    let unit: String
    let correctionsEnabled: Bool
    let ownsSession: (AuthManager.ProfileSessionOwnership) -> Bool
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editing: BodyMetrics?
    @State private var editText = ""
    @State private var showsEdit = false

    private var correction: MetricCorrectedValue? {
        guard let editing, let value = HomeV2WeightStepPolicy.parse(editText),
              value != HomeV2WeightStepPolicy.parse(weightText(editing)) else { return nil }
        let correction = MetricCorrectedValue(weight: unit == "lb" ? value.lbsToKg : value)
        return correction.isValid ? correction : nil
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error {
                    Text(error).foregroundStyle(Color.appError)
                        .accessibilityIdentifier("health_readings_save_error")
                }
                if let change = store.lastChange {
                    Button("Undo last change") {
                        Task {
                            await store.change(ownsSession: ownsSession, undoing: true) {
                                try await MetricCorrectionService.shared.undo(change)
                            }
                        }
                    }
                    .disabled(store.isSaving)
                    .accessibilityIdentifier("health_readings_undo")
                }
                ForEach(store.readings) { metric in
                    reading(metric)
                        .listRowBackground(HomeV2Tokens.Colors.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(HomeV2Tokens.Colors.canvas)
            .overlay {
                if store.readings.isEmpty {
                    ContentUnavailableView("No recent readings", systemImage: "scalemass")
                }
            }
            .navigationTitle("Recent readings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Edit weight", isPresented: $showsEdit) {
                TextField("Weight (\(unit))", text: $editText).keyboardType(.decimalPad)
                Button("Save") { saveCorrection() }.disabled(correction == nil || store.isSaving)
                Button("Cancel", role: .cancel) { editing = nil }
            } message: {
                Text("Changes apply only in LogYourBody. The original Apple Health reading is kept.")
            }
        }
        .tint(HomeV2Tokens.Colors.ink)
        .preferredColorScheme(.dark)
        .onChange(of: store.changeRevision) { _, _ in onChanged() }
    }

    private func reading(_ metric: BodyMetrics) -> some View {
        VStack(alignment: .leading, spacing: HomeV2Tokens.Space.tight) {
            Text("\(weightText(metric)) \(unit)")
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.title, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(HomeV2Tokens.Colors.ink)
            Text(metric.date.formatted(date: .abbreviated, time: .shortened))
                .scaledSystemFont(size: HomeV2Tokens.TypeSize.caption, relativeTo: .caption)
                .foregroundStyle(HomeV2Tokens.Colors.secondary)
            if metric.isExcluded || metric.correctedValue?.weight != nil {
                Text(metric.isExcluded ? "Excluded from trends" : "Edited in LogYourBody")
                    .font(.caption)
                    .foregroundStyle(HomeV2Tokens.Colors.secondary)
            }
            if correctionsEnabled {
                HStack(spacing: HomeV2Tokens.Space.compact) {
                    Button("Edit") {
                        editing = metric
                        editText = weightText(metric)
                        showsEdit = true
                    }
                    .frame(minWidth: JovieTokens.minimumHitTarget, minHeight: JovieTokens.minimumHitTarget)
                    .accessibilityIdentifier("health_reading_edit_\(metric.id)")
                    if !metric.isExcluded {
                        Button("Exclude") {
                            Task {
                                await store.change(ownsSession: ownsSession) {
                                    try await MetricCorrectionService.shared.exclude(metric)
                                }
                            }
                        }
                        .frame(minWidth: JovieTokens.minimumHitTarget, minHeight: JovieTokens.minimumHitTarget)
                        .accessibilityIdentifier("health_reading_exclude_\(metric.id)")
                    }
                }
                .buttonStyle(.borderless)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .disabled(store.isSaving)
            }
        }
        .padding(.vertical, HomeV2Tokens.Space.tight)
    }

    private func weightText(_ metric: BodyMetrics) -> String {
        let value = metric.weight ?? 0
        return HomeV2WeightStepPolicy.text(unit == "lb" ? value.kgToLbs : value)
    }

    private func saveCorrection() {
        guard let editing, let correction else { return }
        Task {
            await store.change(ownsSession: ownsSession) {
                try await MetricCorrectionService.shared.correct(editing, to: correction)
            }
        }
    }
}
