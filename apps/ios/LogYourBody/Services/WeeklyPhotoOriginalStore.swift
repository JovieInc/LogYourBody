//
// WeeklyPhotoOriginalStore.swift
// LogYourBody
//
import Foundation
import UIKit

enum WeeklyPhotoOriginalStore {
    static func applicationDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("weekly-photo-originals", isDirectory: true)
    }

    static func retain(_ data: Data, submissionId: String, directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let allowed = submissionId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let name = allowed.isEmpty ? "photo" : allowed
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func encodedJPEG(_ image: UIImage) -> Data? {
        image.jpegData(compressionQuality: 0.95)
    }

    /// Library bytes stay intact, including HEIC. A camera frame is encoded here,
    /// off any SwiftUI view, because the camera only hands back a bitmap.
    static func originalBytes(library: Data?, image: UIImage) -> Data? {
        if let library, !library.isEmpty { return library }
        return encodedJPEG(image)
    }
}

enum WeeklyPhotoPrepareResult: Sendable {
    case ready(WeeklyPhotoAttachPreparation)
    case empty
    case unavailable
}

struct WeeklyPhotoAttachPreparation: Sendable {
    var bytes: Data
    var fileURL: URL
    var orientation: Int

    /// Retains original bytes before any upload. Empty bytes are not a photo.
    /// A store failure keeps the attempt retryable without dropping the bytes.
    static func make(library: Data?, image: UIImage, submissionId: String) -> WeeklyPhotoPrepareResult {
        guard let bytes = WeeklyPhotoOriginalStore.originalBytes(library: library, image: image),
              !bytes.isEmpty else {
            return .empty
        }
        let orientation = PhotoMetadataService.shared.weeklyPhotoFacts(from: bytes).exifOrientation
        do {
            let url = try WeeklyPhotoOriginalStore.retain(
                bytes,
                submissionId: submissionId,
                directory: WeeklyPhotoOriginalStore.applicationDirectory()
            )
            return .ready(WeeklyPhotoAttachPreparation(bytes: bytes, fileURL: url, orientation: orientation))
        } catch {
            return .unavailable
        }
    }
}

enum WeeklyPhotoCheckInTelemetry {
    /// The default tracker is main-actor isolated, so this call is too.
    @MainActor
    static func emit(
        _ metrics: [WeeklyPhotoHabitMetric],
        tracker: AnalyticsTracking = AppServicePorts.analyticsTracker
    ) {
        for metric in metrics where metric.countsTowardHabit || metric.event == WeeklyPhotoCheckInPolicy.captureSaved ||
            metric.event == WeeklyPhotoCheckInPolicy.captureFailed {
            tracker.track(event: metric.event, properties: metric.properties)
        }
    }
}
