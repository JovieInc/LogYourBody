import SwiftUI
import XCTest
@testable import LogYourBody

@MainActor
final class HealthSyncPresentationTests: XCTestCase {
    private let owner = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
    private let measuredAt = Date(timeIntervalSince1970: 1_772_530_860)
    private let locale = Locale(identifier: "en_US_POSIX")
    private let timeZone = TimeZone(secondsFromGMT: 0)!

    func testCaptionCopySnapshotsCoverEveryStateAndMissingTimestamp() {
        let snapshots: [(HealthSyncState, String)] = [
            (.checking, "Checking Apple Health…"),
            (.updated, "Updated from Apple Health, 9:41 AM"),
            (.unavailable, "Apple Health update unavailable"),
            (.permissionNeeded, "Apple Health access needed"),
            (.offline, "Offline · showing saved readings")
        ]
        XCTAssertEqual(snapshots.count, HealthSyncState.allCases.count)
        for (state, expected) in snapshots {
            XCTAssertEqual(normalized(HealthSyncPresentationPolicy.caption(
                state: state, lastSync: measuredAt, locale: locale, timeZone: timeZone
            )), expected)
        }
        XCTAssertEqual(HealthSyncPresentationPolicy.caption(state: .updated, lastSync: nil), "Updated from Apple Health")
        XCTAssertFalse(HealthSyncPresentationPolicy.isEnabled(isGateEnabled: { _ in false }))
        XCTAssertTrue(HealthSyncPresentationPolicy.isEnabled(isGateEnabled: {
            $0 == "health_sync_receipt_v1"
        }))
    }

    func testReceiptCopyUsesMeasurementTimeAndSelectedUnits() {
        let receipt = HealthWeightReceipt(id: UUID(), metric: metric("new"), expiresAt: measuredAt.addingTimeInterval(60))
        XCTAssertEqual(normalized(receipt.text(unit: "kg", locale: locale, timeZone: timeZone)),
                       "New weight from Apple Health · Mar 3, 9:41 AM · 82.4 kg")
        XCTAssertEqual(normalized(receipt.text(unit: "lb", locale: locale, timeZone: timeZone)),
                       "New weight from Apple Health · Mar 3, 9:41 AM · 181.7 lb")
    }

    /// Native render snapshots are attached to the xcresult for review at both text sizes.
    /// Copy is frozen above; this repository has no pixel-golden snapshot dependency.
    func testStateRenderSnapshotsAtNarrowWidthAndAccessibilityText() throws {
        let receipt = HealthWeightReceipt(id: UUID(), metric: metric("new"), expiresAt: measuredAt.addingTimeInterval(6))
        for state in HealthSyncState.allCases {
            for size in [DynamicTypeSize.large, .accessibility3] {
                for showsReceipt in [false, true] {
                    let view = HealthSyncStatusView(
                        state: state, lastSync: measuredAt, receipt: showsReceipt ? receipt : nil,
                        unit: "kg", onRecentReadings: {}
                    )
                    .padding(JovieTokens.screenInset)
                    .frame(width: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .background(HomeV2Tokens.Colors.canvas)
                    .environment(\.dynamicTypeSize, size)
                    .environment(\.locale, locale)
                    .environment(\.timeZone, timeZone)
                    .transaction { $0.disablesAnimations = true }
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 1
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(image.size.width, 320, accuracy: 1)
                    XCTAssertGreaterThan(image.size.height, 0)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "health-sync-\(state)-\(size)-receipt-\(showsReceipt)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    func testObserverSuppressesCachedHistoryDuplicatesAndIneligibleReadings() async throws {
        let observer = HealthReadingObserver()
        let start = measuredAt.addingTimeInterval(100)
        let cached = metric("cached")
        let initial = await observer.update([cached], owner: owner, sequence: 1, now: start)
        XCTAssertNil(initial?.receipt)
        let historical = metric("history")
        let ignored = [
            metric("manual", source: "manual", importedAt: start),
            metric("other", ownerID: "other", importedAt: start),
            metric("excluded", excluded: true, importedAt: start),
            metric("corrected", correction: 80, importedAt: start),
            metric("invalid", weight: .nan, importedAt: start),
            metric("missing", weight: nil, importedAt: start)
        ]
        let loaded = await observer.update([cached, historical] + ignored, owner: owner, sequence: 2, now: start)
        XCTAssertNil(loaded?.receipt)
        let new = metric("new", importedAt: start.addingTimeInterval(1))
        let received = await observer.update([new, cached], owner: owner, sequence: 3, now: start.addingTimeInterval(1))
        let receipt = try XCTUnwrap(received?.receipt)
        XCTAssertEqual(receipt.metric.id, "new")
        XCTAssertEqual(receipt.expiresAt.timeIntervalSince(start), 7)
        let duplicate = await observer.update([new, cached], owner: owner, sequence: 4, now: start.addingTimeInterval(2))
        XCTAssertEqual(duplicate?.receipt, receipt, "A repeated publication must not restart six seconds")
        let stale = await observer.update([historical], owner: owner, sequence: 2, now: start)
        XCTAssertNil(stale)
        let corrected = metric("new", correction: 80, importedAt: start.addingTimeInterval(1))
        let changed = await observer.update([corrected, cached], owner: owner, sequence: 5, now: start)
        XCTAssertNil(changed?.receipt)
    }

    func testRecentReadingsAreBoundedAndAccountLifetimeResetsBaseline() async throws {
        let observer = HealthReadingObserver()
        let readings = (0..<25).map { metric("reading-\($0)") }
        let first = await observer.update(readings, owner: owner, sequence: 1, now: measuredAt)
        XCTAssertEqual(first?.readings.count, 20)
        let newOwner = AuthManager.ProfileSessionOwnership(subject: owner.subject, generation: 2)
        let reset = await observer.update([metric("new")], owner: newOwner, sequence: 2, now: measuredAt)
        XCTAssertNil(reset?.receipt, "Signing back into the same subject starts a new baseline")
        XCTAssertEqual(reset?.readings.map(\.id), ["new"])
    }

    func testNewSampleCanReplaceALegacyDailyRowWithoutReannouncingEdits() async throws {
        let observer = HealthReadingObserver()
        let start = measuredAt.addingTimeInterval(100)
        _ = await observer.update([metric("day")], owner: owner, sequence: 1, now: start)
        let replacement = metric("day", weight: 81, importedAt: start)
        let updated = await observer.update([replacement], owner: owner, sequence: 2, now: start)
        XCTAssertEqual(updated?.receipt?.metric.weight, 81)
        let edited = metric("day", correction: 80, weight: 81, importedAt: start)
        let corrected = await observer.update([edited], owner: owner, sequence: 3, now: start)
        XCTAssertNil(corrected?.receipt)
    }

    func testAnnouncedReadingStaysReachableOutsideTheLatestTwenty() async throws {
        let observer = HealthReadingObserver()
        let start = measuredAt.addingTimeInterval(100)
        let cached = (0..<25).map { metric("reading-\($0)") }
        _ = await observer.update(cached, owner: owner, sequence: 1, now: start)
        let arrival = metric("zz-arrival", importedAt: start)
        let updated = await observer.update(cached + [arrival], owner: owner, sequence: 2, now: start)
        XCTAssertEqual(updated?.receipt?.metric.id, arrival.id)
        XCTAssertEqual(updated?.readings.first?.id, arrival.id)
        XCTAssertEqual(updated?.readings.count, 20)
    }

    func testSampleIdentityAndWholeSecondImportMetadataDetectSameValueArrival() async throws {
        func reading(sampleID: String) -> BodyMetrics {
            BodyMetrics(
                id: "day", userId: owner.subject, date: measuredAt, weight: 82.4, weightUnit: "kg",
                bodyFatPercentage: nil, bodyFatMethod: nil, muscleMass: nil, boneMass: nil,
                notes: nil, photoUrl: nil, dataSource: "healthkit",
                sourceMetadata: BodyMetricSourceMetadata(
                    sampleId: sampleID, importedAt: ISO8601DateFormatter().string(from: measuredAt)
                ),
                createdAt: measuredAt, updatedAt: measuredAt
            )
        }
        let observer = HealthReadingObserver()
        _ = await observer.update([reading(sampleID: "old")], owner: owner, sequence: 1,
                                  now: measuredAt.addingTimeInterval(0.6))
        let updated = await observer.update([reading(sampleID: "new")], owner: owner, sequence: 2,
                                            now: measuredAt.addingTimeInterval(0.8))
        XCTAssertEqual(updated?.receipt?.metric.sourceMetadata?.sampleId, "new")
    }

    func testTapAndOldTimersCannotDismissReplacementOrReplayReceipt() async throws {
        let store = HealthSyncPresentationStore()
        await store.observe([], owner: owner).value
        let new = metric("new", importedAt: Date().addingTimeInterval(1))
        await store.observe([new], owner: owner).value
        let first = try XCTUnwrap(store.receipt)
        let replacement = metric("replacement", importedAt: Date().addingTimeInterval(1))
        await store.observe([replacement, new], owner: owner).value
        let second = try XCTUnwrap(store.receipt)
        store.dismissReceipt(id: first.id)
        XCTAssertEqual(store.receipt, second)
        store.dismissReceipt(id: second.id)
        await store.observe([replacement, new], owner: owner).value
        XCTAssertNil(store.receipt)
        store.reset()
        XCTAssertTrue(store.readings.isEmpty)
        XCTAssertNil(store.lastChange)
    }

    func testReceiptAutomaticallyDismissesAfterSixSeconds() async throws {
        let store = HealthSyncPresentationStore()
        await store.observe([], owner: owner).value
        await store.observe([metric("new", importedAt: Date().addingTimeInterval(1))], owner: owner).value
        XCTAssertNotNil(store.receipt)
        try await Task.sleep(for: .seconds(6.2))
        XCTAssertNil(store.receipt)
        store.reset()
    }

    func testChangesPreserveUndoOnFailureAndRejectAccountReplacement() async throws {
        let store = HealthSyncPresentationStore()
        let original = metric("new")
        await store.observe([original], owner: owner).value
        let excluded = metric("new", excluded: true)
        let change = PhotoMetricsUpdateResult(metrics: excluded, createdNewEntry: false, previousMetric: original)
        let succeeded = await store.change(ownsSession: { $0 == self.owner }, operation: { change })
        XCTAssertTrue(succeeded)
        XCTAssertEqual(store.readings, [excluded])
        XCTAssertEqual(store.lastChange?.metrics, excluded)
        let failed = await store.change(ownsSession: { _ in true }, undoing: true, operation: {
            throw MetricCorrectionError.entryChanged
        })
        XCTAssertFalse(failed)
        XCTAssertNotNil(store.error)
        XCTAssertEqual(store.lastChange?.metrics, excluded)
        let undone = await store.change(ownsSession: { _ in true }, undoing: true, operation: {
            PhotoMetricsUpdateResult(metrics: original, createdNewEntry: false, previousMetric: excluded)
        })
        XCTAssertTrue(undone)
        XCTAssertEqual(store.readings, [original])
        XCTAssertNil(store.lastChange)
        let replaced = await store.change(ownsSession: { _ in true }, operation: {
            store.reset()
            return change
        })
        XCTAssertFalse(replaced)
        XCTAssertTrue(store.readings.isEmpty)
        XCTAssertNil(store.error)
    }

    private func metric(_ id: String, ownerID: String = "owner", source: String = "healthkit",
                        excluded: Bool = false, correction: Double? = nil, weight: Double? = 82.4,
                        importedAt: Date? = nil) -> BodyMetrics {
        BodyMetrics(
            id: id, userId: ownerID, date: measuredAt, weight: weight, weightUnit: "kg",
            bodyFatPercentage: nil, bodyFatMethod: nil, muscleMass: nil, boneMass: nil,
            notes: nil, photoUrl: nil, dataSource: source, isExcluded: excluded,
            correctedValue: correction.map { MetricCorrectedValue(weight: $0) },
            createdAt: importedAt ?? measuredAt, updatedAt: importedAt ?? measuredAt
        )
    }

    private func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202f}", with: " ").replacingOccurrences(of: "\u{00a0}", with: " ")
    }
}
