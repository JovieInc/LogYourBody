//
// BackgroundRemovalServiceTests.swift
// LogYourBodyTests
//
// KNOWN APP BUG (reported, not fixed): on the iOS simulator,
// removeBackground(from:) crashes the process. Measured on iPhone 17 /
// iOS 26.5 (2026-07): VNGeneratePersonSegmentationRequest delivers
// com.apple.VisionCore Code=1 ("E5RT is not supported") — and BOTH the request
// completion handler and handler.perform report the failure, so the
// withCheckedThrowingContinuation in removeBackground is resumed twice and the
// runtime traps ("attempted to resume a continuation more than once"). The
// Vision path of removeBackground is therefore deliberately untested here:
// any test calling it would kill the test host. On-device (where person
// segmentation is supported) perform does not throw after a completion, so
// the double-resume is latent there but still structurally possible.
//
import XCTest
import UIKit
@testable import LogYourBody

final class BackgroundRemovalServiceTests: XCTestCase {
    // MARK: - Input validation

    func testRemoveBackgroundRejectsImageWithoutCGImage() async throws {
        // This guard runs before the Vision continuation, so it is safe to
        // exercise despite the simulator crash documented in the file header.
        let ciBacked = UIImage(ciImage: CIImage(color: .red))

        do {
            _ = try await BackgroundRemovalService.shared.removeBackground(from: ciBacked)
            XCTFail("CIImage-backed input must be rejected as invalid")
        } catch {
            XCTAssertEqual(error as? BackgroundRemovalService.BackgroundRemovalError, .invalidImage)
        }
    }

    // MARK: - applySegmentationMask (CoreImage, deterministic)

    func testApplySegmentationMaskWithFullMaskKeepsSubjectOpaque() throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 64, height: 64, red: 255, green: 0, blue: 0))
        let mask = try XCTUnwrap(SyntheticImage.constantMask(width: 64, height: 64, value: 255))

        let output = try BackgroundRemovalService.shared.applySegmentationMask(to: cgImage, mask: mask, quality: 0.85)

        let outputCG = try XCTUnwrap(output.cgImage)
        XCTAssertEqual(outputCG.width, 64)
        XCTAssertEqual(outputCG.height, 64)
        let center = try XCTUnwrap(SyntheticImage.pixel(of: outputCG, x: 32, y: 32))
        XCTAssertGreaterThan(center.alpha, 240, "full-strength mask must keep the subject")
        XCTAssertGreaterThan(center.red, 200)
        XCTAssertLessThan(center.blue, 60)
    }

    func testApplySegmentationMaskWithEmptyMaskRemovesEverything() throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 64, height: 64, red: 255, green: 0, blue: 0))
        let mask = try XCTUnwrap(SyntheticImage.constantMask(width: 64, height: 64, value: 0))

        let output = try BackgroundRemovalService.shared.applySegmentationMask(to: cgImage, mask: mask, quality: 0.85)

        let outputCG = try XCTUnwrap(output.cgImage)
        let center = try XCTUnwrap(SyntheticImage.pixel(of: outputCG, x: 32, y: 32))
        XCTAssertLessThan(center.alpha, 15, "zero mask must produce a fully transparent cutout")
    }

    func testApplySegmentationMaskScalesSmallMaskUpToImageSize() throws {
        // Vision masks are lower-resolution than the source; the service must
        // scale the mask to the image extent (output keeps image dimensions).
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 64, height: 64, red: 255, green: 0, blue: 0))
        let mask = try XCTUnwrap(SyntheticImage.constantMask(width: 16, height: 16, value: 255))

        let output = try BackgroundRemovalService.shared.applySegmentationMask(to: cgImage, mask: mask, quality: 0.85)

        let outputCG = try XCTUnwrap(output.cgImage)
        XCTAssertEqual(outputCG.width, 64)
        XCTAssertEqual(outputCG.height, 64)
        let center = try XCTUnwrap(SyntheticImage.pixel(of: outputCG, x: 32, y: 32))
        XCTAssertGreaterThan(center.alpha, 240)
    }

    // MARK: - prepareForUpload downscale math

    func testPrepareForUploadDoesNotUpscaleSmallerImages() async throws {
        // No-upscale rule: an image already inside the bounds passes through
        // at its original size.
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 800, height: 1_000))

        let prepared = await BackgroundRemovalService.shared.prepareForUpload(UIImage(cgImage: cgImage))
        let data = try XCTUnwrap(prepared)

        let decoded = try XCTUnwrap(SyntheticImage.decodePNG(data))
        XCTAssertEqual(decoded.width, 800)
        XCTAssertEqual(decoded.height, 1_000)
    }

    func testPrepareForUploadDownscalesWidthConstrainedImagePreservingAspect() async throws {
        // 2400x1600 landscape: scale = min(1200/2400, 1600/1600) = 0.5 → 1200x800.
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 2_400, height: 1_600))

        let prepared = await BackgroundRemovalService.shared.prepareForUpload(UIImage(cgImage: cgImage))
        let data = try XCTUnwrap(prepared)

        let decoded = try XCTUnwrap(SyntheticImage.decodePNG(data))
        XCTAssertEqual(decoded.width, 1_200)
        XCTAssertEqual(decoded.height, 800)
    }

    func testPrepareForUploadDownscalesHeightConstrainedImagePreservingAspect() async throws {
        // 1200x2400 portrait: scale = min(1200/1200, 1600/2400) = 2/3 → 800x1600.
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 1_200, height: 2_400))

        let prepared = await BackgroundRemovalService.shared.prepareForUpload(UIImage(cgImage: cgImage))
        let data = try XCTUnwrap(prepared)

        let decoded = try XCTUnwrap(SyntheticImage.decodePNG(data))
        XCTAssertEqual(decoded.width, 800)
        XCTAssertEqual(decoded.height, 1_600)
    }

    func testPrepareForUploadHonorsCustomMaxSize() async throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 2_000, height: 2_000))

        let prepared = await BackgroundRemovalService.shared.prepareForUpload(
            UIImage(cgImage: cgImage),
            maxSize: CGSize(width: 500, height: 250)
        )
        let data = try XCTUnwrap(prepared)

        let decoded = try XCTUnwrap(SyntheticImage.decodePNG(data))
        XCTAssertEqual(decoded.width, 250)
        XCTAssertEqual(decoded.height, 250)
    }

    // MARK: - prepareForUpload output format contract

    func testPrepareForUploadEmitsPNGData() async throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 64, height: 64))

        let prepared = await BackgroundRemovalService.shared.prepareForUpload(UIImage(cgImage: cgImage))
        let data = try XCTUnwrap(prepared)

        // PNG magic bytes — the upload contract requires PNG to keep alpha.
        XCTAssertTrue(data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    func testPrepareForUploadPreservesTransparency() async throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 4, height: 4, red: 255, green: 0, blue: 0, alpha: 0))

        let prepared = await BackgroundRemovalService.shared.prepareForUpload(UIImage(cgImage: cgImage))
        let data = try XCTUnwrap(prepared)

        let decoded = try XCTUnwrap(SyntheticImage.decodePNG(data))
        let pixel = try XCTUnwrap(SyntheticImage.pixel(of: decoded, x: 2, y: 2))
        XCTAssertLessThan(pixel.alpha, 15, "alpha channel must survive the PNG round trip")
    }

    // MARK: - Error contract

    func testBackgroundRemovalErrorDescriptionsMatchDocumentedContract() {
        XCTAssertEqual(
            BackgroundRemovalService.BackgroundRemovalError.noPersonFound.errorDescription,
            "No person detected in the image"
        )
        XCTAssertEqual(
            BackgroundRemovalService.BackgroundRemovalError.processingFailed.errorDescription,
            "Failed to process the image"
        )
        XCTAssertEqual(
            BackgroundRemovalService.BackgroundRemovalError.invalidImage.errorDescription,
            "Invalid image format"
        )
    }
}
