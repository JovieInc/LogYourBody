import Combine
import Foundation

@MainActor
final class TrainingSessionDraft: ObservableObject {
    @Published private(set) var rows: [String: TrainingSetDraft] = [:]
    @Published private(set) var loggedSets: [String: TrainingSavedSet] = [:]
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    private let session: TrainingSession
    private let ownerId: String
    private let store: TrainingDraftStore
    private let isCurrent: () -> Bool
    private var persistedRows: [String: TrainingSetDraft] = [:]

    init(session: TrainingSession, ownerId: String, store: TrainingDraftStore, isCurrent: @escaping () -> Bool) {
        self.session = session
        self.ownerId = ownerId
        self.store = store
        self.isCurrent = isCurrent
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
        } catch {
            errorMessage = TrainingDraftError.unavailable.localizedDescription
        }
        reconcileSavedSets()
    }

    func row(for exercise: TrainingExercisePrescription, setNumber: Int) -> TrainingSetDraft {
        let key = "\(exercise.id)-\(setNumber)"
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
        guard isCurrent(), !isSaving, loggedSets[row.key] == nil, row.pendingRequest == nil else { return }
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
            try await send(request)
            guard isCurrent() else { throw TrainingServiceError.authenticationExpired }
            guard try store.remove(row, ownerId: ownerId, sessionId: session.id) else {
                throw TrainingDraftError.changed
            }
            rows.removeValue(forKey: row.key)
            persistedRows.removeValue(forKey: row.key)
            loggedSets[row.key] = TrainingSavedSet(
                sessionId: request.sessionId, exerciseId: request.exerciseId, setNumber: request.setNumber,
                reps: request.reps, loadKg: request.loadKg, rir: request.rir
            )
        } catch let error as LocalizedError {
            if isCurrent() { errorMessage = error.errorDescription ?? "The set could not be saved." }
        } catch {
            if isCurrent() { errorMessage = "The set could not be saved." }
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

    private func reconcileSavedSets() {
        for (key, saved) in loggedSets {
            guard let row = persistedRows[key] else { continue }
            if let pending = row.pendingRequest, saved != TrainingSavedSet(
                sessionId: pending.sessionId, exerciseId: pending.exerciseId, setNumber: pending.setNumber,
                reps: pending.reps, loadKg: pending.loadKg, rir: pending.rir
            ) {
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
        return true
    }

    private func validSavedSet(_ saved: TrainingSavedSet) -> Bool {
        guard saved.sessionId == session.id,
              let exercise = session.exercises.first(where: { $0.id == saved.exerciseId }),
              (1...max(1, exercise.sets)).contains(saved.setNumber),
              (1...50).contains(saved.reps), (0...6).contains(saved.rir) else { return false }
        return saved.loadKg.map { $0.isFinite && (0...500).contains($0) } ?? true
    }
}
