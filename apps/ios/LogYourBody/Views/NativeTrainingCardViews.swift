import SwiftUI

/// Owned SwiftUI surfaces for the versioned training-card contract.
/// json-render is not a consumer, and these views never evaluate generated code.
struct NativeTrainingCardStack: View {
    let cards: [NativeTrainingCard]
    let phases: [String: NativeTrainingCardPhase]
    let exerciseIndexes: [String: Int]
    let ownerSubject: String
    let offline: Bool
    let weeklyProgram: [String]
    let showsStopCoaching: Bool
    let onStopCoaching: () -> Void
    let onAction: (NativeTrainingCard, AdmittedNativeTrainingAction) -> Void

    @Environment(\.theme) private var theme
    @State private var isStopConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(cards, id: \.identity) { card in
                cardView(card)
                    .id(card.identity)
            }
            if showsStopCoaching {
                Button("Stop coaching and delete training data", role: .destructive) {
                    isStopConfirmationPresented = true
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget, alignment: .leading)
                .buttonStyle(.plain)
                .accessibilityIdentifier("training_revoke_button")
            }
        }
        .alert(
            "Delete your training sessions, set logs, and feedback?",
            isPresented: $isStopConfirmationPresented
        ) {
            Button("Stop coaching and delete data", role: .destructive, action: onStopCoaching)
                .accessibilityIdentifier("training_revoke_confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("training_revoke_cancel")
        } message: {
            Text("This removes training records from your account. It does not delete your body-composition data or chat.")
        }
    }

    @ViewBuilder
    private func cardView(_ card: NativeTrainingCard) -> some View {
        switch card.properties {
        case .mesoPlan(let plan):
            NativePlanCard(
                card: card,
                title: plan.title,
                weekCount: plan.weekCount,
                weeks: plan.weeks,
                diff: plan.diff,
                reasons: plan.reasons,
                status: card.pendingProposalId == nil ? "saved" : "pending",
                weeklyProgram: weeklyProgram,
                writesDisabled: writesDisabled(card),
                phase: phases[card.identity] ?? .ready(receipt: nil),
                ownerSubject: ownerSubject,
                onAction: { onAction(card, $0) }
            )
        case .planChange(let change):
            NativePlanCard(
                card: card,
                title: "Plan change",
                weekCount: nil,
                weeks: [],
                diff: change.diff,
                reasons: [change.reason] + change.reasons,
                status: change.status,
                weeklyProgram: weeklyProgram,
                writesDisabled: writesDisabled(card),
                phase: phases[card.identity] ?? .ready(receipt: nil),
                ownerSubject: ownerSubject,
                onAction: { onAction(card, $0) }
            )
        case .workout(let workout):
            NativeWorkoutCard(
                card: card,
                title: workout.title,
                week: workout.week,
                exercises: workout.exercises,
                previous: workout.previous,
                index: exerciseIndexes[card.object.id] ?? 0,
                offline: offline,
                logDisabled: logDisabled(card),
                phase: phases[card.identity] ?? .ready(receipt: nil),
                ownerSubject: ownerSubject,
                onAction: { onAction(card, $0) }
            )
        case .swap(_, let exerciseId, let alternatives):
            NativeSwapCard(
                card: card,
                exerciseId: exerciseId,
                alternatives: alternatives,
                writesDisabled: writesDisabled(card),
                phase: phases[card.identity] ?? .ready(receipt: nil),
                ownerSubject: ownerSubject,
                onAction: { onAction(card, $0) }
            )
        case .feedback(_, let prompt):
            NativeFeedbackCard(
                card: card,
                prompt: prompt,
                writesDisabled: writesDisabled(card),
                phase: phases[card.identity] ?? .ready(receipt: nil),
                ownerSubject: ownerSubject,
                onAction: { onAction(card, $0) }
            )
        case .review(_, let citations, let proposedChange):
            NativeReviewCard(
                card: card,
                citations: citations,
                proposedChange: proposedChange,
                writesDisabled: writesDisabled(card),
                phase: phases[card.identity] ?? .ready(receipt: nil),
                ownerSubject: ownerSubject,
                onAction: { onAction(card, $0) }
            )
        }
    }

    private func writesDisabled(_ card: NativeTrainingCard) -> Bool {
        if offline { return true }
        switch phases[card.identity] {
        case .pending, .loading: return true
        default: return false
        }
    }

    private func logDisabled(_ card: NativeTrainingCard) -> Bool {
        switch phases[card.identity] {
        case .pending, .loading: return true
        default: return false
        }
    }
}

private struct NativePlanCard: View {
    let card: NativeTrainingCard
    let title: String
    let weekCount: Int?
    let weeks: [NativePlanWeek]
    let diff: [NativePlanDiff]
    let reasons: [String]
    let status: String
    let weeklyProgram: [String]
    let writesDisabled: Bool
    let phase: NativeTrainingCardPhase
    let ownerSubject: String
    let onAction: (AdmittedNativeTrainingAction) -> Void

    @Environment(\.theme) private var theme
    @State private var showsProgram = false
    @State private var adjustment = ""

    var body: some View {
        NativeCardChrome(identifier: "native_training_card_\(card.component)_\(card.object.id)") {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.colors.text)
                .accessibilityAddTraits(.isHeader)
            if let weekCount {
                Text("\(weekCount) weeks")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            Text(statusLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.colors.textSecondary)
            if let first = diff.first {
                Text("\(first.label): \(first.from) → \(first.to)")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let reason = reasons.first {
                Text(reason)
                    .font(.body)
                    .foregroundStyle(theme.colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            NativeCardPhaseLabel(card: card, phase: phase)
            Button("Weekly program") {
                if card.component == "MesoPlanCard" {
                    guard admit("expand_program") != nil else { return }
                }
                showsProgram = true
            }
            .buttonStyle(NativeCardActionStyle(filled: false))
            .accessibilityIdentifier("native_training_program_\(card.object.id)")
            if card.pendingProposalId != nil {
                NativeCardAction(title: "Apply", identifier: "native_training_apply_\(card.object.id)", filled: true) {
                    admit("apply_revision")
                }
                .disabled(writesDisabled)
                TextField("Adjustment", text: $adjustment, axis: .vertical)
                    .font(.body)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("native_training_adjust_field_\(card.object.id)")
                NativeCardAction(title: "Adjust", identifier: "native_training_adjust_\(card.object.id)", filled: false) {
                    admit("adjust_revision", payload: ["utterance": adjustment])
                }
                .disabled(writesDisabled)
                NativeCardAction(title: "Reject", identifier: "native_training_reject_\(card.object.id)", filled: false) {
                    admit("reject_revision")
                }
                .disabled(writesDisabled)
            }
        }
        .sheet(isPresented: $showsProgram) {
            NavigationStack {
                List {
                    if !weeklyProgram.isEmpty {
                        Section("This week") {
                            ForEach(weeklyProgram, id: \.self) { line in
                                Text(line).font(.body)
                            }
                        }
                    }
                    if !weeks.isEmpty {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            Section("Week \(week.week)") {
                                ForEach(week.sessions) { session in
                                    Text(session.title).font(.body)
                                }
                            }
                        }
                    }
                    if !diff.isEmpty {
                        Section("Engine diff") {
                            ForEach(Array(diff.enumerated()), id: \.offset) { _, item in
                                Text("\(item.label): \(item.from) → \(item.to)").font(.body)
                            }
                        }
                    }
                    if !reasons.isEmpty {
                        Section("Reasons") {
                            ForEach(reasons, id: \.self) { reason in
                                Text(reason).font(.body)
                            }
                        }
                    }
                }
                .navigationTitle("Weekly program")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showsProgram = false }
                            .accessibilityIdentifier("native_training_program_done")
                    }
                }
            }
            .accessibilityIdentifier("native_training_program_sheet")
        }
    }

    private var statusLabel: String {
        switch status {
        case "pending": "Waiting for your decision"
        case "applied": "Applied to your saved plan"
        case "rejected": "Declined. Your saved plan is unchanged."
        default: "Saved program"
        }
    }

    @discardableResult
    private func admit(_ action: String, payload: [String: Any] = [:]) -> AdmittedNativeTrainingAction? {
        switch NativeTrainingCardContract.admit(
            card: card, action: action, ownerSubject: ownerSubject, payload: payload
        ) {
        case .success(let admitted):
            onAction(admitted)
            return admitted
        case .failure:
            return nil
        }
    }
}

private struct NativeWorkoutCard: View {
    let card: NativeTrainingCard
    let title: String
    let week: Int
    let exercises: [NativeWorkoutExercise]
    let previous: [NativePreviousSet]
    let index: Int
    let offline: Bool
    let logDisabled: Bool
    let phase: NativeTrainingCardPhase
    let ownerSubject: String
    let onAction: (AdmittedNativeTrainingAction) -> Void

    @Environment(\.theme) private var theme
    @State private var reps = 8
    @State private var rir = 2
    @State private var loadText = ""
    @State private var inputMessage: String?
    @State private var showsAll = false
    @State private var seededIndex: Int?

    private var currentIndex: Int {
        exercises.indices.contains(index) ? index : 0
    }

    private var exercise: NativeWorkoutExercise? {
        exercises.indices.contains(currentIndex) ? exercises[currentIndex] : nil
    }

    var body: some View {
        NativeCardChrome(identifier: "native_training_card_WorkoutSessionCard_\(card.object.id)") {
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.colors.text)
            Text("Week \(week)")
                .font(.subheadline)
                .foregroundStyle(theme.colors.textSecondary)
            if let exercise {
                Text(exercise.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(theme.colors.text)
                Text(exercise.setup)
                    .font(.body)
                    .foregroundStyle(theme.colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("native_training_setup_\(exercise.id)")
                Text(prescription(exercise))
                    .font(.body)
                    .foregroundStyle(theme.colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("native_training_prescription_\(exercise.id)")
                if let prior = previous.first(where: { $0.exerciseId == exercise.id }) {
                    Text(previousLine(prior))
                        .font(.subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("native_training_previous_\(exercise.id)")
                }
                Stepper(value: $reps, in: 1...50) {
                    Text("Reps \(reps)").font(.body)
                }
                .accessibilityIdentifier("native_training_reps_\(exercise.id)")
                TextField("Load, kg", text: $loadText)
                    .font(.body)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("native_training_load_\(exercise.id)")
                    .accessibilityLabel("Load in kilograms")
                Stepper(value: $rir, in: 0...6) {
                    Text("RIR \(rir)").font(.body)
                }
                .accessibilityIdentifier("native_training_rir_\(exercise.id)")
                if let inputMessage {
                    Text(inputMessage)
                        .font(.subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                NativeCardPhaseLabel(card: card, phase: phase)
                if exercise.completedSets < exercise.sets {
                    NativeCardAction(
                        title: "Log set \(exercise.completedSets + 1)",
                        identifier: "native_training_log_set_\(card.object.id)",
                        filled: true
                    ) {
                        log(exercise)
                    }
                    .disabled(logDisabled)
                }
                if let prior = previous.first(where: { $0.exerciseId == exercise.id }), prior.revision != nil {
                    NativeCardAction(
                        title: "Correct set \(prior.setNumber)",
                        identifier: "native_training_correct_set_\(card.object.id)",
                        filled: false
                    ) {
                        correct(exercise, prior: prior)
                    }
                    .disabled(logDisabled)
                }
                HStack(spacing: 12) {
                    NativeCardAction(title: "Previous", identifier: "native_training_previous_exercise_\(card.object.id)", filled: false) {
                        move(to: currentIndex - 1)
                    }
                    .disabled(currentIndex == 0)
                    NativeCardAction(title: "Next", identifier: "native_training_next_exercise_\(card.object.id)", filled: false) {
                        move(to: currentIndex + 1)
                    }
                    .disabled(currentIndex >= exercises.count - 1)
                }
                NativeCardAction(title: showsAll ? "Hide exercises" : "All exercises", identifier: "native_training_expand_session_\(card.object.id)", filled: false) {
                    guard admit("expand_session") != nil else { return }
                    showsAll.toggle()
                }
                if showsAll {
                    ForEach(exercises) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name).font(.headline)
                            Text(item.setup).font(.body)
                            Text(prescription(item)).font(.subheadline)
                        }
                        .foregroundStyle(theme.colors.text)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if offline {
                Text("Chat can wait. Logging and exercise changes stay available.")
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { seedIfNeeded() }
        .onChange(of: currentIndex) { _, _ in seedIfNeeded(force: true) }
    }

    private func prescription(_ exercise: NativeWorkoutExercise) -> String {
        let load = exercise.targetLoadKg.map { "\(TrainingLoadInputPolicy.savedText(for: $0)) kg" } ?? "bodyweight"
        return "\(exercise.sets) sets · \(exercise.repMin)–\(exercise.repMax) reps · target \(exercise.targetReps) at RIR \(exercise.targetRir) · \(load)"
    }

    private func previousLine(_ prior: NativePreviousSet) -> String {
        let load = prior.loadKg.map { "\(TrainingLoadInputPolicy.savedText(for: $0)) kg" } ?? "bodyweight"
        return "Previous set \(prior.setNumber): \(prior.reps) reps, \(load), RIR \(prior.rir)"
    }

    private func seedIfNeeded(force: Bool = false) {
        guard let exercise, force || seededIndex != currentIndex else { return }
        reps = exercise.targetReps
        rir = exercise.targetRir
        loadText = TrainingLoadInputPolicy.savedText(for: exercise.targetLoadKg)
        seededIndex = currentIndex
    }

    private func log(_ exercise: NativeWorkoutExercise) {
        guard let load = loadValue() else { return }
        admit("log_set", payload: [
            "exerciseId": exercise.id,
            "setNumber": exercise.completedSets + 1,
            "reps": reps,
            "loadKg": load,
            "rir": rir
        ])
    }

    private func correct(_ exercise: NativeWorkoutExercise, prior: NativePreviousSet) {
        guard let revision = prior.revision, let load = loadValue() else { return }
        admit("correct_set", payload: [
            "exerciseId": exercise.id,
            "setNumber": prior.setNumber,
            "reps": reps,
            "loadKg": load,
            "rir": rir,
            "correctionId": UUID().uuidString,
            "expectedRevision": revision
        ])
    }

    private func move(to index: Int) {
        admit("navigate_exercise", payload: ["exerciseIndex": index])
    }

    private func loadValue() -> Any? {
        do {
            inputMessage = nil
            if let kilograms = try TrainingLoadInputPolicy.loadKg(from: loadText) {
                return kilograms
            }
            return NSNull()
        } catch {
            inputMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    private func admit(_ action: String, payload: [String: Any] = [:]) -> AdmittedNativeTrainingAction? {
        switch NativeTrainingCardContract.admit(
            card: card, action: action, ownerSubject: ownerSubject, payload: payload
        ) {
        case .success(let admitted):
            onAction(admitted)
            return admitted
        case .failure:
            inputMessage = "That training action was not accepted."
            return nil
        }
    }
}

private struct NativeSwapCard: View {
    let card: NativeTrainingCard
    let exerciseId: String
    let alternatives: [NativeSwapAlternative]
    let writesDisabled: Bool
    let phase: NativeTrainingCardPhase
    let ownerSubject: String
    let onAction: (AdmittedNativeTrainingAction) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        NativeCardChrome(identifier: "native_training_card_ExerciseSwapCard_\(card.object.id)") {
            Text("Swap \(exerciseId.replacingOccurrences(of: "_", with: " "))")
                .font(.headline)
                .foregroundStyle(theme.colors.text)
            Text("Eligible alternatives for this exercise. The rest of the plan stays as saved.")
                .font(.subheadline)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            NativeCardPhaseLabel(card: card, phase: phase)
            ForEach(alternatives) { alternative in
                VStack(alignment: .leading, spacing: 4) {
                    Text(alternative.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.colors.text)
                    Text(alternative.tradeoff)
                        .font(.subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    NativeCardAction(
                        title: "Use \(alternative.name)",
                        identifier: "native_training_swap_\(alternative.id)",
                        filled: false
                    ) {
                        admit(alternative.id)
                    }
                    .disabled(writesDisabled)
                }
            }
        }
    }

    private func admit(_ variantId: String) {
        if case .success(let action) = NativeTrainingCardContract.admit(
            card: card,
            action: "swap_exercise",
            ownerSubject: ownerSubject,
            payload: ["toVariantId": variantId]
        ) {
            onAction(action)
        }
    }
}

private struct NativeFeedbackCard: View {
    let card: NativeTrainingCard
    let prompt: String
    let writesDisabled: Bool
    let phase: NativeTrainingCardPhase
    let ownerSubject: String
    let onAction: (AdmittedNativeTrainingAction) -> Void

    @Environment(\.theme) private var theme
    @State private var statement = ""

    var body: some View {
        NativeCardChrome(identifier: "native_training_card_TrainingFeedbackCard_\(card.object.id)") {
            Text("Session note")
                .font(.headline)
                .foregroundStyle(theme.colors.text)
            Text(prompt)
                .font(.body)
                .foregroundStyle(theme.colors.text)
                .fixedSize(horizontal: false, vertical: true)
            TextField("Short note", text: $statement, axis: .vertical)
                .font(.body)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("native_training_feedback_field_\(card.object.id)")
            NativeCardPhaseLabel(card: card, phase: phase)
            NativeCardAction(title: "Save note", identifier: "native_training_feedback_\(card.object.id)", filled: true) {
                if case .success(let action) = NativeTrainingCardContract.admit(
                    card: card,
                    action: "record_feedback",
                    ownerSubject: ownerSubject,
                    payload: ["statement": statement]
                ) {
                    onAction(action)
                }
            }
            .disabled(writesDisabled)
        }
    }
}

private struct NativeReviewCard: View {
    let card: NativeTrainingCard
    let citations: [NativeReviewCitation]
    let proposedChange: NativeProposedChange?
    let writesDisabled: Bool
    let phase: NativeTrainingCardPhase
    let ownerSubject: String
    let onAction: (AdmittedNativeTrainingAction) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        NativeCardChrome(identifier: "native_training_card_ProgressReviewCard_\(card.object.id)") {
            Text("Recorded training")
                .font(.headline)
                .foregroundStyle(theme.colors.text)
            ForEach(citations) { citation in
                Text(citation.statement)
                    .font(.body)
                    .foregroundStyle(theme.colors.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Recorded result \(citation.resultId). \(citation.statement)")
            }
            NativeCardPhaseLabel(card: card, phase: phase)
            if proposedChange != nil {
                NativeCardAction(
                    title: "Propose this change",
                    identifier: "native_training_review_\(card.object.id)",
                    filled: true
                ) {
                    if case .success(let action) = NativeTrainingCardContract.admit(
                        card: card, action: "propose_change", ownerSubject: ownerSubject
                    ) {
                        onAction(action)
                    }
                }
                .disabled(writesDisabled)
            }
        }
    }
}

private struct NativeCardChrome<Content: View>: View {
    @Environment(\.theme) private var theme
    let identifier: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous)
                .stroke(theme.colors.border.opacity(0.7), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

private struct NativeCardPhaseLabel: View {
    @Environment(\.theme) private var theme
    let card: NativeTrainingCard
    let phase: NativeTrainingCardPhase

    var body: some View {
        switch phase {
        case .ready(let receipt):
            if let receipt {
                Text(receipt)
                    .font(.subheadline)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("native_training_phase_\(card.object.id)")
            }
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Saving").font(.subheadline)
            }
            .accessibilityIdentifier("native_training_phase_\(card.object.id)")
        case .pending(let message), .offline(let message), .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("native_training_phase_\(card.object.id)")
        }
    }
}

private struct NativeCardAction: View {
    let title: String
    let identifier: String
    let filled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(NativeCardActionStyle(filled: filled))
        .accessibilityIdentifier(identifier)
    }
}

private struct NativeCardActionStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(filled ? theme.colors.background : theme.colors.text)
            .padding(.horizontal, 16)
            .background {
                if filled {
                    Capsule().fill(theme.colors.text)
                } else {
                    Capsule().stroke(theme.colors.border, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
