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


final class Glp1WeeklyCheckInPolicyTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()

        calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testWeeklyCheckInShowsByDefaultForV1Launch() {
        XCTAssertTrue(Glp1WeeklyCheckInPolicy.defaultShowsWeeklyCheckIn)
        XCTAssertTrue(Glp1WeeklyCheckInPolicy.shouldShowWeeklyCheckIn())
    }

    func testSetupStateWhenNoDoseExists() {
        let medication = makeMedication(startedAt: makeDate(year: 2_026, month: 1, day: 1))

        let summary = Glp1WeeklyCheckInPolicy.summary(
            medications: [medication],
            doseLogs: [],
            now: makeDate(year: 2_026, month: 1, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(summary.status, .setup)
        XCTAssertEqual(summary.title, "Weekly GLP-1 check-in")
        XCTAssertEqual(summary.actionTitle, "Set up")
        XCTAssertEqual(summary.medicationName, "Zepbound")
        XCTAssertNil(summary.daysSinceLastDose)
    }

    func testDueStateUsesLastLoggedDoseWithoutMedicalAdvice() {
        let medication = makeMedication(startedAt: makeDate(year: 2_026, month: 1, day: 1))
        let log = makeDoseLog(takenAt: makeDate(year: 2_026, month: 1, day: 1))

        let summary = Glp1WeeklyCheckInPolicy.summary(
            medications: [medication],
            doseLogs: [log],
            now: makeDate(year: 2_026, month: 1, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(summary.status, .due)
        XCTAssertEqual(summary.title, "Weekly GLP-1 check-in")
        XCTAssertEqual(summary.latestDoseText, "5.0 mg/week")
        XCTAssertEqual(summary.daysSinceLastDose, 9)
        XCTAssertTrue(summary.message.contains("Zepbound was last logged 9 days ago"))
        XCTAssertFalse(summary.message.lowercased().contains("take"))
        XCTAssertFalse(summary.message.lowercased().contains("inject"))
    }

    func testLoggedStateWhenDoseWasRecordedThisWeek() {
        let medication = makeMedication(startedAt: makeDate(year: 2_026, month: 1, day: 1))
        let log = makeDoseLog(takenAt: makeDate(year: 2_026, month: 1, day: 8))

        let summary = Glp1WeeklyCheckInPolicy.summary(
            medications: [medication],
            doseLogs: [log],
            now: makeDate(year: 2_026, month: 1, day: 10),
            calendar: calendar
        )

        XCTAssertEqual(summary.status, .logged)
        XCTAssertEqual(summary.title, "GLP-1 checked in")
        XCTAssertEqual(summary.actionTitle, "Log dose")
        XCTAssertEqual(summary.daysSinceLastDose, 2)
        XCTAssertTrue(summary.message.contains("2 days ago"))
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }

    private func makeMedication(startedAt: Date) -> Glp1Medication {
        Glp1Medication(
            id: "medication",
            userId: "glp1-user",
            displayName: "Zepbound",
            genericName: "tirzepatide",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            route: "subcutaneous",
            frequency: "once weekly",
            doseUnit: "mg/week",
            isCompounded: false,
            hkIdentifier: "hk.glp1.tirzepatide.zepbound.weekly",
            startedAt: startedAt,
            endedAt: nil,
            notes: nil,
            createdAt: startedAt,
            updatedAt: startedAt
        )
    }

    private func makeDoseLog(takenAt: Date) -> Glp1DoseLog {
        Glp1DoseLog(
            id: "dose",
            userId: "glp1-user",
            takenAt: takenAt,
            medicationId: "medication",
            doseAmount: 5.0,
            doseUnit: "mg/week",
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: nil,
            createdAt: takenAt,
            updatedAt: takenAt
        )
    }
}
