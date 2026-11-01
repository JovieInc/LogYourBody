//
//  WireframeAvatarFamily.swift
//  LogYourBody
//
//  Continuous illustrative torso. One topology and one rig per family.
//  Shape sliders are not body-fat or FFMI. Anny and SMPL-X are not bundled.
//

import Foundation
import simd

struct WireframeAvatarAsset: Decodable {
    struct Family: Decodable {
        let rest: [[Double]]
        let adiposity: [[Double]]
        let muscularity: [[Double]]
        let frame: [[Double]]
    }

    struct Joint: Decodable {
        let name: String
        let position: [Double]
    }

    struct Rig: Decodable {
        let joints: [Joint]
        let weights: [[Double]]
        let pose: String
    }

    struct Bound: Decodable {
        let min: Double
        let max: Double
        let meaning: String
    }

    struct Parameters: Decodable {
        let adiposity: Bound
        let muscularity: Bound
        let frame: Bound
    }

    struct Defaults: Decodable {
        let presentation: String
        let adiposity: Double
        let muscularity: Double
        let frame: Double
        let yaw: Double
    }

    struct CameraSpec: Decodable {
        let projection: String
        let fovDegrees: Double
        let distance: Double
        let target: [Double]
        let frontYaw: Double
        let sideYaw: Double
    }

    struct MaterialSpec: Decodable {
        let kind: String
        let fill: Bool
        let color: String
        let lineWidth: Double
        let idleSpin: Bool
    }

    struct LightingSpec: Decodable {
        let model: String
        let depthCue: String
    }

    struct CachingSpec: Decodable {
        let tier: String
        let vertexBudget: Int
        let wireBudget: Int
        let memoryEntries: Int
        let quantization: Double
        let disk: Bool
        let network: Bool
        let photoBytes: Bool
    }

    struct LicenseSpec: Decodable {
        let asset: String
        let holder: String
        let annyEvaluated: String
        let annyReleased: String
        let annyCodeLicense: String
        let annyDataLicense: String
        let annyBundled: Bool
        let smplxIncluded: Bool
        let smplIncluded: Bool
        let somaIncluded: Bool
    }

    struct AuditSample: Decodable {
        let presentation: String
        let adiposity: Double
        let muscularity: Double
        let frame: Double
        let index: Int
        let position: [Double]
    }

    let modelId: String
    let version: String
    let topologyId: String
    let rigId: String
    let illustrative: Bool
    let mapsToBodyFat: Bool
    let mapsToFfmi: Bool
    let pose: String
    let crop: String
    let vertexCount: Int
    let families: [String: Family]
    let faces: [[Int]]
    let wires: [[Int]]
    let rig: Rig
    let parameters: Parameters
    let defaults: Defaults
    let camera: CameraSpec
    let material: MaterialSpec
    let lighting: LightingSpec
    let caching: CachingSpec
    let license: LicenseSpec
    let selectionRecord: String
    let audit: [AuditSample]
}

struct ResolvedWireframe: Equatable {
    let topologyId: String
    let rigId: String
    let vertices: [SIMD3<Double>]
}

enum WireframeMorphError: Error, Equatable {
    case crossTopology
}

struct WireframeSegment: Equatable {
    let x1: Double
    let y1: Double
    let x2: Double
    let y2: Double
    let opacity: Double
}

enum WireframeAvatarLibrary {
    private static let lock = NSLock()
    private static var memory: [String: [SIMD3<Double>]] = [:]

    static func load(from url: URL) -> WireframeAvatarAsset? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WireframeAvatarAsset.self, from: data)
    }

    static func loadFromBundle(_ bundle: Bundle = .main) -> WireframeAvatarAsset? {
        guard let url = bundle.url(forResource: "WireframeAvatarFamily", withExtension: "json") else {
            return nil
        }
        return load(from: url)
    }

    static func clampUnit(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    static func vertices(
        asset: WireframeAvatarAsset,
        presentation: String,
        adiposity: Double,
        muscularity: Double,
        frame: Double
    ) -> [SIMD3<Double>] {
        let key = cacheKey(
            presentation: presentation,
            adiposity: adiposity,
            muscularity: muscularity,
            frame: frame
        )
        lock.lock()
        if let cached = memory[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = interpolate(
            asset: asset,
            presentation: presentation,
            adiposity: adiposity,
            muscularity: muscularity,
            frame: frame
        )
        lock.lock()
        if memory.count >= asset.caching.memoryEntries {
            memory.removeAll()
        }
        memory[key] = resolved
        lock.unlock()
        return resolved
    }

    static func interpolate(
        asset: WireframeAvatarAsset,
        presentation: String,
        adiposity: Double,
        muscularity: Double,
        frame: Double
    ) -> [SIMD3<Double>] {
        let family = asset.families[presentation] ?? asset.families["male"]
        guard let family else { return fallbackVertices() }
        let blend = Blend(
            size: clampUnit(adiposity),
            muscle: clampUnit(muscularity),
            proportion: clampUnit(frame)
        )
        return family.rest.indices.map { index in
            SIMD3(
                coordinate(family, index, 0, blend),
                coordinate(family, index, 1, blend),
                coordinate(family, index, 2, blend)
            )
        }
    }

    static func resolved(
        asset: WireframeAvatarAsset,
        presentation: String,
        adiposity: Double,
        muscularity: Double,
        frame: Double
    ) -> ResolvedWireframe {
        ResolvedWireframe(
            topologyId: asset.topologyId,
            rigId: asset.rigId,
            vertices: interpolate(
                asset: asset,
                presentation: presentation,
                adiposity: adiposity,
                muscularity: muscularity,
                frame: frame
            )
        )
    }

    static func morph(_ from: ResolvedWireframe, _ to: ResolvedWireframe, t: Double) throws -> ResolvedWireframe {
        guard from.topologyId == to.topologyId,
              from.rigId == to.rigId,
              from.vertices.count == to.vertices.count else {
            throw WireframeMorphError.crossTopology
        }
        let blend = min(1, max(0, t))
        let vertices = zip(from.vertices, to.vertices).map { start, end in
            start + (end - start) * blend
        }
        return ResolvedWireframe(topologyId: from.topologyId, rigId: from.rigId, vertices: vertices)
    }

    static func project(
        vertices: [SIMD3<Double>],
        wires: [[Int]],
        yaw: Double,
        width: Double,
        height: Double
    ) -> [WireframeSegment] {
        let camera = ProjectionCamera(yaw: yaw, width: width, height: height)
        return wires.compactMap { wire in
            guard wire.count == 2, let start = vertex(vertices, wire[0]), let end = vertex(vertices, wire[1]) else {
                return nil
            }
            let first = screen(start, camera)
            let second = screen(end, camera)
            let depth = (first.depth + second.depth) * 0.5
            let opacity = 0.62 + 0.38 * min(1, max(0, (depth + 0.6) / 1.2))
            return WireframeSegment(x1: first.x, y1: first.y, x2: second.x, y2: second.y, opacity: opacity)
        }
    }

    static func fallbackVertices() -> [SIMD3<Double>] {
        (0..<2).flatMap { ring in
            (0..<8).map { segment in
                let theta = Double(segment) / 8 * Double.pi * 2
                let radius = ring == 0 ? 0.3 : 0.38
                return SIMD3(cos(theta) * radius, 0.28 + Double(ring) * 0.4, sin(theta) * radius * 0.8)
            }
        }
    }

    static func fallbackWires() -> [[Int]] {
        (0..<8).flatMap { segment in
            [
                [segment, (segment + 1) % 8],
                [8 + segment, 8 + (segment + 1) % 8],
                [segment, 8 + segment]
            ]
        }
    }

    private static func cacheKey(presentation: String, adiposity: Double, muscularity: Double, frame: Double) -> String {
        let quantize = { (value: Double) in
            String(format: "%.2f", (clampUnit(value) / 0.05).rounded() * 0.05)
        }
        return "\(presentation):\(quantize(adiposity)):\(quantize(muscularity)):\(quantize(frame))"
    }

    private struct Blend {
        let size: Double
        let muscle: Double
        let proportion: Double
    }

    private struct ProjectionCamera {
        let cosine: Double
        let sine: Double
        let focal: Double
        let width: Double
        let height: Double

        init(yaw: Double, width: Double, height: Double) {
            cosine = cos(yaw)
            sine = sin(yaw)
            focal = height * 0.92
            self.width = width
            self.height = height
        }
    }

    private static func coordinate(
        _ family: WireframeAvatarAsset.Family,
        _ index: Int,
        _ axis: Int,
        _ blend: Blend
    ) -> Double {
        let rest = family.rest[index]
        let base = axis < rest.count ? rest[axis] : 0
        return base
            + blend.size * delta(family.adiposity, index, axis)
            + blend.muscle * delta(family.muscularity, index, axis)
            + blend.proportion * delta(family.frame, index, axis)
    }

    private static func delta(_ values: [[Double]], _ index: Int, _ axis: Int) -> Double {
        guard values.indices.contains(index), values[index].indices.contains(axis) else { return 0 }
        return values[index][axis]
    }

    private static func vertex(_ vertices: [SIMD3<Double>], _ index: Int) -> SIMD3<Double>? {
        vertices.indices.contains(index) ? vertices[index] : nil
    }

    private static func screen(
        _ point: SIMD3<Double>,
        _ camera: ProjectionCamera
    ) -> (x: Double, y: Double, depth: Double) {
        let x = point.x * camera.cosine + point.z * camera.sine
        let depth = -point.x * camera.sine + point.z * camera.cosine
        let safe = max(depth + 2.35, 0.35)
        return (
            camera.width * 0.5 + x / safe * camera.focal,
            camera.height * 0.5 - (point.y - 0.5) / safe * camera.focal,
            depth
        )
    }
}

actor WireframeAvatarCache {
    static let shared = WireframeAvatarCache()
    private var stored: WireframeAvatarAsset?
    private var didLoad = false

    func asset() -> WireframeAvatarAsset? {
        if didLoad { return stored }
        didLoad = true
        stored = WireframeAvatarLibrary.loadFromBundle()
        return stored
    }
}
