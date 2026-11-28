import CoreGraphics
import Foundation
import UIKit

enum PhotographicAppearanceSampler {
    /// Reads a new grayscale buffer. The source image is not modified.
    static func tones(cgImage: CGImage, count: Int) -> [Double]? {
        guard count > 0 else { return nil }
        let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { pixels.deallocate() }
        guard let context = CGContext(
            data: pixels,
            width: count,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: count,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: count, height: 1))
        return (0..<count).map { Double(pixels[$0]) / 255 }
    }
}

enum PhotographicAppearancePolicy {
    static let flagKey = "photographic_appearance_v1"
    static let killSwitchKey = "photographic_appearance_kill_switch"
    static let releaseDescriptor = FeatureReleaseDescriptor(
        flagKey: flagKey,
        killSwitchKey: killSwitchKey,
        stage: .dogfood,
        minimumBuild: nil
    )

    @MainActor
    static func isEnabled(isGateEnabled: ((String) -> Bool)? = nil) -> Bool {
        let check = isGateEnabled ?? { AppServicePorts.analyticsTracker.isFeatureEnabled(flagKey: $0) }
        return FeatureReleaseEvaluator.evaluate(
            releaseDescriptor,
            context: FeatureReleaseContext(
                actor: .ordinaryCustomer,
                installedBuild: 1,
                configState: .fresh,
                enableGate: check(flagKey),
                killSwitch: check(killSwitchKey)
            )
        ).isEnabled
    }
}

struct PhotographicAppearanceGeometry: Codable, Equatable {
    var snapshotId: String
    var accountId: String
    var bodyId: String
    var effectiveDate: String
    var captureDate: String
    var modelId: String
    var modelVersion: String
    var topologyId: String
    var rigId: String
    var framingId: String
    var shape: PersonalBodyShape
}

struct PhotographicAppearanceSample: Codable, Equatable {
    var accountId: String
    var photoId: String
    var view: String
    var effectiveDate: String
    var captureDate: String
    var framingId: String
    var quality: String
    var samples: [Double]
    var sourceDigest: String
}

struct PhotographicAppearanceTexel: Codable, Equatable {
    var cellId: String
    var region: String
    var slot: Int
    var provenance: String
    var tone: Double?
    var photoId: String?
}

struct PhotographicAppearanceSplat: Codable, Equatable {
    var cellId: String
    var slot: Int
    var tone: Double
    var opacity: Double
    var provenance: String
}

struct PhotographicAppearanceAsset: Codable, Equatable {
    var schema: String
    var id: String
    var cacheKey: String
    var snapshotId: String
    var accountId: String
    var bodyId: String
    var effectiveDate: String
    var captureDate: String
    var modelId: String
    var modelVersion: String
    var presentationVersion: String
    var topologyId: String
    var rigId: String
    var framingId: String
    var shape: PersonalBodyShape
    var licenseId: String
    var rights: String
    var projectionId: String
    var gaussianLayerId: String?
    var representation: String
    var texels: [PhotographicAppearanceTexel]
    var splats: [PhotographicAppearanceSplat]
    var photoIds: [String]
    var sourceDigests: [String: String]
    var geometryDrift: Double
    var appearanceDrift: Double
    var observedCount: Int
    var inferredCount: Int
    var interactive: Bool
    var claimsBodyFat: Bool
    var claimsWeeklyChange: Bool
}

struct PhotographicAppearanceArchive: Codable, Equatable {
    var accountId: String
    var samples: [PhotographicAppearanceSample]
    var geometries: [PhotographicAppearanceGeometry]
    var assets: [PhotographicAppearanceAsset]

    static func empty(_ accountId: String) -> PhotographicAppearanceArchive {
        PhotographicAppearanceArchive(accountId: accountId, samples: [], geometries: [], assets: [])
    }
}

struct PhotographicAppearanceOptions: Equatable {
    var representation: String
    var computeAvailable: Bool
    var licenseOk: Bool
    var requestedModel: String?
    var thermal: String
    var lowEndDevice: Bool
    var reduceMotion: Bool
    var gesture: Bool
    var remoteRequested: Bool
    var memoryLimitBytes: Int?

    static let precompute = PhotographicAppearanceOptions(
        representation: "projection",
        computeAvailable: true,
        licenseOk: true,
        requestedModel: nil,
        thermal: "nominal",
        lowEndDevice: false,
        reduceMotion: false,
        gesture: false,
        remoteRequested: false,
        memoryLimitBytes: nil
    )
}

enum PhotographicAppearanceResult: Equatable {
    case asset(PhotographicAppearanceAsset)
    case fallback(String)
}

struct PhotographicAppearanceComparison: Equatable {
    var bodyFatDelta: Double?
    var weeklyChange: Double?
    var geometryChangedByAppearance: Bool
    var observedToneDelta: Double?
    var label: String
    var before: PersonalBodyShape
    var after: PersonalBodyShape
}

struct PhotographicAppearanceDisplay: Equatable {
    var label: String
    var shape: PersonalBodyShape
    var observedRegions: [String]
    var toneByRegion: [String: Double]
    var claimsBodyFat: Bool
    var claimsWeeklyChange: Bool
}

struct PhotographicAppearancePromotion: Equatable {
    var tier: String
    var baselineObservedCoverage: Double
    var observedCoverage: Double
    var geometryDrift: Double
    var introducedBodyFatClaim: Bool
    var introducedWeeklyChange: Bool
    var truthfulProgress: Bool
    var rightsRecorded: Bool
    var lowEndDeviceEvidence: String
}
