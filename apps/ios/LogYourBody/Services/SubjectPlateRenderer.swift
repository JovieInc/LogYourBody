//
// SubjectPlateRenderer.swift
// LogYourBody
//
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

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

/// Plates cost a Vision pass plus CoreImage, so each photo URL is rendered once
/// and shared by every surface that shows it.
@MainActor
final class SubjectPlateStore: ObservableObject {
    static let shared = SubjectPlateStore()

    private let cache = NSCache<NSString, UIImage>()
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    init(countLimit: Int = 24) {
        cache.countLimit = countLimit
    }

    func cachedPlate(for urlString: String) -> UIImage? {
        cache.object(forKey: NSString(string: urlString))
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
