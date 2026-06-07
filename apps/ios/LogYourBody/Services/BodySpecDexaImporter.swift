import Foundation

protocol BodySpecDexaAPIClient {
    func listResults(page: Int, pageSize: Int) async throws -> BodySpecResultsListResponse
    func getDexaScanInfo(resultId: String) async throws -> BodySpecDexaScanInfoResponse
    func getDexaComposition(resultId: String) async throws -> BodySpecDexaCompositionResponse
}

extension BodySpecAPI: BodySpecDexaAPIClient {}

actor BodySpecDexaImporter {
    @MainActor static let shared = BodySpecDexaImporter(api: BodySpecAPI.shared, authManager: .shared)

    private let api: BodySpecDexaAPIClient
    private let authManager: AuthManager
    private let coreDataManager: CoreDataManager

    init(
        api: BodySpecDexaAPIClient,
        authManager: AuthManager,
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
        do {
            let scanInfo = try await api.getDexaScanInfo(resultId: summary.resultId)

            if await hasImportedResult(summary: summary, scanDate: scanInfo.acquireTime, userId: userId) {
                return false
            }

            let composition = try await api.getDexaComposition(resultId: summary.resultId)

            let metricsId = UUID().uuidString
            let date = scanInfo.acquireTime

            let now = Date()
            let importedAt = ISO8601DateFormatter().string(from: now)

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
                dataSource: BodyMetricSource.bodySpecDexa.rawValue,
                sourceMetadata: BodyMetricSourceMetadata(
                    vendor: "bodyspec",
                    sourceName: "BodySpec DEXA",
                    externalId: summary.service.serviceId,
                    externalResultId: summary.resultId,
                    scannerModel: scanInfo.scannerModel,
                    locationId: summary.location.locationId,
                    locationName: summary.location.name,
                    importedAt: importedAt
                ),
                createdAt: now,
                updatedAt: now
            )

            try await coreDataManager.saveBodyMetricsAndWait(bodyMetrics, userId: userId, markAsSynced: false)

            await MainActor.run {
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

            try await coreDataManager.saveDexaResultsAndWait([dexaResult], userId: userId, markAsSynced: false)

            await MainActor.run {
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

    private func hasImportedResult(
        summary: BodySpecResultSummary,
        scanDate: Date,
        userId: String
    ) async -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: scanDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? scanDate
        let existing = await coreDataManager.fetchBodyMetrics(for: userId, from: startOfDay, to: endOfDay)

        return existing.contains { cached in
            if BodyMetricSourceMetadata(jsonString: cached.sourceMetadataJSON)?.externalResultId == summary.resultId {
                return true
            }

            let isBodySpec = BodyMetricSource.normalizedRawValue(cached.dataSource) ==
                BodyMetricSource.bodySpecDexa.rawValue
            let hasLegacyBodySpecNote = cached.notes?.localizedCaseInsensitiveContains("BodySpec") == true
            let isSameScanTimestamp = cached.date.map { abs($0.timeIntervalSince(scanDate)) < 60 } ?? false

            return isSameScanTimestamp && (isBodySpec || hasLegacyBodySpecNote)
        }
    }
}
