import XCTest
@testable import LogYourBody

@MainActor
final class BodyVisualizationSnapshotTests: BodyVisualizationSnapshotFixtureCase {
    private let ownerId = "11111111-1111-4111-8111-111111111111"

    func testSyntheticFixturesCoverSparseDatesConflictsAndLineage() async throws {
        let harness = try makeHarness()
        let early = try await schedule(harness, request: dexRequest(at: day(0)))
        let later = try await schedule(harness, request: dexRequest(at: day(10)))
        let document = try await harness.ledger.document(accountId: account)
        XCTAssertEqual(document.snapshots.count, 2)
        let filledDay = document.snapshots.contains {
            VisualizationClock.millis($0.effectiveAt) == VisualizationClock.millis(day(5))
        }
        XCTAssertFalse(filledDay)
        XCTAssertEqual(early.snapshot.evidenceLinks.first { $0.id == "dexa-lean" }?.role, .dxaLeanTissue)
        XCTAssertEqual(early.snapshot.evidenceLinks.first { $0.id == "dexa-lean" }?.sourceDefinition, "bodyspec_dexa")
        XCTAssertFalse(early.snapshot.evidenceLinks.contains { $0.role == .skeletalMuscle && $0.id == "dexa-lean" })
        XCTAssertEqual(early.snapshot.evidenceLinks.first { $0.id == "dexa-lean" }?.rawObservationIds, ["raw-dexa"])
        XCTAssertTrue(early.snapshot.fitFlags.contains(.staleInputs))
        XCTAssertFalse(early.snapshot.shape.identifiesUnseenAnatomy)
        XCTAssertEqual(early.snapshot.shape.aggregateConfidence, 0.4)
        let persistedEarly = try persistedText(early.snapshot)
        XCTAssertFalse(persistedEarly.contains("164.5"))
        XCTAssertFalse(persistedEarly.contains("71.25"))
        XCTAssertEqual(later.snapshot.id == early.snapshot.id, false)

        let repeated = try await schedule(harness, request: dexRequest(at: day(0)))
        XCTAssertEqual(repeated.snapshot.id, early.snapshot.id)
        XCTAssertEqual(repeated.job.id, early.job.id)
        let storedCount = try await harness.ledger.snapshotCount(accountId: account)
        XCTAssertEqual(storedCount, 2)

        let conflict = try await schedule(harness, request: request(evidence: [
            evidence("height", role: .height, confidence: 0.4, magnitude: 164.5, unit: "cm"),
            evidence("weight-a", role: .weight, confidence: 0.5, conflictIds: ["weight-b"]),
            evidence("weight-b", role: .weight, confidence: 0.5, conflictIds: ["weight-a"]),
            evidence("fat", role: .bodyFat, confidence: 0.5)
        ]))
        XCTAssertEqual(conflict.snapshot.fitQuality, .conflictingInputs)
        XCTAssertEqual(conflict.snapshot.shape.weightEvidenceIds, ["weight-a", "weight-b"])
        let encoded = try persistedText(conflict.snapshot)
        XCTAssertFalse(encoded.contains("164.5"))
        XCTAssertFalse(encoded.contains("71.25"))
        XCTAssertFalse(encoded.contains("0.99"))
    }

    func testUnknownGeometryProviderClaimAndModelUpgradeStayDistinct() async throws {
        let harness = try makeHarness()
        let unknown = try await schedule(harness, request: request(
            evidence: baseEvidence(),
            representation: .personalizedInferredGeometry,
            provider: "fixture-provider",
            geometryKnown: false
        ))
        XCTAssertEqual(unknown.snapshot.fitQuality, .unknownGeometry)
        XCTAssertEqual(unknown.snapshot.anatomyClaim, .inferred)
        XCTAssertEqual(unknown.snapshot.providerSourceDefinition, "fixture-provider")
        XCTAssertFalse(BodyVisualizationConsumer.presentation(for: unknown.snapshot).personalReconstructionPermitted)

        let known = try await schedule(harness, request: request(
            evidence: baseEvidence(),
            representation: .personalizedInferredGeometry,
            provider: "fixture-provider",
            geometryKnown: true,
            model: model("v1")
        ))
        XCTAssertEqual(known.snapshot.anatomyClaim, .inferred)
        XCTAssertTrue(BodyVisualizationConsumer.presentation(for: known.snapshot).personalReconstructionPermitted)
        XCTAssertEqual(known.snapshot.evidenceLinks.first { $0.role == .weight }?.epistemic, .measured)

        let upgraded = try await schedule(harness, request: request(
            evidence: baseEvidence(),
            representation: .personalizedInferredGeometry,
            provider: "fixture-provider",
            geometryKnown: true,
            model: model("v2")
        ))
        XCTAssertFalse(BodyVisualizationConsumer.progressComparisonAllowed(known.snapshot, upgraded.snapshot))
        let stored = try await harness.ledger.document(accountId: account)
        XCTAssertEqual(stored.snapshots.first { $0.id == known.snapshot.id }?.shape, known.snapshot.shape)
        XCTAssertEqual(stored.snapshots.first { $0.id == known.snapshot.id }?.model, model("v1"))
        XCTAssertEqual(stored.frames.first?.calibrationVersion, "cal-1")
        XCTAssertEqual(stored.frames.first?.topologyId, "topology-a")

        let wireframe = try await schedule(harness, request: request(
            evidence: [],
            representation: .genericIllustration,
            geometryKnown: false,
            at: day(3)
        ))
        XCTAssertEqual(wireframe.snapshot.anatomyClaim, .illustration)
        XCTAssertTrue(BodyVisualizationConsumer.presentation(for: wireframe.snapshot).wireframePermitted)
        XCTAssertFalse(BodyVisualizationConsumer.presentation(for: wireframe.snapshot).personalReconstructionPermitted)
    }

    func testSideViewRefinesFrameWithoutRewritingEarlierShape() async throws {
        let harness = try makeHarness()
        let original = try await schedule(harness, request: request(
            evidence: baseEvidence(),
            captures: [VisualizationCaptureRef(id: "front-capture", viewpoint: "front")]
        ))
        let permit = permit(at: day(0))
        let frame = try await harness.ledger.refineFrame(
            accountId: account,
            capture: VisualizationCaptureRef(id: "side-capture", viewpoint: "side"),
            at: day(2),
            permit: permit
        )
        let stored = try await harness.ledger.document(accountId: account)
        let kept = try XCTUnwrap(stored.snapshots.first { $0.id == original.snapshot.id })
        XCTAssertEqual(frame.revision, 2)
        XCTAssertEqual(frame.refiningCaptureIds, ["side-capture"])
        XCTAssertEqual(kept.frameRevisionAtComputation, 1)
        XCTAssertEqual(kept.shape, original.snapshot.shape)
        XCTAssertEqual(kept.evidenceLinks, original.snapshot.evidenceLinks)

        var redo = request(evidence: baseEvidence(), at: day(0), model: model("v2"))
        redo.retrospectiveOf = original.snapshot.id
        let retrospective = try await schedule(harness, request: redo)
        XCTAssertEqual(retrospective.snapshot.frameRevisionAtComputation, 1)
        XCTAssertEqual(retrospective.snapshot.shape, original.snapshot.shape)
        let afterRefine = try await harness.ledger.document(accountId: account)
        XCTAssertEqual(afterRefine.frames.first?.revision, 2)
        XCTAssertEqual(afterRefine.snapshots.first { $0.id == original.snapshot.id }?.frameRevisionAtComputation, 1)
        XCTAssertEqual(afterRefine.snapshots.first { $0.id == original.snapshot.id }?.shape, original.snapshot.shape)
    }

    func testRetrospectiveModelAndInterpolationDoNotInventProgress() async throws {
        let harness = try makeHarness()
        let first = try await schedule(harness, request: request(evidence: baseEvidence(), at: day(0), model: model("v1")))
        let second = try await schedule(harness, request: request(evidence: baseEvidence(), at: day(4), model: model("v1")))
        XCTAssertTrue(BodyVisualizationConsumer.progressComparisonAllowed(first.snapshot, second.snapshot))
        var bridged = request(evidence: [], representation: .transitionalInterpolation, at: day(2))
        bridged.interpolationEndpointIds = [first.snapshot.id, second.snapshot.id]
        let bridge = try await schedule(harness, request: bridged)
        XCTAssertEqual(bridge.snapshot.representation, .transitionalInterpolation)
        XCTAssertEqual(bridge.snapshot.anatomyClaim, .interpolated)
        XCTAssertFalse(BodyVisualizationConsumer.progressComparisonAllowed(first.snapshot, bridge.snapshot))

        var mismatched = bridged
        mismatched.model = model("v2")
        mismatched.effectiveAt = day(6)
        do {
            _ = try await schedule(harness, request: mismatched)
            XCTFail("A model upgrade cannot bridge incompatible snapshots")
        } catch BodyVisualizationError.incompatibleInterpolation {
        } catch {
            XCTFail("unexpected \(error)")
        }

        var redo = request(evidence: baseEvidence(), at: day(0), model: model("v2"))
        redo.retrospectiveOf = first.snapshot.id
        let retrospective = try await schedule(harness, request: redo)
        XCTAssertEqual(retrospective.snapshot.retrospectiveOf, first.snapshot.id)
        XCTAssertFalse(retrospective.snapshot.asKnownThen)
        XCTAssertEqual(retrospective.snapshot.shape, first.snapshot.shape)
        XCTAssertEqual(retrospective.snapshot.frameRevisionAtComputation, first.snapshot.frameRevisionAtComputation)
        let kept = try await harness.ledger.document(accountId: account)
        XCTAssertTrue(kept.snapshots.contains { $0.id == first.snapshot.id && $0.asKnownThen && $0.model == model("v1") })
        XCTAssertFalse(BodyVisualizationConsumer.progressComparisonAllowed(first.snapshot, retrospective.snapshot))
    }

    func testFfmiIsLineageNotAnIndependentVoteAndTissuesStayDistinct() async throws {
        let harness = try makeHarness()
        var missing = baseEvidence()
        missing.append(evidence(
            "ffmi", role: .ffmi, kind: .estimate, epistemic: .derived, confidence: 0.99, lineageIds: ["ffm"]
        ))
        do {
            _ = try await schedule(harness, request: request(evidence: missing))
            XCTFail("FFMI without height lineage is an independent vote")
        } catch BodyVisualizationError.ffmiIndependentVote {
        } catch {
            XCTFail("unexpected \(error)")
        }

        var measured = baseEvidence()
        measured.append(evidence("ffmi-measured", role: .ffmi, epistemic: .measured, confidence: 0.99))
        do {
            _ = try await schedule(harness, request: request(evidence: measured, at: day(8)))
            XCTFail("A measured label cannot be applied to FFMI")
        } catch BodyVisualizationError.ffmiIndependentVote {
        } catch {
            XCTFail("unexpected \(error)")
        }

        var collided = baseEvidence()
        collided.append(evidence("ffm", role: .skeletalMuscle, confidence: 0.5))
        do {
            _ = try await schedule(harness, request: request(evidence: collided, at: day(9)))
            XCTFail("One id cannot be both fat-free mass and skeletal muscle")
        } catch BodyVisualizationError.tissueIdentityCollision {
        } catch {
            XCTFail("unexpected \(error)")
        }

        var linked = baseEvidence()
        linked.append(evidence("muscle", role: .skeletalMuscle, kind: .observation, source: "fixture-muscle", confidence: 0.42))
        linked.append(evidence(
            "ffmi", role: .ffmi, kind: .estimate, epistemic: .derived, confidence: 0.99,
            lineageIds: ["ffm", "height"]
        ))
        let snapshot = try await schedule(harness, request: request(evidence: linked, at: day(11))).snapshot
        XCTAssertEqual(snapshot.shape.ffmiEvidenceId, "ffmi")
        XCTAssertEqual(snapshot.shape.aggregateConfidence, 0.4)
        XCTAssertEqual(snapshot.evidenceLinks.first { $0.id == "ffm" }?.role, .fatFreeMass)
        XCTAssertEqual(snapshot.evidenceLinks.first { $0.id == "dexa-lean" }?.role, .dxaLeanTissue)
        XCTAssertEqual(snapshot.evidenceLinks.first { $0.id == "muscle" }?.role, .skeletalMuscle)
        XCTAssertEqual(snapshot.evidenceLinks.first { $0.id == "ffmi" }?.lineageIds.sorted(), ["ffm", "height"])
        let persisted = try persistedText(snapshot)
        XCTAssertFalse(persisted.contains("0.99"))
    }

    func testRetriesLateResponsesAndDeletionStayOnTheOriginalSession() async throws {
        let harness = try makeHarness()
        let scheduled = try await schedule(harness, request: request(
            evidence: baseEvidence(),
            representation: .personalizedInferredGeometry,
            geometryKnown: true
        ))
        let again = try await schedule(harness, request: request(
            evidence: baseEvidence(),
            representation: .personalizedInferredGeometry,
            geometryKnown: true
        ))
        XCTAssertEqual(again.job.id, scheduled.job.id)
        var regeneratedPermit = permit(at: day(0))
        regeneratedPermit.generation = 2
        try await harness.ledger.bind(regeneratedPermit)
        let regenerated = try await harness.ledger.schedule(
            request(
                evidence: baseEvidence(),
                representation: .personalizedInferredGeometry,
                geometryKnown: true
            ),
            permit: regeneratedPermit
        )
        XCTAssertEqual(regenerated.snapshot.id, scheduled.snapshot.id)
        XCTAssertNotEqual(regenerated.job.id, scheduled.job.id)
        let permit = permit(at: day(0))
        try await harness.ledger.bind(permit)
        let finished = try await harness.ledger.finish(jobId: scheduled.job.id, permit: permit)
        let retried = try await harness.ledger.finish(jobId: scheduled.job.id, permit: permit)
        guard case .attached(let job) = finished, case .idempotent(let same) = retried else {
            return XCTFail("retry should attach once")
        }
        XCTAssertEqual(job.id, same.id)
        let stored = try await harness.ledger.document(accountId: account)
        XCTAssertEqual(stored.assets.filter { $0.kind == .mesh }.count, 1)
        XCTAssertEqual(Set(stored.assets.map(\.kind)), Set([.mask, .mesh, .texture, .cache]))

        var moved = permit
        moved.effectiveAt = day(1)
        try await harness.ledger.bind(moved)
        let dated = try await harness.ledger.finish(jobId: scheduled.job.id, permit: permit)
        XCTAssertEqual(dated, .rejected(.dateChanged))

        var switched = permit
        switched.accountId = "other-account"
        switched.sessionId = "session-b"
        try await harness.ledger.bind(switched)
        let crossed = try await harness.ledger.finish(jobId: scheduled.job.id, permit: permit)
        XCTAssertEqual(crossed, .rejected(.accountMismatch))
        let otherSnapshots = try await harness.ledger.snapshotCount(accountId: "other-account")
        XCTAssertEqual(otherSnapshots, 0)

        try await harness.ledger.bind(permit)
        var nextGeneration = permit
        nextGeneration.generation = 2
        try await harness.ledger.bind(nextGeneration)
        let staleGeneration = try await harness.ledger.finish(jobId: scheduled.job.id, permit: permit)
        XCTAssertEqual(staleGeneration, .rejected(.generationMismatch))

        await harness.ledger.noteSignedOut()
        let signedOut = try await harness.ledger.finish(jobId: scheduled.job.id, permit: permit)
        XCTAssertEqual(signedOut, .rejected(.loggedOut))

        try await harness.ledger.bind(permit)
        let relaunched = BodyVisualizationLedger(rootURL: harness.root)
        try await relaunched.bind(permit)
        let resumed = try await relaunched.finish(jobId: scheduled.job.id, permit: permit)
        XCTAssertEqual(resumed, .idempotent(job))

        let plan = try await harness.ledger.deletionPlan(accountId: account)
        XCTAssertEqual(Set(plan.kinds), Set([.mask, .mesh, .texture, .cache]))
        try await harness.ledger.purge(accountId: account)
        let reopened = BodyVisualizationLedger(rootURL: harness.root)
        do {
            try await reopened.bind(permit)
            XCTFail("A deleted account cannot accept a relaunched job")
        } catch BodyVisualizationError.deleted {
        } catch {
            XCTFail("unexpected \(error)")
        }
        let late = try await reopened.finish(jobId: scheduled.job.id, permit: permit)
        XCTAssertEqual(late, .rejected(.deleted))
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.root.appendingPathComponent("accounts/\(account)").path))
    }

    func testCorrectionInvalidatesDerivativesAndKeepsSources() async throws {
        let harness = try makeHarness()
        let photo = try await schedule(harness, request: request(
            evidence: baseEvidence(),
            captures: [VisualizationCaptureRef(id: "front-capture", viewpoint: "front")],
            representation: .authenticPhoto
        ))
        let key = "progress-photos/\(account)/accounts/\(ownerId)/front-capture.jpg"
        let permit = permit(at: day(0))
        _ = try await harness.ledger.finish(
            jobId: photo.job.id, permit: permit, existingPhotoObjectKey: key, productOwnerId: ownerId
        )
        do {
            _ = try await harness.ledger.finish(
                jobId: photo.job.id,
                permit: permit,
                existingPhotoObjectKey: "notes/not-a-photo-store/object",
                productOwnerId: ownerId
            )
            XCTFail("A foreign provider key cannot attach")
        } catch BodyVisualizationError.foreignProviderKey {
        } catch {
            XCTFail("unexpected \(error)")
        }
        let plan = try await harness.ledger.deletionPlan(accountId: account)
        XCTAssertEqual(plan.providerObjectKeys, [key])
        XCTAssertTrue(plan.delegatesProviderOriginalsToExistingPhotoLifecycle)

        try await harness.ledger.invalidateDerivatives(accountId: account, evidenceIds: ["weight"])
        let stored = try await harness.ledger.document(accountId: account)
        let snapshot = try XCTUnwrap(stored.snapshots.first)
        XCTAssertTrue(snapshot.invalidated)
        XCTAssertEqual(snapshot.invalidationReason, "correction")
        XCTAssertTrue(snapshot.rawObservationIds.contains("raw-dexa"))
        XCTAssertEqual(snapshot.evidenceLinks.first { $0.id == "weight" }?.sourceDefinition, "fixture-scale")
        XCTAssertEqual(stored.assets.first { $0.kind == .original }?.invalidated, false)
        XCTAssertNotNil(stored.assets.first { $0.kind == .original }?.localRelativePath)
        XCTAssertEqual(stored.assets.first { $0.kind == .cache }?.invalidated, true)
        XCTAssertNil(stored.assets.first { $0.kind == .cache }?.localRelativePath)
        XCTAssertFalse(BodyVisualizationConsumer.presentation(for: snapshot).wireframePermitted)
    }

    func testMigrationIsAdditiveAndReplayable() throws {
        let empty = try BodyVisualizationMigration.migrate(Data())
        let encoded = try BodyVisualizationMigration.encoder().encode(empty)
        let replayed = try BodyVisualizationMigration.migrate(encoded)
        let again = try BodyVisualizationMigration.migrate(try BodyVisualizationMigration.encoder().encode(replayed))
        XCTAssertEqual(replayed, again)
        XCTAssertEqual(replayed.schemaVersion, BodyVisualizationSchema.current)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "jobs")
        object.removeValue(forKey: "assets")
        let partial = try JSONSerialization.data(withJSONObject: object)
        let migrated = try BodyVisualizationMigration.migrate(partial)
        XCTAssertEqual(migrated.frames, empty.frames)
        XCTAssertTrue(migrated.jobs.isEmpty)
        XCTAssertTrue(migrated.assets.isEmpty)

        XCTAssertThrowsError(try BodyVisualizationMigration.migrate(Data("{\"schemaVersion\":9}".utf8))) { error in
            XCTAssertEqual(error as? BodyVisualizationError, .unsupportedSchema(9))
        }
        let claimed = DatedShapeConstraint(
            weightEvidenceIds: [], compositionEvidenceIds: [], ffmiEvidenceId: nil, aggregateConfidence: nil
        )
        var shape = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try BodyVisualizationMigration.encoder().encode(claimed)) as? [String: Any]
        )
        shape["identifiesUnseenAnatomy"] = true
        XCTAssertThrowsError(
            try BodyVisualizationMigration.decoder().decode(
                DatedShapeConstraint.self, from: try JSONSerialization.data(withJSONObject: shape)
            )
        ) { error in
            XCTAssertEqual(error as? BodyVisualizationError, .uniqueAnatomyClaim)
        }
    }

    func testEntryGateRejectsSchedulingUntilEnabled() async throws {
        let harness = try makeHarness()
        let closed = BodyVisualizationEntry(
            isEnabled: { false },
            currentPermit: { date in self.permit(at: date) },
            ledger: harness.ledger
        )
        do {
            _ = try await closed.schedule(request(evidence: baseEvidence()))
            XCTFail("The visualization gate is off")
        } catch BodyVisualizationError.featureDisabled {
        } catch {
            XCTFail("unexpected \(error)")
        }
        let gatedCount = try await harness.ledger.snapshotCount(accountId: account)
        XCTAssertEqual(gatedCount, 0)

        let open = BodyVisualizationEntry(
            isEnabled: { true },
            currentPermit: { date in self.permit(at: date) },
            ledger: harness.ledger
        )
        let scheduled = try await open.schedule(request(evidence: baseEvidence()))
        var current = day(0)
        let changing = BodyVisualizationEntry(
            isEnabled: { true },
            currentPermit: { _ in self.permit(at: current) },
            ledger: harness.ledger
        )
        current = day(4)
        let late = try await changing.finish(jobId: scheduled.job.id, effectiveAt: current)
        XCTAssertEqual(late, .rejected(.dateChanged))
        let document = try await harness.ledger.document(accountId: account)
        XCTAssertTrue(document.assets.isEmpty)
    }
}
