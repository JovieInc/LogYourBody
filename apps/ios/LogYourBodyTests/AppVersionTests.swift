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
}
