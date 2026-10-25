//
// BodyMetricLoggingAndInsightTests.swift
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


final class BodyMetricLoggingServiceTests: XCTestCase {
    func testStoredWeightConvertsPoundsToKilograms() {
        let stored = BodyMetricLoggingService.storedWeightInKilograms(
            displayWeight: 180,
            unit: "lbs"
        )

        XCTAssertEqual(stored ?? 0, 81.6467, accuracy: 0.001)
    }

    func testStoredWeightKeepsKilograms() {
        let stored = BodyMetricLoggingService.storedWeightInKilograms(
            displayWeight: 82.5,
            unit: "kg"
        )

        XCTAssertEqual(stored, 82.5)
    }

    func testLoggedSummaryUsesPreferredWeightUnitAndBodyFatPercent() {
        let metric = BodyMetrics(
            id: "metric-1",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: 81.6467,
            weightUnit: "kg",
            bodyFatPercentage: 14.8,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(
            BodyMetricLoggingService.loggedSummary(for: metric, preferredSystem: .imperial),
            "Logged 180.0 lbs and 14.8% body fat."
        )
    }

    func testSpotlightDocumentUsesLatestMetricSearchCopy() {
        let metric = BodyMetrics(
            id: "metric-spotlight",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: 81.6467,
            weightUnit: "kg",
            bodyFatPercentage: 14.8,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let document = BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .imperial)

        XCTAssertEqual(document?.identifier, "body-metric-metric-spotlight")
        XCTAssertEqual(document?.title, "Latest LogYourBody metrics")
        XCTAssertEqual(document?.contentDescription, "180.0 lbs, 14.8% body fat on 1970-01-01")
        XCTAssertEqual(
            document?.keywords,
            [
                "LogYourBody",
                "body metrics",
                "weight",
                "body composition",
                "1970-01-01",
                "latest weight",
                "body fat"
            ]
        )
    }

    func testSpotlightDocumentSkipsEntriesWithoutSearchableMetrics() {
        let metric = BodyMetrics(
            id: "metric-empty",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: nil,
            weightUnit: nil,
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertNil(BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .imperial))
    }

    func testSpotlightDocumentWithWeightOnlyOmitsBodyFatKeyword() {
        let metric = BodyMetrics(
            id: "metric-weight-only",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: nil,
            bodyFatMethod: nil,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let document = BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .metric)

        XCTAssertEqual(document?.contentDescription, "80.0 kg on 1970-01-01")
        XCTAssertEqual(
            document?.keywords,
            ["LogYourBody", "body metrics", "weight", "body composition", "1970-01-01", "latest weight"]
        )
    }

    func testSpotlightDocumentWithBodyFatOnlyOmitsLatestWeightKeyword() {
        let metric = BodyMetrics(
            id: "metric-bf-only",
            userId: "user-1",
            date: Date(timeIntervalSince1970: 0),
            localDate: "1970-01-01",
            weight: nil,
            weightUnit: nil,
            bodyFatPercentage: 15,
            bodyFatMethod: "Manual",
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: BodyMetricSource.manual.rawValue,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        let document = BodyMetricSpotlightDocument.make(for: metric, preferredSystem: .metric)

        XCTAssertEqual(document?.contentDescription, "15.0% body fat on 1970-01-01")
        XCTAssertEqual(
            document?.keywords,
            ["LogYourBody", "body metrics", "weight", "body composition", "1970-01-01", "body fat"]
        )
    }

    func testStoredWeightMatchesSharedLifecycleFixture() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("web/src/lib/metrics/weight-lifecycle-fixtures.json")
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(WeightLifecycleFixtureFile.self, from: data)
        XCTAssertEqual(fixture.pounds_to_kilograms, "0.45359237")
        XCTAssertEqual(BodyMetricLoggingService.poundsToKilograms, 0.45359237, accuracy: 0.0000000001)

        for item in fixture.cases {
            let unit = item.unit == "lb" ? "lb" : item.unit
            let stored = try XCTUnwrap(
                BodyMetricLoggingService.storedWeightInKilograms(displayWeight: item.value, unit: unit)
            )
            XCTAssertEqual(stored, try XCTUnwrap(Double(item.weight_kg)), accuracy: 0.000001, item.name)
        }
    }

    func testWeightCommandPlansNeverTurnCorrectionIntoCreate() {
        let missingRevision = BodyMetricLoggingService.planWeightCommand(
            kind: "correct", recordId: "record-1", operationId: "operation-1", expectedRevision: nil
        )
        let missingRecord = BodyMetricLoggingService.planWeightCommand(
            kind: "delete", recordId: nil, operationId: "operation-1", expectedRevision: 2
        )
        let create = BodyMetricLoggingService.planWeightCommand(
            kind: "create", recordId: "record-1", operationId: "operation-1", expectedRevision: nil
        )
        let correct = BodyMetricLoggingService.planWeightCommand(
            kind: "correct", recordId: "record-1", operationId: "operation-1", expectedRevision: 2
        )

        guard case .identityRequired = missingRevision else {
            return XCTFail("correction without a revision must not run")
        }
        guard case .identityRequired = missingRecord else {
            return XCTFail("delete without a record must not run")
        }
        XCTAssertEqual(create, .create(recordId: "record-1", operationId: "operation-1"))
        XCTAssertEqual(correct, .correct(recordId: "record-1", operationId: "operation-1", expectedRevision: 2))
    }

    func testAdmissionAndCompletionStayExplicit() {
        XCTAssertEqual(
            BodyMetricLoggingService.admissionGate(
                authenticated: false, protectedDataAvailable: true, clarificationCancelled: false
            ),
            .notAuthenticated
        )
        XCTAssertEqual(
            BodyMetricLoggingService.admissionGate(
                authenticated: true, protectedDataAvailable: false, clarificationCancelled: false
            ),
            .protectedDataUnavailable
        )
        XCTAssertEqual(
            BodyMetricLoggingService.admissionGate(
                authenticated: false, protectedDataAvailable: false, clarificationCancelled: true
            ),
            .clarificationCancelled
        )
        XCTAssertNil(
            BodyMetricLoggingService.admissionGate(
                authenticated: true, protectedDataAvailable: true, clarificationCancelled: false
            )
        )

        let saved = BodyMetricLogCompletion.separate(localSaved: true, healthKitAuthorized: false)
        XCTAssertEqual(saved.local, .saved)
        XCTAssertEqual(saved.healthKit, .denied)
        XCTAssertEqual(saved.cloud, .notClaimed)
        let failed = BodyMetricLogCompletion.separate(localSaved: false, healthKitAuthorized: true)
        XCTAssertEqual(failed.local, .failed)
        XCTAssertEqual(failed.cloud, .notClaimed)
    }

    func testLocalWriteProtectsRetriesTombstonesAndChangedPayloads() {
        XCTAssertEqual(
            BodyMetricLoggingService.decideLocalWrite(
                hasExisting: false, existingOperationId: nil, incomingOperationId: "op",
                weightsEqual: true, existingDeleted: false
            ),
            .insert
        )
        XCTAssertEqual(
            BodyMetricLoggingService.decideLocalWrite(
                hasExisting: true, existingOperationId: "op", incomingOperationId: "op",
                weightsEqual: true, existingDeleted: false
            ),
            .retryKeepingTimestamps
        )
        XCTAssertEqual(
            BodyMetricLoggingService.decideLocalWrite(
                hasExisting: true, existingOperationId: "op", incomingOperationId: "op",
                weightsEqual: true, existingDeleted: true
            ),
            .preserveTombstone
        )
        XCTAssertEqual(
            BodyMetricLoggingService.decideLocalWrite(
                hasExisting: true, existingOperationId: "op", incomingOperationId: "op",
                weightsEqual: false, existingDeleted: false
            ),
            .conflict
        )
        XCTAssertEqual(
            BodyMetricLoggingService.decideLocalWrite(
                hasExisting: true, existingOperationId: "op", incomingOperationId: "newer",
                weightsEqual: false, existingDeleted: true
            ),
            .apply
        )
    }

    func testPushResultDecodesConflictsAndBareRecordArrays() throws {
        let envelope = try BodyMetricBatchPushResult.decode(from: Data(
            #"{"records":[{"id":"kept"}],"conflicts":[{"id":"row-1","code":"tombstone"}]}"#.utf8
        ))
        XCTAssertEqual(envelope.records.first?["id"] as? String, "kept")
        XCTAssertEqual(envelope.conflicts, [BodyMetricPushConflict(id: "row-1", code: "tombstone")])

        let bare = try BodyMetricBatchPushResult.decode(from: Data(#"[{"id":"only"}]"#.utf8))
        XCTAssertTrue(bare.conflicts.isEmpty)
        XCTAssertEqual(bare.records.first?["id"] as? String, "only")
    }
}

private struct WeightLifecycleFixtureFile: Decodable {
    struct CaseFile: Decodable {
        let name: String
        let value: Double
        let unit: String
        let weight_kg: String
    }

    let pounds_to_kilograms: String
    let cases: [CaseFile]
}
