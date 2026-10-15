import SwiftUI

enum MesocycleCanvasPolicy {
    static let featureGate = "mesocycle_canvas_v1"

    static func isEnabled(checkGate: (String) -> Bool) -> Bool {
        checkGate(featureGate)
    }
}

struct CanvasClientRequest {
    var action: String
    var transcript: String?
    var proposalId: String?
    var decision: String?
    var instanceId: String?
    var sets: Int?
    var operation: [String: Any]?
    var expectedWrite: Int?

    var operationKind: String? { operation?["kind"] as? String }
    var toDay: String? { operation?["toDay"] as? String }
    var toSlot: String? { operation?["toSlot"] as? String }
    var exerciseName: String? { operation?["exerciseName"] as? String }
    var declareEquipment: [String]? { operation?["declareEquipment"] as? [String] }
    var resolvedInstanceId: String? { instanceId ?? operation?["instanceId"] as? String }
    var resolvedSets: Int? { sets ?? operation?["sets"] as? Int }

    func jsonObject() -> [String: Any] {
        var body: [String: Any] = ["action": action, "expectedWrite": expectedWrite ?? NSNull()]
        switch action {
        case "submit":
            body["transcript"] = transcript ?? ""
        case "propose":
            body["operation"] = operation ?? [:]
        case "decide":
            body["proposalId"] = proposalId ?? ""
            body["decision"] = decision ?? ""
        case "amend":
            body["proposalId"] = proposalId ?? ""
            body["instanceId"] = instanceId ?? ""
            body["sets"] = sets ?? 0
        default:
            break
        }
        return body
    }
}

struct CanvasExercise: Codable, Equatable, Identifiable {
    var id: String { instanceId }
    let instanceId: String
    let variantId: String
    let name: String
    let sets: Int
    let targetReps: Int
    let priority: String
}

struct CanvasSession: Codable, Equatable, Identifiable {
    let id: String
    let day: String
    let slot: String
    let title: String
    let exercises: [CanvasExercise]
}

struct CanvasPlan: Codable, Equatable {
    let revision: Int
    let sessions: [CanvasSession]
}

struct CanvasMuscleGoal: Codable, Equatable, Identifiable {
    let id: String
    let label: String
    let role: String
    let weeklySets: Double
}

struct CanvasPerformedExercise: Codable, Equatable {
    let instanceId: String
    let variantId: String
    let name: String
    let sets: Int
    let targetReps: Int
}

struct CanvasExecutionSession: Codable, Equatable, Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let day: String
    let slot: String
    let title: String
    let exercises: [CanvasPerformedExercise]
}

struct CanvasChange: Codable, Equatable, Identifiable {
    var id: String { "\(kind)-\(instanceId)-\(reason)" }
    let kind: String
    let instanceId: String
    let name: String?
    let toName: String?
    let fromName: String?
    let reason: String
    let sets: Int?
    let day: String?
    let toDay: String?
    let toSlot: String?
}

struct CanvasProposalBody: Codable, Equatable {
    let id: String
    let changes: [CanvasChange]
}

struct CanvasProposalEnvelope: Codable, Equatable {
    let status: String
    let proposal: CanvasProposalBody
}

struct CanvasReadback: Codable, Equatable {
    let version: Int
    let write: Int?
    let generation: Int
    let plan: CanvasPlan?
    let goals: [CanvasMuscleGoal]
    let weeklyTotals: [String: Double]
    let execution: [CanvasExecutionSession]
    let proposal: CanvasProposalEnvelope?
    var narration: String

    static let empty = CanvasReadback(
        version: 1, write: nil, generation: 0, plan: nil, goals: [], weeklyTotals: [:],
        execution: [], proposal: nil, narration: ""
    )
}

struct CanvasCommandResponse: Codable, Equatable {
    let version: Int?
    let kind: String
    let readback: CanvasReadback
    let missing: [String]?
}

enum CanvasAgreement {
    static func agrees(_ readback: CanvasReadback) -> Bool {
        agrees(plan: readback.plan, execution: readback.execution)
    }

    static func agrees(plan: CanvasPlan?, execution: [CanvasExecutionSession]) -> Bool {
        guard let plan else { return execution.isEmpty }
        guard plan.sessions.count == execution.count else { return false }
        for (session, workout) in zip(plan.sessions, execution) {
            guard session.id == workout.sessionId, session.day == workout.day, session.slot == workout.slot,
                  session.exercises.count == workout.exercises.count else { return false }
            for (card, performed) in zip(session.exercises, workout.exercises) {
                guard card.instanceId == performed.instanceId, card.variantId == performed.variantId,
                      card.sets == performed.sets, card.targetReps == performed.targetReps else { return false }
            }
        }
        return true
    }

    static func fingerprint(_ plan: CanvasPlan?) -> String {
        guard let plan else { return "none" }
        let rows = plan.sessions.map { session in
            let exercises = session.exercises.map { "\($0.instanceId)#\($0.sets)#\($0.variantId)" }.joined(separator: ",")
            return "\(session.id):\(exercises)"
        }.joined(separator: "|")
        return "\(plan.revision)|\(rows)"
    }
}

protocol CanvasSnapshotStoring: AnyObject {
    func load() -> Data?
    func save(_ data: Data)
}

final class MemoryCanvasStore: CanvasSnapshotStoring {
    private var data: Data?
    func load() -> Data? { data }
    func save(_ data: Data) { self.data = data }
}

final class UserDefaultsCanvasStore: CanvasSnapshotStoring {
    private let defaults: UserDefaults
    private let key: String

    init(subject: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = "lyb.mesocycle-canvas.v1.\(subject)"
    }

    func load() -> Data? { defaults.data(forKey: key) }
    func save(_ data: Data) { defaults.set(data, forKey: key) }
}

protocol MesocycleCanvasServicing: AnyObject {
    func perform(_ request: CanvasClientRequest, accessToken: String) async throws -> CanvasCommandResponse
}

extension URLSessionTrainingService: MesocycleCanvasServicing {}

struct CanvasScriptMatch: Decodable {
    let action: String
    let transcript: String?
    let decision: String?
    let operationKind: String?
    let toDay: String?
    let toSlot: String?
    let declareEquipment: [String]?
    let sets: Int?
    let instanceId: String?
    let exerciseName: String?
    let expectedWrite: Int?
    let checkWrite: Bool

    func matches(_ request: CanvasClientRequest) -> Bool {
        if action != request.action { return false }
        if let transcript, transcript != request.transcript { return false }
        if let decision, decision != request.decision { return false }
        if let operationKind, operationKind != request.operationKind { return false }
        if let toDay, toDay != request.toDay { return false }
        if let toSlot, toSlot != request.toSlot { return false }
        if let declareEquipment, declareEquipment != (request.declareEquipment ?? []) { return false }
        if let sets, sets != request.resolvedSets { return false }
        if let instanceId, instanceId != request.resolvedInstanceId { return false }
        if let exerciseName, exerciseName != request.exerciseName { return false }
        if checkWrite, expectedWrite != request.expectedWrite { return false }
        return true
    }
}

struct CanvasScriptStep: Decodable {
    let match: CanvasScriptMatch
    let result: CanvasCommandResponse
}

private final class CanvasSequenceMarker {}

enum MesocycleCanvasSequence {
    static func loadOrThrow() throws -> [CanvasScriptStep] {
        let bundles = [Bundle(for: CanvasSequenceMarker.self), Bundle.main]
        for bundle in bundles {
            if let url = bundle.url(forResource: "MesocycleCanvasSequence", withExtension: "json") {
                return try JSONDecoder().decode([CanvasScriptStep].self, from: Data(contentsOf: url))
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}

final class ScriptedCanvasService: MesocycleCanvasServicing {
    private let steps: [CanvasScriptStep]
    private var index = 0
    private var last = CanvasReadback.empty
    private(set) var consumedCount = 0
    private(set) var lastMismatch = ""

    init(steps: [CanvasScriptStep]) {
        self.steps = steps
    }

    func perform(_ request: CanvasClientRequest, accessToken: String) async throws -> CanvasCommandResponse {
        _ = accessToken
        guard index < steps.count, steps[index].match.matches(request) else {
            lastMismatch = "step \(index) expected \(steps.indices.contains(index) ? steps[index].match.action : "end")"
            var readback = last
            readback.narration = "The save did not land. The saved plan is unchanged."
            return CanvasCommandResponse(version: 1, kind: "missed_update", readback: readback, missing: nil)
        }
        let result = steps[index].result
        index += 1
        consumedCount = index
        if ["read", "proposed", "decided"].contains(result.kind), CanvasAgreement.agrees(result.readback) {
            last = result.readback
        }
        return result
    }
}

@MainActor
final class MesocycleCanvasModel: ObservableObject {
    @Published private(set) var readback: CanvasReadback?
    @Published private(set) var narration = "Tell the coach the goal. Nothing is saved until you accept."
    @Published private(set) var stagedVoice: String?
    @Published private(set) var busy = false

    let reduceMotion: Bool
    private let service: MesocycleCanvasServicing
    private let store: CanvasSnapshotStoring
    private let accessToken: () async -> String?
    private var expectedWrite: Int?
    private var tail: Task<Void, Never> = Task {}
    private var lastRequest: CanvasClientRequest?

    init(
        service: MesocycleCanvasServicing,
        store: CanvasSnapshotStoring,
        accessToken: @escaping () async -> String?,
        reduceMotion: Bool
    ) {
        self.service = service
        self.store = store
        self.accessToken = accessToken
        self.reduceMotion = reduceMotion
    }

    func refresh() async { await send(CanvasClientRequest(action: "read", expectedWrite: expectedWrite)) }
    func submit(_ transcript: String) async {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await send(CanvasClientRequest(action: "submit", transcript: text, expectedWrite: expectedWrite))
    }
    func stageVoice(_ transcript: String) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stagedVoice = text
    }
    func confirmVoice() async {
        guard let stagedVoice else { return }
        self.stagedVoice = nil
        await submit(stagedVoice)
    }
    func cancelVoice() { stagedVoice = nil }
    func decide(_ decision: String) async {
        await enqueue {
            guard let proposal = self.readback?.proposal, proposal.status == "proposed" else { return }
            await self.deliver(CanvasClientRequest(
                action: "decide", proposalId: proposal.proposal.id, decision: decision, expectedWrite: self.expectedWrite
            ))
        }
    }
    func amend(instanceId: String, sets: Int) async {
        await enqueue {
            guard let proposal = self.readback?.proposal, proposal.status == "proposed" else { return }
            await self.deliver(CanvasClientRequest(
                action: "amend", proposalId: proposal.proposal.id, instanceId: instanceId, sets: sets,
                expectedWrite: self.expectedWrite
            ))
        }
    }
    func move(instanceId: String, toDay: String, toSlot: String) async {
        await send(CanvasClientRequest(
            action: "propose",
            operation: ["kind": "move", "instanceId": instanceId, "toDay": toDay, "toSlot": toSlot],
            expectedWrite: expectedWrite
        ))
    }
    func proposeSwap(exerciseName: String, toVariantId: String, declareEquipment: [String]) async {
        await send(CanvasClientRequest(
            action: "propose",
            operation: [
                "kind": "swap", "exerciseName": exerciseName, "toVariantId": toVariantId,
                "declareEquipment": declareEquipment
            ],
            expectedWrite: expectedWrite
        ))
    }
    func proposeSets(instanceId: String, sets: Int) async {
        await send(CanvasClientRequest(
            action: "propose",
            operation: ["kind": "edit_sets", "instanceId": instanceId, "sets": sets],
            expectedWrite: expectedWrite
        ))
    }
    func resendLast() async {
        guard let lastRequest else { return }
        await send(lastRequest)
    }
    func reloadFromStore() {
        guard let data = store.load(),
              let decoded = try? JSONDecoder().decode(CanvasReadback.self, from: data),
              decoded.version == 1,
              CanvasAgreement.agrees(decoded) else {
            narration = "The saved plan could not be read."
            return
        }
        readback = decoded
        expectedWrite = decoded.write
        narration = decoded.narration.isEmpty ? "Saved plan." : decoded.narration
    }

    private func send(_ request: CanvasClientRequest) async {
        await enqueue { await self.deliver(request) }
    }

    private func enqueue(_ work: @escaping () async -> Void) async {
        let previous = tail
        let next = Task { @MainActor in
            await previous.value
            await work()
        }
        tail = next
        await next.value
    }

    private func deliver(_ request: CanvasClientRequest) async {
        guard let token = await accessToken(), !token.isEmpty else {
            narration = "Your session expired. Sign in again to continue."
            return
        }
        busy = true
        defer { busy = false }
        lastRequest = request
        do {
            adopt(try await service.perform(request, accessToken: token))
        } catch let error as TrainingServiceError {
            switch error {
            case .authenticationExpired:
                narration = "Your session expired. Sign in again to continue."
            case .rateLimited:
                narration = "Training is temporarily unavailable. Try again shortly."
            case .invalidResponse, .server:
                narration = "The plan could not be updated."
            }
        } catch {
            narration = "The plan could not be updated."
        }
    }

    private func adopt(_ response: CanvasCommandResponse) {
        guard response.readback.version == 1 else {
            narration = "The plan could not be read."
            return
        }
        let succeeded = response.kind == "read" || response.kind == "proposed" || response.kind == "decided"
        if succeeded {
            guard CanvasAgreement.agrees(response.readback) else {
                narration = "The plan could not be read."
                return
            }
            readback = response.readback
            expectedWrite = response.readback.write
            if !response.readback.narration.isEmpty { narration = response.readback.narration }
            if let data = try? JSONEncoder().encode(response.readback) { store.save(data) }
            return
        }
        if CanvasAgreement.fingerprint(response.readback.plan) == CanvasAgreement.fingerprint(readback?.plan) {
            narration = response.readback.narration.isEmpty
                ? "The saved plan is unchanged."
                : response.readback.narration
            expectedWrite = response.readback.write
        } else {
            narration = "The plan could not be updated."
        }
    }
}

struct MesocycleCanvasScreen: View {
    @StateObject private var model: MesocycleCanvasModel

    init(accessToken: @escaping () async -> String?) {
        _model = StateObject(wrappedValue: MesocycleCanvasModel(
            service: URLSessionTrainingService(),
            store: UserDefaultsCanvasStore(subject: "account"),
            accessToken: accessToken,
            reduceMotion: false
        ))
    }

    var body: some View {
        MesocycleCanvasContainer(model: model, showsFixtureControls: false)
    }
}

struct MesocycleCanvasContainer: View {
    @ObservedObject var model: MesocycleCanvasModel
    var showsFixtureControls: Bool
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.theme) private var theme
    @State private var draft = ""

    private var reduced: Bool { accessibilityReduceMotion || model.reduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("TRAINING PLAN")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.colors.textSecondary)
                    Text("This week")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(theme.colors.text)
                    Text(model.narration)
                        .font(.system(size: 15))
                        .foregroundStyle(theme.colors.textSecondary)
                        .accessibilityIdentifier("canvas_narration")
                        .accessibilityAddTraits(.updatesFrequently)
                    if let voice = model.stagedVoice {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Voice heard a plan edit. Nothing is saved yet.")
                                .accessibilityIdentifier("canvas_voice_pending")
                            Text(voice).font(.system(size: 14))
                            HStack {
                                Button("Confirm voice edit") { Task { await model.confirmVoice() } }
                                    .accessibilityIdentifier("canvas_voice_confirm")
                                Button("Cancel voice edit") { model.cancelVoice() }
                                    .accessibilityIdentifier("canvas_voice_cancel")
                            }
                        }
                    }
                    if let proposal = model.readback?.proposal, proposal.status == "proposed" {
                        preview(proposal.proposal.changes)
                    }
                    days
                    if let goals = model.readback?.goals, !goals.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Muscle goals and weekly totals")
                                .font(.system(size: 13, weight: .semibold))
                            ForEach(goals) { goal in
                                Text("\(goal.label): \(goal.role), \(setsText(goal.weeklySets)) sets")
                                    .accessibilityIdentifier("canvas_goal_\(goal.id)")
                            }
                        }
                        .accessibilityIdentifier("canvas_goals")
                    }
                    if let execution = model.readback?.execution, !execution.isEmpty {
                        Text(executionReadback(execution))
                            .font(.system(size: 13))
                            .foregroundStyle(theme.colors.textSecondary)
                            .accessibilityIdentifier("canvas_execution")
                            .accessibilityLabel(executionReadback(execution))
                    }
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityElement()
                        .accessibilityIdentifier(reduced ? "canvas_motion_reduced" : "canvas_motion_fluid")
                        .accessibilityLabel(reduced ? "Reduced motion" : "Fluid motion")
                    if showsFixtureControls {
                        Button("Check Smith machine without declaring it") {
                            Task {
                                await model.proposeSwap(
                                    exerciseName: "Incline dumbbell press",
                                    toVariantId: "smith_incline_press",
                                    declareEquipment: []
                                )
                            }
                        }
                        .accessibilityIdentifier("canvas_inject_unsupported")
                        Button("Retry a missed save") {
                            Task { await model.proposeSets(instanceId: "standing_calf_raise:tuesday:single:3", sets: 8) }
                        }
                        .accessibilityIdentifier("canvas_inject_missed")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer
        }
        .background(theme.colors.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_root")
        .task { await model.refresh() }
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(dayGroups(model.readback?.plan?.sessions ?? []), id: \.day) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(group.day.capitalized)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.colors.textSecondary)
                    ForEach(group.sessions) { session in
                        sessionCard(session)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_layout_stack")
        .animation(reduced ? nil : .easeInOut(duration: 0.2), value: model.readback?.write)
    }

    private func sessionCard(_ session: CanvasSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.colors.text)
                .accessibilityIdentifier("canvas_day_\(session.day)_\(session.slot)")
            ForEach(session.exercises) { exercise in
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityIdentifier("canvas_card_\(exercise.instanceId)")
                    Text("\(exercise.sets) sets · \(exercise.targetReps) reps · \(exercise.variantId) · \(exercise.priority)")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.colors.textSecondary)
                    Button("Move to Friday") {
                        Task { await model.move(instanceId: exercise.instanceId, toDay: "friday", toSlot: "single") }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("canvas_move_friday_\(exercise.instanceId)")
                    .accessibilityLabel("Move \(exercise.name) to Friday")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func preview(_ changes: [CanvasChange]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review before saving").font(.system(size: 15, weight: .semibold))
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(changeLabel(change)).font(.system(size: 14))
                    if change.kind == "updated" {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: theme.spacing.xs), count: 4),
                            spacing: theme.spacing.xs
                        ) {
                            ForEach(1...8, id: \.self) { value in
                                Button("\(value)") { Task { await model.amend(instanceId: change.instanceId, sets: value) } }
                                    .frame(minHeight: 44)
                                    .accessibilityIdentifier("canvas_sets_\(value)_\(change.instanceId)")
                                    .accessibilityLabel("Sets for \(change.name ?? "exercise") \(value)")
                            }
                        }
                    }
                }
            }
            HStack {
                Button("Accept") { Task { await model.decide("apply") } }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("canvas_accept")
                Button("Reject") { Task { await model.decide("reject") } }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("canvas_reject")
            }
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canvas_preview")
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Prioritize upper chest and triceps", text: $draft)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("canvas_composer")
            HStack {
                Button("Send") {
                    let text = draft
                    draft = ""
                    Task { await model.submit(text) }
                }
                .accessibilityIdentifier("canvas_send")
                Button("Voice") { model.stageVoice(draft); draft = "" }
                    .accessibilityIdentifier("canvas_voice")
                Button("Reload") { model.reloadFromStore() }
                    .accessibilityIdentifier("canvas_reload")
            }
        }
        .padding(16)
    }

    private func executionReadback(_ execution: [CanvasExecutionSession]) -> String {
        execution.map { session in
            session.title + ": " + session.exercises.map { "\($0.name) \($0.sets)x\($0.targetReps)" }.joined(separator: ", ")
        }.joined(separator: "\n")
    }

    private func changeLabel(_ change: CanvasChange) -> String {
        switch change.kind {
        case "added":
            return "\(change.name ?? "Exercise") added. \(change.reason)"
        case "moved":
            return "\(change.name ?? "Exercise") moved to \(change.toDay ?? "") \(change.toSlot ?? ""). \(change.reason)"
        case "replaced":
            return "\(change.fromName ?? "") replaced with \(change.toName ?? ""). \(change.reason)"
        default:
            return "\(change.name ?? "Exercise") sets. \(change.reason)"
        }
    }
}

private struct DayGroup: Identifiable {
    var id: String { day }
    let day: String
    let sessions: [CanvasSession]
}

private func dayGroups(_ sessions: [CanvasSession]) -> [DayGroup] {
    var groups: [DayGroup] = []
    for session in sessions {
        if let index = groups.firstIndex(where: { $0.day == session.day }) {
            groups[index] = DayGroup(day: session.day, sessions: groups[index].sessions + [session])
        } else {
            groups.append(DayGroup(day: session.day, sessions: [session]))
        }
    }
    return groups.map { group in
        DayGroup(day: group.day, sessions: group.sessions.sorted { slotRank($0.slot) < slotRank($1.slot) })
    }
}

private func slotRank(_ slot: String) -> Int {
    slot == "am" ? 0 : slot == "single" ? 1 : 2
}

private func setsText(_ value: Double) -> String {
    value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
}

#if DEBUG
struct MesocycleCanvasFixtureView: View {
    @StateObject private var model: MesocycleCanvasModel

    init() {
        let steps = (try? MesocycleCanvasSequence.loadOrThrow()) ?? []
        _model = StateObject(wrappedValue: MesocycleCanvasModel(
            service: ScriptedCanvasService(steps: steps),
            store: MemoryCanvasStore(),
            accessToken: { "fixture" },
            reduceMotion: ProcessInfo.processInfo.arguments.contains("-lybUITestReduceMotion")
        ))
    }

    var body: some View {
        MesocycleCanvasContainer(model: model, showsFixtureControls: true)
    }
}
#endif
