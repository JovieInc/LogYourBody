import Combine
import Foundation

struct TrainingSetPosition: Equatable, Identifiable {
    let exercise: TrainingExercisePrescription
    let setNumber: Int

    var id: String { "\(exercise.id)-\(setNumber)" }
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
                reps: request.reps, loadKg: request.loadKg, rir: request.rir,
                completedAt: ISO8601DateFormatter().string(from: Date()), revision: 0, corrections: []
            )
            lastSaveReceipt = TrainingSetSaveReceipt(
                id: "\(row.key)-\(row.revision.uuidString)",
                position: TrainingSetPosition(exercise: exercise, setNumber: setNumber),
                corrected: false
            )
            restUntil = Date().addingTimeInterval(90)
        } catch let error as LocalizedError {
            if isCurrent() { errorMessage = error.errorDescription ?? "The set could not be saved." }
        } catch {
            if isCurrent() { errorMessage = "The set could not be saved." }
        }
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

    func replaceSession(_ updated: TrainingSession) {
        guard updated.id == session.id, isCurrent() else { return }
        session = updated
        for saved in updated.loggedSets ?? [] where validSavedSet(saved) {
            loggedSets["\(saved.exerciseId)-\(saved.setNumber)"] = saved
        }
        reconcileSavedSets()
        restoreRestTimer()
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
        let formatter = ISO8601DateFormatter()
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let latest = loggedSets.values.compactMap { saved in
            saved.completedAt.flatMap { formatter.date(from: $0) ?? fractionalFormatter.date(from: $0) }
        }.max()
        guard let latest else { return }
        let restored = latest.addingTimeInterval(90)
        restUntil = restored > Date() ? restored : nil
    }
}
