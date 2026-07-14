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
        await counter.increment()

        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }

        return image
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
