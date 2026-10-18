//
// HomeV2PhotoJourneyPolicyTests.swift
// LogYourBodyTests
//
import UIKit
import XCTest
@testable import LogYourBody

final class HomeV2PhotoJourneyPolicyTests: XCTestCase {
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

    @MainActor
    func testBoundedTimelapsePreparationRequiresItsRolloutGate() {
        XCTAssertFalse(HomeV2TimelapsePolicy.usesBoundedPrefetch(arguments: [], environment: [:]) { key in
            XCTAssertEqual(key, "home_v2_timelapse_bounded_prefetch_v1")
            return false
        })
        XCTAssertTrue(HomeV2TimelapsePolicy.usesBoundedPrefetch(arguments: [], environment: [:]) { _ in true })
    }

    @MainActor
    func testTimelapsePrefetchFixtureRequiresAnAuthenticatedUITestProcess() {
        let arguments = [HomeV2TimelapsePolicy.prefetchFixtureArgument,
                         "-lybUITestPhotoTimelineHUDFixture", HomeV2Policy.photoFixtureArgument]
        let environment = ["XCTestSessionIdentifier": UUID().uuidString,
                           "XCTestBundlePath": "/Tests/LogYourBodyUITests.xctest"]
        #if DEBUG
        XCTAssertTrue(HomeV2TimelapsePolicy.usesBoundedPrefetch(
            arguments: arguments, environment: environment, isGateEnabled: { _ in false }
        ))
        XCTAssertFalse(HomeV2TimelapsePolicy.usesBoundedPrefetch(
            arguments: arguments + [HomeV2Policy.rollbackFixtureArgument],
            environment: environment, isGateEnabled: { _ in false }
        ))
        #endif
        XCTAssertFalse(HomeV2TimelapsePolicy.usesBoundedPrefetch(
            arguments: arguments, environment: [:], isGateEnabled: { _ in false }
        ))
        XCTAssertFalse(HomeV2TimelapsePolicy.usesBoundedPrefetch(
            arguments: arguments + [HomeV2TimelapsePolicy.prefetchFixtureArgument],
            environment: environment, isGateEnabled: { _ in false }
        ))
    }

    @MainActor
    func testTimelapseLongHistoryLoadsOnlyCurrentAndTwoUpcomingFrames() async {
        var events: [String] = []
        await HomeV2TimelapsePolicy.prepareWindow(
            from: 0, count: 3_000, loops: false,
            load: { events.append("load \($0)") },
            currentReady: { events.append("ready") }
        )
        XCTAssertEqual(events, ["load 0", "ready", "load 1", "load 2"])
    }

    func testTimelapseWindowHandlesEndLoopAndSmallHistoriesWithoutDuplicates() {
        XCTAssertEqual(HomeV2TimelapsePolicy.prefetchFrames(from: 2_999, count: 3_000, loops: false), [2_999])
        XCTAssertEqual(HomeV2TimelapsePolicy.prefetchFrames(from: 2_999, count: 3_000, loops: true), [2_999, 0, 1])
        XCTAssertEqual(HomeV2TimelapsePolicy.prefetchFrames(from: 1, count: 2, loops: true), [1, 0])
        XCTAssertEqual(HomeV2TimelapsePolicy.prefetchFrames(from: 0, count: 1, loops: true), [0])
        XCTAssertTrue(HomeV2TimelapsePolicy.prefetchFrames(from: 0, count: 0, loops: true).isEmpty)
        XCTAssertTrue(HomeV2TimelapsePolicy.prefetchFrames(from: -1, count: 3, loops: false).isEmpty)
        XCTAssertTrue(HomeV2TimelapsePolicy.prefetchFrames(from: 3, count: 3, loops: false).isEmpty)
    }

    @MainActor
    func testTimelapseIsReadyBeforeSlowSuccessorAndCancellationStopsFurtherPrefetch() async {
        let successorStarted = expectation(description: "Successor is loading")
        var resumeSuccessor: CheckedContinuation<Void, Never>?
        var loaded: [Int] = []
        var ready = false
        let task = Task {
            await HomeV2TimelapsePolicy.prepareWindow(
                from: 0, count: 3_000, loops: false,
                load: { frame in
                    loaded.append(frame)
                    if frame == 1 {
                        await withCheckedContinuation {
                            resumeSuccessor = $0
                            successorStarted.fulfill()
                        }
                    }
                },
                currentReady: { ready = true }
            )
        }
        await fulfillment(of: [successorStarted], timeout: 2)
        XCTAssertTrue(ready, "A slow future photo must not disable playback of the current photo")
        task.cancel()
        resumeSuccessor?.resume()
        await task.value
        XCTAssertEqual(loaded, [0, 1], "Leaving or scrubbing must not start another stale prefetch")
    }

    @MainActor
    func testCancelledCurrentFrameCannotPublishReadinessOrWarmSuccessors() async {
        let currentStarted = expectation(description: "Current photo is loading")
        var resumeCurrent: CheckedContinuation<Void, Never>?
        var loaded: [Int] = []
        var ready = false
        let task = Task {
            await HomeV2TimelapsePolicy.prepareWindow(
                from: 0, count: 3_000, loops: false,
                load: { frame in
                    loaded.append(frame)
                    await withCheckedContinuation {
                        resumeCurrent = $0
                        currentStarted.fulfill()
                    }
                },
                currentReady: { ready = true }
            )
        }
        await fulfillment(of: [currentStarted], timeout: 2)
        task.cancel()
        resumeCurrent?.resume()
        await task.value
        XCTAssertFalse(ready)
        XCTAssertEqual(loaded, [0])
    }

    @MainActor
    func testEmptyTimelapseDoesNotLoadOrPublishReadiness() async {
        await HomeV2TimelapsePolicy.prepareWindow(
            from: 0, count: 0, loops: true,
            load: { _ in XCTFail("There is no photo to load") },
            currentReady: { XCTFail("An empty history cannot play") }
        )
    }

    func testTimelapseScrubDuringPreparationAndPauseCannotBeOverridden() {
        var state = HomeV2TimelapsePlaybackState()
        state.select(2)
        state.prepared(frame: 0, count: 3)
        XCTAssertFalse(state.isReady, "The old preparation cannot enable a different frame")
        state.prepared(frame: 2, count: 3)
        XCTAssertTrue(state.isReady)
        XCTAssertFalse(state.isPlaying, "Scrubbing before readiness cancels initial autoplay")
        state.togglePlayback()
        XCTAssertTrue(state.isPlaying)
        state.togglePlayback()
        state.prepared(frame: 2, count: 3)
        XCTAssertFalse(state.isPlaying, "A restarted prefetch must preserve an explicit pause")
        state.select(2)
        XCTAssertTrue(state.isReady, "Selecting the same frame must not wait for a task that will not restart")
    }

    func testTimelapseAutoplaysOnlyOnceAndOnlyWithMultiplePhotos() {
        for count in [0, 1, 3] {
            var state = HomeV2TimelapsePlaybackState()
            state.prepared(frame: 0, count: count)
            XCTAssertEqual(state.isReady, count >= 1)
            XCTAssertEqual(state.isPlaying, count > 1)
            state.isPlaying = false
            state.prepared(frame: 0, count: count)
            XCTAssertFalse(state.isPlaying)
        }
        var legacy = HomeV2TimelapsePlaybackState()
        legacy.select(1, needsPreparation: false)
        XCTAssertFalse(legacy.isReady, "Legacy scrubbing still waits for its preparation task")
        legacy.prepared(frame: 1, count: 3)
        legacy.select(2, needsPreparation: false)
        XCTAssertTrue(legacy.isReady, "Legacy scrubbing retains completed preparation")
        XCTAssertFalse(legacy.isPlaying)
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

    func testPairToolsExplainInsufficientPhotosAndKeepNormalRoutes() {
        let pair = HomeV2PhotoPair(before: 1, after: 0)
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .compare, pair: nil), .insufficientPhotos(.compare))
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .share, pair: nil), .insufficientPhotos(.share))
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .compare, pair: pair), .compare(pair))
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .share, pair: pair), .share(pair))
        XCTAssertEqual(HomeV2PhotoRoute.destination(for: .allPhotos, pair: nil), .allPhotos)
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
}
