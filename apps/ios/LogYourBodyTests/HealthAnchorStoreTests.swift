import HealthKit
import XCTest
@testable import LogYourBody

final class HealthAnchorStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var store: HealthAnchorStore!

    override func setUp() {
        super.setUp()
        suiteName = "HealthAnchorStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = HealthAnchorStore(defaults: defaults!)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testAnchorIsPersistedPerUserAndSampleKind() {
        store.advance(Data([1]), for: .weight, userId: "user-a", commitSucceeded: true)
        store.advance(Data([2]), for: .bodyFat, userId: "user-a", commitSucceeded: true)
        store.advance(Data([3]), for: .steps, userId: "user-a", commitSucceeded: true)
        store.advance(Data([4]), for: .weight, userId: "user-b", commitSucceeded: true)

        XCTAssertEqual(store.anchor(for: .weight, userId: "user-a"), Data([1]))
        XCTAssertEqual(store.anchor(for: .bodyFat, userId: "user-a"), Data([2]))
        XCTAssertEqual(store.anchor(for: .steps, userId: "user-a"), Data([3]))
        XCTAssertEqual(store.anchor(for: .weight, userId: "user-b"), Data([4]))
        XCTAssertNil(store.anchor(for: .bodyFat, userId: "user-b"))
        XCTAssertNotEqual(
            defaults.data(forKey: HealthKitDefaultsKey.weightQueryAnchor.scoped(with: "user-a")),
            defaults.data(forKey: HealthKitDefaultsKey.weightQueryAnchor.scoped(with: "user-b"))
        )
    }

    func testAnchorDoesNotAdvanceWhenTheCommitFails() {
        store.advance(Data([7]), for: .weight, userId: "user-a", commitSucceeded: true)

        store.advance(Data([8]), for: .weight, userId: "user-a", commitSucceeded: false)
        store.advance(nil, for: .weight, userId: "user-a", commitSucceeded: true)
        store.advance(Data(), for: .bodyFat, userId: "user-a", commitSucceeded: true)

        XCTAssertEqual(store.anchor(for: .weight, userId: "user-a"), Data([7]))
        XCTAssertNil(store.anchor(for: .bodyFat, userId: "user-a"))
        XCTAssertNil(store.anchor(for: .steps, userId: "user-b"))
    }

    func testResetClearsOnlyThatUsersAnchors() {
        store.advance(Data([1]), for: .weight, userId: "user-a", commitSucceeded: true)
        store.advance(Data([2]), for: .bodyFat, userId: "user-a", commitSucceeded: true)
        store.advance(Data([3]), for: .steps, userId: "user-a", commitSucceeded: true)
        store.advance(Data([4]), for: .weight, userId: "user-b", commitSucceeded: true)

        store.reset(userId: "user-a")

        XCTAssertNil(store.anchor(for: .weight, userId: "user-a"))
        XCTAssertNil(store.anchor(for: .bodyFat, userId: "user-a"))
        XCTAssertNil(store.anchor(for: .steps, userId: "user-a"))
        XCTAssertFalse(store.hasBodyMetricAnchors(userId: "user-a"))
        XCTAssertEqual(store.anchor(for: .weight, userId: "user-b"), Data([4]))
    }

    func testDeletedWeightSampleMarksAHealthKitRowAndKeepsAPairedBodyFatSample() {
        let weight = importedRow(id: "weight-only", source: "healthkit", weight: 70, bodyFat: nil, metadata: weightMetadata)
        let combined = importedRow(
            id: "combined", source: "HealthKit", weight: 71, bodyFat: 18,
            metadata: combinedMetadata
        )
        let manual = importedRow(
            id: "manual", source: "manual", weight: 72, bodyFat: nil, metadata: weightMetadata
        )

        let weightChanges = HealthAnchorDeletionPolicy.changes(
            deleting: "weight-sample", kind: .weight, rows: [weight, combined, manual]
        )
        let bodyFatChanges = HealthAnchorDeletionPolicy.changes(
            deleting: "fat-sample", kind: .bodyFat, rows: [combined]
        )

        XCTAssertEqual(weightChanges.count, 2)
        XCTAssertTrue(weightChanges.contains(.markDeleted("weight-only")))
        guard case .keepBodyFatOnly("combined", let kept) = weightChanges[1] else {
            return XCTFail("Paired body fat must stay on the row")
        }
        XCTAssertEqual(kept.sampleId, "fat-sample")
        XCTAssertEqual(kept.quantityType, HKQuantityTypeIdentifier.bodyFatPercentage.rawValue)
        XCTAssertNil(kept.bodyFatSampleId)
        XCTAssertEqual(
            bodyFatChanges,
            [.keepWeightOnly("combined", weightOnlyMetadata)]
        )
    }

    func testDeletedBodyFatSampleMarksABodyFatOnlyRow() {
        let row = importedRow(
            id: "fat-only", source: "healthkit", weight: nil, bodyFat: 19, metadata: bodyFatMetadata
        )

        let changes = HealthAnchorDeletionPolicy.changes(
            deleting: "fat-sample", kind: .bodyFat, rows: [row]
        )

        XCTAssertEqual(changes, [.markDeleted("fat-only")])
    }

    private func importedRow(
        id: String, source: String, weight: Double?, bodyFat: Double?, metadata: BodyMetricSourceMetadata
    ) -> HealthAnchorImportedRow {
        HealthAnchorImportedRow(
            id: id, dataSource: source, weight: weight, bodyFatPercentage: bodyFat, metadata: metadata
        )
    }

    private var weightMetadata: BodyMetricSourceMetadata {
        BodyMetricSourceMetadata(
            vendor: "apple_health", sourceName: "Scale", sampleId: "weight-sample",
            quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue
        )
    }

    private var bodyFatMetadata: BodyMetricSourceMetadata {
        BodyMetricSourceMetadata(
            vendor: "apple_health", sourceName: "Scale", sampleId: "fat-sample",
            quantityType: HKQuantityTypeIdentifier.bodyFatPercentage.rawValue
        )
    }

    private var combinedMetadata: BodyMetricSourceMetadata {
        BodyMetricSourceMetadata(
            vendor: "apple_health", sourceName: "Scale", sampleId: "weight-sample",
            quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue, bodyFatSampleId: "fat-sample"
        )
    }

    private var weightOnlyMetadata: BodyMetricSourceMetadata {
        BodyMetricSourceMetadata(
            vendor: "apple_health", sourceName: "Scale", sampleId: "weight-sample",
            quantityType: HKQuantityTypeIdentifier.bodyMass.rawValue
        )
    }
}
