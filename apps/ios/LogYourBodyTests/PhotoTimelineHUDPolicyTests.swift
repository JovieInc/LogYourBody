//
// AccountDeletionAndShareCardTests.swift
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


final class PhotoTimelineHUDPolicyTests: XCTestCase {
    func testPhotoTimelineHUDIsDefaultV1Surface() {
        XCTAssertTrue(PhotoTimelineHUDPolicy.defaultShowsPhotoTimelineHUD)
        XCTAssertTrue(PhotoTimelineHUDPolicy.shouldShowPhotoTimelineHUD())
        XCTAssertEqual(PaidAppSurfacePolicy.surface(), .photoTimelineHUD)
    }

    func testDefaultHomeModeDefaultsToAvatar() {
        XCTAssertEqual(Constants.defaultHomeModeKey, "defaultHomeMode")
        XCTAssertEqual(Constants.onboardingCompletedUserIdKey, "onboardingCompletedUserId")
        XCTAssertEqual(DefaultHomeMode.default, .avatar)
        XCTAssertEqual(DefaultHomeMode(storedValue: "photo"), .photo)
        XCTAssertEqual(DefaultHomeMode(storedValue: "unexpected"), .avatar)
        XCTAssertEqual(DefaultHomeMode.avatar.timelineMode, .avatar)
        XCTAssertEqual(DefaultHomeMode.photo.timelineMode, .photo)
        XCTAssertEqual(DefaultHomeMode(timelineMode: .avatar), .avatar)
        XCTAssertEqual(DefaultHomeMode(timelineMode: .photo), .photo)
    }

    func testAvatarBodyFatCatalogSelectsNearestMaleBucket() {
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 16.4, gender: "male"),
            AvatarBodyFatCatalog.Match(sex: .male, bucket: 15)
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 20.2, gender: "male").assetName,
            "avatar_male_22"
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 80, gender: "male").bucket,
            55
        )
    }

    func testAvatarBodyFatCatalogSelectsNearestFemaleBucket() {
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 22.4, gender: "female"),
            AvatarBodyFatCatalog.Match(sex: .female, bucket: 21)
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 45.2, gender: "woman").assetName,
            "avatar_female_50"
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: 72, gender: "f").bucket,
            60
        )
    }

    func testAvatarBodyFatCatalogUsesSexSpecificDefaultsWhenBodyFatIsMissing() {
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: nil, gender: "male").assetName,
            "avatar_male_18"
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: nil, gender: "female").assetName,
            "avatar_female_28"
        )
        XCTAssertEqual(
            AvatarBodyFatCatalog.match(bodyFatPercentage: nil, gender: nil).assetName,
            "avatar_male_18"
        )
    }

    func testAvatarBodyFatAssetsHaveTransparentSourceBackgrounds() throws {
        let assetNames = AvatarBodyFatCatalog.Sex.male.buckets.map {
            AvatarBodyFatCatalog.Match(sex: .male, bucket: $0).assetName
        } + AvatarBodyFatCatalog.Sex.female.buckets.map {
            AvatarBodyFatCatalog.Match(sex: .female, bucket: $0).assetName
        }

        for assetName in assetNames {
            let image = try XCTUnwrap(UIImage(named: assetName), "\(assetName) should exist in the app asset catalog")
            let perimeterAlphaValues = try renderedPerimeterAlphaValues(for: image)

            XCTAssertTrue(
                perimeterAlphaValues.allSatisfy { $0 <= 4 },
                "\(assetName) should not retain the black source-image rectangle"
            )
        }
    }

    func testPhotoTimelineHUDMetricStateCopyIsExplicit() {
        XCTAssertEqual(PhotoTimelineHUDPolicy.stateText(presence: .present), "Measured")
        XCTAssertEqual(
            PhotoTimelineHUDPolicy.stateText(presence: .interpolated, confidence: .medium),
            "Interpolated - medium confidence"
        )
        XCTAssertEqual(PhotoTimelineHUDPolicy.stateText(presence: .lastKnown), "Last known")
        XCTAssertEqual(PhotoTimelineHUDPolicy.stateText(presence: .missing), "Missing")
    }

    private func renderedPerimeterAlphaValues(for image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var alphaValues: [UInt8] = []
        alphaValues.reserveCapacity((width * 2) + (height * 2))

        for xValue in 0..<width {
            alphaValues.append(alphaValue(in: pixels, width: width, x: xValue, y: 0))
            alphaValues.append(alphaValue(in: pixels, width: width, x: xValue, y: height - 1))
        }

        for yValue in 0..<height {
            alphaValues.append(alphaValue(in: pixels, width: width, x: 0, y: yValue))
            alphaValues.append(alphaValue(in: pixels, width: width, x: width - 1, y: yValue))
        }

        return alphaValues
    }

    private func alphaValue(in pixels: [UInt8], width: Int, x: Int, y: Int) -> UInt8 {
        let bytesPerPixel = 4
        let index = (y * width + x) * bytesPerPixel + 3
        return pixels[index]
    }
}
