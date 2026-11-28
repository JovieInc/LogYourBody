//
// ImageCacheServiceTests.swift
// LogYourBodyTests
//

import XCTest
import UIKit
@testable import LogYourBody

@MainActor
final class ImageCacheServiceTests: XCTestCase {
    func testConcurrentLoadsForSameURLShareSinglePipelineRequest() async throws {
        let loader = CountingImageLoader(
            image: makeImage(color: .systemPurple),
            delayNanoseconds: 50_000_000
        )
        let service = ImageCacheService(
            imageLoader: loader,
            notificationCenter: NotificationCenter()
        )
        let url = "https://example.com/progress-photo.jpg"

        async let first = service.loadImage(from: url)
        async let second = service.loadImage(from: url)

        let images = await [first, second]
        let loadCount = await loader.loadCount()

        XCTAssertEqual(loadCount, 1)
        XCTAssertNotNil(images[0])
        XCTAssertNotNil(images[1])
        XCTAssertEqual(images[0]?.size, images[1]?.size)
    }

    func testCachedImagePreventsSecondPipelineRequest() async throws {
        let loader = CountingImageLoader(
            image: makeImage(color: .systemTeal),
            delayNanoseconds: 0
        )
        let service = ImageCacheService(
            imageLoader: loader,
            notificationCenter: NotificationCenter()
        )
        let url = "https://example.com/cached-progress-photo.jpg"

        let first = await service.loadImage(from: url)
        let second = await service.loadImage(from: url)
        let loadCount = await loader.loadCount()

        XCTAssertEqual(loadCount, 1)
        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotNil(service.cachedImage(for: url))
    }

    func testMemoryWarningClearsCachedImage() async throws {
        let notificationCenter = NotificationCenter()
        let loader = CountingImageLoader(
            image: makeImage(color: .systemBlue),
            delayNanoseconds: 0
        )
        let service = ImageCacheService(
            imageLoader: loader,
            notificationCenter: notificationCenter
        )
        let url = "https://example.com/photo-before-memory-warning.jpg"

        let image = await service.loadImage(from: url)
        XCTAssertNotNil(image)
        XCTAssertNotNil(service.cachedImage(for: url))

        notificationCenter.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)

        XCTAssertNil(service.cachedImage(for: url))
    }

    func testPreloadImagesLoadsAllDistinctURLsWithBoundedConcurrency() async throws {
        let loader = CountingImageLoader(image: makeImage(color: .systemGreen), delayNanoseconds: 0)
        let service = ImageCacheService(imageLoader: loader, notificationCenter: NotificationCenter())
        // More URLs than the concurrency cap (4) to prove the sliding window still
        // covers every item rather than dropping the tail.
        let urls = (0..<7).map { "https://example.com/preload-\($0).jpg" }

        service.preloadImages(urls)

        // preloadImages is fire-and-forget; poll until every distinct URL loaded.
        try await waitUntil { await loader.loadCount() == urls.count }

        let cachedCount = urls.filter { service.cachedImage(for: $0) != nil }.count
        XCTAssertEqual(cachedCount, urls.count)
    }

    func testPreloadImagesSkipsEmptyURLs() async throws {
        let loader = CountingImageLoader(image: makeImage(color: .systemOrange), delayNanoseconds: 0)
        let service = ImageCacheService(imageLoader: loader, notificationCenter: NotificationCenter())

        service.preloadImages(["https://example.com/a.jpg", "", "https://example.com/b.jpg", ""])

        try await waitUntil { await loader.loadCount() == 2 }
        // Give any erroneous empty-string load a chance to register before asserting.
        try await Task.sleep(nanoseconds: 20_000_000)
        let loadCount = await loader.loadCount()
        XCTAssertEqual(loadCount, 2)
    }

    func testCacheCountAndCostLimitsStay() {
        XCTAssertEqual(ImageCacheService.cacheCountLimit, 100)
        XCTAssertEqual(ImageCacheService.cacheCostLimit, 100 * 1_024 * 1_024)
        let service = ImageCacheService(
            imageLoader: CountingImageLoader(image: makeImage(color: .systemGray), delayNanoseconds: 0),
            notificationCenter: NotificationCenter()
        )
        XCTAssertEqual(service.cacheCountLimitForTests, ImageCacheService.cacheCountLimit)
        XCTAssertEqual(service.cacheCostLimitForTests, ImageCacheService.cacheCostLimit)
    }

    func testCancelledPrefetchDoesNotInstallImage() async throws {
        let loader = CountingImageLoader(image: makeImage(color: .systemRed), delayNanoseconds: 400_000_000)
        let service = ImageCacheService(imageLoader: loader, notificationCenter: NotificationCenter())
        let url = "https://example.com/cancelled-prefetch.jpg"

        let task = Task { await service.loadImage(from: url, maxPixelSize: 200) }
        try await waitUntil { await loader.loadCount() == 1 }
        task.cancel()
        let image = await task.value

        XCTAssertNil(image)
        XCTAssertNil(service.cachedImage(for: url, maxPixelSize: 200))
        XCTAssertNil(service.cachedImage(for: url))
        // A late decode must not fill the slot after the scrub has moved on.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(service.cachedImage(for: url, maxPixelSize: 200))
    }

    func testDifferentPixelSizeDoesNotReuseCachedBitmap() async throws {
        let loader = CountingImageLoader(image: makeImage(color: .systemIndigo), delayNanoseconds: 0)
        let service = ImageCacheService(imageLoader: loader, notificationCenter: NotificationCenter())
        let url = "https://example.com/sized-photo.jpg"

        let small = await service.loadImage(from: url, maxPixelSize: 40)
        let large = await service.loadImage(from: url, maxPixelSize: 120)
        let smallAgain = await service.loadImage(from: url, maxPixelSize: 40)
        let loadCount = await loader.loadCount()
        let smallImage = try XCTUnwrap(small)
        let largeImage = try XCTUnwrap(large)

        XCTAssertEqual(smallImage.size.width, 40, accuracy: 0.5)
        XCTAssertEqual(largeImage.size.width, 120, accuracy: 0.5)
        XCTAssertFalse(smallImage === largeImage)
        XCTAssertTrue(small === smallAgain)
        XCTAssertEqual(loadCount, 2)
        XCTAssertNil(service.cachedImage(for: url))
        XCTAssertTrue(service.cachedImage(for: url, maxPixelSize: 40) === small)
        XCTAssertTrue(service.cachedImage(for: url, maxPixelSize: 120) === large)
    }

    func testPreloadDeduplicatesPerURLAndPixelSize() async throws {
        let loader = CountingImageLoader(image: makeImage(color: .systemGreen), delayNanoseconds: 0)
        let service = ImageCacheService(imageLoader: loader, notificationCenter: NotificationCenter())
        let url = "https://example.com/neighbor.jpg"

        service.preloadImages([url, url, ""], maxPixelSize: 64)
        service.preloadImages([url], maxPixelSize: 96)

        try await waitUntil { await loader.loadCount() == 2 }
        try await Task.sleep(nanoseconds: 20_000_000)
        let loadCount = await loader.loadCount()
        let small = service.cachedImage(for: url, maxPixelSize: 64)
        let large = service.cachedImage(for: url, maxPixelSize: 96)
        let smallImage = try XCTUnwrap(small)
        let largeImage = try XCTUnwrap(large)

        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(smallImage.size.width, 64, accuracy: 0.5)
        XCTAssertEqual(largeImage.size.width, 96, accuracy: 0.5)
        XCTAssertFalse(smallImage === largeImage)
    }

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        _ condition: () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }

    private func makeImage(color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 80, height: 120))
        }
    }
}

private final class CountingImageLoader: ProgressPhotoImageLoading {
    private let image: UIImage
    private let delayNanoseconds: UInt64
    private let counter = LoadCounter()

    init(image: UIImage, delayNanoseconds: UInt64) {
        self.image = image
        self.delayNanoseconds = delayNanoseconds
    }

    func loadCount() async -> Int {
        await counter.current()
    }

    func loadImage(urlString _: String) async throws -> UIImage {
        try await nextImage(sized: nil)
    }

    func loadImage(urlString _: String, maxPixelSize: Int) async throws -> UIImage {
        try await nextImage(sized: maxPixelSize)
    }

    private func nextImage(sized maxPixelSize: Int?) async throws -> UIImage {
        await counter.increment()
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        guard let maxPixelSize else { return image }
        let side = CGFloat(max(maxPixelSize, 1))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.systemRed.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        }
    }
}

private actor LoadCounter {
    private var value = 0

    func increment() {
        value += 1
    }

    func current() -> Int {
        value
    }
}
