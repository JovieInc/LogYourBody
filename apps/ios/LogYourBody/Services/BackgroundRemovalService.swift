//
// BackgroundRemovalService.swift
// LogYourBody
//
import Foundation
import Vision
import CoreImage
import UIKit
class BackgroundRemovalService {
    static let shared = BackgroundRemovalService()
    private init() {}

    enum BackgroundRemovalError: LocalizedError {
        case noPersonFound
        case processingFailed
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .noPersonFound:
                return "No person detected in the image"
            case .processingFailed:
                return "Failed to process the image"
            case .invalidImage:
                return "Invalid image format"
            }
        }
    }

    /// Remove background from image using Vision person segmentation
    func removeBackground(from image: UIImage, quality: Float = 0.85) async throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw BackgroundRemovalError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Create Vision request for person segmentation
            let request = VNGeneratePersonSegmentationRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let result = request.results?.first as? VNPixelBufferObservation else {
                    continuation.resume(throwing: BackgroundRemovalError.noPersonFound)
                    return
                }

                do {
                    let maskedImage = try self.applySegmentationMask(
                        to: cgImage,
                        mask: result.pixelBuffer,
                        quality: quality
                    )
                    continuation.resume(returning: maskedImage)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            // Set quality level (higher = better quality but slower)
            request.qualityLevel = quality > 0.8 ? .accurate : .balanced

            // Process the image
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Apply the segmentation mask to create transparent background
    private func applySegmentationMask(to cgImage: CGImage, mask: CVPixelBuffer, quality: Float) throws -> UIImage {
        let ciImage = CIImage(cgImage: cgImage)
        let maskImage = CIImage(cvPixelBuffer: mask)

        // Scale mask to match image size
        let scaleX = ciImage.extent.width / maskImage.extent.width
        let scaleY = ciImage.extent.height / maskImage.extent.height

        let scaledMask = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Apply Gaussian blur to soften mask edges for more natural cutout
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            throw BackgroundRemovalError.processingFailed
        }
        blurFilter.setValue(scaledMask, forKey: kCIInputImageKey)
        blurFilter.setValue(2.0, forKey: kCIInputRadiusKey)

        guard let blurredMask = blurFilter.outputImage else {
            throw BackgroundRemovalError.processingFailed
        }

        // Create alpha mask by blending the original image with the mask
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw BackgroundRemovalError.processingFailed
        }
        blendFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(blurredMask, forKey: kCIInputMaskImageKey)

        guard let outputImage = blendFilter.outputImage else {
            throw BackgroundRemovalError.processingFailed
        }

        // Render the result
        let context = CIContext()
        guard let finalCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            throw BackgroundRemovalError.processingFailed
        }

        return UIImage(cgImage: finalCGImage)
    }

    /// Prepare image data for upload (convert to PNG to preserve alpha channel)
    func prepareForUpload(
        _ image: UIImage,
        maxSize: CGSize = CGSize(width: 1_200, height: 1_600)
    ) async -> Data? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Resize if needed while maintaining aspect ratio
                let resizedImage: UIImage
                if image.size.width > maxSize.width || image.size.height > maxSize.height {
                    let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height)
                    let newSize = CGSize(
                        width: image.size.width * scale,
                        height: image.size.height * scale
                    )

                    // Use modern UIGraphicsImageRenderer instead of deprecated API
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1.0
                    format.opaque = false // Important for transparency

                    let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
                    resizedImage = renderer.image { _ in
                        image.draw(in: CGRect(origin: .zero, size: newSize))
                    }
                } else {
                    resizedImage = image
                }

                // Convert to PNG to preserve alpha channel
                let data = resizedImage.pngData()
                continuation.resume(returning: data)
            }
        }
    }
}
