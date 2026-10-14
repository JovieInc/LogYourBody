//
// HomeV2MetricEditorialTests.swift
// LogYourBodyTests
//
import XCTest
@testable import LogYourBody

/// Scale, gaps, and source copy for the shared Steps, Weight, Body fat, FFMI, and timeline hero.
final class HomeV2MetricEditorialTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private let locale = Locale(identifier: "en_US")

    func testEmptySeriesHasNoPlottedValueAndNoAxis() {
        let plotted = plot([], anchorsToZero: true)
        XCTAssertTrue(plotted.marks.isEmpty)
        XCTAssertTrue(plotted.runs.isEmpty)
        XCTAssertEqual(plotted.yDomain.lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(plotted.yDomain.upperBound, 1, accuracy: 0.001)
        XCTAssertTrue(plotted.xAxisDates.isEmpty)
        XCTAssertEqual(plotted.smoothing, "linear")

        let hero = stepsCanvas([], enough: false)
        XCTAssertEqual(hero.value, "—")
        XCTAssertEqual(hero.unit, "steps")
        XCTAssertEqual(hero.comparison, "No data in this range")
        XCTAssertFalse(hero.visibleLines.contains("Apple Health"))
    }

    func testOneSampleIsAPointWithoutALine() {
        let plotted = plot([sample(-3, 4_200)], anchorsToZero: true)
        XCTAssertEqual(plotted.runs.count, 1)
        XCTAssertEqual(plotted.runs.first?.count, 1)
        XCTAssertEqual(plotted.xAxisDates.count, 1)
        XCTAssertEqual(plotted.marks.first?.value ?? -1, 4_200, accuracy: 0.001)
        XCTAssertEqual(stepsCanvas([sample(-3, 4_200)], enough: false).comparison, "1 day of data in this range")
    }

    func testTwoAdjacentDaysShareOneRunAndAGapDoesNot() {
        let adjacent = plot([sample(-1, 100), sample(0, 140)], anchorsToZero: true)
        XCTAssertEqual(adjacent.runs.count, 1)
        XCTAssertEqual(adjacent.runs.first?.count, 2)

        let gap = plot([sample(-10, 100), sample(0, 140)], anchorsToZero: true)
        XCTAssertEqual(gap.runs.count, 2)
        XCTAssertTrue(gap.runs.allSatisfy { $0.count == 1 })
        XCTAssertEqual(gap.smoothing, "linear")
        XCTAssertEqual(
            stepsCanvas([sample(-10, 100), sample(0, 140)], enough: false).comparison,
            "2 days of data in this range"
        )
    }

    func testThirtyStepDaysKeepAZeroBaselineAndFullDateLabels() {
        let points = (0..<30).map { sample(-29 + $0, Double(5_000 + $0 * 80)) }
        let plotted = plot(points, anchorsToZero: true)
        XCTAssertEqual(plotted.runs.count, 1)
        XCTAssertEqual(plotted.runs.first?.count, 30)
        XCTAssertEqual(plotted.xAxisDates.count, 3)
        XCTAssertEqual(plotted.yDomain.lowerBound, 0, accuracy: 0.001)
        let peak = plotted.marks.map(\.value).max() ?? 0
        XCTAssertGreaterThan(plotted.yDomain.upperBound, peak)
        XCTAssertEqual(plotted.smoothing, "linear")

        let monthLabels = HomeV2ChartIntegrity.axisLabels(
            dates: plotted.xAxisDates, range: .month1, locale: locale, calendar: calendar
        )
        let allLabels = HomeV2ChartIntegrity.axisLabels(
            dates: plotted.xAxisDates, range: .all, locale: locale, calendar: calendar
        )
        XCTAssertEqual(monthLabels.count, 3)
        XCTAssertEqual(allLabels.count, 3)
        XCTAssertNotEqual(monthLabels, allLabels)
        for label in monthLabels + allLabels {
            XCTAssertFalse(label.contains("..."), label)
            XCTAssertFalse(label.contains("…"), label)
            XCTAssertTrue(label.contains(where: \.isNumber), label)
        }
        XCTAssertTrue(allLabels.allSatisfy { $0.contains("2026") })
        let lastLabel = monthLabels.last ?? ""
        XCTAssertEqual(lastLabel.filter(\.isLetter), "Oct")
        XCTAssertEqual(lastLabel.filter(\.isNumber), "14")

        let hero = stepsCanvas(points, enough: true, provenance: stepsProvenance)
        XCTAssertEqual(hero.unit, "steps")
        XCTAssertEqual(hero.value, "7,320")
        XCTAssertTrue(hero.comparison.contains("daily average"))
        XCTAssertFalse(hero.comparison.contains("Averaging"))
        let visible = hero.visibleLines.joined(separator: "\n")
        XCTAssertFalse(visible.contains("Apple Health"))
        XCTAssertFalse(visible.contains("Steps come from"))
        XCTAssertTrue(visible.contains("HealthKit"))
        XCTAssertTrue(stepsProvenance.body.contains("Apple Health"))
    }

    func testRangeSwitchKeepsTheStepsFloorAndFollowsVisibleData() {
        let history = (0..<60).map { sample(-59 + $0, Double(1_000 + $0)) }
        let now = date(0)
        let month = HomeV2TrendPolicy.points(history, in: .month1, now: now, calendar: calendar)
        let all = HomeV2TrendPolicy.points(history, in: .all, now: now, calendar: calendar)
        let monthPlot = plot(month, anchorsToZero: true)
        let allPlot = plot(all, anchorsToZero: true)
        XCTAssertEqual(monthPlot.yDomain.lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(allPlot.yDomain.lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(monthPlot.xAxisDates.count, 3)
        XCTAssertEqual(allPlot.xAxisDates.count, 3)
        XCTAssertLessThan(monthPlot.marks.count, allPlot.marks.count)
        XCTAssertEqual(monthPlot.smoothing, allPlot.smoothing)
    }

    func testGapsNegativesAndCarriedValuesStayHonest() {
        let hole = plot(
            [sample(-2, 8_000), sample(-1, 1, presence: .missing), sample(0, 7_500)],
            anchorsToZero: true
        )
        XCTAssertEqual(hole.droppedMissing, 1)
        XCTAssertEqual(hole.runs.count, 2)
        XCTAssertFalse(hole.marks.contains { $0.value == 1 })

        let negative = plot([sample(-1, -40), sample(0, 6_000)], anchorsToZero: true)
        XCTAssertEqual(negative.droppedNegative, 1)
        XCTAssertFalse(negative.marks.contains { $0.value <= 0 })
        XCTAssertEqual(negative.marks.map(\.value), [6_000])

        let zero = plot([sample(-1, 0), sample(0, 6_000)], anchorsToZero: true)
        XCTAssertEqual(zero.droppedNegative, 0)
        XCTAssertTrue(zero.marks.contains { $0.value == 0 })
        XCTAssertEqual(zero.yDomain.lowerBound, 0, accuracy: 0.001)

        let carried = [
            sample(-2, 10),
            sample(-1, 1, presence: .interpolated),
            sample(0, 12, presence: .lastKnown)
        ]
        let measured = plot(carried, anchorsToZero: false)
        XCTAssertEqual(measured.droppedCarried, 2)
        XCTAssertEqual(measured.marks.map(\.value), [10])
        let average = plot(carried, anchorsToZero: false, keepsCarriedValues: true)
        XCTAssertEqual(average.droppedCarried, 0)
        XCTAssertEqual(average.runs.count, 1)
        XCTAssertEqual(average.runs.first?.count, 3)
    }

    func testCarriedBodyMetricsDoNotBecomeHeroValuesOrTrendDays() {
        let points = [sample(-6, 18)] + (0..<6).map {
            sample(-5 + $0, Double(20 + $0), presence: $0 == 5 ? .lastKnown : .interpolated)
        }
        let observed = HomeV2MetricEditorial.observedPoints(points)
        XCTAssertEqual(observed.map(\.value), [18])
        XCTAssertFalse(HomeV2TrendPolicy.hasEnoughData(observed, calendar: calendar))
        XCTAssertEqual(plot(points, anchorsToZero: false).marks.map(\.value), [18])
        for metric in [HomeV2ProgressMetric.bodyFat, .ffmi] {
            let canvas = HomeV2MetricEditorial.canvas(HomeV2MetricCanvasRequest(
                metric: metric, points: points, unit: "", deltaUnit: "",
                range: .month1, provenance: nil, target: nil,
                hasEnoughData: HomeV2TrendPolicy.hasEnoughData(observed, calendar: calendar),
                formatValue: { String(format: "%.1f", $0) },
                dateText: { self.dayText($0) }, calendar: calendar
            ))
            XCTAssertEqual(canvas.value, "18.0")
            XCTAssertEqual(canvas.comparison, "1 day of data in this range")
            XCTAssertEqual(canvas.context.first { $0.id == "extreme" }?.value, "18.0")
        }
        let invalid = [sample(-3, -2), sample(-2, .nan), sample(-1, 1, presence: .missing),
                       sample(0, 19, presence: .estimated)]
        XCTAssertEqual(HomeV2MetricEditorial.observedPoints(invalid).map(\.value), [19])
    }

    func testMixedWeightSelectionUsesDailyValueAndLabelsAverageFallback() {
        let average = [sample(-1, 181), sample(0, 182, presence: .interpolated)]
        let raw = [sample(-1, 179)]
        let mixed = HomeV2ChartIntegrity.plot(
            points: average, dotPoints: raw,
            anchorsToZero: false, keepsCarriedValues: true,
            calendar: calendar
        )
        XCTAssertEqual(mixed.marks.count, 3)
        XCTAssertEqual(mixed.selectionSamples.count, 2)
        let daily = HomeV2ChartIntegrity.nearest(to: date(-1), in: mixed.selectionSamples)
        XCTAssertEqual(daily?.value, 179)
        XCTAssertEqual(daily?.kind, .daily)
        let fallback = HomeV2ChartIntegrity.nearest(to: date(0), in: mixed.selectionSamples)
        XCTAssertEqual(fallback?.value, 182)
        XCTAssertEqual(fallback?.kind, .sevenDayAverage)
        XCTAssertTrue(HomeV2ChartIntegrity.tooltip(
            date: date(0), valueText: "182.0", locale: locale,
            calendar: calendar, kind: .sevenDayAverage
        )
            .hasSuffix("7-day average"))
        XCTAssertTrue(HomeV2ChartIntegrity.tooltip(
            date: date(-1), valueText: "179.0", locale: locale,
            calendar: calendar, kind: .daily
        )
            .hasSuffix("Daily value"))
        // Equal raw/average values still retain provenance instead of deduplicating it away.
        let equal = HomeV2ChartIntegrity.plot(
            points: [sample(0, 180)], dotPoints: [sample(0, 180)],
            anchorsToZero: false, keepsCarriedValues: true,
            calendar: calendar
        )
        XCTAssertEqual(equal.marks.count, 2)
        XCTAssertEqual(equal.selectionSamples.first?.kind, .daily)
    }

    func testUnevenDatesRemainActualTimeAxisPositions() {
        let uneven = plot([sample(-13, 1), sample(-12, 2), sample(0, 3)], anchorsToZero: true)
        XCTAssertEqual(uneven.xAxisDates, [-13, -12, 0].map { calendar.startOfDay(for: date($0)) })
        let span = uneven.xAxisDates[2].timeIntervalSince(uneven.xAxisDates[0])
        let middleOffset = uneven.xAxisDates[1].timeIntervalSince(uneven.xAxisDates[0])
        XCTAssertEqual(middleOffset / span, 1.0 / 13.0, accuracy: 0.001)
        // Production passes these dates to native AxisValueLabel, never an equally spaced HStack.
    }

    func testWeightDomainLeavesRoomAboveZero() {
        let plotted = plot([sample(-4, 180), sample(0, 182)], anchorsToZero: false)
        XCTAssertGreaterThan(plotted.yDomain.lowerBound, 0)
        XCTAssertLessThan(plotted.yDomain.lowerBound, 180)
        XCTAssertGreaterThan(plotted.yDomain.upperBound, 182)
        XCTAssertFalse(plotted.anchorsToZero)
    }

    func testTooltipAndNearestSampleUseTheFullDate() {
        let plotted = plot([sample(-10, 1_000), sample(0, 7_544)], anchorsToZero: true)
        let text = HomeV2ChartIntegrity.tooltip(
            date: date(0), valueText: "7,544", locale: locale, calendar: calendar
        )
        let pieces = text.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertEqual(pieces.count, 3)
        XCTAssertEqual(pieces.first?.filter(\.isLetter) ?? "", "Oct")
        XCTAssertEqual(pieces.first?.filter(\.isNumber) ?? "", "14")
        XCTAssertEqual(pieces[1], "7,544")
        XCTAssertEqual(pieces.last ?? "", "Daily value")
        XCTAssertFalse(text.contains("..."))
        XCTAssertFalse(text.contains("…"))
        let nearer = HomeV2ChartIntegrity.nearest(to: date(-1), in: plotted.marks)
        XCTAssertEqual(nearer?.value ?? 0, 7_544, accuracy: 0.001)
        let midpoint = calendar.startOfDay(for: date(-5))
        let tie = HomeV2ChartIntegrity.nearest(to: midpoint, in: plotted.marks)
        XCTAssertEqual(tie?.value ?? 0, 1_000, accuracy: 0.001)
    }

    func testProvenanceChipIsTheOnlySourceOnTheCanvas() {
        let cases: [(String, String)] = [
            ("Apple Health", "HealthKit"),
            ("HealthKit", "HealthKit"),
            ("Withings", "Withings"),
            ("Estimated by your Withings", "Withings"),
            ("Typed", "Typed"),
            ("Entered by you", "Typed"),
            ("manual", "Typed"),
            ("BodySpec DEXA", "DEXA"),
            ("From your DEXA scan", "DEXA"),
            ("Visual estimate", "Estimate"),
            ("Estimated from weight, body fat and height", "Estimated"),
            ("Source not recorded", "Source"),
            ("", "Source")
        ]
        for (source, chip) in cases {
            XCTAssertEqual(HomeV2MetricEditorial.chip(for: source), chip, source)
            XCTAssertFalse(chip.contains("Apple Health"))
        }

        let steps = HomeV2MetricEditorial.progressProvenance(metric: .steps, bodyFatSource: nil)
        XCTAssertEqual(steps?.chip, "HealthKit")
        XCTAssertEqual(HomeV2MetricEditorial.progressProvenance(metric: .weight, bodyFatSource: nil), nil)
        let fat = HomeV2MetricEditorial.progressProvenance(metric: .bodyFat, bodyFatSource: "Withings")
        XCTAssertEqual(fat?.chip, "Withings")
        XCTAssertTrue(fat?.body.contains("Estimated by your Withings") == true)
        XCTAssertEqual(
            HomeV2MetricEditorial.progressProvenance(metric: .ffmi, bodyFatSource: nil)?.chip,
            "Estimated"
        )

        let hero = stepsCanvas([sample(0, 7_544)], enough: true, provenance: steps)
        XCTAssertEqual(hero.provenance?.chip, "HealthKit")
        XCTAssertFalse(hero.visibleLines.joined(separator: " ").contains(steps?.body ?? "Apple Health"))
        XCTAssertEqual(hero.context.first { $0.id == "target" }?.label, "Target · Daily goal")
    }

    func testTimelineProvenanceCollapsesToOneChip() {
        let health = entry(source: "healthkit", weight: 82.1, bodyFat: 15.8, method: "visual_estimate")
        let mixed = HomeV2MetricEditorial.timelineProvenance(for: health)
        XCTAssertEqual(mixed?.chip, "Sources")
        XCTAssertTrue(mixed?.body.contains("Apple Health") == true)
        XCTAssertTrue(mixed?.body.contains("Visual estimate") == true)

        let typed = entry(source: "manual", weight: 82.1, bodyFat: nil, method: nil)
        XCTAssertEqual(HomeV2MetricEditorial.timelineProvenance(for: typed)?.chip, "Typed")
        XCTAssertEqual(
            HomeV2MetricEditorial.timelineProvenance(for: entry(source: "manual", weight: nil, bodyFat: nil, method: nil)),
            nil
        )
        XCTAssertEqual(HomeV2MetricEditorial.compositionLine(percentage: 15.8), "Body fat 15.8%")
        let weightHero = weightCanvas([sample(-20, 180), sample(0, 182)], enough: true)
        XCTAssertEqual(weightHero.comparison, "Up 2.0 lb in 3 months")
        XCTAssertEqual(weightHero.context.first { $0.id == "extreme" }?.label.hasPrefix("Low"), true)
        XCTAssertFalse(weightHero.visibleLines.contains("HealthKit"))
    }

    private var stepsProvenance: HomeV2ProvenanceDetail {
        HomeV2MetricEditorial.progressProvenance(metric: .steps, bodyFatSource: nil)
            ?? HomeV2ProvenanceDetail(chip: "HealthKit", title: "Steps", body: "")
    }

    private func stepsCanvas(
        _ points: [MetricChartDataPoint],
        enough: Bool,
        provenance: HomeV2ProvenanceDetail? = nil
    ) -> HomeV2MetricEditorial.Canvas {
        withUSLocale {
            HomeV2MetricEditorial.canvas(
                HomeV2MetricCanvasRequest(
                    metric: .steps,
                    points: points,
                    unit: "",
                    deltaUnit: "",
                    range: .month1,
                    provenance: provenance,
                    target: 10_000,
                    hasEnoughData: enough,
                    formatValue: { FormatterCache.formattedSteps($0) ?? "—" },
                    dateText: { self.dayText($0) },
                    calendar: self.calendar
                )
            )
        }
    }

    private func weightCanvas(
        _ points: [MetricChartDataPoint],
        enough: Bool
    ) -> HomeV2MetricEditorial.Canvas {
        HomeV2MetricEditorial.canvas(
            HomeV2MetricCanvasRequest(
                metric: .weight,
                points: points,
                unit: "lb",
                deltaUnit: "lb",
                range: .month3,
                provenance: nil,
                target: nil,
                hasEnoughData: enough,
                formatValue: { String(format: "%.1f", $0) },
                dateText: { self.dayText($0) },
                calendar: self.calendar
            )
        )
    }

    private func withUSLocale<T>(_ body: () -> T) -> T {
        let formatter = FormatterCache.stepsFormatter
        let original = formatter.locale
        formatter.locale = locale
        defer { formatter.locale = original }
        return body()
    }

    private func plot(
        _ points: [MetricChartDataPoint],
        anchorsToZero: Bool,
        keepsCarriedValues: Bool = false
    ) -> HomeV2ChartIntegrity.Plot {
        HomeV2ChartIntegrity.plot(
            points: points,
            anchorsToZero: anchorsToZero,
            keepsCarriedValues: keepsCarriedValues,
            calendar: calendar
        )
    }

    private func sample(
        _ dayOffset: Int,
        _ value: Double,
        presence: MetricPresence = .present
    ) -> MetricChartDataPoint {
        MetricChartDataPoint(date: date(dayOffset), value: value, presence: presence)
    }

    private func date(_ dayOffset: Int) -> Date {
        var parts = DateComponents()
        parts.year = 2_026
        parts.month = 10
        parts.day = 14 + dayOffset
        parts.hour = 12
        parts.timeZone = calendar.timeZone
        return calendar.date(from: parts) ?? Date(timeIntervalSince1970: 0)
    }

    private func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    private func entry(
        source: String,
        weight: Double?,
        bodyFat: Double?,
        method: String?
    ) -> BodyMetrics {
        let day = date(0)
        return BodyMetrics(
            id: "editorial",
            userId: "editorial",
            date: day,
            weight: weight,
            weightUnit: "kg",
            bodyFatPercentage: bodyFat,
            bodyFatMethod: method,
            muscleMass: nil,
            boneMass: nil,
            notes: nil,
            photoUrl: nil,
            dataSource: source,
            createdAt: day,
            updatedAt: day
        )
    }
}
