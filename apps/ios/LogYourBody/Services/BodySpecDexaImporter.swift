import Foundation

actor BodySpecDexaImporter {
    static let shared = BodySpecDexaImporter()

    private let api: BodySpecAPI
    private let authManager: AuthManager
    private let coreDataManager: CoreDataManager

    init(
        api: BodySpecAPI = .shared,
        authManager: AuthManager = .shared,
        coreDataManager: CoreDataManager = .shared
    ) {
        self.api = api
        self.authManager = authManager
        self.coreDataManager = coreDataManager
    }

    struct ImportResult {
        let importedCount: Int
        let skippedCount: Int
    }

    func importDexaResults() async -> ImportResult {
        guard Constants.isBodySpecEnabled else {
            return ImportResult(importedCount: 0, skippedCount: 0)
        }

        guard let userId = await MainActor.run(body: { authManager.currentUser?.id }) else {
            return ImportResult(importedCount: 0, skippedCount: 0)
        }

        var imported = 0
        var skipped = 0

        var page = 1
        let pageSize = 50

        while true {
            do {
                let pageResponse = try await api.listResults(page: page, pageSize: pageSize)

                let dexaResults = pageResponse.results.filter { summary in
                    guard let code = summary.service.serviceCode?.uppercased() else {
                        return summary.service.name.uppercased() == "DEXA"
                    }
                    return code == "DXA"
                }

                if dexaResults.isEmpty && pageResponse.results.isEmpty {
                    break
                }

                for summary in dexaResults {
                    let didImport = await importSingleResult(summary: summary, userId: userId)
                    if didImport {
                        imported += 1
                    } else {
                        skipped += 1
                    }
                }

                if pageResponse.results.count < pageSize {
                    break
                }

                page += 1
            } catch {
                let context = ErrorContext(
                    feature: "sync",
                    operation: "bodySpecImportPage\(page)",
                    screen: nil,
                    userId: userId
                )
                ErrorReporter.shared.captureNonFatal(error, context: context)
                break
            }
        }

        return ImportResult(importedCount: imported, skippedCount: skipped)
    }

    private func importSingleResult(
        summary: BodySpecResultSummary,
        userId: String
    ) async -> Bool {
        let metricsId = UUID().uuidString

        let existing = await coreDataManager.fetchBodyMetrics(
            for: userId,
            from: summary.startTime,
            to: summary.startTime
        )

        let alreadyHasBodySpecEntry = existing.contains { cached in
            if let source = cached.dataSource, source.lowercased() == "partner:bodyspec" {
                return true
            }

            if let notes = cached.notes, notes.localizedCaseInsensitiveContains("BodySpec") {
                return true
            }

            return false
        }

        if alreadyHasBodySpecEntry {
            return false
        }

        do {
            let scanInfo = try await api.getDexaScanInfo(resultId: summary.resultId)
            let composition = try await api.getDexaComposition(resultId: summary.resultId)

            let date = scanInfo.acquireTime

            let now = Date()

            let bodyMetrics = BodyMetrics(
                id: metricsId,
                userId: userId,
                date: date,
                weight: composition.total.totalMassKg,
                weightUnit: "kg",
                bodyFatPercentage: composition.total.regionFatPct,
                bodyFatMethod: "DEXA (BodySpec)",
                muscleMass: composition.total.leanMassKg,
                boneMass: composition.total.boneMassKg,
                notes: "Imported from BodySpec DEXA",
                photoUrl: nil,
                dataSource: "partner:bodyspec",
                createdAt: now,
                updatedAt: now
            )

            await MainActor.run {
                CoreDataManager.shared.saveBodyMetrics(bodyMetrics, userId: userId, markAsSynced: false)
                RealtimeSyncManager.shared.syncIfNeeded()
            }

            // Best-effort upsert of DEXA metadata to Supabase
            let dexaResult = DexaResult(
                id: UUID().uuidString,
                userId: userId,
                bodyMetricsId: metricsId,
                externalSource: "bodyspec",
                externalResultId: summary.resultId,
                externalUpdateTime: scanInfo.analyzeTime,
                scannerModel: scanInfo.scannerModel,
                locationId: summary.location.locationId,
                locationName: summary.location.name,
                acquireTime: scanInfo.acquireTime,
                analyzeTime: scanInfo.analyzeTime,
                vatMassKg: nil,
                vatVolumeCm3: nil,
                resultPdfUrl: nil,
                resultPdfName: nil,
                createdAt: now,
                updatedAt: now
            )

            await MainActor.run {
                CoreDataManager.shared.saveDexaResults([dexaResult], userId: userId, markAsSynced: false)
                RealtimeSyncManager.shared.updatePendingSyncCount()
                RealtimeSyncManager.shared.syncIfNeeded()
            }

            return true
        } catch {
            let context = ErrorContext(
                feature: "sync",
                operation: "bodySpecImportSingle",
                screen: nil,
                userId: userId
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
            return false
        }
    }
}
