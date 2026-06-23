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
