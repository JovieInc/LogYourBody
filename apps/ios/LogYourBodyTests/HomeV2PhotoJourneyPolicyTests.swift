//
// HomeV2PhotoJourneyPolicyTests.swift
// LogYourBodyTests
//
import UIKit
import XCTest
@testable import LogYourBody

final class HomeV2PhotoJourneyPolicyTests: XCTestCase {
    private let calendar = Calendar.current

    private func day(_ daysAgo: Int) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date())) ?? Date()
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

    func testRulerSpansAtLeastEightWeeksAndFindsTheNearestPhoto() {
        let dates = [day(20), day(10), day(0)]
        let span = HomeV2PhotoRulerPolicy.span(for: dates)
        XCTAssertEqual(span.start, day(20))
        XCTAssertGreaterThanOrEqual(span.duration, TimeInterval(HomeV2PhotoRulerPolicy.minimumSpanDays * 24 * 60 * 60) - 1)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.fraction(of: day(20), in: span), 0, accuracy: 0.001)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: 0, dates: dates, span: span), 0)
        XCTAssertEqual(HomeV2PhotoRulerPolicy.nearestIndex(to: 1, dates: dates, span: span), 2)
        XCTAssertNil(HomeV2PhotoRulerPolicy.nearestIndex(to: 0.5, dates: [], span: span))
        XCTAssertGreaterThanOrEqual(HomeV2PhotoRulerPolicy.weekTicks(in: span).count, 8)
        XCTAssertFalse(HomeV2PhotoRulerPolicy.monthStarts(in: span).isEmpty)

        let long = HomeV2PhotoRulerPolicy.span(for: [day(200), day(0)])
        XCTAssertEqual(long.end, day(0))
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
