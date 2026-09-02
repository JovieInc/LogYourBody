//
// AppVersionTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

/// Unit tests for `AppVersion`.
///
/// Scope note: `AppVersion` is a thin bundle-metadata reader — it has no
/// semver parsing, comparison, or prerelease logic (the only version
/// comparison in the app is `String.compare(_:options: .numeric)` inside
/// `AppVersionManager`, exercised by `AppVersionManagerTests`). These tests
/// pin the actual contract: bundle wiring, fallbacks, and the display
/// format consumed by `VersionRow` and `AnalyticsService`.
final class AppVersionTests: XCTestCase {
    func testValuesReflectBundleInfoDictionary() {
        let info = Bundle.main.infoDictionary
        let expectedVersion = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let expectedBuild = info?["CFBundleVersion"] as? String ?? "1"

        XCTAssertEqual(AppVersion.current, expectedVersion)
        XCTAssertEqual(AppVersion.build, expectedBuild)
    }

    func testShortVersionIsCurrentVersionWithoutPrefix() {
        XCTAssertEqual(AppVersion.shortVersion, AppVersion.current)
        XCTAssertFalse(AppVersion.shortVersion.hasPrefix("Version"))
    }

    func testFullVersionEmbedsVersionAndBuildInDisplayFormat() {
        XCTAssertEqual(AppVersion.fullVersion, "Version \(AppVersion.current) (\(AppVersion.build))")
        XCTAssertTrue(AppVersion.fullVersion.hasPrefix("Version "))
        XCTAssertTrue(AppVersion.fullVersion.hasSuffix("(\(AppVersion.build))"))
    }

    func testReleaseReviewRequiresExactInstalledReleaseEvidence() throws {
        let item = try XCTUnwrap(ReleaseReviewCatalog.items(version: "2.4", build: "2407").first)

        XCTAssertEqual(
            ReleaseReviewPresentationPolicy.pendingItems(
                from: [item],
                installedVersion: "2.4",
                installedBuild: "2407",
                reviewedTokens: [],
                isEligible: true
            ),
            [item]
        )
        XCTAssertTrue(
            ReleaseReviewPresentationPolicy.pendingItems(
                from: [item],
                installedVersion: "2.4",
                installedBuild: "2408",
                reviewedTokens: [],
                isEligible: true
            ).isEmpty
        )
        XCTAssertTrue(
            ReleaseReviewPresentationPolicy.pendingItems(
                from: [item],
                installedVersion: "2.5",
                installedBuild: "2407",
                reviewedTokens: [],
                isEligible: true
            ).isEmpty
        )
    }

    func testReleaseReviewSeenAndReviewedStatesRemainDistinct() throws {
        let item = try XCTUnwrap(ReleaseReviewCatalog.items(version: "2.4", build: "2407").first)
        var state = ReleaseReviewState()

        state.recordSeen(item)
        XCTAssertTrue(state.hasSeen(item))
        XCTAssertFalse(state.hasReviewed(item))
        XCTAssertEqual(
            ReleaseReviewPresentationPolicy.pendingItems(
                from: [item],
                installedVersion: "2.4",
                installedBuild: "2407",
                reviewedTokens: state.reviewedTokens,
                isEligible: true
            ),
            [item],
            "Dismissing a seen item must surface it again on the next app open."
        )

        state.recordReviewed(item)
        XCTAssertTrue(state.hasReviewed(item))
        XCTAssertTrue(
            ReleaseReviewPresentationPolicy.pendingItems(
                from: [item],
                installedVersion: "2.4",
                installedBuild: "2407",
                reviewedTokens: state.reviewedTokens,
                isEligible: true
            ).isEmpty
        )
    }

    func testReleaseReviewDoesNotPresentUntilCustomerSurfaceIsEligible() throws {
        let item = try XCTUnwrap(ReleaseReviewCatalog.items(version: "2.4", build: "2407").first)

        XCTAssertTrue(
            ReleaseReviewPresentationPolicy.pendingItems(
                from: [item],
                installedVersion: "2.4",
                installedBuild: "2407",
                reviewedTokens: [],
                isEligible: false
            ).isEmpty
        )
    }

    func testReleaseReviewIdentityDoesNotUsePullRequestOrCIProvenance() throws {
        let item = try XCTUnwrap(ReleaseReviewCatalog.items(version: "2.4", build: "2407").first)

        XCTAssertEqual(item.evidence.product, "logyourbody")
        XCTAssertEqual(item.evidence.destination.rawValue, "logyourbody://timeline")
        XCTAssertTrue(item.evidenceToken.contains("2.4+2407"))
        XCTAssertFalse(item.evidenceToken.localizedCaseInsensitiveContains("github"))
        XCTAssertFalse(item.evidenceToken.localizedCaseInsensitiveContains("ci"))
    }

    func testReleaseReviewCatalogKeepsMetadataSemanticsAndCTAExplanationDistinct() throws {
        let item = try XCTUnwrap(ReleaseReviewCatalog.items(version: "2.4", build: "2407").first)
        let metadata = ReleaseReviewCatalog.metadata(for: item.evidence)

        XCTAssertEqual(metadata.map(\.label), ["Version", "Build"])
        XCTAssertEqual(metadata.map(\.value), ["2.4", "2407"])
        XCTAssertTrue(ReleaseReviewContentPolicy.violations(metadata: metadata, items: [item]).isEmpty)
    }

    func testReleaseReviewContentPolicyRejectsMergedMetadataSemantics() throws {
        let item = try XCTUnwrap(ReleaseReviewCatalog.items(version: "2.4", build: "2407").first)
        let deliberatelyInvalidField = ReleaseReviewMetadataField(
            id: "version",
            label: "Version",
            value: "2.4",
            labelRole: .value,
            valueRole: .value
        )

        XCTAssertEqual(
            ReleaseReviewContentPolicy.violations(
                metadata: [deliberatelyInvalidField],
                items: [item]
            ),
            [.mergedMetadataSemantics(fieldID: "version")],
            "A label and value rendered with the same semantic role must fail review."
        )
    }

    func testReleaseReviewContentPolicyRejectsAdjacentCTARedundancy() throws {
        let item = try XCTUnwrap(ReleaseReviewCatalog.items(version: "2.4", build: "2407").first)
        let deliberatelyInvalidItem = ReleaseReviewItem(
            id: item.id,
            evidence: item.evidence,
            title: item.title,
            summary: item.summary,
            symbolName: item.symbolName,
            actionTitle: item.actionTitle,
            adjacentActionDescription: "Opens Timeline"
        )

        XCTAssertEqual(
            ReleaseReviewContentPolicy.violations(metadata: [], items: [deliberatelyInvalidItem]),
            [.redundantAdjacentAction(itemID: item.id)],
            "Adjacent explanation must not restate its CTA destination or action."
        )
    }
}
