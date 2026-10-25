import SwiftUI

enum DelegatedTrainingPolicy {
    static let featureGate = "delegated_programming_v1"
}

@MainActor
final class DelegatedTrainingModel: ObservableObject {
    @Published var context: TrainingPlanContext?
    @Published var inputs = TrainingPlanningInputs()
    @Published var proposal: TrainingPlanStoredProposal?
    @Published var message: String?
    @Published var busy = false
    private let service: DelegatedTrainingServicing
    private let accessToken: () async -> String?
    private let isCurrent: () -> Bool
    private var proposalRequestId = UUID().uuidString
    private var decisionRequestId = UUID().uuidString

    init(
        service: DelegatedTrainingServicing,
        initialProposal: TrainingPlanStoredProposal? = nil,
        accessToken: @escaping () async -> String?,
        isCurrent: @escaping () -> Bool
    ) {
        self.service = service
        self.proposal = initialProposal
        self.accessToken = accessToken
        self.isCurrent = isCurrent
    }

    func refresh() async {
        await perform { token in
            let loaded = try await self.service.planningContext(accessToken: token)
            guard self.isCurrent() else { throw TrainingServiceError.authenticationExpired }
            guard loaded.delegatedProgramming == true else { throw TrainingServiceError.server(code: "not_found") }
            self.context = loaded
            self.inputs = loaded.knownInputs ?? TrainingPlanningInputs()
            self.proposal = loaded.pendingProposal
        }
    }

    func inputsChanged() {
        proposalRequestId = UUID().uuidString
    }

    func propose(utterance: String? = nil, restoreRevision: String? = nil) async {
        guard let context else { return }
        let request = TrainingPlanProposalRequest(
            requestId: proposalRequestId, expectedGeneration: context.generation,
            reason: utterance ?? (restoreRevision == nil
                ? "Recommend a safe starting program from my known inputs."
                : "Restore an allowed prior program."),
            intent: restoreRevision.map { .init(kind: "restore", revisionId: $0) } ?? (utterance == nil ? .init(
                kind: "recommend", inputs: inputs, adultConfirmed: true, safetyConfirmed: true
            ) : nil),
            utterance: utterance,
            baseProposalId: utterance != nil && proposal?.status == "proposed" ? proposal?.proposal.id : nil
        )
        await perform { token in
            let response = try await self.service.proposePlan(accessToken: token, request: request)
            guard self.isCurrent() else { throw TrainingServiceError.authenticationExpired }
            self.proposal = response.stored
            self.message = response.question
            self.decisionRequestId = UUID().uuidString
        }
    }

    func adjustCard(utterance: String) async {
        let reference: TrainingCardReference
        if let proposal {
            reference = proposal.cardReference
        } else if let revision = context?.currentSetup?.programRevisionId,
                  let plan = context?.currentSetup?.delegated?.plan {
            reference = TrainingCardReference(component: .mesoPlan, objectId: revision, revision: plan.revision)
        } else { return }
        do {
            try TrainingCardAdapter.authorize(
                TrainingCardAction(reference: reference, name: .adjust),
                current: reference, ownsSession: isCurrent(), canWrite: !busy
            )
            await propose(utterance: utterance)
        } catch { message = "Refresh the saved plan before adjusting it." }
    }

    func decideCard(_ action: TrainingCardAction) async -> Bool {
        guard let proposal else { return false }
        do {
            try TrainingCardAdapter.authorize(
                action, current: proposal.cardReference, ownsSession: isCurrent(),
                canWrite: proposal.status == "proposed" && !busy
            )
            guard action.name == .apply || action.name == .reject else {
                throw TrainingCardContractError.unsupportedAction
            }
            let applied = await decide(action.name.rawValue)
            if applied && context?.currentSetup?.delegated?.plan != proposal.proposal.plan {
                message = "The saved program does not match the reviewed draft. Refresh before starting."
                return false
            }
            return applied
        } catch {
            message = "This card changed or is unavailable. Refresh the plan before trying again."
            return false
        }
    }

    func decide(_ decision: String) async -> Bool {
        guard ["apply", "reject"].contains(decision),
              let proposal, proposal.status == "proposed" else { return false }
        var applied = false
        await perform { token in
            let response = try await self.service.decidePlan(accessToken: token, request: .init(
                requestId: self.decisionRequestId, proposalId: proposal.proposal.id, decision: decision
            ))
            guard self.isCurrent() else { throw TrainingServiceError.authenticationExpired }
            guard response.receipt.proposalId == proposal.proposal.id,
                  response.receipt.requestId == self.decisionRequestId,
                  response.receipt.status == (decision == "apply" ? "applied" : "rejected") else {
                throw TrainingServiceError.invalidResponse
            }
            let loaded = try await self.service.planningContext(accessToken: token)
            guard self.isCurrent() else { throw TrainingServiceError.authenticationExpired }
            if decision == "apply" {
                guard response.receipt.status == "applied",
                      let revision = response.receipt.revisionId,
                      loaded.currentSetup?.programRevisionId == revision else {
                    throw TrainingServiceError.invalidResponse
                }
                applied = true
            }
            self.context = loaded
            self.proposal = nil
            self.message = decision == "reject" ? "Draft declined. Your saved plan is unchanged." : nil
            self.proposalRequestId = UUID().uuidString
        }
        return applied
    }

    private func perform(_ action: (String) async throws -> Void) async {
        guard !busy, isCurrent() else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            guard let token = await accessToken(), isCurrent() else {
                throw TrainingServiceError.authenticationExpired
            }
            try await action(token)
        } catch {
            guard isCurrent() else { return }
            message = error.localizedDescription
        }
    }
}

struct DelegatedTrainingView: View {
    var cardsEnabled = false
    @StateObject private var model: DelegatedTrainingModel
    @Environment(\.dismiss) private var dismiss
    @State private var adultConfirmed = false
    @State private var safetyConfirmed = false
    @State private var steering = ""
    @State private var hasGoalDate = false
    @State private var goalDate = Date()
    let onApplied: () async -> Void

    init(
        initialProposal: TrainingPlanStoredProposal? = nil,
        cardsEnabled: Bool = false,
        accessToken: @escaping () async -> String?,
        isCurrent: @escaping () -> Bool,
        onApplied: @escaping () async -> Void
    ) {
        _model = StateObject(wrappedValue: DelegatedTrainingModel(
            service: URLSessionTrainingService(), initialProposal: initialProposal,
            accessToken: accessToken, isCurrent: isCurrent
        ))
        self.cardsEnabled = cardsEnabled
        self.onApplied = onApplied
    }

    var body: some View {
        NavigationStack {
            Form {
                if let proposal = model.proposal {
                    review(proposal)
                } else if let plan = model.context?.currentSetup?.delegated?.plan {
                    planSections(plan)
                    steeringSection
                } else if model.context != nil {
                    firstRunInputs
                    safetySection
                    Button("Recommend my plan") { Task { await model.propose() } }
                        .disabled(model.busy || !adultConfirmed || !safetyConfirmed)
                        .accessibilityIdentifier("training_recommend_plan")
                } else {
                    ProgressView("Loading known training information")
                }
                if let message = model.message {
                    Section { Text(message).accessibilityIdentifier("training_plan_message") }
                    Button("Refresh plan") { Task { await model.refresh() } }
                }
                if let history = model.context?.history, !history.isEmpty {
                    Section {
                        DisclosureGroup("Why your plan changed") {
                            ForEach(history) { revision in
                                Text(revision.reason)
                                ForEach(revision.summary, id: \.self) { Text($0).font(.footnote) }
                                Button("Review restoring this plan") {
                                    model.inputsChanged()
                                    Task { await model.propose(restoreRevision: revision.revisionId) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(model.proposal?.proposal.transition == nil ? "Your training plan" : "Next block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .disabled(model.busy)
            .task { await model.refresh() }
            .onChange(of: model.inputs) { _, _ in model.inputsChanged() }
            .onChange(of: steering) { _, _ in model.inputsChanged() }
        }
    }

    @ViewBuilder private var firstRunInputs: some View {
        Section("LYB builds your plan") {
            Text("Share what matters. LYB recommends one draft; you review and steer.")
            if model.context?.knownInputs?.goal == nil {
                TextField("Training outcome", text: Binding(
                    get: { model.inputs.goal ?? "" }, set: { model.inputs.goal = $0 }
                ))
            }
            if model.context?.knownInputs?.goalDate == nil {
                Toggle("I have a goal date", isOn: $hasGoalDate)
                    .onChange(of: hasGoalDate) { _, value in
                        model.inputs.goalDate = value ? ISO8601DateFormatter().string(from: goalDate) : nil
                    }
                if hasGoalDate {
                    DatePicker("Goal date", selection: $goalDate, displayedComponents: .date)
                        .onChange(of: goalDate) { _, value in
                            model.inputs.goalDate = ISO8601DateFormatter().string(from: value)
                        }
                }
            }
            if model.context?.knownInputs?.experience == nil {
                Picker("Experience", selection: $model.inputs.experience) {
                    Text("Choose").tag(Optional<String>.none)
                    Text("New to training").tag(Optional("new"))
                    Text("Returning").tag(Optional("returning"))
                    Text("Training regularly").tag(Optional("experienced"))
                }
            }
            scheduleInputs
        }
        constraintsSection
    }

    @ViewBuilder private var scheduleInputs: some View {
        if model.context?.knownInputs?.sessionsPerWeek == nil {
            Picker("Days each week", selection: $model.inputs.sessionsPerWeek) {
                Text("Choose").tag(Optional<Int>.none)
                ForEach(2...6, id: \.self) { Text("\($0)").tag(Optional($0)) }
            }
        }
        if model.context?.knownInputs?.minutesPerSession == nil {
            Picker("Minutes per session", selection: $model.inputs.minutesPerSession) {
                Text("Choose").tag(Optional<Int>.none)
                ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { Text("\($0)").tag(Optional($0)) }
            }
        }
        if model.context?.knownInputs?.equipment == nil {
            Picker("Equipment", selection: $model.inputs.equipment) {
                Text("Choose").tag(Optional<String>.none)
                Text("Dumbbells").tag(Optional("dumbbells"))
                Text("Full gym").tag(Optional("full_gym"))
            }
        }
    }

    @ViewBuilder private var constraintsSection: some View {
        if model.context?.knownInputs?.excludedVariantIds == nil {
            Section("Durable movement exclusions") {
                Button("No movements to exclude") { model.inputs.excludedVariantIds = [] }
                DisclosureGroup("Choose movements to exclude") {
                    ForEach(model.context?.movements ?? []) { movement in
                        Toggle(movement.name, isOn: selection(movement.id, key: \.excludedVariantIds))
                    }
                }
            }
        }
        if model.context?.knownInputs?.limitations == nil {
            Section("Known limitations") {
                Button("No known limitations") { model.inputs.limitations = [] }
                ForEach(model.context?.limitations ?? [], id: \.self) { limitation in
                    Toggle(limitation.replacingOccurrences(of: "_", with: " ").capitalized,
                           isOn: selection(limitation, key: \.limitations))
                }
                Text("For other restrictions, get qualified review before starting. LYB cannot clear a medical restriction.")
            }
        }
    }

    private func selection(_ value: String, key: WritableKeyPath<TrainingPlanningInputs, [String]?>) -> Binding<Bool> {
        Binding(get: { model.inputs[keyPath: key]?.contains(value) == true }, set: { selected in
            var values = model.inputs[keyPath: key] ?? []
            values.removeAll { $0 == value }
            if selected { values.append(value) }
            model.inputs[keyPath: key] = values
        })
    }

    private var safetySection: some View {
        Section("Safety") {
            Toggle("I’m 18 or older.", isOn: $adultConfirmed)
            Toggle(
                "I’m not pregnant or postpartum, have no eating-disorder risk, " +
                    "and no medical restriction that makes this training unsafe.",
                isOn: $safetyConfirmed
            )
        }
    }

    @ViewBuilder private func review(_ stored: TrainingPlanStoredProposal) -> some View {
        if cardsEnabled {
            Section {
                PlanChangeCard(stored: stored, busy: model.busy) { action in
                    Task {
                        if await model.decideCard(action) { await onApplied(); dismiss() }
                    }
                }
            }
        }
        Section(stored.status == "proposed" ? "Recommended draft" : "Draft status: \(stored.status)") {
            Text(stored.proposal.reason)
            Text("Proposed by \(stored.proposal.actor.kind)")
            ForEach(stored.proposal.summary, id: \.self) { Text($0) }
        }
        if let transition = stored.proposal.transition {
            Section("Staying") { ForEach(transition.staying, id: \.self) { Text($0) } }
            Section("Changing") { ForEach(transition.changing, id: \.self) { Text($0) }; Text(transition.why) }
            if !transition.expiring.isEmpty {
                Section("Expiring priorities") { Text(transition.expiring.joined(separator: ", ")) }
            }
        }
        planSections(stored.proposal.plan)
        Section("Assumptions") { ForEach(stored.proposal.assumptions, id: \.self) { Text($0) } }
        if stored.status == "proposed" && !cardsEnabled {
            Button(stored.proposal.transition == nil ? "Start program" : "Start next block") {
                Task {
                    if await model.decide("apply") { await onApplied(); dismiss() }
                }
            }
            .accessibilityIdentifier("training_apply_recommended_plan")
            Button("Decline draft", role: .destructive) { Task { _ = await model.decide("reject") } }
        }
        // Steering always targets the canonical saved program; the returned diff
        // is reviewed before apply, including when a next-block preview is open.
        steeringSection
    }

    private func planSections(_ plan: CanvasPlan) -> some View {
        ForEach(plan.sessions) { session in
            Section(session.title) {
                ForEach(session.exercises) { exercise in
                    Text("\(exercise.name) · \(exercise.sets) × \(exercise.targetReps)")
                }
            }
        }
    }

    private var steeringSection: some View {
        Section("Steer your plan") {
            TextField("Keep cable curls, prioritize biceps…", text: $steering)
            Text("Kept movements and exclusions persist. Muscle priorities last for this block.")
                .font(.footnote)
            Button("Review changes") {
                Task {
                    if cardsEnabled { await model.adjustCard(utterance: steering) }
                    else { await model.propose(utterance: steering) }
                }
            }
                .disabled(steering.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("training_review_steering")
        }
    }
}
