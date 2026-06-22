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


final class Glp1DoseHistoryFormatterTests: XCTestCase {
    func testDoseTextRemovesUnneededDecimalZeros() {
        let log = makeDoseLog(amount: 2.50, unit: "mg/week")

        XCTAssertEqual(Glp1DoseHistoryFormatter.doseText(log), "2.5 mg/week")
    }

    func testDateTextUsesPlainRelativeLabelsForRecentDoses() {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let now = calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2_026,
            month: 6,
            day: 16,
            hour: 12
        ))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        XCTAssertEqual(Glp1DoseHistoryFormatter.dateText(now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(Glp1DoseHistoryFormatter.dateText(yesterday, now: now, calendar: calendar), "Yesterday")
    }

    func testDoseTextShowsRestDayForNoDoseRestLog() {
        let log = makeDoseLog(amount: nil, unit: nil, notes: "Rest day: traveling")

        XCTAssertEqual(Glp1DoseHistoryFormatter.doseText(log), "Rest day")
        XCTAssertTrue(Glp1DoseHistoryFormatter.isRestDay(log))
    }

    private func makeDoseLog(amount: Double?, unit: String?, notes: String? = nil) -> Glp1DoseLog {
        let now = Date()

        return Glp1DoseLog(
            id: "dose",
            userId: "glp1-user",
            takenAt: now,
            medicationId: "medication",
            doseAmount: amount,
            doseUnit: unit,
            drugClass: "dual GIP/GLP-1 receptor agonist",
            brand: "Zepbound",
            isCompounded: false,
            supplierType: nil,
            supplierName: nil,
            notes: notes,
            createdAt: now,
            updatedAt: now
        )
    }
}
