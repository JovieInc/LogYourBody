//
// VisionOrientationService.swift
// LogYourBody
//
import UIKit
import Vision
import CoreImage

@MainActor
class VisionOrientationService {
    static let shared = VisionOrientationService()

    private init() {}

    /// Detects the orientation of a person in the image and returns a properly oriented image
    func correctImageOrientation(_ image: UIImage) async throws -> UIImage {
        // print("🔍 VisionOrientationService: Starting orientation detection")

        guard let cgImage = image.cgImage else {
            // print("❌ VisionOrientationService: Failed to get CGImage")
            return image
        }

        // Create Vision request for body pose detection
        let request = VNDetectHumanBodyPoseRequest()
        request.revision = VNDetectHumanBodyPoseRequestRevision1

        // Create image request handler
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        do {
            // Perform the body pose detection
            try handler.perform([request])

            guard let observation = request.results?.first else {
                // print("⚠️ VisionOrientationService: No body pose detected, trying face detection")
                return try await correctUsingFaceDetection(image)
            }

            // Analyze the body pose to determine orientation
            let rotation = try analyzeBodyPose(observation, imageSize: image.size)
            // print("📐 VisionOrientationService: Detected rotation needed: \(rotation) degrees")

            // Apply rotation if needed
            if abs(rotation) > 5 { // Only rotate if angle is significant
                return rotateImage(image, byDegrees: rotation)
            }

            return image
        } catch {
            // print("❌ VisionOrientationService: Body pose detection failed: \(error)")
            // Fallback to face detection
            return try await correctUsingFaceDetection(image)
        }
    }

    /// Fallback method using face detection when body pose detection fails
    private func correctUsingFaceDetection(_ image: UIImage) async throws -> UIImage {
        // print("🔍 VisionOrientationService: Using face detection for orientation")

        guard let cgImage = image.cgImage else {
            return image
        }

        // Create face detection request
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])

        do {
            try handler.perform([request])

            guard let faces = request.results, !faces.isEmpty else {
                // print("⚠️ VisionOrientationService: No faces detected, returning original image")
                return image
            }

            // Analyze face positions to determine orientation
            let rotation = analyzeFaceOrientation(faces, imageSize: image.size)
            // print("📐 VisionOrientationService: Face detection suggests rotation: \(rotation) degrees")

            if abs(rotation) > 5 {
                return rotateImage(image, byDegrees: rotation)
            }

            return image
        } catch {
            // print("❌ VisionOrientationService: Face detection failed: \(error)")
            return image
        }
    }

    /// Analyzes body pose observation to determine required rotation
    private func analyzeBodyPose(_ observation: VNHumanBodyPoseObservation, imageSize: CGSize) throws -> CGFloat {
        // Get key body points
        let bodyPoints = try observation.recognizedPoints(.all)

        // Get head and hip points for orientation detection
        guard let nose = bodyPoints[.nose],
              let leftHip = bodyPoints[.leftHip],
              let rightHip = bodyPoints[.rightHip],
              nose.confidence > 0.5,
              leftHip.confidence > 0.5,
              rightHip.confidence > 0.5 else {
            throw VisionError.insufficientConfidence
        }

        // Calculate the midpoint of hips
        let hipMidpoint = CGPoint(
            x: (leftHip.location.x + rightHip.location.x) / 2,
            y: (leftHip.location.y + rightHip.location.y) / 2
        )

        // Calculate vector from hips to head
        let bodyVector = CGVector(
            dx: nose.location.x - hipMidpoint.x,
            dy: nose.location.y - hipMidpoint.y
        )

        // Calculate angle from vertical (person should be upright)
        let angle = atan2(bodyVector.dx, -bodyVector.dy) * 180 / .pi

        // Determine rotation needed (round to nearest 90 degrees for major corrections)
        if abs(angle) < 45 {
            return 0 // Already upright
        } else if angle > 45 && angle < 135 {
            return -90 // Rotate left
        } else if angle < -45 && angle > -135 {
            return 90 // Rotate right
        } else {
            return 180 // Upside down
        }
    }

    /// Analyzes face rectangles to determine orientation
    private func analyzeFaceOrientation(_ faces: [VNFaceObservation], imageSize: CGSize) -> CGFloat {
        // If we have multiple faces, use the largest one
        guard let largestFace = faces.max(by: {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }) else {
            return 0
        }

        let faceRect = largestFace.boundingBox

        // Check aspect ratio to guess orientation
        let aspectRatio = faceRect.width / faceRect.height

        // Face is typically taller than wide when upright
        if aspectRatio > 1.2 {
            // Face is wider than tall, likely sideways
            // Check which side by position
            if faceRect.midX < 0.5 {
                return 90 // Rotate right
            } else {
                return -90 // Rotate left
            }
        } else if aspectRatio < 0.8,
                  faceRect.midY < 0.3 {
            // Face is at top and narrow, likely upside down
            return 180
        }

        return 0 // Seems upright
    }

    /// Rotates image by specified degrees
    private func rotateImage(_ image: UIImage, byDegrees degrees: CGFloat) -> UIImage {
        let radians = degrees * .pi / 180

        // Calculate new size after rotation
        var newSize = image.size
        if abs(degrees) == 90 || abs(degrees) == 270 {
            newSize = CGSize(width: image.size.height, height: image.size.width)
        }

        // Create context and rotate
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return image }

        // Move to center, rotate, then draw
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        context.rotate(by: radians)

        let drawRect = CGRect(
            x: -image.size.width / 2,
            y: -image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )

        image.draw(in: drawRect)

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    enum VisionError: LocalizedError {
        case insufficientConfidence
        case noBodyDetected
        case noFaceDetected

        var errorDescription: String? {
            switch self {
            case .insufficientConfidence:
                return "Could not confidently detect body orientation"
            case .noBodyDetected:
                return "No human body detected in image"
            case .noFaceDetected:
                return "No face detected in image"
            }
        }
    }
}
