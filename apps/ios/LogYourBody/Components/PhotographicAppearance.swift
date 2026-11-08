//
//  PhotographicAppearance.swift
//  LogYourBody
//
//  On-device photo projection onto the accepted outline. The outline's shape
//  stays put. Unseen surfaces stay unmarked. DiGS-Avatar is not bundled.
//

import CoreGraphics
import Foundation
import UIKit

enum PhotographicAppearance {
    static let schema = "lyb.photographic-appearance.v1"
    static let projectionId = "lyb.appearance.photo-projection.v1"
    static let gaussianLayerId = "lyb.appearance.gaussian-layer.v1"
    static let presentationVersion = "lyb.appearance.presentation.v1"
    static let framingId = "lyb.capture.framing.v1"
    static let modelId = "lyb.wireframe.torso"
    static let modelVersion = "1.0.0"
    static let topologyId = "lyb.wireframe.torso.v1"
    static let rigId = "lyb.wireframe.torso.rig.v1"
    static let licenseId = "CC0-1.0"
    static let rightsHolder = "first-party"
    static let cellsPerRegion = 8
    static let regions = ["front", "side", "back"]
    static let baselineCoverage = 0.0
    static let refusedModels = ["DiGS-Avatar", "SMPL", "SMPL-X", "SOMA", "Anny"]
    static let allowedModels = [projectionId, gaussianLayerId, "first-party"]
    static let texelStride = 16
    static let splatStride = 48
    static let maxBytes = 4_096
    static let lowEndMaxBytes = 1_024
    static let retains = ["photo", "wireframe", "personal-mesh"]

    static var cellCount: Int { regions.count * cellsPerRegion }

    static func copyShape(_ shape: PersonalBodyShape) -> PersonalBodyShape {
        PersonalBodyShape(
            adiposity: shape.adiposity,
            muscularity: shape.muscularity,
            frame: shape.frame,
            depth: shape.depth
        )
    }

    static func shapeDrift(_ left: PersonalBodyShape, _ right: PersonalBodyShape) -> Double {
        max(
            abs(left.adiposity - right.adiposity),
            abs(left.muscularity - right.muscularity),
            abs(left.frame - right.frame),
            abs(left.depth - right.depth)
        )
    }

    static func sealedShape(
        _ accepted: PersonalBodyShape,
        proposed: PersonalBodyShape?
    ) -> (shape: PersonalBodyShape, rejectedDelta: Double) {
        (copyShape(accepted), proposed.map { shapeDrift(accepted, $0) } ?? 0)
    }

    static func replaceOriginal(original: [Double], proposed: [Double]) -> (ok: Bool, reason: String) {
        _ = original.count + proposed.count
        return (false, "original-photo")
    }

    static func estimateBytes(representation: String, observedCount: Int) -> Int {
        let projection = cellCount * texelStride
        if representation == "projection" { return projection }
        return projection + observedCount * splatStride
    }

    static func withinBudget(bytes: Int, lowEndDevice: Bool, memoryLimitBytes: Int?) -> Bool {
        let tier = lowEndDevice ? lowEndMaxBytes : maxBytes
        let limit = memoryLimitBytes.map { min(tier, $0) } ?? tier
        return bytes <= limit
    }

    static func visibleRegion(_ yaw: Double) -> String {
        let wrapped = atan2(sin(yaw), cos(yaw))
        let distance = abs(wrapped)
        if distance <= .pi / 4 { return "front" }
        if distance >= (.pi * 3) / 4 { return "back" }
        return "side"
    }

    static func motion(reduceMotion: Bool) -> (duration: Double, autoSpin: Bool) {
        (reduceMotion ? 0 : 0.2, false)
    }

    static func coverage(_ asset: PhotographicAppearanceAsset?) -> Double {
        guard let asset, !asset.texels.isEmpty else { return 0 }
        return Double(asset.observedCount) / Double(asset.texels.count)
    }

    static func project(
        geometry: PhotographicAppearanceGeometry,
        samples: [PhotographicAppearanceSample],
        options: PhotographicAppearanceOptions
    ) -> PhotographicAppearanceResult {
        if options.gesture { return .fallback("gesture") }
        if options.remoteRequested { return .fallback("remote-regeneration") }
        if options.representation == "turntable" { return .fallback("not-interactive") }
        if licenseRefusal(options) { return .fallback("license") }
        if !options.computeAvailable { return .fallback("compute") }
        if options.thermal == "serious" || options.thermal == "critical" { return .fallback("thermal") }
        if !acceptedModel(geometry) { return .fallback("model") }
        let used = samples.filter { usable($0, geometry) }
        guard !used.isEmpty else { return .fallback("unsupported") }
        guard let representation = representationFor(options) else { return .fallback("budget") }
        return .asset(makeAsset(geometry, used, representation))
    }

    static func quantifyDrift(
        corpus: [PhotographicAppearanceGeometry],
        asset: PhotographicAppearanceAsset
    ) -> (matched: Bool, geometryDrift: Double, appearanceDrift: Double) {
        guard let accepted = corpus.first(where: { $0.snapshotId == asset.snapshotId }) else {
            return (false, .infinity, asset.appearanceDrift)
        }
        return (true, shapeDrift(accepted.shape, asset.shape), asset.appearanceDrift)
    }

    static func lookup(
        date: String,
        cache: [PhotographicAppearanceAsset],
        topologyId: String
    ) -> PhotographicAppearanceAsset? {
        cache.last { $0.effectiveDate == date && $0.topologyId == topologyId }
    }

    static func readForGesture(
        cacheKey: String,
        cache: [PhotographicAppearanceAsset],
        remoteRequested: Bool
    ) -> (asset: PhotographicAppearanceAsset?, regenerated: Bool, reason: String?) {
        if remoteRequested { return (nil, false, "remote-regeneration") }
        let asset = cache.first { $0.cacheKey == cacheKey }
        return (asset, false, asset == nil ? "cache-miss" : nil)
    }

    static func progressDisplay(
        before: PhotographicAppearanceAsset,
        after: PhotographicAppearanceAsset,
        yaw: Double
    ) -> PhotographicAppearanceComparison {
        let region = visibleRegion(yaw)
        var deltas: [Double] = []
        for left in before.texels where left.region == region && left.provenance == "observed" {
            guard let tone = left.tone,
                  let right = after.texels.first(where: { $0.cellId == left.cellId }),
                  right.provenance == "observed",
                  let other = right.tone else { continue }
            deltas.append(other - tone)
        }
        let observed = deltas.isEmpty ? nil : deltas.reduce(0, +) / Double(deltas.count)
        let label = observed == nil
            ? "Viewpoint has no shared observation"
            : "Appearance only. Not a weekly change."
        return PhotographicAppearanceComparison(
            bodyFatDelta: nil,
            weeklyChange: nil,
            geometryChangedByAppearance: false,
            observedToneDelta: observed,
            label: label,
            before: copyShape(before.shape),
            after: copyShape(after.shape)
        )
    }

    static func remember(
        archive: PhotographicAppearanceArchive,
        sample: PhotographicAppearanceSample,
        geometry: PhotographicAppearanceGeometry,
        options: PhotographicAppearanceOptions = .precompute
    ) -> PhotographicAppearanceArchive {
        var next = archive
        next.samples = mergeSamples(archive.samples, sample)
        next.geometries = mergeGeometries(archive.geometries, geometry)
        let dated = next.samples.filter {
            $0.accountId == geometry.accountId && $0.effectiveDate == geometry.effectiveDate
        }
        guard case .asset(let asset) = project(geometry: geometry, samples: dated, options: options) else {
            return next
        }
        next.assets.removeAll {
            $0.accountId == geometry.accountId && $0.effectiveDate == geometry.effectiveDate
        }
        next.assets.append(asset)
        return next
    }

    static func forgetPhoto(
        _ archive: PhotographicAppearanceArchive,
        photoId: String
    ) -> PhotographicAppearanceArchive {
        var next = archive
        next.samples.removeAll { $0.photoId == photoId }
        next.assets.removeAll { assetUsesPhoto($0, photoId) }
        next.geometries.removeAll { geometry in
            !next.samples.contains {
                $0.accountId == geometry.accountId && $0.effectiveDate == geometry.effectiveDate
            }
        }
        return next
    }

    static func forgetAccount(_ archive: PhotographicAppearanceArchive) -> PhotographicAppearanceArchive {
        PhotographicAppearanceArchive.empty(archive.accountId)
    }

    static func appearanceLabel(_ asset: PhotographicAppearanceAsset) -> String {
        var observed: [String] = []
        for region in regions where asset.texels.contains(where: {
            $0.region == region && $0.provenance == "observed"
        }) {
            observed.append(region)
        }
        guard !observed.isEmpty else { return "Unseen surfaces stay unmarked" }
        return "Observed \(joinRegions(observed)). Unseen surfaces stay unmarked."
    }

    static func display(for asset: PhotographicAppearanceAsset) -> PhotographicAppearanceDisplay {
        var sums: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for texel in asset.texels where texel.provenance == "observed" {
            sums[texel.region, default: 0] += texel.tone ?? 0
            counts[texel.region, default: 0] += 1
        }
        var tones: [String: Double] = [:]
        var observed: [String] = []
        for region in regions {
            guard let count = counts[region], count > 0, let sum = sums[region] else { continue }
            observed.append(region)
            tones[region] = sum / Double(count)
        }
        return PhotographicAppearanceDisplay(
            label: appearanceLabel(asset),
            shape: asset.shape,
            observedRegions: observed,
            toneByRegion: tones,
            claimsBodyFat: false,
            claimsWeeklyChange: false
        )
    }

    static func promotionDecision(_ evidence: PhotographicAppearancePromotion) -> (promoted: Bool, reasons: [String]) {
        var reasons: [String] = []
        if evidence.tier != "repeatable-on-device" && evidence.tier != "calibrated" { reasons.append("tier") }
        if evidence.observedCoverage <= evidence.baselineObservedCoverage { reasons.append("improvement") }
        if evidence.geometryDrift != 0 { reasons.append("geometry-drift") }
        if evidence.introducedBodyFatClaim || evidence.introducedWeeklyChange || !evidence.truthfulProgress {
            reasons.append("false-progress")
        }
        if !evidence.rightsRecorded { reasons.append("rights") }
        if evidence.lowEndDeviceEvidence != "physical-device" && evidence.lowEndDeviceEvidence != "distributed-build" {
            reasons.append("device-evidence")
        }
        return (reasons.isEmpty, reasons)
    }

    private static func makeAsset(
        _ geometry: PhotographicAppearanceGeometry,
        _ used: [PhotographicAppearanceSample],
        _ representation: String
    ) -> PhotographicAppearanceAsset {
        let sealed = sealedShape(geometry.shape, proposed: nil)
        var byRegion: [String: PhotographicAppearanceSample] = [:]
        for sample in used { byRegion[sample.view] = sample }
        var texels: [PhotographicAppearanceTexel] = []
        var splats: [PhotographicAppearanceSplat] = []
        for (regionIndex, region) in regions.enumerated() {
            let source = byRegion[region]
            for index in 0..<cellsPerRegion {
                let cellId = "\(region)-\(index)"
                let slot = regionIndex * cellsPerRegion + index
                guard let source else {
                    texels.append(PhotographicAppearanceTexel(
                        cellId: cellId, region: region, slot: slot, provenance: "inferred", tone: nil, photoId: nil
                    ))
                    continue
                }
                let tone = index < source.samples.count ? source.samples[index] : 0
                texels.append(PhotographicAppearanceTexel(
                    cellId: cellId, region: region, slot: slot, provenance: "observed", tone: tone, photoId: source.photoId
                ))
                if representation == "gaussian" {
                    splats.append(PhotographicAppearanceSplat(
                        cellId: cellId, slot: slot, tone: tone, opacity: 1, provenance: "observed"
                    ))
                }
            }
        }
        var photoIds: [String] = []
        var digests: [String: String] = [:]
        var captureDates: [String] = []
        for sample in used {
            if !photoIds.contains(sample.photoId) { photoIds.append(sample.photoId) }
            digests[sample.photoId] = sample.sourceDigest
            captureDates.append(sample.captureDate)
        }
        let cacheKey = fingerprint([
            geometry.snapshotId, geometry.topologyId, geometry.modelVersion, geometry.framingId, representation
        ] + photoIds.sorted())
        return PhotographicAppearanceAsset(
            schema: schema,
            id: fingerprint([geometry.accountId, geometry.effectiveDate, cacheKey]),
            cacheKey: cacheKey,
            snapshotId: geometry.snapshotId,
            accountId: geometry.accountId,
            bodyId: geometry.bodyId,
            effectiveDate: geometry.effectiveDate,
            captureDate: captureDates.max() ?? geometry.captureDate,
            modelId: geometry.modelId,
            modelVersion: geometry.modelVersion,
            presentationVersion: presentationVersion,
            topologyId: geometry.topologyId,
            rigId: geometry.rigId,
            framingId: geometry.framingId,
            shape: sealed.shape,
            licenseId: licenseId,
            rights: rightsHolder,
            projectionId: projectionId,
            gaussianLayerId: representation == "gaussian" ? gaussianLayerId : nil,
            representation: representation,
            texels: texels,
            splats: splats,
            photoIds: photoIds,
            sourceDigests: digests,
            geometryDrift: shapeDrift(geometry.shape, sealed.shape),
            appearanceDrift: toneDrift(used, texels),
            observedCount: texels.filter { $0.provenance == "observed" }.count,
            inferredCount: texels.filter { $0.provenance == "inferred" }.count,
            interactive: true,
            claimsBodyFat: false,
            claimsWeeklyChange: false
        )
    }

    private static func toneDrift(
        _ samples: [PhotographicAppearanceSample],
        _ texels: [PhotographicAppearanceTexel]
    ) -> Double {
        var deltas: [Double] = []
        for sample in samples {
            for (index, tone) in sample.samples.enumerated() {
                guard let texel = texels.first(where: { $0.cellId == "\(sample.view)-\(index)" }),
                      let stored = texel.tone else { continue }
                deltas.append(abs(stored - tone))
            }
        }
        guard !deltas.isEmpty else { return 0 }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    private static func usable(
        _ sample: PhotographicAppearanceSample,
        _ geometry: PhotographicAppearanceGeometry
    ) -> Bool {
        guard sample.accountId == geometry.accountId,
              sample.effectiveDate == geometry.effectiveDate,
              regions.contains(sample.view),
              sample.quality == "supported",
              sample.framingId == geometry.framingId,
              sample.framingId == framingId,
              !sample.photoId.isEmpty,
              !sample.captureDate.isEmpty,
              !sample.sourceDigest.isEmpty,
              sample.samples.count == cellsPerRegion else { return false }
        return sample.samples.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 }
    }

    private static func acceptedModel(_ geometry: PhotographicAppearanceGeometry) -> Bool {
        geometry.modelId == modelId &&
            geometry.modelVersion == modelVersion &&
            geometry.topologyId == topologyId &&
            geometry.rigId == rigId &&
            geometry.framingId == framingId &&
            !geometry.snapshotId.isEmpty &&
            !geometry.bodyId.isEmpty
    }

    private static func licenseRefusal(_ options: PhotographicAppearanceOptions) -> Bool {
        if !options.licenseOk { return true }
        guard let requested = options.requestedModel, !requested.isEmpty else { return false }
        if refusedModels.contains(requested) { return true }
        return !allowedModels.contains(requested)
    }

    private static func representationFor(_ options: PhotographicAppearanceOptions) -> String? {
        let wanted = options.representation == "gaussian" ? "gaussian" : "projection"
        if withinBudget(
            bytes: estimateBytes(representation: wanted, observedCount: cellCount),
            lowEndDevice: options.lowEndDevice,
            memoryLimitBytes: options.memoryLimitBytes
        ) {
            return wanted
        }
        if wanted == "gaussian" && withinBudget(
            bytes: estimateBytes(representation: "projection", observedCount: cellCount),
            lowEndDevice: options.lowEndDevice,
            memoryLimitBytes: options.memoryLimitBytes
        ) {
            return "projection"
        }
        return nil
    }

    private static func assetUsesPhoto(_ asset: PhotographicAppearanceAsset, _ photoId: String) -> Bool {
        asset.photoIds.contains(photoId) ||
            asset.texels.contains { $0.photoId == photoId } ||
            asset.sourceDigests[photoId] != nil
    }

    private static func mergeSamples(
        _ current: [PhotographicAppearanceSample],
        _ sample: PhotographicAppearanceSample
    ) -> [PhotographicAppearanceSample] {
        var next = current.filter {
            !($0.accountId == sample.accountId && $0.photoId == sample.photoId && $0.view == sample.view)
        }
        next.append(sample)
        return next
    }

    private static func mergeGeometries(
        _ current: [PhotographicAppearanceGeometry],
        _ geometry: PhotographicAppearanceGeometry
    ) -> [PhotographicAppearanceGeometry] {
        var next = current.filter {
            !(
                $0.accountId == geometry.accountId &&
                    $0.effectiveDate == geometry.effectiveDate &&
                    $0.topologyId == geometry.topologyId
            )
        }
        next.append(geometry)
        return next
    }

    private static func joinRegions(_ regions: [String]) -> String {
        if regions.count == 2, let first = regions.first, let last = regions.last {
            return "\(first) and \(last)"
        }
        guard let last = regions.last else { return "" }
        if regions.count == 1 { return last }
        return regions.dropLast().joined(separator: ", ") + ", and " + last
    }

    private static func fingerprint(_ parts: [String]) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in parts.joined(separator: "\u{1f}").utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }
}
