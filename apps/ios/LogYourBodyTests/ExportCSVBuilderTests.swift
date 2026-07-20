import XCTest
@testable import LogYourBody

final class ExportCSVBuilderTests: XCTestCase {
    // MARK: - Deterministic fixtures

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else {
            XCTFail("Failed to build date \(year)-\(month)-\(day)")
            return Date(timeIntervalSince1970: 0)
        }
        return date
    }

    private func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .short
        return formatter
    }

    private func makeMetric(
        id: String,
        date: Date,
        weight: Double? = nil,
        weightUnit: String? = nil,
        bodyFatPercentage: Double? = nil,
        muscleMass: Double? = nil,
        boneMass: Double? = nil,
        notes: String? = nil,
        photoUrl: String? = nil
    ) -> BodyMetrics {
        BodyMetrics(
            id: id,
            userId: "user-1",
            date: date,
            weight: weight,
            weightUnit: weightUnit,
            bodyFatPercentage: bodyFatPercentage,
            bodyFatMethod: nil,
            muscleMass: muscleMass,
            boneMass: boneMass,
            notes: notes,
            photoUrl: photoUrl,
            dataSource: "manual",
            createdAt: date,
            updatedAt: date
        )
    }

    private func rows(of csv: String) -> [String] {
        csv.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    // MARK: - Body metrics CSV

    func testBodyMetricsEmptyStoreProducesHeaderOnly() {
        let csv = ExportCSVBuilder.makeBodyMetricsCSV(
            metrics: [],
            heightInches: nil,
            dateFormatter: makeFormatter()
        )

        XCTAssertEqual(
            csv,
            "Date,Weight,Weight Unit,Body Fat %,FFMI,Muscle Mass,Bone Mass,Notes,Photo URL\n"
        )
    }

    func testBodyMetricsRowsSortAscendingByDate() {
        let jan5 = makeDate(2_024, 1, 5)
        let mar10 = makeDate(2_024, 3, 10)
        let feb20 = makeDate(2_024, 2, 20)
        let metrics = [
            makeMetric(id: "march", date: mar10, weight: 180.0, weightUnit: "lbs"),
            makeMetric(id: "january", date: jan5, weight: 185.0, weightUnit: "lbs"),
            makeMetric(id: "february", date: feb20, weight: 182.5, weightUnit: "lbs")
        ]

        let csv = ExportCSVBuilder.makeBodyMetricsCSV(
            metrics: metrics,
            heightInches: nil,
            dateFormatter: makeFormatter()
        )

        let lines = rows(of: csv)
        XCTAssertEqual(lines.count, 4)
        XCTAssertEqual(lines[1], "1/5/24,185.0,lbs,0.0,0.0,0.0,0.0,\"\",")
        XCTAssertEqual(lines[2], "2/20/24,182.5,lbs,0.0,0.0,0.0,0.0,\"\",")
        XCTAssertEqual(lines[3], "3/10/24,180.0,lbs,0.0,0.0,0.0,0.0,\"\",")
    }

    func testBodyMetricsRowRendersAllColumnsAndUnits() {
        let metric = makeMetric(
            id: "full",
            date: makeDate(2_024, 1, 5),
            weight: 80.25,
            weightUnit: "kg",
            bodyFatPercentage: 21.5,
            muscleMass: 60.5,
            boneMass: 3.1,
            notes: "Felt strong",
            photoUrl: "https://example.com/photo.jpg"
        )

        let csv = ExportCSVBuilder.makeBodyMetricsCSV(
            metrics: [metric],
            heightInches: nil,
            dateFormatter: makeFormatter()
        ) { _, _ in 22.4 }

        XCTAssertEqual(
            rows(of: csv).last,
            "1/5/24,80.25,kg,21.5,22.4,60.5,3.1,\"Felt strong\",https://example.com/photo.jpg"
        )
    }

    func testBodyMetricsDefaultsMissingWeightAndUnitToZeroAndLbs() {
        let metric = makeMetric(id: "sparse", date: makeDate(2_024, 1, 5))

        let csv = ExportCSVBuilder.makeBodyMetricsCSV(
            metrics: [metric],
            heightInches: nil,
            dateFormatter: makeFormatter()
        )

        XCTAssertEqual(rows(of: csv).last, "1/5/24,0.0,lbs,0.0,0.0,0.0,0.0,\"\",")
    }

    func testBodyMetricsFFMIIsZeroWhenHeightUnavailable() {
        let metric = makeMetric(
            id: "no-height",
            date: makeDate(2_024, 1, 5),
            weight: 180.0,
            weightUnit: "lbs",
            bodyFatPercentage: 20.0
        )

        let csv = ExportCSVBuilder.makeBodyMetricsCSV(
            metrics: [metric],
            heightInches: nil,
            dateFormatter: makeFormatter()
        )

        XCTAssertEqual(rows(of: csv).last, "1/5/24,180.0,lbs,20.0,0.0,0.0,0.0,\"\",")
    }

    func testBodyMetricsFFMINilFromProviderBecomesZero() {
        let metric = makeMetric(
            id: "nil-ffmi",
            date: makeDate(2_024, 1, 5),
            weight: 180.0,
            weightUnit: "lbs",
            bodyFatPercentage: 20.0
        )

        let csv = ExportCSVBuilder.makeBodyMetricsCSV(
            metrics: [metric],
            heightInches: 70,
            dateFormatter: makeFormatter()
        ) { _, _ in nil }

        XCTAssertEqual(rows(of: csv).last, "1/5/24,180.0,lbs,20.0,0.0,0.0,0.0,\"\",")
    }

    func testBodyMetricsNotesContainingCommaStayInsideQuotedField() {
        let metric = makeMetric(
            id: "comma-notes",
            date: makeDate(2_024, 1, 5),
            notes: "Felt strong, slept well"
        )

        let csv = ExportCSVBuilder.makeBodyMetricsCSV(
            metrics: [metric],
            heightInches: nil,
            dateFormatter: makeFormatter()
        )

        XCTAssertEqual(rows(of: csv).count, 2)
        XCTAssertEqual(
            rows(of: csv).last,
            "1/5/24,0.0,lbs,0.0,0.0,0.0,0.0,\"Felt strong, slept well\","
        )
    }

    // MARK: - Daily logs CSV

    func testDailyLogsEmptyStoreProducesHeaderOnly() {
        let csv = ExportCSVBuilder.makeDailyLogsCSV(logs: [], dateFormatter: makeFormatter())

        XCTAssertEqual(csv, "Date,Weight,Weight Unit,Steps,Notes\n")
    }

    func testDailyLogsRowsSortAscendingAndRenderValues() {
        let jan5 = makeDate(2_024, 1, 5)
        let jan3 = makeDate(2_024, 1, 3)
        let logs = [
            DailyLog(id: "later", userId: "user-1", date: jan5, weight: 75.5, weightUnit: "kg", stepCount: 8_200),
            DailyLog(
                id: "earlier",
                userId: "user-1",
                date: jan3,
                weight: 76.0,
                weightUnit: "kg",
                stepCount: 10_050,
                notes: "Morning"
            )
        ]

        let csv = ExportCSVBuilder.makeDailyLogsCSV(logs: logs, dateFormatter: makeFormatter())

        let lines = rows(of: csv)
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[1], "1/3/24,76.0,kg,10050,\"Morning\"")
        XCTAssertEqual(lines[2], "1/5/24,75.5,kg,8200,\"\"")
    }

    func testDailyLogsDefaultsMissingValues() {
        let log = DailyLog(id: "sparse", userId: "user-1", date: makeDate(2_024, 1, 5))

        let csv = ExportCSVBuilder.makeDailyLogsCSV(logs: [log], dateFormatter: makeFormatter())

        XCTAssertEqual(rows(of: csv).last, "1/5/24,0.0,,0,\"\"")
    }
}
