import Combine
import Foundation

struct TrainingSetPosition: Equatable, Identifiable {
    let exercise: TrainingExercisePrescription
    let setNumber: Int

    var id: String { "\(exercise.id)-\(setNumber)" }
}

enum TrainingSetUndoPolicy {
    static let compactWindow: TimeInterval = 30

    static func makeReceipt(_ saved: TrainingSavedSet, now: Date) -> TrainingSetUndoReceipt? {
        guard (saved.revision ?? 0) >= 1,
              let audit = saved.corrections?.last,
              UUID(uuidString: audit.id) != nil
        else { return nil }
        return TrainingSetUndoReceipt(
            id: UUID().uuidString,
            sessionId: saved.sessionId,
            exerciseId: saved.exerciseId,
            setNumber: saved.setNumber,
            expectedRevision: saved.revision ?? 0,
            reps: audit.previous.reps,
            loadKg: audit.previous.loadKg,
            rir: audit.previous.rir,
            restoresCorrectionId: audit.id,
            issuedAt: now,
            submitted: false
        )
    }

    static func offer(
        receipt: TrainingSetUndoReceipt,
        sessionId: String,
        saved: TrainingSavedSet?,
        now: Date
    ) -> TrainingSetUndoReceipt? {
        guard receipt.sessionId == sessionId,
              let saved,
              saved.sessionId == receipt.sessionId,
              saved.exerciseId == receipt.exerciseId,
              saved.setNumber == receipt.setNumber,
              (saved.revision ?? 0) == receipt.expectedRevision
        else { return nil }
        if receipt.submitted { return receipt }
        guard now.timeIntervalSince(receipt.issuedAt) < compactWindow else { return nil }
        return receipt
    }
}

struct TrainingSetSaveReceipt: Equatable, Identifiable {
    let id: String
    let position: TrainingSetPosition
    let corrected: Bool
}

@MainActor
final class TrainingSessionDraft: ObservableObject {
    @Published private(set) var session: TrainingSession
    @Published private(set) var rows: [String: TrainingSetDraft] = [:]
    @Published private(set) var loggedSets: [String: TrainingSavedSet] = [:]
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSaveReceipt: TrainingSetSaveReceipt?
    @Published private(set) var restUntil: Date?
    @Published private(set) var rest = TrainingRestDraft()
    @Published private(set) var feedback: TrainingFeedbackDraft?
    @Published private(set) var undoReceipt: TrainingSetUndoReceipt?

    private let ownerId: String
    private let store: TrainingDraftStore
    private let isCurrent: () -> Bool
    private let now: () -> Date
    let restTimerEnabled: Bool
    private var persistedRows: [String: TrainingSetDraft] = [:]

    init(
        session: TrainingSession, ownerId: String, store: TrainingDraftStore,
        isCurrent: @escaping () -> Bool, now: @escaping () -> Date = Date.init,
        restTimerEnabled: Bool = false
    ) {
        self.session = session
        self.ownerId = ownerId
        self.store = store
        self.isCurrent = isCurrent
        self.now = now
        self.restTimerEnabled = restTimerEnabled
        guard isCurrent() else { return }
        // A failed journal read or cleanup must never hide authoritative acknowledgements.
        for saved in session.loggedSets ?? [] where validSavedSet(saved) {
            loggedSets["\(saved.exerciseId)-\(saved.setNumber)"] = saved
        }
        do {
            rows = try store.load(ownerId: ownerId, sessionId: session.id).filter { _, row in
                validRow(row)
            }
            persistedRows = rows
            feedback = try store.loadFeedback(ownerId: ownerId, sessionId: session.id)
            if restTimerEnabled { rest = try store.loadRest(ownerId: ownerId, sessionId: session.id) }
            undoReceipt = try store.loadUndo(ownerId: ownerId, sessionId: session.id)
        } catch {
            errorMessage = TrainingDraftError.unavailable.localizedDescription
        }
        reconcileSavedSets()
        restoreRestTimer()
    }

    func row(for exercise: TrainingExercisePrescription, setNumber: Int) -> TrainingSetDraft {
        let key = "\(exercise.id)-\(setNumber)"
        if let row = rows[key], row.correctionBase != nil { return row }
        if let saved = loggedSets[key] {
            return TrainingSetDraft(
                exerciseId: exercise.id, setNumber: setNumber, repsText: String(saved.reps),
                loadText: TrainingLoadInputPolicy.savedText(for: saved.loadKg), rir: saved.rir
            )
        }
        return rows[key] ?? TrainingSetDraft(
            exerciseId: exercise.id, setNumber: setNumber, repsText: String(exercise.targetReps),
            loadText: TrainingLoadPrefillPolicy.text(for: exercise.targetLoadKg), rir: exercise.targetRir
        )
    }

    func update(_ exercise: TrainingExercisePrescription, setNumber: Int, edit: (inout TrainingSetDraft) -> Void) {
        var row = row(for: exercise, setNumber: setNumber)
        let saved = loggedSets[row.key]
        guard isCurrent(), !isSaving,
              saved == nil || (row.correctionBase.map { base in
                  saved.map { sameSetVersion($0, base) } ?? false
              } ?? false),
              row.pendingRequest == nil, row.pendingCorrection == nil
        else { return }
        edit(&row)
        row.revision = UUID()
        do {
            guard try store.replace(
                row, expecting: persistedRows[row.key], ownerId: ownerId, sessionId: session.id
            ) else {
                errorMessage = TrainingDraftError.changed.localizedDescription
                return
            }
            rows[row.key] = row
            persistedRows[row.key] = row
            errorMessage = nil
        } catch {
            rows[row.key] = row
            errorMessage = TrainingDraftError.unavailable.localizedDescription
        }
    }

    func save(
        _ exercise: TrainingExercisePrescription,
        setNumber: Int,
        send: (TrainingSetLogRequest) async throws -> Void
    ) async {
        await saveAcknowledged(exercise, setNumber: setNumber) { request in
            try await send(request)
            return nil
        }
    }

    /// Adopts the server row when the acknowledgement matches this attempt. A newer
    /// local revision is left in place, including when the acknowledgement is empty.
    func saveAcknowledged(
        _ exercise: TrainingExercisePrescription,
        setNumber: Int,
        acknowledge: (TrainingSetLogRequest) async throws -> TrainingSavedSet?
    ) async {
        var row = row(for: exercise, setNumber: setNumber)
        guard isCurrent(), !isSaving, loggedSets[row.key] == nil else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let request = try row.pendingRequest ?? makeRequest(row)
            if row.pendingRequest == nil {
                row.pendingRequest = request
                row.revision = UUID()
                guard try store.replace(
                    row, expecting: persistedRows[row.key], ownerId: ownerId, sessionId: session.id
                ) else { throw TrainingDraftError.changed }
                rows[row.key] = row
                persistedRows[row.key] = row
            }
            guard try store.load(ownerId: ownerId, sessionId: session.id)[row.key] == row else {
                throw TrainingDraftError.changed
            }
            guard isCurrent() else { throw TrainingServiceError.authenticationExpired }
            let acknowledged = try await acknowledge(request)
            guard isCurrent() else { throw TrainingServiceError.authenticationExpired }
            try finishLogAcknowledgement(
                row: row, request: request, acknowledged: acknowledged, exercise: exercise, setNumber: setNumber
            )
            persistCachedReceipt()
        } catch let error as LocalizedError {
            if isCurrent() { errorMessage = error.errorDescription ?? "The set could not be saved." }
        } catch {
            if isCurrent() { errorMessage = "The set could not be saved." }
        }
    }

    var undoAffordance: TrainingSetUndoReceipt? {
        guard let undoReceipt else { return nil }
        return TrainingSetUndoPolicy.offer(
            receipt: undoReceipt,
            sessionId: session.id,
            saved: loggedSets["\(undoReceipt.exerciseId)-\(undoReceipt.setNumber)"],
            now: now()
        )
    }

    var allPositions: [TrainingSetPosition] {
        session.exercises.flatMap { exercise in
            (1...max(1, exercise.sets)).map {
                TrainingSetPosition(exercise: exercise, setNumber: $0)
            }
        }
    }

    var currentPosition: TrainingSetPosition? {
        allPositions.first { loggedSets[$0.id] == nil }
    }

    var upNextPosition: TrainingSetPosition? {
        let remaining = allPositions.filter { loggedSets[$0.id] == nil }
        return remaining.dropFirst().first
    }

    var lastCompletedPosition: TrainingSetPosition? {
        let latest = loggedSets.max { left, right in
            (left.value.completedAt ?? "") < (right.value.completedAt ?? "")
        }?.key
        return allPositions.first(where: { $0.id == latest }) ?? allPositions.last { loggedSets[$0.id] != nil }
    }

    var completedCount: Int { loggedSets.count }
    var totalCount: Int { allPositions.count }

    /// A timer never clears a reported limitation. A proceed receipt applies only to its intended set.
    var nextSetRecommendation: TrainingNextSetRecommendation? {
        guard let response = feedback?.recommendationReceipt else { return nil }
        if response.nextSetRecommendation.action == .symptomSafety { return response.nextSetRecommendation }
        guard let context = response.feedback.observation.context,
              currentPosition?.id == "\(context.exerciseId)-\(context.setNumber)",
              response.nextSetRecommendation.observationIds.contains(response.feedback.id),
              let time = response.feedback.observation.observedAt.flatMap(observationDate),
              (0...1_800).contains(now().timeIntervalSince(time))
        else { return nil }
        return response.nextSetRecommendation
    }

    func recordWorkoutFeedback(
        _ proposal: TrainingWorkoutFeedback,
        source: String,
        send: (TrainingFeedbackRequest) async throws -> TrainingFeedbackResponse
    ) async {
        let position = proposal.intent == .unusuallyWeak ? lastCompletedPosition : currentPosition
        guard proposal.sessionId == session.id, let position,
              position.id == "\(proposal.exerciseId)-\(proposal.setNumber)"
        else {
            errorMessage = TrainingDraftError.changed.localizedDescription
            return
        }
        var request = TrainingFeedbackRequest(
            sessionId: session.id,
            performance: proposal.intent == .unusuallyWeak ? "down" : nil,
            source: source
        )
        request.context = TrainingFeedbackContext(exerciseId: position.exercise.id, setNumber: position.setNumber)
        request.targetMuscle = position.exercise.primaryMuscle
        request.originalStatement = proposal.originalStatement
        switch proposal.intent {
        case .breathingLimited: request.breathingReadiness = "limited"
        case .gripLimited: request.supportingReadiness = TrainingSupportingReadiness(grip: "limited")
        case .ready: request.targetMuscleReadiness = "ready"
        case .moreRest, .unknown: request.targetMuscleReadiness = "unknown"
        case .unusuallyWeak:
            if let saved = loggedSets[position.id] {
                request.context?.reps = saved.reps
                request.context?.loadKg = saved.loadKg
                request.context?.rir = saved.rir
            }
        }
        if proposal.originalStatement.lowercased().hasPrefix("actually"),
           feedback?.request.context == request.context {
            request.correctsObservationId = feedback?.response?.feedback.id
        }
        await recordFeedback(request, send: send)
    }

    @discardableResult
    func recordFeedback(
        _ input: TrainingFeedbackRequest,
        send: (TrainingFeedbackRequest) async throws -> TrainingFeedbackResponse
    ) async -> Bool {
        guard isCurrent(), !isSaving, input.sessionId == session.id else { return false }
        guard feedback == nil || feedback?.response != nil else {
            errorMessage = "Feedback is pending sync. Retry it before adding another observation."
            return false
        }
        var request = input
        request.sourceObservationId = UUID().uuidString
        request.observedAt = ISO8601DateFormatter().string(from: now())
        let previous = feedback?.recommendationReceipt
        let pending = TrainingFeedbackDraft(
            request: request,
            readinessHold: previous?.nextSetRecommendation.action == .proceed ? nil : previous
        )
        do {
            guard try store.replaceFeedback(
                pending, expecting: feedback, ownerId: ownerId, sessionId: session.id
            ) else { throw TrainingDraftError.changed }
            feedback = pending
        } catch {
            errorMessage = TrainingDraftError.unavailable.localizedDescription
            return false
        }
        return await retryFeedback(send: send)
    }

    @discardableResult
    func retryFeedback(send: (TrainingFeedbackRequest) async throws -> TrainingFeedbackResponse) async -> Bool {
        guard isCurrent(), !isSaving, let pending = feedback, pending.response == nil else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let response = try await send(pending.request)
            guard isCurrent() else { throw TrainingServiceError.authenticationExpired }
            guard response.matches(pending.request) else { throw TrainingServiceError.invalidResponse }
            let saved = TrainingFeedbackDraft(
                request: pending.request, response: response, readinessHold: pending.readinessHold
            )
            guard try store.replaceFeedback(
                saved, expecting: pending, ownerId: ownerId, sessionId: session.id
            ) else { throw TrainingDraftError.changed }
            feedback = saved
            if response.nextSetRecommendation.action == .symptomSafety { cancelRest() }
            return true
        } catch let error as LocalizedError {
            if isCurrent() { errorMessage = error.errorDescription }
        } catch {
            if isCurrent() { errorMessage = "The check-in could not be saved. Retry when connected." }
        }
        return false
    }

    func replaceSession(_ updated: TrainingSession) {
        guard updated.id == session.id, isCurrent() else { return }
        session = updated
        for saved in updated.loggedSets ?? [] where validSavedSet(saved) {
            loggedSets["\(saved.exerciseId)-\(saved.setNumber)"] = saved
        }
        reconcileSavedSets()
        restoreRestTimer()
        persistCachedReceipt()
    }

    func beginCorrection(_ position: TrainingSetPosition) {
        let key = position.id
        guard isCurrent(), !isSaving, rows[key] == nil, let saved = loggedSets[key] else { return }
        let row = TrainingSetDraft(
            exerciseId: position.exercise.id,
            setNumber: position.setNumber,
            repsText: String(saved.reps),
            loadText: TrainingLoadInputPolicy.savedText(for: saved.loadKg),
            rir: saved.rir,
            correctionBase: saved
        )
        do {
            guard try store.replace(row, expecting: nil, ownerId: ownerId, sessionId: session.id) else {
                throw TrainingDraftError.changed
            }
            rows[key] = row
            persistedRows[key] = row
            errorMessage = nil
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = TrainingDraftError.unavailable.localizedDescription
        }
    }

    func cancelCorrection(_ position: TrainingSetPosition) {
        guard let row = rows[position.id], row.correctionBase != nil, row.pendingCorrection == nil else { return }
        do {
            guard try store.remove(row, ownerId: ownerId, sessionId: session.id) else {
                throw TrainingDraftError.changed
            }
            rows.removeValue(forKey: position.id)
            persistedRows.removeValue(forKey: position.id)
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = TrainingDraftError.unavailable.localizedDescription
        }
    }

    func correct(
        _ position: TrainingSetPosition,
        send: (TrainingSetCorrectionRequest) async throws -> TrainingSavedSet
    ) async {
        var row = row(for: position.exercise, setNumber: position.setNumber)
        guard isCurrent(), !isSaving,
              let base = row.correctionBase,
              loggedSets[row.key].map({ sameSetVersion($0, base) }) == true
        else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let request = try row.pendingCorrection ?? makeCorrection(row, base: base)
            if row.pendingCorrection == nil {
                row.pendingCorrection = request
                row.revision = UUID()
                guard try store.replace(
                    row, expecting: persistedRows[row.key], ownerId: ownerId, sessionId: session.id
                ) else { throw TrainingDraftError.changed }
                rows[row.key] = row
                persistedRows[row.key] = row
            }
            guard isCurrent() else { throw TrainingServiceError.authenticationExpired }
            let corrected = try await send(request)
            guard isCurrent(), corrected.sessionId == session.id,
                  corrected.exerciseId == row.exerciseId,
                  corrected.setNumber == row.setNumber
            else { throw TrainingServiceError.invalidResponse }
            guard try store.remove(row, ownerId: ownerId, sessionId: session.id) else {
                throw TrainingDraftError.changed
            }
            rows.removeValue(forKey: row.key)
            persistedRows.removeValue(forKey: row.key)
            loggedSets[row.key] = corrected
            persistCachedReceipt()
            issueUndoReceipt(for: corrected)
            lastSaveReceipt = TrainingSetSaveReceipt(
                id: request.correctionId,
                position: position,
                corrected: true
            )
        } catch let error as LocalizedError {
            if isCurrent() { errorMessage = error.errorDescription ?? "The correction could not be saved." }
        } catch {
            if isCurrent() { errorMessage = "The correction could not be saved." }
        }
    }

    private func persistCachedReceipt() {
        var snapshot = session
        snapshot.loggedSets = loggedSets.values.sorted { "\($0.exerciseId)-\($0.setNumber)" < "\($1.exerciseId)-\($1.setNumber)" }
        do {
            try store.updateCachedSession(snapshot, ownerId: ownerId)
        } catch {
            errorMessage = TrainingDraftError.unavailable.localizedDescription
        }
    }

    func undo(send: (TrainingSetUndoRequest) async throws -> TrainingSavedSet) async {
        guard var receipt = undoAffordance, isCurrent(), !isSaving else { return }
        let key = "\(receipt.exerciseId)-\(receipt.setNumber)"
        guard let saved = loggedSets[key],
              let position = allPositions.first(where: { $0.id == key })
        else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if !receipt.submitted {
                var queued = receipt
                queued.submitted = true
                guard try store.replaceUndo(
                    queued, expecting: receipt, ownerId: ownerId, sessionId: session.id
                ) else { throw TrainingDraftError.changed }
                undoReceipt = queued
                receipt = queued
            }
            var row = rows[key] ?? TrainingSetDraft(
                exerciseId: receipt.exerciseId,
                setNumber: receipt.setNumber,
                repsText: String(receipt.reps),
                loadText: TrainingLoadInputPolicy.savedText(for: receipt.loadKg),
                rir: receipt.rir,
                correctionBase: saved
            )
            if row.pendingCorrection == nil {
                row.repsText = String(receipt.reps)
                row.loadText = TrainingLoadInputPolicy.savedText(for: receipt.loadKg)
                row.rir = receipt.rir
                row.correctionBase = saved
                row.pendingCorrection = try makeCorrection(row, base: saved, correctionId: receipt.id)
                row.revision = UUID()
                guard try store.replace(
                    row, expecting: persistedRows[key], ownerId: ownerId, sessionId: session.id
                ) else { throw TrainingDraftError.changed }
                rows[key] = row
                persistedRows[key] = row
            }
            guard let pending = row.pendingCorrection, pending.correctionId == receipt.id else {
                throw TrainingDraftError.changed
            }
            guard isCurrent() else { throw TrainingServiceError.authenticationExpired }
            let undone = try await send(
                TrainingSetUndoRequest(
                    sessionId: receipt.sessionId,
                    exerciseId: receipt.exerciseId,
                    setNumber: receipt.setNumber,
                    undoId: receipt.id,
                    expectedRevision: receipt.expectedRevision
                )
            )
            guard isCurrent(),
                  undone.sessionId == receipt.sessionId,
                  undone.exerciseId == receipt.exerciseId,
                  undone.setNumber == receipt.setNumber,
                  undone.reps == receipt.reps,
                  undone.loadKg == receipt.loadKg,
                  undone.rir == receipt.rir,
                  undone.revision == receipt.expectedRevision + 1,
                  undone.corrections?.contains(where: { $0.id == receipt.id }) == true
            else { throw TrainingServiceError.invalidResponse }
            if rows[key] != nil {
                guard try store.remove(row, ownerId: ownerId, sessionId: session.id) else {
                    throw TrainingDraftError.changed
                }
                rows.removeValue(forKey: key)
                persistedRows.removeValue(forKey: key)
            }
            guard try store.replaceUndo(nil, expecting: receipt, ownerId: ownerId, sessionId: session.id) else {
                throw TrainingDraftError.changed
            }
            undoReceipt = nil
            loggedSets[key] = undone
            persistCachedReceipt()
            lastSaveReceipt = TrainingSetSaveReceipt(id: receipt.id, position: position, corrected: true)
        } catch let error as LocalizedError {
            if isCurrent() { errorMessage = error.errorDescription ?? "The correction could not be undone." }
        } catch {
            if isCurrent() { errorMessage = "The correction could not be undone." }
        }
    }

    private func finishLogAcknowledgement(
        row: TrainingSetDraft,
        request: TrainingSetLogRequest,
        acknowledged: TrainingSavedSet?,
        exercise: TrainingExercisePrescription,
        setNumber: Int
    ) throws {
        if let acknowledged {
            guard acknowledged.sessionId == request.sessionId,
                  acknowledged.exerciseId == request.exerciseId,
                  acknowledged.setNumber == request.setNumber,
                  acknowledged.reps == request.reps,
                  acknowledged.loadKg == request.loadKg,
                  acknowledged.rir == request.rir
            else { throw TrainingServiceError.invalidResponse }
        }
        let stored = try store.load(ownerId: ownerId, sessionId: session.id)[row.key]
        let pendingUnchanged = stored == row
        let pendingCleared = stored == nil
        let local = loggedSets[row.key]
        let localRevision = local?.revision ?? 0
        let acknowledgedRevision = acknowledged?.revision ?? 0
        if local != nil && localRevision > acknowledgedRevision {
            if pendingUnchanged {
                guard try store.remove(row, ownerId: ownerId, sessionId: session.id) else {
                    throw TrainingDraftError.changed
                }
                rows.removeValue(forKey: row.key)
                persistedRows.removeValue(forKey: row.key)
            } else if !pendingCleared {
                throw TrainingDraftError.changed
            }
            errorMessage = nil
            return
        }
        guard pendingUnchanged || pendingCleared else { throw TrainingDraftError.changed }
        if pendingUnchanged {
            guard try store.remove(row, ownerId: ownerId, sessionId: session.id) else {
                throw TrainingDraftError.changed
            }
        }
        rows.removeValue(forKey: row.key)
        persistedRows.removeValue(forKey: row.key)
        if let acknowledged {
            loggedSets[row.key] = acknowledged
        } else if local == nil || localRevision == 0 {
            loggedSets[row.key] = TrainingSavedSet(
                sessionId: request.sessionId, exerciseId: request.exerciseId, setNumber: request.setNumber,
                reps: request.reps, loadKg: request.loadKg, rir: request.rir,
                completedAt: ISO8601DateFormatter().string(from: now()), revision: 0, corrections: []
            )
        }
        lastSaveReceipt = TrainingSetSaveReceipt(
            id: "\(row.key)-\(row.revision.uuidString)",
            position: TrainingSetPosition(exercise: exercise, setNumber: setNumber),
            corrected: false
        )
        if restTimerEnabled {
            startRest(after: exercise, setKey: row.key, at: now())
        } else {
            restUntil = now().addingTimeInterval(90)
        }
    }

    private func issueUndoReceipt(for saved: TrainingSavedSet) {
        guard let receipt = TrainingSetUndoPolicy.makeReceipt(saved, now: now()) else { return }
        do {
            guard try store.replaceUndo(
                receipt, expecting: undoReceipt, ownerId: ownerId, sessionId: session.id
            ) else { return }
            undoReceipt = receipt
        } catch {
            undoReceipt = nil
        }
    }

    private func makeRequest(_ row: TrainingSetDraft) throws -> TrainingSetLogRequest {
        guard let reps = Int(row.repsText), (1...50).contains(reps), (0...6).contains(row.rir) else {
            throw TrainingServiceError.invalidResponse
        }
        return TrainingSetLogRequest(
            sessionId: session.id, exerciseId: row.exerciseId, setNumber: row.setNumber,
            reps: reps, loadKg: try TrainingLoadInputPolicy.loadKg(from: row.loadText), rir: row.rir
        )
    }

    private func makeCorrection(
        _ row: TrainingSetDraft,
        base: TrainingSavedSet,
        correctionId: String = UUID().uuidString
    ) throws -> TrainingSetCorrectionRequest {
        guard let reps = Int(row.repsText), (1...50).contains(reps), (0...6).contains(row.rir) else {
            throw TrainingServiceError.invalidResponse
        }
        return TrainingSetCorrectionRequest(
            sessionId: session.id,
            exerciseId: row.exerciseId,
            setNumber: row.setNumber,
            reps: reps,
            loadKg: try TrainingLoadInputPolicy.loadKg(from: row.loadText),
            rir: row.rir,
            correctionId: correctionId,
            expectedRevision: base.revision ?? 0
        )
    }

    private func reconcileSavedSets() {
        for (key, saved) in loggedSets {
            guard let row = persistedRows[key] else { continue }
            if let base = row.correctionBase {
                guard let pending = row.pendingCorrection else { continue }
                if sameSetVersion(saved, base) { continue }
                guard saved.revision == pending.expectedRevision + 1,
                      saved.reps == pending.reps,
                      saved.loadKg == pending.loadKg,
                      saved.rir == pending.rir,
                      saved.corrections?.contains(where: { $0.id == pending.correctionId }) == true
                else {
                    errorMessage = "A correction differs from the saved set. Review it before retrying."
                    continue
                }
                do {
                    guard try store.remove(row, ownerId: ownerId, sessionId: session.id) else {
                        errorMessage = TrainingDraftError.changed.localizedDescription
                        continue
                    }
                    rows.removeValue(forKey: key)
                    persistedRows.removeValue(forKey: key)
                    if undoReceipt?.id == pending.correctionId {
                        if try store.replaceUndo(
                            nil, expecting: undoReceipt, ownerId: ownerId, sessionId: session.id
                        ) {
                            undoReceipt = nil
                        }
                    }
                } catch {
                    errorMessage = TrainingDraftError.unavailable.localizedDescription
                }
                continue
            }
            if let pending = row.pendingRequest,
               saved.sessionId != pending.sessionId ||
                saved.exerciseId != pending.exerciseId ||
                saved.setNumber != pending.setNumber ||
                saved.reps != pending.reps ||
                saved.loadKg != pending.loadKg ||
                saved.rir != pending.rir {
                errorMessage = "A previous save attempt differs from the saved set. Your draft has been retained."
                continue
            }
            do {
                guard try store.remove(row, ownerId: ownerId, sessionId: session.id) else {
                    errorMessage = TrainingDraftError.changed.localizedDescription
                    continue
                }
                rows.removeValue(forKey: key)
                persistedRows.removeValue(forKey: key)
            } catch {
                errorMessage = TrainingDraftError.unavailable.localizedDescription
            }
        }
    }

    private func validRow(_ row: TrainingSetDraft) -> Bool {
        guard let exercise = session.exercises.first(where: { $0.id == row.exerciseId }),
              (1...max(1, exercise.sets)).contains(row.setNumber), (0...6).contains(row.rir) else { return false }
        if let pending = row.pendingRequest { return (try? makeRequest(row)) == pending }
        if let base = row.correctionBase {
            guard base.sessionId == session.id,
                  base.exerciseId == row.exerciseId,
                  base.setNumber == row.setNumber
            else { return false }
            if let pending = row.pendingCorrection {
                return (try? makeCorrection(row, base: base, correctionId: pending.correctionId)) == pending
            }
        }
        return true
    }

    private func validSavedSet(_ saved: TrainingSavedSet) -> Bool {
        guard saved.sessionId == session.id,
              let exercise = session.exercises.first(where: { $0.id == saved.exerciseId }),
              (1...max(1, exercise.sets)).contains(saved.setNumber),
              (1...50).contains(saved.reps), (0...6).contains(saved.rir) else { return false }
        guard saved.loadKg.map({ $0.isFinite && (0...500).contains($0) }) ?? true,
              (saved.revision ?? 0) >= 0
        else { return false }
        return saved.corrections?.allSatisfy { audit in
            !audit.id.isEmpty &&
                (1...50).contains(audit.previous.reps) &&
                (0...6).contains(audit.previous.rir) &&
                (audit.previous.loadKg.map { $0.isFinite && (0...500).contains($0) } ?? true)
        } ?? true
    }

    private func sameSetVersion(_ left: TrainingSavedSet, _ right: TrainingSavedSet) -> Bool {
        left.sessionId == right.sessionId &&
            left.exerciseId == right.exerciseId &&
            left.setNumber == right.setNumber &&
            left.reps == right.reps &&
            left.loadKg == right.loadKg &&
            left.rir == right.rir &&
            (left.revision ?? 0) == (right.revision ?? 0)
    }

    private func restoreRestTimer() {
        if restTimerEnabled {
            guard canRest else { cancelRest(); return }
            guard let position = lastCompletedPosition,
                  let date = loggedSets[position.id]?.completedAt.flatMap(observationDate)
            else { return }
            // Preserve adjustments and skips when refreshing or reopening this session.
            guard rest.lastSetKey != position.id else {
                restUntil = rest.countdown?.endsAt
                return
            }
            startRest(after: position.exercise, setKey: position.id, at: date)
            return
        }
        let latest = loggedSets.values.compactMap { saved in
            saved.completedAt.flatMap(observationDate)
        }.max()
        guard let latest else { return }
        let restored = latest.addingTimeInterval(90)
        restUntil = restored
    }

    var ownsSession: Bool { isCurrent() }

    private var canRest: Bool {
        isCurrent() && currentPosition != nil && !session.safetyStop && session.executionPaused != true &&
            session.executionEvents?.last?.kind != "ended" && nextSetRecommendation?.action != .symptomSafety
    }

    func adjustRest(by seconds: Int) {
        guard restTimerEnabled, canRest, let countdown = rest.countdown,
              countdown.remaining(at: now()) > 0 else { return }
        let adjusted = countdown.adjusted(by: seconds)
        rest.countdown = adjusted
        rest.durations[countdown.exerciseId] = adjusted.duration
        persistRest()
    }

    func cancelRest() {
        guard restTimerEnabled else { return }
        rest.countdown = nil
        restUntil = nil
        if isCurrent() { persistRest() }
    }

    private func startRest(after exercise: TrainingExercisePrescription, setKey: String, at date: Date) {
        rest.lastSetKey = setKey
        rest.countdown = canRest ? TrainingRestCountdown(
            id: UUID(), exerciseId: exercise.id, startedAt: date,
            duration: rest.durations[exercise.id] ?? TrainingRestPolicy.defaultDuration(for: exercise)
        ) : nil
        persistRest()
    }

    private func persistRest() {
        restUntil = rest.countdown?.endsAt
        do {
            try store.saveRest(rest, ownerId: ownerId, sessionId: session.id)
        } catch {
            errorMessage = "The rest timer could not be saved on this device."
        }
    }

    private func observationDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
}
