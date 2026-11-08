//
// BodyPhotoPresentation.swift
// LogYourBody
//
// Matting, framing and temporal alignment for the Home photo stage.
// Derivatives are reversible masks and similarity transforms. The source
// photograph is never rewritten, beautified or nonrigidly warped.
//
import CoreGraphics

enum BodyViewpoint: String, Equatable {
    case front
    case side
    case unknown
}

struct BodyPhotoCaptureMetadata: Equatable {
    var viewpoint: BodyViewpoint
    var mirrored: Bool
    /// Normalized crop in the source, origin top-left. The full frame is the unit square.
    var crop: CGRect
    /// Point size of the image whose landmarks live in this metadata's space.
    var sourceSize: CGSize
}

struct BodyLandmarkFrame: Equatable {
    struct Joint: Equatable {
        var point: CGPoint
        var confidence: Float
    }

    var leftShoulder: Joint?
    var rightShoulder: Joint?
    var leftHip: Joint?
    var rightHip: Joint?
    var leftWrist: Joint?
    var rightWrist: Joint?
    var metadata: BodyPhotoCaptureMetadata

    func mapped(by registration: BodyPhotoRegistration) -> BodyLandmarkFrame {
        var copy = self
        copy.leftShoulder = leftShoulder?.applying(registration)
        copy.rightShoulder = rightShoulder?.applying(registration)
        copy.leftHip = leftHip?.applying(registration)
        copy.rightHip = rightHip?.applying(registration)
        copy.leftWrist = leftWrist?.applying(registration)
        copy.rightWrist = rightWrist?.applying(registration)
        return copy
    }

    /// Wrists the matte must keep. Shoulder width is intentionally absent.
    func protectedPoints(minimumConfidence: Float = BodyPhotoAlignmentPolicy.minimumConfidence) -> [CGPoint] {
        [leftWrist, rightWrist].compactMap { joint in
            guard let joint, joint.confidence >= minimumConfidence else { return nil }
            return joint.point
        }
    }
}

private extension BodyLandmarkFrame.Joint {
    func applying(_ registration: BodyPhotoRegistration) -> BodyLandmarkFrame.Joint {
        BodyLandmarkFrame.Joint(point: point.applying(registration.transform), confidence: confidence)
    }
}

enum BodyPhotoHonestReason: String, Equatable {
    case poseMismatch
    case mirrorDisagreement
    case missingLandmarks
    case unsupportedCrop
}

enum BodyPhotoAlignment: Equatable {
    case aligned(
        BodyPhotoRegistration,
        source: BodyPhotoCaptureMetadata,
        target: BodyPhotoCaptureMetadata
    )
    case honest(
        BodyPhotoHonestReason,
        source: BodyPhotoCaptureMetadata,
        target: BodyPhotoCaptureMetadata
    )

    var sourceMetadata: BodyPhotoCaptureMetadata {
        switch self {
        case .aligned(_, let source, _), .honest(_, let source, _):
            return source
        }
    }

    var targetMetadata: BodyPhotoCaptureMetadata {
        switch self {
        case .aligned(_, _, let target), .honest(_, _, let target):
            return target
        }
    }
}

enum BodyPhotoAlignmentPolicy {
    static let minimumConfidence: Float = 0.3
    static let minimumTorsoLength: CGFloat = 1
    static let frontShoulderRatio: CGFloat = 0.45
    static let sideShoulderRatio: CGFloat = 0.28

    static func inferredViewpoint(_ frame: BodyLandmarkFrame) -> BodyViewpoint {
        guard let shoulders = midpoint(frame.leftShoulder, frame.rightShoulder),
              let hips = midpoint(frame.leftHip, frame.rightHip),
              let width = distance(frame.leftShoulder, frame.rightShoulder) else {
            return .unknown
        }
        let torso = hypot(shoulders.x - hips.x, shoulders.y - hips.y)
        guard torso >= minimumTorsoLength else { return .unknown }
        let ratio = width / torso
        if ratio >= frontShoulderRatio { return .front }
        if ratio <= sideShoulderRatio { return .side }
        return .unknown
    }

    static func cropSupported(_ metadata: BodyPhotoCaptureMetadata) -> Bool {
        let size = metadata.sourceSize
        guard size.width.isFinite, size.height.isFinite, size.width > 1, size.height > 1 else { return false }
        let aspect = size.width / size.height
        guard aspect > 0.2, aspect < 5 else { return false }
        let crop = metadata.crop
        guard crop.origin.x.isFinite, crop.origin.y.isFinite,
              crop.width.isFinite, crop.height.isFinite,
              crop.width > 0, crop.height > 0 else { return false }
        return crop.minX >= -0.001 && crop.minY >= -0.001 && crop.maxX <= 1.001 && crop.maxY <= 1.001
    }

    /// Similarity that places `source` onto `target` using the torso segment only.
    /// Shoulder width never contributes to scale, so a real change in width remains.
    static func align(source: BodyLandmarkFrame, onto target: BodyLandmarkFrame) -> BodyPhotoAlignment {
        let sourceMeta = source.metadata
        let targetMeta = target.metadata
        guard cropSupported(sourceMeta), cropSupported(targetMeta) else {
            return .honest(.unsupportedCrop, source: sourceMeta, target: targetMeta)
        }
        if sourceMeta.mirrored != targetMeta.mirrored {
            return .honest(.mirrorDisagreement, source: sourceMeta, target: targetMeta)
        }
        let sourceView = resolvedViewpoint(source)
        let targetView = resolvedViewpoint(target)
        guard sourceView != .unknown, sourceView == targetView else {
            return .honest(.poseMismatch, source: sourceMeta, target: targetMeta)
        }
        guard let sourceAxis = torsoAxis(source), let targetAxis = torsoAxis(target) else {
            return .honest(.missingLandmarks, source: sourceMeta, target: targetMeta)
        }
        let scale = targetAxis.length / sourceAxis.length
        let rotation = targetAxis.angle - sourceAxis.angle
        guard let registration = registration(
            scale: scale,
            rotation: rotation,
            sourceCenter: sourceAxis.center,
            targetCenter: targetAxis.center
        ) else {
            return .honest(.missingLandmarks, source: sourceMeta, target: targetMeta)
        }
        return .aligned(registration, source: sourceMeta, target: targetMeta)
    }

    /// Maps the source photograph onto the stage occupied by the target's torso crop.
    static func stageRegistration(
        source: BodyLandmarkFrame,
        target: BodyLandmarkFrame,
        targetImageSize: CGSize,
        stage: CGSize,
        anchor: CGPoint?
    ) -> BodyPhotoAlignment {
        guard let crop = AspectFillCropper.registration(
            imageSize: targetImageSize,
            in: stage,
            anchor: anchor
        ) else {
            return .honest(.unsupportedCrop, source: source.metadata, target: target.metadata)
        }
        return align(source: source, onto: target.mapped(by: crop))
    }

    private static func resolvedViewpoint(_ frame: BodyLandmarkFrame) -> BodyViewpoint {
        frame.metadata.viewpoint == .unknown ? inferredViewpoint(frame) : frame.metadata.viewpoint
    }

    private static func torsoAxis(_ frame: BodyLandmarkFrame) -> (center: CGPoint, length: CGFloat, angle: CGFloat)? {
        guard let shoulders = midpoint(frame.leftShoulder, frame.rightShoulder),
              let hips = midpoint(frame.leftHip, frame.rightHip) else { return nil }
        let delta = CGPoint(x: shoulders.x - hips.x, y: shoulders.y - hips.y)
        let length = hypot(delta.x, delta.y)
        guard length >= minimumTorsoLength else { return nil }
        let center = CGPoint(x: (shoulders.x + hips.x) / 2, y: (shoulders.y + hips.y) / 2)
        return (center, length, atan2(delta.y, delta.x))
    }

    private static func registration(
        scale: CGFloat,
        rotation: CGFloat,
        sourceCenter: CGPoint,
        targetCenter: CGPoint
    ) -> BodyPhotoRegistration? {
        guard let partial = BodyPhotoRegistration(translation: .zero, rotation: rotation, scale: scale) else { return nil }
        let rotated = sourceCenter.applying(partial.transform)
        return BodyPhotoRegistration(
            translation: CGPoint(x: targetCenter.x - rotated.x, y: targetCenter.y - rotated.y),
            rotation: rotation,
            scale: scale
        )
    }

    private static func midpoint(_ first: BodyLandmarkFrame.Joint?, _ second: BodyLandmarkFrame.Joint?) -> CGPoint? {
        guard let first, let second,
              first.confidence >= minimumConfidence,
              second.confidence >= minimumConfidence else { return nil }
        return CGPoint(x: (first.point.x + second.point.x) / 2, y: (first.point.y + second.point.y) / 2)
    }

    private static func distance(_ first: BodyLandmarkFrame.Joint?, _ second: BodyLandmarkFrame.Joint?) -> CGFloat? {
        guard let first, let second,
              first.confidence >= minimumConfidence,
              second.confidence >= minimumConfidence else { return nil }
        return hypot(first.point.x - second.point.x, first.point.y - second.point.y)
    }
}
