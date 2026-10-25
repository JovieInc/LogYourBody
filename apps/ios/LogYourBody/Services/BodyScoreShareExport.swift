import CryptoKit
import os
import SwiftUI
import UIKit

/// All export inputs are frozen at the tap. Never log this fingerprint or its inputs.
struct BodyScoreShareSnapshot: Equatable {
    let payload: BodyScoreSharePayload
    let aspect: BodyScoreShareAspect
    let options: BodyScoreShareOptions
    var rendererRevision = 1

    var fingerprint: Data {
        let fields: [String?] = [
            String(payload.score), payload.scoreText, payload.tagline, payload.ffmiValue, payload.ffmiCaption,
            payload.bodyFatValue, payload.bodyFatCaption, payload.weightValue, payload.weightCaption,
            payload.deltaText, payload.bodyFatPercentage.map { String($0) }, payload.gender,
            payload.photoImage.map { String(describing: ObjectIdentifier($0)) },
            payload.preferredMetric?.rawValue, payload.accountSession?.subject,
            payload.accountSession.map { String($0.generation) }, aspect.rawValue, String(rendererRevision),
            options.selectedMetric?.rawValue
        ] + [options.includeObservation, options.includeRange, options.includeTrend, options.includeProvenance,
             options.includeWeight, options.includeBodyFat, options.includeFFMI, options.includeVisual].map { String($0) }
        let metrics = payload.contextualMetrics.map {
            [$0.kind.rawValue, $0.value, $0.unit, $0.observation, $0.range, $0.trend, $0.provenance, $0.evidence]
        }
        // Length-prefixed fields distinguish nil, empty strings, and embedded delimiters.
        var digest = SHA256()
        for field in fields + metrics.flatMap({ $0 }) {
            let value = field.map { "\($0.utf8.count):\($0)" } ?? "nil:"
            digest.update(data: Data(value.utf8))
        }
        return Data(digest.finalize())
    }
}

enum SharePhotoSaveResult: Equatable {
    case saved, denied, restricted, failed, cancelled
}

enum BodyScoreShareFailure: Error, Equatable {
    case render, file, photosDenied, photosRestricted, photosWrite, systemShare, sessionLimit

    var message: String {
        switch self {
        case .render: return "The card could not be rendered. Try again."
        case .file: return "The card could not be prepared. Free some storage and try again."
        case .photosDenied: return "Allow Photos access in Settings, or use Share."
        case .photosRestricted: return "Photos access is restricted on this device. Use Share instead."
        case .photosWrite: return "Photos could not save the card. Check storage and try again, or use Share."
        case .systemShare: return "The card could not be shared. Try again or use Save."
        case .sessionLimit: return "Close and reopen this sheet to save more cards."
        }
    }
}

enum BodyScoreShareState: Equatable {
    case idle, preparing, rendering, saving, sharing, succeeded, failed(BodyScoreShareFailure), cancelled

    var message: String {
        switch self {
        case .idle: return ""
        case .preparing: return "Preparing card…"
        case .rendering: return "Rendering card…"
        case .saving: return "Saving to Photos…"
        case .sharing: return "Sharing card…"
        case .succeeded: return "Done"
        case .failed(let failure): return failure.message
        case .cancelled: return "Export cancelled"
        }
    }
}

struct BodyScoreSharePresentation: Identifiable {
    let id: UUID
    let url: URL
}

/// Only fixed phase names enter Instruments; no health values, account IDs, or fingerprints.
enum BodyScoreShareTrace {
    static let log = OSLog(subsystem: "com.logyourbody.app", category: "ShareExport")

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, _ id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}

/// One worker and one artifact per sheet. No rendered-image cache can outlive a payload/privacy edit.
@MainActor
final class BodyScoreShareExport: ObservableObject {
    enum Action { case save, share }
    typealias Save = @MainActor (URL, @escaping @MainActor () -> Bool) async -> SharePhotoSaveResult

    private final class SavedContent {
        weak var photo: UIImage?
        let hadPhoto: Bool

        init(_ photo: UIImage?) {
            self.photo = photo
            hadPhoto = photo != nil
        }

        func matches(_ candidate: UIImage?) -> Bool {
            hadPhoto ? photo != nil && photo === candidate : candidate == nil
        }
    }

    @Published private(set) var state: BodyScoreShareState = .idle
    @Published private(set) var presentation: BodyScoreSharePresentation?
    @Published private(set) var isSystemSharePresented = false
    @Published private(set) var isBusy = false
    private var task: Task<Void, Never>?
    private var operationID: UUID?
    private var ownsOperation: (@MainActor () -> Bool)?
    private var current: BodyScoreShareSnapshot?
    private var savedFingerprints: [Data: SavedContent] = [:]
    private let prepare: (BodyScoreShareSnapshot) async throws -> BodyScoreShareSnapshot
    private let render: @MainActor (BodyScoreShareSnapshot) -> UIImage?
    private let encode: (UIImage) async throws -> URL
    private let remove: (URL) async -> Void
    private let save: Save
    private var feedbackTrace: OSSignpostID?

    init(
        prepare: @escaping (BodyScoreShareSnapshot) async throws -> BodyScoreShareSnapshot = {
            try await BodyScoreShareImageWorker.shared.prepare($0)
        },
        render: @escaping @MainActor (BodyScoreShareSnapshot) -> UIImage? = { BodyScoreShareExport.capture($0) },
        encode: @escaping (UIImage) async throws -> URL = { try await BodyScoreShareImageWorker.shared.encode($0) },
        remove: @escaping (URL) async -> Void = { await BodyScoreShareImageWorker.shared.remove($0) },
        save: @escaping Save = { await LivePhotoLibraryAdapter.shared.saveShareCard($0, whileOwned: $1) }
    ) {
        self.prepare = prepare
        self.render = render
        self.encode = encode
        self.remove = remove
        self.save = save
    }

    func start(_ action: Action, snapshot: BodyScoreShareSnapshot, isCurrent: @escaping @MainActor () -> Bool) {
        guard !isBusy, isCurrent() else { return }
        current = snapshot
        if action == .save, savedFingerprints[snapshot.fingerprint]?.matches(snapshot.payload.photoImage) == true {
            state = .succeeded
            return
        }
        // Bound receipts without retaining any source photos. A new sheet starts a new session.
        guard action != .save || savedFingerprints.count < 128 else { state = .failed(.sessionLimit); return }
        operationID = UUID()
        ownsOperation = isCurrent
        let id = operationID
        isBusy = true
        feedbackTrace = BodyScoreShareTrace.begin("TapToFeedback")
        state = .preparing // Synchronous acknowledgement, before any image work or Task is created.
        task = Task { [weak self] in
            // Give SwiftUI a presentation turn. This is not evidence of device frame latency.
            try? await Task.sleep(for: .milliseconds(20))
            guard let self else { return }
            await self.run(action, snapshot: snapshot, id: id, isCurrent: isCurrent)
        }
    }

    func feedbackDidAppear() {
        guard let feedbackTrace else { return }
        BodyScoreShareTrace.end("TapToFeedback", feedbackTrace)
        self.feedbackTrace = nil
    }

    func reconcile(_ snapshot: BodyScoreShareSnapshot) {
        guard let current, current != snapshot else { return }
        invalidate()
    }

    func invalidate() {
        operationID = nil
        ownsOperation = nil
        current = nil
        task?.cancel()
        feedbackDidAppear()
        state = .cancelled
        isSystemSharePresented = false
        // Keep the task slot occupied until even a cancellation-ignoring adapter drains.
        if task == nil, let presentation {
            self.presentation = nil
            isBusy = true
            task = Task { [weak self, remove] in
                await remove(presentation.url)
                self?.task = nil
                self?.isBusy = false
            }
        }
    }

    /// SwiftUI dismissal can precede the activity callback. It is not an outcome receipt.
    func hideSystemShare() { isSystemSharePresented = false }

    func completeShare(id: UUID, completed: Bool, failed: Bool = false) {
        guard presentation?.id == id else { return }
        guard operationID == id, ownsOperation?() == true else { invalidate(); return }
        state = failed ? .failed(.systemShare) : completed ? .succeeded : .cancelled
        operationID = nil
        ownsOperation = nil
        let url = presentation?.url
        isSystemSharePresented = false
        presentation = nil
        task = Task { [weak self, remove] in
            if let url { await remove(url) }
            self?.task = nil
            self?.isBusy = false
        }
    }

    private func run(
        _ action: Action, snapshot: BodyScoreShareSnapshot, id: UUID?, isCurrent: @escaping @MainActor () -> Bool
    ) async {
        var artifact: URL?
        do {
            try check(id, isCurrent)
            artifact = try await makeArtifact(snapshot, id: id, isCurrent: isCurrent)
            try check(id, isCurrent)
            if action == .share, let artifact, let id {
                state = .sharing
                presentation = BodyScoreSharePresentation(id: id, url: artifact)
                isSystemSharePresented = true
                task = nil
                return // Presentation owns the file until the activity completion/dismiss callback.
            }
            if let artifact {
                state = .saving
                let result = await save(artifact, { self.operationID == id && isCurrent() && !Task.isCancelled })
                if result == .saved { savedFingerprints[snapshot.fingerprint] = SavedContent(snapshot.payload.photoImage) }
                try check(id, isCurrent)
                switch result {
                case .saved: state = .succeeded
                case .denied: state = .failed(.photosDenied)
                case .restricted: state = .failed(.photosRestricted)
                case .failed: state = .failed(.photosWrite)
                case .cancelled: state = .cancelled
                }
            }
        } catch is CancellationError {
            if operationID == id { state = .cancelled }
        } catch {
            if operationID == id { state = .failed(error as? BodyScoreShareFailure ?? .file) }
        }
        if let artifact { await remove(artifact) }
        ownsOperation = nil
        task = nil
        isBusy = false
    }

    private func makeArtifact(
        _ snapshot: BodyScoreShareSnapshot, id: UUID?, isCurrent: @escaping @MainActor () -> Bool
    ) async throws -> URL {
        let prepared = try await prepare(snapshot)
        try check(id, isCurrent)
        state = .rendering
        let image = try autoreleasepool {
            guard let image = render(prepared) else { throw BodyScoreShareFailure.render }
            return image
        }
        try check(id, isCurrent)
        return try await encode(image)
    }

    private func check(_ id: UUID?, _ isCurrent: () -> Bool) throws {
        guard operationID == id, isCurrent(), !Task.isCancelled else { throw CancellationError() }
    }

    static func capture(_ snapshot: BodyScoreShareSnapshot) -> UIImage? {
        let trace = BodyScoreShareTrace.begin("MainCapture")
        defer { BodyScoreShareTrace.end("MainCapture", trace) }
        let size = snapshot.aspect.pixelSize
        let renderer = ImageRenderer(content: BodyScoreShareCardView(
            payload: snapshot.payload, aspect: snapshot.aspect, options: snapshot.options)
            .frame(width: size.width, height: size.height).environment(\.colorScheme, .dark))
        renderer.scale = 1
        return renderer.uiImage
    }
}

actor BodyScoreShareImageWorker {
    static let shared = BodyScoreShareImageWorker()

    func prepare(_ snapshot: BodyScoreShareSnapshot) async throws -> BodyScoreShareSnapshot {
        let trace = BodyScoreShareTrace.begin("ImagePreparation")
        defer { BodyScoreShareTrace.end("ImagePreparation", trace) }
        try Task.checkCancellation()
        var payload = snapshot.payload
        if snapshot.options.includeVisual, snapshot.options.selectedMetric == nil, let photo = payload.photoImage {
            guard let thumbnail = await photo.byPreparingThumbnail(ofSize: snapshot.aspect.pixelSize) else {
                throw BodyScoreShareFailure.render
            }
            payload.photoImage = thumbnail
        } else {
            payload.photoImage = nil
        }
        try Task.checkCancellation()
        return BodyScoreShareSnapshot(payload: payload, aspect: snapshot.aspect, options: snapshot.options,
                                      rendererRevision: snapshot.rendererRevision)
    }

    func encode(_ image: UIImage) throws -> URL {
        let trace = BodyScoreShareTrace.begin("EncodeAndWrite")
        defer { BodyScoreShareTrace.end("EncodeAndWrite", trace) }
        try Task.checkCancellation()
        return try autoreleasepool {
            guard let data = image.pngData() else { throw BodyScoreShareFailure.file }
            try Task.checkCancellation()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            do {
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                try Task.checkCancellation()
                return url
            } catch {
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }
    }

    func remove(_ url: URL) { try? FileManager.default.removeItem(at: url) }
}
