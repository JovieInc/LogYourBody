//
//  PersonalBodyEstimateTests.swift
//  LogYourBodyTests
//
//  Fixtures use ids and unit quantities. They contain no photo bytes.
//

import XCTest
@testable import LogYourBody

@MainActor
final class PersonalBodyEstimateTests: XCTestCase {
    private let identity = PersonalBodyIdentity(accountId: "account-a", bodyId: "account-a.body", frame: 0.42)
    private let prior = PersonalBodyShape(adiposity: 0.5, muscularity: 0.25, frame: 0.1, depth: 0.5)

    func testProtocolExplainsTheBenefitAndMakesNoCompositionClaim() {
        XCTAssertEqual(PersonalBodyEstimate.protocolId, "lyb.capture.front-side.v1")
        XCTAssertEqual(PersonalBodyEstimate.modelId, "lyb.wireframe.torso")
        XCTAssertEqual(PersonalBodyEstimate.topologyId, "lyb.wireframe.torso.v1")
        XCTAssertTrue(PersonalBodyEstimate.benefitCopy.contains("adjust the personal outline for this date"))
        XCTAssertTrue(PersonalBodyEstimate.benefitCopy.contains("does not measure body fat"))
        let display = PersonalBodyEstimate.display(
            for: "2026-11-01", snapshots: [], activeTopology: PersonalBodyEstimate.topologyId
        )
        XCTAssertFalse(display.claimsBodyFat)
        XCTAssertFalse(display.claimsWeeklyChange)
        XCTAssertTrue(PersonalBodyPolicy.isEnabled { _ in false })
        XCTAssertFalse(PersonalBodyPolicy.isEnabled { $0 == PersonalBodyPolicy.killSwitchKey })
    }

    func testOneTwoAndManyViewsIgnoreDiaryAndOldDexa() throws {
        let front = try XCTUnwrap(PersonalBodyEstimate.fitShape(
            captures: [capture()], identity: identity, prior: prior
        ))
        XCTAssertEqual(front.supported, ["torsoWidth"])
        XCTAssertTrue(front.inferred.contains("torsoDepth"))
        XCTAssertEqual(front.shape.frame, 0.42, accuracy: 1e-9)
        XCTAssertEqual(front.shape.muscularity, 0.25, accuracy: 1e-9)
        XCTAssertEqual(front.shape.adiposity, blended(0.5, 0.8), accuracy: 1e-9)

        let pair = try XCTUnwrap(PersonalBodyEstimate.fitShape(
            captures: [capture(), capture(id: "side", photoId: "photo-side", view: .side, torsoWidth: nil, torsoDepth: 0.2)],
            identity: identity,
            prior: prior
        ))
        XCTAssertEqual(pair.supported, ["torsoWidth", "torsoDepth"])
        XCTAssertEqual(pair.shape.depth, blended(0.5, 0.2), accuracy: 1e-9)

        let many = try XCTUnwrap(PersonalBodyEstimate.fitShape(
            captures: [
                capture(id: "f1", torsoWidth: 0.2),
                capture(id: "f2", torsoWidth: 0.4),
                capture(id: "f3", torsoWidth: 0.9),
                capture(id: "back", photoId: "photo-back", view: .back, torsoWidth: nil)
            ],
            identity: identity,
            prior: prior
        ))
        XCTAssertEqual(many.shape.adiposity, blended(0.5, 0.4), accuracy: 1e-9)
        XCTAssertFalse(many.captureIds.contains("back"))

        let dated = capture(id: "other-day", effectiveDate: "2026-11-02", torsoWidth: 0.1)
        let grouped = try XCTUnwrap(PersonalBodyEstimate.fitShape(
            captures: [capture(), dated], identity: identity, prior: prior
        ))
        XCTAssertEqual(grouped.shape.adiposity, front.shape.adiposity, accuracy: 1e-9)

        let dexa = PersonalBodyEstimate.step(
            existing: nil,
            request: request(captures: [capture(dexaBodyFat: 40, dexaDate: "2026-11-01")])
        )
        let encoded = try JSONEncoder().encode(XCTUnwrap(dexa.snapshot))
        let snapshotText = String(bytes: encoded, encoding: .utf8)
        XCTAssertFalse(snapshotText?.contains("40") ?? false)
        XCTAssertEqual(try XCTUnwrap(dexa.snapshot).shape.adiposity, front.shape.adiposity, accuracy: 1e-9)
        XCTAssertFalse(try XCTUnwrap(dexa.snapshot).claimsBodyFat)

        let diary = PersonalBodyEstimate.fitShape(
            captures: [capture(id: "selfie", sessionId: nil, view: .diary, torsoWidth: 0.99)],
            identity: identity,
            prior: prior
        )
        XCTAssertNil(diary)
    }

    func testPoorMissingOccludedAndChangedPoseStayAtThePrior() throws {
        let side = capture(id: "side", photoId: "photo-side", view: .side, torsoWidth: nil, torsoDepth: 0.1)
        for quality in [PersonalBodyCaptureQuality.poor, .occluded, .poseChanged, .missing] {
            let ignored = capture(
                id: side.id, photoId: side.photoId, view: .side, quality: quality, torsoWidth: nil, torsoDepth: 0.1
            )
            let fitted = try XCTUnwrap(PersonalBodyEstimate.fitShape(
                captures: [capture(), ignored], identity: identity, prior: prior
            ))
            XCTAssertEqual(fitted.supported, ["torsoWidth"])
            XCTAssertEqual(fitted.shape.depth, prior.depth, accuracy: 1e-9)
        }
        XCTAssertEqual(PersonalBodyEstimate.classifyPose(view: .front, shoulderSpan: 0.04, profileDepth: nil), .poseChanged)
        XCTAssertEqual(PersonalBodyEstimate.classifyPose(view: .front, shoulderSpan: nil, profileDepth: nil), .missing)
        XCTAssertEqual(PersonalBodyEstimate.classifyPose(view: .side, shoulderSpan: 0.5, profileDepth: 0.2), .poseChanged)
        XCTAssertEqual(PersonalBodyEstimate.classifyPose(view: .side, shoulderSpan: 0.1, profileDepth: 0.2), .supported)
    }

    func testExternalFailureLeavesThePhotoJourneyAndOnDeviceWorksOffline() {
        let offline = PersonalBodyEstimate.step(existing: nil, request: request(online: false))
        XCTAssertEqual(offline.journey, "estimate")
        XCTAssertNotNil(offline.snapshot)

        let denied = PersonalBodyEstimate.step(
            existing: nil,
            request: request(route: .external, consentGranted: false, providerAvailable: true)
        )
        XCTAssertEqual(denied.job.failure, Optional("denied"))
        XCTAssertNil(denied.snapshot)
        XCTAssertEqual(denied.journey, "photo")

        let unavailable = PersonalBodyEstimate.step(
            existing: nil,
            request: request(online: false, route: .external, consentGranted: true)
        )
        XCTAssertEqual(unavailable.job.failure, Optional("provider-unavailable"))
        XCTAssertNil(unavailable.snapshot)

        let refused = PersonalBodyEstimate.step(
            existing: nil,
            request: request(route: .external, consentGranted: true, providerAvailable: true)
        )
        XCTAssertEqual(refused.job.failure, Optional("refused-by-policy"))
        XCTAssertNil(refused.snapshot)
        XCTAssertFalse(refused.job.failure?.contains("http") ?? true)
    }

    func testRetryCancelAndTimeoutStayBounded() {
        let first = PersonalBodyEstimate.step(existing: nil, request: request())
        XCTAssertEqual(first.job.status, "settled")
        let again = PersonalBodyEstimate.step(existing: first.job, request: request())
        XCTAssertEqual(again.job, first.job)
        XCTAssertNil(again.snapshot)
        XCTAssertEqual(again.journey, "estimate")

        let timeout = request(now: 9, deadline: 1)
        var timed = PersonalBodyEstimate.step(existing: nil, request: timeout)
        XCTAssertEqual(timed.job.status, "timedOut")
        XCTAssertNil(timed.snapshot)
        timed = PersonalBodyEstimate.step(existing: timed.job, request: timeout)
        timed = PersonalBodyEstimate.step(existing: timed.job, request: timeout)
        XCTAssertEqual(timed.job.attempts, 3)
        XCTAssertEqual(PersonalBodyEstimate.step(existing: timed.job, request: timeout).job, timed.job)

        let canceled = PersonalBodyEstimate.step(existing: nil, request: request(canceled: true))
        XCTAssertEqual(canceled.job.status, "canceled")
        XCTAssertNil(canceled.snapshot)
        let repeated = PersonalBodyEstimate.step(existing: canceled.job, request: request(canceled: true))
        XCTAssertEqual(repeated.job, canceled.job)
    }

    func testDeletionAndAccountSwitchKeepTheOtherOutline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("personal-body-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PersonalBodyEstimateStore(root: root)

        let saved = await store.record(capture(), identity: identity, now: 1_000, deadline: 5_000)
        XCTAssertEqual(saved.journey, "estimate")
        let visible = await store.index(accountId: identity.accountId, dates: ["2026-11-01"])
        XCTAssertEqual(visible.displays["2026-11-01"]?.kind, Optional("settled"))

        await store.forget(accountId: identity.accountId, photoId: "photo-front")
        let forgotten = await store.index(accountId: identity.accountId, dates: ["2026-11-01"])
        XCTAssertNotEqual(forgotten.displays["2026-11-01"]?.kind, Optional("settled"))

        let other = PersonalBodyIdentity(accountId: "account-b", bodyId: "account-b.body", frame: 0.42)
        _ = await store.record(
            capture(accountId: "account-b"),
            identity: other,
            now: 1_000,
            deadline: 5_000
        )
        await store.forgetAccount(identity.accountId)
        let remaining = await store.index(accountId: other.accountId, dates: ["2026-11-01"])
        XCTAssertEqual(remaining.displays["2026-11-01"]?.kind, Optional("settled"))
        let removed = root.appendingPathComponent("account-a.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: removed.path))
        let kept = try Data(contentsOf: root.appendingPathComponent("account-b.json"))
        let keptText = String(bytes: kept, encoding: .utf8)
        XCTAssertFalse(keptText?.contains("jpeg") ?? false)
    }

    func testModelUpdateIsolatesAndSameTopologyDatesBlend() throws {
        let archive = PersonalBodyEstimate.apply(archive: .empty(identity.accountId), existing: nil, request: request())
        let later = PersonalBodyEstimate.apply(
            archive: archive,
            existing: nil,
            request: request(captures: [
                capture(id: "later", photoId: "photo-later", effectiveDate: "2026-11-05", torsoWidth: 0.2)
            ])
        )
        let settled = PersonalBodyEstimate.display(
            for: "2026-11-01", snapshots: later.snapshots, activeTopology: PersonalBodyEstimate.topologyId
        )
        XCTAssertEqual(settled.kind, "settled")
        XCTAssertEqual(settled.label, "Saved date")
        let between = PersonalBodyEstimate.display(
            for: "2026-11-03", snapshots: later.snapshots, activeTopology: PersonalBodyEstimate.topologyId
        )
        XCTAssertEqual(between.kind, "transitional")
        XCTAssertEqual(between.label, "Moving between saved dates")
        XCTAssertFalse(between.claimsBodyFat)
        XCTAssertFalse(between.claimsWeeklyChange)
        XCTAssertEqual(try XCTUnwrap(between.shape).frame, 0.42, accuracy: 1e-9)

        let shifted = PersonalBodyIdentity(accountId: identity.accountId, bodyId: identity.bodyId, frame: 0.9)
        let mismatch = PersonalBodyEstimate.apply(
            archive: archive,
            existing: nil,
            request: request(
                captures: [capture(id: "later", photoId: "photo-later", effectiveDate: "2026-11-05", torsoWidth: 0.2)],
                identity: shifted
            )
        )
        let blocked = PersonalBodyEstimate.display(
            for: "2026-11-03", snapshots: mismatch.snapshots, activeTopology: PersonalBodyEstimate.topologyId
        )
        XCTAssertEqual(blocked.kind, "fallback")
        XCTAssertNil(blocked.shape)

        var updated = later.snapshots
        updated[0].topologyId = "lyb.wireframe.torso.v2"
        let isolated = PersonalBodyEstimate.display(
            for: "2026-11-01", snapshots: updated, activeTopology: PersonalBodyEstimate.topologyId
        )
        XCTAssertTrue(isolated.isolated)
        XCTAssertNil(isolated.shape)
        XCTAssertEqual(isolated.label, "Saved outline uses another model")
        XCTAssertEqual(
            PersonalBodyEstimate.morph(left: PersonalBodyEstimate.topologyId, right: "lyb.wireframe.torso.v2"),
            "cross-topology"
        )
        XCTAssertNil(PersonalBodyEstimate.morph(
            left: PersonalBodyEstimate.topologyId, right: PersonalBodyEstimate.topologyId
        ))
    }

    func testScrubAndRotateDoNotFitAndKeepOneViewpoint() {
        let archive = PersonalBodyEstimate.apply(archive: .empty(identity.accountId), existing: nil, request: request())
        let jobs = archive.jobs
        for day in 1...20 {
            let key = String(format: "2026-11-%02d", day)
            _ = PersonalBodyEstimate.display(
                for: key, snapshots: archive.snapshots, activeTopology: PersonalBodyEstimate.topologyId
            )
            _ = PersonalBodyEstimate.applyDrag(yaw: 0.2, dx: Double(day), dy: 1)
        }
        XCTAssertEqual(archive.jobs, jobs)
        XCTAssertEqual(PersonalBodyEstimate.gestureOwner(dx: 40, dy: 3), "timeline")
        XCTAssertEqual(PersonalBodyEstimate.gestureOwner(dx: 1, dy: 30), "rotate")
        XCTAssertEqual(PersonalBodyEstimate.applyDrag(yaw: 0.2, dx: 40, dy: 3), 0.2, accuracy: 1e-9)
        XCTAssertEqual(PersonalBodyEstimate.applyDrag(yaw: 0, dx: 1, dy: 30), 0.24, accuracy: 1e-9)
        XCTAssertEqual(PersonalBodyEstimate.yaw(for: "front"), 0, accuracy: 1e-9)
        XCTAssertEqual(PersonalBodyEstimate.yaw(for: "reset"), 0, accuracy: 1e-9)
        XCTAssertEqual(PersonalBodyEstimate.yaw(for: "side"), Double.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(PersonalBodyEstimate.depthScale(0), 0.85, accuracy: 1e-9)
        XCTAssertEqual(PersonalBodyEstimate.depthScale(1), 1.15, accuracy: 1e-9)
        let pair = PersonalBodyEstimate.pairedViewpoints(PersonalBodyViewpoint(yaw: 0.4, scale: 1))
        XCTAssertEqual(pair.0, pair.1)
    }

    private func blended(_ prior: Double, _ observed: Double) -> Double {
        prior + (observed - prior) * PersonalBodyEstimate.fitBlend
    }

    private func capture(
        id: String = "capture-front",
        accountId: String = "account-a",
        photoId: String = "photo-front",
        sessionId: String? = "session-1",
        view: PersonalBodyViewKind = .front,
        effectiveDate: String = "2026-11-01",
        quality: PersonalBodyCaptureQuality = .supported,
        torsoWidth: Double? = 0.8,
        torsoDepth: Double? = nil,
        dexaBodyFat: Double? = nil,
        dexaDate: String? = nil
    ) -> PersonalBodyCapture {
        PersonalBodyCapture(
            id: id, accountId: accountId, photoId: photoId, sessionId: sessionId, view: view,
            effectiveDate: effectiveDate, quality: quality, torsoWidth: torsoWidth, torsoDepth: torsoDepth,
            dexaBodyFat: dexaBodyFat, dexaDate: dexaDate
        )
    }

    private func request(
        captures: [PersonalBodyCapture]? = nil,
        identity: PersonalBodyIdentity? = nil,
        prior: PersonalBodyShape? = nil,
        now: Int = 1_000,
        deadline: Int = 5_000,
        online: Bool = true,
        route: PersonalBodyRoute = .onDevice,
        consentGranted: Bool = false,
        providerAvailable: Bool = false,
        canceled: Bool = false,
        usesPrior: Bool = true
    ) -> PersonalBodyFitRequest {
        let owner = identity ?? self.identity
        return PersonalBodyFitRequest(
            now: now, deadline: deadline, online: online, route: route, consentGranted: consentGranted,
            providerAvailable: providerAvailable, canceled: canceled, identity: owner,
            captures: captures ?? [capture()],
            prior: usesPrior ? (prior ?? self.prior) : nil,
            activeTopology: PersonalBodyEstimate.topologyId
        )
    }
}
