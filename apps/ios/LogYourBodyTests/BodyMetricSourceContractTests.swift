//
// BodyMetricContractTests.swift
// LogYourBodyTests
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody


final class BodyMetricSourceContractTests: XCTestCase {
    func testSourceNormalizationCoversLaunchImportSources() {
        XCTAssertEqual(BodyMetricSource.normalizedRawValue(nil), "manual")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("Manual"), "manual")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("HealthKit"), "healthkit")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("smart scale"), "smart_scale")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("partner:bodyspec"), "bodyspec_dexa")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("DEXA PDF"), "dexa_pdf")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("InBody PDF"), "inbody_pdf")
        XCTAssertEqual(BodyMetricSource.dexaPDF.rawValue, "dexa_pdf")
        XCTAssertEqual(BodyMetricSource.inbodyPDF.rawValue, "inbody_pdf")
        XCTAssertTrue(BodyMetricSource.allowedRawValues.contains("dexa_pdf"))
        XCTAssertTrue(BodyMetricSource.allowedRawValues.contains("inbody_pdf"))
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("skinfold caliper"), "caliper")
        XCTAssertEqual(BodyMetricSource.normalizedRawValue("Photo Import"), "photo")
    }

    func testSourceMetadataTrimsEmptyValuesAndSerializesPointersOnly() throws {
        let metadata = BodyMetricSourceMetadata(
            vendor: " BodySpec ",
            sourceName: "",
            deviceModel: "Scanner X",
            externalResultId: " result-123 "
        )

        let jsonString = try XCTUnwrap(metadata.jsonString)
        let decoded = try XCTUnwrap(BodyMetricSourceMetadata(jsonString: jsonString))

        XCTAssertEqual(decoded.vendor, "BodySpec")
        XCTAssertNil(decoded.sourceName)
        XCTAssertEqual(decoded.deviceModel, "Scanner X")
        XCTAssertEqual(decoded.externalResultId, "result-123")
        XCTAssertEqual(decoded.jsonObject["vendor"], "BodySpec")
    }

    func testUnconfiguredBuildCannotClaimAnExistingConnectionIsAvailable() {
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecConnection(configured: false, connected: true), "Unavailable")
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecConnection(configured: false, connected: false), "Unavailable")
    }

    func testScanPresenceCannotEstablishBodySpecConnection() {
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecConnection(configured: true, connected: false), "Not connected")
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecConnection(configured: true, connected: true), "Connected")
    }

    func testHistoryRefreshCannotApplyAfterAccountSwitchSignOutOrCancellation() {
        XCTAssertTrue(IntegrationStatusPolicy.mayApplyHistory(
            requestedUserId: "owner", currentUserId: "owner", cancelled: false
        ))
        for userId in ["other", nil, ""] {
            XCTAssertFalse(IntegrationStatusPolicy.mayApplyHistory(
                requestedUserId: "owner", currentUserId: userId, cancelled: false
            ))
        }
        XCTAssertFalse(IntegrationStatusPolicy.mayApplyHistory(
            requestedUserId: "owner", currentUserId: "owner", cancelled: true
        ))
        XCTAssertFalse(IntegrationStatusPolicy.mayApplyHistory(
            requestedUserId: "", currentUserId: "", cancelled: false
        ))
    }

    func testHistoryUsesBodySpecAcquisitionDatesRatherThanOtherVendorsOrUpdateTime() {
        let older = scan(id: "older", source: "bodyspec", acquired: 100, updated: 900)
        let newer = scan(id: "newer", source: "BodySpec", acquired: 200, updated: 300)
        let other = scan(id: "other", source: "inbody_pdf", acquired: 800, updated: 800)
        XCTAssertEqual(IntegrationStatusPolicy.bodySpecHistory([other, older, newer]).map(\.id), ["newer", "older"])
        XCTAssertEqual(IntegrationStatusPolicy.scanDate(older, directoryEnabled: true), older.acquireTime)
    }

    func testMissingAcquisitionDateDoesNotBecomeLastSyncTime() {
        let result = scan(id: "unknown", source: "bodyspec", acquired: nil, updated: 900)
        XCTAssertNil(IntegrationStatusPolicy.scanDate(result, directoryEnabled: true))
        XCTAssertEqual(IntegrationStatusPolicy.scanDate(result, directoryEnabled: false), result.updatedAt)
    }

    private func scan(id: String, source: String, acquired: TimeInterval?, updated: TimeInterval) -> DexaResult {
        DexaResult(
            id: id, userId: "owner", bodyMetricsId: nil, externalSource: source, externalResultId: id,
            externalUpdateTime: nil, scannerModel: nil, locationId: nil, locationName: nil,
            acquireTime: acquired.map { Date(timeIntervalSince1970: $0) }, analyzeTime: nil,
            vatMassKg: nil, vatVolumeCm3: nil, resultPdfUrl: nil, resultPdfName: nil,
            createdAt: Date(timeIntervalSince1970: updated), updatedAt: Date(timeIntervalSince1970: updated)
        )
    }
}
