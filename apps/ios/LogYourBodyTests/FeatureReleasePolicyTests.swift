//
// FeatureReleasePolicyTests.swift
// LogYourBodyTests
//
// Runs the shared Jovie/LYB release-lifecycle conformance corpus
// (shared/release/feature-release-policy-fixtures.json, JOV-8056) through the
// Swift adapter. The corpus is the contract: any divergence is a failure.
//

import XCTest
@testable import LogYourBody

private struct FeatureReleaseFixtureCorpus: Decodable {
    struct Case: Decodable {
        let name: String
        let descriptor: FeatureReleaseDescriptor
        let context: FeatureReleaseContext
        let expected: FeatureReleaseDecision
    }

    let schemaVersion: Int
    var cases: [Case]
}

final class FeatureReleasePolicyTests: XCTestCase {
    /// Returns the first case whose observed decision diverges, or nil.
    private func firstMismatch(in corpus: FeatureReleaseFixtureCorpus) -> String? {
        for testCase in corpus.cases {
            let observed = FeatureReleaseEvaluator.evaluate(testCase.descriptor, context: testCase.context)
            guard observed == testCase.expected else {
                return """
                \(testCase.name): expected isEnabled=\(testCase.expected.isEnabled) \
                reason=\(testCase.expected.reason.rawValue), got isEnabled=\(observed.isEnabled) \
                reason=\(observed.reason.rawValue)
                """
            }
        }
        return nil
    }

    private func loadCorpus() throws -> FeatureReleaseFixtureCorpus {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent() // FeatureReleasePolicyTests.swift
            .deletingLastPathComponent() // LogYourBodyTests
            .deletingLastPathComponent() // ios
            .deletingLastPathComponent() // apps
        let fixtureURL = repoRoot
            .appendingPathComponent("shared")
            .appendingPathComponent("release")
            .appendingPathComponent("feature-release-policy-fixtures.json")
        let data = try Data(contentsOf: fixtureURL)
        return try JSONDecoder().decode(FeatureReleaseFixtureCorpus.self, from: data)
    }

    func testSharedConformanceCorpus() throws {
        let corpus = try loadCorpus()
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertFalse(corpus.cases.isEmpty)
        XCTAssertNil(firstMismatch(in: corpus))
    }

    /// The corpus harness must actually catch a deliberate divergence —
    /// a runner that cannot fail is not a conformance gate.
    func testDivergenceIsDetected() throws {
        var corpus = try loadCorpus()
        guard let first = corpus.cases.first else {
            return XCTFail("fixture corpus is empty")
        }
        corpus.cases[0] = FeatureReleaseFixtureCorpus.Case(
            name: first.name,
            descriptor: first.descriptor,
            context: first.context,
            expected: FeatureReleaseDecision(
                isEnabled: !first.expected.isEnabled,
                reason: first.expected.reason
            )
        )
        XCTAssertNotNil(firstMismatch(in: corpus))
    }
}
