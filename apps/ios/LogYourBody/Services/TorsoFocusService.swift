//
// TorsoFocusService.swift
// LogYourBody
//
import UIKit
import Vision

/// On-device torso anchor for the photo stage. A Vision body-pose pass finds
/// the midpoint between the shoulders and hips; the crop holds that point on
/// `stageAnchor` so the torso stays in frame and the dimmed band below stays
/// clear for the stat overlay. A nil anchor means "frame the center" — the
/// stage still works on the simulator and on photos without a detected pose.
enum TorsoFocusService {
    /// Where the torso midpoint lands in the stage, as a fraction from the
    /// top-left. Slightly above center leaves the lower band free for stats.
    static let stageAnchor = CGPoint(x: 0.5, y: 0.42)
    static let minimumConfidence: Float = 0.3

    /// Torso midpoint normalized in display space: x right, y down, 0–1.
    static func torsoCenter(in image: UIImage) async -> CGPoint? {
        await reading(in: image).center
    }

    /// One pose pass supplies the crop anchor and the landmark frame. Wrists are
    /// kept so a matte can refuse to drop a hand; they are not a scale source.
    static func reading(in image: UIImage) async -> (center: CGPoint?, frame: BodyLandmarkFrame) {
        let metadata = BodyPhotoCaptureMetadata(
            viewpoint: .unknown,
            mirrored: isMirrored(image.imageOrientation),
            crop: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceSize: image.size
        )
        guard let cgImage = image.cgImage else {
            return (nil, BodyLandmarkFrame(metadata: metadata))
        }
        let orientation = cgImagePropertyOrientation(of: image.imageOrientation)
        let imageSize = image.size
        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.first else {
                return (nil, BodyLandmarkFrame(metadata: metadata))
            }
            var frame = landmarkFrame(of: observation, imageSize: imageSize, metadata: metadata)
            frame.metadata.viewpoint = BodyPhotoAlignmentPolicy.inferredViewpoint(frame)
            return (torsoCenter(of: observation), frame)
        }.value
    }

    static func landmarkFrame(
        of observation: VNHumanBodyPoseObservation,
        imageSize: CGSize,
        metadata: BodyPhotoCaptureMetadata
    ) -> BodyLandmarkFrame {
        let points = try? observation.recognizedPoints(.all)
        func joint(_ name: VNHumanBodyPoseObservation.JointName) -> BodyLandmarkFrame.Joint? {
            guard let points, let point = points[name], point.confidence > minimumConfidence else { return nil }
            return BodyLandmarkFrame.Joint(
                point: CGPoint(
                    x: point.location.x * imageSize.width,
                    y: (1 - point.location.y) * imageSize.height
                ),
                confidence: point.confidence
            )
        }
        return BodyLandmarkFrame(
            leftShoulder: joint(.leftShoulder),
            rightShoulder: joint(.rightShoulder),
            leftHip: joint(.leftHip),
            rightHip: joint(.rightHip),
            leftWrist: joint(.leftWrist),
            rightWrist: joint(.rightWrist),
            metadata: metadata
        )
    }

    /// Torso midpoint from a pose observation, converted from Vision's
    /// bottom-left origin into display space (y down).
    static func torsoCenter(of observation: VNHumanBodyPoseObservation) -> CGPoint? {
        guard let points = try? observation.recognizedPoints(.all) else { return nil }

        guard let shoulders = jointMidpoint(.leftShoulder, .rightShoulder, in: points)
                ?? jointLocation(.neck, in: points),
              let hips = jointMidpoint(.leftHip, .rightHip, in: points)
                ?? jointLocation(.root, in: points) else {
            return nil
        }

        return CGPoint(
            x: (shoulders.x + hips.x) / 2,
            y: 1 - (shoulders.y + hips.y) / 2
        )
    }

    private static func jointLocation(
        _ joint: VNHumanBodyPoseObservation.JointName,
        in points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> CGPoint? {
        guard let point = points[joint], point.confidence > minimumConfidence else { return nil }
        return point.location
    }

    private static func jointMidpoint(
        _ firstJoint: VNHumanBodyPoseObservation.JointName,
        _ secondJoint: VNHumanBodyPoseObservation.JointName,
        in points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> CGPoint? {
        guard let first = jointLocation(firstJoint, in: points),
              let second = jointLocation(secondJoint, in: points) else { return nil }
        return CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    private static func isMirrored(_ orientation: UIImage.Orientation) -> Bool {
        switch orientation {
        case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
            return true
        default:
            return false
        }
    }

    private static func cgImagePropertyOrientation(
        of orientation: UIImage.Orientation
    ) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
