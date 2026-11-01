//
//  WireframeAvatarFamilyTests.swift
//  LogYourBodyTests
//
//  The committed torso and the Swift sampler stay on one topology.
//

import XCTest
@testable import LogYourBody

@MainActor
final class WireframeAvatarFamilyTests: XCTestCase {
    func testCommittedAssetMatchesTheSwiftSampler() throws {
        let asset = try loadAsset()
        XCTAssertEqual(asset.modelId, "lyb.wireframe.torso")
        XCTAssertEqual(asset.version, "1.0.0")
        XCTAssertEqual(asset.topologyId, "lyb.wireframe.torso.v1")
        XCTAssertEqual(asset.rigId, "lyb.wireframe.torso.rig.v1")
        XCTAssertFalse(asset.topologyId.contains("smpl"))
        XCTAssertEqual(asset.vertexCount, 160)
        XCTAssertEqual(asset.wires.count, 304)
        XCTAssertTrue(asset.illustrative)
        XCTAssertFalse(asset.mapsToBodyFat)
        XCTAssertFalse(asset.mapsToFfmi)
        XCTAssertFalse(asset.material.idleSpin)
        XCTAssertFalse(asset.license.annyBundled)
        XCTAssertFalse(asset.license.smplxIncluded)
        XCTAssertFalse(asset.license.smplIncluded)
        XCTAssertFalse(asset.license.somaIncluded)
        XCTAssertEqual(asset.license.asset, "CC0-1.0")
        XCTAssertFalse(asset.caching.disk)
        XCTAssertFalse(asset.caching.network)
        XCTAssertFalse(asset.caching.photoBytes)
        XCTAssertEqual(asset.families["male"]?.rest.count, asset.vertexCount)
        XCTAssertEqual(asset.families["female"]?.rest.count, asset.vertexCount)
        XCTAssertEqual(asset.audit.count, 3)

        for sample in asset.audit {
            let vertices = WireframeAvatarLibrary.interpolate(
                asset: asset,
                presentation: sample.presentation,
                adiposity: sample.adiposity,
                muscularity: sample.muscularity,
                frame: sample.frame
            )
            let point = try XCTUnwrap(vertex(vertices, sample.index))
            XCTAssertEqual(point.x, sample.position[0], accuracy: 1e-5)
            XCTAssertEqual(point.y, sample.position.count > 1 ? sample.position[1] : 0, accuracy: 1e-5)
            XCTAssertEqual(point.z, sample.position.count > 2 ? sample.position[2] : 0, accuracy: 1e-5)
        }
    }

    func testSameTopologyMorphsAndCrossTopologyIsRefused() throws {
        let asset = try loadAsset()
        let male = resolved(asset, presentation: "male", adiposity: 0, muscularity: 0, frame: 0)
        let female = resolved(asset, presentation: "female", adiposity: 1, muscularity: 1, frame: 1)
        let blended = try WireframeAvatarLibrary.morph(male, female, t: 0.5)
        XCTAssertEqual(blended.topologyId, male.topologyId)
        XCTAssertEqual(blended.rigId, male.rigId)
        XCTAssertEqual(blended.vertices.count, male.vertices.count)

        let foreign = ResolvedWireframe(
            topologyId: "smplx",
            rigId: female.rigId,
            vertices: female.vertices
        )
        XCTAssertThrowsError(try WireframeAvatarLibrary.morph(male, foreign, t: 0.5)) { error in
            XCTAssertEqual(error as? WireframeMorphError, .crossTopology)
        }

        let shorter = ResolvedWireframe(
            topologyId: female.topologyId,
            rigId: female.rigId,
            vertices: Array(female.vertices.dropLast())
        )
        XCTAssertThrowsError(try WireframeAvatarLibrary.morph(male, shorter, t: 0.5)) { error in
            XCTAssertEqual(error as? WireframeMorphError, .crossTopology)
        }
    }

    func testRepresentativeGridKeepsIdentityInsideBounds() throws {
        let asset = try loadAsset()
        let steps = [0.0, 0.5, 1.0]
        for presentation in ["male", "female"] {
            for adiposity in steps {
                for muscularity in steps {
                    for frame in steps {
                        assertBounded(
                            asset,
                            presentation: presentation,
                            adiposity: adiposity,
                            muscularity: muscularity,
                            frame: frame
                        )
                    }
                }
            }
        }

        for parameters in steps {
            let male = shoulderWidth(asset, presentation: "male", value: parameters)
            let female = shoulderWidth(asset, presentation: "female", value: parameters)
            XCTAssertGreaterThan(male, female)
        }

        let thin = waistWidth(asset, presentation: "male", adiposity: 0)
        let full = waistWidth(asset, presentation: "male", adiposity: 1)
        XCTAssertGreaterThan(full, thin)
        let narrow = frameWidth(asset, presentation: "female", frame: 0)
        let broad = frameWidth(asset, presentation: "female", frame: 1)
        XCTAssertGreaterThan(broad, narrow)
    }

    func testPresentationRotationAndKillSwitchAreExplicit() {
        XCTAssertEqual(WireframeAvatarMotion.presentation(stored: nil), "male")
        XCTAssertEqual(WireframeAvatarMotion.presentation(stored: "female"), "female")
        XCTAssertEqual(WireframeAvatarMotion.presentation(stored: "other"), "male")
        XCTAssertEqual(WireframeAvatarMotion.dragGain, 0.008)
        XCTAssertFalse(WireframeAvatarMotion.idleSpin)
        XCTAssertEqual(WireframeAvatarMotion.yaw(for: "front"), 0)
        XCTAssertEqual(WireframeAvatarMotion.yaw(for: "reset"), 0)
        XCTAssertEqual(WireframeAvatarMotion.yaw(for: "side"), Double.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(WireframeAvatarMotion.applyDrag(yaw: 0.2, dx: 40, dy: 3), 0.2)
        XCTAssertEqual(WireframeAvatarMotion.applyDrag(yaw: 0, dx: 1, dy: 30), 0.24, accuracy: 1e-9)
        XCTAssertEqual(WireframeAvatarMotion.applyDrag(yaw: 3, dx: 0, dy: 100), Double.pi, accuracy: 1e-9)
        XCTAssertEqual(WireframeAvatarMotion.animationDuration(reduceMotion: true), 0)
        XCTAssertEqual(WireframeAvatarMotion.animationDuration(reduceMotion: false), 0.2)
        XCTAssertEqual(WireframeAvatarLibrary.clampUnit(-2), 0)
        XCTAssertEqual(WireframeAvatarLibrary.clampUnit(4), 1)

        let off = WireframeAvatarPolicy.isEnabled { _ in false }
        let stopped = WireframeAvatarPolicy.isEnabled { $0 == WireframeAvatarPolicy.killSwitchKey }
        XCTAssertTrue(off)
        XCTAssertFalse(stopped)

        let fallback = WireframeAvatarLibrary.project(
            vertices: WireframeAvatarLibrary.fallbackVertices(),
            wires: WireframeAvatarLibrary.fallbackWires(),
            yaw: 0,
            width: 200,
            height: 280
        )
        XCTAssertEqual(WireframeAvatarLibrary.fallbackVertices().count, 16)
        XCTAssertFalse(fallback.isEmpty)
    }

    private func loadAsset() throws -> WireframeAvatarAsset {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("LogYourBody")
            .appendingPathComponent("Resources")
            .appendingPathComponent("WireframeAvatarFamily.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WireframeAvatarAsset.self, from: data)
    }

    private func resolved(
        _ asset: WireframeAvatarAsset,
        presentation: String,
        adiposity: Double,
        muscularity: Double,
        frame: Double
    ) -> ResolvedWireframe {
        WireframeAvatarLibrary.resolved(
            asset: asset,
            presentation: presentation,
            adiposity: adiposity,
            muscularity: muscularity,
            frame: frame
        )
    }

    private func assertBounded(
        _ asset: WireframeAvatarAsset,
        presentation: String,
        adiposity: Double,
        muscularity: Double,
        frame: Double
    ) {
        let vertices = WireframeAvatarLibrary.interpolate(
            asset: asset,
            presentation: presentation,
            adiposity: adiposity,
            muscularity: muscularity,
            frame: frame
        )
        XCTAssertEqual(vertices.count, asset.vertexCount)
        for ring in 0..<9 {
            XCTAssertGreaterThan(vertices[(ring + 1) * 16].y, vertices[ring * 16].y)
        }
        for vertex in vertices {
            XCTAssertTrue(vertex.x.isFinite && vertex.y.isFinite && vertex.z.isFinite)
            let radius = hypot(vertex.x, vertex.z)
            XCTAssertGreaterThanOrEqual(radius, 0.18)
            XCTAssertLessThanOrEqual(radius, 0.62)
        }
    }

    private func vertex(_ vertices: [SIMD3<Double>], _ index: Int) -> SIMD3<Double>? {
        vertices.indices.contains(index) ? vertices[index] : nil
    }

    private func shoulderWidth(
        _ asset: WireframeAvatarAsset,
        presentation: String,
        value: Double
    ) -> Double {
        meanAbsX(
            resolved(asset, presentation: presentation, adiposity: value, muscularity: value, frame: value),
            ring: 9
        )
    }

    private func frameWidth(
        _ asset: WireframeAvatarAsset,
        presentation: String,
        frame: Double
    ) -> Double {
        meanAbsX(
            resolved(asset, presentation: presentation, adiposity: 0, muscularity: 0, frame: frame),
            ring: 9
        )
    }

    private func waistWidth(
        _ asset: WireframeAvatarAsset,
        presentation: String,
        adiposity: Double
    ) -> Double {
        meanAbsX(
            resolved(asset, presentation: presentation, adiposity: adiposity, muscularity: 0, frame: 0),
            ring: 3
        )
    }

    private func meanAbsX(_ wireframe: ResolvedWireframe, ring: Int) -> Double {
        let start = ring * 16
        let slice = wireframe.vertices[start..<(start + 16)]
        return slice.reduce(0) { $0 + abs($1.x) } / 16
    }
}
