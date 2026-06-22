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
