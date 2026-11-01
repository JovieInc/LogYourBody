//
//  PersonalBodyEngineTests.swift
//  LogYourBodyTests
//
//  The personal body decision stays off the weekly photo loop.
//

import XCTest
@testable import LogYourBody

final class PersonalBodyEngineTests: XCTestCase {
    func testDecisionKeepsPersonalizationOffThePhotoLoop() throws {
        let decision = try loadDecision()
        XCTAssertEqual(decision.issue, "LYB-316")
        XCTAssertEqual(decision.selectedEngineId, "lyb.personal.parametric.wireframe.v1")
        XCTAssertEqual(decision.fallbackEngineId, "lyb.wireframe.torso")
        XCTAssertEqual(decision.topologyId, "lyb.wireframe.torso.v1")
        XCTAssertEqual(decision.releaseStage, "disabled")
        XCTAssertFalse(decision.personalizedProduction)
        XCTAssertFalse(decision.addsCaptureStep)
        XCTAssertFalse(decision.mapsToBodyFat)
        XCTAssertFalse(decision.mapsToDexa)
        XCTAssertEqual(decision.pose, "neutral-identity")
        XCTAssertEqual(decision.clothing, "unsupported")
        XCTAssertEqual(decision.candidates.map(\.id), ["bodygram", "parametric-wireframe", "digs-avatar"])
        XCTAssertEqual(decision.candidates.map(\.executed), [false, true, false])
        XCTAssertFalse(decision.unsupported.omniFlashVerifiedMeshApi)
        XCTAssertFalse(decision.unsupported.gnmPublicBody)
        XCTAssertFalse(decision.unsupported.mojuloIsBodyReconstruction)
        XCTAssertFalse(decision.unsupported.meshlibTimingIsReconstruction)
        XCTAssertFalse(decision.unsupported.exactRememberedDemoConfirmed)

        XCTAssertEqual(PersonalBodyEngine.releaseDescriptor.stage, .disabled)
        XCTAssertFalse(PersonalBodyEngine.isPersonalizationEnabled())

        let drawing = PersonalBodyEngine.appliedIllustration(
            storedAdiposity: 0.25,
            storedMuscularity: 0.5,
            storedFrame: 0.75,
            photoByteCount: 0,
            decision: decision
        )
        XCTAssertFalse(drawing.personalized)
        XCTAssertEqual(drawing.engineId, decision.fallbackEngineId)
        XCTAssertEqual(drawing.adiposity, 0.25)
        XCTAssertEqual(drawing.muscularity, 0.5)
        XCTAssertEqual(drawing.frame, 0.75)
    }

    func testPhotoBytesAndMixedBodyStatesStayOnTheFallback() throws {
        let decision = try loadDecision()
        let graduated = PersonalBodyDecision(
            issue: decision.issue,
            selectedEngineId: decision.selectedEngineId,
            fallbackEngineId: decision.fallbackEngineId,
            personalizedProduction: true,
            addsCaptureStep: decision.addsCaptureStep,
            mapsToBodyFat: decision.mapsToBodyFat,
            mapsToDexa: decision.mapsToDexa,
            topologyId: decision.topologyId,
            releaseStage: decision.releaseStage,
            flagKey: decision.flagKey,
            killSwitchKey: decision.killSwitchKey,
            pose: decision.pose,
            crop: decision.crop,
            clothing: decision.clothing,
            candidates: decision.candidates,
            unsupported: decision.unsupported
        )
        let photos = PersonalBodyEngine.appliedIllustration(
            storedAdiposity: 0.2,
            storedMuscularity: 0.2,
            storedFrame: 0.2,
            photoByteCount: 32,
            decision: graduated,
            personalizationEnabled: true
        )
        XCTAssertFalse(photos.personalized)
        XCTAssertEqual(photos.engineId, decision.fallbackEngineId)

        let mixed = PersonalBodyEngine.appliedIllustration(
            storedAdiposity: 0.2,
            storedMuscularity: 0.2,
            storedFrame: 0.2,
            bodyStates: ["synthetic-session-a", "synthetic-session-b"],
            decision: graduated,
            personalizationEnabled: true
        )
        XCTAssertFalse(mixed.personalized)
        XCTAssertEqual(mixed.adiposity, 0.2)

        let selected = PersonalBodyEngine.appliedIllustration(
            storedAdiposity: 0.2,
            storedMuscularity: 0.3,
            storedFrame: 0.4,
            decision: graduated,
            personalizationEnabled: true
        )
        XCTAssertTrue(selected.personalized)
        XCTAssertEqual(selected.engineId, decision.selectedEngineId)
        XCTAssertEqual(selected.adiposity, 0.2)
        XCTAssertEqual(selected.muscularity, 0.3)
        XCTAssertEqual(selected.frame, 0.4)
    }

    private func loadDecision() throws -> PersonalBodyDecision {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LogYourBody")
            .appendingPathComponent("Resources")
            .appendingPathComponent("PersonalBodyEngine.json")
        let decision = try XCTUnwrap(PersonalBodyEngine.load(from: url))
        return decision
    }
}
