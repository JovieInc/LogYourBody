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

    func testReservedStageUsesTheSameBudgetForEveryPhotoState() {
        let tallContent: CGFloat = 692
        let tall = HomeV2StageReservation.size(width: 390, contentHeight: tallContent, presentation: .photo)
        XCTAssertGreaterThan(tall.width, 0)
        XCTAssertGreaterThan(tall.height, 0)
        XCTAssertEqual(tall.height, 390 / HomeV2Tokens.photoAspectRatio, accuracy: 0.01)
        XCTAssertEqual(
            tall.height,
            HomeV2Layout.stageHeight(
                width: 390,
                height: tallContent + HomeV2StageReservation.dockAllowance + HomeV2Layout.belowPhotoHeight
            ),
            accuracy: 0.01
        )
        for presentation in HomeV2StagePresentation.allCases {
            let size = HomeV2StageReservation.size(
                width: 390, contentHeight: tallContent, presentation: presentation
            )
            XCTAssertEqual(size.width, tall.width, accuracy: 0.01, "\(presentation)")
            XCTAssertEqual(size.height, tall.height, accuracy: 0.01, "\(presentation)")
        }

        let almostSquare = HomeV2StageReservation.size(width: 393, contentHeight: 488, presentation: .photo)
        XCTAssertEqual(almostSquare.height, 393 / HomeV2Tokens.photoAspectRatio, accuracy: 0.01)

        let shortContent: CGFloat = 300
        let short = HomeV2StageReservation.size(width: 375, contentHeight: shortContent, presentation: .noPhoto)
        let expectedShort = shortContent + HomeV2StageReservation.dockAllowance
        XCTAssertEqual(short.height, expectedShort, accuracy: 0.01)
        XCTAssertLessThan(short.height, 375 / HomeV2Tokens.photoAspectRatio)
        for presentation in [HomeV2StagePresentation.loading, .failedLoad, .offline, .photo] {
            let size = HomeV2StageReservation.size(
                width: 375, contentHeight: shortContent, presentation: presentation
            )
            XCTAssertEqual(size.height, short.height, accuracy: 0.01, "\(presentation)")
        }

        let aboveFloor = HomeV2StageReservation.size(width: 320, contentHeight: 232, presentation: .offline)
        XCTAssertEqual(aboveFloor.height, 232 + HomeV2StageReservation.dockAllowance, accuracy: 0.01)
        XCTAssertGreaterThan(aboveFloor.height, HomeV2Layout.minimumStageHeight)
        XCTAssertLessThan(aboveFloor.height, 320 / HomeV2Tokens.photoAspectRatio)

        let floor = HomeV2StageReservation.size(width: 320, contentHeight: 100, presentation: .loading)
        XCTAssertEqual(floor.height, HomeV2Layout.minimumStageHeight, accuracy: 0.01)

        let blank = HomeV2StageReservation.size(
            width: .nan, contentHeight: -.infinity, presentation: .failedLoad
        )
        XCTAssertEqual(blank.width, 0, accuracy: 0.01)
        XCTAssertEqual(blank.height, 0, accuracy: 0.01)
    }

    func testEmptyPhotoLibraryOffersAddInsteadOfTheBrowseHint() {
        XCTAssertTrue(HomeV2EmptyPhotoLibrary.showsEmptyState(photoCount: 0))
        XCTAssertFalse(HomeV2EmptyPhotoLibrary.showsEmptyState(photoCount: 1))
        XCTAssertEqual(HomeV2EmptyPhotoLibrary.title, "Add progress photo")
        XCTAssertNotEqual(HomeV2EmptyPhotoLibrary.title, HomeV2PhotoCopy.tapToOpen)
        XCTAssertTrue(HomeV2EmptyPhotoLibrary.captureOrImport.contains("library"))
        XCTAssertTrue(HomeV2EmptyPhotoLibrary.privacy.localizedCaseInsensitiveContains("optional"))
        XCTAssertFalse(HomeV2EmptyPhotoLibrary.why.isEmpty)
        XCTAssertFalse(HomeV2EmptyPhotoLibrary.posing.isEmpty)
        XCTAssertEqual(HomeV2PhotoCopy.tryPhotoAgain, "Try again")
    }
}
