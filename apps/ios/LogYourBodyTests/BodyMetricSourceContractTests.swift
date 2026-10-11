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
}
