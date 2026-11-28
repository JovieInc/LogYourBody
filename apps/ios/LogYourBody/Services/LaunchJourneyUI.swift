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
    @Environment(\.dismiss) private var dismiss
    var existing: DatedOutcome?
    var errorText: String?
    var isSaving = false
    var includesDatedControls = false
    var allowsMaintenance = false
    var onSave: (DatedOutcome) -> Void

    @State private var metric: DatedOutcome.Metric
    @State private var valueText: String
    @State private var dateText: String
    @State private var constraints: DatedOutcome.Constraints
    @State private var sessionsText: String
    @State private var minutesText: String
    @State private var isPreparingSave = false

    init(
        existing: DatedOutcome?, errorText: String?, isSaving: Bool = false, includesDatedControls: Bool = false,
        allowsMaintenance: Bool = false,
        onSave: @escaping (DatedOutcome) -> Void
    ) {
        self.existing = existing
        self.errorText = errorText
        self.onSave = onSave
        self.isSaving = isSaving
        self.includesDatedControls = includesDatedControls
        self.allowsMaintenance = allowsMaintenance
        _metric = State(initialValue: existing?.outcome.metric ?? .weightKg)
        _valueText = State(initialValue: existing.map { String(existingValue($0)) } ?? "")
        _dateText = State(initialValue: existing?.outcomeDate ?? "")
        _constraints = State(initialValue: existing?.constraints ?? .init())
        _sessionsText = State(initialValue: existing?.constraints.availability.sessionsPerWeek.map(String.init) ?? "")
        _minutesText = State(initialValue: existing?.constraints.availability.minutesPerSession.map(String.init) ?? "")
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
                if includesDatedControls {
                    Section("Availability (optional)") {
                        TextField("Sessions per week", text: $sessionsText)
                            .keyboardType(.numberPad)
                        TextField("Minutes per session", text: $minutesText)
                            .keyboardType(.numberPad)
                    }
                    intervalSection("Travel", intervals: $constraints.travel)
                    if !allowsMaintenance {
                        intervalSection("Maintenance", intervals: $constraints.maintenance)
                    }
                }
                if allowsMaintenance {
                    Toggle("Maintenance interval", isOn: Binding(
                        get: { !constraints.maintenance.isEmpty },
                        set: { enabled in
                            constraints.maintenance = enabled ? [.init(start: "", end: "")] : []
                        }
                    ))
                    .accessibilityIdentifier("launch_outcome_maintenance")
                    if !constraints.maintenance.isEmpty {
                        intervalSection("Maintenance", intervals: $constraints.maintenance)
                    }
                }
                Text(LaunchPromiseCopy.framing)
                    .font(.footnote)
                if let errorText {
                    Text(errorText)
                }
            }
            .disabled(isSaving || isPreparingSave)
            .navigationTitle("Outcome and date")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || isPreparingSave)
                        .accessibilityIdentifier("launch_outcome_save")
                }
                if includesDatedControls || allowsMaintenance {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSaving || isPreparingSave)
                            .accessibilityIdentifier("launch_outcome_cancel")
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving || isPreparingSave)
    }

    private func intervalSection(_ title: String, intervals: Binding<[DatedOutcome.Interval]>) -> some View {
        Section("\(title) (optional)") {
            ForEach(intervals.wrappedValue.indices, id: \.self) { index in
                VStack {
                    TextField("Start (YYYY-MM-DD)", text: intervals[index].start)
                        .accessibilityIdentifier(title == "Maintenance" && index == 0 ? "launch_maintenance_start" : "")
                    TextField("End (YYYY-MM-DD)", text: intervals[index].end)
                        .accessibilityIdentifier(title == "Maintenance" && index == 0 ? "launch_maintenance_end" : "")
                }
            }
            .onDelete { intervals.wrappedValue.remove(atOffsets: $0) }
            Button("Add \(title.lowercased()) interval") {
                intervals.wrappedValue.append(.init(start: "", end: ""))
            }
        }
    }

    private func save() {
        guard !isSaving, !isPreparingSave else { return }
        let draft = DatedOutcomeEditorDraft(
            metric: metric, targetText: valueText, dateText: dateText, constraints: constraints,
            sessionsText: includesDatedControls ? sessionsText : nil,
            minutesText: includesDatedControls ? minutesText : nil
        )
        isPreparingSave = true
        Task {
            let value = await Task.detached { draft.resolve() }.value
            isPreparingSave = false
            onSave(value)
        }
    }
}

private func existingValue(_ outcome: DatedOutcome) -> Double {
    outcome.outcome.targetValue
}

/// Shared contextual editor for first launch, timeline and settings. All journal
/// work suspends on the store's private context; the opening session is frozen.
struct DatedOutcomeEditorHost: View {
    @Environment(\.dismiss) private var dismiss
    let auth: AuthManager
    let owner: AuthManager.ProfileSessionOwnership
    var onSaved: () -> Void
    @State private var model: DatedOutcomeEditorModel

    init(store: DatedOutcomeStore, auth: AuthManager, owner: AuthManager.ProfileSessionOwnership, onSaved: @escaping () -> Void) {
        self.auth = auth
        self.owner = owner
        self.onSaved = onSaved
        _model = State(initialValue: DatedOutcomeEditorModel(store: store) { auth.ownsAccountSession(owner) })
    }

    var body: some View {
        Group {
            if auth.ownsAccountSession(owner), model.isPresentationCurrent {
                if model.isLoaded {
                    editor
                } else {
                    VStack(spacing: 16) {
                        if let error = model.errorText {
                            Text(error)
                            Button("Retry") { Task { await model.load() } }
                        } else {
                            ProgressView()
                        }
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("launch_outcome_cancel")
                    }
                }
            } else {
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("launch_outcome_cancel")
            }
        }
        .task { await model.load() }
    }

    private var editor: some View {
        VStack(spacing: 8) {
            if model.store.syncIssue == .conflict || model.hasLocalConflict {
                reconciliation
            }
            LaunchOutcomeEditor(
                existing: existingOutcome, errorText: model.errorText,
                isSaving: model.isSaving, includesDatedControls: true, allowsMaintenance: true
            ) { value in
                Task { if await model.save(value) { onSaved() } }
            }
        }
    }

    private var existingOutcome: DatedOutcome? {
        #if DEBUG
        return DatedStatsUITestFixture.editorOutcome(saved: model.snapshot?.value)
        #else
        return model.snapshot?.value
        #endif
    }

    private var reconciliation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("A different outcome has been saved. Your input is kept here.")
                Button(model.hasLocalConflict ? "Review saved outcome" : "Review account outcome") {
                    Task { await model.reviewAccountValue(fetch: fetchAccountValue) }
                }
                if let account = model.accountValue {
                    Text("Saved target: \(account.value.outcome.targetValue.formatted()) · \(account.value.outcomeDate)")
                    Button(model.hasLocalConflict ? "Use saved outcome and discard draft"
                        : "Use account outcome and discard device edit") {
                        Task { if await model.useAccountValue() { onSaved() } }
                    }
                    .disabled(model.isSaving)
                }
            }
        }
        .frame(maxHeight: 160)
        .padding(.horizontal, JovieTokens.screenInset)
    }

    private func fetchAccountValue() async throws -> DatedOutcomeSnapshot? {
        guard auth.ownsAccountSession(owner), let request = auth.captureRequestSession(),
              let authorization = await auth.getAccessToken(for: request), auth.ownsAccountSession(owner) else {
            throw DatedOutcomeError.unauthenticated
        }
        let value = try await ProductAPIClient.shared.fetchDatedOutcome(token: authorization.token)
        guard auth.ownsAccountSession(owner) else { throw DatedOutcomeError.unauthenticated }
        return value
    }
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
