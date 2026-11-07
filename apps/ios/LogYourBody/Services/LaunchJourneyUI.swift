import SwiftUI

struct LaunchDirectiveCard: View {
    let presentation: LaunchJourney.Presentation
    var note: String?
    var onAction: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("launch_directive_scroll")
        }
        .frame(maxHeight: 160)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch_directive_\(presentation.surface.rawValue)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(presentation.title)
                .font(.headline)
            Text(presentation.action.detail)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(.footnote)
            }
            Button(presentation.action.title, action: onAction)
                .accessibilityIdentifier("launch_next_action")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LaunchHiddenSurfaceRecovery: View {
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(LaunchJourney.hiddenSurfaceMessage)
                .font(.body)
                .multilineTextAlignment(.center)
            Button(LaunchJourney.hiddenSurfaceAction, action: onBack)
                .accessibilityIdentifier("launch_hidden_surface_recovery")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LaunchOutcomeEditor: View {
    var existing: DatedOutcome?
    var errorText: String?
    var onSave: (DatedOutcome) -> Void

    @State private var metric: DatedOutcome.Metric
    @State private var valueText: String
    @State private var dateText: String

    init(existing: DatedOutcome?, errorText: String?, onSave: @escaping (DatedOutcome) -> Void) {
        self.existing = existing
        self.errorText = errorText
        self.onSave = onSave
        _metric = State(initialValue: existing?.outcome.metric ?? .weightKg)
        _valueText = State(initialValue: existing.map { String(existingValue($0)) } ?? "")
        _dateText = State(initialValue: existing?.outcomeDate ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Outcome", selection: $metric) {
                    Text("Weight (kg)").tag(DatedOutcome.Metric.weightKg)
                    Text("Body fat %").tag(DatedOutcome.Metric.bodyFatPercentage)
                    Text("FFMI").tag(DatedOutcome.Metric.ffmi)
                }
                TextField("Target", text: $valueText)
                    .accessibilityIdentifier("launch_outcome_value")
                TextField("Date (YYYY-MM-DD)", text: $dateText)
                    .accessibilityIdentifier("launch_outcome_date")
                Text(LaunchPromiseCopy.framing)
                    .font(.footnote)
                if let errorText {
                    Text(errorText)
                }
            }
            .navigationTitle("Outcome and date")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("launch_outcome_save")
                }
            }
        }
    }

    private func save() {
        guard let value = Double(valueText), value.isFinite, value > 0 else {
            onSave(invalidAttempt())
            return
        }
        var outcome = existing ?? DatedOutcome(
            outcome: .init(metric: metric, targetValue: value),
            outcomeDate: dateText
        )
        outcome.outcome.metric = metric
        outcome.outcome.targetValue = value
        outcome.outcomeDate = dateText
        onSave(outcome)
    }

    private func invalidAttempt() -> DatedOutcome {
        var outcome = existing ?? DatedOutcome(
            outcome: .init(metric: metric, targetValue: 0),
            outcomeDate: dateText
        )
        outcome.outcomeDate = dateText
        outcome.outcome.targetValue = Double(valueText) ?? .nan
        return outcome
    }
}

private func existingValue(_ outcome: DatedOutcome) -> Double {
    outcome.outcome.targetValue
}

extension DashboardViewLiquid {
    var isLaunchJourneyEnabled: Bool {
        _ = featureGateRefreshToken
        return LaunchJourney.isEnabled()
    }

    var homeChatDraftBinding: Binding<String> {
        let ownership = authManager.captureAccountSession()
        return AccountSessionChatDraft.binding(storage: $homeChatDraft, owner: ownership) {
            guard let ownership else { return false }
            return authManager.ownsAccountSession(ownership)
        }
    }

    var launchJourneyDirective: some View {
        LaunchDirectiveCard(
            presentation: launchJourneyPresentation,
            note: launchHoldNote,
            onAction: { performLaunchNextAction(launchJourneyPresentation) }
        )
        .padding(.horizontal, JovieTokens.screenInset)
        .padding(.top, 8)
        .sheet(isPresented: $showsLaunchOutcomeEditor) {
            launchJourneyOutcomeEditor
        }
    }

    var launchJourneyOutcomeEditor: some View {
        LaunchOutcomeEditor(
            existing: (try? realtimeSyncManager.datedOutcomeStore.load())?.value,
            errorText: launchOutcomeError
        ) { outcome in
            do {
                try realtimeSyncManager.datedOutcomeStore.save(outcome)
                launchOutcomeError = nil
                showsLaunchOutcomeEditor = false
            } catch {
                launchOutcomeError = "That outcome could not be saved. Revise the date or value."
            }
        }
    }

    var launchJourneyPresentation: LaunchJourney.Presentation {
        let surface: LaunchJourney.Surface
        if isHomeChatExpanded || selectedPhotoTimelineRootPage == .chat {
            surface = .coach
        } else if selectedPhotoTimelineRootPage == .analytics {
            surface = .stats
        } else {
            surface = .timeline
        }
        let snapshot = try? realtimeSyncManager.datedOutcomeStore.load()
        let input = LaunchJourney.Input(
            now: Date(),
            outcome: snapshot?.value,
            readings: launchJourneyReadings(),
            offline: !realtimeSyncManager.isOnline,
            permissionDenied: false,
            safetyAvailable: true,
            freshnessWindow: nil,
            thresholds: [:],
            safeWeeklyChangeKg: nil,
            glp1Disclosed: false,
            dexaPresent: bodyMetrics.contains { metric in
                let source = (metric.dataSource ?? "").lowercased()
                return source.contains("dexa") || (metric.bodyFatMethod ?? "").lowercased().contains("dexa")
            }
        )
        return LaunchJourney.presentations(for: input).first { $0.surface == surface }
            ?? LaunchJourney.presentations(for: input)[0]
    }

    func performLaunchNextAction(_ presentation: LaunchJourney.Presentation) {
        switch presentation.action.title {
        case "Retry sync":
            launchHoldNote = nil
            realtimeSyncManager.syncAll()
        case "Enter one measurement", "Add one measurement", "Record a fresh measurement", "Record one new measurement":
            launchHoldNote = nil
            presentAddEntrySheet()
        case "Hold the plan", "Hold this maintenance interval", "Review progress":
            launchHoldNote = presentation.action.detail
        default:
            launchHoldNote = nil
            showsLaunchOutcomeEditor = true
        }
    }

    private func launchJourneyReadings() -> [LaunchJourney.Reading] {
        bodyMetrics.flatMap { metric -> [LaunchJourney.Reading] in
            guard !metric.isExcluded else { return [] }
            var readings: [LaunchJourney.Reading] = []
            if let weight = metric.weight, weight.isFinite, weight > 0 {
                let unit = metric.weightUnit?.lowercased()
                let kilograms = unit == "lbs" || unit == "lb" ? UnitConversion.lbsToKg(weight) : weight
                readings.append(.init(date: metric.date, metric: .weightKg, value: kilograms))
            }
            if let bodyFat = metric.bodyFatPercentage, bodyFat.isFinite, bodyFat > 0 {
                readings.append(.init(date: metric.date, metric: .bodyFatPercentage, value: bodyFat))
            }
            return readings
        }
    }
}
