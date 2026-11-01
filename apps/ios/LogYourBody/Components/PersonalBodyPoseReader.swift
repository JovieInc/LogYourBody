//
//  PersonalBodyPoseReader.swift
//  LogYourBody
//
//  On-device pose check for a labeled front or side. A missing body stays
//  unsupported. The numbers are shoulder span and profile depth, not body fat.
//

import UIKit
import Vision

enum PersonalBodyPoseReader {
    static func read(image: UIImage, view: PersonalBodyViewKind) async -> PersonalBodyCapture {
        guard let cgImage = image.cgImage else {
            return observation(view: view, shoulderSpan: nil, profileDepth: nil)
        }
        let orientation = cgImagePropertyOrientation(of: image.imageOrientation)
        let points = await Task.detached(priority: .userInitiated) {
            joints(in: cgImage, orientation: orientation)
        }.value
        return observation(view: view, shoulderSpan: points?.shoulderSpan, profileDepth: points?.profileDepth)
    }

    static func observation(
        view: PersonalBodyViewKind,
        shoulderSpan: Double?,
        profileDepth: Double?
    ) -> PersonalBodyCapture {
        let quality = PersonalBodyEstimate.classifyPose(
            view: view,
            shoulderSpan: shoulderSpan,
            profileDepth: profileDepth
        )
        return PersonalBodyCapture(
            id: "",
            accountId: "",
            photoId: "",
            sessionId: nil,
            view: view,
            effectiveDate: "",
            quality: quality,
            torsoWidth: view == .front && quality == .supported ? shoulderSpan : nil,
            torsoDepth: view == .side && quality == .supported ? profileDepth : nil,
            dexaBodyFat: nil,
            dexaDate: nil
        )
    }

    private struct Joints {
        let shoulderSpan: Double?
        let profileDepth: Double?
    }

    private static func joints(in image: CGImage, orientation: CGImagePropertyOrientation) -> Joints? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let points = try? observation.recognizedPoints(.all) else { return nil }
        let left = location(.leftShoulder, in: points)
        let right = location(.rightShoulder, in: points)
        let shoulderSpan: Double?
        if let left, let right {
            shoulderSpan = hypot(Double(left.x - right.x), Double(left.y - right.y))
        } else {
            shoulderSpan = nil
        }
        let shoulders = midpoint(left, right)
        let hips = midpoint(location(.leftHip, in: points), location(.rightHip, in: points))
        let profileDepth: Double?
        if let shoulders, let hips {
            profileDepth = abs(Double(shoulders.x - hips.x))
        } else {
            profileDepth = nil
        }
        return Joints(shoulderSpan: shoulderSpan, profileDepth: profileDepth)
    }

    private static func location(
        _ joint: VNHumanBodyPoseObservation.JointName,
        in points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
    ) -> CGPoint? {
        guard let point = points[joint], point.confidence > 0.3 else { return nil }
        return point.location
    }

    private static func midpoint(_ first: CGPoint?, _ second: CGPoint?) -> CGPoint? {
        guard let first, let second else { return nil }
        return CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }

    private static func cgImagePropertyOrientation(of orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
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
