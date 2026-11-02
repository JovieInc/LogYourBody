//
// SubjectPlateRenderer.swift
// LogYourBody
//
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Presentation-only similarity transform. A single positive scale preserves
/// body proportions and excludes reflection, shear and independent axis scaling.
/// The source image remains separate from the rendered stage crop.
struct BodyPhotoRegistration: Equatable {
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
