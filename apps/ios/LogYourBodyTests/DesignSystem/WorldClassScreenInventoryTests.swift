//
// WorldClassScreenInventoryTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

final class WorldClassScreenInventoryTests: XCTestCase {
    func testApprovedScreenCatalogStaysAtFortySixStates() {
        XCTAssertEqual(WorldClassScreen.allCases.count, 46)

        let counts = Dictionary(grouping: WorldClassScreen.allCases, by: \.flow)
            .mapValues(\.count)

        XCTAssertEqual(counts[.entry], 5)
        XCTAssertEqual(counts[.onboarding], 17)
        XCTAssertEqual(counts[.core], 11)
        XCTAssertEqual(counts[.subscription], 3)
        XCTAssertEqual(counts[.account], 10)
    }

    func testRawValuesStayStableInDeclarationOrder() {
        XCTAssertEqual(
            WorldClassScreen.allCases.map(\.rawValue),
            [
                "launch",
                "signIn",
                "legalConsent",
                "biometricLock",
                "whatsNew",
                "bodyScoreIntro",
                "sexAtBirth",
                "height",
                "appleHealth",
                "confirmImportedData",
                "weight",
                "bodyFatMethod",
                "bodyFatValue",
                "visualEstimate",
                "calculation",
                "bodyScoreReveal",
                "chooseHomeView",
                "email",
                "verifyAccount",
                "completeProfile",
                "firstProgressPhoto",
                "paywall",
                "home",
                "photoTimeline",
                "stats",
                "chat",
                "metricDetail",
                "logWeight",
                "logBodyFat",
                "addProgressPhoto",
                "glp1CheckIn",
                "shareBodyScore",
                "syncDetails",
                "dailyReminder",
                "planUnavailable",
                "restorePurchases",
                "settings",
                "editProfile",
                "trackingAndGoals",
                "integrations",
                "importPhotos",
                "exportData",
                "activeSessions",
                "privacyAndData",
                "deleteAccount",
                "bugReport"
            ]
        )
    }

    func testAccessibilityIdentifiersStayStableUniqueAnchors() {
        let identifiers = WorldClassScreen.allCases.map(\.accessibilityIdentifier)

        XCTAssertEqual(Set(identifiers).count, WorldClassScreen.allCases.count)
        XCTAssertEqual(
            WorldClassScreen.home.accessibilityIdentifier,
            "world_class_screen_home"
        )
        XCTAssertEqual(
            WorldClassScreen.settings.accessibilityIdentifier,
            "world_class_screen_settings"
        )
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("world_class_screen_") })
        XCTAssertTrue(identifiers.allSatisfy { !$0.contains(" ") })

        for screen in WorldClassScreen.allCases {
            XCTAssertEqual(screen.id, screen.rawValue)
            XCTAssertEqual(screen.accessibilityIdentifier, "world_class_screen_\(screen.rawValue)")
        }
    }

    func testEachFlowHasAShippedPathProbeScreen() {
        let probes: [(WorldClassScreenFlow, WorldClassScreen)] = [
            (.entry, .signIn),
            (.onboarding, .bodyScoreIntro),
            (.core, .home),
            (.subscription, .dailyReminder),
            (.account, .settings)
        ]

        XCTAssertEqual(Set(probes.map(\.0)), Set(WorldClassScreenFlow.allCases))

        for (flow, screen) in probes {
            XCTAssertEqual(screen.flow, flow)
            XCTAssertEqual(screen.accessibilityIdentifier, WorldClassScreen(rawValue: screen.rawValue)?.accessibilityIdentifier)
            XCTAssertTrue(screen.accessibilityIdentifier.hasPrefix("world_class_screen_"))
        }
    }

    func testFlowMembershipStaysStable() {
        XCTAssertEqual(WorldClassScreen.launch.flow, .entry)
        XCTAssertEqual(WorldClassScreen.signIn.flow, .entry)
        XCTAssertEqual(WorldClassScreen.bodyScoreIntro.flow, .onboarding)
        XCTAssertEqual(WorldClassScreen.paywall.flow, .onboarding)
        XCTAssertEqual(WorldClassScreen.home.flow, .core)
        XCTAssertEqual(WorldClassScreen.chat.flow, .core)
        XCTAssertEqual(WorldClassScreen.dailyReminder.flow, .subscription)
        XCTAssertEqual(WorldClassScreen.settings.flow, .account)
        XCTAssertEqual(WorldClassScreen.bugReport.flow, .account)
    }
}
