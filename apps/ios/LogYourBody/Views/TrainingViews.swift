import SwiftUI

enum TrainingPresentation: Identifiable {
    case setup
    case session(TrainingSession, AuthManager.ProfileSessionOwnership)
    case voiceSetReview(TrainingSession, VoiceHeardIntent)
    case canvas(AuthManager.ProfileSessionOwnership)
    case program(AuthManager.ProfileSessionOwnership)

    var id: String {
        switch self {
        case .setup: "setup"
        case .session(let session, let owner): "session-\(owner.subject)-\(owner.generation)-\(session.id)"
        case .voiceSetReview(let session, _): "voice-set-review-\(session.id)"
        case .canvas(let owner): "canvas-\(owner.subject)-\(owner.generation)"
        case .program(let owner): "program-\(owner.subject)-\(owner.generation)"
        }
    }
}

struct TrainingCoachCard: View {
    let session: TrainingSession
    let onStart: () -> Void
    let onStop: () -> Void

    @Environment(\.theme) private var theme
    @State private var isStopConfirmationPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT SESSION")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(theme.colors.textSecondary)
                    Text(session.safetyStop ? "Pause for now" : session.title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.colors.text)
                }
                Spacer(minLength: 8)
                Text("Week \(session.week)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
            }

            if session.safetyStop {
                Text(session.explanation ?? "Pause this session and check in with a qualified professional " +
                    "if symptoms persist or worsen.")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("training_safety_stop")
                Button(action: onStart) {
                    HStack {
                        Text("Update recovery check-in")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.colors.text)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("training_update_checkin")
            } else {
                Text("\(session.exercises.count) movements · engine-guided sets and reps")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.colors.textSecondary)
                Button(action: onStart) {
                    HStack {
                        Text("Start session")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.background)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 48)
                    .background(theme.colors.text, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("training_start_session")
            }

            Button("Stop coaching and delete training data", role: .destructive) {
                isStopConfirmationPresented = true
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(theme.colors.textSecondary)
            .buttonStyle(.plain)
            .accessibilityIdentifier("training_revoke_button")
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous)
                .stroke(theme.colors.border.opacity(0.7), lineWidth: 1)
        }
        // confirmationDialog presents without Cancel, so stopping coaching has no reachable escape hatch.
        .alert(
            "Delete your training sessions, set logs, and feedback?",
            isPresented: $isStopConfirmationPresented
        ) {
            Button("Stop coaching and delete data", role: .destructive, action: onStop)
                .accessibilityIdentifier("training_revoke_confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("training_revoke_cancel")
        } message: {
            Text("This removes training records from your account. It does not delete your body-composition data or chat.")
        }
    }
}

struct TrainingSetupCard: View {
    let action: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TRAINING COACH")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(theme.colors.textSecondary)
            Text("Build a plan around your training history.")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.colors.text)
            Text("Start only if the adult and safety checks fit you. Sessions are saved to your account " +
                "and can be deleted at any time.")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                HStack {
                    Text("Set up training")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.colors.background)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(theme.colors.text, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("training_setup_button")
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius, style: .continuous))
    }
}

struct TrainingWeekCompleteCard: View {
    let week: Int

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(theme.colors.accentTeal)
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly sessions complete")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.colors.text)
                Text("Week \(week) is logged. Your next session will appear in the next training week.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct TrainingEnrollmentView: View {
    let onEnroll: (Int, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var sessionsPerWeek = 2
    @State private var equipment = "dumbbells"
    @State private var adultConfirmed = false
    @State private var safetyConfirmed = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A deterministic engine sets the workout. Chat can explain only what the engine returns.")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Section("Schedule") {
                    Picker("Sessions each week", selection: $sessionsPerWeek) {
                        Text("2 days").tag(2)
                        Text("3 days").tag(3)
                    }
                    .pickerStyle(.segmented)
                    Picker("Equipment", selection: $equipment) {
                        Text("Dumbbells").tag("dumbbells")
                        Text("Full gym").tag("full_gym")
                    }
                }

                Section("Safety") {
                    Toggle("I’m 18 or older.", isOn: $adultConfirmed)
                    Toggle(
                        "I’m not pregnant or postpartum, have no eating-disorder risk, " +
                            "and have no medical restriction that makes this training unsafe.",
                        isOn: $safetyConfirmed
                    )
                    Text("If these checks do not fit, do not start this program. Pause training for concerning pain " +
                        "or symptoms and seek qualified care when needed.")
                        .font(.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.appWarning)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
            .navigationTitle("Training coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Starting…" : "Start") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || !adultConfirmed || !safetyConfirmed)
                    .accessibilityIdentifier("training_enroll_confirm")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("training_enroll_close_button")
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.vertical, JovieTokens.itemGap)
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await onEnroll(sessionsPerWeek, equipment)
            dismiss()
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Training could not be started. Please try again."
        } catch {
            errorMessage = "Training could not be started. Please try again."
        }
    }
}

/// The engine carries last session's final-set load forward on hold and
/// add-reps weeks; the load field starts there, like reps start at the target.
enum TrainingLoadPrefillPolicy {
    static func text(for targetLoadKg: Double?) -> String {
        guard let targetLoadKg, targetLoadKg > 0 else { return "" }
        let rounded = (targetLoadKg * 100).rounded() / 100
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(0...2))
            .grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX"))
        return rounded.formatted(style)
    }
}

enum TrainingLoadInputPolicy {
    static let invalidMessage = "Enter a load from 0 to 500 kg, or leave it blank for bodyweight."

    static func loadKg(from text: String) throws -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return nil }
        guard value.range(of: #"^([0-9]+([.,][0-9]*)?|[.,][0-9]+)$"#, options: .regularExpression) != nil,
              let load = Double(value.replacingOccurrences(of: ",", with: ".")),
              load.isFinite, (0...500).contains(load)
        else { throw InputError.invalidLoad }
        return load
    }

    static func isValid(_ text: String) -> Bool {
        do {
            _ = try loadKg(from: text)
            return true
        } catch {
            return false
        }
    }

    static func savedText(for load: Double?) -> String {
        guard let load else { return "" }
        let text = String(load)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    enum InputError: LocalizedError {
        case invalidLoad
        var errorDescription: String? { TrainingLoadInputPolicy.invalidMessage }
    }
}

private enum TrainingVoiceReview {
    case log(VoiceSetProposal)
    case correct(VoiceSetProposal)
    case action(TrainingWorkoutAction)
    case feedback(TrainingWorkoutFeedback, String)
}

enum TrainingCompletionMotionPolicy {
    static func shouldAnimate(reduceMotion: Bool) -> Bool { !reduceMotion }
}

struct TrainingLiveSessionView: View {
    let voiceEnabled: Bool
    let readinessEnabled: Bool
    let progressEnabled: Bool
    let progressDecision: TrainingProgressDecision?
    let onLoadProgress: (() async throws -> TrainingProgressResponse)?
    let onLogSet: (TrainingExercisePrescription, Int, Int, Double?, Int) async throws -> TrainingSavedSet
    let onCorrectSet: (TrainingSetCorrectionRequest) async throws -> TrainingSavedSet
    let onUndoSet: (TrainingSetUndoRequest) async throws -> TrainingSavedSet
    let onWorkoutAction: (TrainingWorkoutActionRequest) async throws -> TrainingSession
    let onVoiceIntent: (TrainingSession, String, VoiceSetContext?, VoiceSetContext?) async throws -> VoiceIntentResponse
    let onFeedback: (TrainingFeedbackRequest) async throws -> TrainingFeedbackResponse

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var draft: TrainingSessionDraft
    @StateObject private var progress: TrainingProgressModel
    @State private var voiceCapture = VoiceCaptureService()
    @State private var soreness = 0
    @State private var pump = 0
    @State private var jointPain = 0
    @State private var performance = "stable"
    @State private var feedbackMuscle = ""
    @State private var muscleRecovery = "unknown"
    @State private var feedbackSaved = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var commandText = ""
    @State private var pendingTranscript = ""
    @State private var voiceReview: TrainingVoiceReview?
    @State private var showVoiceReview = false
    @State private var correctionPosition: TrainingSetPosition?
    @State private var completionReceipt: TrainingSetSaveReceipt?
    @State private var showEndConfirmation = false

    init(
        session: TrainingSession,
        ownerId: String,
        voiceEnabled: Bool,
        readinessEnabled: Bool = false,
        progressEnabled: Bool = false,
        progressDecision: TrainingProgressDecision? = nil,
        draftStore: TrainingDraftStore = .shared,
        isCurrent: @escaping () -> Bool,
        onLogSet: @escaping (TrainingExercisePrescription, Int, Int, Double?, Int) async throws -> TrainingSavedSet,
        onCorrectSet: @escaping (TrainingSetCorrectionRequest) async throws -> TrainingSavedSet,
        onUndoSet: @escaping (TrainingSetUndoRequest) async throws -> TrainingSavedSet,
        onWorkoutAction: @escaping (TrainingWorkoutActionRequest) async throws -> TrainingSession,
        onVoiceIntent: @escaping (
            TrainingSession, String, VoiceSetContext?, VoiceSetContext?
        ) async throws -> VoiceIntentResponse,
        onFeedback: @escaping (TrainingFeedbackRequest) async throws -> TrainingFeedbackResponse,
        onLoadProgress: (() async throws -> TrainingProgressResponse)? = nil
    ) {
        self.voiceEnabled = voiceEnabled
        self.readinessEnabled = readinessEnabled
        self.progressEnabled = progressEnabled
        self.progressDecision = progressDecision
        self.onLoadProgress = onLoadProgress
        self.onLogSet = onLogSet
        self.onCorrectSet = onCorrectSet
        self.onUndoSet = onUndoSet
        self.onWorkoutAction = onWorkoutAction
        self.onVoiceIntent = onVoiceIntent
        self.onFeedback = onFeedback
        _draft = StateObject(wrappedValue: TrainingSessionDraft(
            session: session, ownerId: ownerId, store: draftStore, isCurrent: isCurrent
        ))
        _progress = StateObject(wrappedValue: TrainingProgressModel(isCurrent: isCurrent))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: JovieTokens.screenInset) {
                    sessionHeader
                    if hasSafetyStop {
                        safetyCard
                    } else if draft.session.executionPaused == true {
                        pausedCard
                    } else if let current = draft.currentPosition {
                        currentCard(current)
                        if progressEnabled {
                            TrainingExerciseHistoryRow(exerciseId: current.exercise.id, model: progress)
                        }
                        upNextCard
                        if progressEnabled, let next = draft.upNextPosition {
                            TrainingExerciseHistoryRow(exerciseId: next.exercise.id, model: progress)
                                .accessibilityIdentifier("training_history_up_next_\(next.exercise.id)")
                        }
                        restState
                    } else {
                        completeCard
                    }
                    if readinessEnabled {
                        readinessControl
                    }
                    if hasSafetyStop {
                        Button("End workout", role: .destructive) { showEndConfirmation = true }
                            .buttonStyle(.bordered)
                    } else if draft.session.executionPaused == true {
                        Button("End workout", role: .destructive) { showEndConfirmation = true }
                            .buttonStyle(.bordered)
                        commandControl
                    } else {
                        sessionControls
                        commandControl
                    }
                    feedbackCard
                    if progressEnabled {
                        TrainingProgressReviewSection(model: progress, decision: progressDecision) {
                            Task { await refreshProgress() }
                        }
                    }
                    if let message = errorMessage ?? draft.errorMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Color.appWarning)
                            .accessibilityIdentifier("training_live_error")
                    } else if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(theme.colors.textSecondary)
                    }
                }
                .padding(20)
            }
            .background(theme.colors.background)
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            // The navigation-bar Close accessibility frame stays 36 points tall.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Text("Close")
                        .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isSaving || draft.isSaving)
                .accessibilityIdentifier("training_live_session_close_button")
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.vertical, JovieTokens.itemGap)
            }
        }
        .interactiveDismissDisabled(isSaving || draft.isSaving)
        .task(id: progressRefreshKey) { await refreshProgress() }
        .onDisappear { voiceCapture.cancel() }
        .onChange(of: draft.lastSaveReceipt) { _, receipt in
            guard let receipt else { return }
            if !TrainingCompletionMotionPolicy.shouldAnimate(reduceMotion: effectiveReduceMotion) {
                completionReceipt = receipt
            } else {
                withAnimation(.easeOut(duration: 0.2)) { completionReceipt = receipt }
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                if completionReceipt?.id == receipt.id { completionReceipt = nil }
            }
        }
        .alert("Review command", isPresented: $showVoiceReview) {
            Button("Cancel", role: .cancel) { voiceReview = nil }
            Button(reviewActionTitle) { confirmVoiceReview() }
        } message: {
            Text(reviewMessage)
        }
        .alert("End this workout?", isPresented: $showEndConfirmation) {
            Button("Keep training", role: .cancel) {}
            Button("End workout", role: .destructive) { performAction(.end) }
        } message: {
            Text("Completed sets stay saved. Unfinished work is recorded only for today.")
        }
        .sheet(item: $correctionPosition, onDismiss: cancelOpenCorrection) { position in
            correctionSheet(position)
        }
    }

    private var progressRefreshKey: String {
        "\(progressEnabled)-\(draft.session.executionRevision ?? 0)-" +
            "\(draft.lastSaveReceipt?.id ?? "")-\(draft.feedback?.response?.feedback.id ?? "")"
    }

    private func refreshProgress() async {
        guard progressEnabled, let onLoadProgress else { return }
        await progress.load(using: onLoadProgress)
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
            Text("WEEK \(draft.session.week) · \(draft.session.title.uppercased())")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(theme.colors.textSecondary)
            Text("\(draft.completedCount) of \(draft.totalCount) sets")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.colors.text)
                .accessibilityIdentifier("training_progress")
        }
    }

    private func currentCard(_ position: TrainingSetPosition) -> some View {
        let exercise = position.exercise
        let row = draft.row(for: exercise, setNumber: position.setNumber)
        return VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOW")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(theme.colors.accentTeal)
                    Text(exercise.name)
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.colors.text)
                    Text("Set \(position.setNumber) of \(exercise.sets) · \(exercise.repRange.min)–\(exercise.repRange.max) reps · \(exercise.targetRir) RIR")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.colors.textSecondary)
                }
                Spacer(minLength: 8)
                if completionReceipt?.corrected == false {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(theme.colors.accentTeal)
                        .accessibilityLabel("Set saved")
                        .accessibilityIdentifier("training_set_completion_receipt")
                }
            }
            if let instruction = exercise.loadInstruction {
                Text(instruction)
                    .font(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            HStack(spacing: JovieTokens.itemGap) {
                labeledField(
                    "REPS",
                    placeholder: "Reps",
                    text: repsBinding(for: exercise, setNumber: position.setNumber),
                    keyboard: .numberPad,
                    id: "training_reps_\(exercise.id)_\(position.setNumber)"
                )
                labeledField(
                    "LOAD KG",
                    placeholder: "Load kg",
                    text: loadBinding(for: exercise, setNumber: position.setNumber),
                    keyboard: .decimalPad,
                    id: "training_load_\(exercise.id)_\(position.setNumber)"
                )
            }
            .disabled(draft.isSaving || row.pendingRequest != nil)
            if !TrainingLoadInputPolicy.isValid(row.loadText) {
                Text(TrainingLoadInputPolicy.invalidMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.appWarning)
                    .accessibilityIdentifier("training_load_error_\(exercise.id)_\(position.setNumber)")
            }
            Stepper(
                "\(row.rir) reps in reserve",
                value: rirBinding(for: exercise, setNumber: position.setNumber),
                in: 0...6
            )
            .font(.system(size: 13))
            .disabled(draft.isSaving || row.pendingRequest != nil)
            .accessibilityIdentifier("training_rir_\(exercise.id)_\(position.setNumber)")
            Button(row.pendingRequest == nil ? "Log set" : "Retry set") {
                Task { await log(exercise, setNumber: position.setNumber) }
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.colors.text)
            .disabled(
                draft.isSaving || !(1...50).contains(Int(row.repsText) ?? 0) ||
                    !TrainingLoadInputPolicy.isValid(row.loadText)
            )
            .accessibilityIdentifier("training_log_set_\(exercise.id)_\(position.setNumber)")
            if row.pendingRequest != nil && !draft.isSaving {
                Text("Pending sync. Retry sends the same set identity and values.")
                    .font(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityIdentifier("training_pending_sync")
            }
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.colors.border.opacity(0.7), lineWidth: 1)
        }
        .accessibilityIdentifier("training_now_card")
    }

    private var upNextCard: some View {
        HStack(spacing: 12) {
            Text("UP NEXT")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(theme.colors.textSecondary)
            if let next = draft.upNextPosition {
                Text("\(next.exercise.name) · set \(next.setNumber)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.text)
            } else {
                Text("Finish workout")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.colors.text)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(theme.colors.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius))
        .accessibilityIdentifier("training_up_next")
    }

    @ViewBuilder private var restState: some View {
        if let restUntil = draft.restUntil {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(restUntil.timeIntervalSince(context.date).rounded(.up)))
                Text(remaining > 0 ? "Rest · \(remaining)s" : "Timer elapsed · readiness not assessed")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityIdentifier("training_rest_timer")
            }
        }
    }

    private var hasSafetyStop: Bool {
        draft.session.safetyStop || (readinessEnabled && draft.nextSetRecommendation?.action == .symptomSafety)
    }

    private var readinessControl: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            readinessContent
        }
    }

    private var readinessContent: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            if let recommendation = draft.nextSetRecommendation {
                Text(recommendation.title)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("training_next_set_action")
                ForEach(recommendation.reasons, id: \.self) { reason in
                    Text(reason).font(.footnote).foregroundStyle(theme.colors.textSecondary)
                }
                Text("For today. Changes to future sessions need your review.")
                    .font(.footnote)
                    .foregroundStyle(theme.colors.textSecondary)
            }
            if draft.feedback?.response == nil, draft.feedback != nil {
                Text("Feedback pending sync. No updated recommendation yet.")
                    .font(.footnote)
                    .accessibilityIdentifier("training_feedback_pending")
                Button("Retry feedback") { Task { await draft.retryFeedback(send: onFeedback) } }
                    .accessibilityIdentifier("training_feedback_retry")
            } else if !hasSafetyStop {
                Menu("Rest or readiness") {
                    Button("Still out of breath") { submitReadiness(.breathingLimited, statement: "still out of breath") }
                    Button("Grip is limiting me") { submitReadiness(.gripLimited, statement: "my grip is limiting me") }
                    Button("Need more rest") { submitReadiness(.moreRest, statement: "need more rest") }
                    Button("Ready now") { submitReadiness(.ready, statement: "ready now") }
                    Button("That set was unusually weak") {
                        submitReadiness(.unusuallyWeak, statement: "that set was unusually weak")
                    }
                }
                .accessibilityIdentifier("training_readiness_menu")
            }
        }
        .disabled(isSaving || draft.isSaving)
        .accessibilityIdentifier("training_readiness_control")
    }

    private func submitReadiness(_ intent: TrainingWorkoutFeedback.Intent, statement: String) {
        let position = intent == .unusuallyWeak ? draft.lastCompletedPosition : draft.currentPosition
        guard let position else { return }
        let proposal = TrainingWorkoutFeedback(
            sessionId: draft.session.id, exerciseId: position.exercise.id, setNumber: position.setNumber,
            intent: intent, originalStatement: statement
        )
        Task { await draft.recordWorkoutFeedback(proposal, source: "touch", send: onFeedback) }
    }

    private var sessionControls: some View {
        VStack(spacing: JovieTokens.itemGap) {
            HStack(spacing: JovieTokens.itemGap) {
                Button("Equipment occupied", systemImage: "arrow.triangle.swap") {
                    guard let current = draft.currentPosition else { return }
                    performAction(.equipmentUnavailable(current.exercise.id))
                }
                Button("30 min", systemImage: "clock") { performAction(.shorten(30)) }
            }
            HStack(spacing: JovieTokens.itemGap) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    if let undo = draft.undoAffordance {
                        Button(undo.submitted ? "Retry undo" : "Undo", systemImage: "arrow.uturn.backward") {
                            Task { await undoLastCorrection() }
                        }
                        .accessibilityLabel(undo.submitted ? "Retry undo" : "Undo correction")
                        .accessibilityIdentifier(undo.submitted ? "training_undo_pending" : "training_set_undo")
                    }
                }
                Button("Correct", systemImage: "pencil") {
                    guard let last = draft.lastCompletedPosition else { return }
                    draft.beginCorrection(last)
                    correctionPosition = last
                }
                .accessibilityIdentifier("training_set_correct")
                .disabled(draft.lastCompletedPosition == nil)
                Menu("More", systemImage: "ellipsis") {
                    Button("Skip this today") {
                        guard let current = draft.currentPosition else { return }
                        performAction(.skip(current.exercise.id))
                    }
                    Button("Pause workout") { performAction(.pause) }
                    Button("End workout", role: .destructive) { showEndConfirmation = true }
                }
            }
        }
        .buttonStyle(.bordered)
        .disabled(isSaving || draft.isSaving)
    }

    @ViewBuilder private var commandControl: some View {
        if voiceCapture.isRecording {
            HStack(spacing: 12) {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<4, id: \.self) { index in
                        Capsule()
                            .fill(theme.colors.accentTeal)
                            .frame(
                                width: 3,
                                height: CGFloat(max(5, voiceCapture.inputLevel * Double(16 + index * 4)))
                            )
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(voiceCapture.recordingStartedAt ?? context.date))
                    Text("Listening · \(elapsed)s")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                Spacer()
                Button("Cancel") { voiceCapture.cancel() }
                Button("Stop") { finishVoiceCapture() }
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, JovieTokens.compactInset)
            .frame(minHeight: 48)
            .background(theme.colors.surface, in: Capsule())
            .accessibilityIdentifier("training_voice_capsule")
        } else {
            HStack(spacing: JovieTokens.itemGap) {
                TextField("Type a workout command", text: $commandText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { submitTypedCommand() }
                    .accessibilityIdentifier("training_command_field")
                if voiceEnabled {
                    Button(action: startVoiceCapture) {
                        Image(systemName: voiceCapture.isFinishing ? "ellipsis" : "mic.fill")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(voiceCapture.isFinishing || isSaving)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Talk")
                    .accessibilityIdentifier("training_voice_button")
                }
            }
        }
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: JovieTokens.itemGap) {
            Label("Workout paused", systemImage: "exclamationmark.shield")
                .font(.system(size: 18, weight: .semibold))
            Text(draft.nextSetRecommendation?.reasons.first ?? draft.session.explanation ??
                "Pause and review these symptoms before continuing.")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.textSecondary)
            Text("If it persists or worsens, seek qualified care.")
                .font(.footnote)
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(JovieTokens.compactInset)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius))
        .accessibilityIdentifier("training_live_safety_stop")
    }

    private var pausedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout paused")
                .font(.system(size: 20, weight: .semibold))
            Button("Resume") { performAction(.resume) }
                .buttonStyle(.borderedProminent)
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius))
    }

    private var completeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Workout complete", systemImage: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(theme.colors.text)
            Text("Your saved sets are ready for the next coaching update.")
                .font(.system(size: 14))
                .foregroundStyle(theme.colors.textSecondary)
        }
        .padding(JovieTokens.compactInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: JovieTokens.cardRadius))
    }

    private func labeledField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        id: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(id)
        }
    }

    private func correctionSheet(_ position: TrainingSetPosition) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(position.exercise.name) · set \(position.setNumber)")
                    .font(.system(size: 18, weight: .semibold))
                HStack {
                    labeledField(
                        "REPS", placeholder: "Reps",
                        text: repsBinding(for: position.exercise, setNumber: position.setNumber),
                        keyboard: .numberPad, id: "training_correction_reps"
                    )
                    labeledField(
                        "LOAD KG", placeholder: "Load kg",
                        text: loadBinding(for: position.exercise, setNumber: position.setNumber),
                        keyboard: .decimalPad, id: "training_correction_load"
                    )
                }
                Stepper(
                    "\(rirBinding(for: position.exercise, setNumber: position.setNumber).wrappedValue) reps in reserve",
                    value: rirBinding(for: position.exercise, setNumber: position.setNumber), in: 0...6
                )
                Button("Save correction") { Task { await saveCorrection(position) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.isSaving)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Correct set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        draft.cancelCorrection(position)
                        correctionPosition = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var feedbackCard: some View {
        DisclosureGroup("Recovery check-in") {
            VStack(alignment: .leading, spacing: 12) {
                Stepper("Soreness: \(soreness) / 10", value: $soreness, in: 0...10)
                Stepper("Pump: \(pump) / 10", value: $pump, in: 0...10)
                Stepper("Joint pain: \(jointPain) / 10", value: $jointPain, in: 0...10)
                Picker("Performance", selection: $performance) {
                    Text("Down").tag("down")
                    Text("Stable").tag("stable")
                    Text("Up").tag("up")
                }
                .pickerStyle(.segmented)
                if !feedbackMuscles.isEmpty {
                    Picker("Muscle detail", selection: $feedbackMuscle) {
                        Text("Whole session").tag("")
                        ForEach(feedbackMuscles, id: \.self) { muscle in
                            Text(muscle.replacingOccurrences(of: "_", with: " ").capitalized).tag(muscle)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Optional. Choose a muscle only when these answers describe it specifically.")
                        .font(.footnote)
                        .foregroundStyle(theme.colors.textSecondary)
                    if !feedbackMuscle.isEmpty {
                        Picker("Recovery", selection: $muscleRecovery) {
                            Text("Unknown").tag("unknown")
                            Text("Limited").tag("limited")
                            Text("Ready").tag("ready")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Button(
                    feedbackSaved ? "Feedback saved" :
                        draft.session.safetyStop ? "Save updated check-in" : "Save check-in"
                ) {
                    Task { await saveFeedback() }
                }
                .disabled(feedbackSaved || isSaving || draft.isSaving)
                .accessibilityIdentifier("training_save_feedback")
            }
        }
        .padding(16)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func setKey(_ exercise: TrainingExercisePrescription, setNumber: Int) -> String {
        "\(exercise.id)-\(setNumber)"
    }

    private var effectiveReduceMotion: Bool {
        #if DEBUG
        reduceMotion || ProcessInfo.processInfo.arguments.contains("-lybUITestReduceMotion")
        #else
        reduceMotion
        #endif
    }

    private func repsBinding(for exercise: TrainingExercisePrescription, setNumber: Int) -> Binding<String> {
        Binding(
            get: { draft.row(for: exercise, setNumber: setNumber).repsText },
            set: { value in draft.update(exercise, setNumber: setNumber) { $0.repsText = value } }
        )
    }

    private func loadBinding(for exercise: TrainingExercisePrescription, setNumber: Int) -> Binding<String> {
        return Binding(
            get: { draft.row(for: exercise, setNumber: setNumber).loadText },
            set: { value in draft.update(exercise, setNumber: setNumber) { $0.loadText = value } }
        )
    }

    private func rirBinding(for exercise: TrainingExercisePrescription, setNumber: Int) -> Binding<Int> {
        Binding(
            get: { draft.row(for: exercise, setNumber: setNumber).rir },
            set: { value in draft.update(exercise, setNumber: setNumber) { $0.rir = value } }
        )
    }

    private func log(_ exercise: TrainingExercisePrescription, setNumber: Int) async {
        guard !isSaving else { return }
        errorMessage = nil
        await draft.saveAcknowledged(exercise, setNumber: setNumber) { request in
            try await onLogSet(
                exercise, request.setNumber, request.reps, request.loadKg, request.rir
            )
        }
    }

    private func undoLastCorrection() async {
        await draft.undo(send: onUndoSet)
    }

    private func saveCorrection(_ position: TrainingSetPosition) async {
        await draft.correct(position, send: onCorrectSet)
        if draft.rows[position.id] == nil { correctionPosition = nil }
    }

    private func cancelOpenCorrection() {
        guard let row = draft.rows.values.first(where: {
            $0.correctionBase != nil && $0.pendingCorrection == nil
        }), let position = draft.allPositions.first(where: { $0.id == row.key }) else { return }
        draft.cancelCorrection(position)
    }

    private func performAction(_ action: TrainingWorkoutAction) {
        Task { @MainActor in
            guard !isSaving else { return }
            isSaving = true
            errorMessage = nil
            defer { isSaving = false }
            do {
                let request = TrainingWorkoutActionRequest(
                    sessionId: draft.session.id,
                    eventId: UUID().uuidString,
                    expectedRevision: draft.session.executionRevision ?? 0,
                    action: action
                )
                let updated = try await onWorkoutAction(request)
                draft.replaceSession(updated)
                statusMessage = actionResultMessage(updated.executionEvents?.last?.kind) ?? statusMessage
                if action.kind == "end" { dismiss() }
            } catch let error as LocalizedError {
                errorMessage = error.errorDescription ?? "The workout could not be updated."
            } catch {
                errorMessage = "The workout could not be updated."
            }
        }
    }

    private func actionResultMessage(_ kind: String?) -> String? {
        switch kind {
        case "reordered": "Moved this exercise later for today."
        case "substituted": "Using an eligible alternative today. Choose its load yourself."
        case "shortened": "Session shortened around the highest-priority work."
        case "skipped": "Skipped for today. Your lasting preferences did not change."
        case "paused": "Workout paused."
        case "resumed": "Workout resumed."
        default: nil
        }
    }

    private func startVoiceCapture() {
        Task { @MainActor in
            errorMessage = nil
            do {
                try await voiceCapture.start()
            } catch let error as LocalizedError {
                errorMessage = error.errorDescription ?? "Voice input is unavailable."
            } catch {
                errorMessage = "Voice input is unavailable."
            }
        }
    }

    private func finishVoiceCapture() {
        Task { @MainActor in
            do {
                let transcript = try await voiceCapture.finish()
                await interpretCommand(transcript, source: "voice")
            } catch is CancellationError {
                return
            } catch let error as LocalizedError {
                errorMessage = error.errorDescription ?? "Voice input is unavailable."
            } catch {
                errorMessage = "Voice input is unavailable."
            }
        }
    }

    private func submitTypedCommand() {
        let text = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        commandText = ""
        Task { await interpretCommand(text, source: "text") }
    }

    private func interpretCommand(_ transcript: String, source: String) async {
        do {
            let response = try await onVoiceIntent(
                draft.session,
                transcript,
                voiceContext(draft.currentPosition),
                voiceContext(draft.lastCompletedPosition)
            )
            pendingTranscript = transcript
            switch response.kind {
            case "workout_feedback":
                guard readinessEnabled, let feedback = response.feedback else {
                    throw TrainingServiceError.invalidResponse
                }
                voiceReview = .feedback(feedback, source)
            case "log_set":
                guard let proposal = response.proposal else { throw TrainingServiceError.invalidResponse }
                voiceReview = .log(proposal)
            case "correct_set":
                guard let proposal = response.proposal else { throw TrainingServiceError.invalidResponse }
                voiceReview = .correct(proposal)
            case "workout_action":
                guard let action = response.action?.trainingAction else { throw TrainingServiceError.invalidResponse }
                if response.requiresConfirmation == false {
                    statusMessage = "Heard: “\(transcript)”"
                    performAction(action)
                    return
                }
                voiceReview = .action(action)
            case "clarify":
                errorMessage = trainingVoiceClarification(response.missingFields ?? [])
                return
            default:
                errorMessage = "That command needs a little more detail. Nothing changed."
                return
            }
            showVoiceReview = true
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "The command could not be reviewed."
        } catch {
            errorMessage = "The command could not be reviewed."
        }
    }

    private func trainingVoiceClarification(_ fields: [String]) -> String {
        let prompts = [
            "session": "start a training session",
            "exercise": "name one exercise in your current session",
            "set_number": "say the set number",
            "reps": "say the rep count",
            "rir": "say the reps in reserve",
            "weight": "say the load with a unit",
            "load_accounting": "say whether that load is per hand"
        ]
        let needed = fields.compactMap { prompts[$0] }
        if needed.isEmpty { return "That command needs a little more detail. Nothing changed." }
        return "I heard a set log. To prepare it, \(needed.joined(separator: ", and ")). Nothing was logged."
    }

    private func voiceContext(_ position: TrainingSetPosition?) -> VoiceSetContext? {
        guard let position else { return nil }
        let row = draft.row(for: position.exercise, setNumber: position.setNumber)
        guard let reps = Int(row.repsText) else { return nil }
        let load: Double?
        do { load = try TrainingLoadInputPolicy.loadKg(from: row.loadText) } catch { return nil }
        return VoiceSetContext(
            exerciseId: position.exercise.id,
            exerciseName: position.exercise.name,
            setNumber: position.setNumber,
            reps: reps,
            loadKg: load,
            rir: row.rir
        )
    }

    private var reviewActionTitle: String {
        switch voiceReview {
        case .log: "Log set"
        case .correct: "Save correction"
        case .action: "Apply"
        case .feedback: "Save observation"
        case nil: "Continue"
        }
    }

    private var reviewMessage: String {
        switch voiceReview {
        case .log(let proposal):
            "\(pendingTranscript)\n\nLog \(proposal.reps) reps, \(proposal.rir) RIR for \(proposal.exerciseName), set \(proposal.setNumber)?"
        case .correct(let proposal):
            "\(pendingTranscript)\n\nCorrect \(proposal.exerciseName), set \(proposal.setNumber) to \(proposal.reps) reps?"
        case .action(let action):
            "\(pendingTranscript)\n\nApply \(action.kind.replacingOccurrences(of: "_", with: " ")) for this workout?"
        case .feedback:
            "\(pendingTranscript)\n\nSave this observation for the intended set? It does not change your future plan."
        case nil:
            pendingTranscript
        }
    }

    private func confirmVoiceReview() {
        defer { voiceReview = nil }
        switch voiceReview {
        case .feedback(let proposal, let source):
            Task { await draft.recordWorkoutFeedback(proposal, source: source, send: onFeedback) }
        case .log(let proposal):
            guard let current = draft.currentPosition, current.id == "\(proposal.exerciseId)-\(proposal.setNumber)" else {
                errorMessage = VoiceSetAdmission.rejectedLogMessage
                return
            }
            draft.update(current.exercise, setNumber: current.setNumber) {
                $0.repsText = String(proposal.reps)
                $0.loadText = TrainingLoadInputPolicy.savedText(for: proposal.loadKg)
                $0.rir = proposal.rir
            }
            Task { await log(current.exercise, setNumber: current.setNumber) }
        case .correct(let proposal):
            guard let last = draft.lastCompletedPosition, last.id == "\(proposal.exerciseId)-\(proposal.setNumber)" else {
                errorMessage = VoiceSetAdmission.rejectedLogMessage
                return
            }
            draft.beginCorrection(last)
            draft.update(last.exercise, setNumber: last.setNumber) {
                $0.repsText = String(proposal.reps)
                $0.loadText = TrainingLoadInputPolicy.savedText(for: proposal.loadKg)
                $0.rir = proposal.rir
            }
            Task { await saveCorrection(last) }
        case .action(let action):
            performAction(action)
        case nil:
            break
        }
    }

    private func saveFeedback() async {
        guard !isSaving, !draft.isSaving, !feedbackSaved else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let muscles: [String: TrainingMuscleFeedbackRequest]? = feedbackMuscle.isEmpty ? nil : [
                feedbackMuscle: TrainingMuscleFeedbackRequest(
                    soreness: soreness,
                    recovery: muscleRecovery == "unknown" ? nil : muscleRecovery,
                    pump: pump,
                    workload: nil,
                    performance: performance
                )
            ]
            let request = TrainingFeedbackRequest(
                sessionId: draft.session.id,
                soreness: feedbackMuscle.isEmpty ? soreness : nil,
                pump: feedbackMuscle.isEmpty ? pump : nil,
                performance: feedbackMuscle.isEmpty ? performance : nil,
                jointPain: jointPain,
                muscles: muscles
            )
            if readinessEnabled {
                feedbackSaved = await draft.recordFeedback(request, send: onFeedback)
            } else {
                _ = try await onFeedback(request)
                feedbackSaved = true
            }
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "The check-in could not be saved."
        } catch {
            errorMessage = "The check-in could not be saved."
        }
    }

    private var feedbackMuscles: [String] {
        var seen = Set<String>()
        return draft.session.exercises.compactMap { exercise in
            seen.insert(exercise.primaryMuscle).inserted ? exercise.primaryMuscle : nil
        }
    }
}

struct VoiceSetReviewView: View {
    let session: TrainingSession
    let heard: VoiceHeardIntent
    let onLogSet: (VoiceSetProposal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedExerciseID: String?
    @State private var selectedSetNumber: Int?

    private var selectedExercise: TrainingExercisePrescription? {
        session.exercises.first(where: { $0.id == selectedExerciseID })
    }

    private var spokenLoadDescription: String {
        guard let loadValue = heard.loadValue else { return "Bodyweight" }
        let unit = heard.weightUnit ?? ""
        let spoken = "\(loadValue.formatted()) \(unit)".trimmingCharacters(in: .whitespaces)
        guard let loadKg = heard.loadKg else { return spoken }
        return "\(spoken) (\(String(format: "%.1f", loadKg)) kg)"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Check the exercise and set before saving.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("Exercise", selection: $selectedExerciseID) {
                    Text("Choose an exercise").tag(String?.none)
                    ForEach(session.exercises) { exercise in
                        Text(exercise.name).tag(Optional(exercise.id))
                    }
                }
                .accessibilityIdentifier("voice_set_exercise_picker")

                Picker("Set number", selection: $selectedSetNumber) {
                    Text("Choose a set").tag(Int?.none)
                    if let selectedExercise {
                        ForEach(1...max(1, selectedExercise.sets), id: \.self) { number in
                            Text("Set \(number)").tag(Optional(number))
                        }
                    }
                }
                .disabled(selectedExercise == nil)
                .accessibilityIdentifier("voice_set_number_picker")

                Text("\(heard.reps) reps · \(spokenLoadDescription) · \(heard.rir) RIR")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityIdentifier("voice_set_heard_values")

                Spacer(minLength: 0)

                Button(action: confirm) {
                    Text("Log set")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color.primary, in: Capsule())
                }
                .disabled(selectedExercise == nil || selectedSetNumber == nil)
                .accessibilityIdentifier("voice_set_log_confirm")
            }
            .padding(20)
            .navigationTitle("Review set")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity, minHeight: JovieTokens.minimumHitTarget)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("voice_set_review_cancel_button")
                .padding(.horizontal, JovieTokens.screenInset)
                .padding(.vertical, JovieTokens.itemGap)
            }
            .onChange(of: selectedExerciseID) { _, _ in
                selectedSetNumber = nil
                guard let selectedExercise,
                      let setNumber = heard.setNumber,
                      (1...max(1, selectedExercise.sets)).contains(setNumber)
                else { return }
                selectedSetNumber = setNumber
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func confirm() {
        guard let selectedExercise, let selectedSetNumber else { return }
        onLogSet(
            VoiceSetProposal(
                sessionId: session.id,
                exerciseId: selectedExercise.id,
                exerciseName: selectedExercise.name,
                setNumber: selectedSetNumber,
                reps: heard.reps,
                loadKg: heard.loadKg,
                rir: heard.rir
            )
        )
        dismiss()
    }
}

#if DEBUG
/// Uses the production live view with isolated synthetic acknowledgments; never contacts a service.
struct TrainingLiveSessionFixtureView: View {
    private static let defaults = UserDefaults(suiteName: "lyb.training.ui-fixture")!
    private static let draftStore = TrainingDraftStore(
        rootURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TrainingDrafts-UIFixture", isDirectory: true)
    )
    @State private var savedSets: [TrainingSavedSet]
    @State private var presented = false
    @State private var showEnrollment = false
    @State private var showVoiceReview = false
    @State private var showStopCard = false
    @State private var stopCount = 0
    @State private var offline = false
    @State private var submissionCount = 0

    init() {
        if ProcessInfo.processInfo.arguments.contains("-lybUITestResetTrainingFixture") {
            Self.defaults.removeObject(forKey: "savedSets")
            Self.defaults.removeObject(forKey: "submissionCount")
            try? Self.draftStore.purge(ownerId: "fixture-training-owner")
        }
        if ProcessInfo.processInfo.arguments.contains("-lybUITestTrainingExpiredRest"),
           Self.defaults.data(forKey: "savedSets") == nil {
            let seed = TrainingSavedSet(
                sessionId: "fixture-training-session", exerciseId: "fixture_press", setNumber: 1,
                reps: 9, loadKg: 60, rir: 1,
                completedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120))
            )
            Self.defaults.set(try? JSONEncoder().encode([seed]), forKey: "savedSets")
        }
        let data = Self.defaults.data(forKey: "savedSets") ?? Data("[]".utf8)
        _savedSets = State(initialValue: (try? JSONDecoder().decode([TrainingSavedSet].self, from: data)) ?? [])
        _submissionCount = State(initialValue: Self.defaults.integer(forKey: "submissionCount"))
    }

    private var session: TrainingSession {
        TrainingSession(
            id: "fixture-training-session", week: 2, slot: 0, pattern: "A", title: "Fixture training",
            exercises: [
                TrainingExercisePrescription(
                    id: "fixture_press", name: "Fixture press", primaryMuscle: "chest",
                    muscleContribution: ["chest": 1], sets: 2, repRange: .init(min: 8, max: 12),
                    targetReps: 10, targetRir: 3,
                    targetLoadKg: ProcessInfo.processInfo.arguments.contains("-lybUITestTrainingBlankLoad") ? nil : 60,
                    loadInstruction: "Repeat last session’s load.", progression: "hold", evidenceIds: []
                )
            ],
            safetyStop: false, explanation: nil, evidenceIds: [],
            loggedSets: ProcessInfo.processInfo.arguments.contains("-lybUITestTrainingLostResponse") ? [] : savedSets
        )
    }

    private var progressFixture: TrainingProgressResponse {
        let recorded = TrainingProgress.RecordedSet(
            id: "history-set", sessionId: "history-session", exerciseId: "fixture_press",
            setNumber: 1, reps: 8, loadKg: 12.5, rir: 2,
            completedAt: "2026-10-24T12:00:00.000Z", revision: 0, corrections: nil
        )
        return TrainingProgressResponse(version: 1, progress: TrainingProgress(
            enrolled: true, completedSessions: 1, setsLast7Days: 1,
            exercises: [.init(
                exerciseId: "fixture_press", name: "Fixture press", lastPerformedAt: recorded.completedAt,
                lastSession: [recorded], heaviestSet: recorded, totalSets: 1
            )], latestCheckIn: nil, sessions: []
        ))
    }

    var body: some View {
        VStack(spacing: 20) {
            Button("Open fixture session") { presented = true }
                .accessibilityIdentifier("training_fixture_open")
            Button("Open enrollment") { showEnrollment = true }
                .accessibilityIdentifier("training_fixture_enroll")
            Button("Open voice review") { showVoiceReview = true }
                .accessibilityIdentifier("training_fixture_voice_review")
            Button("Open stop card") { showStopCard = true }
                .accessibilityIdentifier("training_fixture_stop_card")
            if showStopCard {
                TrainingCoachCard(session: session, onStart: {}, onStop: { stopCount += 1 })
            }
            Text("Stops: \(stopCount)")
                .accessibilityIdentifier("training_fixture_stop_count")
            Toggle("Offline fixture", isOn: $offline)
                .accessibilityIdentifier("training_fixture_offline")
            Text("Acknowledged sets: \(savedSets.count)")
                .accessibilityIdentifier("training_fixture_count")
            Text("Submissions: \(submissionCount)")
                .accessibilityIdentifier("training_fixture_submissions")
            if let saved = savedSets.first {
                Text("Saved load: \(saved.loadKg.map { TrainingLoadInputPolicy.savedText(for: $0) } ?? "bodyweight")")
                    .accessibilityIdentifier("training_fixture_saved_load")
            }
        }
        .padding(20)
        .sheet(isPresented: $presented) {
            TrainingLiveSessionView(
                session: session, ownerId: "fixture-training-owner", voiceEnabled: true,
                readinessEnabled: true,
                progressEnabled: ProcessInfo.processInfo.arguments.contains("-lybUITestTrainingProgress"),
                draftStore: Self.draftStore,
                isCurrent: { true }, onLogSet: { exercise, number, reps, load, rir in
                    submissionCount += 1
                    Self.defaults.set(submissionCount, forKey: "submissionCount")
                    guard !offline else { throw URLError(.notConnectedToInternet) }
                    let losesResponse = savedSets.isEmpty &&
                        ProcessInfo.processInfo.arguments.contains("-lybUITestTrainingLostResponse")
                    let saved = TrainingSavedSet(
                        sessionId: session.id, exerciseId: exercise.id, setNumber: number,
                        reps: reps, loadKg: load, rir: rir,
                        completedAt: ISO8601DateFormatter().string(from: Date())
                    )
                    savedSets.removeAll { $0.exerciseId == exercise.id && $0.setNumber == number }
                    savedSets.append(saved)
                    Self.defaults.set(try JSONEncoder().encode(savedSets), forKey: "savedSets")
                    if losesResponse { throw URLError(.networkConnectionLost) }
                    return saved
                }, onCorrectSet: { request in
                    guard !offline else { throw URLError(.notConnectedToInternet) }
                    let saved = TrainingSavedSet(
                        sessionId: request.sessionId,
                        exerciseId: request.exerciseId,
                        setNumber: request.setNumber,
                        reps: request.reps,
                        loadKg: request.loadKg,
                        rir: request.rir,
                        revision: request.expectedRevision + 1,
                        corrections: [
                            TrainingSetCorrectionAudit(
                                id: request.correctionId,
                                correctedAt: "2026-10-12T00:00:00.000Z",
                                previous: .init(reps: 10, loadKg: 60, rir: 3)
                            )
                        ]
                    )
                    savedSets.removeAll { $0.exerciseId == request.exerciseId && $0.setNumber == request.setNumber }
                    savedSets.append(saved)
                    Self.defaults.set(try JSONEncoder().encode(savedSets), forKey: "savedSets")
                    return saved
                }, onUndoSet: { request in
                    guard !offline else { throw URLError(.notConnectedToInternet) }
                    let current = savedSets.first {
                        $0.exerciseId == request.exerciseId && $0.setNumber == request.setNumber
                    }
                    let saved = TrainingSavedSet(
                        sessionId: request.sessionId,
                        exerciseId: request.exerciseId,
                        setNumber: request.setNumber,
                        reps: current?.corrections?.last?.previous.reps ?? current?.reps ?? 10,
                        loadKg: current?.corrections?.last?.previous.loadKg ?? current?.loadKg,
                        rir: current?.corrections?.last?.previous.rir ?? current?.rir ?? 3,
                        revision: request.expectedRevision + 1,
                        corrections: (current?.corrections ?? []) + [
                            TrainingSetCorrectionAudit(
                                id: request.undoId,
                                correctedAt: "2026-10-12T00:00:00.000Z",
                                previous: .init(
                                    reps: current?.reps ?? 10,
                                    loadKg: current?.loadKg,
                                    rir: current?.rir ?? 3
                                )
                            )
                        ]
                    )
                    savedSets.removeAll { $0.exerciseId == request.exerciseId && $0.setNumber == request.setNumber }
                    savedSets.append(saved)
                    Self.defaults.set(try JSONEncoder().encode(savedSets), forKey: "savedSets")
                    return saved
                }, onWorkoutAction: { _ in
                    guard !offline else { throw URLError(.notConnectedToInternet) }
                    return session
                }, onVoiceIntent: { _, _, _, _ in
                    throw VoiceAPIError.unavailable
                }, onFeedback: { request in
                    guard !offline else { throw URLError(.notConnectedToInternet) }
                    // Synthetic server receipt for UI wiring only; the production engine is tested separately.
                    return TrainingFeedbackResponse(
                        version: 1,
                        feedback: .init(id: request.sourceObservationId ?? "fixture-feedback", observation: request),
                        nextSetRecommendation: .init(
                            scope: "between_set",
                            action: request.breathingReadiness == "limited" ? .extendRest :
                                request.supportingReadiness?.grip == "limited" ? .adjustOrSkip :
                                request.targetMuscleReadiness == "ready" ? .proceed : .clarify,
                            reasons: ["Fixture observation; timer expiry is advisory."], uncertainty: "moderate",
                            observationIds: [request.sourceObservationId ?? "fixture-feedback"],
                            weeklyPlanChanged: false, safetyCertified: false
                        )
                    )
                }, onLoadProgress: {
                    if ProcessInfo.processInfo.arguments.contains("-lybUITestTrainingHistoryUnavailable") {
                        throw URLError(.notConnectedToInternet)
                    }
                    return progressFixture
                }
            )
        }
        .sheet(isPresented: $showEnrollment) {
            TrainingEnrollmentView { _, _ in }
        }
        .sheet(isPresented: $showVoiceReview) {
            VoiceSetReviewView(
                session: session,
                heard: VoiceHeardIntent(
                    setNumber: 1,
                    reps: 8,
                    loadValue: 60,
                    weightUnit: "kg",
                    loadKg: 60,
                    rir: 2
                ),
                onLogSet: { _ in }
            )
        }
    }
}
#endif
