import XCTest
@testable import LogYourBody

final class SessionListOrderingTests: XCTestCase {
    private func makeSession(
        id: String,
        lastActiveAt: Date,
        isCurrentSession: Bool = false
    ) -> SessionInfo {
        SessionInfo(
            id: id,
            deviceName: "Device \(id)",
            deviceType: "iPhone",
            location: "Test",
            ipAddress: "",
            lastActiveAt: lastActiveAt,
            createdAt: lastActiveAt,
            isCurrentSession: isCurrentSession
        )
    }

    func testCurrentSessionPinnedFirstEvenWhenLeastRecentlyActive() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let sessions = [
            makeSession(id: "other-new", lastActiveAt: new),
            makeSession(id: "current", lastActiveAt: old, isCurrentSession: true)
        ]

        let ordered = SessionListOrdering.sorted(sessions)

        XCTAssertEqual(ordered.map(\.id), ["current", "other-new"])
    }

    func testNonCurrentSessionsSortByLastActiveDescending() {
        let base = Date(timeIntervalSince1970: 1_000)
        let sessions = [
            makeSession(id: "oldest", lastActiveAt: base),
            makeSession(id: "newest", lastActiveAt: base.addingTimeInterval(2_000)),
            makeSession(id: "middle", lastActiveAt: base.addingTimeInterval(1_000))
        ]

        let ordered = SessionListOrdering.sorted(sessions)

        XCTAssertEqual(ordered.map(\.id), ["newest", "middle", "oldest"])
    }

    func testCurrentSessionFirstThenRemainingByRecency() {
        let base = Date(timeIntervalSince1970: 1_000)
        let sessions = [
            makeSession(id: "older-other", lastActiveAt: base),
            makeSession(id: "newer-other", lastActiveAt: base.addingTimeInterval(1_000)),
            makeSession(id: "current", lastActiveAt: base, isCurrentSession: true)
        ]

        let ordered = SessionListOrdering.sorted(sessions)

        XCTAssertEqual(ordered.map(\.id), ["current", "newer-other", "older-other"])
    }

    func testEmptyAndSingleSessionInputsPassThrough() {
        XCTAssertTrue(SessionListOrdering.sorted([]).isEmpty)

        let single = [makeSession(id: "only", lastActiveAt: Date(timeIntervalSince1970: 1_000), isCurrentSession: true)]
        XCTAssertEqual(SessionListOrdering.sorted(single).map(\.id), ["only"])
    }
}
