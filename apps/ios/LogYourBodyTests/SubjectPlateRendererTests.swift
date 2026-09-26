//
// SubjectPlateRendererTests.swift
// LogYourBodyTests
//
import XCTest
import UIKit
@testable import LogYourBody

final class SubjectPlateRendererTests: XCTestCase {
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
