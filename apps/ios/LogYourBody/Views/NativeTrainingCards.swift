import SwiftUI

struct NativeTrainingCardSource {
    let response: TrainingNextResponse?
    let plan: CanvasPlan?
    let planRevisionId: String?
    let ownerSubject: String
    let transcriptText: String
}

struct NativeTrainingCardStatus {
    let isLoading: Bool
    let errorMessage: String?
    let chatBusy: Bool
}

struct NativeTrainingCardMutations {
    let apply: (String) async -> Void
    let reject: (String) async -> Void
    let adjust: (String, String) async -> Void
    let swap: (String, String, String) async -> Void
    let feedback: (String, String) async -> Void
}

struct NativeTrainingCardActions {
    let retry: () -> Void
    let openSession: (TrainingSession) -> Void
    let mutations: NativeTrainingCardMutations
}

struct NativeTrainingCardStack: View {
    let source: NativeTrainingCardSource
    let status: NativeTrainingCardStatus
    let actions: NativeTrainingCardActions
    @Environment(\.theme) private var theme
    @State private var pending = false
    @State private var showsWeek = false
    @State private var adjustment = ""

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            if status.isLoading && source.response == nil {
                ProgressView("Loading training")
                    .font(.subheadline)
                    .accessibilityIdentifier("native_training_loading")
            }
            if pending {
                ProgressView("Saving change")
                    .font(.subheadline)
                    .accessibilityIdentifier("native_training_pending")
            }
            if let message = status.errorMessage {
                VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityIdentifier("native_training_error")
                    Button("Retry training", action: actions.retry)
                        .frame(minHeight: JovieTokens.minimumHitTarget)
                        .accessibilityIdentifier("native_training_retry")
                }
            }
            if let session = source.response?.session, let workout = card("WorkoutSessionCard", id: session.id) {
                NativeWorkoutSessionCard(
                    session: session, card: workout, chatBusy: status.chatBusy,
                    offline: status.errorMessage != nil, onLog: { actions.openSession(session) }
                )
            }
            if let planCard = card("MesoPlanCard") {
                NativeMesoPlanCard(
                    response: source.response, plan: source.plan, card: planCard, showsWeek: $showsWeek
                )
            }
            if let proposal = source.response?.nextBlock,
               let change = card("PlanChangeCard", id: proposal.proposal.id) {
                NativePlanChangeCard(
                    proposal: proposal, card: change, adjustment: $adjustment, pending: pending,
                    handlers: NativePlanChangeHandlers(
                        apply: { run { await actions.mutations.apply(change.objectId) } },
                        reject: { run { await actions.mutations.reject(change.objectId) } },
                        adjust: { run { await actions.mutations.adjust(change.objectId, adjustment) } }
                    )
                )
            }
            if let session = source.response?.session, let swap = card("ExerciseSwapCard", id: session.id) {
                NativeExerciseSwapCard(session: session, card: swap, pending: pending) { exerciseId, variantId in
                    run { await actions.mutations.swap(session.id, exerciseId, variantId) }
                }
            }
            if let session = source.response?.session, let feedback = card("TrainingFeedbackCard", id: session.id) {
                NativeTrainingFeedbackCard(card: feedback, pending: pending) { performance in
                    run { await actions.mutations.feedback(session.id, performance) }
                }
            }
            if let session = source.response?.session, let review = card("ProgressReviewCard", id: session.id) {
                NativeProgressReviewCard(
                    session: session, decision: source.response?.decision, card: review
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native_training_card_stack")
    }

    private var cards: [ApprovedNativeTrainingCard] {
        NativeTrainingCardProjector.renderable(
            response: source.response, plan: source.plan, planRevisionId: source.planRevisionId,
            ownerSubject: source.ownerSubject, transcriptText: source.transcriptText
        )
    }

    private func card(_ component: String, id: String? = nil) -> ApprovedNativeTrainingCard? {
        cards.first { $0.component == component && (id == nil || $0.objectId == id) }
    }

    private func run(_ operation: @escaping () async -> Void) {
        guard !pending else { return }
        pending = true
        Task {
            await operation()
            pending = false
        }
    }
}

struct NativeWorkoutSessionCard: View {
    let session: TrainingSession
    let card: ApprovedNativeTrainingCard
    let chatBusy: Bool
    let offline: Bool
    let onLog: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Text(session.safetyStop ? "Pause for now" : session.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.colors.text)
            Text("Saved revision \(card.revision)")
                .font(.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("native_card_revision_WorkoutSessionCard")
            if let exercise = session.exercises.first {
                Text(exercise.name)
                    .font(.headline)
                Text(prescription(exercise))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let setup = exercise.loadInstruction {
                    Text(setup)
                        .font(.subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Text(previousPerformance(exercise))
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityIdentifier("native_workout_previous")
            }
            Button(action: onLog) {
                Text(session.safetyStop ? "Update recovery check-in" : "Log set")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: JovieTokens.controlHeight)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!NativeTrainingCardInteractionPolicy.loggingEnabled(chatBusy: chatBusy, offline: offline))
            .accessibilityIdentifier("native_workout_log")
        }
        .nativeTrainingCardChrome()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native_workout_session_card")
    }

    private func prescription(_ exercise: TrainingExercisePrescription) -> String {
        var text = "\(exercise.sets) sets · \(exercise.targetReps) reps "
        text += "(\(exercise.repRange.min)–\(exercise.repRange.max)) · \(exercise.targetRir) RIR"
        if let load = exercise.targetLoadKg { text += " · \(load.formatted()) kg" }
        return text
    }

    private func previousPerformance(_ exercise: TrainingExercisePrescription) -> String {
        guard let set = session.loggedSets?.last(where: { $0.exerciseId == exercise.id }) else {
            return "No recorded set yet."
        }
        let load = set.loadKg.map { "\($0.formatted()) kg" } ?? "bodyweight"
        let corrected = set.corrections?.isEmpty == false ? " · corrected" : ""
        return "Previous: \(set.reps) reps · \(load) · \(set.rir) RIR\(corrected)"
    }
}

struct NativeMesoPlanCard: View {
    let response: TrainingNextResponse?
    let plan: CanvasPlan?
    let card: ApprovedNativeTrainingCard
    @Binding var showsWeek: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Text(plan == nil ? "This session" : "Week plan")
                .font(.headline)
            Text("Saved revision \(card.revision)")
                .font(.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("native_card_revision_MesoPlanCard")
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(theme.colors.textSecondary)
            Button("Week plan") { showsWeek = true }
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .accessibilityIdentifier("native_plan_open_week")
        }
        .nativeTrainingCardChrome()
        .accessibilityIdentifier("native_meso_plan_card")
        .sheet(isPresented: $showsWeek) { weekSheet }
    }

    private var summary: String {
        if let plan { return "\(plan.sessions.count) sessions in this program" }
        if let week = response?.week, let count = response?.weekCount { return "Week \(week) of \(count)" }
        return "Engine session"
    }

    private var weekSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
                    if let plan {
                        ForEach(plan.sessions) { session in
                            Text(session.title).font(.headline)
                            ForEach(session.exercises) { exercise in
                                Text("\(exercise.name) · \(exercise.sets) sets · \(exercise.targetReps) reps")
                                    .font(.body)
                            }
                        }
                    } else if let session = response?.session {
                        Text(session.title).font(.headline)
                        ForEach(session.exercises) { exercise in
                            Text(detail(exercise)).font(.body)
                        }
                    }
                }
                .padding(JovieTokens.screenInset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Week plan")
            .toolbar {
                Button("Done") { showsWeek = false }
                    .accessibilityIdentifier("native_plan_week_done")
            }
        }
        .accessibilityIdentifier("native_plan_week_sheet")
    }

    private func detail(_ exercise: TrainingExercisePrescription) -> String {
        "\(exercise.name) · \(exercise.sets) sets · \(exercise.targetReps) reps · \(exercise.targetRir) RIR"
    }
}

struct NativePlanChangeHandlers {
    let apply: () -> Void
    let reject: () -> Void
    let adjust: () -> Void
}

struct NativePlanChangeCard: View {
    let proposal: TrainingPlanStoredProposal
    let card: ApprovedNativeTrainingCard
    @Binding var adjustment: String
    let pending: Bool
    let handlers: NativePlanChangeHandlers
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Text("Plan change")
                .font(.headline)
            Text("Saved revision \(card.revision)")
                .font(.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("native_card_revision_PlanChangeCard")
            if let transition = proposal.proposal.transition {
                Text(transition.why).font(.body)
                changeList("Staying", transition.staying)
                changeList("Changing", transition.changing)
                changeList("Expiring", transition.expiring)
            }
            if !proposal.proposal.assumptions.isEmpty {
                changeList("Reasons", proposal.proposal.assumptions)
            }
            ForEach(Array(proposal.proposal.summary.enumerated()), id: \.offset) { _, line in
                Text(line).font(.subheadline)
            }
            TextField("What should change?", text: $adjustment)
                .font(.body)
                .frame(minHeight: JovieTokens.minimumHitTarget)
                .accessibilityIdentifier("native_plan_adjust_note")
            planButton("Apply", identifier: "native_plan_apply", action: handlers.apply)
            planButton(
                "Adjust", identifier: "native_plan_adjust",
                enabled: NativeTrainingCardDispatch.adjustmentUtteranceIsValid(adjustment),
                action: handlers.adjust
            )
            planButton("Reject", identifier: "native_plan_reject", action: handlers.reject)
        }
        .nativeTrainingCardChrome()
        .accessibilityIdentifier("native_plan_change_card")
    }

    private func changeList(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
            if !lines.isEmpty {
                Text(title).font(.subheadline.weight(.semibold))
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.subheadline)
                }
            }
        }
        .accessibilityIdentifier("native_plan_diff_\(title.lowercased())")
    }

    private func planButton(
        _ title: String, identifier: String, enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        let writesEnabled = NativeTrainingCardInteractionPolicy.planWriteEnabled(pending: pending)
        return Button(title, action: action)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: JovieTokens.controlHeight)
            .disabled(!enabled || !writesEnabled)
            .accessibilityIdentifier(identifier)
    }
}

struct NativeExerciseSwapCard: View {
    let session: TrainingSession
    let card: ApprovedNativeTrainingCard
    let pending: Bool
    let onSelect: (String, String) -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Text("Swap one movement")
                .font(.headline)
            Text("Saved revision \(card.revision)")
                .font(.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("native_card_revision_ExerciseSwapCard")
            Text("Replaces this movement only. The rest of the plan stays.")
                .font(.subheadline)
                .foregroundStyle(theme.colors.textSecondary)
            ForEach(session.exercises) { exercise in
                if let alternatives = exercise.substitutions, !alternatives.isEmpty,
                   card.actions.contains(where: { $0.kind == "select_swap" }) {
                    Text(exercise.name).font(.body.weight(.semibold))
                    ForEach(alternatives) { alternative in
                        VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
                            Text(alternative.name).font(.body)
                            ForEach(
                                NativeTrainingCardProjector.tradeoffs(current: exercise, alternative: alternative),
                                id: \.self
                            ) { line in
                                Text(line).font(.footnote).foregroundStyle(theme.colors.textSecondary)
                            }
                            Button("Use \(alternative.name)") {
                                onSelect(exercise.id, alternative.id)
                            }
                            .frame(minHeight: JovieTokens.minimumHitTarget)
                            .disabled(!NativeTrainingCardInteractionPolicy.planWriteEnabled(pending: pending))
                            .accessibilityIdentifier("native_swap_\(alternative.id)")
                        }
                    }
                }
            }
        }
        .nativeTrainingCardChrome()
        .accessibilityIdentifier("native_exercise_swap_card")
    }
}

struct NativeTrainingFeedbackCard: View {
    let card: ApprovedNativeTrainingCard
    let pending: Bool
    let onSubmit: (String) -> Void
    @State private var performance = "stable"
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Text("Session check-in")
                .font(.headline)
            Text("A short report for this session. It is separate from the progress review.")
                .font(.subheadline)
            Picker("Reported performance", selection: $performance) {
                Text("Up").tag("up")
                Text("Stable").tag("stable")
                Text("Down").tag("down")
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("native_feedback_performance")
            Button("Save check-in") { onSubmit(performance) }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: JovieTokens.controlHeight)
                .disabled(!NativeTrainingCardInteractionPolicy.planWriteEnabled(pending: pending))
                .accessibilityIdentifier("native_feedback_save")
            Text("Saved revision \(card.revision)")
                .font(.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("native_card_revision_TrainingFeedbackCard")
        }
        .foregroundStyle(theme.colors.text)
        .nativeTrainingCardChrome()
        .accessibilityIdentifier("native_training_feedback_card")
    }
}

struct NativeProgressReviewCard: View {
    let session: TrainingSession
    let decision: TrainingProgressDecision?
    let card: ApprovedNativeTrainingCard
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Text("Progress review")
                .font(.headline)
            Text("Saved revision \(card.revision)")
                .font(.footnote)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("native_card_revision_ProgressReviewCard")
            if let sets = session.loggedSets, !sets.isEmpty {
                ForEach(Array(sets.enumerated()), id: \.offset) { _, set in
                    Text(recorded(set)).font(.subheadline)
                }
                if let decision, decision.hasMeaningfulChange {
                    Text("Before: \(decision.before)")
                    Text("Next: \(decision.after)")
                    Text(decision.rationale)
                        .accessibilityIdentifier("native_review_reason")
                    if decision.decision.requiresConfirmation == true {
                        Text("Proposed change · confirmation required")
                    }
                } else {
                    Text("The engine did not propose a change.")
                }
            } else {
                Text("Recorded results will appear after you log a set.")
            }
        }
        .font(.subheadline)
        .foregroundStyle(theme.colors.text)
        .nativeTrainingCardChrome()
        .accessibilityIdentifier("native_progress_review_card")
    }

    private func recorded(_ set: TrainingSavedSet) -> String {
        let name = session.exercises.first { $0.id == set.exerciseId }?.name ?? "Movement"
        let load = set.loadKg.map { "\($0.formatted()) kg" } ?? "bodyweight"
        return "\(name): \(set.reps) reps · \(load) · \(set.rir) RIR"
    }
}

private extension View {
    func nativeTrainingCardChrome() -> some View {
        modifier(NativeTrainingCardChrome())
    }
}

private struct NativeTrainingCardChrome: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(JovieTokens.compactInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                theme.colors.surface,
                in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous)
            )
    }
}
