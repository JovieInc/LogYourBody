import SwiftUI

/// An occasional movement check-in, with unknown values preserved until explicitly reported.
struct TrainingSelectionView: View {
    @State private var exercise: TrainingExercisePrescription
    @State private var setNumber: Int
    let ownsSession: () -> Bool
    let onFeedback: (TrainingFeedbackRequest) async throws -> TrainingFeedbackResponse
    let onReview: (TrainingSelectionRequest) async throws -> TrainingSelectionResponse
    let onAction: (TrainingWorkoutActionRequest) async throws -> TrainingSession

    @State private var session: TrainingSession
    @State private var context = TrainingSelectionContext(
        gymId: "Current gym", availableEquipment: [], excludedConcerns: []
    )
    @State private var trunkFatigue: Int?
    @State private var jointPain: Int?
    @State private var generalExhaustion: Int?
    @State private var quality: String?
    @State private var stability: String?
    @State private var rom: String?
    @State private var concerningSymptoms = false
    @State private var floorBlocked = false
    @State private var setupNote = ""
    @State private var savedContext: TrainingSelectionContext?
    @State private var confirmedSetup = false
    @State private var review: TrainingSelectionResponse.Review?
    @State private var receipt: TrainingFeedbackResponse?
    @State private var pendingFeedback: TrainingFeedbackRequest?
    @State private var pendingAction: TrainingWorkoutActionRequest?
    @State private var busy = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private let equipment = [
        "dumbbells", "barbell", "ez_bar", "machine", "cable", "bench", "adjustable_bench", "bodyweight", "smith"
    ]

    init(
        session: TrainingSession, exercise: TrainingExercisePrescription, setNumber: Int,
        feedbackDraft: TrainingFeedbackDraft? = nil,
        ownsSession: @escaping () -> Bool,
        onFeedback: @escaping (TrainingFeedbackRequest) async throws -> TrainingFeedbackResponse,
        onReview: @escaping (TrainingSelectionRequest) async throws -> TrainingSelectionResponse,
        onAction: @escaping (TrainingWorkoutActionRequest) async throws -> TrainingSession
    ) {
        _exercise = State(initialValue: exercise)
        _setNumber = State(initialValue: setNumber)
        self.ownsSession = ownsSession
        self.onFeedback = onFeedback
        self.onReview = onReview
        self.onAction = onAction
        _session = State(initialValue: session)
        if let draft = feedbackDraft, draft.request.context?.exerciseId == exercise.id {
            let observation = draft.request
            _receipt = State(initialValue: draft.response)
            _pendingFeedback = State(initialValue: draft.response == nil ? observation : nil)
            _trunkFatigue = State(initialValue: observation.trunkFatigue)
            _jointPain = State(initialValue: observation.jointPain)
            _generalExhaustion = State(initialValue: observation.generalExhaustion)
            _quality = State(initialValue: observation.targetMuscleQuality)
            _stability = State(initialValue: observation.stability)
            _rom = State(initialValue: observation.context?.romRestriction)
            _concerningSymptoms = State(initialValue: !(observation.symptomFlags ?? []).isEmpty)
            _setupNote = State(initialValue: observation.context?.setup ?? "")
            _setNumber = State(initialValue: observation.context?.setNumber ?? setNumber)
            _context = State(initialValue: TrainingSelectionContext(
                gymId: observation.context?.gymId ?? "Current gym",
                availableEquipment: observation.context?.availableEquipment ?? [], excludedConcerns: []
            ))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(exercise.name) {
                    Text("Optional movement feedback. Leave anything you did not observe unreported.")
                    scorePicker("Back/trunk fatigue", value: $trunkFatigue)
                    scorePicker("Joint discomfort", value: $jointPain)
                    Toggle("Pain or concerning/neurologic symptoms", isOn: $concerningSymptoms)
                    DisclosureGroup("Muscle effort, stability and ROM") {
                        choicePicker("Target-muscle quality", value: $quality, choices: ["poor", "adequate", "good"])
                        choicePicker("Stability", value: $stability, choices: ["stable", "unstable"])
                        choicePicker("Meaningful ROM restriction", value: $rom, choices: ["none", "limited", "blocked"])
                        scorePicker("General fatigue", value: $generalExhaustion)
                    }
                }
                .disabled(busy || pendingFeedback != nil || pendingAction != nil)
                Section("This gym and setup") {
                    if let savedContext {
                        Button("Reuse equipment from \(savedContext.gymId)") {
                            context = savedContext
                            setupNote = savedContext.setupNote ?? ""
                            floorBlocked = savedContext.excludedConcerns.contains("floor_rom_blocked")
                        }
                    }
                    TextField("Gym name", text: $context.gymId)
                        .accessibilityIdentifier("training_selection_gym")
                    TextField("Setup notes (optional)", text: $setupNote)
                    Toggle("Floor blocks my curl ROM", isOn: $floorBlocked)
                    DisclosureGroup("Confirm equipment available today") {
                        ForEach(equipment, id: \.self) { item in
                            Toggle(item.replacingOccurrences(of: "_", with: " "), isOn: Binding(
                                get: { context.availableEquipment.contains(item) },
                                set: { present in
                                    context.availableEquipment.removeAll { $0 == item }
                                    if present { context.availableEquipment.append(item) }
                                }
                            ))
                        }
                    }
                    Text("A machine tag does not confirm a specific station. Check the actual option before approving.")
                        .font(.footnote)
                }
                .disabled(busy || pendingFeedback != nil || pendingAction != nil)
                Section {
                    Button(pendingFeedback == nil ? "Save feedback and review options" : "Retry feedback") {
                        Task { await saveAndReview() }
                    }
                    .accessibilityIdentifier("training_selection_review")
                    .disabled(busy || pendingAction != nil || context.gymId.trimmingCharacters(in: .whitespaces).isEmpty)
                    if receipt != nil {
                        Text("Response saved. You can correct it here.").font(.footnote)
                    }
                }
                if let review { optionsSection(review) }
                if let pendingAction {
                    Section {
                        Button("Retry saved choice") { Task { await apply(pendingAction.action) } }
                            .disabled(busy)
                    }
                }
                if let swap = session.executionEvents?.last,
                   swap.selectionContext != nil, swap.kind == "substituted" {
                    Section {
                        Text("Trial saved for today. Repeated positive responses can retain it for this block.")
                        Button("Undo this swap") {
                            var action = TrainingWorkoutAction(kind: "restore_swap", exerciseId: nil, minutes: nil)
                            action.swapEventId = swap.id
                            Task { await apply(action) }
                        }
                        .accessibilityIdentifier("training_selection_undo")
                        .disabled(busy)
                        Text("Undo is available before recording sets for the replacement.").font(.footnote)
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(Color.appWarning) } }
            }
            .navigationTitle("Movement response")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: context) { _, _ in review = nil; confirmedSetup = false }
            .onChange(of: floorBlocked) { _, _ in review = nil; confirmedSetup = false }
            .onChange(of: trunkFatigue) { _, _ in invalidateReview() }
            .onChange(of: jointPain) { _, _ in invalidateReview() }
            .onChange(of: generalExhaustion) { _, _ in invalidateReview() }
            .onChange(of: quality) { _, _ in invalidateReview() }
            .onChange(of: stability) { _, _ in invalidateReview() }
            .onChange(of: rom) { _, _ in invalidateReview() }
            .onChange(of: concerningSymptoms) { _, _ in invalidateReview() }
            .onChange(of: setupNote) { _, _ in invalidateReview() }
            .task {
                guard ownsSession() else { return }
                if let response = try? await onReview(.init(
                    sessionId: session.id, exerciseId: exercise.id, context: context
                )), ownsSession() { savedContext = response.review.preferredContext }
            }
        }
    }

    private func invalidateReview() {
        review = nil
        confirmedSetup = false
    }

    private func scorePicker(_ title: String, value: Binding<Int?>) -> some View {
        Picker(title, selection: value) {
            Text("Not reported").tag(nil as Int?)
            ForEach(0...10, id: \.self) { Text("\($0)/10").tag(Optional($0)) }
        }
    }

    private func choicePicker(_ title: String, value: Binding<String?>, choices: [String]) -> some View {
        Picker(title, selection: value) {
            Text("Not reported").tag(nil as String?)
            ForEach(choices, id: \.self) { Text($0.capitalized).tag(Optional($0)) }
        }
    }

    private func optionsSection(_ review: TrainingSelectionResponse.Review) -> some View {
        Section("Review options") {
            Text(review.message).font(.footnote)
            if review.options.isEmpty && review.status != "symptom_safety" {
                Text("No supported option fits the current observations and confirmed equipment. " +
                     "You can correct the feedback or skip today.")
            }
            Toggle("I checked the station, clearance, cable line and comfortable range", isOn: $confirmedSetup)
            ForEach(review.options) { option in
                Text(option.name).font(.headline)
                Text(option.reasonText).font(.footnote)
                TrainingVariantSetupView(variantId: option.variantId, setup: option.setup)
                Button("Approve trial: \(option.name)") {
                    var action = TrainingWorkoutAction.swap(exercise.id, with: option.variantId)
                    action.selectionContext = review.context
                    Task { await apply(action) }
                }
                .accessibilityIdentifier("training_selection_approve_\(option.variantId)")
                .disabled(busy || pendingAction != nil || !confirmedSetup || review.revision != (session.executionRevision ?? 0))
            }
        }
    }

    @MainActor private func saveAndReview() async {
        guard ownsSession(), !busy else { return }
        busy = true
        errorMessage = nil
        review = nil
        defer { busy = false }
        do {
            context.gymId = context.gymId.trimmingCharacters(in: .whitespacesAndNewlines)
            let note = setupNote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !context.gymId.isEmpty, context.gymId.utf16.count <= 80, note.utf16.count <= 160 else {
                errorMessage = "Enter a gym name and use a shorter gym name or setup note."
                return
            }
            context.excludedConcerns = floorBlocked ? ["floor_rom_blocked"] : []
            context.setupNote = note.isEmpty ? nil : note
            var feedback = pendingFeedback ?? TrainingFeedbackRequest(sessionId: session.id, jointPain: jointPain)
            if pendingFeedback == nil {
                feedback.context = .init(exerciseId: exercise.id, setNumber: setNumber,
                                         gymId: context.gymId, setup: context.setupNote, romRestriction: rom)
                feedback.context?.availableEquipment = context.availableEquipment
                feedback.trunkFatigue = trunkFatigue
                feedback.generalExhaustion = generalExhaustion
                feedback.targetMuscleQuality = quality
                feedback.stability = stability
                feedback.symptomFlags = concerningSymptoms ? ["other_concerning"] : nil
                feedback.sourceObservationId = UUID().uuidString
                feedback.correctsObservationId = receipt?.feedback.id
            }
            pendingFeedback = feedback
            receipt = try await onFeedback(feedback)
            guard ownsSession() else { return }
            pendingFeedback = nil
            if concerningSymptoms || (jointPain ?? 0) > 0 {
                session = try await onAction(actionRequest(.pain(exercise.id)))
            }
            let response = try await onReview(.init(sessionId: session.id, exerciseId: exercise.id, context: context))
            guard ownsSession() else { return }
            review = response.review
        } catch { errorMessage = error.localizedDescription }
    }

    private func actionRequest(_ action: TrainingWorkoutAction) -> TrainingWorkoutActionRequest {
        .init(sessionId: session.id, eventId: UUID().uuidString,
              expectedRevision: session.executionRevision ?? 0, action: action)
    }

    @MainActor private func apply(_ action: TrainingWorkoutAction) async {
        guard ownsSession(), !busy else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            let request = pendingAction ?? actionRequest(action)
            pendingAction = request
            session = try await onAction(request)
            guard ownsSession() else { return }
            if let replacementId = session.executionEvents?.last?.replacementExerciseId,
               let replacement = session.exercises.first(where: { $0.id == replacementId }) {
                exercise = replacement
                setNumber = 1
                receipt = nil
                trunkFatigue = nil
                jointPain = nil
                generalExhaustion = nil
                quality = nil
                stability = nil
                rom = nil
            }
            pendingAction = nil
            review = nil
        } catch {
            if !(error is URLError), (error as? TrainingServiceError) != .invalidResponse { pendingAction = nil }
            errorMessage = error.localizedDescription
        }
    }
}
