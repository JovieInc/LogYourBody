//
// BackgroundRemovalServiceTests.swift
// LogYourBodyTests
//
// removeBackground(from:) runs Vision synchronously off the main actor and
// reads `request.results` after `perform` returns. There is no completion
// handler, so an unsupported platform (the simulator reports
// com.apple.VisionCore Code=1, "E5RT is not supported") surfaces as a thrown
// error instead of the double-resumed continuation that used to trap the
// test host.
//
import XCTest
import UIKit
@testable import LogYourBody

final class BackgroundRemovalServiceTests: XCTestCase {
    // MARK: - Input validation

    func testRemoveBackgroundSurfacesUnsupportedSegmentationAsAnErrorNotATrap() async throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 32, height: 40, red: 120, green: 120, blue: 120))

        do {
            let output = try await BackgroundRemovalService.shared.removeBackground(from: UIImage(cgImage: cgImage))
            XCTAssertEqual(output.cgImage?.width, 32, "when segmentation is supported the output keeps its size")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty, "unsupported segmentation must throw, never trap")
        }
    }

    func testRemoveBackgroundRejectsImageWithoutCGImage() async throws {
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
