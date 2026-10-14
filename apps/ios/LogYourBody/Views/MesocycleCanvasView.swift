import SwiftUI

struct MesocycleCanvasCards: View {
    let plan: CanvasPlan
    var highlights: [String: String] = [:]
    var interactive: Bool = false
    var onMoveNext: (CanvasExercise) -> Void = { _ in }
    var onDrop: (String, String, String) -> Void = { _, _, _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !plan.goals.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Muscle goals")
                            .font(.headline)
                            .accessibilityIdentifier("mesocycle_canvas_goals")
                        ForEach(plan.goals) { goal in
                            Text("\(goal.label): \(goal.role), \(goal.weeklySets, specifier: "%.2f") weekly sets")
                                .accessibilityIdentifier("mesocycle_goal_\(goal.id)")
                        }
                    }
                }
                ForEach(plan.days) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(day.label).font(.title3.weight(.semibold))
                        ForEach(day.sessions) { session in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(session.title).font(.subheadline.weight(.semibold))
                                ForEach(session.exercises) { exercise in
                                    exerciseCard(exercise)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                            .dropDestination(for: String.self) { items, _ in
                                guard interactive, let instanceId = items.first else { return false }
                                onDrop(instanceId, day.id, session.id)
                                return true
                            }
                            .accessibilityIdentifier("mesocycle_session_\(session.id)")
                        }
                    }
                    .accessibilityIdentifier("mesocycle_day_\(day.id)")
                }
            }
            .padding(16)
        }
    }

    private func exerciseCard(_ exercise: CanvasExercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.name).font(.body.weight(.semibold))
            Text("\(exercise.sets) sets · \(exercise.repRange.min)-\(exercise.repRange.max) reps · \(exercise.priority)")
                .font(.footnote)
            if interactive {
                Button("Move \(exercise.name) to the next day") { onMoveNext(exercise) }
                    .accessibilityIdentifier("mesocycle_move_\(exercise.instanceId)")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(border(highlights[exercise.instanceId]), lineWidth: 2))
        .draggable(exercise.instanceId)
        .accessibilityIdentifier("mesocycle_exercise_\(exercise.instanceId)")
        .accessibilityValue(highlights[exercise.instanceId] ?? exercise.priority)
    }

    private func border(_ change: String?) -> Color {
        switch change {
        case "added": return .green
        case "moved": return .blue
        case "replaced": return .yellow
        case "updated": return .purple
        case "kept": return .gray
        default: return .clear
        }
    }
}

struct MesocycleCanvasEditor: View {
    @Binding var journal: CanvasJournal
    var reducesMotion: Bool
    var onPersist: (CanvasJournal) -> Void
    @State private var text = ""
    @State private var message = ""
    @State private var checked: Set<String> = []
    @State private var sequence = 1

    private var pending: CanvasProposal? {
        journal.proposals.last { $0.status == "proposed" }
    }

    private var shown: CanvasPlan? {
        pending?.preview ?? journal.persistedPlan
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(message)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("mesocycle_canvas_live")
            Text(readback)
                .font(.caption2)
                .accessibilityIdentifier("mesocycle_canvas_readback")
            if let pending {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview. The saved plan changes only when you accept.")
                    Text(pending.source).accessibilityIdentifier("mesocycle_canvas_preview_source")
                    ForEach(pending.ops, id: \.id) { op in
                        Toggle(opLabel(op), isOn: Binding(
                            get: { checked.contains(op.id) || checked.isEmpty },
                            set: { isOn in
                                if checked.isEmpty { checked = Set(pending.ops.map(\.id)) }
                                if isOn { checked.insert(op.id) } else { checked.remove(op.id) }
                            }
                        ))
                    }
                    HStack {
                        Button("Accept") { decide("apply") }.accessibilityIdentifier("mesocycle_canvas_accept")
                        Button("Reject") { decide("reject") }.accessibilityIdentifier("mesocycle_canvas_reject")
                    }
                }
                .padding(16)
                .accessibilityIdentifier("mesocycle_canvas_preview")
            }
            if let shown {
                MesocycleCanvasCards(
                    plan: shown,
                    highlights: (pending?.highlights ?? []).reduce(into: [String: String]()) { marks, highlight in
                        marks[highlight.instanceId] = highlight.change
                    },
                    interactive: pending == nil,
                    onMoveNext: moveNext,
                    onDrop: drop
                )
            } else {
                Text("No saved plan")
                    .padding(16)
                    .accessibilityIdentifier("mesocycle_canvas_empty")
            }
            HStack {
                TextField("Plan message", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .disabled(pending != nil)
                    .accessibilityIdentifier("mesocycle_canvas_composer")
                Button("Send") { submit("chat") }
                    .disabled(pending != nil || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("mesocycle_canvas_send")
                Button("Send voice") { submit("voice") }
                    .disabled(pending != nil || text.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("mesocycle_canvas_voice")
            }
            .padding(16)
        }
        .accessibilityIdentifier("mesocycle_canvas_board")
    }

    private var readback: String {
        guard let plan = journal.persistedPlan else { return "No saved plan" }
        return plan.days.flatMap { day in
            day.sessions.flatMap { session in session.exercises.map { "\($0.instanceId)|\($0.name)|\($0.sets)" } }
        }.joined(separator: "\n")
    }

    private func submit(_ source: String) {
        let utterance = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pending == nil, !utterance.isEmpty else { return }
        let command = CanvasPropose(
            requestId: "req-\(sequence)", expectedGeneration: journal.generation, baseRevisionId: journal.revisionId,
            source: source, text: utterance, ops: nil
        )
        sequence += 1
        text = ""
        commit(.propose(command))
    }

    private func decide(_ decision: String) {
        guard let pending else { return }
        let ids = checked.isEmpty ? pending.ops.map(\.id) : pending.ops.map(\.id).filter { checked.contains($0) }
        let command = CanvasDecide(
            requestId: "req-\(sequence)", proposalId: pending.id, expectedGeneration: journal.generation,
            decision: decision, acceptedOpIds: ids, setEdits: nil
        )
        sequence += 1
        checked = []
        commit(.decide(command))
    }

    private func moveNext(_ exercise: CanvasExercise) {
        guard let plan = shown, pending == nil else { return }
        guard let index = plan.days.firstIndex(where: { day in
            day.sessions.contains { $0.exercises.contains { $0.instanceId == exercise.instanceId } }
        }) else { return }
        let day = plan.days[(index + 1) % plan.days.count]
        guard let session = day.sessions.first else { return }
        drop(exercise.instanceId, day.id, session.id)
    }

    private func drop(_ instanceId: String, _ dayId: String, _ sessionId: String) {
        guard pending == nil else { return }
        let command = CanvasPropose(
            requestId: "req-\(sequence)", expectedGeneration: journal.generation, baseRevisionId: journal.revisionId,
            source: "direct", text: nil,
            ops: [CanvasOp(
                id: "drag-\(instanceId)-\(sequence)", kind: "move", target: nil, count: nil, day: nil, toVariantId: nil,
                item: nil, instanceId: instanceId, toDay: dayId, toSessionId: sessionId, toIndex: 0, sets: nil
            )]
        )
        sequence += 1
        commit(.propose(command))
    }

    private func commit(_ command: CanvasCommand) {
        let reduced = MesocycleCanvasRevision.reduce(journal: journal, command: command)
        message = reduced.narration
        guard reduced.persist else { return }
        if reducesMotion {
            journal = reduced.journal
        } else {
            withAnimation { journal = reduced.journal }
        }
        onPersist(journal)
    }

    private func opLabel(_ op: CanvasOp) -> String {
        switch op.kind {
        case "prioritize": return op.target == "upper_chest" ? "Prioritize upper chest" : "Prioritize triceps"
        case "training_days": return "Train five days"
        case "split_day": return "Split Wednesday into AM and PM"
        case "swap_variant": return "Swap incline dumbbell press for Smith machine incline press"
        case "declare_equipment": return "Declare Smith machine"
        case "draft": return "Accept the coach draft"
        case "undo": return "Undo the last accepted edit"
        case "redo": return "Redo the undone edit"
        default: return op.kind
        }
    }
}

struct MesocycleCanvasRemoteView: View {
    let load: () async throws -> CanvasPlan?
    @State private var plan: CanvasPlan?
    @State private var message = "Loading the saved mesocycle."

    var body: some View {
        Group {
            if let plan {
                MesocycleCanvasCards(plan: plan)
            } else {
                Text(message)
                    .padding(24)
                    .accessibilityIdentifier("mesocycle_canvas_remote")
            }
        }
        .task {
            do {
                if let loaded = try await load() {
                    plan = loaded
                } else {
                    message = "No saved mesocycle yet."
                }
            } catch {
                message = "The saved mesocycle could not be loaded."
            }
        }
    }
}

#if DEBUG
struct MesocycleCanvasFixtureView: View {
    private static let defaults = UserDefaults(suiteName: "lyb.mesocycle-canvas.ui-fixture")!
    @State private var journal: CanvasJournal

    init() {
        if ProcessInfo.processInfo.arguments.contains("-lybUITestResetMesocycleCanvas") {
            Self.defaults.removeObject(forKey: "journal")
        }
        let stored = Self.defaults.data(forKey: "journal")
            .flatMap { try? JSONDecoder().decode(CanvasJournal.self, from: $0) } ?? .empty
        _journal = State(initialValue: stored)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(reducesMotion ? "Motion reduced" : "Motion standard")
                .accessibilityIdentifier("mesocycle_canvas_motion")
            MesocycleCanvasEditor(journal: $journal, reducesMotion: reducesMotion) { next in
                if let data = try? JSONEncoder().encode(next) {
                    Self.defaults.set(data, forKey: "journal")
                }
            }
        }
    }

    private var reducesMotion: Bool {
        ProcessInfo.processInfo.arguments.contains("-lybUITestReduceMotion")
    }
}
#endif
