import Foundation
import CryptoKit

struct BodySpecDexaImportSession {
    let api: BodySpecDexaAPIClient
    let admission: @MainActor () throws -> Void
}

protocol BodySpecDexaAPIClient {
    func importSession(for ownership: AuthManager.ProfileSessionOwnership) async throws -> BodySpecDexaImportSession
    func listResults(page: Int, pageSize: Int) async throws -> BodySpecResultsListResponse
    func getDexaScanInfo(resultId: String) async throws -> BodySpecDexaScanInfoResponse
    func getDexaComposition(resultId: String) async throws -> BodySpecDexaCompositionResponse
}

extension BodySpecAPI: BodySpecDexaAPIClient {}

actor BodySpecDexaImporter: MetricSourceAdapter {
    @MainActor static let shared = BodySpecDexaImporter(api: BodySpecAPI.shared, authManager: .shared)

    // Provider events are unverified. Never infer push delivery from a connected account.
    nonisolated let capabilities = MetricSourceCapabilities(incrementalPull: true, scheduledPoll: true)
    private let api: BodySpecDexaAPIClient
    private let authManager: AuthManager
    private let coreDataManager: CoreDataManager
    private let userDefaults: UserDefaults
    private let syncGuard: @MainActor () throws -> Void
    private let syncTrigger: @MainActor () -> Void

    init(
        api: BodySpecDexaAPIClient,
        authManager: AuthManager,
        coreDataManager: CoreDataManager = .shared,
        userDefaults: UserDefaults = .standard,
        syncGuard: @escaping @MainActor () throws -> Void = {},
        syncTrigger: @escaping @MainActor () -> Void = {
            RealtimeSyncManager.shared.updatePendingSyncCount()
            RealtimeSyncManager.shared.syncIfNeeded()
        }
    ) {
        self.api = api
        self.authManager = authManager
        self.coreDataManager = coreDataManager
        self.userDefaults = userDefaults
        self.syncGuard = syncGuard
        self.syncTrigger = syncTrigger
    }

    var lastSuccessfulSync: Date? {
        get async {
            await MainActor.run {
                guard let ownership = authManager.captureAccountSession() else { return nil }
                return userDefaults.object(forKey: lastSyncKey(for: ownership.subject)) as? Date
            }
        }
    }

    nonisolated func idempotencyKey(for report: BodySpecResultSummary) -> String { report.resultId }

    func checkEntitlementAndCost() async throws { try await syncGuard() }

    func replay(from startDate: Date?) async throws -> ImportResult {
        try Task.checkCancellation()
        try await checkEntitlementAndCost()
        return await importDexaResults(from: startDate)
    }

    struct ImportResult {
        let importedCount: Int
        let skippedCount: Int
        let failedCount: Int
        let wasCancelled: Bool

        var summaryTitle: String { failedCount > 0 || wasCancelled ? "Sync incomplete" : "Sync complete" }
        var summary: String {
            if wasCancelled { return "Sync stopped. Sign in and try again to finish importing your scans." }
            if failedCount > 0 { return "Some scans couldn’t be imported. Try again to finish syncing." }
            if importedCount == 0, skippedCount == 0 { return "No new DEXA scans found." }
            let importedUnit = importedCount == 1 ? "scan" : "scans"
            let skippedUnit = skippedCount == 1 ? "scan" : "scans"
            return "Imported \(importedCount) new \(importedUnit) and skipped \(skippedCount) \(skippedUnit)."
        }
    }

    func importDexaResults() async -> ImportResult {
        do {
            return try await MetricSourceScheduler.replay(self, triggeredBy: .incrementalPull)
                ?? ImportResult(importedCount: 0, skippedCount: 0, failedCount: 0, wasCancelled: false)
        } catch {
            return ImportResult(importedCount: 0, skippedCount: 0, failedCount: 0, wasCancelled: true)
        }
    }

    private func importDexaResults(from startDate: Date?) async -> ImportResult {
        guard Constants.isBodySpecEnabled else {
            return ImportResult(importedCount: 0, skippedCount: 0, failedCount: 0, wasCancelled: false)
        }

        guard let ownership = await MainActor.run(body: { authManager.captureAccountSession() }) else {
            return ImportResult(importedCount: 0, skippedCount: 0, failedCount: 0, wasCancelled: true)
        }
        let session: BodySpecDexaImportSession
        do {
            let captured = try await api.importSession(for: ownership)
            session = BodySpecDexaImportSession(api: captured.api, admission: { [syncGuard] in
                try syncGuard()
                try captured.admission()
            })
            try await session.admission()
        } catch {
            return ImportResult(importedCount: 0, skippedCount: 0, failedCount: 0, wasCancelled: true)
        }
        let userId = ownership.subject
        var imported = 0
        var skipped = 0
        var failed = 0
        var cancelled = false

        var page = 1
        let pageSize = 50

        while true {
            do {
                try await requireOwnership(ownership)
                try await session.admission()
                let pageResponse = try await session.api.listResults(page: page, pageSize: pageSize)
                try await requireOwnership(ownership)
                try await session.admission()

                let dexaResults = pageResponse.results.filter { summary in
                    if let startDate, summary.startTime < startDate { return false }
                    guard let code = summary.service.serviceCode?.uppercased() else {
                        return summary.service.name.uppercased() == "DEXA"
                    }
                    return code == "DXA"
                }

                if dexaResults.isEmpty && pageResponse.results.isEmpty {
                    break
                }

                for summary in dexaResults {
                    do {
                        let outcome = try await importSingleResult(summary: summary, ownership: ownership, session: session)
                        if outcome == .duplicate { skipped += 1 } else { imported += 1 }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        failed += 1
                        report(error, operation: "bodySpecImportSingle", userId: userId)
                    }
                }

                if pageResponse.results.count < pageSize {
                    break
                }

                page += 1
            } catch is CancellationError {
                cancelled = true
                break
            } catch {
                failed += 1
                report(error, operation: "bodySpecImportPage\(page)", userId: userId)
                break
            }
        }

        if failed == 0, !cancelled {
            do {
                try await MainActor.run {
                    try Task.checkCancellation()
                    try session.admission()
                    guard authManager.ownsAccountSession(ownership) else { throw CancellationError() }
                    userDefaults.set(Date(), forKey: lastSyncKey(for: userId))
                }
            } catch {
                cancelled = true
            }
        }
        return ImportResult(importedCount: imported, skippedCount: skipped, failedCount: failed, wasCancelled: cancelled)
    }

    nonisolated private func lastSyncKey(for userId: String) -> String {
        "metricSource.bodySpec.lastSuccessfulSync.\(userId)"
    }

    private func importSingleResult(
        summary: BodySpecResultSummary,
        ownership: AuthManager.ProfileSessionOwnership,
        session: BodySpecDexaImportSession
    ) async throws -> BodySpecPairCommitOutcome {
        let userId = ownership.subject
        let reportID = idempotencyKey(for: summary)
        guard !reportID.isEmpty else { throw BodySpecImportPersistenceError.invalidPair }
        try await requireOwnership(ownership)
        try await session.admission()
        let scanInfo = try await session.api.getDexaScanInfo(resultId: reportID)
        try await requireOwnership(ownership)
        guard scanInfo.resultId == reportID else { throw BodySpecImportPersistenceError.invalidPair }
        if try await MainActor.run(body: {
            try coreDataManager.hasCompleteBodySpecImportPair(externalID: reportID, userId: userId) {
                try Task.checkCancellation()
                try session.admission()
                guard authManager.ownsAccountSession(ownership) else { throw CancellationError() }
            }
        }) { return .duplicate }
        let composition = try await session.api.getDexaComposition(resultId: reportID)
        try await requireOwnership(ownership)
        guard scanInfo.resultId == reportID, composition.resultId == reportID else {
            throw BodySpecImportPersistenceError.invalidPair
        }

        let measurements = try reportedLeanMass(kilograms: composition.total.leanMassKg)
        let metricsId = UUID().uuidString
        let date = scanInfo.acquireTime

        let now = Date()
        let importedAt = ISO8601DateFormatter().string(from: now)

        let bodyMetrics = BodyMetrics(
            id: metricsId,
            userId: userId,
            date: date,
            localDate: BodyMetricLocalDate.key(for: date),
            weight: composition.total.totalMassKg,
            weightUnit: "kg",
            bodyFatPercentage: composition.total.regionFatPct,
            bodyFatMethod: "DEXA (BodySpec)",
            // BodySpec's explicit lean mass is not a muscle measurement.
            muscleMass: nil,
            boneMass: composition.total.boneMassKg,
            notes: "Imported from BodySpec DEXA",
            photoUrl: nil,
            dataSource: BodyMetricSource.bodySpecDexa.rawValue,
            sourceMetadata: BodyMetricSourceMetadata(
                vendor: "bodyspec",
                sourceName: "BodySpec DEXA",
                externalId: summary.service.serviceId,
                externalResultId: reportID,
                scannerModel: scanInfo.scannerModel,
                locationId: summary.location.locationId,
                locationName: summary.location.name,
                importedAt: importedAt
            ),
            createdAt: now,
            updatedAt: now
        )

        let dexaResult = DexaResult(
            id: UUID().uuidString,
            userId: userId,
            bodyMetricsId: metricsId,
            externalSource: "bodyspec",
            externalResultId: reportID,
            externalUpdateTime: scanInfo.analyzeTime,
            scannerModel: scanInfo.scannerModel,
            locationId: summary.location.locationId,
            locationName: summary.location.name,
            acquireTime: scanInfo.acquireTime,
            analyzeTime: scanInfo.analyzeTime,
            vatMassKg: nil,
            vatVolumeCm3: nil,
            reportedMeasurements: measurements,
            resultPdfUrl: nil,
            resultPdfName: nil,
            createdAt: now,
            updatedAt: now
        )

        return try await MainActor.run {
            let outcome = try coreDataManager.commitBodySpecImportPair(
                metric: bodyMetrics, result: dexaResult, userId: userId
            ) { [authManager] in
                try Task.checkCancellation()
                try session.admission()
                guard authManager.ownsAccountSession(ownership) else { throw CancellationError() }
            }
            if outcome != .duplicate { syncTrigger() }
            return outcome
        }
    }
    /// Preserve the reported field without deriving another mass category.
    private func reportedLeanMass(kilograms: Double) throws -> ReportedMeasurements {
        guard kilograms.isFinite, kilograms > 0 else { throw BodySpecImportPersistenceError.invalidPair }
        let data = try JSONSerialization.data(withJSONObject: [
            "schema_version": 1,
            "items": [[
                "kind": ReportedMeasurements.Kind.leanMass.rawValue,
                "value": kilograms,
                "unit": ReportedMeasurements.Unit.kilograms.rawValue,
                "reported_label": "lean_mass_kg",
                "reported_unit": "kg"
            ]]
        ])
        // Use the same bounded wire validator as storage and sync, never silently omit invalid data.
        return try JSONDecoder().decode(ReportedMeasurements.self, from: data)
    }

    private func requireOwnership(_ ownership: AuthManager.ProfileSessionOwnership) async throws {
        try Task.checkCancellation()
        guard await MainActor.run(body: { authManager.ownsAccountSession(ownership) }) else {
            throw CancellationError()
        }
    }

    private func report(_ error: Error, operation: String, userId: String) {
        ErrorReporter.shared.captureNonFatal(error, context: ErrorContext(
            feature: "sync", operation: operation, screen: nil, userId: userId
        ))
    }
}

struct DexaPDFScan: Decodable, Equatable {
    let date: String
    let weight: Double
    let weightUnit: String
    let bodyFatPercentage: Double?
    let muscleMass: Double?
    let boneMass: Double?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case date
        case weight
        case weightUnit = "weight_unit"
        case bodyFatPercentage = "body_fat_percentage"
        case muscleMass = "muscle_mass"
        case boneMass = "bone_mass"
        case source
    }
}

/// A reported source label is evidence of a method only when it explicitly names one.
/// Preserve that label separately; it is not a scanner-model identifier.
struct PDFScanProvenance {
    let reportedLabel: String?
    let dataSource: String
    let bodyFatMethod: String?
    let importNote: String

    var displayLabel: String { reportedLabel ?? "Source not identified" }

    init(source: String?) {
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        reportedLabel = trimmed?.isEmpty == false ? trimmed : nil
        let words = (reportedLabel ?? "").lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        let mentionsInBody = words.contains("inbody") || zip(words, words.dropFirst()).contains {
            $0.0 == "in" && $0.1 == "body"
        }
        let mentionsDexa = words.contains("dexa") || words.contains("dxa")
        let isInBodyLabel = words.first == "inbody" || words.starts(with: ["in", "body"])
        let isDexaLabel = words.first == "dexa" || words.first == "dxa"
        let uncertaintyWords: Set<String> = [
            "no", "not", "non", "cannot", "unknown", "unidentified", "unspecified", "undetermined",
            "uncertain", "unconfirmed", "unverified", "unclear", "possible", "possibly", "probable",
            "probably", "suspected", "maybe", "tentative", "pending"
        ]
        let hasUncertainMethod = !uncertaintyWords.isDisjoint(with: words) || reportedLabel?.contains("?") == true

        if isInBodyLabel && !mentionsDexa && !hasUncertainMethod {
            dataSource = BodyMetricSource.inbodyPDF.rawValue
            bodyFatMethod = "inbody"
            importNote = "Imported from InBody PDF"
        } else if isDexaLabel && !mentionsInBody && !hasUncertainMethod {
            dataSource = BodyMetricSource.dexaPDF.rawValue
            bodyFatMethod = "dexa"
            importNote = "Imported from DEXA PDF"
        } else {
            dataSource = BodyMetricSource.pdfImport.rawValue
            bodyFatMethod = nil
            importNote = "Imported from PDF"
        }
    }
}

private struct DexaPDFParserResponse: Decodable {
    struct Payload: Decodable {
        let scans: [DexaPDFScan]?
    }

    let success: Bool?
    let error: String?
    let details: String?
    let data: Payload?
}

struct DexaPDFImportPlan {
    let metrics: [BodyMetrics]
    let results: [DexaResult]
    let skippedDuplicateCount: Int
}

enum DexaPDFScanMapper {
    static func makePlan(
        scans: [DexaPDFScan],
        userId: String,
        existingResults: [DexaResult],
        now: Date = Date()
    ) -> DexaPDFImportPlan {
        let existingResultIds = Set(existingResults.map(\.externalResultId))
        var candidateResults: [DexaResult] = []
        var candidateMetrics: [BodyMetrics] = []
        var seenIds = existingResultIds
        var skippedDuplicates = 0

        for scan in scans {
            guard let date = date(for: scan.date), scan.weight > 0 else { continue }
            let provenance = PDFScanProvenance(source: scan.source)
            let dataSource = provenance.dataSource
            let externalResultId = stableResultId(for: scan, dataSource: dataSource)
            guard !matchesLegacyImport(scan, dataSource: dataSource, existingResults: existingResults),
                  seenIds.insert(externalResultId).inserted else {
                skippedDuplicates += 1
                continue
            }

            let metricsId = UUID().uuidString
            candidateMetrics.append(
                BodyMetrics(
                    id: metricsId,
                    userId: userId,
                    date: date,
                    localDate: scan.date,
                    weight: scan.weight,
                    weightUnit: scan.weightUnit.lowercased(),
                    bodyFatPercentage: scan.bodyFatPercentage,
                    bodyFatMethod: provenance.bodyFatMethod,
                    muscleMass: scan.muscleMass,
                    boneMass: scan.boneMass,
                    notes: provenance.importNote,
                    photoUrl: nil,
                    dataSource: dataSource,
                    sourceMetadata: BodyMetricSourceMetadata(
                        vendor: "pdf_import",
                        sourceName: provenance.reportedLabel,
                        externalResultId: externalResultId,
                        importedAt: ISO8601DateFormatter().string(from: now)
                    ),
                    createdAt: now,
                    updatedAt: now
                )
            )

            candidateResults.append(
                DexaResult(
                    id: UUID().uuidString,
                    userId: userId,
                    bodyMetricsId: metricsId,
                    externalSource: dataSource,
                    externalResultId: externalResultId,
                    externalUpdateTime: nil,
                    scannerModel: nil,
                    locationId: nil,
                    locationName: nil,
                    acquireTime: date,
                    analyzeTime: nil,
                    vatMassKg: nil,
                    vatVolumeCm3: nil,
                    scanWeight: scan.weight,
                    scanWeightUnit: scan.weightUnit.lowercased(),
                    bodyFatPercentage: scan.bodyFatPercentage,
                    muscleMass: scan.muscleMass,
                    boneMass: scan.boneMass,
                    resultPdfUrl: nil,
                    resultPdfName: nil,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        return DexaPDFImportPlan(
            metrics: candidateMetrics,
            results: candidateResults,
            skippedDuplicateCount: skippedDuplicates
        )
    }

    private static func matchesLegacyImport(
        _ scan: DexaPDFScan,
        dataSource: String,
        existingResults: [DexaResult]
    ) -> Bool {
        let oldLabel = scan.source ?? "DEXA Scan"
        let oldSource = oldLabel.localizedCaseInsensitiveContains("inbody")
            ? BodyMetricSource.inbodyPDF.rawValue : BodyMetricSource.dexaPDF.rawValue
        guard oldSource != dataSource else { return false }
        let oldId = stableResultId(for: scan, dataSource: oldSource)
        let oldTrimmedLabel = oldLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        // Old imports stored their report label in scannerModel. Require that
        // evidence so the old ID cannot hide a different reported source. Do
        // not add this alias to seenIds: new unknown and DEXA rows are distinct.
        return existingResults.contains { result in
            result.externalResultId == oldId && result.externalSource == oldSource &&
                result.scannerModel?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(oldTrimmedLabel) == .orderedSame
        }
    }

    private static func date(for value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func stableResultId(for scan: DexaPDFScan, dataSource: String) -> String {
        let canonicalValue = [
            dataSource,
            scan.date,
            String(scan.weight),
            scan.weightUnit.lowercased(),
            scan.bodyFatPercentage.map { String($0) } ?? "",
            scan.muscleMass.map { String($0) } ?? "",
            scan.boneMass.map { String($0) } ?? ""
        ].joined(separator: "|")
        let digest = SHA256.hash(data: Data(canonicalValue.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class DexaPDFImportCoordinator {
    static let shared = DexaPDFImportCoordinator()

    private let coreDataManager: CoreDataManager
    private let session: URLSession

    init(coreDataManager: CoreDataManager = .shared, session: URLSession? = nil) {
        self.coreDataManager = coreDataManager
        self.session = session ?? ProductAPIClient.shared.session
    }

    func parse(fileData: Data, fileName: String, accessToken: String) async throws -> [DexaPDFScan] {
        guard fileData.count <= 10 * 1_024 * 1_024 else {
            throw DexaPDFImportError.fileTooLarge
        }

        let url = try ProductAPIClient.shared.productAPIURL("/api/parse-pdf")
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")

        var body = Data()
        let safeFileName = fileName.replacingOccurrences(of: "\"", with: "")
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFileName)\"\r\n".utf8))
        body.append(Data("Content-Type: application/pdf\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DexaPDFImportError.invalidResponse
        }
        let parsed = try? JSONDecoder().decode(DexaPDFParserResponse.self, from: responseData)
        guard (200...299).contains(httpResponse.statusCode) else {
            throw DexaPDFImportError.server(parsed?.details ?? parsed?.error ?? "The scan could not be read.")
        }
        guard parsed?.success == true, let scans = parsed?.data?.scans, !scans.isEmpty else {
            throw DexaPDFImportError.server(parsed?.details ?? parsed?.error ?? "No scan data was found.")
        }
        return scans
    }

    func save(scans: [DexaPDFScan], userId: String) async throws -> DexaPDFImportPlan {
        let existingResults = await coreDataManager.fetchDexaResults(for: userId, limit: 1_000)
        let plan = DexaPDFScanMapper.makePlan(
            scans: scans,
            userId: userId,
            existingResults: existingResults
        )

        for metric in plan.metrics {
            try await coreDataManager.saveBodyMetricsAndWait(metric, userId: userId, markAsSynced: false)
        }
        try await coreDataManager.saveDexaResultsAndWait(plan.results, userId: userId, markAsSynced: false)
        RealtimeSyncManager.shared.updatePendingSyncCount()
        RealtimeSyncManager.shared.syncIfNeeded()
        return plan
    }
}

enum DexaPDFImportError: LocalizedError {
    case fileTooLarge
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "Choose a PDF under 10 MB."
        case .invalidResponse:
            "The scan service returned an invalid response."
        case .server(let message):
            message
        }
    }
}
