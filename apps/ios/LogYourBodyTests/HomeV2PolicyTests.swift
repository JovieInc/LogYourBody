//
// HomeV2PolicyTests.swift
// LogYourBodyTests
//
import XCTest
import UIKit
@testable import LogYourBody

@MainActor
final class HomeV2PolicyTests: XCTestCase {
    func testHomeV2DefaultsOnWhenKillSwitchIsOff() {
        var askedKey: String?
        XCTAssertTrue(
            HomeV2Policy.isEnabled(
                arguments: ["-lybUITestPhotoTimelineHUDFixture"],
                isGateEnabled: { key in
                    askedKey = key
                    return false
                }
            )
        )
        XCTAssertEqual(askedKey, HomeV2Policy.killSwitchKey)
    }

    func testKillSwitchDisablesHomeV2() {
        var askedKey: String?
        XCTAssertFalse(
            HomeV2Policy.isEnabled(arguments: [], isGateEnabled: { key in
                askedKey = key
                return true
            })
        )
        XCTAssertEqual(askedKey, HomeV2Policy.killSwitchKey)
    }

    #if DEBUG
    func testRollbackFixtureDisablesHomeV2WithoutReadingRemoteGates() {
        XCTAssertFalse(
            HomeV2Policy.isEnabled(arguments: [HomeV2Policy.rollbackFixtureArgument], isGateEnabled: { _ in
                XCTFail("The explicit rollback fixture must not read remote gates")
                return false
            })
        )
    }

    func testRollbackFixtureWinsOverConflictingHomeV2Fixtures() {
        let homeFixtures = [
            HomeV2Policy.fixtureArgument,
            HomeV2Policy.photoFixtureArgument,
            HomeV2Policy.emptyFixtureArgument,
            HomeV2SystemStatePolicy.offlineFixtureArgument,
            HomeV2SystemStatePolicy.healthOffFixtureArgument,
            HomeV2SystemStatePolicy.loadingFixtureArgument
        ]
        for fixture in homeFixtures {
            XCTAssertFalse(
                HomeV2Policy.isEnabled(
                    arguments: [fixture, HomeV2Policy.rollbackFixtureArgument],
                    isGateEnabled: { _ in false }
                ),
                "Rollback must win over \(fixture)"
            )
        }
    }

    #else
    func testRollbackFixtureArgumentCannotDisableShippingHome() {
        XCTAssertTrue(
            HomeV2Policy.isEnabled(arguments: ["-lybUITestHomeRollbackFixture"], isGateEnabled: { _ in false })
        )
    }
    #endif

    #if DEBUG
    func testFixtureArgumentsEnableHomeV2WithoutTheGate() {
        XCTAssertTrue(
            HomeV2Policy.isEnabled(arguments: [HomeV2Policy.fixtureArgument], isGateEnabled: { _ in false })
        )
        XCTAssertTrue(
            HomeV2Policy.isEnabled(arguments: [HomeV2Policy.photoFixtureArgument], isGateEnabled: { _ in false })
        )
        XCTAssertTrue(
            HomeV2Policy.isEnabled(arguments: [HomeV2Policy.emptyFixtureArgument], isGateEnabled: { _ in false })
        )
    }
    #endif

    func testChangeSentenceReadsAsASentence() {
        XCTAssertEqual(HomeV2Copy.changeSentence(delta: -1.8, unit: "lb"), "Down 1.8 lb in 30 days")
        XCTAssertEqual(HomeV2Copy.changeSentence(delta: 0.4, unit: "kg"), "Up 0.4 kg in 30 days")
        XCTAssertEqual(HomeV2Copy.changeSentence(delta: 0.02, unit: "lb"), "No change in 30 days")
        XCTAssertEqual(HomeV2Copy.changeSentence(delta: nil, unit: "lb"), "No 30-day trend yet")
    }

    func testCompositionHeadlineShowsDirectComparableBodyFatTrend() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let older = calendar.date(byAdding: .day, value: -20, to: now) ?? now
        let otherMethod = calendar.date(byAdding: .day, value: -10, to: now) ?? now
        let latest = calendar.date(byAdding: .day, value: -4, to: now) ?? now

        let headline = HomeV2CompositionPolicy.headline(
            metrics: [
                compositionMetric(date: older, bodyFat: 24.1, method: "dexa"),
                compositionMetric(date: otherMethod, bodyFat: 28.0, method: "manual"),
                compositionMetric(date: latest, bodyFat: 21.2, method: "DEXA (BodySpec)")
            ],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(headline, "DEXA body fat 21.2% · Down 2.9 pts in 16 days")
    }

    func testCompositionHeadlineLabelsEstimatesAndDoesNotInventATrend() {
        let now = Date()
        let estimate = compositionMetric(date: now, bodyFat: 25.4, method: "visual_estimate")
        XCTAssertEqual(
            HomeV2CompositionPolicy.headline(metrics: [estimate], now: now),
            "Estimated body fat 25.4% · trend starts with another check-in"
        )

        let stale = compositionMetric(
            date: now.addingTimeInterval(-40 * 86_400),
            bodyFat: 24.0,
            method: "dexa"
        )
        XCTAssertEqual(
            HomeV2CompositionPolicy.headline(metrics: [stale], now: now),
            HomeV2Copy.compositionTrackingPrompt
        )
    }

    private func compositionMetric(date: Date, bodyFat: Double, method: String) -> BodyMetrics {
        BodyMetrics(
            id: UUID().uuidString,
            userId: "home-composition-test",
            date: date,
            localDate: BodyMetricLocalDate.key(for: date),
            weight: 80,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: method,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }

    func testSinceSentenceAndPhotoPositionReadAsSentences() {
        XCTAssertEqual(HomeV2Copy.sinceSentence(delta: -12.8, unit: "lb", since: "Apr 2"), "Down 12.8 lb since Apr 2")
        XCTAssertEqual(HomeV2Copy.sinceSentence(delta: 0.3, unit: "kg", since: "Apr 2"), "Up 0.3 kg since Apr 2")
        XCTAssertEqual(HomeV2Copy.sinceSentence(delta: 0.01, unit: "lb", since: "Apr 2"), "No change since Apr 2")
        XCTAssertEqual(HomeV2Copy.photoPosition(3, of: 24), "Photo 3 of 24")
        XCTAssertEqual(HomeV2Copy.firstPhoto, "First photo")
    }

    func testCompactChangeNeverFallsBackToABareUnit() {
        XCTAssertEqual(HomeV2Copy.compactChange(delta: -0.9, unit: "pts"), "−0.9 pts")
        XCTAssertEqual(HomeV2Copy.compactChange(delta: 0.2, unit: ""), "+0.2")
        XCTAssertEqual(HomeV2Copy.compactChange(delta: 0.0, unit: "pts"), "No change")
        XCTAssertEqual(HomeV2Copy.compactChange(delta: nil, unit: "pts"), "No 30-day trend")
    }

    func testAspectFillCropCoversTheTargetAndCentersTheOverflow() {
        let tall = AspectFillCropper.fillRect(imageSize: CGSize(width: 400, height: 500), in: CGSize(width: 393, height: 439))
        XCTAssertEqual(tall.width, 393, accuracy: 0.01)
        XCTAssertEqual(tall.height, 491.25, accuracy: 0.01)
        XCTAssertEqual(tall.midY, 219.5, accuracy: 0.01)

        let wide = AspectFillCropper.fillRect(imageSize: CGSize(width: 1_000, height: 500), in: CGSize(width: 393, height: 491))
        XCTAssertEqual(wide.height, 491, accuracy: 0.01)
        XCTAssertEqual(wide.width, 982, accuracy: 0.01)
        XCTAssertEqual(wide.midX, 196.5, accuracy: 0.01)

        let cropped = AspectFillCropper.crop(UIImage(), to: CGSize(width: 40, height: 50))
        XCTAssertEqual(cropped.size, CGSize(width: 40, height: 50))
    }

    func testStageKeepsFourByFiveWhenItFitsAndGivesUpHeightOnShortScreens() {
        XCTAssertEqual(HomeV2Layout.stageHeight(width: 390, height: 760), 487.5, accuracy: 0.01)
        XCTAssertEqual(HomeV2Layout.stageHeight(width: 390, height: 700), 476, accuracy: 0.01)
        XCTAssertEqual(HomeV2Layout.stageHeight(width: 375, height: 470), 246, accuracy: 0.01)
        XCTAssertEqual(HomeV2Layout.stageHeight(width: 320, height: 300), 200, accuracy: 0.01)
    }

    func testFocusContractCopyReadsAsSentences() {
        XCTAssertEqual(HomeV2Copy.loggedSentence(value: "173.4", unit: "lb"), "Logged 173.4 lb for today")
        XCTAssertEqual(HomeV2Copy.latestPhotoCaption(date: "Sep 25"), "Latest photo · Sep 25")
        XCTAssertEqual(HomeV2Copy.phaseSentence(kind: .cutting, weeks: 9), "Cutting for 9 weeks.")
        XCTAssertEqual(HomeV2Copy.phaseSentence(kind: .gaining, weeks: 1), "Gaining for 1 week.")
        XCTAssertEqual(HomeV2Copy.phaseSentence(kind: .maintaining, weeks: 0), "Maintaining.")
        XCTAssertNil(HomeV2Copy.phaseSentence(kind: .insufficientData, weeks: 3), "No phase line before there is a trend")
        XCTAssertEqual(HomeV2Copy.displayUnit(.imperial), "lb")
        XCTAssertEqual(HomeV2Copy.displayUnit(.metric), "kg")
        XCTAssertEqual(HomeV2Copy.weightRangeError(unit: "lb"), "Enter a weight between 44 and 1100 lb.")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        var components = DateComponents()
        components.year = 2_026
        components.month = 9
        components.day = 26
        components.hour = 7
        components.minute = 2
        let date = Calendar.current.date(from: components) ?? Date()
        XCTAssertEqual(HomeV2Copy.todayDateText(date, formatter: formatter), "Today, 7:02 AM")
    }

    func testWeightStepsByATenthAndStaysInRange() {
        XCTAssertEqual(HomeV2WeightStepPolicy.stepped(173.4, by: 1, unit: "lb"), 173.5, accuracy: 0.001)
        XCTAssertEqual(HomeV2WeightStepPolicy.stepped(173.4, by: -1, unit: "lb"), 173.3, accuracy: 0.001)
        XCTAssertEqual(HomeV2WeightStepPolicy.stepped(44.0, by: -1, unit: "lb"), 44.0, accuracy: 0.001)
        XCTAssertEqual(HomeV2WeightStepPolicy.stepped(500.0, by: 1, unit: "kg"), 500.0, accuracy: 0.001)
        XCTAssertEqual(HomeV2WeightStepPolicy.text(173.44), "173.4")
        XCTAssertEqual(HomeV2WeightStepPolicy.parse("173,4"), 173.4)
        XCTAssertNil(HomeV2WeightStepPolicy.parse("heavy"))
        XCTAssertEqual(HomeV2WeightStepPolicy.clamped(9_999, unit: "lb"), 1_100, accuracy: 0.001)
        XCTAssertEqual(HomeV2WeightStepPolicy.defaultValue(unit: "kg"), 70, accuracy: 0.001)
    }

    func testPhaseWeeksCountConsecutiveWeeksMovingThePhasesWay() {
        let calendar = Calendar.current
        let now = Date()
        func metric(daysAgo: Int, weight: Double) -> BodyMetrics {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
            return BodyMetrics(
                id: "phase_\(daysAgo)",
                userId: "user",
                date: date,
                weight: weight,
                weightUnit: "kg",
                bodyFatPercentage: nil,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: nil,
                photoUrl: nil,
                dataSource: "manual",
                createdAt: date,
                updatedAt: date
            )
        }

        // Five weeks losing, then two weeks gaining before that: the cut is five weeks old.
        var metrics: [BodyMetrics] = []
        for week in 0..<5 {
            metrics.append(metric(daysAgo: week * 7 + 1, weight: 80 + Double(week) * 0.5))
        }
        metrics.append(metric(daysAgo: 36, weight: 81.5))
        metrics.append(metric(daysAgo: 43, weight: 80.5))
        XCTAssertEqual(HomeV2PhasePolicy.weeks(kind: .cutting, metrics: metrics), 5)
        XCTAssertEqual(HomeV2PhasePolicy.weeks(kind: .insufficientData, metrics: metrics), 0)
        XCTAssertEqual(HomeV2PhasePolicy.weeks(kind: .cutting, metrics: []), 0)
        XCTAssertEqual(HomeV2PhasePolicy.weeks(kind: .cutting, metrics: [metric(daysAgo: 0, weight: 80)]), 1)
    }
}
