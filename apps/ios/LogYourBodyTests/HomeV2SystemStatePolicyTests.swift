//
// HomeV2SystemStatePolicyTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class HomeV2SystemStatePolicyTests: XCTestCase {
    private func state(
        loaded: Bool = true,
        online: Bool = true,
        syncEnabled: Bool = true,
        authorized: Bool = true,
        everAuthorized: Bool = true,
        hasHealthData: Bool = true,
        arguments: [String] = []
    ) -> HomeV2SystemState? {
        HomeV2SystemStatePolicy.state(
            hasLoadedInitialData: loaded,
            isOnline: online,
            healthSyncEnabled: syncEnabled,
            healthAuthorized: authorized,
            healthEverAuthorized: everAuthorized,
            hasHealthData: hasHealthData,
            arguments: arguments
        )
    }

    func testAllWellShowsNoState() {
        XCTAssertNil(state())
    }

    func testLoadingWinsThenOfflineThenHealthOff() {
        XCTAssertEqual(state(loaded: false, online: false, authorized: false), .loading)
        XCTAssertEqual(state(online: false, authorized: false), .offline)
        XCTAssertEqual(state(authorized: false), .healthOff)
    }

    func testHealthOffNeverNagsAManualOnlyPerson() {
        XCTAssertNil(state(authorized: false, hasHealthData: false), "No Apple Health data means nothing is 'off'")
        XCTAssertNil(state(syncEnabled: false, authorized: false), "Sync turned off on purpose is not a fault")
        XCTAssertNil(state(authorized: false, everAuthorized: false), "Never authorized is not 'off', it is not yet on")
    }

    func testAuthorizationIsRememberedOnlyWhenGranted() {
        let defaults = UserDefaults(suiteName: "HomeV2SystemStatePolicyTests") ?? .standard
        defaults.removeObject(forKey: HomeV2SystemStatePolicy.everAuthorizedKey)
        HomeV2SystemStatePolicy.recordAuthorization(false, defaults: defaults)
        XCTAssertFalse(defaults.bool(forKey: HomeV2SystemStatePolicy.everAuthorizedKey))
        HomeV2SystemStatePolicy.recordAuthorization(true, defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: HomeV2SystemStatePolicy.everAuthorizedKey))
        defaults.removeObject(forKey: HomeV2SystemStatePolicy.everAuthorizedKey)
    }

    #if DEBUG
    func testFixturesForceEachState() {
        XCTAssertEqual(state(arguments: [HomeV2SystemStatePolicy.offlineFixtureArgument]), .offline)
        XCTAssertEqual(state(arguments: [HomeV2SystemStatePolicy.healthOffFixtureArgument]), .healthOff)
        XCTAssertEqual(state(arguments: [HomeV2SystemStatePolicy.loadingFixtureArgument]), .loading)
    }
    #endif
}
