//
// LocalExportWork.swift
// LogYourBody
//
// Local export reads value snapshots on a background context and encodes off the main actor.
//

import CoreData
import Foundation

enum LocalExportFormat: Equatable {
    case json
    case csv

    var fileExtension: String {
        switch self {
        case .json:
            return "json"
        case .csv:
            return "csv"
        }
    }
}

struct ExportValueSnapshots {
    var bodyMetrics: [BodyMetrics]
    var dailyLogs: [DailyLog]
}

struct ExportValueSnapshotProbe: Equatable {
    var isPrivateQueue: Bool
    var isViewContext: Bool
    var isMainThread: Bool
}

struct ExportValueSnapshotRead {
    var snapshots: ExportValueSnapshots
    var probe: ExportValueSnapshotProbe
}

struct LocalExportFile: Equatable {
    var url: URL
    var encodedOffMainActor: Bool
}

enum LocalExportWriteResult: Equatable {
    case file(LocalExportFile)
    case unavailable
}

struct LocalExportRequest {
    var user: User
    var snapshots: ExportValueSnapshots
    var formats: Set<LocalExportFormat>
    var includePhotos: Bool
    var heightCm: Double?
    var now = Date()
}

@MainActor
final class LocalExportFlight {
    private(set) var isExporting = false

    /// Synchronous admission. A second caller gets false and starts no work.
    func begin() -> Bool {
        guard !isExporting else { return false }
        isExporting = true
        return true
    }

    func end() {
        isExporting = false
    }
}

@MainActor
enum LocalExportCoordinator {
    static func start(
        flight: LocalExportFlight,
        operation: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never>? {
        guard flight.begin() else { return nil }
        return Task { @MainActor in
            defer { flight.end() }
            await operation()
        }
    }
}

extension CoreDataManager {
    /// Reads export rows on a private-queue context and returns value snapshots only.
    func fetchExportValueSnapshots(for userId: String) async -> ExportValueSnapshotRead {
        let viewIdentity = await MainActor.run {
            ObjectIdentifier(persistentContainer.viewContext)
        }
        let context = persistentContainer.newBackgroundContext()
        return await context.perform {
            let probe = ExportValueSnapshotProbe(
                isPrivateQueue: context.concurrencyType == .privateQueueConcurrencyType,
                isViewContext: ObjectIdentifier(context) == viewIdentity,
                isMainThread: Thread.isMainThread
            )
            return ExportValueSnapshotRead(
                snapshots: ExportValueSnapshots(
                    bodyMetrics: Self.bodySnapshots(in: context, userId: userId),
                    dailyLogs: Self.dailySnapshots(in: context, userId: userId)
                ),
                probe: probe
            )
        }
    }

    private static func bodySnapshots(in context: NSManagedObjectContext, userId: String) -> [BodyMetrics] {
        let request: NSFetchRequest<CachedBodyMetrics> = CachedBodyMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        let cached = (try? context.fetch(request)) ?? []
        return cached.compactMap { $0.toBodyMetrics() }
    }

    private static func dailySnapshots(in context: NSManagedObjectContext, userId: String) -> [DailyLog] {
        let request: NSFetchRequest<CachedDailyMetrics> = CachedDailyMetrics.fetchRequest()
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]
        guard let cached = try? context.fetch(request) else { return [] }
        return cached.map { log in
            DailyLog(
                id: log.id ?? UUID().uuidString,
                userId: log.userId ?? "",
                date: log.date ?? Date(),
                weight: nil,
                weightUnit: nil,
                stepCount: Int(log.steps),
                notes: log.notes,
                createdAt: log.createdAt ?? Date(),
                updatedAt: log.updatedAt ?? Date()
            )
        }
    }
}

enum LocalExportWork {
    private static let fileDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func write(_ request: LocalExportRequest) async throws -> LocalExportWriteResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try InteractionSignpost.measureExportEncode {
                        try encode(request)
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func encode(_ request: LocalExportRequest) throws -> LocalExportWriteResult {
        let encodedOffMainActor = !Thread.isMainThread
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogYourBody_Export_\(request.now.timeIntervalSince1970)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let export = ExportData(
            exportDate: request.now,
            user: request.user,
            bodyMetrics: request.snapshots.bodyMetrics,
            dailyLogs: request.snapshots.dailyLogs,
            photoURLs: request.includePhotos ? request.snapshots.bodyMetrics.compactMap(\.photoUrl) : []
        )
        var urls: [URL] = []
        if request.formats.contains(.json) {
            urls.append(try writeJSON(export, to: directory, now: request.now))
        }
        if request.formats.contains(.csv) {
            urls.append(contentsOf: try writeCSV(export, to: directory, heightCm: request.heightCm, now: request.now))
        }
        if request.includePhotos, !export.photoURLs.isEmpty {
            urls.append(try writePhotoManifest(export.photoURLs, to: directory))
        }
        guard urls.count == 1, let url = urls.first, FileManager.default.fileExists(atPath: url.path) else {
            return .unavailable
        }
        return .file(LocalExportFile(url: url, encodedOffMainActor: encodedOffMainActor))
    }

    private static func writeJSON(_ export: ExportData, to directory: URL, now: Date) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        let url = directory.appendingPathComponent("LogYourBody_Export_\(fileDay(now)).json")
        try data.write(to: url)
        return url
    }

    private static func writeCSV(
        _ export: ExportData,
        to directory: URL,
        heightCm: Double?,
        now: Date
    ) throws -> [URL] {
        let heightInches: Double?
        if let heightCm, heightCm > 0 {
            heightInches = heightCm / 2.54
        } else {
            heightInches = nil
        }
        let day = fileDay(now)
        var urls: [URL] = []
        let metricsURL = directory.appendingPathComponent("body_metrics_\(day).csv")
        try ExportCSVBuilder.makeBodyMetricsCSV(metrics: export.bodyMetrics, heightInches: heightInches)
            .write(to: metricsURL, atomically: true, encoding: .utf8)
        urls.append(metricsURL)
        if !export.dailyLogs.isEmpty {
            let logsURL = directory.appendingPathComponent("daily_logs_\(day).csv")
            try ExportCSVBuilder.makeDailyLogsCSV(logs: export.dailyLogs)
                .write(to: logsURL, atomically: true, encoding: .utf8)
            urls.append(logsURL)
        }
        return urls
    }

    private static func writePhotoManifest(_ photoURLs: [String], to directory: URL) throws -> URL {
        let photosDir = directory.appendingPathComponent("photos")
        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)
        let url = photosDir.appendingPathComponent("photo_urls.txt")
        try photoURLs.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func fileDay(_ date: Date) -> String {
        fileDayFormatter.string(from: date)
    }
}
