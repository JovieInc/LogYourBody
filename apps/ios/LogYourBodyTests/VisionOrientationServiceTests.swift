//
// VisionOrientationServiceTests.swift
// LogYourBodyTests
//
import XCTest
import UIKit
@testable import LogYourBody

@MainActor
final class VisionOrientationServiceTests: XCTestCase {
    // MARK: - Fallback behavior (deterministic on simulator)

    func testCorrectImageOrientationReturnsCIImageBackedInputAsIs() async throws {
        // The pre-Vision guard returns the input untouched when no CGImage exists.
        let ciBacked = UIImage(ciImage: CIImage(color: .red))

        let result = try await VisionOrientationService.shared.correctImageOrientation(ciBacked)

        XCTAssertTrue(result === ciBacked)
    }

    func testCorrectImageOrientationOnPersonLessImageReturnsOriginalUnrotated() async throws {
        // Pinned simulator behavior (measured 2026-07, iPhone 17 / iOS 26.5):
        // VNDetectHumanBodyPoseRequest.perform throws com.apple.Vision Code=9
        // ("Unable to setup request"), the service catches it and falls back to
        // VNDetectFaceRectanglesRequest, whose perform also throws Code=9, that
        // fallback catches too, and the contract is "return the caller's image
        // unmodified". Every Vision failure path in this service funnels to
        // returning the original instance, so identity is the stable assertion.
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 512, height: 512))
        let image = UIImage(cgImage: cgImage)

        let result = try await VisionOrientationService.shared.correctImageOrientation(image)

        XCTAssertTrue(result === image, "no body/face detected must return the original image instance")
    }

    // MARK: - rotateImage geometry

    func testRotateImageByRightAnglesSwapsDimensionsOnlyForQuarterTurns() throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 100, height: 200))
        let image = UIImage(cgImage: cgImage)

        XCTAssertEqual(
            VisionOrientationService.shared.rotateImage(image, byDegrees: 90).size,
            CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(
            VisionOrientationService.shared.rotateImage(image, byDegrees: -90).size,
            CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(
            VisionOrientationService.shared.rotateImage(image, byDegrees: 270).size,
            CGSize(width: 200, height: 100)
        )
        XCTAssertEqual(
            VisionOrientationService.shared.rotateImage(image, byDegrees: 180).size,
            CGSize(width: 100, height: 200)
        )
    }

    func testRotateImageByZeroKeepsContentIntact() throws {
        let cgImage = try XCTUnwrap(SyntheticImage.horizontalSplitCGImage(
            width: 100,
            height: 200,
            top: (red: 255, green: 0, blue: 0, alpha: 255),
            bottom: (red: 0, green: 0, blue: 255, alpha: 255)
        ))
        let image = UIImage(cgImage: cgImage)

        let rotated = VisionOrientationService.shared.rotateImage(image, byDegrees: 0)

        XCTAssertEqual(rotated.size, CGSize(width: 100, height: 200))
        let rotatedCG = try XCTUnwrap(rotated.cgImage)
        let topPixel = try XCTUnwrap(SyntheticImage.pixel(of: rotatedCG, x: 50, y: 25))
        XCTAssertGreaterThan(topPixel.red, 200)
        XCTAssertLessThan(topPixel.blue, 60)
        let bottomPixel = try XCTUnwrap(SyntheticImage.pixel(of: rotatedCG, x: 50, y: 175))
        XCTAssertGreaterThan(bottomPixel.blue, 200)
        XCTAssertLessThan(bottomPixel.red, 60)
    }

    // MARK: - Error contract

    func testVisionErrorDescriptionsMatchDocumentedContract() {
        XCTAssertEqual(
            VisionOrientationService.VisionError.insufficientConfidence.errorDescription,
            "Could not confidently detect body orientation"
        )
        XCTAssertEqual(
            VisionOrientationService.VisionError.noBodyDetected.errorDescription,
            "No human body detected in image"
        )
        XCTAssertEqual(
            VisionOrientationService.VisionError.noFaceDetected.errorDescription,
            "No face detected in image"
        )
    }
}
