//
// SubjectPlateRenderer.swift
// LogYourBody
//
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// Presentation-only similarity transform. A single positive scale preserves
/// body proportions and excludes reflection, shear and independent axis scaling.
/// The source image remains separate from the rendered stage crop.
struct BodyPhotoRegistration {
    let translation: CGPoint
    let rotation: CGFloat
    let scale: CGFloat

    init?(translation: CGPoint, rotation: CGFloat = 0, scale: CGFloat) {
        guard translation.x.isFinite, translation.y.isFinite,
              rotation.isFinite, scale.isFinite, scale > 0 else { return nil }
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }

    var transform: CGAffineTransform {
        let cosine = cos(rotation) * scale
        let sine = sin(rotation) * scale
        return CGAffineTransform(a: cosine, b: sine, c: -sine, d: cosine, tx: translation.x, ty: translation.y)
    }
}

/// The progress-photo treatment: the person stays sharp while the background is
/// blurred, desaturated and dimmed, so every photo reads the same no matter the
/// room it was taken in. Nothing is ever drawn over the person.
enum SubjectPlateRenderer {
    static let blurDivisor: CGFloat = 24
    static let backgroundSaturation: Float = 0.05
    static let backgroundDim: CGFloat = 0.28
    static let segmentationQuality: Float = 0.85

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Full plate when person segmentation is available; the treated background
    /// alone when it is not (simulator, no person found), so the surface keeps
    /// the same geometry either way.
    static func render(
        _ image: UIImage,
        remover: BackgroundRemovalService = .shared
    ) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let background = treatedBackground(of: cgImage)
        var composite = background

        if let mask = try? await remover.personMask(for: cgImage, quality: segmentationQuality),
           let cutout = try? remover.applySegmentationMask(to: cgImage, mask: mask, quality: segmentationQuality),
           let cutoutCG = cutout.cgImage {
            composite = CIImage(cgImage: cutoutCG).composited(over: background)
        }

        return flatten(composite, like: image, cgImage: cgImage)
    }

    static func treatedBackground(of cgImage: CGImage) -> CIImage {
        let source = CIImage(cgImage: cgImage)
        let extent = source.extent
        let blurred = source
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(extent.width / blurDivisor))
            .cropped(to: extent)

        let controls = CIFilter.colorControls()
        controls.inputImage = blurred
        controls.saturation = backgroundSaturation
        let desaturated = controls.outputImage ?? blurred

        return desaturated.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: backgroundDim, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: backgroundDim, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: backgroundDim, w: 0)
        ])
    }

    static func flatten(_ ciImage: CIImage, like image: UIImage, cgImage: CGImage) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        guard let output = context.createCGImage(ciImage, from: rect) else { return image }
        return UIImage(cgImage: output, scale: image.scale, orientation: image.imageOrientation)
    }
}

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
        guard let cgImage = image.cgImage else { return nil }
        let orientation = cgImagePropertyOrientation(of: image.imageOrientation)

        return await Task.detached(priority: .userInitiated) {
            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            guard (try? handler.perform([request])) != nil,
                  let observation = request.results?.first else {
                return nil
            }
            return torsoCenter(of: observation)
        }.value
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

/// Plates cost a Vision pass plus CoreImage, so each photo URL is rendered once
/// and shared by every surface that shows it.
@MainActor
final class SubjectPlateStore: ObservableObject {
    static let shared = SubjectPlateStore()

    private let cache = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private var focusAnchors: [String: CGPoint] = [:]
    private var focusTasks: [String: Task<CGPoint?, Never>] = [:]

    init(countLimit: Int = 24) {
        cache.countLimit = countLimit
    }

    func cachedPlate(for urlString: String) -> UIImage? {
        cache.object(forKey: NSString(string: urlString))
    }

    /// Torso anchors cost one body-pose pass per photo; cache them next to the
    /// plate so every surface frames the same photo the same way.
    func cachedFocus(for urlString: String) -> CGPoint? {
        focusAnchors[urlString]
    }

    func focus(for urlString: String, image: UIImage) async -> CGPoint? {
        if let cached = focusAnchors[urlString] { return cached }
        if let running = focusTasks[urlString] { return await running.value }

        let task = Task<CGPoint?, Never> {
            await TorsoFocusService.torsoCenter(in: image)
        }
        focusTasks[urlString] = task
        let anchor = await task.value
        focusTasks.removeValue(forKey: urlString)
        if let anchor {
            focusAnchors[urlString] = anchor
        }
        return anchor
    }

    func plate(for urlString: String, image: UIImage) async -> UIImage? {
        if let cached = cachedPlate(for: urlString) { return cached }
        if let running = tasks[urlString] { return await running.value }

        let task = Task<UIImage?, Never> {
            await SubjectPlateRenderer.render(image)
        }
        tasks[urlString] = task
        let plate = await task.value
        tasks.removeValue(forKey: urlString)
        if let plate {
            cache.setObject(plate, forKey: NSString(string: urlString))
        }
        return plate
    }
}
