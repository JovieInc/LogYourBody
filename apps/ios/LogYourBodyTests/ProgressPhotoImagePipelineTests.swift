//
// DashboardTimelineAndPolicyTests.swift
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


@MainActor
final class ProgressPhotoImagePipelineTests: XCTestCase {
    func testFilmstripDecodesTargetSizedPixelsAndRejectsMalformedData() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 2_400, height: 1_800)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let data = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let decoded = await ProgressPhotoImagePipeline.decodeAndOptimizeImage(from: data, maxPixelSize: 160)
        let thumbnail = try XCTUnwrap(decoded)
        XCTAssertEqual(thumbnail.size.width, 160, accuracy: 1)
        XCTAssertEqual(thumbnail.size.height, 120, accuracy: 1)
        XCTAssertEqual(thumbnail.imageOrientation, .up)
        XCTAssertLessThanOrEqual(ProgressPhotoImagePipeline.cacheCost(for: thumbnail), 160 * 160 * 4)
        let malformed = await ProgressPhotoImagePipeline.decodeAndOptimizeImage(from: Data([0, 1]), maxPixelSize: 160)
        XCTAssertNil(malformed)
        let invalidSize = await ProgressPhotoImagePipeline.decodeAndOptimizeImage(from: data, maxPixelSize: 0)
        XCTAssertNil(invalidSize)
    }

    func testThumbnailCacheCannotReplaceHeroImageAndEvictsBothVariants() async throws {
        let size = CGSize(width: 800, height: 1_000)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("filmstrip-\(UUID().uuidString).jpg")
        try XCTUnwrap(image.jpegData(compressionQuality: 0.8)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = ImageCacheService()
        let small = try XCTUnwrap(await cache.loadThumbnail(from: url.absoluteString))
        let large = try XCTUnwrap(await cache.loadImage(from: url.absoluteString))
        XCTAssertEqual(small.size.height, 160, accuracy: 1)
        XCTAssertEqual(small.size.width, 128, accuracy: 1)
        XCTAssertGreaterThan(large.size.height, 160)
        let retained = try XCTUnwrap(await cache.loadThumbnail(from: url.absoluteString))
        XCTAssertTrue(small === retained)
        cache.clearImage(url.absoluteString)
        try FileManager.default.removeItem(at: url)
        let cleared = await cache.loadThumbnail(from: url.absoluteString)
        XCTAssertNil(cleared)
        XCTAssertNil(cache.cachedImage(for: url.absoluteString))
    }

    func testOptimizeImageDownsamplesLargeImages() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2_400, height: 1_800), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 1_800))
        }

        let optimized = ProgressPhotoImagePipeline.optimizeImage(image, maxDimension: 1_200)

        XCTAssertLessThanOrEqual(max(optimized.size.width, optimized.size.height), 1_200)
        XCTAssertEqual(optimized.size.width, 1_200, accuracy: 1)
        XCTAssertEqual(optimized.size.height, 900, accuracy: 1)
    }

    func testCacheCostUsesPixelBytesWithoutEncodingImageData() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        }

        XCTAssertEqual(ProgressPhotoImagePipeline.cacheCost(for: image), 20_000)
    }

    func testResolvedImageLoadsAndCachesLocalPhotoForShareExport() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 180)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 120, height: 180))
        }
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lyb-share-cache-\(UUID().uuidString).png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let first = await OptimizedProgressPhotoView.resolvedImage(for: url.absoluteString)
        let second = await OptimizedProgressPhotoView.resolvedImage(for: url.absoluteString)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(first?.size.width, second?.size.width)
        XCTAssertEqual(first?.size.height, second?.size.height)
    }
}
