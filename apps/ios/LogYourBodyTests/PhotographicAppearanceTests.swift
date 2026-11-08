//
//  PhotographicAppearanceTests.swift
//  LogYourBodyTests
//
//  Fixtures use ids and unit tones. They contain no photo bytes.
//

import XCTest
@testable import LogYourBody

@MainActor
final class PhotographicAppearanceTests: XCTestCase {
    private let shape = PersonalBodyShape(adiposity: 0.42, muscularity: 0.31, frame: 0.58, depth: 0.47)

    func testProjectionKeepsTheAcceptedShapeAndMarksUnseenSurfaces() {
        let accepted = geometry()
        let front = sample()
        let original = front.samples
        let result = PhotographicAppearance.project(geometry: accepted, samples: [front], options: .precompute)
        guard case .asset(let asset) = result else {
            return XCTFail("Expected a cached projection")
        }
        XCTAssertEqual(asset.shape, shape)
        XCTAssertEqual(asset.geometryDrift, 0)
        XCTAssertEqual(asset.appearanceDrift, 0)
        XCTAssertEqual(front.samples, original)
        XCTAssertTrue(asset.texels.filter { $0.region == "front" }.allSatisfy { $0.provenance == "observed" })
        XCTAssertTrue(asset.texels.filter { $0.region == "back" }.allSatisfy { $0.provenance == "inferred" && $0.tone == nil })
        XCTAssertFalse(asset.claimsBodyFat)
        XCTAssertFalse(asset.claimsWeeklyChange)
        XCTAssertGreaterThan(PhotographicAppearance.coverage(asset), PhotographicAppearance.baselineCoverage)
        XCTAssertEqual(PhotographicAppearance.appearanceLabel(asset), "Observed front. Unseen surfaces stay unmarked.")
        let drift = PhotographicAppearance.quantifyDrift(corpus: [accepted], asset: asset)
        XCTAssertTrue(drift.matched)
        XCTAssertEqual(drift.geometryDrift, 0)
    }

    func testRefusalsKeepThePhotoAndDoNotRewriteIt() {
        let accepted = geometry()
        let front = sample()
        XCTAssertEqual(reason(PhotographicAppearance.project(
            geometry: accepted, samples: [front], options: options(representation: "turntable")
        )), "not-interactive")
        XCTAssertEqual(reason(PhotographicAppearance.project(
            geometry: accepted, samples: [front], options: options(requestedModel: "DiGS-Avatar")
        )), "license")
        XCTAssertEqual(reason(PhotographicAppearance.project(
            geometry: accepted, samples: [front], options: options(gesture: true)
        )), "gesture")
        XCTAssertEqual(reason(PhotographicAppearance.project(
            geometry: accepted, samples: [front], options: options(remoteRequested: true)
        )), "remote-regeneration")
        let refusal = PhotographicAppearance.replaceOriginal(original: front.samples, proposed: Array(repeating: 0.2, count: 8))
        XCTAssertFalse(refusal.ok)
        XCTAssertEqual(refusal.reason, "original-photo")
        let sealed = PhotographicAppearance.sealedShape(shape, proposed: PersonalBodyShape(
            adiposity: 0.1, muscularity: 0.95, frame: shape.frame, depth: shape.depth
        ))
        XCTAssertEqual(sealed.shape, shape)
        XCTAssertGreaterThan(sealed.rejectedDelta, 0)
        XCTAssertFalse(PhotographicAppearancePolicy.isEnabled { _ in false })
        XCTAssertTrue(PhotographicAppearancePolicy.isEnabled { $0 == PhotographicAppearancePolicy.flagKey })
        XCTAssertFalse(PhotographicAppearancePolicy.isEnabled { _ in true })
    }

    func testScrubAndComparisonDoNotInventWeeklyChange() throws {
        let earlier = try asset(project(geometry(), [sample()]))
        let laterShape = PersonalBodyShape(adiposity: 0.5, muscularity: shape.muscularity, frame: shape.frame, depth: shape.depth)
        let later = try asset(project(
            geometry(snapshotId: "snapshot-2", effectiveDate: "2026-11-08", captureDate: "2026-11-08", shape: laterShape),
            [sample(photoId: "photo-later", effectiveDate: "2026-11-08", captureDate: "2026-11-08", samples: tones(6))]
        ))
        let cache = [earlier, later]
        let found = PhotographicAppearance.lookup(
            date: "2026-11-08", cache: cache, topologyId: PhotographicAppearance.topologyId
        )
        XCTAssertEqual(found?.snapshotId, "snapshot-2")
        let missing = PhotographicAppearance.lookup(
            date: "2026-11-03", cache: cache, topologyId: PhotographicAppearance.topologyId
        )
        XCTAssertNil(missing)
        let read = PhotographicAppearance.readForGesture(cacheKey: later.cacheKey, cache: cache, remoteRequested: false)
        XCTAssertFalse(read.regenerated)
        XCTAssertEqual(read.asset?.id, later.id)
        let remote = PhotographicAppearance.readForGesture(
            cacheKey: later.cacheKey, cache: cache, remoteRequested: true
        )
        XCTAssertEqual(remote.reason, "remote-regeneration")
        let progress = PhotographicAppearance.progressDisplay(before: earlier, after: later, yaw: 0)
        XCTAssertNil(progress.bodyFatDelta)
        XCTAssertNil(progress.weeklyChange)
        XCTAssertFalse(progress.geometryChangedByAppearance)
        XCTAssertEqual(progress.label, "Appearance only. Not a weekly change.")
        XCTAssertEqual(PhotographicAppearance.motion(reduceMotion: true).duration, 0)
        XCTAssertFalse(PhotographicAppearance.motion(reduceMotion: false).autoSpin)
        let decision = PhotographicAppearance.promotionDecision(PhotographicAppearancePromotion(
            tier: "repeatable-on-device",
            baselineObservedCoverage: 0,
            observedCoverage: PhotographicAppearance.coverage(earlier),
            geometryDrift: 0,
            introducedBodyFatClaim: false,
            introducedWeeklyChange: false,
            truthfulProgress: true,
            rightsRecorded: true,
            lowEndDeviceEvidence: "source"
        ))
        XCTAssertFalse(decision.promoted)
        XCTAssertTrue(decision.reasons.contains("device-evidence"))
    }

    func testDerivedTextureDeletesWithThePhotoAndTheAccount() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("appearance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PhotographicAppearanceStore(root: root)
        let saved = await store.remember(sample(), geometry: geometry())
        guard case .asset = saved else { return XCTFail("Expected a stored projection") }
        let visible = await store.index(accountId: "account-a", dates: ["2026-11-01"])
        XCTAssertEqual(visible["2026-11-01"]?.observedRegions, ["front"])
        await store.forget(accountId: "account-a", photoId: "photo-front")
        let forgotten = await store.index(accountId: "account-a", dates: ["2026-11-01"])
        XCTAssertNil(forgotten["2026-11-01"])
        _ = await store.remember(
            sample(accountId: "account-b", photoId: "photo-b"),
            geometry: geometry(snapshotId: "snapshot-b", accountId: "account-b", bodyId: "account-b.body")
        )
        await store.forgetAccount("account-a")
        let remaining = await store.index(accountId: "account-b", dates: ["2026-11-01"])
        XCTAssertEqual(remaining["2026-11-01"]?.claimsBodyFat, false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("account-a.json").path))
    }

    private func tones(_ seed: Double) -> [Double] {
        (0..<8).map { (seed + Double($0)) / 20 }
    }

    private func geometry(
        snapshotId: String = "snapshot-1",
        accountId: String = "account-a",
        bodyId: String = "account-a.body",
        effectiveDate: String = "2026-11-01",
        captureDate: String = "2026-11-01",
        shape: PersonalBodyShape? = nil
    ) -> PhotographicAppearanceGeometry {
        PhotographicAppearanceGeometry(
            snapshotId: snapshotId,
            accountId: accountId,
            bodyId: bodyId,
            effectiveDate: effectiveDate,
            captureDate: captureDate,
            modelId: PhotographicAppearance.modelId,
            modelVersion: PhotographicAppearance.modelVersion,
            topologyId: PhotographicAppearance.topologyId,
            rigId: PhotographicAppearance.rigId,
            framingId: PhotographicAppearance.framingId,
            shape: shape ?? self.shape
        )
    }

    private func sample(
        accountId: String = "account-a",
        photoId: String = "photo-front",
        effectiveDate: String = "2026-11-01",
        captureDate: String = "2026-11-01",
        samples: [Double]? = nil
    ) -> PhotographicAppearanceSample {
        PhotographicAppearanceSample(
            accountId: accountId,
            photoId: photoId,
            view: "front",
            effectiveDate: effectiveDate,
            captureDate: captureDate,
            framingId: PhotographicAppearance.framingId,
            quality: "supported",
            samples: samples ?? tones(2),
            sourceDigest: "digest-\(photoId)"
        )
    }

    private func options(
        representation: String = "projection",
        requestedModel: String? = nil,
        gesture: Bool = false,
        remoteRequested: Bool = false
    ) -> PhotographicAppearanceOptions {
        PhotographicAppearanceOptions(
            representation: representation,
            computeAvailable: true,
            licenseOk: true,
            requestedModel: requestedModel,
            thermal: "nominal",
            lowEndDevice: false,
            reduceMotion: false,
            gesture: gesture,
            remoteRequested: remoteRequested,
            memoryLimitBytes: nil
        )
    }

    private func project(
        _ geometry: PhotographicAppearanceGeometry,
        _ samples: [PhotographicAppearanceSample]
    ) -> PhotographicAppearanceResult {
        PhotographicAppearance.project(geometry: geometry, samples: samples, options: .precompute)
    }

    private func asset(_ result: PhotographicAppearanceResult) throws -> PhotographicAppearanceAsset {
        guard case .asset(let asset) = result else {
            struct Missing: Error {}
            XCTFail("Expected an asset")
            throw Missing()
        }
        return asset
    }

    private func reason(_ result: PhotographicAppearanceResult) -> String? {
        guard case .fallback(let reason) = result else { return nil }
        return reason
    }
}
