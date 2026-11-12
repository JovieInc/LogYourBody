import XCTest
@testable import LogYourBody

final class BodyParameterModelTests: XCTestCase {
    private let requested = BodyParameterValues(adiposity: 0.237, muscularity: 0.419, proportion: 0.673)

    func testFixedBodyFatPreservesDistinctContinuousTriplesInBothFamilies() throws {
        let other = BodyParameterValues(adiposity: 0.641, muscularity: 0.173, proportion: 0.827)
        for family in BodyParameterFamily.allCases {
            let first = try project(family: family)
            let second = try BodyParameterModel.current.project(
                family: family, requested: other, evidence: inputs()
            )
            XCTAssertEqual(first.family, family)
            XCTAssertEqual(second.family, family)
            XCTAssertEqual(first.parameters, requested)
            XCTAssertEqual(second.parameters, other)
            XCTAssertNotEqual(first.parameters.adiposity, second.parameters.adiposity)
            XCTAssertNotEqual(first.parameters.muscularity, second.parameters.muscularity)
            XCTAssertNotEqual(first.parameters.proportion, second.parameters.proportion)
            XCTAssertEqual(first.evidenceLinks, second.evidenceLinks)
            XCTAssertEqual(first.derivedFFMI, second.derivedFFMI)
        }
        XCTAssertNotEqual(try project(family: .male), try project(family: .female))
    }

    func testChangingOnlyBodyFatLeavesMuscularityAndProportionUnchanged() throws {
        for family in BodyParameterFamily.allCases {
            let first = try project(family: family, evidence: inputs(bodyFat: 20))
            let second = try project(family: family, evidence: inputs(bodyFat: 35))
            XCTAssertEqual(first.parameters.adiposity, second.parameters.adiposity)
            XCTAssertEqual(first.parameters.muscularity, second.parameters.muscularity)
            XCTAssertEqual(first.parameters.proportion, second.parameters.proportion)
            XCTAssertNotEqual(first.derivedFFMI?.value, second.derivedFFMI?.value)
        }
    }

    func testSharedInputFFMIIsDerivedWithoutCreatingSeparateEvidence() throws {
        let source = inputs()
        let presentation = try project(evidence: source)
        let derived = try XCTUnwrap(presentation.derivedFFMI)
        XCTAssertEqual(derived.value, 64 / (1.7 * 1.7) + 6.1 * 0.1, accuracy: 1e-9)
        XCTAssertEqual(derived.lineageIds, ["body-fat", "height", "weight"])
        XCTAssertEqual(presentation.evidenceLinks.map(\.id), source.map(\.id).sorted())
        XCTAssertEqual(presentation.evidenceLinks.count, 3)
        XCTAssertFalse(presentation.evidenceLinks.contains { $0.role == .ffmi })
        XCTAssertEqual(presentation.evidenceLinks.filter { $0.recordKind == .observation }.map(\.id),
                       ["body-fat", "height", "weight"])
    }

    func testStoredModelVersionChangeKeepsOriginalObservationIdentitiesAndDates() throws {
        let source = inputs()
        let original = try project(evidence: source)
        let changed = try BodyParameterModel(id: BodyParameterModel.current.id, version: "2.0.0").project(
            family: .female, requested: requested, evidence: source
        )
        let data = try JSONEncoder().encode([original, changed])
        let stored = try JSONDecoder().decode([BodyParameterPresentation].self, from: data)
        XCTAssertEqual(stored, [original, changed])
        XCTAssertEqual(stored.map(\.reconstructionModelId), [BodyParameterModel.current.id, BodyParameterModel.current.id])
        XCTAssertEqual(stored.map(\.reconstructionModelVersion), ["1.0.0", "2.0.0"])
        XCTAssertEqual(stored[0].parameters, stored[1].parameters)
        XCTAssertEqual(stored[0].evidenceLinks, stored[1].evidenceLinks)
        let documents = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        for document in documents {
            XCTAssertNil(document["id"])
            XCTAssertNil(document["effectiveAt"])
            XCTAssertNil(document["observedAt"])
        }
        let observationIds = Set(stored.flatMap(\.evidenceLinks).filter { $0.recordKind == .observation }.map(\.id))
        XCTAssertEqual(observationIds, Set(source.map(\.id)))
        let observationsById = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
        let datedObservations = observationIds.compactMap { observationsById[$0] }
        XCTAssertEqual(datedObservations.count, 3)
        XCTAssertEqual(Set(datedObservations.map(\.effectiveAt)), [Date(timeIntervalSince1970: 0)])
    }

    func testOnlySupportedRangesClampEachCoordinateIndependently() throws {
        let ranges = BodyParameterRanges(adiposity: 0.3...0.8, muscularity: 0.2...0.9, proportion: 0.1...0.6)
        for family in BodyParameterFamily.allCases {
            let value = try BodyParameterModel.current.project(
                family: family, requested: requested, supportedRanges: ranges, evidence: inputs()
            )
            XCTAssertEqual(value.parameters, BodyParameterValues(adiposity: 0.3, muscularity: 0.419, proportion: 0.6))
            let extremes = try BodyParameterModel.current.project(
                family: family, requested: BodyParameterValues(adiposity: -4, muscularity: 8, proportion: 0.123)
            )
            XCTAssertEqual(extremes.parameters, BodyParameterValues(adiposity: 0, muscularity: 1, proportion: 0.123))
        }
    }

    func testHeightWeightDexaAndEstimatesDoNotSelectShapeCoordinates() throws {
        var source = inputs()
        source[0].magnitude = 190
        source[1].magnitude = 110
        source[2].recordKind = .estimate
        source[2].epistemic = .inferred
        source[2].lineageIds = ["source-estimate"]
        source.append(evidence("dxa-lean", role: .dxaLeanTissue, value: 60, unit: "kg"))
        let value = try project(evidence: source)
        XCTAssertEqual(value.parameters, requested)
        XCTAssertEqual(value.evidenceLinks.count, 4)
        let estimate = try XCTUnwrap(value.evidenceLinks.first { $0.id == "body-fat" })
        XCTAssertEqual(estimate.recordKind, .estimate)
        XCTAssertEqual(estimate.epistemic, .inferred)
        XCTAssertEqual(estimate.lineageIds, ["source-estimate"])
        let withoutEvidence = try project(evidence: [])
        XCTAssertEqual(withoutEvidence.parameters, requested)
        XCTAssertTrue(withoutEvidence.evidenceLinks.isEmpty)
        XCTAssertNil(withoutEvidence.derivedFFMI)
    }

    func testMissingInvalidAmbiguousOrConflictingInputsDoNotDeriveFFMI() throws {
        for index in 0..<3 {
            var missing = inputs()
            missing.remove(at: index)
            XCTAssertNil(try project(evidence: missing).derivedFFMI)
            for invalid in [Double.nan, .infinity, -.infinity, -1, 0] {
                var source = inputs()
                source[index].magnitude = invalid
                XCTAssertNil(try project(evidence: source).derivedFFMI)
            }
            var wrongUnit = inputs()
            wrongUnit[index].unit = "unsupported"
            XCTAssertNil(try project(evidence: wrongUnit).derivedFFMI)
            var ambiguous = inputs()
            var duplicate = ambiguous[index]
            duplicate.id += "-other"
            ambiguous.append(duplicate)
            XCTAssertNil(try project(evidence: ambiguous).derivedFFMI)
            var conflicting = inputs()
            conflicting[index].conflictIds = ["conflict"]
            XCTAssertNil(try project(evidence: conflicting).derivedFFMI)
            var stale = inputs()
            stale[index].stale = true
            XCTAssertNil(try project(evidence: stale).derivedFFMI)
        }
        XCTAssertNil(try project(evidence: inputs(bodyFat: 100)).derivedFFMI)
    }

    func testNonFiniteCoordinatesAndUnsupportedRangesAreRejected() throws {
        for invalid in [Double.nan, .infinity, -.infinity] {
            let values = [
                BodyParameterValues(adiposity: invalid, muscularity: 0.5, proportion: 0.5),
                BodyParameterValues(adiposity: 0.5, muscularity: invalid, proportion: 0.5),
                BodyParameterValues(adiposity: 0.5, muscularity: 0.5, proportion: invalid)
            ]
            for value in values {
                XCTAssertThrowsError(try BodyParameterModel.current.project(family: .male, requested: value)) {
                    XCTAssertEqual($0 as? BodyParameterModelError, .nonFiniteParameter)
                }
            }
        }
        let invalidRanges = [
            BodyParameterRanges(adiposity: -0.1...1, muscularity: 0...1, proportion: 0...1),
            BodyParameterRanges(adiposity: 0...1, muscularity: 0...1.1, proportion: 0...1),
            BodyParameterRanges(adiposity: 0...1, muscularity: 0...1, proportion: 0...Double.infinity)
        ]
        for ranges in invalidRanges {
            XCTAssertThrowsError(try BodyParameterModel.current.project(
                family: .female, requested: requested, supportedRanges: ranges
            )) {
                XCTAssertEqual($0 as? BodyParameterModelError, .unsupportedRange)
            }
        }
    }

    func testIndependentFFMIMixedAccountsDuplicateEvidenceAndEmptyModelStampsAreRejected() throws {
        var independent = inputs()
        independent.append(evidence("ffmi", role: .ffmi, value: 25, unit: "kg/m2"))
        XCTAssertThrowsError(try project(evidence: independent)) {
            XCTAssertEqual($0 as? BodyParameterModelError, .independentFFMI)
        }
        var mixed = inputs()
        mixed[0].accountId = "other-account"
        XCTAssertThrowsError(try project(evidence: mixed)) {
            XCTAssertEqual($0 as? BodyParameterModelError, .invalidEvidence)
        }
        XCTAssertThrowsError(try project(evidence: inputs() + [inputs()[0]])) {
            XCTAssertEqual($0 as? BodyParameterModelError, .invalidEvidence)
        }
        for model in [BodyParameterModel(id: " ", version: "1"), BodyParameterModel(id: "model", version: "")] {
            XCTAssertThrowsError(try model.project(family: .male, requested: requested)) {
                XCTAssertEqual($0 as? BodyParameterModelError, .invalidModelIdentity)
            }
        }
    }

    private func project(
        family: BodyParameterFamily = .female,
        evidence: [CanonicalBodyEvidenceRef]? = nil
    ) throws -> BodyParameterPresentation {
        try BodyParameterModel.current.project(family: family, requested: requested, evidence: evidence ?? inputs())
    }

    private func inputs(bodyFat: Double = 20) -> [CanonicalBodyEvidenceRef] {
        [
            evidence("height", role: .height, value: 170, unit: "cm"),
            evidence("weight", role: .weight, value: 80, unit: "kg"),
            evidence("body-fat", role: .bodyFat, value: bodyFat, unit: "%")
        ]
    }

    private func evidence(
        _ id: String,
        role: CanonicalBodyEvidenceRef.Role,
        value: Double,
        unit: String
    ) -> CanonicalBodyEvidenceRef {
        CanonicalBodyEvidenceRef(
            id: id, accountId: "parameter-test", recordKind: .observation, role: role, epistemic: .measured,
            effectiveAt: Date(timeIntervalSince1970: 0), sourceDefinition: "unit-test", confidence: 0.5,
            stale: false, conflictIds: [], lineageIds: [], rawObservationIds: [], magnitude: value, unit: unit
        )
    }
}
