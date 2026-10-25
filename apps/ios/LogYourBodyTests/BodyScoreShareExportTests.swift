import XCTest
import UIKit
import Vision
@testable import LogYourBody

@MainActor
final class BodyScoreShareExportTests: XCTestCase {
    private final class Barrier {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
        func resume() { continuation?.resume(); continuation = nil }
    }

    func testRapidDoubleTapAcknowledgesSynchronouslyAndSavesExactlyOnce() async {
        let barrier = Barrier()
        var preparations = 0
        var saves = 0
        var removals = 0
        let exporter = makeExporter(prepare: { snapshot in
            preparations += 1
            await barrier.wait()
            return snapshot
        }, remove: { _ in removals += 1 }, save: { _, current in
            XCTAssertTrue(current())
            saves += 1
            return .saved
        })
        let snapshot = makeSnapshot()
        exporter.start(.save, snapshot: snapshot, isCurrent: { true })
        XCTAssertEqual(exporter.state, .preparing)
        XCTAssertTrue(exporter.isBusy)
        for _ in 0..<100 { exporter.start(.save, snapshot: snapshot, isCurrent: { true }) }
        await waitUntil { barrier.continuation != nil }
        XCTAssertEqual(preparations, 1)
        barrier.resume()
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(exporter.state, .succeeded)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(removals, 1)
        exporter.start(.save, snapshot: snapshot, isCurrent: { true })
        XCTAssertEqual(exporter.state, .succeeded)
        XCTAssertFalse(exporter.isBusy)
        XCTAssertEqual(saves, 1)
    }

    func testPayloadFormatAndPrivacyEditsSuppressDelayedPreparationWithoutSpawningTasks() async {
        var edits = [makeSnapshot(score: "91"), makeSnapshot(aspect: .story)]
        var options = BodyScoreShareOptions()
        options.includeVisual = true
        options.includeWeight = true
        edits.append(makeSnapshot(options: options))
        for edit in edits {
            let barrier = Barrier()
            var preparations = 0
            var captures = 0
            let exporter = makeExporter(prepare: { snapshot in
                preparations += 1
                await barrier.wait() // Deliberately ignores cancellation.
                return snapshot
            }, render: { _ in captures += 1; return UIImage() })
            exporter.start(.share, snapshot: makeSnapshot(), isCurrent: { true })
            await waitUntil { barrier.continuation != nil }
            exporter.reconcile(edit)
            for _ in 0..<100 { exporter.start(.share, snapshot: edit, isCurrent: { true }) }
            XCTAssertEqual(exporter.state, .cancelled)
            XCTAssertTrue(exporter.isBusy)
            barrier.resume()
            await waitUntil { !exporter.isBusy }
            XCTAssertEqual(preparations, 1)
            XCTAssertEqual(captures, 0)
            XCTAssertNil(exporter.presentation)
        }
    }

    func testDismissalDuringEncodingRemovesLateFileAndNeverPresentsIt() async {
        let barrier = Barrier()
        var removed: [URL] = []
        let url = URL(fileURLWithPath: "/tmp/synthetic-share.png")
        let exporter = makeExporter(encode: { _ in
            await barrier.wait()
            return url
        }, remove: { removed.append($0) })
        exporter.start(.share, snapshot: makeSnapshot(), isCurrent: { true })
        await waitUntil { barrier.continuation != nil }
        exporter.invalidate()
        barrier.resume()
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(exporter.state, .cancelled)
        XCTAssertNil(exporter.presentation)
        XCTAssertEqual(removed, [url])
    }

    func testLateSaveSuccessAfterEditIsSuppressedButReceiptPreventsDuplicateRetry() async {
        let barrier = Barrier()
        var saves = 0
        let exporter = makeExporter(save: { _, _ in
            saves += 1
            await barrier.wait() // Models an already-submitted, noncancellable Photos write.
            return .saved
        })
        let snapshot = makeSnapshot()
        exporter.start(.save, snapshot: snapshot, isCurrent: { true })
        await waitUntil { barrier.continuation != nil }
        XCTAssertEqual(exporter.state, .saving)
        exporter.reconcile(makeSnapshot(score: "91"))
        barrier.resume()
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(exporter.state, .cancelled)
        exporter.start(.save, snapshot: snapshot, isCurrent: { true })
        XCTAssertEqual(exporter.state, .succeeded)
        XCTAssertEqual(saves, 1)
    }

    func testRenderAndEncodingFailuresAreActionableAndRetryCanSucceed() async {
        var canRender = false
        var canEncode = false
        var saves = 0
        let exporter = makeExporter(render: { _ in canRender ? UIImage() : nil }, encode: { _ in
            guard canEncode else { throw BodyScoreShareFailure.file }
            return URL(fileURLWithPath: "/tmp/synthetic-share.png")
        }, save: { _, _ in saves += 1; return .saved })
        exporter.start(.save, snapshot: makeSnapshot(), isCurrent: { true })
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(exporter.state, .failed(.render))
        XCTAssertTrue(exporter.state.message.contains("Try again"))
        canRender = true
        exporter.start(.save, snapshot: makeSnapshot(), isCurrent: { true })
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(exporter.state, .failed(.file))
        canEncode = true
        exporter.start(.save, snapshot: makeSnapshot(), isCurrent: { true })
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(exporter.state, .succeeded)
        XCTAssertEqual(saves, 1)
    }

    func testPhotosOutcomesNeverClaimSuccessForDenialRestrictionOrWriteFailure() async {
        let cases: [(SharePhotoSaveResult, BodyScoreShareState)] = [
            (.denied, .failed(.photosDenied)), (.restricted, .failed(.photosRestricted)),
            (.failed, .failed(.photosWrite)), (.cancelled, .cancelled), (.saved, .succeeded)
        ]
        for (result, expected) in cases {
            let exporter = makeExporter(save: { _, _ in result })
            exporter.start(.save, snapshot: makeSnapshot(), isCurrent: { true })
            await waitUntil { !exporter.isBusy }
            XCTAssertEqual(exporter.state, expected)
            XCTAssertFalse(exporter.state.message.isEmpty)
        }
    }

    func testShareCompletionCancellationFailureAndStaleCallbacks() async throws {
        for outcome in [BodyScoreShareState.cancelled, .succeeded, .failed(.systemShare)] {
            var removed = 0
            let exporter = makeExporter(remove: { _ in removed += 1 })
            exporter.start(.share, snapshot: makeSnapshot(), isCurrent: { true })
            await waitUntil { exporter.presentation != nil }
            let presentation = try XCTUnwrap(exporter.presentation)
            XCTAssertEqual(exporter.state, .sharing)
            exporter.hideSystemShare()
            XCTAssertEqual(exporter.state, .sharing, "A dismiss binding must not preempt the activity's receipt")
            XCTAssertTrue(exporter.isBusy)
            exporter.completeShare(id: UUID(), completed: true)
            XCTAssertEqual(exporter.state, .sharing)
            exporter.completeShare(id: presentation.id, completed: outcome == .succeeded,
                                   failed: outcome == .failed(.systemShare))
            exporter.completeShare(id: presentation.id, completed: true)
            await waitUntil { !exporter.isBusy }
            XCTAssertEqual(exporter.state, outcome)
            XCTAssertEqual(removed, 1)
            XCTAssertNil(exporter.presentation)
        }
    }

    func testPresentedShareCannotReportSuccessAfterOwnershipChanges() async throws {
        var owns = true
        var removals = 0
        let exporter = makeExporter(remove: { _ in removals += 1 })
        exporter.start(.share, snapshot: makeSnapshot(), isCurrent: { owns })
        await waitUntil { exporter.presentation != nil }
        let presentation = try XCTUnwrap(exporter.presentation)
        owns = false
        exporter.completeShare(id: presentation.id, completed: true)
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(exporter.state, .cancelled)
        XCTAssertEqual(removals, 1)
        XCTAssertNil(exporter.presentation)
    }

    func testPhotoAdapterRechecksOwnershipAfterPermissionAndWaitsForWriteResult() async {
        let barrier = Barrier()
        var owns = true
        var writes = 0
        let task = Task {
            await LivePhotoLibraryAdapter.saveShareCard(whileOwned: { owns }, authorize: {
                await barrier.wait()
                return .authorized
            }, write: { writes += 1; return true })
        }
        await waitUntil { barrier.continuation != nil }
        owns = false
        barrier.resume()
        let cancelled = await task.value
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertEqual(writes, 0)
        for status in [AppAuthorizationState.denied, .restricted] {
            let result = await LivePhotoLibraryAdapter.saveShareCard(
                whileOwned: { true }, authorize: { status }, write: { writes += 1; return true })
            XCTAssertEqual(result, status == .denied ? .denied : .restricted)
        }
        XCTAssertEqual(writes, 0)
        let failed = await LivePhotoLibraryAdapter.saveShareCard(
            whileOwned: { true }, authorize: { .authorized }, write: { false })
        XCTAssertEqual(failed, .failed)
        let writeBarrier = Barrier()
        var completed = false
        let pendingWrite = Task {
            let result = await LivePhotoLibraryAdapter.saveShareCard(
                whileOwned: { true }, authorize: { .authorized }, write: { await writeBarrier.wait(); return true })
            completed = true
            return result
        }
        await waitUntil { writeBarrier.continuation != nil }
        XCTAssertFalse(completed)
        writeBarrier.resume()
        let saved = await pendingWrite.value
        XCTAssertEqual(saved, .saved)
        XCTAssertTrue(completed)
    }

    func testFreshExportsUseNewPayloadAndOptionsInsteadOfSavedPixels() async {
        var captured: [BodyScoreShareSnapshot] = []
        let exporter = makeExporter(render: { snapshot in captured.append(snapshot); return UIImage() })
        var snapshot = makeSnapshot()
        exporter.start(.save, snapshot: snapshot, isCurrent: { true })
        await waitUntil { !exporter.isBusy }
        snapshot = makeSnapshot(score: "91")
        exporter.reconcile(snapshot)
        exporter.start(.save, snapshot: snapshot, isCurrent: { true })
        await waitUntil { !exporter.isBusy }
        var options = BodyScoreShareOptions()
        options.includeWeight = true
        snapshot = makeSnapshot(score: "91", aspect: .square, options: options)
        exporter.reconcile(snapshot)
        exporter.start(.save, snapshot: snapshot, isCurrent: { true })
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(captured.count, 3)
        XCTAssertEqual(captured.map { $0.payload.scoreText }, ["82", "91", "91"])
        XCTAssertEqual(captured.last, snapshot)
        XCTAssertFalse(captured[0].options.includeWeight)
        XCTAssertTrue(captured[2].options.includeWeight)
    }

    func testPreparationDropsPrivatePhotoAndBoundsOptedInImageThenCleansRealFile() async throws {
        let source = UIGraphicsImageRenderer(size: CGSize(width: 2_000, height: 3_000)).image { _ in
            UIColor.red.setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: 2_000, height: 3_000))
        }
        var snapshot = makeSnapshot()
        var payload = snapshot.payload
        payload.photoImage = source
        snapshot = BodyScoreShareSnapshot(payload: payload, aspect: .portrait, options: .init())
        let worker = BodyScoreShareImageWorker.shared
        let privateSnapshot = try await worker.prepare(snapshot)
        XCTAssertNil(privateSnapshot.payload.photoImage)
        var options = BodyScoreShareOptions()
        options.includeVisual = true
        let publicSnapshot = try await worker.prepare(.init(payload: payload, aspect: .portrait, options: options))
        let photo = try XCTUnwrap(publicSnapshot.payload.photoImage)
        XCTAssertLessThanOrEqual(photo.size.width * photo.scale, snapshot.aspect.pixelSize.width)
        XCTAssertLessThanOrEqual(photo.size.height * photo.scale, snapshot.aspect.pixelSize.height)
        let url = try await worker.encode(photo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        await worker.remove(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testProductionPipelineExportsRefreshedMetricWithoutPreviouslyEnabledPrivateSource() async throws {
        var pngs: [Data] = []
        let exporter = BodyScoreShareExport(save: { url, _ in
            do { pngs.append(try Data(contentsOf: url)); return .saved } catch { return .failed }
        })
        var options = BodyScoreShareOptions(selectedMetric: .steps)
        options.includeProvenance = true
        let first = try metricSnapshot(value: "7544", options: options)
        exporter.start(.save, snapshot: first, isCurrent: { true })
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(exporter.state, .succeeded)
        options.includeProvenance = false
        let second = try metricSnapshot(value: "9863", options: options)
        exporter.reconcile(second)
        exporter.start(.save, snapshot: second, isCurrent: { true })
        await waitUntil { !exporter.isBusy }
        XCTAssertEqual(exporter.state, .succeeded)
        XCTAssertEqual(pngs.count, 2)
        guard pngs.count == 2 else { return }
        let before = try recognizedText(pngs[0])
        let after = try recognizedText(pngs[1])
        XCTAssertTrue(before.contains("7544"))
        XCTAssertTrue(before.contains("privatesource"))
        XCTAssertTrue(after.contains("9863"))
        XCTAssertFalse(after.contains("7544"))
        XCTAssertFalse(after.contains("privatesource"))
        XCTAssertFalse(after.contains("9917"))
    }

    func testCancellationReleasesRenderedBufferAfterDelayedEncoderDrains() async {
        let barrier = Barrier()
        weak var rendered: UIImage?
        let exporter = makeExporter(render: { _ in
            let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { _ in
                UIColor.red.setFill()
                UIRectFill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
            rendered = image
            return image
        }, encode: { _ in
            await barrier.wait()
            return URL(fileURLWithPath: "/tmp/synthetic-share.png")
        })
        exporter.start(.share, snapshot: makeSnapshot(), isCurrent: { true })
        await waitUntil { barrier.continuation != nil }
        XCTAssertNotNil(rendered)
        exporter.invalidate()
        barrier.resume()
        await waitUntil { !exporter.isBusy }
        await waitUntil { rendered == nil }
        XCTAssertNil(rendered)
    }

    func testFingerprintCoversPayloadPhotoFormatEveryOptionOwnerAndRendererRevision() throws {
        let base = makeSnapshot()
        var variants = [makeSnapshot(score: "91"), makeSnapshot(aspect: .story)]
        let paths: [WritableKeyPath<BodyScoreShareOptions, Bool>] = [
            \.includeObservation, \.includeRange, \.includeTrend, \.includeProvenance,
            \.includeWeight, \.includeBodyFat, \.includeFFMI, \.includeVisual
        ]
        for path in paths {
            var options = base.options
            options[keyPath: path].toggle()
            variants.append(makeSnapshot(options: options))
        }
        var payload = base.payload
        payload.photoImage = UIImage()
        variants.append(.init(payload: payload, aspect: base.aspect, options: base.options))
        payload = base.payload
        payload.preferredMetric = .steps
        variants.append(.init(payload: payload, aspect: base.aspect, options: base.options))
        payload.accountSession = .init(subject: "synthetic", generation: 1)
        variants.append(.init(payload: payload, aspect: base.aspect, options: base.options))
        var revision = base
        revision.rendererRevision += 1
        variants.append(revision)
        variants.append(try metricSnapshot(value: "7544", options: .init(selectedMetric: .steps)))
        XCTAssertEqual(base.fingerprint, makeSnapshot().fingerprint)
        for variant in variants { XCTAssertNotEqual(base.fingerprint, variant.fingerprint) }
    }

    private func metricSnapshot(value: String, options: BodyScoreShareOptions) throws -> BodyScoreShareSnapshot {
        let steps = ContextualMetricSnapshot(kind: .steps, value: value, unit: "steps", observation: "",
                                             range: "", trend: nil, provenance: "PrivateSource")
        let weight = ContextualMetricSnapshot(kind: .weight, value: "991.7", unit: "kg", observation: "",
                                              range: "", trend: nil, provenance: nil)
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual([steps, weight], selected: .steps))
        return .init(payload: payload, aspect: .portrait, options: options)
    }

    private func recognizedText(_ png: Data) throws -> String {
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "synthetic-share-export"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            .joined().lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func makeExporter(
        prepare: @escaping (BodyScoreShareSnapshot) async throws -> BodyScoreShareSnapshot = { $0 },
        render: @escaping @MainActor (BodyScoreShareSnapshot) -> UIImage? = { _ in UIImage() },
        encode: @escaping (UIImage) async throws -> URL = { _ in URL(fileURLWithPath: "/tmp/synthetic-share.png") },
        remove: @escaping (URL) async -> Void = { _ in },
        save: @escaping BodyScoreShareExport.Save = { _, _ in .saved }
    ) -> BodyScoreShareExport {
        BodyScoreShareExport(prepare: prepare, render: render, encode: encode, remove: remove, save: save)
    }

    private func makeSnapshot(
        score: String = "82", aspect: BodyScoreShareAspect = .portrait, options: BodyScoreShareOptions = .init()
    ) -> BodyScoreShareSnapshot {
        .init(payload: .init(score: Int(score) ?? 0, scoreText: score, tagline: "Synthetic fixture",
                             ffmiValue: "21.8", ffmiCaption: "FFMI", bodyFatValue: "16.4", bodyFatCaption: "%",
                             weightValue: "181.0", weightCaption: "lb", deltaText: nil, bodyFatPercentage: 16.4,
                             gender: "male", photoImage: nil), aspect: aspect, options: options)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2_000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Export did not reach the expected state", file: file, line: line)
    }
}
