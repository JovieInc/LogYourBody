//
// HomeV2PhotoJourneyPolicyTests.swift
// LogYourBodyTests
//
import UIKit
import XCTest
@testable import LogYourBody

final class HomeV2PhotoJourneyPolicyTests: XCTestCase {
    private func rulerCalendar(timeZoneID: String = "UTC") throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZoneID))
        return calendar
    }

    private func rulerDate(
        year: Int = 2_026, month: Int, day: Int, hour: Int = 0, calendar: Calendar
    ) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    func testCopyReadsAsTheDesignWrites() {
        XCTAssertEqual(HomeV2PhotoCopy.compareTitle(days: 176), "Compare · 176 days")
        XCTAssertEqual(HomeV2PhotoCopy.compareTitle(days: 1), "Compare · 1 day")
        XCTAssertEqual(HomeV2PhotoCopy.cardHeadline(delta: -12.8, unit: "lb", days: 176), "−12.8 lb in 176 days")
        XCTAssertEqual(HomeV2PhotoCopy.cardHeadline(delta: 0.3, unit: "kg", days: 30), "+0.3 kg in 30 days")
        XCTAssertEqual(HomeV2PhotoCopy.cardHeadline(delta: 0.01, unit: "lb", days: 3), "No change in 3 days")
        XCTAssertEqual(HomeV2PhotoCopy.bodyFatDeltaLine(-7.2), "Est. body fat −7.2 pts")
        XCTAssertNil(HomeV2PhotoCopy.bodyFatDeltaLine(nil))
        XCTAssertEqual(HomeV2PhotoCopy.bodyFatTransition(from: 21.4, to: 14.2), "Body fat: 21.4% → 14.2%")
        XCTAssertEqual(HomeV2PhotoCopy.playbackSummary(speed: 1, loops: false), "Playback · 1× · Loop off")
        XCTAssertEqual(HomeV2PhotoCopy.playbackSummary(speed: 0.5, loops: true), "Playback · 0.5× · Loop on")
        XCTAssertEqual(HomeV2PhotoCopy.photoDetails(weight: "173.4 lb"), "Photo details · 173.4 lb")
        XCTAssertEqual(HomeV2PhotoCopy.timelapseSubtitle(from: "Apr 2", to: "Sep 25", count: 24), "Apr 2 to Sep 25, 24 photos")
        XCTAssertEqual(HomeV2PhotoCopy.bodyFatChange(-7.2), "Body fat · −7.2 pts")
        XCTAssertEqual(HomeV2PhotoCopy.bodyFatChange(0.0), "Body fat · no change")
        XCTAssertEqual(HomeV2PhotoCopy.estimatedBySource(HomeV2ContextCopy.typed), "Body fat estimate entered by you.")
        XCTAssertEqual(HomeV2PhotoCopy.estimatedBySource("scale"), "Body fat estimated by your scale.")
    }

    func testRulerSpansAtLeastEightWeeksAndFindsTheNearestPhoto() throws {
        let calendar = try rulerCalendar()
        let latest = try rulerDate(month: 10, day: 10, calendar: calendar)
        let dates = try [20, 10, 0].map {
            try XCTUnwrap(calendar.date(byAdding: .day, value: -$0, to: latest))
        }
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        XCTAssertEqual(span.start, calendar.date(byAdding: .day, value: -56, to: latest))
        XCTAssertEqual(span.end, latest)
        XCTAssertEqual(calendar.dateComponents([.day], from: span.start, to: span.end).day, 56)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.fraction(of: latest, in: span), 1, accuracy: 0.001)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: 0, dates: dates, span: span), 0)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: 1, dates: dates, span: span), 2)
        XCTAssertNil(HomeV2PhotoRulerPolicy.nearestIndex(to: 0.5, dates: [], span: span))
        XCTAssertGreaterThanOrEqual(HomeV2PhotoRulerPolicy.weekTicks(in: span, calendar: calendar).count, 8)
        XCTAssertFalse(HomeV2PhotoRulerPolicy.monthStarts(in: span, calendar: calendar).isEmpty)
    }

    func testSingleReadingRulerEndsAtItsTimestampWithoutFutureMonthLabels() throws {
        let calendar = try rulerCalendar()
        let reading = try rulerDate(month: 10, day: 10, hour: 15, calendar: calendar)
        let span = HomeV2PhotoRulerPolicy.span(for: [reading], calendar: calendar)
        XCTAssertEqual(span.end, reading)
        XCTAssertEqual(span.start, try rulerDate(month: 8, day: 15, calendar: calendar))
        XCTAssertEqual(HomeV2PhotoRulerPolicy.fraction(of: reading, in: span), 1)
        let months = HomeV2PhotoRulerPolicy.monthStarts(in: span, calendar: calendar)
        XCTAssertEqual(months.map { calendar.component(.month, from: $0) }, [9, 10])
        XCTAssertTrue(months.allSatisfy { $0 <= reading })
        XCTAssertTrue(HomeV2PhotoRulerPolicy.weekTicks(in: span, calendar: calendar).allSatisfy { $0 <= reading })
        for fraction: CGFloat in [0, 0.5, 1] {
            XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: fraction, dates: [reading], span: span), 0)
        }
    }

    func testTwoReadingRulerPadsBackwardAndKeepsBothSelectableAcrossNewYear() throws {
        let calendar = try rulerCalendar()
        let first = try rulerDate(month: 12, day: 28, hour: 9, calendar: calendar)
        let latest = try rulerDate(year: 2_027, month: 1, day: 5, hour: 18, calendar: calendar)
        let dates = [first, latest]
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        XCTAssertEqual(span.end, latest)
        XCTAssertLessThan(span.start, first)
        XCTAssertEqual(calendar.dateComponents([.day], from: span.start, to: span.end).day, 56)
        for (index, date) in dates.enumerated() {
            let fraction = HomeV2PhotoRulerPolicy.fraction(of: date, in: span)
            XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: fraction, dates: dates, span: span), index)
        }
        XCTAssertTrue(HomeV2PhotoRulerPolicy.monthStarts(in: span, calendar: calendar).allSatisfy { $0 <= latest })
    }

    func testLongRulerPreservesTheEarliestDayAndExactLatestTimestamp() throws {
        let calendar = try rulerCalendar()
        let first = try rulerDate(month: 1, day: 12, hour: 8, calendar: calendar)
        let latest = try rulerDate(month: 10, day: 10, hour: 20, calendar: calendar)
        let span = HomeV2PhotoRulerPolicy.span(for: [latest, first], calendar: calendar)
        XCTAssertEqual(span.start, calendar.startOfDay(for: first))
        XCTAssertEqual(span.end, latest)
        XCTAssertGreaterThan(calendar.dateComponents([.day], from: span.start, to: span.end).day ?? 0, 56)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: 0, dates: [first, latest], span: span), 0)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: 1, dates: [first, latest], span: span), 1)
    }

    func testSameDayRulerPreservesDistinctTimestampPositions() throws {
        let calendar = try rulerCalendar()
        let morning = try rulerDate(month: 10, day: 10, hour: 8, calendar: calendar)
        let evening = try rulerDate(month: 10, day: 10, hour: 20, calendar: calendar)
        let dates = [morning, evening]
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        let first = HomeV2PhotoRulerPolicy.fraction(of: morning, in: span)
        let last = HomeV2PhotoRulerPolicy.fraction(of: evening, in: span)
        XCTAssertLessThan(first, last)
        XCTAssertEqual(last, 1)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: first, dates: dates, span: span), 0)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: last, dates: dates, span: span), 1)
    }

    func testRulerMinimumUsesCalendarDaysAcrossBothDaylightSavingTransitions() throws {
        let calendar = try rulerCalendar(timeZoneID: "America/Los_Angeles")
        for month in [3, 11] {
            let latest = try rulerDate(month: month, day: 20, hour: 12, calendar: calendar)
            let span = HomeV2PhotoRulerPolicy.span(for: [latest], calendar: calendar)
            let padded = try XCTUnwrap(calendar.date(byAdding: .day, value: -56, to: latest))
            XCTAssertEqual(span.start, calendar.startOfDay(for: padded))
            XCTAssertEqual(span.end, latest)
            XCTAssertEqual(calendar.dateComponents([.day], from: span.start, to: span.end).day, 56)
            XCTAssertEqual(calendar.component(.hour, from: span.start), 0)
            let offsetChange = calendar.timeZone.secondsFromGMT(for: latest) -
                calendar.timeZone.secondsFromGMT(for: span.start)
            XCTAssertNotEqual(offsetChange, 0, "Each fixture must actually cross a DST transition")
            XCTAssertEqual(span.duration, Double(56 * 86_400 + 12 * 3_600 - offsetChange), accuracy: 0.001)
        }
    }

    func testEmptyRulerEndsAtTheSuppliedNowWithoutSelectableRecords() throws {
        let calendar = try rulerCalendar()
        let now = try rulerDate(month: 10, day: 10, hour: 15, calendar: calendar)
        let span = HomeV2PhotoRulerPolicy.span(for: [], calendar: calendar, now: now)
        XCTAssertEqual(span.end, now)
        XCTAssertEqual(span.start, try rulerDate(month: 8, day: 15, calendar: calendar))
        XCTAssertNil(HomeV2PhotoRulerPolicy.nearestIndex(to: 1, dates: [], span: span))
    }

    func testTimelapseAdvancesAndStopsOrLoops() {
        XCTAssertEqual(HomeV2TimelapsePolicy.next(after: 0, count: 3, loops: false), 1)
        XCTAssertNil(HomeV2TimelapsePolicy.next(after: 2, count: 3, loops: false))
        XCTAssertEqual(HomeV2TimelapsePolicy.next(after: 2, count: 3, loops: true), 0)
        XCTAssertNil(HomeV2TimelapsePolicy.next(after: 0, count: 0, loops: true))
        XCTAssertEqual(HomeV2TimelapsePolicy.frameInterval(speed: 2), 0.3, accuracy: 0.001)
        XCTAssertEqual(HomeV2TimelapsePolicy.frameInterval(speed: 0.5), 1.2, accuracy: 0.001)
    }

    func testEveryToolNamesItsDestination() {
        for tool in HomeV2PhotoTool.allCases {
            XCTAssertFalse(tool.title.isEmpty)
            XCTAssertFalse(tool.systemImage.isEmpty)
            XCTAssertFalse(tool.identifier.isEmpty)
        }
        XCTAssertEqual(HomeV2PhotoPair(before: 2, after: 5).id, "2-5")
    }

    func testMissingMeasurementsDoNotClaimNoChange() {
        for delta: Double? in [nil, .nan, .infinity, -.infinity] {
            XCTAssertEqual(
                HomeV2PhotoCopy.cardHeadline(delta: delta, unit: "lb", days: 30),
                "Weight change unavailable"
            )
            XCTAssertEqual(HomeV2PhotoCopy.bodyFatChange(delta), "Body fat · no comparison")
        }
        XCTAssertEqual(HomeV2PhotoCopy.cardHeadline(delta: 0, unit: "lb", days: 30), "No change in 30 days")
        XCTAssertEqual(HomeV2PhotoCopy.bodyFatChange(0), "Body fat · no change")
    }

    func testShareCropCoversTheWholePaneAndRemovesTheTop() {
        let pane = CGSize(width: 154, height: 329)
        for imageSize in [CGSize(width: 400, height: 500), CGSize(width: 1_000, height: 500)] {
            let rect = HomeV2ShareCropPolicy.drawRect(imageSize: imageSize, in: pane, cropsTop: true)
            XCTAssertLessThanOrEqual(rect.minX, 0)
            XCTAssertLessThanOrEqual(rect.minY, 0)
            XCTAssertGreaterThanOrEqual(rect.maxX, pane.width)
            XCTAssertGreaterThanOrEqual(rect.maxY, pane.height)
            let croppedTop = rect.minY + rect.height * HomeV2ShareCropPolicy.topFraction
            XCTAssertLessThanOrEqual(croppedTop, 0.001, "The removed top must be outside the rendered pane")
        }
    }

    @MainActor
    func testRenderedShareCropHasNoTopStripeOrEmptyBottom() throws {
        let size = CGSize(width: 100, height: 100)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let source = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 22))
        }
        let crop = HomeV2ShareCropper.crop(source, to: size, cropsTop: true)
        let image = try XCTUnwrap(crop.cgImage)
        var pixels = [UInt8](repeating: 0, count: 100 * 100 * 4)
        let context = try XCTUnwrap(CGContext(
            data: &pixels, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(origin: .zero, size: size))
        for row in [0, 50, 99] {
            let offset = (row * 100 + 50) * 4
            XCTAssertEqual(pixels[offset], 0, "No red top stripe should survive the crop")
            XCTAssertEqual(pixels[offset + 2], 255, "The photo must cover the top, middle and bottom")
            XCTAssertEqual(pixels[offset + 3], 255, "The pane must have no transparent gap")
        }
    }

    func testPairToolsExplainInsufficientPhotosAndKeepNormalRoutes() throws {
        let rows = [routeMetric("new", day: 7), routeMetric("old", day: 0)]
        let receipt = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
        let publication = try XCTUnwrap(HomeV2PhotoRoute.Publication(
            metrics: rows, selectedPhoto: .init(rows[0]), ownership: receipt
        ))
        let pair = HomeV2PhotoPair(before: 1, after: 0)
        let bound = try XCTUnwrap(publication.bind(pair))
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .compare, pair: nil, publication: publication)?.destination,
                       .insufficientPhotos(.compare))
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .share, pair: nil, publication: publication)?.destination,
                       .insufficientPhotos(.share))
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .compare, pair: pair, publication: publication)?.destination,
                       .compare(bound))
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .share, pair: pair, publication: publication)?.destination,
                       .share(bound))
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .allPhotos, pair: nil, publication: publication)?.destination,
                       .allPhotos)
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .timelapse, pair: nil, publication: publication)?.destination,
                       .timelapse)
        XCTAssertNil(HomeV2PhotoRoute.destination(for: .timeline, pair: nil, publication: publication))
        XCTAssertNil(HomeV2PhotoRoute.destination(for: .share, pair: .init(before: 0, after: 0), publication: publication))
    }

    @MainActor
    func testShareLoadingFailureCanRetrySuccessfully() async {
        let loader = HomeV2SharePhotoLoader()
        let image = UIImage()
        await loader.load(beforeURL: "before", afterURL: "after", plate: { url in
            url == "before" ? nil : image
        })
        XCTAssertEqual(loader.state, .failed)
        XCTAssertNil(loader.beforePlate)
        await loader.load(beforeURL: "before", afterURL: "after", plate: { _ in image })
        XCTAssertEqual(loader.state, .ready)
        XCTAssertTrue(loader.beforePlate === image)
        XCTAssertTrue(loader.afterPlate === image)
        await loader.load(beforeURL: nil, afterURL: "after", plate: { _ in image })
        XCTAssertEqual(loader.state, .failed)
        XCTAssertNil(loader.beforePlate, "A different pair cannot reuse the previous share image")
        XCTAssertNil(loader.afterPlate)
    }

    @MainActor
    func testSupersededShareLoadCannotReplaceTheCurrentPair() async {
        let loader = HomeV2SharePhotoLoader()
        let oldImage = UIImage()
        let currentImage = UIImage()
        var resumeOld: CheckedContinuation<UIImage?, Never>?
        let oldTask = Task {
            await loader.load(beforeURL: "old-before", afterURL: "old-after", plate: { _ in
                await withCheckedContinuation { resumeOld = $0 }
            })
        }
        while resumeOld == nil { await Task.yield() }
        await loader.load(beforeURL: "new-before", afterURL: "new-after", plate: { _ in currentImage })
        resumeOld?.resume(returning: oldImage)
        await oldTask.value
        XCTAssertEqual(loader.state, .ready)
        XCTAssertTrue(loader.beforePlate === currentImage)
        XCTAssertTrue(loader.afterPlate === currentImage)
    }

    func testPhotoRoutePublicationKeepsActualPairAcrossReorderAndInsertion() throws {
        let selected = routeMetric("selected", day: 7)
        let older = routeMetric("older", day: 0)
        let receipt = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
        let publication = try XCTUnwrap(HomeV2PhotoRoute.Publication(
            metrics: [selected, older], selectedPhoto: .init(selected), ownership: receipt
        ))
        let indices = try XCTUnwrap(publication.defaultPair)
        let ids = try XCTUnwrap(publication.bind(indices))
        let changedOrder = [older, routeMetric("new-arrival", day: 14), selected]
        XCTAssertTrue(publication.admits(ownership: receipt, metrics: changedOrder))
        XCTAssertEqual(ids.before, .init(older))
        XCTAssertEqual(ids.after, .init(selected))
        XCTAssertEqual(publication.indices(for: ids), indices)
        XCTAssertEqual(publication.metrics[indices.after], selected)
        XCTAssertNotEqual(changedOrder[indices.after].id, selected.id,
                          "The old integer would point elsewhere in live order; rendering must use captured rows")
    }

    func testPhotoRoutePublicationRejectsDeletedChangedDuplicateAndForeignRows() throws {
        let selected = routeMetric("selected", day: 7)
        let older = routeMetric("older", day: 0)
        let receipt = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
        let publication = try XCTUnwrap(HomeV2PhotoRoute.Publication(
            metrics: [selected, older], selectedPhoto: .init(selected), ownership: receipt
        ))
        XCTAssertFalse(publication.admits(ownership: receipt, metrics: [selected]))
        XCTAssertFalse(publication.admits(ownership: receipt, metrics: [older]))
        XCTAssertFalse(publication.admits(
            ownership: receipt,
            metrics: [routeMetric("selected", day: 7, photo: "file:///changed.jpg"), older]
        ))
        XCTAssertFalse(publication.admits(ownership: receipt, metrics: [selected, selected, older]))
        XCTAssertNil(HomeV2PhotoRoute.Publication(
            metrics: [selected, routeMetric("foreign", day: 0, owner: "other")],
            selectedPhoto: .init(selected), ownership: receipt
        ))
        XCTAssertNil(HomeV2PhotoRoute.Publication(metrics: [selected], selectedPhoto: .init(selected), ownership: nil))
    }

    func testPhotoRoutePublicationRejectsLogoutReplacementAndSameAccountReturn() throws {
        let selected = routeMetric("selected", day: 7)
        let receipt = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
        let publication = try XCTUnwrap(HomeV2PhotoRoute.Publication(
            metrics: [selected], selectedPhoto: .init(selected), ownership: receipt
        ))
        XCTAssertTrue(publication.admits(ownership: receipt, metrics: [selected]))
        XCTAssertFalse(publication.admits(ownership: nil, metrics: [selected]))
        XCTAssertFalse(publication.admits(ownership: .init(subject: "other", generation: 1), metrics: [selected]))
        XCTAssertFalse(publication.admits(ownership: .init(subject: "owner", generation: 2), metrics: [selected]))
    }

    @MainActor
    func testHeldPhotoRouteReturnRejectsClosedReopenedAndReplacementLifetimes() async throws {
        let rows = [routeMetric("selected", day: 7), routeMetric("older", day: 0)]
        let receipt = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
        for replacement in ["closed", "reopened", "generation", "foreign", "deleted", "reorder-positive"] {
            let publication = try XCTUnwrap(HomeV2PhotoRoute.Publication(
                metrics: rows, selectedPhoto: .init(rows[0]), ownership: receipt
            ))
            let pair = try XCTUnwrap(publication.bind(try XCTUnwrap(publication.defaultPair)))
            let captured = HomeV2PhotoRoute(publication: publication, destination: .pickDates(pair))
            let state = HeldPhotoRouteState(route: captured, receipt: receipt, rows: rows)
            let entered = expectation(description: "Old picker return held")
            var resume: CheckedContinuation<Void, Never>?
            let task = Task { @MainActor in
                await withCheckedContinuation { resume = $0; entered.fulfill() }
                return captured.transition(to: .compare(pair), currentRoute: state.route,
                                           ownership: state.receipt, metrics: state.rows)
            }
            await fulfillment(of: [entered], timeout: 1)
            switch replacement {
            case "closed": state.route = nil
            case "reopened":
                let reopened = try XCTUnwrap(HomeV2PhotoRoute.Publication(
                    metrics: rows, selectedPhoto: .init(rows[0]), ownership: receipt
                ))
                XCTAssertNotEqual(publication.id, reopened.id)
                state.route = HomeV2PhotoRoute(publication: reopened, destination: .pickDates(pair))
            case "generation": state.receipt = .init(subject: "owner", generation: 2)
            case "foreign": state.receipt = .init(subject: "other", generation: 1)
            case "deleted": state.rows = [rows[0]]
            default: state.rows.reverse()
            }
            resume?.resume()
            let result = await task.value
            if replacement == "reorder-positive" {
                XCTAssertEqual(result?.publication.id, publication.id)
                XCTAssertEqual(result?.destination, .compare(pair))
                XCTAssertEqual(result?.publication.metrics, rows)
            } else {
                XCTAssertNil(result, replacement)
            }
            XCTAssertEqual(state.rows, replacement == "deleted" ? [rows[0]] :
                           (replacement == "reorder-positive" ? Array(rows.reversed()) : rows))
        }
    }

    @MainActor
    func testPhotoRouteBodyFatSourceUsesOnlyTheActualPair() throws {
        let ownership = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
        let newestUnrelated = routeMetric("unrelated-latest", day: 14, source: "manual", method: "manual")
        let dexa = routeMetric("dexa", day: 0, source: "healthkit", method: "dexa")
        let laterDexa = routeMetric("later-dexa", day: 7, source: "healthkit", method: "dexa")
        let publication = try XCTUnwrap(HomeV2PhotoRoute.Publication(
            metrics: [newestUnrelated, laterDexa, dexa], selectedPhoto: .init(laterDexa), ownership: ownership
        ))
        let bound = try XCTUnwrap(publication.bind(.init(before: 2, after: 1)))
        let pair = try XCTUnwrap(publication.indices(for: bound))
        let caption = try XCTUnwrap(HomeV2CompareView.bodyFatCaption(
            before: publication.metrics[pair.before], after: publication.metrics[pair.after]
        ))
        XCTAssertEqual(caption, "From your DEXA scan", "HealthKit transport does not relabel a recorded DEXA scan as an estimate")
        XCTAssertFalse(caption.contains("estimated by"))
        XCTAssertEqual(HomeV2EditorialPolicy.bodyFat(in: publication.metrics[pair.after])?.caption, caption)
        let health = routeMetric("health", day: 0, source: "healthkit", method: "healthkit")
        XCTAssertEqual(HomeV2CompareView.bodyFatCaption(before: health, after: health), "From Apple Health")
        let visual = routeMetric("visual", day: 7, source: "manual", method: "visual_estimate")
        XCTAssertEqual(HomeV2CompareView.bodyFatCaption(before: visual, after: visual), "Visual estimate")
        let mixed = try XCTUnwrap(HomeV2CompareView.bodyFatCaption(before: dexa, after: visual))
        XCTAssertEqual(mixed, "Before: From your DEXA scan. After: Visual estimate.")
        XCTAssertFalse(mixed.contains("estimated by your Apple Health"))
        let entered = routeMetric("typed", day: 7, source: "manual", method: "typed")
        XCTAssertEqual(HomeV2CompareView.bodyFatCaption(before: health, after: entered),
                       "Before: From Apple Health. After: Entered by you.")
        let unknown = routeMetric("unknown", day: 7, source: "manual", method: nil)
        XCTAssertEqual(HomeV2CompareView.bodyFatCaption(before: unknown, after: unknown), "Source not recorded")
        let inferred = routeMetric("inferred", day: 7, source: "manual", method: "interpolated")
        XCTAssertNil(HomeV2CompareView.bodyFatCaption(before: dexa, after: inferred))
    }

    @MainActor
    func testHeldCompareReturnRejectsWithinCoverDestinationABA() async throws {
        let rows = [routeMetric("selected", day: 7), routeMetric("older", day: 0)]
        let receipt = AuthManager.ProfileSessionOwnership(subject: "owner", generation: 1)
        let publication = try XCTUnwrap(HomeV2PhotoRoute.Publication(
            metrics: rows, selectedPhoto: .init(rows[0]), ownership: receipt
        ))
        let pair = try XCTUnwrap(publication.bind(try XCTUnwrap(publication.defaultPair)))
        let captured = HomeV2PhotoRoute(publication: publication, destination: .compare(pair))
        let state = HeldPhotoRouteState(route: captured, receipt: receipt, rows: rows)
        let entered = expectation(description: "Original Compare callback held")
        var resume: CheckedContinuation<Void, Never>?
        let task = Task { @MainActor in
            await withCheckedContinuation { resume = $0; entered.fulfill() }
            return captured.transition(to: .share(pair), currentRoute: state.route,
                                       ownership: state.receipt, metrics: state.rows)
        }
        await fulfillment(of: [entered], timeout: 1)
        let picker = try XCTUnwrap(captured.transition(
            to: .pickDates(pair), currentRoute: captured, ownership: receipt, metrics: rows
        ))
        let returned = try XCTUnwrap(picker.transition(
            to: .compare(pair), currentRoute: picker, ownership: receipt, metrics: rows
        ))
        XCTAssertEqual(returned.publication.id, captured.publication.id)
        XCTAssertEqual(returned.destination, captured.destination)
        XCTAssertEqual(returned.publication.metrics, captured.publication.metrics)
        XCTAssertNotEqual(returned.instanceID, captured.instanceID)
        state.route = returned
        resume?.resume()
        let result = await task.value
        XCTAssertNil(result, "An old Compare callback must not regain admission after Compare→Picker→Compare")
    }

    @MainActor
    private final class HeldPhotoRouteState {
        var route: HomeV2PhotoRoute?
        var receipt: AuthManager.ProfileSessionOwnership?
        var rows: [BodyMetrics]
        init(route: HomeV2PhotoRoute, receipt: AuthManager.ProfileSessionOwnership, rows: [BodyMetrics]) {
            self.route = route
            self.receipt = receipt
            self.rows = rows
        }
    }

    private func routeMetric(
        _ id: String, day: Int, owner: String = "owner", photo: String? = nil,
        source: String = "healthkit", method: String? = "healthkit"
    ) -> BodyMetrics {
        let date = Date(timeIntervalSince1970: 1_700_000_000).addingTimeInterval(Double(day) * 86_400)
        return BodyMetrics(
            id: id, userId: owner, date: date, weight: 80, weightUnit: "kg",
            bodyFatPercentage: 20, bodyFatMethod: method, muscleMass: nil, boneMass: nil,
            notes: "Original source", photoUrl: photo ?? "file:///synthetic-" + id + ".jpg",
            dataSource: source, createdAt: date, updatedAt: date
        )
    }

    func testPhotoScrubRequiresMoreThanASecondAndMapsBothDirectionsWithoutAnInitialJump() {
        XCTAssertGreaterThan(HomeV2PhotoScrubPolicy.holdDuration, 1)
        XCTAssertEqual(HomeV2PhotoScrubPolicy.position(start: 4, translation: 0, width: 400, count: 5), 4)
        XCTAssertEqual(HomeV2PhotoScrubPolicy.position(start: 4, translation: -200, width: 400, count: 5), 2)
        XCTAssertEqual(HomeV2PhotoScrubPolicy.position(start: 0, translation: 200, width: 400, count: 5), 2)
        XCTAssertEqual(HomeV2PhotoScrubPolicy.position(start: 2, translation: -400, width: 400, count: 5), 0)
        XCTAssertEqual(HomeV2PhotoScrubPolicy.position(start: 2, translation: 400, width: 400, count: 5), 4)
        XCTAssertEqual(HomeV2PhotoScrubPolicy.position(
            start: 2, translation: .greatestFiniteMagnitude, width: 1, count: 5
        ), 4)
    }

    func testPhotoScrubRejectsEmptySingleOrInvalidSelectionsAndGeometry() {
        for count in [0, 1] {
            XCTAssertNil(HomeV2PhotoScrubPolicy.position(start: 0, translation: 100, width: 400, count: count))
        }
        for start in [-1, 3] {
            XCTAssertNil(HomeV2PhotoScrubPolicy.position(start: start, translation: 100, width: 400, count: 3))
        }
        for width: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertNil(HomeV2PhotoScrubPolicy.position(start: 0, translation: 100, width: width, count: 3))
        }
        for translation: CGFloat in [.nan, .infinity, -.infinity] {
            XCTAssertNil(HomeV2PhotoScrubPolicy.position(start: 0, translation: translation, width: 400, count: 3))
        }
    }

    @MainActor
    func testPhotoScrubGateDefaultsOffAndUsesThePlatformPort() {
        XCTAssertFalse(HomeV2PhotoScrubPolicy.isEnabled(arguments: [], checkGate: { _ in false }))
        var checked: [String] = []
        XCTAssertTrue(HomeV2PhotoScrubPolicy.isEnabled(arguments: [], checkGate: {
            checked.append($0)
            return true
        }))
        XCTAssertEqual(checked, [HomeV2PhotoScrubPolicy.gateKey])
        #if DEBUG
        XCTAssertTrue(HomeV2PhotoScrubPolicy.isEnabled(
            arguments: [HomeV2PhotoScrubPolicy.fixtureArgument], checkGate: { _ in false }
        ))
        #endif
    }

    // BEGIN SUPPLEMENTAL FOUNDATION RULER CONTRACTS
    // These exact bodies are also assembled against the unmodified candidate
    // production enum for the supplemental Mac Foundation run.
    private func contractCalendar(_ zone: String = "UTC", identifier: Calendar.Identifier = .gregorian) throws -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return calendar
    }

    private func contractDate(_ year: Int, _ month: Int = 1, _ day: Int = 1, calendar: Calendar) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private func contractDenseDates(_ count: Int = 3_650, calendar: Calendar) throws -> [Date] {
        let start = try contractDate(2_016, calendar: calendar)
        return try (0..<count).map { try XCTUnwrap(calendar.date(byAdding: .day, value: $0, to: start)) }
    }

    private func assertContractPlan(
        _ plan: HomeV2PhotoRulerPolicy.RenderPlan, dates: [Date], selected: Int,
        span: DateInterval, maximumMarks: Int, maximumLabels: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(plan.entryIndices.count + plan.minorTicks.count + plan.majorTicks.count,
                                 maximumMarks, "Rendering work must be bounded by screen space", file: file, line: line)
        XCTAssertLessThanOrEqual(plan.labels.count, maximumLabels, file: file, line: line)
        XCTAssertEqual(Set(plan.entryIndices).count, plan.entryIndices.count, file: file, line: line)
        XCTAssertTrue(plan.entryIndices.allSatisfy { dates.indices.contains($0) }, file: file, line: line)
        if dates.indices.contains(selected) {
            XCTAssertTrue(
                plan.entryIndices.contains(selected),
                "The selected original index must survive thinning",
                file: file,
                line: line
            )
        }
        for layer in [plan.minorTicks, plan.majorTicks, plan.labels.map(\.date)] {
            XCTAssertEqual(layer, layer.sorted(), file: file, line: line)
            XCTAssertEqual(Set(layer).count, layer.count, file: file, line: line)
            XCTAssertTrue(layer.allSatisfy { $0 >= span.start && $0 <= span.end }, file: file, line: line)
            XCTAssertTrue(layer.allSatisfy { $0.timeIntervalSince1970.isFinite }, file: file, line: line)
        }
        XCTAssertTrue(Set(plan.minorTicks).isDisjoint(with: Set(plan.majorTicks)), file: file, line: line)
        XCTAssertTrue(
            plan.labels.allSatisfy { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            file: file,
            line: line
        )
    }

    func testAdaptiveRulerCapsTenYearDailyHistoryAndKeepsSelectedObservation() throws {
        let calendar = try contractCalendar()
        let dates = try contractDenseDates(calendar: calendar)
        let original = dates
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        let plan = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: 1_837, span: span, width: 390,
                                                     calendar: calendar,
                                                     locale: Locale(identifier: "en_US")
        )
        // A 390pt ruler can afford at most 65 observation, 32 minor and 8 major
        // marks, and 5 normal-size labels. The old 4,292-mark ruler fails here.
        assertContractPlan(plan, dates: dates, selected: 1_837, span: span, maximumMarks: 105, maximumLabels: 5)
        XCTAssertLessThanOrEqual(plan.entryIndices.count, 65)
        XCTAssertEqual(dates, original, "Display thinning cannot change or discard raw history")
        XCTAssertEqual(span.start, calendar.startOfDay(for: original[0]))
        XCTAssertEqual(span.end, original[3_649])
    }

    func testAdaptiveRulerSparseTenYearHistoryDoesNotGenerateCalendarNoise() throws {
        let calendar = try contractCalendar()
        let dates = try [2_016, 2_017, 2_020, 2_023, 2_026].map { try contractDate($0, calendar: calendar) }
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        let plan = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: 2, span: span, width: 390,
                                                     calendar: calendar,
                                                     locale: Locale(identifier: "en_US")
        )
        // Five observations cannot justify the old >600 calendar marks.
        assertContractPlan(plan, dates: dates, selected: 2, span: span, maximumMarks: 45, maximumLabels: 5)
        XCTAssertEqual(plan.entryIndices, [0, 1, 2, 3, 4])
    }

    func testAdaptiveRulerNeverLosesASelectedCoincidentOriginalIndex() throws {
        let calendar = try contractCalendar()
        let day = try contractDate(2_026, 10, 10, calendar: calendar)
        let dates = Array(repeating: day, count: 3_650)
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        for selected in [0, 1, 1_837, 3_649] {
            let plan = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: selected, span: span, width: 390,
                                                         calendar: calendar
            )
            XCTAssertEqual(
                plan.entryIndices,
                [selected],
                "Duplicate dates keep the selected identity, not merely a matching timestamp"
            )
        }
        XCTAssertEqual(dates.count, 3_650)
        XCTAssertEqual(Set(dates), Set([day]))
    }

    func testAdaptiveRulerRapidForwardReverseSelectionRetainsEveryRawSelectableDate() throws {
        let calendar = try contractCalendar()
        let dates = try contractDenseDates(calendar: calendar)
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        let sequence = [0, 3_400, 1_700, 1_701, 5, 3_649, 0, 2_500, 17, 16]
        for selected in sequence {
            let plan = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: selected, span: span, width: 390,
                                                         calendar: calendar
            )
            assertContractPlan(plan, dates: dates, selected: selected, span: span, maximumMarks: 105, maximumLabels: 5)
            let position = CGFloat(dates[selected].timeIntervalSince(span.start) / span.duration)
            XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: position, dates: dates, span: span), selected,
                           "Thinned display indices must never become the selectable data source")
        }
    }

    func testAdaptiveRulerReversedInputPreservesOriginalIndicesAndTimestamps() throws {
        let calendar = try contractCalendar()
        let ascending = try contractDenseDates(calendar: calendar)
        let dates = Array(ascending.reversed())
        let original = dates
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        for selected in [0, 47, 1_837, 3_649] {
            let plan = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: selected, span: span, width: 390,
                                                         calendar: calendar
            )
            assertContractPlan(plan, dates: dates, selected: selected, span: span, maximumMarks: 105, maximumLabels: 5)
            let position = CGFloat(dates[selected].timeIntervalSince(span.start) / span.duration)
            XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: position, dates: dates, span: span), selected)
        }
        XCTAssertEqual(dates, original)
        XCTAssertEqual(span.end, ascending[3_649])
    }

    func testAdaptiveRulerBoundsExtremeHistoryBeforeIteratingCalendarMarks() throws {
        let calendar = try contractCalendar()
        let dates = try [1_900, 2_000, 2_100, 2_200, 2_300, 2_400].map { try contractDate($0, calendar: calendar) }
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        let plan = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: 3, span: span, width: 390,
                                                     calendar: calendar,
                                                     locale: Locale(identifier: "fr_FR")
        )
        assertContractPlan(plan, dates: dates, selected: 3, span: span, maximumMarks: 46, maximumLabels: 5)
        XCTAssertEqual(dates[3], try contractDate(2_200, calendar: calendar))
    }

    func testAdaptiveRulerCalendarLocaleAndLargeTypeRespectActualLabelSpacing() throws {
        let first = Date(timeIntervalSince1970: 1_704_110_400) // 2024-01-01 12:00 UTC.
        let last = Date(timeIntervalSince1970: 1_735_732_800)  // 2025-01-01 12:00 UTC.
        let dates = [first, last]
        let span = DateInterval(start: first, end: last)
        for identifier: Calendar.Identifier in [.gregorian, .hebrew, .islamicCivil] {
            let calendar = try contractCalendar("America/Los_Angeles", identifier: identifier)
            for locale in ["en_US", "ar_SA", "ja_JP", "fr_FR"] {
                for spacing: CGFloat in [72, 144] {
                    let plan = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: 1, span: span, width: 390,
                                                                 minimumLabelSpacing: spacing,
                                                                 calendar: calendar,
                                                                 locale: Locale(identifier: locale)
                    )
                    assertContractPlan(plan, dates: dates, selected: 1, span: span, maximumMarks: 42,
                                       maximumLabels: spacing == 72 ? 5 : 2)
                    for (left, right) in zip(plan.labels, plan.labels.dropFirst()) {
                        let distance = right.date.timeIntervalSince(left.date) / span.duration * 390
                        XCTAssertGreaterThanOrEqual(distance + 0.001, Double(spacing),
                                                    "\(identifier)/\(locale) labels must honor the allocated text width"
                        )
                    }
                }
            }
        }
    }

    func testAdaptiveRulerInvalidGeometryStaysFiniteAndSelectedIsVisible() throws {
        let calendar = try contractCalendar()
        let dates = try contractDenseDates(calendar: calendar)
        let span = HomeV2PhotoRulerPolicy.span(for: dates, calendar: calendar)
        for width: CGFloat in [0, -1, .nan, .infinity, -.infinity] {
            let plan = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: 1_837, span: span, width: width,
                                                         calendar: calendar
            )
            XCTAssertEqual(plan.entryIndices, [1_837])
            XCTAssertTrue(plan.minorTicks.isEmpty)
            XCTAssertTrue(plan.majorTicks.isEmpty)
            XCTAssertTrue(plan.labels.isEmpty)
        }
        for width: CGFloat in [1, 5, .greatestFiniteMagnitude] {
            let plan = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: 1_837, span: span, width: width,
                                                         minimumTickSpacing: .nan,
                                                         minimumLabelSpacing: .infinity,
                                                         calendar: calendar
            )
            assertContractPlan(plan, dates: dates, selected: 1_837, span: span, maximumMarks: 1_110, maximumLabels: 56)
        }
        let empty = HomeV2PhotoRulerPolicy.renderPlan(dates: [], selected: -1, span: span, width: 390, calendar: calendar)
        XCTAssertTrue(empty.entryIndices.isEmpty)
        let invalidSelection = HomeV2PhotoRulerPolicy.renderPlan(dates: dates, selected: 99_999, span: span, width: 390,
                                                                 calendar: calendar
        )
        assertContractPlan(invalidSelection, dates: dates, selected: 99_999, span: span, maximumMarks: 105, maximumLabels: 5)
    }

    func testAdaptiveRulerRTLAndLTRMapTheSameObservedMomentAndClampEdges() throws {
        let calendar = try contractCalendar()
        let dates = try [0, 7, 28, 56].map {
            try XCTUnwrap(calendar.date(byAdding: .day, value: $0, to: contractDate(2_026, calendar: calendar)))
        }
        let span = DateInterval(start: dates[0], end: dates[3])
        for (position, expectedIndex) in [(CGFloat(0), 0), (48.75, 1), (195, 2), (390, 3)] {
            let ltr = HomeV2PhotoRulerPolicy.logicalFraction(at: position, width: 390)
            let rtl = HomeV2PhotoRulerPolicy.logicalFraction(at: 390 - position, width: 390, isRightToLeft: true)
            XCTAssertEqual(ltr, rtl, accuracy: 0.000001)
            XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: ltr, dates: dates, span: span), expectedIndex)
            XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: rtl, dates: dates, span: span), expectedIndex)
        }
        XCTAssertEqual(HomeV2PhotoRulerPolicy.logicalFraction(at: -10, width: 390), 0)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.logicalFraction(at: 400, width: 390), 1)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.logicalFraction(at: -10, width: 390, isRightToLeft: true), 1)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.logicalFraction(at: 400, width: 390, isRightToLeft: true), 0)
        for width: CGFloat in [0, .nan, .infinity] {
            XCTAssertEqual(HomeV2PhotoRulerPolicy.logicalFraction(at: 50, width: width), 0)
        }
    }
    // END SUPPLEMENTAL FOUNDATION RULER CONTRACTS

    // BEGIN NATIVE AXIS CONTRACTS
    func testHomeWeightScaleUsesSupportedObservedBoundsWithoutInventingReadings() throws {
        let scale = HomeV2TimelinePolicy.WeightScale(kilograms: [70, 90, .nan, .infinity, -.infinity, -1, 100_000])
        XCTAssertEqual(scale.kilograms, 70...90)
        let domain = try XCTUnwrap(scale.domain(unit: "kg"))
        XCTAssertEqual(domain.lowerBound, 67.6, accuracy: 0.000001)
        XCTAssertEqual(domain.upperBound, 92.4, accuracy: 0.000001)
        let singleton = try XCTUnwrap(HomeV2TimelinePolicy.WeightScale(kilograms: [80]).domain(unit: "kg"))
        XCTAssertEqual(singleton.lowerBound, 73.6, accuracy: 0.000001)
        XCTAssertEqual(singleton.upperBound, 86.4, accuracy: 0.000001)
        for values: [Double] in [[], [.nan, .infinity, -.infinity, -1, 100_000]] {
            let missing = HomeV2TimelinePolicy.WeightScale(kilograms: values)
            XCTAssertNil(missing.kilograms)
            XCTAssertNil(missing.domain(unit: "kg"))
        }
    }

    func testHomeWeightScaleSnapshotExcludesForeignOwnersAndReflectsSameRowCorrection() throws {
        let moment = Date(timeIntervalSince1970: 1_700_000_000)
        let owner = "synthetic-contract-owner"
        let first = contractMetric(id: "first", date: moment, weight: 80)
        let second = contractMetric(id: "second", date: moment.addingTimeInterval(86_400), weight: 90)
        let foreign = contractMetric(id: "foreign", date: moment, weight: 120, owner: "synthetic-other-owner")
        let snapshot = HomeV2TimelinePolicy.Snapshot(metrics: [foreign, second, first], owner: owner,
                                                     ownership: .init(subject: owner, generation: 1)
        )
        XCTAssertEqual(snapshot.weightScale.kilograms, 80...90)
        let corrected = contractMetric(id: first.id, date: first.date, weight: 70)
        XCTAssertEqual(first.id, corrected.id)
        XCTAssertEqual(first.date, corrected.date)
        XCTAssertEqual(first.updatedAt, corrected.updatedAt)
        let refreshed = HomeV2TimelinePolicy.Snapshot(metrics: [foreign, second, corrected], owner: owner,
                                                      ownership: .init(subject: owner, generation: 1)
        )
        XCTAssertEqual(refreshed.weightScale.kilograms, 70...90)
        XCTAssertEqual(refreshed.reconcile(HomeV2TimelinePolicy.Selection(first))?.id,
                       HomeV2TimelinePolicy.EntryID(first), "Correcting a reading must retain its selected identity")
        let anonymous = HomeV2TimelinePolicy.Snapshot(metrics: [first, second, foreign], owner: nil)
        XCTAssertNil(anonymous.weightScale.kilograms)
    }

    func testHomeWeightScaleUnitChangeConvertsOnceAndKeepsCanonicalBounds() throws {
        let scale = HomeV2TimelinePolicy.WeightScale(kilograms: [70, 90])
        let pounds = try XCTUnwrap(scale.domain(unit: "lb"))
        // Independent arithmetic using the retained product conversion 2.20462.
        XCTAssertEqual(pounds.lowerBound, 149.032312, accuracy: 0.000001)
        XCTAssertEqual(pounds.upperBound, 203.706888, accuracy: 0.000001)
        XCTAssertEqual(scale.kilograms, 70...90, "Changing display units must never rewrite raw health bounds")
        let kilograms = try XCTUnwrap(scale.domain(unit: "kg"))
        XCTAssertEqual(kilograms.lowerBound, 67.6, accuracy: 0.000001)
        XCTAssertEqual(kilograms.upperBound, 92.4, accuracy: 0.000001)
        XCTAssertEqual(scale.domain(unit: "lb"), pounds, "Returning to a unit must not convert an already converted domain")
    }

    func testHomeFixedChartScaleSurvivesVisibleDateChangesWhenItEnclosesObservedValues() {
        let fixed: ClosedRange<Double> = 50...100
        XCTAssertEqual(HomeV2TrendPolicy.displayDomain(fixed: fixed, observedValues: [70, 80],
                                                       fallback: 60...90, anchorsToZero: false), fixed)
        XCTAssertEqual(HomeV2TrendPolicy.displayDomain(fixed: fixed, observedValues: [90, 98],
                                                       fallback: 88...102, anchorsToZero: false), fixed)
        XCTAssertEqual(HomeV2TrendPolicy.displayDomain(fixed: fixed, observedValues: [50, 100],
                                                       fallback: 45...105, anchorsToZero: false), fixed)
    }

    func testHomeFixedChartScaleRejectsClippingInvalidBoundsAndZeroAnchorContradictions() {
        let fallback: ClosedRange<Double> = 40...110
        for fixed: ClosedRange<Double>? in [nil, -1...100, 50...50, 0...Double.infinity, -Double.infinity...100, 60...80] {
            XCTAssertEqual(HomeV2TrendPolicy.displayDomain(fixed: fixed, observedValues: [50, 100],
                                                           fallback: fallback, anchorsToZero: false), fallback)
        }
        for invalid: Double in [.nan, .infinity, -.infinity] {
            XCTAssertEqual(HomeV2TrendPolicy.displayDomain(fixed: 0...120, observedValues: [invalid],
                                                           fallback: fallback, anchorsToZero: false), fallback)
        }
        XCTAssertEqual(HomeV2TrendPolicy.displayDomain(fixed: 50...100, observedValues: [70, 80],
                                                       fallback: fallback, anchorsToZero: true), fallback)
        XCTAssertEqual(HomeV2TrendPolicy.displayDomain(fixed: 0...120, observedValues: [0, 120],
                                                       fallback: fallback, anchorsToZero: true), 0...120)
    }
    // END NATIVE AXIS CONTRACTS

    // BEGIN NATIVE CACHE ATTRIBUTION CONTRACTS
    // These execute the real cache/service in the existing app test target.
    // They are not included in the ruler-only Foundation package.
    private func contractMetric(
        id: String, date: Date, weight: Double? = 80, bodyFat: Double? = nil,
        bodyFatMethod: String? = nil, source: String = "manual", metadata: BodyMetricSourceMetadata? = nil,
        owner: String = "synthetic-contract-owner"
    ) -> BodyMetrics {
        BodyMetrics(id: id, userId: owner, date: date, weight: weight, weightUnit: "kg",
                    bodyFatPercentage: bodyFat, bodyFatMethod: bodyFatMethod, muscleMass: nil, boneMass: nil,
                    notes: nil, photoUrl: nil, dataSource: source, sourceMetadata: metadata,
                    createdAt: date, updatedAt: date)
    }

    private func contractCacheHistory(
        method: String?, source: String, bodyFatSourceOverride: BodyMetricSource? = nil
    ) throws -> [BodyMetrics] {
        let calendar = Calendar.current
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2_026, month: 1, day: 1, hour: 12)))
        let metadata = bodyFatSourceOverride.map {
            BodyMetricSourceMetadata().settingEntrySource($0, fields: [.bodyFat])
        }
        return try (0...90).map { day in
            let date = try XCTUnwrap(calendar.date(byAdding: .day, value: day, to: first))
            let bodyFat: Double? = day == 0 ? 20 : (day == 90 ? 30 : nil)
            return contractMetric(id: "synthetic-day-\(day)", date: date, bodyFat: bodyFat,
                                  bodyFatMethod: method, source: source, metadata: metadata)
        }
    }

    func testHeroCacheMethodOnlyCorrectionRevokesAndRestoresWideDEXAEstimate() throws {
        let dexa = try contractCacheHistory(method: "dexa", source: "manual")
        let manual = try contractCacheHistory(method: "manual", source: "manual")
        let queryDate = dexa[0].date.addingTimeInterval(dexa[90].date.timeIntervalSince(dexa[0].date) / 2)
        let query = contractMetric(id: "synthetic-query", date: queryDate, weight: nil)
        let cache = HeroMetricInterpolationCache()
        XCTAssertEqual(try XCTUnwrap(cache.values(for: query, in: dexa, heightInches: 70).bodyFat), 25, accuracy: 0.001)
        // Same count, IDs, dates, measured numbers and updatedAt; only the
        // eligibility-defining measurement method has changed.
        XCTAssertEqual(dexa.map(\.id), manual.map(\.id))
        XCTAssertEqual(dexa.map(\.date), manual.map(\.date))
        XCTAssertEqual(dexa.map(\.updatedAt), manual.map(\.updatedAt))
        XCTAssertEqual(dexa.map(\.bodyFatPercentage), manual.map(\.bodyFatPercentage))
        let corrected = cache.values(for: query, in: manual, heightInches: 70)
        XCTAssertNil(corrected.bodyFat, "A manual 90-day gap is outside the supported interpolation window")
        XCTAssertNil(corrected.ffmi, "Derived FFMI cannot retain an ineligible cached body-fat estimate")
        XCTAssertEqual(corrected, HeroMetricInterpolationCache().values(for: query, in: manual, heightInches: 70))
        XCTAssertEqual(try XCTUnwrap(cache.values(for: query, in: dexa, heightInches: 70).bodyFat), 25, accuracy: 0.001)
    }

    func testHeroCacheFieldSourceOnlyCorrectionRevokesAndRestoresWideDEXAEstimate() throws {
        let imported = try contractCacheHistory(method: nil, source: "bodyspec_dexa")
        let replaced = try contractCacheHistory(method: nil, source: "bodyspec_dexa", bodyFatSourceOverride: .smartScale)
        let queryDate = imported[0].date.addingTimeInterval(imported[90].date.timeIntervalSince(imported[0].date) / 2)
        let query = contractMetric(id: "synthetic-query", date: queryDate, weight: nil)
        let cache = HeroMetricInterpolationCache()
        XCTAssertEqual(imported[0].measurementSource(for: .bodyFat), .bodySpecDexa)
        XCTAssertEqual(replaced[0].measurementSource(for: .bodyFat), .smartScale)
        XCTAssertEqual(imported.map(\.attributedBodyFatMethod), replaced.map(\.attributedBodyFatMethod))
        XCTAssertEqual(imported.map(\.bodyFatMethod), replaced.map(\.bodyFatMethod))
        XCTAssertEqual(imported.map(\.dataSource), replaced.map(\.dataSource))
        XCTAssertEqual(imported.map(\.id), replaced.map(\.id))
        XCTAssertEqual(imported.map(\.date), replaced.map(\.date))
        XCTAssertEqual(imported.map(\.updatedAt), replaced.map(\.updatedAt))
        XCTAssertEqual(imported.map(\.bodyFatPercentage), replaced.map(\.bodyFatPercentage))
        XCTAssertEqual(try XCTUnwrap(cache.values(for: query, in: imported, heightInches: 70).bodyFat), 25, accuracy: 0.001)
        let corrected = cache.values(for: query, in: replaced, heightInches: 70)
        XCTAssertNil(corrected.bodyFat, "Field-level scale attribution overrides the retained DEXA import source")
        XCTAssertEqual(corrected, HeroMetricInterpolationCache().values(for: query, in: replaced, heightInches: 70))
        XCTAssertEqual(try XCTUnwrap(cache.values(for: query, in: imported, heightInches: 70).bodyFat), 25, accuracy: 0.001)
    }

    func testHeroCacheHeightChangePreservesMeasurementsAndRecomputesCanonicalFFMI() throws {
        let history = try contractCacheHistory(method: "dexa", source: "manual")
        let queryDate = history[0].date.addingTimeInterval(history[90].date.timeIntervalSince(history[0].date) / 2)
        let query = contractMetric(id: "synthetic-query", date: queryDate, weight: nil)
        let cache = HeroMetricInterpolationCache()
        let at70 = cache.values(for: query, in: history, heightInches: 70)
        let at72 = cache.values(for: query, in: history, heightInches: 72)
        XCTAssertEqual(try XCTUnwrap(at70.weight), 80, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(at70.bodyFat), 25, accuracy: 0.001)
        XCTAssertEqual(at70.weight, at72.weight)
        XCTAssertEqual(at70.bodyFat, at72.bodyFat)
        // Independent canonical oracle: 60kg lean mass / squared height in
        // metres + 6.1 * (1.8 - heightMetres), rounded to one decimal.
        XCTAssertEqual(try XCTUnwrap(at70.ffmi), 19.1, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(at72.ffmi), 17.8, accuracy: 0.001)
        XCTAssertEqual(at72, HeroMetricInterpolationCache().values(for: query, in: history, heightInches: 72))
        let noHeight = cache.values(for: query, in: history, heightInches: nil)
        XCTAssertNil(noHeight.ffmi)
        XCTAssertEqual(noHeight.bodyFat, at70.bodyFat)
    }
    // END NATIVE CACHE ATTRIBUTION CONTRACTS

    // BEGIN NATIVE HERO READING CONTRACTS
    func testHeroReadingMissingRequestedMetricCannotSubstituteAnotherAvailableKind() {
        let available = HomeV2TimelinePolicy.HeroReading(kind: .weight, value: "80.0", unit: "kg",
                                                         detail: "Synthetic observed weight"
        )
        for kind: HomeV2ProgressMetric in [.bodyFat, .ffmi] {
            let protected = available.forRequestedMetric(kind)
            XCTAssertEqual(protected.kind, kind)
            XCTAssertNil(protected.value)
            XCTAssertNil(protected.bodyFatFraction)
            XCTAssertEqual(protected.detail, kind == .ffmi ? "Needs weight, body fat and height" : "\(kind.title) unavailable at this time.")
            XCTAssertNil(protected.evidence)
        }
        XCTAssertEqual(available.forRequestedMetric(.weight), available)
    }

    func testHeroReadingRejectsInvalidCompositionGeometryWithoutRewritingDisplayValue() {
        for fraction: Double in [-0.01, 1.01, .nan, .infinity, -.infinity] {
            let reading = HomeV2TimelinePolicy.HeroReading(kind: .bodyFat, value: "25.0", unit: "%",
                                                           detail: "Synthetic invalid geometry",
                                                           bodyFatFraction: fraction
            )
            XCTAssertNil(reading.bodyFatFraction)
            XCTAssertEqual(reading.value, "25.0", "Rejecting invalid geometry does not rewrite a measurement")
        }
        for fraction: Double in [0, 0.25, 1] {
            XCTAssertEqual(HomeV2TimelinePolicy.HeroReading(kind: .bodyFat, value: "25.0", unit: "%",
                                                            detail: "Synthetic",
                                                            bodyFatFraction: fraction
                ).bodyFatFraction,
                fraction
            )
        }
    }

    // END NATIVE HERO READING CONTRACTS

    // BEGIN NATIVE SHARE CONTRACTS
    private func contractShareSnapshot(
        _ kind: ContextualMetricKind, value: String, moment: String = "Synthetic selected moment"
    ) -> ContextualMetricSnapshot {
        ContextualMetricSnapshot(kind: kind, value: value, unit: kind == .weight ? "kg" : "%",
                                 observation: moment, range: "Synthetic visible range", trend: nil,
                                 provenance: "Synthetic source", evidence: "Synthetic evidence")
    }

    func testContextualShareStartsWithChosenMetricAndKeepsTheFrozenMomentAcrossPickerChanges() throws {
        var liveSnapshots = [contractShareSnapshot(.weight, value: "80.0"),
                             contractShareSnapshot(.bodyFat, value: "25.0"),
                             contractShareSnapshot(.ffmi, value: "19.0")]
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual(liveSnapshots, selected: .bodyFat))
        XCTAssertEqual(payload.preferredMetric, .bodyFat)
        var options = BodyScoreShareOptions(selectedMetric: payload.preferredMetric)
        XCTAssertEqual(payload.snapshot(for: options)?.kind, .bodyFat)
        XCTAssertEqual(payload.snapshot(for: options)?.value, "25.0")
        liveSnapshots = [contractShareSnapshot(.weight, value: "81.0", moment: "Later live moment")]
        for (kind, expected) in [(ContextualMetricKind.ffmi, "19.0"), (.weight, "80.0"), (.bodyFat, "25.0")] {
            options.selectedMetric = kind
            XCTAssertEqual(payload.snapshot(for: options)?.value, expected)
            XCTAssertEqual(payload.snapshot(for: options)?.observation, "Synthetic selected moment",
                           "Metric picker changes must not capture a later live timeline selection")
        }
        XCTAssertEqual(liveSnapshots[0].observation, "Later live moment", "Fixture must actually change the live data")
        XCTAssertNil(payload.photoImage)
        XCTAssertNil(payload.gender)
        XCTAssertNil(payload.bodyFatPercentage)
        XCTAssertEqual(payload.score, 0)
    }

    func testContextualShareUnavailableChosenMetricStaysChosenAndCannotExport() throws {
        let snapshots = [contractShareSnapshot(.weight, value: "80.0"),
                         contractShareSnapshot(.bodyFat, value: "—"),
                         contractShareSnapshot(.ffmi, value: "—")]
        XCTAssertNil(BodyScoreSharePayload.contextual(snapshots, selected: .bodyFat),
                     "Existing callers keep unavailable selection opt-in")
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual(
            snapshots, selected: .bodyFat, includeUnavailableSelection: true
        ))
        XCTAssertEqual(payload.preferredMetric, .bodyFat)
        XCTAssertEqual(payload.contextualMetrics.map(\.kind), [.weight, .bodyFat],
                       "Only the requested missing metric belongs in this unavailable preview")
        var options = BodyScoreShareOptions(selectedMetric: payload.preferredMetric)
        XCTAssertEqual(payload.snapshot(for: options)?.value, "—")
        XCTAssertFalse(payload.canExport(options: options), "Unavailable is a preview, never a fabricated share value")
        options.selectedMetric = .weight
        XCTAssertTrue(payload.canExport(options: options))
        XCTAssertEqual(payload.snapshot(for: options)?.value, "80.0")
        options.selectedMetric = .ffmi
        XCTAssertNil(payload.snapshot(for: options))
        XCTAssertFalse(payload.canExport(options: options))
        options.selectedMetric = nil
        XCTAssertFalse(payload.canExport(options: options), "A contextual score-zero payload cannot invent a Body Score export")
        XCTAssertNil(BodyScoreSharePayload.contextual(snapshots, selected: .steps, includeUnavailableSelection: true),
                     "An absent requested metric must never fall back to an available different metric")
    }

    func testContextualSharePrivacyDefaultsDoNotAddUnselectedHealthFieldsOrVisuals() throws {
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual(
            [contractShareSnapshot(.weight, value: "80.0")], selected: .weight
        ))
        var options = BodyScoreShareOptions(selectedMetric: payload.preferredMetric)
        XCTAssertFalse(options.includeProvenance)
        XCTAssertFalse(options.includeWeight)
        XCTAssertFalse(options.includeBodyFat)
        XCTAssertFalse(options.includeFFMI)
        XCTAssertFalse(options.includeVisual)
        XCTAssertFalse(options.hasMetrics)
        XCTAssertEqual(options.includedSummary, "Weight")
        let snapshot = try XCTUnwrap(payload.snapshot(for: options))
        XCTAssertFalse(snapshot.detail(options: options).contains("Synthetic source"))
        options.includeProvenance = true
        XCTAssertTrue(snapshot.detail(options: options).contains("Synthetic source"))
    }

    func testScreenshotOfferRequiresActiveVisibleAndNoExistingPresentation() {
        let inputs = [
            (false, false, false, false), (false, false, true, false),
            (false, true, false, false), (false, true, true, false),
            (true, false, false, false), (true, false, true, false),
            (true, true, false, true), (true, true, true, false)
        ]
        for (active, visible, presenting, expected) in inputs {
            XCTAssertEqual(ContextualMetricSharePolicy.canOfferScreenshot(
                isActive: active, isVisible: visible, isPresenting: presenting
            ), expected)
        }
    }

    func testMVPTopLevelSidebarHasOnlyTodayAndProgress() {
        XCTAssertEqual(HomeV2SidebarDestination.allCases.map(\.rawValue), ["today", "progress"])
    }

    @MainActor
    func testFrozenHomeShareRejectsLogoutAccountReplacementAndSameSubjectGenerationChange() throws {
        let original = AuthManager.ProfileSessionOwnership(subject: "synthetic-A", generation: 1)
        let replacements: [AuthManager.ProfileSessionOwnership?] = [
            nil, .init(subject: "synthetic-B", generation: 2), .init(subject: "synthetic-A", generation: 3)
        ]
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual(
            [contractShareSnapshot(.bodyFat, value: "25.0")], selected: .bodyFat
        ))
        for replacement in replacements {
            var current: AuthManager.ProfileSessionOwnership? = original
            var capture = AccountBoundShareCapture()
            capture.freeze(payload, owner: original)
            capture.reconcile(currentOwner: original)
            XCTAssertEqual(capture.authorizedPayload { $0 == current }?.preferredMetric, .bodyFat)
            current = replacement
            XCTAssertNil(capture.authorizedPayload { $0 == current }, "Stale capture must stop rendering/exporting immediately")
            capture.reconcile(currentOwner: replacement)
            XCTAssertNil(capture.payload)
            // A completion from the former account lifetime cannot authorize
            // itself merely because it arrives after the new owner is visible.
            capture.freeze(payload, owner: original)
            XCTAssertNil(capture.authorizedPayload { $0 == current })
            capture.clear()
            XCTAssertNil(capture.payload)
        }
    }
    // END NATIVE SHARE CONTRACTS

    // Composed repair regressions. Supplemental Foundation can run the ruler
    // cases only; real app-target execution remains separately required.
    func testRulerDropsLabelsWhoseActualClampedFramesOverlapAtEitherEdge() throws {
        let calendar = try contractCalendar()
        let start = Date(timeIntervalSince1970: 0)
        let span = DateInterval(start: start, duration: 100 * 86_400)
        for locale in ["en_US", "ar_SA", "ja_JP"] {
            for days: [Double] in [[5, 49], [51, 95]] {
                let dates = days.map { start.addingTimeInterval($0 * 86_400) }
                let labels = HomeV2PhotoRulerPolicy.positionedLabels(
                    dates: dates, span: span, width: 200, minimumLabelSpacing: 88,
                    calendar: calendar, locale: Locale(identifier: locale)
                )
                // Raw centers differ by exactly 88pt. Edge clamping reduces
                // the actual center distance to 54pt, so two cannot fit.
                XCTAssertEqual(labels.count, 1)
                XCTAssertEqual(labels.first?.date, dates[0])
                let expectedFirstPosition: CGFloat = days[0] == 5 ? 44 : 102
                XCTAssertEqual(try XCTUnwrap(labels.first?.position), expectedFirstPosition, accuracy: 0.001)
            }
        }
    }

    func testRulerActualLabelGeometryStaysBoundedAtAccessibilitySpacingAndNarrowWidths() throws {
        let calendar = try contractCalendar()
        let start = Date(timeIntervalSince1970: 0)
        let span = DateInterval(start: start, duration: 100 * 86_400)
        let axDates = [88.0 / 350, 264.0 / 350].map { start.addingTimeInterval($0 * span.duration) }
        let axLabels = HomeV2PhotoRulerPolicy.positionedLabels(
            dates: axDates, span: span, width: 350, minimumLabelSpacing: 176, calendar: calendar
        )
        XCTAssertEqual(axLabels.count, 1, "Raw 176pt spacing becomes 174pt after clamping the right edge")
        for width: CGFloat in [40, 88, 200, 390] {
            for spacing: CGFloat in [88, 176] {
                let dates = (0...20).map { start.addingTimeInterval(Double($0) / 20 * span.duration) }
                let labels = HomeV2PhotoRulerPolicy.positionedLabels(
                    dates: dates, span: span, width: width, minimumLabelSpacing: spacing,
                    calendar: calendar, locale: Locale(identifier: "ar_SA")
                )
                let half = min(width, spacing) / 2
                for label in labels {
                    XCTAssertTrue(label.position.isFinite)
                    XCTAssertGreaterThanOrEqual(label.position, half)
                    XCTAssertLessThanOrEqual(label.position, width - half)
                }
                for (left, right) in zip(labels, labels.dropFirst()) {
                    // Compare real displayed label frames, independently of
                    // date fraction spacing. RTL reverses centers only.
                    XCTAssertLessThanOrEqual(left.position + spacing / 2, right.position - spacing / 2 + 0.001)
                    let rtlLeft = width - right.position, rtlRight = width - left.position
                    XCTAssertGreaterThanOrEqual(rtlRight - rtlLeft + 0.001, spacing)
                }
                if width < spacing { XCTAssertLessThanOrEqual(labels.count, 1) }
            }
        }
        for width: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertTrue(HomeV2PhotoRulerPolicy.positionedLabels(
                dates: axDates, span: span, width: width, minimumLabelSpacing: 88, calendar: calendar
            ).isEmpty)
        }
    }

    func testLoadingSelectedShareSnapshotCannotExportOrReuseAStaleNumber() throws {
        var steps = contractShareSnapshot(.steps, value: "999")
        steps.isLoading = true
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual(
            [contractShareSnapshot(.weight, value: "80.0"), steps], selected: .steps,
            includeUnavailableSelection: true
        ))
        let options = BodyScoreShareOptions(selectedMetric: payload.preferredMetric)
        XCTAssertEqual(payload.preferredMetric, .steps)
        XCTAssertEqual(
            payload.snapshot(for: options)?.displayValue,
            "—",
            "Loading preview must hide a retained stale numeric value"
        )
        XCTAssertEqual(payload.snapshot(for: options)?.unavailableMessage, "Loading Steps…")
        XCTAssertFalse(try XCTUnwrap(payload.snapshot(for: options)).isAvailable)
        XCTAssertFalse(payload.canExport(options: options), "Even a retained numeric value is unavailable while loading")
        let complete = try XCTUnwrap(BodyScoreSharePayload.contextual(
            [contractShareSnapshot(.steps, value: "6000")], selected: .steps
        ))
        XCTAssertTrue(complete.canExport(options: options))
        XCTAssertEqual(complete.snapshot(for: options)?.displayValue, "6000")
        XCTAssertNil(complete.snapshot(for: options)?.unavailableMessage)
        XCTAssertFalse(payload.canExport(options: options), "A completed new capture cannot rewrite the frozen loading capture")
    }

    func testShareDetailControlsUseOnlyNonblankFieldsOfTheSelectedFrozenSnapshot() throws {
        for value: String? in [nil, "", " ", "\n\t"] {
            XCTAssertFalse(ContextualMetricSharePolicy.hasDetail(value))
        }
        XCTAssertTrue(ContextualMetricSharePolicy.hasDetail("\nSynthetic source\t"))
        let weight = ContextualMetricSnapshot(kind: .weight, value: "80", unit: "kg", observation: "Synthetic date",
                                              range: "Synthetic range",
                                              trend: "Synthetic trend",
                                              provenance: "Synthetic source"
        )
        let fat = ContextualMetricSnapshot(kind: .bodyFat, value: "20", unit: "%", observation: "Synthetic date",
                                           range: "",
                                           trend: nil,
                                           provenance: " \n"
        )
        let payload = try XCTUnwrap(BodyScoreSharePayload.contextual([weight, fat], selected: .weight))
        var options = BodyScoreShareOptions(selectedMetric: .weight)
        XCTAssertTrue(ContextualMetricSharePolicy.hasDetail(payload.snapshot(for: options)?.range))
        XCTAssertTrue(ContextualMetricSharePolicy.hasDetail(payload.snapshot(for: options)?.trend))
        XCTAssertTrue(ContextualMetricSharePolicy.hasDetail(payload.snapshot(for: options)?.provenance))
        options.selectedMetric = .bodyFat
        XCTAssertTrue(ContextualMetricSharePolicy.hasDetail(payload.snapshot(for: options)?.observation))
        XCTAssertFalse(ContextualMetricSharePolicy.hasDetail(payload.snapshot(for: options)?.range))
        XCTAssertFalse(ContextualMetricSharePolicy.hasDetail(payload.snapshot(for: options)?.trend))
        XCTAssertFalse(ContextualMetricSharePolicy.hasDetail(payload.snapshot(for: options)?.provenance))
        options.includeProvenance = true
        XCTAssertEqual(payload.snapshot(for: options)?.detail(options: options), "Synthetic date",
                       "Hidden blank fields must not leave inert text or separator fragments in the export")
    }
}
