import XCTest
@testable import LogYourBody

@MainActor
extension BodyVisualizationSnapshotTests {
    struct Harness {
        var root: URL
        var ledger: BodyVisualizationLedger
    }

    func persistedText<T: Encodable>(_ value: T) throws -> String {
        let data = try BodyVisualizationMigration.encoder().encode(value)
        return try XCTUnwrap(String(bytes: data, encoding: .utf8))
    }

    func makeHarness() throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("body-visualization-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return Harness(root: root, ledger: BodyVisualizationLedger(rootURL: root))
    }

    func schedule(_ harness: Harness, request: BodyVisualizationRequest) async throws -> ScheduledVisualization {
        let active = permit(at: request.effectiveAt)
        try await harness.ledger.bind(active)
        return try await harness.ledger.schedule(request, permit: active)
    }

    func day(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset * 86_400)
    }

    func permit(
        account: String? = nil,
        session: String = "session-a",
        generation: UInt64 = 1,
        at: Date
    ) -> VisualizationWorkPermit {
        VisualizationWorkPermit(
            accountId: account ?? self.account,
            sessionId: session,
            generation: generation,
            effectiveAt: at,
            acceptsAttachments: true,
            deleted: false
        )
    }

    func model(_ version: String = "v1") -> VisualizationModelIdentity {
        VisualizationModelIdentity(
            modelVersion: version,
            calibrationVersion: "cal-1",
            presentationVersion: "present-1",
            topologyId: "topology-a"
        )
    }

    func evidence(
        _ id: String,
        role: CanonicalBodyEvidenceRef.Role,
        kind: CanonicalBodyEvidenceRef.RecordKind = .observation,
        epistemic: CanonicalBodyEvidenceRef.Epistemic = .measured,
        source: String = "fixture-scale",
        confidence: Double = 0.5,
        stale: Bool = false,
        conflictIds: [String] = [],
        lineageIds: [String] = [],
        rawObservationIds: [String] = [],
        magnitude: Double? = nil,
        unit: String? = nil,
        at: Date? = nil
    ) -> CanonicalBodyEvidenceRef {
        CanonicalBodyEvidenceRef(
            id: id,
            accountId: account,
            recordKind: kind,
            role: role,
            epistemic: epistemic,
            effectiveAt: at ?? day(0),
            sourceDefinition: source,
            confidence: confidence,
            stale: stale,
            conflictIds: conflictIds,
            lineageIds: lineageIds,
            rawObservationIds: rawObservationIds,
            magnitude: magnitude,
            unit: unit
        )
    }

    func baseEvidence() -> [CanonicalBodyEvidenceRef] {
        [
            evidence("height", role: .height, confidence: 0.4, magnitude: 164.5, unit: "cm"),
            evidence("weight", role: .weight, confidence: 0.55, magnitude: 71.25, unit: "kg"),
            evidence("ffm", role: .fatFreeMass, source: "fixture-ffm", confidence: 0.45),
            evidence(
                "dexa-lean", role: .dxaLeanTissue, kind: .estimate, epistemic: .measured,
                source: "bodyspec_dexa", confidence: 0.7, stale: true, rawObservationIds: ["raw-dexa"], at: day(-400)
            )
        ]
    }

    func dexRequest(at date: Date) -> BodyVisualizationRequest {
        request(evidence: baseEvidence(), at: date, representation: .personalizedInferredGeometry, geometryKnown: true)
    }

    func request(
        evidence: [CanonicalBodyEvidenceRef],
        captures: [VisualizationCaptureRef] = [],
        representation: VisualizationRepresentation = .personalizedInferredGeometry,
        provider: String? = nil,
        geometryKnown: Bool = true,
        at: Date? = nil,
        model: VisualizationModelIdentity? = nil
    ) -> BodyVisualizationRequest {
        let effective = at ?? day(0)
        return BodyVisualizationRequest(
            accountId: account,
            effectiveAt: effective,
            computedAt: effective,
            evidence: evidence,
            captures: captures,
            model: model ?? self.model(),
            representation: representation,
            providerSourceDefinition: provider,
            geometryKnown: geometryKnown
        )
    }
}
