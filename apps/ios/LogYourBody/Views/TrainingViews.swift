import SwiftUI

enum TrainingPresentation: Identifiable {
    case setup
    case session(TrainingSession)
    case voiceSetReview(TrainingSession, VoiceHeardIntent)

    var id: String {
        switch self {
        case .setup: "setup"
        case .session(let session): "session-\(session.id)"
        case .voiceSetReview(let session, _): "voice-set-review-\(session.id)"
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
        .confirmationDialog(
            "Delete your training sessions, set logs, and feedback?",
            isPresented: $isStopConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Stop coaching and delete data", role: .destructive, action: onStop)
            Button("Cancel", role: .cancel) {}
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Starting…" : "Start") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || !adultConfirmed || !safetyConfirmed)
                    .accessibilityIdentifier("training_enroll_confirm")
                }
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

struct TrainingLiveSessionView: View {
    let session: TrainingSession
    let onLogSet: (TrainingExercisePrescription, Int, Int, Double?, Int) async throws -> Void
    let onFeedback: (Int, Int, String, Int) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var repsByKey: [String: String] = [:]
    @State private var loadByKey: [String: String] = [:]
    @State private var rirByKey: [String: Int] = [:]
    @State private var loggedSets: Set<String> = []
    @State private var soreness = 0
    @State private var pump = 0
    @State private var jointPain = 0
    @State private var performance = "stable"
    @State private var feedbackSaved = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if session.safetyStop {
                        Text(session.explanation ?? "Pause this session and seek qualified guidance if pain persists or worsens.")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.colors.textSecondary)
                            .accessibilityIdentifier("training_live_safety_stop")
                        Text("Keep training paused if pain persists or worsens. Save a new check-in " +
                            "only when your recovery has changed.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.textSecondary)
                        feedbackCard
                    } else {
                        Text("Week \(session.week) · \(session.title)")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(theme.colors.text)
                        ForEach(session.exercises) { exercise in
                            exerciseCard(exercise)
                        }
                        feedbackCard
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.appWarning)
                    }
                }
                .padding(20)
            }
            .background(theme.colors.background)
            .navigationTitle("Live session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func exerciseCard(_ exercise: TrainingExercisePrescription) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.colors.text)
                Text("\(exercise.sets) sets · \(exercise.repRange.min)–\(exercise.repRange.max) reps · \(exercise.targetRir) RIR")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                if let loadInstruction = exercise.loadInstruction {
                    Text(loadInstruction)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }

            ForEach(1...max(1, exercise.sets), id: \.self) { setNumber in
                setRow(exercise, setNumber: setNumber)
                if setNumber < exercise.sets {
                    Divider().overlay(theme.colors.border)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func setRow(_ exercise: TrainingExercisePrescription, setNumber: Int) -> some View {
        let key = setKey(exercise, setNumber: setNumber)
        return VStack(alignment: .leading, spacing: JovieTokens.tightGap) {
            Text("Set \(setNumber)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.colors.textSecondary)
            HStack(spacing: JovieTokens.tightGap) {
                TextField("Reps", text: repsBinding(for: exercise, setNumber: setNumber))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("training_reps_\(exercise.id)_\(setNumber)")
                TextField("Load kg", text: loadBinding(for: exercise, setNumber: setNumber))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("training_load_\(exercise.id)_\(setNumber)")
            }
            Stepper("\(rirBinding(for: exercise, setNumber: setNumber).wrappedValue) reps in reserve", value: rirBinding(for: exercise, setNumber: setNumber), in: 0...6)
                .font(.system(size: 13))
                .accessibilityIdentifier("training_rir_\(exercise.id)_\(setNumber)")
            Button(loggedSets.contains(key) ? "Set logged" : "Log set") {
                Task { await log(exercise, setNumber: setNumber) }
            }
            .disabled(
                loggedSets.contains(key) || isSaving ||
                    Int(repsBinding(for: exercise, setNumber: setNumber).wrappedValue) == nil
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.colors.text)
            .accessibilityIdentifier("training_log_set_\(exercise.id)_\(setNumber)")
        }
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recovery check-in")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.colors.text)
            Stepper("Soreness: \(soreness) / 10", value: $soreness, in: 0...10)
            Stepper("Pump: \(pump) / 10", value: $pump, in: 0...10)
            Stepper("Joint pain: \(jointPain) / 10", value: $jointPain, in: 0...10)
            Picker("Performance", selection: $performance) {
                Text("Down").tag("down")
                Text("Stable").tag("stable")
                Text("Up").tag("up")
            }
            .pickerStyle(.segmented)
            Button(feedbackSaved ? "Feedback saved" : session.safetyStop ? "Save updated check-in" : "Save check-in") {
                Task { await saveFeedback() }
            }
            .disabled(feedbackSaved || isSaving)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.colors.text)
            .accessibilityIdentifier("training_save_feedback")
        }
        .padding(16)
        .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func setKey(_ exercise: TrainingExercisePrescription, setNumber: Int) -> String {
        "\(exercise.id)-\(setNumber)"
    }

    private func repsBinding(for exercise: TrainingExercisePrescription, setNumber: Int) -> Binding<String> {
        let key = setKey(exercise, setNumber: setNumber)
        return Binding(get: { repsByKey[key] ?? String(exercise.targetReps) }, set: { repsByKey[key] = $0 })
    }

    private func loadBinding(for exercise: TrainingExercisePrescription, setNumber: Int) -> Binding<String> {
        let key = setKey(exercise, setNumber: setNumber)
        return Binding(get: { loadByKey[key] ?? "" }, set: { loadByKey[key] = $0 })
    }

    private func rirBinding(for exercise: TrainingExercisePrescription, setNumber: Int) -> Binding<Int> {
        let key = setKey(exercise, setNumber: setNumber)
        return Binding(get: { rirByKey[key] ?? exercise.targetRir }, set: { rirByKey[key] = $0 })
    }

    private func log(_ exercise: TrainingExercisePrescription, setNumber: Int) async {
        guard let reps = Int(repsBinding(for: exercise, setNumber: setNumber).wrappedValue) else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let loadText = loadBinding(for: exercise, setNumber: setNumber).wrappedValue
            try await onLogSet(
                exercise,
                setNumber,
                reps,
                Double(loadText),
                rirBinding(for: exercise, setNumber: setNumber).wrappedValue
            )
            loggedSets.insert(setKey(exercise, setNumber: setNumber))
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "The set could not be saved."
        } catch {
            errorMessage = "The set could not be saved."
        }
    }

    private func saveFeedback() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onFeedback(soreness, pump, performance, jointPain)
            feedbackSaved = true
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "The check-in could not be saved."
        } catch {
            errorMessage = "The check-in could not be saved."
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
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
