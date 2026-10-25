import SwiftUI

struct TrainingCycleReviewView: View {
    let accessToken: () async -> String?
    let isCurrent: () -> Bool
    let onApplied: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var context: TrainingRevisionContextResponse?
    @State private var weekCount = 4
    @State private var sessionsPerWeek = 2
    @State private var equipment = "dumbbells"
    @State private var adultConfirmed = false
    @State private var safetyConfirmed = false
    @State private var renewTemporaryPreferences = false
    @State private var selectedVariants: [String: TrainingRetainedVariant] = [:]
    @State private var reason = "Review my training block"
    @State private var proposal: TrainingCycleProposal?
    @State private var requestId = UUID().uuidString
    @State private var decisionId = UUID().uuidString
    @State private var busy = false
    @State private var errorMessage: String?
    var service: any TrainingCycleReviewServicing = URLSessionTrainingService()

    private var isRepeat: Bool { context?.cycle?.phase == "review" }
    private var isEnrollment: Bool { context?.cycle == nil }

    var body: some View {
        NavigationStack {
            Form {
                if let proposal {
                    draft(proposal)
                } else if context != nil {
                    configuration
                } else {
                    ProgressView("Loading block")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.appWarning)
                    Button("Reload") { Task { await load() } }
                }
            }
            .disabled(busy)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
            .navigationTitle(isRepeat ? "Next block" : isEnrollment ? "Training coach" : "Review block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(proposal == nil ? "Review draft" : "Apply") {
                        Task { await submit() }
                    }
                    .disabled(busy || context == nil || (isEnrollment && (!adultConfirmed || !safetyConfirmed)))
                    .accessibilityIdentifier("training_cycle_review_confirm")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("Close") { dismiss() }
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(busy)
                    .accessibilityIdentifier("training_enroll_close_button")
                    .padding(.horizontal, JovieTokens.screenInset)
                    .padding(.vertical, JovieTokens.itemGap)
            }
            .task { await load() }
        }
    }

    @ViewBuilder private var configuration: some View {
        Section("Block length") {
            Picker("Weeks, including deload", selection: $weekCount) {
                ForEach(4...6, id: \.self) { Text("\($0) weeks").tag($0) }
            }.pickerStyle(.segmented)
                .accessibilityIdentifier("training_cycle_length")
            Text("The final week has fewer sets and more repetitions in reserve. Recovery check-ins still apply.")
                .font(.footnote)
            TextField("Reason", text: $reason)
        }
        if isEnrollment {
            Section("Schedule and safety") {
                Picker("Sessions each week", selection: $sessionsPerWeek) {
                    Text("2 days").tag(2)
                    Text("3 days").tag(3)
                }
                Picker("Equipment", selection: $equipment) {
                    Text("Dumbbells").tag("dumbbells")
                    Text("Full gym").tag("full_gym")
                }
                Toggle("I’m 18 or older.", isOn: $adultConfirmed)
                    .accessibilityIdentifier("training_cycle_adult_confirm")
                Toggle(
                    "I’m not pregnant or postpartum, have no eating-disorder risk, " +
                        "and have no medical restriction that makes this training unsafe.",
                    isOn: $safetyConfirmed
                )
                .accessibilityIdentifier("training_cycle_safety_confirm")
            }
        }
        if let cycle = context?.cycle {
            Section(isRepeat ? "Keep exercises that worked" : "Retained exercises") {
                ForEach(cycle.variants) { variant in
                    Toggle(variant.name ?? variant.toVariantId, isOn: Binding(
                        get: { selectedVariants[variant.fromExerciseId]?.toVariantId == variant.toVariantId },
                        set: { selectedVariants[variant.fromExerciseId] = $0 ? variant : nil }
                    ))
                    .accessibilityIdentifier("training_cycle_keep_" + variant.toVariantId)
                    Text(variant.reason).font(.caption)
                }
            }
            if isRepeat && (!cycle.priorities.isEmpty || !cycle.constraints.isEmpty) {
                Section("Temporary preferences") {
                    Toggle("Renew for the next block", isOn: $renewTemporaryPreferences)
                        .accessibilityIdentifier("training_cycle_renew_priorities")
                    ForEach(cycle.priorities, id: \.muscle) { Text("\($0.muscle): \($0.reason)") }
                    ForEach(cycle.constraints, id: \.id) { Text($0.reason) }
                }
            }
            Section {
                Text("Equipment and enduring exclusions stay in effect. " +
                    "History and feedback remain linked to their original exercises.")
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder private func draft(_ proposal: TrainingCycleProposal) -> some View {
        Section("Draft · week \(proposal.plan.week) of \(weekCount)") {
            Text(proposal.reason)
            ForEach(proposal.plan.sessions) { session in
                Text(session.title).font(.headline)
                ForEach(session.exercises) { exercise in
                    Text("\(exercise.name) · \(exercise.sets) sets · \(exercise.targetReps) reps · \(exercise.targetRir) RIR")
                }
            }
        }
        Section("Review") {
            ForEach(proposal.assumptions, id: \.self) { Text($0) }
            Button("Reject draft", role: .destructive) { Task { await decide("reject") } }
        }
    }

    private func token() async throws -> String {
        guard isCurrent(), let token = await accessToken(), isCurrent() else {
            throw TrainingServiceError.authenticationExpired
        }
        return token
    }

    private func load() async {
        busy = true
        defer { busy = false }
        do {
            let response = try await service.loadRevisionContext(accessToken: token())
            guard isCurrent() else { return }
            context = response
            weekCount = response.cycle?.weekCount ?? 4
            selectedVariants = Dictionary(
                (response.cycle?.retainedVariants ?? []).map { ($0.fromExerciseId, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            proposal = nil
            requestId = UUID().uuidString
            decisionId = UUID().uuidString
            errorMessage = nil
        } catch { if isCurrent() { errorMessage = error.localizedDescription } }
    }

    private func submit() async {
        if proposal != nil { await decide("apply"); return }
        guard let context else { return }
        busy = true
        defer { busy = false }
        var intent = TrainingCycleIntent(
            kind: isEnrollment ? "initial_enrollment" : isRepeat ? "repeat_cycle" : "revise_cycle",
            weekCount: weekCount
        )
        if isEnrollment {
            intent.adultConfirmed = adultConfirmed
            intent.safetyConfirmed = safetyConfirmed
            intent.sessionsPerWeek = sessionsPerWeek
            intent.equipment = equipment
        } else {
            intent.retainedVariants = selectedVariants.values.sorted { $0.fromExerciseId < $1.fromExerciseId }.map {
                TrainingRetainedVariant(fromExerciseId: $0.fromExerciseId, toVariantId: $0.toVariantId, reason: $0.reason)
            }
            if isRepeat {
                intent.priorities = renewTemporaryPreferences ? context.cycle?.priorities : []
                intent.constraints = renewTemporaryPreferences ? context.cycle?.constraints : []
            }
        }
        do {
            let response = try await service.proposeCycle(accessToken: token(), request: TrainingCycleProposalRequest(
                requestId: requestId, expectedGeneration: context.generation, intent: intent, reason: reason
            ))
            guard isCurrent() else { return }
            proposal = response.stored.proposal
            errorMessage = nil
        } catch { if isCurrent() { errorMessage = error.localizedDescription } }
    }

    private func decide(_ decision: String) async {
        guard let proposal else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await service.decideCycle(accessToken: token(), request: TrainingCycleDecisionRequest(
                requestId: decisionId, proposalId: proposal.id, decision: decision
            ))
            guard isCurrent() else { return }
            if decision == "apply" { await onApplied(); dismiss() } else { await load() }
        } catch { if isCurrent() { errorMessage = error.localizedDescription } }
    }
}
