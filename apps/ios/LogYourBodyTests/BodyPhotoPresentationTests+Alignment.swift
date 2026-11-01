//
// BodyPhotoPresentationTests+Alignment.swift
// LogYourBodyTests
//
import UIKit
import XCTest
@testable import LogYourBody

extension BodyPhotoPresentationTests {
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
