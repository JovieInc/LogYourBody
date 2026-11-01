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

struct BodyPhotoRenderResult {
    var image: UIImage
    var mask: PersonMaskGrid?
    var fellBackToIntact: Bool
    var retry: PersonMaskRetry?
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

    /// Full plate when a confident person mask is available. Low-confidence masks
    /// return the intact photograph. Unavailable segmentation keeps the treated
    /// background so the stage geometry does not depend on Vision.
    static func render(
        _ image: UIImage,
        remover: BackgroundRemovalService = .shared
    ) async -> UIImage {
        await renderResult(image, remover: remover).image
    }

    static func renderResult(
        _ image: UIImage,
        protectedPoints: [CGPoint] = [],
        cropSupported: Bool = true,
        remover: BackgroundRemovalService = .shared
    ) async -> BodyPhotoRenderResult {
        guard let cgImage = image.cgImage, cropSupported else {
            return BodyPhotoRenderResult(
                image: image,
                mask: nil,
                fellBackToIntact: true,
                retry: PersonMaskRetry(reason: .unsupportedCrop, canRetry: true)
            )
        }
        guard let grid = try? await remover.personMaskGrid(for: cgImage, quality: segmentationQuality) else {
            let plate = flatten(treatedBackground(of: cgImage), like: image, cgImage: cgImage)
            return BodyPhotoRenderResult(image: plate, mask: nil, fellBackToIntact: false, retry: nil)
        }
        let pixelScaleX = CGFloat(cgImage.width) / max(image.size.width, 1)
        let pixelScaleY = CGFloat(cgImage.height) / max(image.size.height, 1)
        let pixelPoints = protectedPoints.map { CGPoint(x: $0.x * pixelScaleX, y: $0.y * pixelScaleY) }
        switch PersonMaskPolicy.decide(
            mask: grid,
            imageWidth: cgImage.width,
            imageHeight: cgImage.height,
            protectedPoints: pixelPoints,
            cropSupported: true
        ) {
        case .intact(let retry):
            return BodyPhotoRenderResult(image: image, mask: grid, fellBackToIntact: true, retry: retry)
        case .refined(let refined):
            let presented = present(
                cgImage: cgImage, mask: refined, scale: image.scale, orientation: image.imageOrientation
            )
            return BodyPhotoRenderResult(
                image: presented ?? image,
                mask: refined,
                fellBackToIntact: presented == nil,
                retry: presented == nil ? PersonMaskRetry(reason: .lowConfidence, canRetry: true) : nil
            )
        }
    }

    /// Subject pixels stay exact. The dimmed background, including its frame stroke, shows around them.
    static func present(
        cgImage: CGImage,
        mask: PersonMaskGrid,
        scale: CGFloat,
        orientation: UIImage.Orientation
    ) -> UIImage? {
        let like = UIImage(cgImage: cgImage, scale: scale, orientation: orientation)
        let treated = flatten(treatedBackground(of: cgImage), like: like, cgImage: cgImage)
        guard let treatedImage = treated.cgImage,
              let sourcePixels = BodyPhotoBitmap.read(cgImage),
              let backgroundPixels = BodyPhotoBitmap.read(treatedImage),
              let output = BodyPhotoCompositor.composite(
                source: sourcePixels,
                background: backgroundPixels,
                width: cgImage.width,
                height: cgImage.height,
                mask: mask
              ) else { return nil }
        return BodyPhotoBitmap.image(
            pixels: output,
            width: cgImage.width,
            height: cgImage.height,
            scale: scale,
            orientation: orientation
        )
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

/// Plates cost a Vision pass plus CoreImage, so each photo URL is rendered once
/// and shared by every surface that shows it.
@MainActor
final class SubjectPlateStore: ObservableObject {
    static let shared = SubjectPlateStore()

    private let cache = NSCache<NSString, UIImage>()
    private let preparedImages = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]
    private var prepareTasks: [String: Task<UIImage?, Never>] = [:]
    private var focusAnchors: [String: CGPoint] = [:]
    private var focusTasks: [String: Task<CGPoint?, Never>] = [:]
    private var landmarkFrames: [String: BodyLandmarkFrame] = [:]
    private var imageSizes: [String: CGSize] = [:]
    private var retries: [String: PersonMaskRetry] = [:]
    private var derivativeCache = BodyPhotoDerivativeCache()

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

    func landmarkFrame(for urlString: String) -> BodyLandmarkFrame? {
        landmarkFrames[urlString]
    }

    func maskRetry(for urlString: String) -> PersonMaskRetry? {
        retries[urlString]
    }

    /// Cache read for a scrub frame. Segmentation and decoding stay on `prepare`.
    func invalidatePrepared(urlString: String, target: CGSize) {
        let key = BodyPhotoDerivativeCache.key(url: urlString, size: target)
        preparedImages.removeObject(forKey: NSString(string: key))
        cache.removeObject(forKey: NSString(string: urlString))
        retries.removeValue(forKey: urlString)
    }

    func scrubImage(for urlString: String, target: CGSize) -> UIImage? {
        _ = BodyPhotoScrubSession.display(prepared: derivativeCache.prepared(url: urlString, size: target))
        guard BodyPhotoScrubSession.work.segmentations == 0,
              BodyPhotoScrubSession.work.fullResolutionDecodes == 0 else { return nil }
        let key = BodyPhotoDerivativeCache.key(url: urlString, size: target)
        return preparedImages.object(forKey: NSString(string: key))
    }

    func alignment(from sourceURL: String, to targetURL: String, stage: CGSize) -> BodyPhotoAlignment? {
        guard let source = landmarkFrames[sourceURL],
              let target = landmarkFrames[targetURL],
              let targetSize = imageSizes[targetURL] else { return nil }
        return BodyPhotoAlignmentPolicy.stageRegistration(
            source: source,
            target: target,
            targetImageSize: targetSize,
            stage: stage,
            anchor: focusAnchors[targetURL]
        )
    }

    func focus(for urlString: String, image: UIImage) async -> CGPoint? {
        if let cached = focusAnchors[urlString], landmarkFrames[urlString] != nil { return cached }
        if let running = focusTasks[urlString] { return await running.value }

        let task = Task<CGPoint?, Never> {
            let reading = await TorsoFocusService.reading(in: image)
            self.landmarkFrames[urlString] = reading.frame
            self.imageSizes[urlString] = image.size
            return reading.center
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
            let frame = self.landmarkFrames[urlString]
            let points = frame?.protectedPoints() ?? []
            let supported = frame.map { BodyPhotoAlignmentPolicy.cropSupported($0.metadata) } ?? true
            let result = await SubjectPlateRenderer.renderResult(
                image,
                protectedPoints: points,
                cropSupported: supported
            )
            self.record(result.retry, for: urlString)
            return result.image
        }
        tasks[urlString] = task
        let plate = await task.value
        tasks.removeValue(forKey: urlString)
        if let plate {
            cache.setObject(plate, forKey: NSString(string: urlString))
        }
        return plate
    }

    /// Target-sized matte and mask. Pass the adjacent-date window in `retaining`
    /// so a later date does not keep every earlier derivative.
    func prepare(
        urlString: String,
        image: UIImage,
        target: CGSize,
        retaining urls: [String]? = nil
    ) async -> UIImage? {
        let key = BodyPhotoDerivativeCache.key(url: urlString, size: target)
        if let cached = preparedImages.object(forKey: NSString(string: key)) {
            if let existing = derivativeCache.prepared(url: urlString, size: target) {
                derivativeCache.store(existing, retaining: urls)
            }
            return cached
        }
        if let running = prepareTasks[key] { return await running.value }

        let task = Task<UIImage?, Never> {
            await self.prepareNow(urlString: urlString, image: image, target: target, retaining: urls)
        }
        prepareTasks[key] = task
        let prepared = await task.value
        prepareTasks.removeValue(forKey: key)
        return prepared
    }

    private func prepareNow(
        urlString: String,
        image: UIImage,
        target: CGSize,
        retaining urls: [String]?
    ) async -> UIImage? {
        let anchor = await focus(for: urlString, image: image)
        let registration = AspectFillCropper.registration(imageSize: image.size, in: target, anchor: anchor)
        let framed: UIImage
        let points: [CGPoint]
        if let registration {
            framed = AspectFillCropper.crop(image, to: target, registration: registration)
            points = landmarkFrames[urlString]?.mapped(by: registration).protectedPoints() ?? []
        } else {
            framed = image
            points = []
        }
        let metadata = landmarkFrames[urlString]?.metadata
        let supported = metadata.map(BodyPhotoAlignmentPolicy.cropSupported) ?? true
        let result = await SubjectPlateRenderer.renderResult(
            framed,
            protectedPoints: points,
            cropSupported: supported
        )
        let key = BodyPhotoDerivativeCache.key(url: urlString, size: target)
        preparedImages.setObject(result.image, forKey: NSString(string: key))
        record(result.retry, for: urlString)
        rememberDerivative(
            for: urlString,
            target: target,
            mask: result.mask,
            retry: result.retry,
            fellBack: result.fellBackToIntact,
            retaining: urls
        )
        return result.image
    }

    private func rememberDerivative(
        for urlString: String,
        target: CGSize,
        mask: PersonMaskGrid?,
        retry: PersonMaskRetry?,
        fellBack: Bool = false,
        retaining urls: [String]?
    ) {
        let metadata = landmarkFrames[urlString]?.metadata ?? BodyPhotoCaptureMetadata(
            viewpoint: .unknown,
            mirrored: false,
            crop: CGRect(x: 0, y: 0, width: 1, height: 1),
            sourceSize: imageSizes[urlString] ?? target
        )
        derivativeCache.store(
            BodyPhotoDerivative(
                url: urlString,
                targetSize: target,
                mask: mask,
                fellBackToIntact: fellBack || retry != nil,
                retry: retry,
                metadata: metadata
            ),
            retaining: urls
        )
    }

    private func record(_ retry: PersonMaskRetry?, for urlString: String) {
        if let retry, retry.canRetry {
            retries[urlString] = retry
        } else {
            retries.removeValue(forKey: urlString)
        }
    }
}

/// Aspect-fill crop in points. Drawing through UIKit also normalises EXIF
/// orientation, so the crop rect is computed in display space.
enum AspectFillCropper {
    static func fillRect(imageSize: CGSize, in target: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, target.width > 0, target.height > 0 else {
            return CGRect(origin: .zero, size: target)
        }
        let scale = max(target.width / imageSize.width, target.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (target.width - drawn.width) / 2,
            y: (target.height - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        )
    }

    /// Aspect-fill where `anchor` — a normalized point in image space (x
    /// right, y down, 0–1) — lands on `anchorTarget`, a fraction of the
    /// target. Offsets clamp so the drawn image still covers the frame;
    /// a nil anchor is the centered fill above.
    static func fillRect(imageSize: CGSize, in target: CGSize, anchor: CGPoint?, anchorTarget: CGPoint) -> CGRect {
        let rect = fillRect(imageSize: imageSize, in: target)
        guard let anchor else { return rect }

        let offsetX = min(0, max(target.width - rect.width, anchorTarget.x * target.width - anchor.x * rect.width))
        let offsetY = min(0, max(target.height - rect.height, anchorTarget.y * target.height - anchor.y * rect.height))
        return CGRect(x: offsetX, y: offsetY, width: rect.width, height: rect.height)
    }

    static func crop(_ image: UIImage, to target: CGSize) -> UIImage {
        crop(image, to: target, anchor: nil)
    }

    static func crop(_ image: UIImage, to target: CGSize, anchor: CGPoint?) -> UIImage {
        guard target.width > 0, target.height > 0 else { return image }
        guard let registration = registration(imageSize: image.size, in: target, anchor: anchor) else {
            return UIGraphicsImageRenderer(size: target).image { _ in }
        }
        return crop(image, to: target, registration: registration)
    }

    static func registration(imageSize: CGSize, in target: CGSize, anchor: CGPoint?) -> BodyPhotoRegistration? {
        guard imageSize.width > 0, imageSize.height > 0, target.width > 0, target.height > 0 else { return nil }
        let rect = fillRect(
            imageSize: imageSize,
            in: target,
            anchor: anchor,
            anchorTarget: TorsoFocusService.stageAnchor
        )
        return BodyPhotoRegistration(
            translation: rect.origin,
            scale: max(target.width / imageSize.width, target.height / imageSize.height)
        )
    }

    /// Render a disposable stage image; never rewrite the source with its crop.
    static func crop(_ image: UIImage, to target: CGSize, registration: BodyPhotoRegistration) -> UIImage {
        guard target.width > 0, target.height > 0 else { return image }
        return UIGraphicsImageRenderer(size: target).image { context in
            context.cgContext.concatenate(registration.transform)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
