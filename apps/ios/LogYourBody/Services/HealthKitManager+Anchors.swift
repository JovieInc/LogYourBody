import Foundation
import HealthKit

extension HealthKitManager {
    func anchorStore() -> HealthAnchorStore {
        HealthAnchorStore(defaults: userDefaults)
    }

    func hasBodyMetricAnchors(userId: String?) -> Bool {
        anchorStore().hasBodyMetricAnchors(userId: userId)
    }

    /// Live HealthKit reads stay off while a unit test is feeding import queries.
    func canSeedAnchorsFromHealthStore() -> Bool {
        if anchoredSampleQuery != nil { return true }
        if weightImportQuery != nil || bodyFatImportQuery != nil || stepHistoryQuery != nil ||
            todayStepQuantityQuery != nil {
            return false
        }
        // Read access is confirmed by the existing authorization flow. Write sharing is not required.
        return isAuthorized || HealthKitAuthorizationPolicy.isAuthorized(
            writeStatus: healthStore.authorizationStatus(for: weightType),
            hasConfirmedReadAccess: hasConfirmedAuthorization()
        )
    }

    func importAnchoredBodyMetrics() async throws {
        guard let ownership = await captureImportOwnership() else { throw HealthKitError.notAuthorized }
        try await requireImportOwnership(ownership)
        guard beginWeightSyncIfPossible() else { return }
        defer { endWeightSync() }
        try await importAnchoredBodyMetricsUnlocked(ownership)
    }

    func importAnchoredBodyMetricsUnlocked(
        _ ownership: AuthManager.ProfileSessionOwnership
    ) async throws {
        let userId = ownership.subject
        guard let weightAnchor = anchorStore().anchor(for: .weight, userId: userId),
              let bodyFatAnchor = anchorStore().anchor(for: .bodyFat, userId: userId) else {
            return
        }
        let weightPage = try await fetchAnchoredPage(.weight, anchor: weightAnchor)
        let bodyFatPage = try await fetchAnchoredPage(.bodyFat, anchor: bodyFatAnchor)
        try await requireImportOwnership(ownership)
        let committed = try await commitAnchoredBodyMetrics(
            weightPage, bodyFatPage: bodyFatPage, ownership: ownership
        )
        guard committed else { throw HealthKitError.syncFailed }
        let store = anchorStore()
        store.advance(weightPage.newAnchor, for: .weight, userId: userId, commitSucceeded: true)
        store.advance(bodyFatPage.newAnchor, for: .bodyFat, userId: userId, commitSucceeded: true)
        await recordSuccessfulMetricSourceSync(for: ownership)
    }

    func commitAnchoredBodyMetrics(
        _ weightPage: HealthAnchoredSamplePage,
        bodyFatPage: HealthAnchoredSamplePage,
        ownership: AuthManager.ProfileSessionOwnership
    ) async throws -> Bool {
        let weightSamples = weightPage.added.filter { $0.kind == .weight }.map { sample in
            HealthKitWeightImportSample(
                weight: sample.value, date: sample.date, sourceMetadata: sample.sourceMetadata
            )
        }
        let bodyFatSamples = bodyFatPage.added.filter { $0.kind == .bodyFat }.map { sample in
            HealthKitBodyFatImportSample(
                percentage: sample.value, date: sample.date, sourceMetadata: sample.sourceMetadata
            )
        }
        if !weightSamples.isEmpty || !bodyFatSamples.isEmpty {
            var batchFailed = false
            _ = await processBatchHealthKitData(
                weightHistory: weightSamples, bodyFatHistory: bodyFatSamples, ownership: ownership,
                onFailure: { batchFailed = true }
            )
            try await requireImportOwnership(ownership)
            if batchFailed { return false }
        }
        return try await applyAnchoredBodyMetricDeletions(
            weightPage.deleted + bodyFatPage.deleted, ownership: ownership
        )
    }

    @discardableResult
    func applyAnchoredBodyMetricDeletions(
        _ deletions: [HealthAnchoredDeletion],
        ownership: AuthManager.ProfileSessionOwnership
    ) async throws -> Bool {
        let bodyDeletions = deletions.filter { $0.kind == .weight || $0.kind == .bodyFat }
        guard !bodyDeletions.isEmpty else { return true }
        var metrics = await (importCoreDataManager ?? .shared)
            .fetchBodyMetrics(for: ownership.subject)
            .compactMap { $0.toBodyMetrics() }
        try await requireImportOwnership(ownership)
        var rows = metrics.map { importedRow($0) }
        for deletion in bodyDeletions {
            let applied = try await applyOneAnchoredDeletion(
                deletion, metrics: &metrics, rows: &rows, ownership: ownership
            )
            if !applied { return false }
        }
        return true
    }

    private func applyOneAnchoredDeletion(
        _ deletion: HealthAnchoredDeletion,
        metrics: inout [BodyMetrics],
        rows: inout [HealthAnchorImportedRow],
        ownership: AuthManager.ProfileSessionOwnership
    ) async throws -> Bool {
        let changes = HealthAnchorDeletionPolicy.changes(
            deleting: deletion.id, kind: deletion.kind, rows: rows
        )
        for change in changes {
            guard let index = metrics.firstIndex(where: { $0.id == changedRowId(change) }) else {
                return false
            }
            let outcome = try await apply(change, to: metrics[index], ownership: ownership)
            guard remember(outcome, at: index, metrics: &metrics, rows: &rows) else { return false }
        }
        return true
    }

    func seedBodyMetricAnchors(ownership: AuthManager.ProfileSessionOwnership) async {
        let userId = ownership.subject
        let store = anchorStore()
        let weightMissing = store.anchor(for: .weight, userId: userId) == nil
        let bodyFatMissing = store.anchor(for: .bodyFat, userId: userId) == nil
        guard weightMissing || bodyFatMissing, canSeedAnchorsFromHealthStore() else { return }
        do {
            let weightMark = try await fetchAnchoredPage(.weight, anchor: nil, includeSamples: false)
            let bodyFatMark = try await fetchAnchoredPage(.bodyFat, anchor: nil, includeSamples: false)
            let watermark = try await commitAnchoredBodyMetrics(
                HealthAnchoredSamplePage(added: [], deleted: weightMark.deleted, newAnchor: weightMark.newAnchor),
                bodyFatPage: HealthAnchoredSamplePage(
                    added: [], deleted: bodyFatMark.deleted, newAnchor: bodyFatMark.newAnchor
                ),
                ownership: ownership
            )
            guard watermark else { return }
            let weightDelta = try await fetchAnchoredPage(.weight, anchor: weightMark.newAnchor)
            let bodyFatDelta = try await fetchAnchoredPage(.bodyFat, anchor: bodyFatMark.newAnchor)
            try await requireImportOwnership(ownership)
            let committed = try await commitAnchoredBodyMetrics(
                weightDelta, bodyFatPage: bodyFatDelta, ownership: ownership
            )
            guard committed else { return }
            if weightMissing {
                store.advance(
                    weightDelta.newAnchor ?? weightMark.newAnchor,
                    for: .weight, userId: userId, commitSucceeded: true
                )
            }
            if bodyFatMissing {
                store.advance(
                    bodyFatDelta.newAnchor ?? bodyFatMark.newAnchor,
                    for: .bodyFat, userId: userId, commitSucceeded: true
                )
            }
        } catch {
            return
        }
    }

    func importAnchoredSteps(
        _ anchor: Data, ownership: AuthManager.ProfileSessionOwnership
    ) async throws {
        let page = try await fetchAnchoredPage(.steps, anchor: anchor)
        try await requireImportOwnership(ownership)
        let committed = try await commitAnchoredSteps(page, ownership: ownership)
        guard committed else { return }
        anchorStore().advance(page.newAnchor, for: .steps, userId: ownership.subject, commitSucceeded: true)
    }

    func seedStepAnchor(ownership: AuthManager.ProfileSessionOwnership) async {
        let store = anchorStore()
        guard store.anchor(for: .steps, userId: ownership.subject) == nil,
              canSeedAnchorsFromHealthStore() else { return }
        do {
            let mark = try await fetchAnchoredPage(.steps, anchor: nil, includeSamples: false)
            if !mark.deleted.isEmpty {
                let deleted = try await commitAnchoredSteps(
                    HealthAnchoredSamplePage(added: [], deleted: mark.deleted, newAnchor: mark.newAnchor),
                    ownership: ownership
                )
                guard deleted else { return }
            }
            guard let cursor = mark.newAnchor else { return }
            let delta = try await fetchAnchoredPage(.steps, anchor: cursor)
            try await requireImportOwnership(ownership)
            let committed = try await commitAnchoredSteps(delta, ownership: ownership)
            guard committed else { return }
            store.advance(
                delta.newAnchor ?? cursor, for: .steps, userId: ownership.subject, commitSucceeded: true
            )
        } catch {
            return
        }
    }

    func fetchAnchoredPage(
        _ kind: HealthAnchorSampleKind, anchor: Data?, includeSamples: Bool = true
    ) async throws -> HealthAnchoredSamplePage {
        if let anchoredSampleQuery {
            return try await anchoredSampleQuery(kind, anchor)
        }
        return try await fetchLiveAnchoredPage(kind, anchorData: anchor, includeSamples: includeSamples)
    }

    private func commitAnchoredSteps(
        _ page: HealthAnchoredSamplePage, ownership: AuthManager.ProfileSessionOwnership
    ) async throws -> Bool {
        let calendar = Calendar.current
        var days = Set(page.added.map { calendar.startOfDay(for: $0.date) })
        for deletion in page.deleted where deletion.kind == .steps {
            if let date = deletion.date { days.insert(calendar.startOfDay(for: date)) }
        }
        let undatedDeletion = page.deleted.contains { $0.kind == .steps && $0.date == nil }
        if undatedDeletion {
            try await refreshStepWindow(ownership: ownership)
            return true
        }
        for day in days {
            let total = try await fetchStepTotal(on: day)
            try await requireImportOwnership(ownership)
            try await upsertImportedSteps(total, date: day, ownership: ownership)
        }
        return true
    }

    private func refreshStepWindow(ownership: AuthManager.ProfileSessionOwnership) async throws {
        let history = try await fetchStepCountHistory(days: 365)
        try await requireImportOwnership(ownership)
        let calendar = Calendar.current
        var reportedDays = Set<Date>()
        for (stepCount, date) in history {
            let day = calendar.startOfDay(for: date)
            reportedDays.insert(day)
            try await upsertImportedSteps(stepCount, date: date, ownership: ownership)
        }
        let start = calendar.date(byAdding: .day, value: -365, to: Date()) ?? Date()
        let stored = await (importCoreDataManager ?? .shared).fetchDailyMetrics(
            for: ownership.subject, from: start, to: Date()
        )
        try await requireImportOwnership(ownership)
        for row in stored {
            guard let date = row.date, row.notes == "Imported from HealthKit" else { continue }
            let day = calendar.startOfDay(for: date)
            if !reportedDays.contains(day) {
                try await upsertImportedSteps(0, date: date, ownership: ownership)
            }
        }
    }

    private func upsertImportedSteps(
        _ steps: Int, date: Date, ownership: AuthManager.ProfileSessionOwnership
    ) async throws {
        let store = importCoreDataManager ?? .shared
        if let existing = await store.fetchDailyMetrics(for: ownership.subject, date: date)?.toDailyMetrics() {
            if existing.steps == steps || (existing.steps == nil && steps == 0) { return }
            let updated = makeUpdatedDailyMetrics(from: existing, steps: steps, updatedAt: Date())
            try await requireImportOwnership(ownership)
            try await store.saveDailyMetricsAndWait(updated, userId: ownership.subject)
        } else if steps > 0 {
            try await saveDailySteps(steps: steps, date: date, ownership: ownership)
        }
    }

    private func fetchStepTotal(on day: Date) async throws -> Int {
        if let stepDayTotalQuery {
            return try await stepDayTotalQuery(day) ?? 0
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? day.addingTimeInterval(86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepCountType, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                do {
                    let count = try HealthKitStepCountPolicy.stepCount(
                        from: statistics?.sumQuantity()?.doubleValue(for: HKUnit.count())
                    )
                    continuation.resume(returning: count ?? 0)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            healthStore.execute(query)
        }
    }

    private func fetchLiveAnchoredPage(
        _ kind: HealthAnchorSampleKind, anchorData: Data?, includeSamples: Bool
    ) async throws -> HealthAnchoredSamplePage {
        let sampleType = quantityType(for: kind)
        let anchor = anchorData.flatMap {
            try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: sampleType, predicate: nil, anchor: anchor, limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let added: [HealthAnchoredSample]
                if includeSamples, let self {
                    added = (samples as? [HKQuantitySample] ?? []).compactMap { self.anchoredSample($0, kind: kind) }
                } else {
                    added = []
                }
                let removed = (deleted ?? []).map {
                    HealthAnchoredDeletion(id: $0.uuid.uuidString, kind: kind, date: nil)
                }
                let archived = newAnchor.flatMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                }
                continuation.resume(returning: HealthAnchoredSamplePage(
                    added: added, deleted: removed, newAnchor: archived
                ))
            }
            healthStore.execute(query)
        }
    }

    private func quantityType(for kind: HealthAnchorSampleKind) -> HKQuantityType {
        switch kind {
        case .weight: return weightType
        case .bodyFat: return bodyFatType
        case .steps: return stepCountType
        }
    }

    private func anchoredSample(
        _ sample: HKQuantitySample, kind: HealthAnchorSampleKind
    ) -> HealthAnchoredSample? {
        let value: Double
        switch kind {
        case .weight:
            value = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        case .bodyFat:
            value = sample.quantity.doubleValue(for: HKUnit.percent()) * 100
        case .steps:
            value = sample.quantity.doubleValue(for: HKUnit.count())
        }
        guard value.isFinite, value >= 0 else { return nil }
        return HealthAnchoredSample(
            id: sample.uuid.uuidString, kind: kind, value: value, date: sample.startDate,
            sourceMetadata: sourceMetadata(from: sample)
        )
    }

    private func changedRowId(_ change: HealthAnchorRowChange) -> String {
        switch change {
        case .markDeleted(let id), .keepBodyFatOnly(let id, _), .keepWeightOnly(let id, _):
            return id
        }
    }

    private enum AnchorApplyResult {
        case deleted
        case updated(BodyMetrics)
        case failed
    }

    private func apply(
        _ change: HealthAnchorRowChange,
        to metric: BodyMetrics,
        ownership: AuthManager.ProfileSessionOwnership
    ) async throws -> AnchorApplyResult {
        switch change {
        case .markDeleted(let id):
            let deleted = await (importCoreDataManager ?? .shared)
                .markBodyMetricDeleted(id: id, userId: ownership.subject)
            return deleted ? .deleted : .failed
        case .keepBodyFatOnly(_, let metadata):
            let kept = replacing(
                metric, weight: nil, bodyFat: metric.bodyFatPercentage,
                method: metric.bodyFatMethod, metadata: metadata
            )
            try await saveBodyMetrics(kept, ownership: ownership)
            return .updated(kept)
        case .keepWeightOnly(_, let metadata):
            let kept = replacing(metric, weight: metric.weight, bodyFat: nil, method: nil, metadata: metadata)
            try await saveBodyMetrics(kept, ownership: ownership)
            return .updated(kept)
        }
    }

    private func remember(
        _ outcome: AnchorApplyResult,
        at index: Int,
        metrics: inout [BodyMetrics],
        rows: inout [HealthAnchorImportedRow]
    ) -> Bool {
        switch outcome {
        case .failed:
            return false
        case .deleted:
            metrics.remove(at: index)
            rows.remove(at: index)
            return true
        case .updated(let kept):
            metrics[index] = kept
            rows[index] = importedRow(kept)
            return true
        }
    }

    private func importedRow(_ metric: BodyMetrics) -> HealthAnchorImportedRow {
        HealthAnchorImportedRow(
            id: metric.id, dataSource: metric.dataSource ?? "", weight: metric.weight,
            bodyFatPercentage: metric.bodyFatPercentage, metadata: metric.sourceMetadata
        )
    }

    private func replacing(
        _ metric: BodyMetrics, weight: Double?, bodyFat: Double?, method: String?, metadata: BodyMetricSourceMetadata
    ) -> BodyMetrics {
        BodyMetrics(
            id: metric.id, userId: metric.userId, date: metric.date, localDate: metric.localDate,
            weight: weight, weightUnit: metric.weightUnit, bodyFatPercentage: bodyFat, bodyFatMethod: method,
            muscleMass: metric.muscleMass, boneMass: metric.boneMass, waistCm: metric.waistCm, hipCm: metric.hipCm,
            waistUnit: metric.waistUnit, notes: metric.notes, photoUrl: metric.photoUrl,
            dataSource: metric.dataSource, sourceMetadata: metadata, createdAt: metric.createdAt, updatedAt: Date()
        )
    }
}
