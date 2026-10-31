import XCTest
@testable import LogYourBody

final class HealthSyncStateTests: XCTestCase {
    private let syncDate = Date(timeIntervalSince1970: 1_000)

    func testTransitionTableFromEveryState() {
        let rows: [(HealthSyncState.Event, HealthSyncState)] = [
            (.refreshStarted, .checking),
            (.refreshFinished(at: syncDate), .updated),
            (.noNewData(at: syncDate), .updated),
            (.refreshFailed, .unavailable),
            (.authorizationDenied, .permissionNeeded),
            (.authorizationRevoked, .permissionNeeded),
            (.noNetwork, .offline)
        ]

        for initial in HealthSyncState.allCases {
            for (event, target) in rows {
                var reducer = makeReducer(in: initial)
                reducer.reduce(event)

                let expected: HealthSyncState
                if initial == .permissionNeeded {
                    expected = .permissionNeeded
                } else if case .refreshFinished = event, initial != .checking {
                    expected = initial
                } else if case .noNewData = event, initial != .checking {
                    expected = initial
                } else {
                    expected = target
                }
                XCTAssertEqual(reducer.state, expected, "\(initial) + \(event)")
            }
        }
    }

    func testPermissionDenialAndRevocationStaySilentUntilAuthorizationIsRestored() {
        for permissionEvent in [HealthSyncState.Event.authorizationDenied, .authorizationRevoked] {
            var reducer = makeReducer(in: .updated)
            let previousSync = reducer.lastSuccessfulSync
            reducer.reduce(permissionEvent)

            let lateEvents: [HealthSyncState.Event] = [
                .refreshStarted, .refreshFinished(at: syncDate.addingTimeInterval(60)),
                .noNewData(at: syncDate.addingTimeInterval(120)), .refreshFailed, .noNetwork
            ]
            for event in lateEvents {
                reducer.reduce(event)
                XCTAssertEqual(reducer.state, .permissionNeeded)
                XCTAssertFalse(reducer.state.isNagWorthy)
                XCTAssertEqual(reducer.lastSuccessfulSync, previousSync)
            }

            reducer.reduce(.authorizationGranted)
            reducer.reduce(.refreshStarted)
            reducer.reduce(.refreshFinished(at: syncDate.addingTimeInterval(180)))
            XCTAssertEqual(reducer.state, .updated)
            XCTAssertEqual(reducer.lastSuccessfulSync, syncDate.addingTimeInterval(180))
        }
    }

    func testOnlySuccessfulRefreshesAdvanceLastSuccessfulSync() {
        var reducer = HealthSyncStateReducer()
        XCTAssertNil(reducer.lastSuccessfulSync)
        reducer.reduce(.refreshFinished(at: syncDate))
        XCTAssertNil(reducer.lastSuccessfulSync, "A completion without a refresh is stale")

        reducer.reduce(.refreshStarted)
        reducer.reduce(.refreshFinished(at: syncDate))
        XCTAssertEqual(reducer.lastSuccessfulSync, syncDate)

        for event in [HealthSyncState.Event.refreshStarted, .refreshFailed, .noNetwork,
                      .authorizationDenied, .authorizationRevoked, .authorizationGranted] {
            reducer.reduce(event)
            XCTAssertEqual(reducer.lastSuccessfulSync, syncDate, "\(event)")
        }

        reducer.reduce(.refreshStarted)
        reducer.reduce(.noNewData(at: syncDate.addingTimeInterval(60)))
        XCTAssertEqual(reducer.state, .updated, "An empty successful read is not permission denial")
        XCTAssertEqual(reducer.lastSuccessfulSync, syncDate.addingTimeInterval(60))

        reducer.reduce(.refreshStarted)
        reducer.reduce(.refreshFinished(at: syncDate))
        XCTAssertEqual(reducer.lastSuccessfulSync, syncDate.addingTimeInterval(60), "Never move the date backwards")
    }

    func testNagRuleForEveryState() {
        for state in HealthSyncState.allCases {
            XCTAssertEqual(state.isNagWorthy, state == .unavailable || state == .offline, "\(state)")
        }
    }

    func testAuthorizationGrantedOnlyClearsPermissionNeeded() {
        for state in HealthSyncState.allCases {
            var reducer = makeReducer(in: state)
            let previousSync = reducer.lastSuccessfulSync
            reducer.reduce(.authorizationGranted)
            XCTAssertEqual(reducer.state, state == .permissionNeeded ? .unavailable : state)
            XCTAssertEqual(reducer.lastSuccessfulSync, previousSync)
        }
    }

    private func makeReducer(in state: HealthSyncState) -> HealthSyncStateReducer {
        var reducer = HealthSyncStateReducer()
        switch state {
        case .checking: reducer.reduce(.refreshStarted)
        case .updated:
            reducer.reduce(.refreshStarted)
            reducer.reduce(.refreshFinished(at: syncDate))
        case .unavailable: reducer.reduce(.refreshFailed)
        case .permissionNeeded: reducer.reduce(.authorizationDenied)
        case .offline: reducer.reduce(.noNetwork)
        }
        return reducer
    }
}
