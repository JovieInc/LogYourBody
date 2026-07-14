//
// BulkImportManagerBoundsTests.swift
// LogYourBodyTests
//
// Regression coverage for a confirmed crash: `importPhoto(at:)` bounds-checks the
// index only once, before its first `await`. If the user cancels an in-flight
// bulk import and starts a smaller one, `importTasks` shrinks while the old task
// is still suspended; on resume its captured index pointed past the array and
// `importTasks[index]` trapped with "Index out of range". `updateImportTask`
// re-validates the index on every mutation.
//
import XCTest
@testable import LogYourBody

@MainActor
final class BulkImportManagerBoundsTests: XCTestCase {
    func test_updateImportTask_indexPastEnd_isSafeNoOp() {
        let manager = BulkImportManager.shared
        let original = manager.importTasks
        defer { manager.importTasks = original }

        manager.importTasks = []

        // Would previously crash: importTasks[5] on an empty array.
        manager.updateImportTask(at: 5) { $0.status = .completed }
        XCTAssertTrue(manager.importTasks.isEmpty)

        // A negative index is also a safe no-op.
        manager.updateImportTask(at: -1) { $0.status = .failed }
        XCTAssertTrue(manager.importTasks.isEmpty)
    }
}
