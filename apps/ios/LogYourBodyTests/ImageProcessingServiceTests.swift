//
// ImageProcessingServiceTests.swift
// LogYourBodyTests
//
import XCTest
import UIKit
@testable import LogYourBody

final class ImageProcessingServiceTests: XCTestCase {
    // MARK: - cropToHuman: normalized Vision rect → pixel rect

    func testCropToHumanConvertsNormalizedRectToPixelCoordinates() throws {
        let service = ImageProcessingService()
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 400, height: 600))

        // Vision boxes are normalized with a bottom-left origin; CGImage pixels
        // are top-left origin, so y must flip: pixelY = (1 - maxY) * height.
        let cropped = try service.cropToHuman(
            cgImage: cgImage,
            boundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        )

        let croppedCG = try XCTUnwrap(cropped.cgImage)
        XCTAssertEqual(croppedCG.width, 200)
        XCTAssertEqual(croppedCG.height, 300)
    }

    func testCropToHumanFlipsVisionYAxisOntoImageRows() throws {
        let service = ImageProcessingService()
        // CG row 0 (top) is red; bottom half is blue.
        let cgImage = try XCTUnwrap(SyntheticImage.horizontalSplitCGImage(
            width: 400,
            height: 600,
            top: (red: 255, green: 0, blue: 0, alpha: 255),
            bottom: (red: 0, green: 0, blue: 255, alpha: 255)
        ))

        // Vision's bottom half (y 0...0.5, bottom-left origin) must map to the
        // blue (CG-bottom) rows, not the red ones.
        let bottomHalf = try service.cropToHuman(
            cgImage: cgImage,
            boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.5)
        )
        let bottomPixel = try XCTUnwrap(SyntheticImage.pixel(of: XCTUnwrap(bottomHalf.cgImage), x: 200, y: 150))
        XCTAssertGreaterThan(bottomPixel.blue, 200)
        XCTAssertLessThan(bottomPixel.red, 60)

        // Vision's top half must map to the red (CG-top) rows.
        let topHalf = try service.cropToHuman(
            cgImage: cgImage,
            boundingBox: CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        )
        let topPixel = try XCTUnwrap(SyntheticImage.pixel(of: XCTUnwrap(topHalf.cgImage), x: 200, y: 150))
        XCTAssertGreaterThan(topPixel.red, 200)
        XCTAssertLessThan(topPixel.blue, 60)
    }

    func testCropToHumanWithRectFullyOutsideImageThrowsCropFailed() throws {
        let service = ImageProcessingService()
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 400, height: 600))

        // A normalized rect starting at (2, 2) lies entirely outside the image;
        // CGImage.cropping returns nil and the pipeline must surface cropFailed.
        XCTAssertThrowsError(try service.cropToHuman(
            cgImage: cgImage,
            boundingBox: CGRect(x: 2, y: 2, width: 0.5, height: 0.5)
        )) { error in
            XCTAssertEqual(error as? ProcessingError, .cropFailed)
        }
    }

    // MARK: - aspectFillToSize: scale math

    func testAspectFillToSizeFillsTargetDimensionsExactly() throws {
        let service = ImageProcessingService()
        let target = CGSize(width: 600, height: 800)
        // Wide, tall, exact, and larger sources must all come out at exactly the
        // target size: scale = max(targetW/sourceW, targetH/sourceH).
        let sources = [
            (width: 1_000, height: 500),
            (width: 500, height: 1_000),
            (width: 600, height: 800),
            (width: 1_200, height: 1_600)
        ]

        for source in sources {
            let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: source.width, height: source.height))
            let output = try service.aspectFillToSize(
                UIImage(cgImage: cgImage),
                targetSize: target,
                centerOnPerson: false
            )
            let outputCG = try XCTUnwrap(output.cgImage)
            XCTAssertEqual(outputCG.width, 600, "source \(source.width)x\(source.height)")
            XCTAssertEqual(outputCG.height, 800, "source \(source.width)x\(source.height)")
        }
    }

    func testAspectFillToSizeUpscalesSmallSourcesToFillTarget() throws {
        let service = ImageProcessingService()
        // Aspect-fill has no no-upscale rule: a source smaller than the target
        // is scaled up so the target is fully covered.
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 300, height: 400))

        let output = try service.aspectFillToSize(
            UIImage(cgImage: cgImage),
            targetSize: CGSize(width: 600, height: 800),
            centerOnPerson: false
        )

        let outputCG = try XCTUnwrap(output.cgImage)
        XCTAssertEqual(outputCG.width, 600)
        XCTAssertEqual(outputCG.height, 800)
    }

    func testAspectFillToSizeCentersTheCropWindowOnTheSource() throws {
        let service = ImageProcessingService()
        // Left half red, right half blue. Scale = max(600/1000, 800/500) = 1.6,
        // so the 600-wide output window is centered: source x range 312.5...687.5,
        // which straddles the red/blue seam at x=500 exactly at output center.
        let cgImage = try XCTUnwrap(SyntheticImage.verticalSplitCGImage(
            width: 1_000,
            height: 500,
            left: (red: 255, green: 0, blue: 0, alpha: 255),
            right: (red: 0, green: 0, blue: 255, alpha: 255)
        ))

        let output = try service.aspectFillToSize(
            UIImage(cgImage: cgImage),
            targetSize: CGSize(width: 600, height: 800),
            centerOnPerson: false
        )
        let outputCG = try XCTUnwrap(output.cgImage)

        let leftPixel = try XCTUnwrap(SyntheticImage.pixel(of: outputCG, x: 150, y: 400))
        XCTAssertGreaterThan(leftPixel.red, 200)
        XCTAssertLessThan(leftPixel.blue, 60)

        let rightPixel = try XCTUnwrap(SyntheticImage.pixel(of: outputCG, x: 450, y: 400))
        XCTAssertGreaterThan(rightPixel.blue, 200)
        XCTAssertLessThan(rightPixel.red, 60)
    }

    func testAspectFillToSizeWithPersonCenteringFallsBackToCenterOnPersonLessImage() throws {
        let service = ImageProcessingService()
        // centerOnPerson: true runs a Vision human-rectangle request; on a
        // person-less synthetic image no observation exists, so the service
        // falls back to its default center (0.5, 0.5) and the output is
        // identical to plain centering. Deterministic on any platform.
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 1_000, height: 500))

        let output = try service.aspectFillToSize(
            UIImage(cgImage: cgImage),
            targetSize: CGSize(width: 600, height: 800)
        )

        let outputCG = try XCTUnwrap(output.cgImage)
        XCTAssertEqual(outputCG.width, 600)
        XCTAssertEqual(outputCG.height, 800)
    }

    func testAspectFillToSizeRejectsImageWithoutCGImage() throws {
        let service = ImageProcessingService()
        // A UIImage backed by CIImage (not CGImage) has cgImage == nil.
        let ciBacked = UIImage(ciImage: CIImage(color: .red))

        XCTAssertThrowsError(try service.aspectFillToSize(
            ciBacked,
            targetSize: CGSize(width: 600, height: 800),
            centerOnPerson: false
        )) { error in
            XCTAssertEqual(error as? ProcessingError, .invalidImage)
        }
    }

    // MARK: - createThumbnail

    func testCreateThumbnailProducesExactSizeAtUnitScale() throws {
        let service = ImageProcessingService()
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 1_200, height: 1_600, red: 255, green: 0, blue: 0))

        let thumbnail = try service.createThumbnail(
            from: UIImage(cgImage: cgImage),
            size: CGSize(width: 150, height: 200)
        )

        XCTAssertEqual(thumbnail.size, CGSize(width: 150, height: 200))
        XCTAssertEqual(thumbnail.scale, 1)
        let thumbnailCG = try XCTUnwrap(thumbnail.cgImage)
        XCTAssertEqual(thumbnailCG.width, 150)
        XCTAssertEqual(thumbnailCG.height, 200)
        let pixel = try XCTUnwrap(SyntheticImage.pixel(of: thumbnailCG, x: 75, y: 100))
        XCTAssertGreaterThan(pixel.red, 200, "thumbnail must render the source, not a blank canvas")
    }

    // MARK: - EXIF orientation normalization (pipeline step 0)

    func testFixedOrientationReturnsUpOrientedImageUnchanged() throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 100, height: 200))
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)

        XCTAssertTrue(image.fixedOrientation() === image)
    }

    func testFixedOrientationBakesSidewaysEXIFIntoPixels() throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 100, height: 200))
        let sideways = UIImage(cgImage: cgImage, scale: 1, orientation: .right)
        XCTAssertEqual(sideways.size, CGSize(width: 200, height: 100))

        let fixed = sideways.fixedOrientation()

        XCTAssertEqual(fixed.imageOrientation, .up)
        let fixedCG = try XCTUnwrap(fixed.cgImage)
        XCTAssertEqual(fixedCG.width, 200)
        XCTAssertEqual(fixedCG.height, 100)
    }

    func testFixedOrientationFlipsUpsideDownContent() throws {
        // Top half red, bottom half blue; a 180° EXIF rotation must swap them.
        let cgImage = try XCTUnwrap(SyntheticImage.horizontalSplitCGImage(
            width: 100,
            height: 200,
            top: (red: 255, green: 0, blue: 0, alpha: 255),
            bottom: (red: 0, green: 0, blue: 255, alpha: 255)
        ))
        let upsideDown = UIImage(cgImage: cgImage, scale: 1, orientation: .down)

        let fixed = upsideDown.fixedOrientation()
        let fixedCG = try XCTUnwrap(fixed.cgImage)
        XCTAssertEqual(fixedCG.width, 100)
        XCTAssertEqual(fixedCG.height, 200)

        let topPixel = try XCTUnwrap(SyntheticImage.pixel(of: fixedCG, x: 50, y: 25))
        XCTAssertGreaterThan(topPixel.blue, 200, "former bottom half must render on top after a 180° fix")
        let bottomPixel = try XCTUnwrap(SyntheticImage.pixel(of: fixedCG, x: 50, y: 175))
        XCTAssertGreaterThan(bottomPixel.red, 200, "former top half must render on the bottom after a 180° fix")
    }

    // MARK: - Full pipeline: pinned Vision-on-simulator failure

    // Measured on iPhone 17 / iOS 26.5 simulator (2026-07): every detection
    // request this pipeline uses fails at setup — VNDetectHumanRectanglesRequest,
    // VNDetectHumanBodyPoseRequest, and VNDetectFaceRectanglesRequest all throw
    // com.apple.Vision Code=9 ("Could not create inference context" / "Unable to
    // setup request"). So on simulator the pipeline never reaches its
    // noHumanDetected path; the first request throws out of
    // detectHumanBoundingBox and processImage surfaces the raw Vision error.
    // That failure delivery is deterministic — the assertions below pin it.

    func testProcessImageSurfacesVisionSetupFailureVerbatim() async throws {
        let service = ImageProcessingService()
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 512, height: 512))

        var thrown: Error?
        do {
            _ = try await service.processImage(UIImage(cgImage: cgImage), imageId: "person-less")
            XCTFail("Vision inference is unavailable on simulator; processImage must throw")
        } catch {
            thrown = error
        }

        let error = try XCTUnwrap(thrown)
        let nsError = error as NSError
        XCTAssertEqual(nsError.domain, "com.apple.Vision")
        XCTAssertEqual(nsError.code, 9)
        XCTAssertFalse(error is ProcessingError, "Vision's setup failure must surface raw, not remapped")
    }

    func testProcessImageFailureIsRecordedOnTheTaskAndBookkeepingResets() async throws {
        let service = ImageProcessingService()
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 512, height: 512))

        _ = try? await service.processImage(UIImage(cgImage: cgImage), imageId: "tracked-failure")

        let task = await MainActor.run {
            service.processingTasks.first { $0.imageId == "tracked-failure" }
        }
        let trackedTask = try XCTUnwrap(task, "failed processing must remain observable on the task list")
        XCTAssertEqual(trackedTask.status, .failed)
        XCTAssertNotNil(trackedTask.error)
        XCTAssertNil(trackedTask.resultImage)
        XCTAssertEqual(trackedTask.progress, 0.2, "failure happens at the detecting stage")
        let activeCount = await MainActor.run { service.activeProcessingCount }
        XCTAssertEqual(activeCount, 0, "active count must return to zero after a failure")
    }

    func testProcessBatchImagesSwallowsItemFailuresAndRestoresBookkeeping() async throws {
        let service = ImageProcessingService()
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 512, height: 512))
        let items = (0..<3).map { (image: UIImage(cgImage: cgImage), id: "batch-\($0)") }

        await service.processBatchImages(items)

        typealias TaskSnapshot = (count: Int, statuses: [ImageProcessingService.ProcessingStatus], hadErrors: [Bool])
        let states = await MainActor.run { () -> TaskSnapshot in
            let tasks = service.processingTasks
            return (service.activeProcessingCount, tasks.map(\.status), tasks.map { $0.error != nil })
        }
        XCTAssertEqual(states.count, 0)
        XCTAssertEqual(states.statuses.count, 3)
        XCTAssertTrue(states.statuses.allSatisfy { $0 == .failed })
        XCTAssertTrue(states.hadErrors.allSatisfy { $0 })
    }

    // MARK: - Error contract

    func testProcessingErrorDescriptionsMatchDocumentedContract() {
        XCTAssertEqual(ProcessingError.invalidImage.errorDescription, "Invalid image format")
        XCTAssertEqual(ProcessingError.noHumanDetected.errorDescription, "No person detected in image")
        XCTAssertEqual(ProcessingError.cropFailed.errorDescription, "Failed to crop image")
        XCTAssertEqual(ProcessingError.processingFailed.errorDescription, "Image processing failed")
    }
}
