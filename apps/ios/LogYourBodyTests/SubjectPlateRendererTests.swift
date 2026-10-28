//
// SubjectPlateRendererTests.swift
// LogYourBodyTests
//
import XCTest
import UIKit
@testable import LogYourBody

final class SubjectPlateRendererTests: XCTestCase {
    func testRegistrationPreservesAnglesAndRelativeLengthsAndIsInvertible() throws {
        let registration = try XCTUnwrap(BodyPhotoRegistration(
            translation: CGPoint(x: 13, y: -21), rotation: .pi / 6, scale: 1.7
        ))
        let transform = registration.transform
        let origin = CGPoint.zero.applying(transform)
        let horizontal = CGPoint(x: 10, y: 0).applying(transform)
        let vertical = CGPoint(x: 0, y: 10).applying(transform)
        let dx = CGPoint(x: horizontal.x - origin.x, y: horizontal.y - origin.y)
        let dy = CGPoint(x: vertical.x - origin.x, y: vertical.y - origin.y)
        XCTAssertEqual(origin, registration.translation)
        XCTAssertEqual(hypot(dx.x, dx.y), 17, accuracy: 0.0001)
        XCTAssertEqual(hypot(dy.x, dy.y), 17, accuracy: 0.0001)
        XCTAssertEqual(dx.x * dy.x + dx.y * dy.y, 0, accuracy: 0.0001, "No shear")
        XCTAssertGreaterThan(transform.a * transform.d - transform.b * transform.c, 0, "No reflection")
        XCTAssertEqual(atan2(dx.y, dx.x), registration.rotation, accuracy: 0.0001)
        let restored = horizontal.applying(transform.inverted())
        XCTAssertEqual(restored.x, 10, accuracy: 0.0001)
        XCTAssertEqual(restored.y, 0, accuracy: 0.0001)
    }

    func testRegistrationRejectsSingularReflectedAndNonFiniteInputs() {
        let invalidScales: [CGFloat] = [0, -1, .infinity, .nan]
        for scale in invalidScales {
            XCTAssertNil(BodyPhotoRegistration(translation: .zero, scale: scale))
        }
        XCTAssertNil(BodyPhotoRegistration(translation: .zero, rotation: .nan, scale: 1))
        XCTAssertNil(BodyPhotoRegistration(translation: CGPoint(x: .infinity, y: 0), scale: 1))
        XCTAssertNil(AspectFillCropper.registration(imageSize: .zero, in: CGSize(width: 40, height: 50), anchor: nil))
    }

    func testRegisteredPresentationKeepsSourceBytesRecoverable() throws {
        let bytes = try XCTUnwrap(SyntheticImage.mirrorSelfie().pngData())
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("mirror-\(UUID().uuidString).png")
        try bytes.write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let source = try XCTUnwrap(UIImage(contentsOfFile: sourceURL.path))
        let stage = CGSize(width: 60, height: 75)
        let anchor = CGPoint(x: 0.5, y: 0.6)
        let registration = try XCTUnwrap(AspectFillCropper.registration(imageSize: source.size, in: stage, anchor: anchor))
        let expected = AspectFillCropper.fillRect(
            imageSize: source.size, in: stage, anchor: anchor, anchorTarget: TorsoFocusService.stageAnchor
        )
        XCTAssertEqual(registration.scale, 0.5, accuracy: 0.0001)
        XCTAssertEqual(registration.rotation, 0)
        XCTAssertEqual(registration.transform.a, registration.transform.d)
        XCTAssertEqual(registration.transform.b, 0)
        XCTAssertEqual(registration.transform.c, 0)
        XCTAssertEqual(CGRect(origin: .zero, size: source.size).applying(registration.transform), expected)
        let presentation = AspectFillCropper.crop(source, to: stage, anchor: anchor)
        XCTAssertEqual(presentation.size, stage)
        XCTAssertNotEqual(presentation.pngData(), bytes)
        let presentationCG = try XCTUnwrap(presentation.cgImage)
        let pixel = try XCTUnwrap(SyntheticImage.pixel(
            of: presentationCG, x: presentationCG.width / 2, y: presentationCG.height / 2
        ))
        XCTAssertGreaterThan(pixel.green, pixel.red, "The registered stage must contain the synthetic torso")
        let rotated = try XCTUnwrap(BodyPhotoRegistration(translation: CGPoint(x: 10, y: 5), rotation: 0.1, scale: 0.5))
        XCTAssertEqual(AspectFillCropper.crop(source, to: stage, registration: rotated).size, stage)
        XCTAssertEqual(try Data(contentsOf: sourceURL), bytes)
        let recovered = try XCTUnwrap(UIImage(contentsOfFile: sourceURL.path))
        XCTAssertEqual(recovered.size, CGSize(width: 120, height: 200))
        XCTAssertEqual(recovered.pngData(), source.pngData())
    }

    func testTreatedBackgroundIsDimmedAndDesaturatedAtTheSameSize() throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 64, height: 64, red: 255, green: 0, blue: 0))

        let plate = SubjectPlateRenderer.flatten(
            SubjectPlateRenderer.treatedBackground(of: cgImage),
            like: UIImage(cgImage: cgImage),
            cgImage: cgImage
        )

        let output = try XCTUnwrap(plate.cgImage)
        XCTAssertEqual(output.width, 64)
        XCTAssertEqual(output.height, 64)
        let center = try XCTUnwrap(SyntheticImage.pixel(of: output, x: 32, y: 32))
        XCTAssertLessThan(max(Int(center.red), Int(center.green), Int(center.blue)), 90, "background must be dimmed")
        XCTAssertLessThan(abs(Int(center.red) - Int(center.blue)), 40, "background must be desaturated")
    }

    func testRenderKeepsGeometryWhenPersonSegmentationIsUnavailable() async throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 48, height: 60, red: 40, green: 90, blue: 200))

        let plate = await SubjectPlateRenderer.render(UIImage(cgImage: cgImage))

        XCTAssertEqual(plate.cgImage?.width, 48)
        XCTAssertEqual(plate.cgImage?.height, 60)
    }

    @MainActor
    func testStoreRendersEachURLOnceAndCachesThePlate() async throws {
        let cgImage = try XCTUnwrap(SyntheticImage.solidCGImage(width: 16, height: 20, red: 10, green: 10, blue: 10))
        let store = SubjectPlateStore(countLimit: 4)
        let image = UIImage(cgImage: cgImage)

        XCTAssertNil(store.cachedPlate(for: "file:///a.jpg"))
        let first = await store.plate(for: "file:///a.jpg", image: image)
        XCTAssertNotNil(first)
        XCTAssertTrue(store.cachedPlate(for: "file:///a.jpg") === first)
    }
}
