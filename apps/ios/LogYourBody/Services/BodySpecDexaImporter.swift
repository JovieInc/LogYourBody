import Foundation
import CryptoKit

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
                localDate: BodyMetricLocalDate.key(for: date),
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

            // Best-effort upsert of DEXA metadata to ProductAPI
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
        let existing = await coreDataManager.fetchBodyMetrics(
            for: userId,
            localDate: BodyMetricLocalDate.key(for: scanDate)
        )

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
