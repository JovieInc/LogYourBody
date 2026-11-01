//
// BodyPhotoPresentationTests.swift
// LogYourBodyTests
//
import XCTest
import UIKit
@testable import LogYourBody

final class BodyPhotoPresentationTests: XCTestCase {
    func testSubjectColorSurvivesMattingAcrossSkinTonesAndSizes() throws {
        let tones: [(UInt8, UInt8, UInt8)] = [
            (255, 224, 189),
            (198, 134, 88),
            (92, 58, 42),
            (60, 40, 36)
        ]
        let sizes = [(width: 24, height: 32), (width: 48, height: 40), (width: 20, height: 64)]
        var preserved: [(UInt8, UInt8, UInt8)] = []
        for tone in tones {
            for size in sizes {
                let source = try pixels(width: size.width, height: size.height, red: 20, green: 90, blue: 200)
                fill(&source.pixels, width: size.width, rect: subjectRect(width: size.width, height: size.height), color: tone)
                var mask = PersonMaskGrid(
                    width: size.width,
                    height: size.height,
                    values: [UInt8](repeating: 0, count: size.width * size.height)
                )
                fillMask(&mask, rect: subjectRect(width: size.width, height: size.height), value: 255)
                let output = try XCTUnwrap(BodyPhotoCompositor.composite(
                    source: source.pixels,
                    background: source.pixels,
                    width: size.width,
                    height: size.height,
                    mask: mask
                ))
                let center = subjectRect(width: size.width, height: size.height)
                let pixel = try pixel(output, width: size.width, x: Int(center.midX), y: Int(center.midY))
                XCTAssertEqual(pixel.0, tone.0)
                XCTAssertEqual(pixel.1, tone.1)
                XCTAssertEqual(pixel.2, tone.2)
                preserved.append(tone)
            }
        }
        XCTAssertEqual(Set(preserved.map { "\($0.0),\($0.1),\($0.2)" }).count, tones.count)
    }

    func testBackgroundDimIsIndependentAndTheFrameSitsBehindTheSubject() throws {
        let width = 64
        let height = 64
        var source = try pixels(width: width, height: height, red: 240, green: 30, blue: 30)
        let tone = (red: UInt8(80), green: UInt8(50), blue: UInt8(40))
        fill(
            &source.pixels,
            width: width,
            rect: CGRect(x: 24, y: 16, width: 16, height: 28),
            color: (tone.red, tone.green, tone.blue)
        )
        var background = source.pixels
        for index in stride(from: 0, to: background.count, by: 4) {
            background[index] = 30
            background[index + 1] = 30
            background[index + 2] = 30
            background[index + 3] = 255
        }
        var mask = PersonMaskGrid(width: width, height: height, values: [UInt8](repeating: 0, count: width * height))
        fillMask(&mask, rect: CGRect(x: 24, y: 16, width: 16, height: 28), value: 255)
        let untouched = source.pixels
        let output = try XCTUnwrap(BodyPhotoCompositor.composite(
            source: source.pixels, background: background, width: width, height: height, mask: mask
        ))
        XCTAssertEqual(source.pixels, untouched, "compositing must not rewrite the source bytes")
        let subject = try pixel(output, width: width, x: 32, y: 30)
        XCTAssertEqual(subject.0, tone.red)
        XCTAssertEqual(subject.1, tone.green)
        XCTAssertEqual(subject.2, tone.blue)
        XCTAssertTrue(BodyPhotoFrameTreatment.isStroke(x: 11, y: 20, width: width, height: height))
        let stroke = try pixel(output, width: width, x: 11, y: 20)
        let outside = try pixel(output, width: width, x: 2, y: 2)
        XCTAssertEqual(outside.0, 30, "background outside the stroke stays the treated plate")
        XCTAssertGreaterThan(stroke.0, outside.0, "the frame is painted only on the background")
        let subjectOnStroke = try pixel(output, width: width, x: 32, y: 30)
        XCTAssertEqual(subjectOnStroke.2, tone.blue)
    }

    func testOcclusionHoleKeepsTheSourcePixelAndDoesNotInventSkin() throws {
        let width = 32
        let height = 32
        var source = try pixels(width: width, height: height, red: 198, green: 134, blue: 88)
        source.pixels[(16 * width + 16) * 4] = 0
        source.pixels[(16 * width + 16) * 4 + 1] = 0
        source.pixels[(16 * width + 16) * 4 + 2] = 0
        var mask = PersonMaskGrid(width: width, height: height, values: [UInt8](repeating: 255, count: width * height))
        mask.values[16 * width + 16] = 0
        mask.values[16 * width + 15] = 0
        mask.values[15 * width + 16] = 0
        mask.values[15 * width + 15] = 0
        let decision = PersonMaskPolicy.decide(
            mask: mask, imageWidth: width, imageHeight: height, protectedPoints: [], cropSupported: true
        )
        guard case .refined(let refined) = decision else {
            return XCTFail("a small phone hole is filled with the original matte, not rejected")
        }
        XCTAssertEqual(refined.values[16 * width + 16], 255)
        var background = [UInt8](repeating: 10, count: width * height * 4)
        let output = try XCTUnwrap(BodyPhotoCompositor.composite(
            source: source.pixels, background: background, width: width, height: height, mask: refined
        ))
        let phone = try pixel(output, width: width, x: 16, y: 16)
        XCTAssertEqual(phone.0, 0)
        XCTAssertEqual(phone.1, 0)
        XCTAssertEqual(phone.2, 0)
        let skin = try pixel(output, width: width, x: 8, y: 8)
        XCTAssertEqual(skin.0, 198)
        XCTAssertEqual(skin.1, 134)
        XCTAssertEqual(skin.2, 88)
        _ = background
    }

    func testLowConfidenceLargeHoleAndMissingLimbFallBackIntact() {
        let width = 20
        let height = 20
        let faint = PersonMaskGrid(width: width, height: height, values: [UInt8](repeating: 20, count: width * height))
        let low = PersonMaskPolicy.decide(
            mask: faint, imageWidth: width, imageHeight: height, protectedPoints: [], cropSupported: true
        )
        guard case .intact(let lowRetry) = low else { return XCTFail("low confidence keeps the photograph") }
        XCTAssertEqual(lowRetry.reason, .lowConfidence)
        XCTAssertTrue(lowRetry.canRetry)

        var solid = PersonMaskGrid(width: width, height: height, values: [UInt8](repeating: 255, count: width * height))
        for row in 4..<14 {
            for column in 4..<14 {
                solid.values[row * width + column] = 0
            }
        }
        let hole = PersonMaskPolicy.decide(
            mask: solid, imageWidth: width, imageHeight: height, protectedPoints: [], cropSupported: true
        )
        guard case .intact(let holeRetry) = hole else { return XCTFail("a large hole is not filled with invented body") }
        XCTAssertEqual(holeRetry.reason, .interiorHole)
        XCTAssertTrue(holeRetry.canRetry)

        var clipped = PersonMaskGrid(width: width, height: height, values: [UInt8](repeating: 255, count: width * height))
        for row in 0..<height {
            for column in 14..<width {
                clipped.values[row * width + column] = 0
            }
        }
        let missing = PersonMaskPolicy.decide(
            mask: clipped,
            imageWidth: width,
            imageHeight: height,
            protectedPoints: [CGPoint(x: 17, y: 10)],
            cropSupported: true
        )
        guard case .intact(let missingRetry) = missing else { return XCTFail("a clipped hand keeps the intact photo") }
        XCTAssertEqual(missingRetry.reason, .missingLimb)
        XCTAssertTrue(missingRetry.canRetry)

        let unsupported = PersonMaskPolicy.decide(
            mask: faint, imageWidth: width, imageHeight: height, protectedPoints: [], cropSupported: false
        )
        guard case .intact(let cropRetry) = unsupported else { return XCTFail("unsupported crops retry") }
        XCTAssertEqual(cropRetry.reason, .unsupportedCrop)
        XCTAssertTrue(cropRetry.canRetry)
    }

    func testPartialBodyAndSoftHairKeepTheSilhouette() {
        let width = 30
        let height = 40
        var mask = PersonMaskGrid(width: width, height: height, values: [UInt8](repeating: 0, count: width * height))
        for row in 0..<24 {
            for column in 8..<22 {
                mask.values[row * width + column] = 255
            }
        }
        mask.values[24 * width + 12] = 70
        let decision = PersonMaskPolicy.decide(
            mask: mask, imageWidth: width, imageHeight: height, protectedPoints: [], cropSupported: true
        )
        guard case .refined(let refined) = decision else { return XCTFail("a partial body still mattes") }
        XCTAssertEqual(refined.values[10 * width + 12], 255)
        XCTAssertEqual(refined.values[24 * width + 12], 200, "soft hair beside the body is included")
        XCTAssertEqual(refined.values[24 * width + 2], 0, "distant background is not grown into a body")
        var source = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<24 {
            for column in 8..<22 {
                let offset = (row * width + column) * 4
                source[offset] = 92
                source[offset + 1] = 58
                source[offset + 2] = 42
                source[offset + 3] = 255
            }
        }
        let background = [UInt8](repeating: 255, count: source.count)
        let output = try? XCTUnwrap(BodyPhotoCompositor.composite(
            source: source, background: background, width: width, height: height, mask: refined
        ))
        XCTAssertEqual(BodyPhotoCompositor.subjectWidth(
            pixels: output ?? [], width: width, height: height, red: 92, green: 58, blue: 42
        ), 14)
        let wider = subjectWidth(ofTone: (198, 134, 88), columns: 8..<26, rows: 0..<24, width: width, height: height)
        XCTAssertEqual(wider, 18)
        XCTAssertGreaterThan(wider, 14, "a wider body stays wider")
    }

    func testAlignmentUsesTorsoLengthAndKeepsShoulderWidth() throws {
        let narrow = frame(shoulderSpan: 20, torso: 80, wrist: CGPoint(x: 10, y: 70))
        let wide = frame(shoulderSpan: 50, torso: 80, wrist: CGPoint(x: 90, y: 20))
        let closer = frame(shoulderSpan: 50, torso: 40, wrist: nil)
        let narrowMatch = try aligned(BodyPhotoAlignmentPolicy.align(source: narrow, onto: wide))
        let closerMatch = try aligned(BodyPhotoAlignmentPolicy.align(source: narrow, onto: closer))
        XCTAssertEqual(narrowMatch.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(closerMatch.scale, 0.5, accuracy: 0.0001)
        let left = try XCTUnwrap(narrow.leftShoulder).point.applying(narrowMatch.transform)
        XCTAssertEqual(left.x, try XCTUnwrap(narrow.leftShoulder).point.x, accuracy: 0.001)
        XCTAssertNotEqual(left.x, try XCTUnwrap(wide.leftShoulder).point.x, accuracy: 1)
        let horizontal = CGPoint(x: 10, y: 0).applying(closerMatch.transform)
        let vertical = CGPoint(x: 0, y: 10).applying(closerMatch.transform)
        let origin = CGPoint.zero.applying(closerMatch.transform)
        let dx = CGPoint(x: horizontal.x - origin.x, y: horizontal.y - origin.y)
        let dy = CGPoint(x: vertical.x - origin.x, y: vertical.y - origin.y)
        XCTAssertEqual(hypot(dx.x, dx.y), 5, accuracy: 0.001)
        XCTAssertEqual(hypot(dy.x, dy.y), 5, accuracy: 0.001)
        XCTAssertEqual(dx.x * dy.x + dx.y * dy.y, 0, accuracy: 0.001)
    }

    func testRotatedCompatibleViewsStayAUniformSimilarity() throws {
        let source = frame(shoulderSpan: 24, torso: 80, wrist: nil)
        let center = CGPoint(x: 50, y: 80)
        let angle: CGFloat = 0.35
        var target = source
        target.leftShoulder?.point = rotate(try XCTUnwrap(source.leftShoulder).point, around: center, by: angle)
        target.rightShoulder?.point = rotate(try XCTUnwrap(source.rightShoulder).point, around: center, by: angle)
        target.leftHip?.point = rotate(try XCTUnwrap(source.leftHip).point, around: center, by: angle)
        target.rightHip?.point = rotate(try XCTUnwrap(source.rightHip).point, around: center, by: angle)
        let registration = try aligned(BodyPhotoAlignmentPolicy.align(source: source, onto: target))
        XCTAssertEqual(registration.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(registration.rotation, angle, accuracy: 0.0001)
        let mapped = try XCTUnwrap(source.leftShoulder).point.applying(registration.transform)
        XCTAssertEqual(mapped.x, try XCTUnwrap(target.leftShoulder).point.x, accuracy: 0.01)
        XCTAssertEqual(mapped.y, try XCTUnwrap(target.leftShoulder).point.y, accuracy: 0.01)
    }

    func testPoseMirrorAndCropMismatchesStayHonestAndKeepMetadata() throws {
        let front = frame(shoulderSpan: 30, torso: 80, wrist: nil)
        var side = frame(shoulderSpan: 6, torso: 80, wrist: nil)
        side.metadata.viewpoint = .side
        let mismatch = BodyPhotoAlignmentPolicy.align(source: front, onto: side)
        guard case .honest(let reason, let sourceMeta, let targetMeta) = mismatch else {
            return XCTFail("front and side are not registered as the same pose")
        }
        XCTAssertEqual(reason, .poseMismatch)
        XCTAssertEqual(sourceMeta, front.metadata)
        XCTAssertEqual(targetMeta, side.metadata)

        var mirrored = front
        mirrored.metadata.mirrored = true
        let mirror = BodyPhotoAlignmentPolicy.align(source: front, onto: mirrored)
        guard case .honest(let mirrorReason, let mirrorSource, _) = mirror else {
            return XCTFail("a mirror disagreement is not silently flipped")
        }
        XCTAssertEqual(mirrorReason, .mirrorDisagreement)
        XCTAssertFalse(mirrorSource.mirrored)
        XCTAssertTrue(mirrored.metadata.mirrored)

        var wide = front
        wide.metadata.sourceSize = CGSize(width: 400, height: 40)
        let crop = BodyPhotoAlignmentPolicy.align(source: wide, onto: front)
        guard case .honest(let cropReason, let cropSource, _) = crop else {
            return XCTFail("an extreme crop is not forced into a comparison")
        }
        XCTAssertEqual(cropReason, .unsupportedCrop)
        XCTAssertEqual(cropSource.crop, wide.metadata.crop)
        XCTAssertEqual(cropSource.sourceSize, wide.metadata.sourceSize)
    }

    func testStageRegistrationLandsTheTorsoWithoutUsingShoulderWidth() throws {
        let source = frame(shoulderSpan: 20, torso: 80, wrist: nil)
        let wider = frame(shoulderSpan: 48, torso: 80, wrist: nil)
        let stage = CGSize(width: 50, height: 80)
        let anchor = CGPoint(x: 0.5, y: 0.4)
        let alignedWide = try aligned(BodyPhotoAlignmentPolicy.stageRegistration(
            source: source, target: wider, targetImageSize: source.metadata.sourceSize, stage: stage, anchor: anchor
        ))
        let same = frame(shoulderSpan: 20, torso: 80, wrist: nil)
        let alignedSame = try aligned(BodyPhotoAlignmentPolicy.stageRegistration(
            source: source, target: same, targetImageSize: source.metadata.sourceSize, stage: stage, anchor: anchor
        ))
        XCTAssertEqual(alignedWide.scale, alignedSame.scale, accuracy: 0.0001)
        let center = CGPoint(x: 50, y: 80).applying(alignedSame.transform)
        XCTAssertEqual(center.x, 25, accuracy: 0.05)
        XCTAssertEqual(center.y, 33.6, accuracy: 0.05)
    }

    func testCrossDissolveKeepsEndpointsAndIsNotACapture() throws {
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_720_000_000)
        let captures = ["photo-earlier", "photo-later"]
        let transition = BodyPhotoTransition.crossDissolve(
            earlierDate: earlier, earlierID: captures[0], laterDate: later, laterID: captures[1], progress: 0.5
        )
        let blend = try XCTUnwrap(transition)
        XCTAssertEqual(blend.earlierDate, earlier)
        XCTAssertEqual(blend.laterDate, later)
        XCTAssertEqual(blend.earlierSourceID, captures[0])
        XCTAssertEqual(blend.laterSourceID, captures[1])
        XCTAssertEqual(blend.earlierOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(blend.laterOpacity, 0.5, accuracy: 0.0001)
        XCTAssertFalse(blend.isPersistedCapture)
        XCTAssertEqual(BodyPhotoCaptureLog.idsAfterTransition(existing: captures, transition: blend), captures)
        XCTAssertNil(BodyPhotoTransition.crossDissolve(
            earlierDate: earlier, earlierID: "same", laterDate: later, laterID: "same", progress: 0.5
        ))
    }

    func testScrubFrameDoesNotSegmentAndTheAdjacentCacheIsBounded() {
        XCTAssertEqual(BodyPhotoScrubSession.work.segmentations, 0)
        XCTAssertEqual(BodyPhotoScrubSession.work.fullResolutionDecodes, 0)
        XCTAssertNil(BodyPhotoScrubSession.display(prepared: nil))
        let urls = (0..<8).map { "https://photos.example/\($0).jpg" }
        let optionalURLs: [String?] = urls
        XCTAssertEqual(BodyPhotoPreparationPlan.neighborURLs(around: 5, urls: optionalURLs), Array(urls[4...6]))
        XCTAssertEqual(BodyPhotoPreparationPlan.neighborURLs(around: 0, urls: optionalURLs), Array(urls[0...1]))
        var cache = BodyPhotoDerivativeCache()
        for url in urls {
            cache.store(derivative(url), retaining: nil)
        }
        XCTAssertLessThanOrEqual(cache.entries.count, BodyPhotoDerivativeCache.capacity)
        let window = Array(urls[4...6])
        cache.store(derivative(window[1]), retaining: window)
        XCTAssertEqual(Set(cache.entries.values.map(\.url)), Set(window))
    }

    func testFrameUsesApprovedTokensAndFitsAShortStage() {
        XCTAssertEqual(BodyPhotoFrameTreatment.overlap, HomeV2Tokens.Space.tight)
        XCTAssertEqual(BodyPhotoFrameTreatment.inset, HomeV2Tokens.Space.row)
        XCTAssertEqual(BodyPhotoFrameTreatment.radius, HomeV2Tokens.photoSlotRadius)
        XCTAssertEqual(BodyPhotoFrameTreatment.stroke, HomeV2Tokens.Space.hairline * 2)
        let stage = CGSize(width: 320, height: HomeV2Layout.stageHeight(width: 320, height: 300))
        let frame = BodyPhotoFrameTreatment.frameRect(in: stage)
        XCTAssertGreaterThanOrEqual(stage.height, HomeV2Layout.minimumStageHeight)
        XCTAssertGreaterThanOrEqual(frame.minX, 0)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
        XCTAssertLessThanOrEqual(frame.maxX, stage.width + 0.01)
        XCTAssertLessThanOrEqual(frame.maxY, stage.height + 0.01)
        XCTAssertGreaterThan(frame.width, stage.width * 0.5)
    }

    func testPresentKeepsSubjectPixelsOnAMaskedPlate() throws {
        let width = 48
        let height = 60
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = 30
            pixels[index + 1] = 140
            pixels[index + 2] = 220
            pixels[index + 3] = 255
        }
        for row in 18..<42 {
            for column in 16..<32 {
                let offset = (row * width + column) * 4
                pixels[offset] = 92
                pixels[offset + 1] = 58
                pixels[offset + 2] = 42
                pixels[offset + 3] = 255
            }
        }
        let image = try XCTUnwrap(BodyPhotoBitmap.image(
            pixels: pixels, width: width, height: height, scale: 1, orientation: .up
        ))
        let cgImage = try XCTUnwrap(image.cgImage)
        var mask = PersonMaskGrid(width: width, height: height, values: [UInt8](repeating: 0, count: width * height))
        for row in 18..<42 {
            for column in 16..<32 { mask.values[row * width + column] = 255 }
        }
        let presented = try XCTUnwrap(SubjectPlateRenderer.present(
            cgImage: cgImage, mask: mask, scale: 1, orientation: .up
        ))
        let output = try XCTUnwrap(presented.cgImage)
        let subject = try XCTUnwrap(SyntheticImage.pixel(of: output, x: 24, y: 30))
        XCTAssertEqual(subject.red, 92)
        XCTAssertEqual(subject.green, 58)
        XCTAssertEqual(subject.blue, 42)
        let background = try XCTUnwrap(SyntheticImage.pixel(of: output, x: 2, y: 2))
        XCTAssertLessThan(Int(background.blue), 140)
        XCTAssertEqual(output.width, width)
        XCTAssertEqual(output.height, height)
    }

    @MainActor
    func testScrubImageReadsThePreparedPlateOnly() async throws {
        let store = SubjectPlateStore(countLimit: 4)
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 30, height: 40, red: 90, green: 40, blue: 30))
        let image = UIImage(cgImage: cgImage)
        let target = CGSize(width: 20, height: 24)
        let url = "file:///prepared-plate.png"
        XCTAssertNil(store.scrubImage(for: url, target: target))
        let prepared = await store.prepare(urlString: url, image: image, target: target, retaining: [url])
        let cached = try XCTUnwrap(prepared)
        XCTAssertTrue(store.scrubImage(for: url, target: target) === cached)
        XCTAssertEqual(cached.size, target)
        store.invalidatePrepared(urlString: url, target: target)
        XCTAssertNil(store.scrubImage(for: url, target: target))
        XCTAssertEqual(BodyPhotoScrubSession.work.segmentations, 0)
        XCTAssertEqual(BodyPhotoScrubSession.work.fullResolutionDecodes, 0)
    }

    func testSmallPreviewsStayOffTheStageDerivativePath() {
        XCTAssertFalse(BodyPhotoStagePreparation.preparesDerivative(
            size: CGSize(width: 28, height: 36),
            hasDrawingRegistration: false
        ))
        XCTAssertFalse(BodyPhotoStagePreparation.preparesDerivative(
            size: CGSize(width: 320, height: 400),
            hasDrawingRegistration: true
        ))
        XCTAssertTrue(BodyPhotoStagePreparation.preparesDerivative(
            size: CGSize(width: 320, height: 400),
            hasDrawingRegistration: false
        ))
    }

    func testUnsupportedCropReturnsTheSamePhotograph() async throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 16, height: 16, red: 10, green: 20, blue: 30))
        let image = UIImage(cgImage: cgImage)
        let result = await SubjectPlateRenderer.renderResult(image, cropSupported: false)
        let retry = try XCTUnwrap(result.retry)
        XCTAssertTrue(result.image === image)
        XCTAssertTrue(result.fellBackToIntact)
        XCTAssertNil(result.mask)
        XCTAssertEqual(retry.reason, .unsupportedCrop)
        XCTAssertTrue(retry.canRetry)
    }

    func testMirrorSelfiePhoneHoleKeepsTheSourcePixel() throws {
        let image = SyntheticImage.mirrorSelfie()
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let source = try XCTUnwrap(BodyPhotoBitmap.read(cgImage))
        var mask = PersonMaskGrid(width: width, height: height, values: [UInt8](repeating: 255, count: width * height))
        for row in 40..<68 {
            for column in 70..<86 {
                mask.values[row * width + column] = 0
            }
        }
        let decision = PersonMaskPolicy.decide(
            mask: mask,
            imageWidth: width,
            imageHeight: height,
            protectedPoints: [],
            cropSupported: true
        )
        guard case .refined(let refined) = decision else {
            return XCTFail("a phone-sized hole in a mirror selfie stays a matte")
        }
        XCTAssertGreaterThanOrEqual(width, 86)
        XCTAssertGreaterThanOrEqual(height, 68)
        XCTAssertEqual(mask.values[50 * width + 78], 0)
        XCTAssertEqual(refined.values[50 * width + 78], 255)
        let output = try XCTUnwrap(BodyPhotoCompositor.composite(
            source: source,
            background: source,
            width: width,
            height: height,
            mask: refined
        ))
        let before = try pixel(source, width: width, x: 78, y: 50)
        let after = try pixel(output, width: width, x: 78, y: 50)
        XCTAssertEqual(after.0, before.0)
        XCTAssertEqual(after.1, before.1)
        XCTAssertEqual(after.2, before.2)
    }

    private func pixels(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) throws -> (pixels: [UInt8], width: Int) {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = red
            pixels[index + 1] = green
            pixels[index + 2] = blue
            pixels[index + 3] = 255
        }
        return (pixels, width)
    }

    private func fill(
        _ pixels: inout [UInt8],
        width: Int,
        rect: CGRect,
        color: (UInt8, UInt8, UInt8)
    ) {
        for row in Int(rect.minY)..<Int(rect.maxY) {
            for column in Int(rect.minX)..<Int(rect.maxX) {
                let offset = (row * width + column) * 4
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
                pixels[offset + 3] = 255
            }
        }
    }

    private func fillMask(_ mask: inout PersonMaskGrid, rect: CGRect, value: UInt8) {
        for row in Int(rect.minY)..<Int(rect.maxY) {
            for column in Int(rect.minX)..<Int(rect.maxX) {
                mask.values[row * mask.width + column] = value
            }
        }
    }

    private func subjectRect(width: Int, height: Int) -> CGRect {
        CGRect(x: width / 4, y: height / 5, width: width / 2, height: height / 2)
    }

    private func pixel(_ pixels: [UInt8], width: Int, x: Int, y: Int) throws -> (UInt8, UInt8, UInt8, UInt8) {
        let offset = (y * width + x) * 4
        return (pixels[offset], pixels[offset + 1], pixels[offset + 2], pixels[offset + 3])
    }

    private func subjectWidth(
        ofTone tone: (UInt8, UInt8, UInt8),
        columns: Range<Int>,
        rows: Range<Int>,
        width: Int,
        height: Int
    ) -> Int {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in rows {
            for column in columns {
                let offset = (row * width + column) * 4
                pixels[offset] = tone.0
                pixels[offset + 1] = tone.1
                pixels[offset + 2] = tone.2
            }
        }
        return BodyPhotoCompositor.subjectWidth(
            pixels: pixels, width: width, height: height, red: tone.0, green: tone.1, blue: tone.2
        )
    }

    private func frame(shoulderSpan: CGFloat, torso: CGFloat, wrist: CGPoint?) -> BodyLandmarkFrame {
        let centerX: CGFloat = 50
        let shoulderY: CGFloat = 40
        let hipY = shoulderY + torso
        let hipSpan = shoulderSpan * 0.8
        return BodyLandmarkFrame(
            leftShoulder: .init(point: CGPoint(x: centerX - shoulderSpan / 2, y: shoulderY), confidence: 0.9),
            rightShoulder: .init(point: CGPoint(x: centerX + shoulderSpan / 2, y: shoulderY), confidence: 0.9),
            leftHip: .init(point: CGPoint(x: centerX - hipSpan / 2, y: hipY), confidence: 0.9),
            rightHip: .init(point: CGPoint(x: centerX + hipSpan / 2, y: hipY), confidence: 0.9),
            leftWrist: wrist.map { .init(point: $0, confidence: 0.9) },
            rightWrist: nil,
            metadata: BodyPhotoCaptureMetadata(
                viewpoint: .front,
                mirrored: false,
                crop: CGRect(x: 0, y: 0, width: 1, height: 1),
                sourceSize: CGSize(width: 100, height: 200)
            )
        )
    }

    private func aligned(_ alignment: BodyPhotoAlignment) throws -> BodyPhotoRegistration {
        guard case .aligned(let registration, _, _) = alignment else {
            XCTFail("expected an aligned registration")
            throw AlignmentTestError.notAligned
        }
        return registration
    }

    private func rotate(_ point: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + cos(angle) * dx - sin(angle) * dy,
            y: center.y + sin(angle) * dx + cos(angle) * dy
        )
    }

    private func derivative(_ url: String) -> BodyPhotoDerivative {
        BodyPhotoDerivative(
            url: url,
            targetSize: CGSize(width: 20, height: 24),
            mask: nil,
            fellBackToIntact: false,
            retry: nil,
            metadata: BodyPhotoCaptureMetadata(
                viewpoint: .front,
                mirrored: false,
                crop: CGRect(x: 0, y: 0, width: 1, height: 1),
                sourceSize: CGSize(width: 20, height: 24)
            )
        )
    }
}

private enum AlignmentTestError: Error {
    case notAligned
}
