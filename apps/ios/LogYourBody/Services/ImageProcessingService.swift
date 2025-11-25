//
// ImageProcessingService.swift
// LogYourBody
//
import UIKit
import Vision
import CoreImage
import Combine

class ImageProcessingService: ObservableObject {
    static let shared = ImageProcessingService()

    @Published var processingTasks: [ProcessingTask] = []
    @Published var activeProcessingCount: Int = 0

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    struct ProcessingTask: Identifiable {
        let id = UUID()
        let imageId: String
        var status: ProcessingStatus = .pending
        var progress: Double = 0
        var error: Error?
        var resultImage: UIImage?
        var thumbnailImage: UIImage?
    }

    enum ProcessingStatus {
        case pending
        case detecting
        case cropping
        case removingBackground
        case finalizing
        case completed
        case failed
    }

    // MARK: - Public Methods

    func processImage(_ image: UIImage, imageId: String) async throws -> ProcessedImageResult {
        // Create and track task
        let task = ProcessingTask(imageId: imageId, status: .pending)
        await MainActor.run {
            processingTasks.append(task)
            activeProcessingCount += 1
        }

        // Show processing notification
        await showProcessingNotification(for: imageId)

        do {
            let result = try await Task.detached(
                priority: .userInitiated
            ) { [image, taskId = task.id, weak self] () async throws -> ProcessedImageResult in
                guard let self else {
                    throw ProcessingError.processingFailed
                }
                return try await self.performImageProcessing(image, taskId: taskId)
            }.value

            // Update task status
            await updateTaskStatus(task.id, status: .completed, result: result.finalImage)

            return result
        } catch {
            await updateTaskStatus(task.id, status: .failed, error: error)
            throw error
        }
    }

    func processBatchImages(_ images: [(image: UIImage, id: String)]) async {
        // Process images concurrently
        await withTaskGroup(of: Void.self) { group in
            for (image, id) in images {
                group.addTask { [weak self] in
                    do {
                        _ = try await self?.processImage(image, imageId: id)
                    } catch {
                        // print("Failed to process image \(id): \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Private Processing Methods

    private func performImageProcessing(_ image: UIImage, taskId: UUID) async throws -> ProcessedImageResult {
        // Step 0: Apply EXIF-aware orientation first
        let orientationFixedImage = image.fixedOrientation()

        guard let cgImage = orientationFixedImage.cgImage else {
            throw ProcessingError.invalidImage
        }

        // Step 1: Detect human bounding box
        updateTaskProgress(taskId, status: .detecting, progress: 0.2)
        let boundingBox = try detectHumanBoundingBox(in: cgImage)

        // Step 2: Crop to bounding box (person-centered)
        updateTaskProgress(taskId, status: .cropping, progress: 0.4)
        let croppedImage = try cropToHuman(cgImage: cgImage, boundingBox: boundingBox)

        // Step 3: Apply aspect fill to target size (centered on person)
        let targetSize = CGSize(width: 600, height: 800) // Standard portrait size
        let aspectFilledImage = try aspectFillToSize(croppedImage, targetSize: targetSize, centerOnPerson: true)

        // Step 4: Remove background
        updateTaskProgress(taskId, status: .removingBackground, progress: 0.6)
        let backgroundRemovedImage = try await BackgroundRemovalService.shared.removeBackground(from: aspectFilledImage)

        // Step 5: Create thumbnail
        updateTaskProgress(taskId, status: .finalizing, progress: 0.8)
        let thumbnailImage = try createThumbnail(from: backgroundRemovedImage, size: CGSize(width: 150, height: 200))

        updateTaskProgress(taskId, status: .completed, progress: 1.0)

        return ProcessedImageResult(
            originalImage: orientationFixedImage,
            finalImage: backgroundRemovedImage,
            thumbnailImage: thumbnailImage,
            boundingBox: boundingBox
        )
    }

    private func detectHumanBoundingBox(in cgImage: CGImage) throws -> CGRect {
        var detectedBox: CGRect?

        let request = VNDetectHumanRectanglesRequest { request, error in
            if let error = error {
                // print("Human detection error: \(error)")
                return
            }

            guard let observations = request.results as? [VNHumanObservation],
                  let firstHuman = observations.first else {
                return
            }

            detectedBox = firstHuman.boundingBox
        }

        // Try human rectangles first
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        // If no human detected, try body pose
        if detectedBox == nil {
            detectedBox = try detectBodyPoseBoundingBox(in: cgImage)
        }

        // If still no detection, try face rectangles and expand
        if detectedBox == nil {
            detectedBox = try detectFaceAndExpandBoundingBox(in: cgImage)
        }

        guard let box = detectedBox else {
            throw ProcessingError.noHumanDetected
        }

        // Add some padding to the bounding box
        let padding: CGFloat = 0.1
        let paddedBox = CGRect(
            x: max(0, box.origin.x - box.width * padding),
            y: max(0, box.origin.y - box.height * padding),
            width: min(1.0 - box.origin.x + box.width * padding, box.width * (1 + 2 * padding)),
            height: min(1.0 - box.origin.y + box.height * padding, box.height * (1 + 2 * padding))
        )

        return paddedBox
    }

    private func detectBodyPoseBoundingBox(in cgImage: CGImage) throws -> CGRect? {
        var detectedBox: CGRect?

        let request = VNDetectHumanBodyPoseRequest { request, _ in
            guard let observations = request.results as? [VNHumanBodyPoseObservation],
                  let pose = observations.first else {
                return
            }

            // Get all recognized points
            let recognizedPoints = try? pose.recognizedPoints(.all)
            guard let points = recognizedPoints, !points.isEmpty else { return }

            // Find bounding box from all detected points
            var minX: CGFloat = 1.0
            var minY: CGFloat = 1.0
            var maxX: CGFloat = 0.0
            var maxY: CGFloat = 0.0

            for (_, point) in points where point.confidence > 0.3 {
                minX = min(minX, point.location.x)
                minY = min(minY, point.location.y)
                maxX = max(maxX, point.location.x)
                maxY = max(maxY, point.location.y)
            }

            if maxX > minX && maxY > minY {
                detectedBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return detectedBox
    }

    private func detectFaceAndExpandBoundingBox(in cgImage: CGImage) throws -> CGRect? {
        var detectedBox: CGRect?

        let request = VNDetectFaceRectanglesRequest { request, _ in
            guard let observations = request.results as? [VNFaceObservation],
                  let face = observations.first else {
                return
            }

            // Expand face box to approximate full body
            let faceBox = face.boundingBox
            let expandedHeight = faceBox.height * 8 // Approximate body height
            let expandedWidth = faceBox.width * 3 // Approximate body width

            detectedBox = CGRect(
                x: faceBox.midX - expandedWidth / 2,
                y: faceBox.maxY - expandedHeight,
                width: expandedWidth,
                height: expandedHeight
            )
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        return detectedBox
    }

    private func cropToHuman(cgImage: CGImage, boundingBox: CGRect) throws -> UIImage {
        // Convert normalized coordinates to pixel coordinates
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let pixelRect = CGRect(
            x: boundingBox.origin.x * width,
            y: (1 - boundingBox.maxY) * height, // Flip Y coordinate
            width: boundingBox.width * width,
            height: boundingBox.height * height
        )

        guard let croppedCGImage = cgImage.cropping(to: pixelRect) else {
            throw ProcessingError.cropFailed
        }

        return UIImage(cgImage: croppedCGImage)
    }

    private func aspectFillToSize(_ image: UIImage, targetSize: CGSize, centerOnPerson: Bool = true) throws -> UIImage {
        guard let cgImage = image.cgImage else {
            throw ProcessingError.invalidImage
        }

        let sourceWidth = CGFloat(cgImage.width)
        let sourceHeight = CGFloat(cgImage.height)

        // Calculate scale to fill target
        let scale = max(targetSize.width / sourceWidth, targetSize.height / sourceHeight)

        // Calculate scaled size
        let scaledWidth = sourceWidth * scale
        let scaledHeight = sourceHeight * scale

        // Calculate offset to center (person-aware if needed)
        var offsetX = (scaledWidth - targetSize.width) / 2
        var offsetY = (scaledHeight - targetSize.height) / 2

        // If centering on person, detect center of mass and adjust offset
        if centerOnPerson {
            if let personCenter = try? detectPersonCenter(in: cgImage) {
                // Convert normalized person center to scaled coordinates
                let scaledPersonX = personCenter.x * scaledWidth
                let scaledPersonY = personCenter.y * scaledHeight

                // Try to center the crop on the person
                offsetX = max(0, min(scaledWidth - targetSize.width, scaledPersonX - targetSize.width / 2))
                offsetY = max(0, min(scaledHeight - targetSize.height, scaledPersonY - targetSize.height / 2))
            }
        }

        // Create transform
        var transform = CGAffineTransform.identity
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -offsetX / scale, y: -offsetY / scale)

        // Apply transform using Core Image
        let ciImage = CIImage(cgImage: cgImage)

        let transformedImage = ciImage.transformed(by: transform)
        let cropRect = CGRect(origin: .zero, size: targetSize)
        let croppedImage = transformedImage.cropped(to: cropRect)

        guard let outputCGImage = ciContext.createCGImage(croppedImage, from: cropRect) else {
            throw ProcessingError.processingFailed
        }

        return UIImage(cgImage: outputCGImage)
    }

    /// Detect the center point of the person in the image
    private func detectPersonCenter(in cgImage: CGImage) throws -> CGPoint {
        var centerPoint = CGPoint(x: 0.5, y: 0.5) // Default center

        let request = VNDetectHumanRectanglesRequest { request, error in
            guard error == nil,
                  let observations = request.results as? [VNHumanObservation],
                  let firstHuman = observations.first else {
                return
            }

            let box = firstHuman.boundingBox
            // Calculate center of bounding box
            centerPoint = CGPoint(
                x: box.midX,
                y: box.midY
            )
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        return centerPoint
    }

    private func createThumbnail(from image: UIImage, size: CGSize) throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - Task Management

    private func updateTaskProgress(_ taskId: UUID, status: ProcessingStatus, progress: Double) {
        Task { @MainActor in
            if let index = processingTasks.firstIndex(where: { $0.id == taskId }) {
                processingTasks[index].status = status
                processingTasks[index].progress = progress
            }
        }
    }

    private func updateTaskStatus(_ taskId: UUID, status: ProcessingStatus, result: UIImage? = nil, error: Error? = nil) async {
        await MainActor.run {
            if let index = processingTasks.firstIndex(where: { $0.id == taskId }) {
                processingTasks[index].status = status
                processingTasks[index].resultImage = result
                processingTasks[index].error = error

                if status == .completed || status == .failed {
                    activeProcessingCount = max(0, activeProcessingCount - 1)

                    // Remove completed tasks after delay
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        if let idx = processingTasks.firstIndex(where: { $0.id == taskId }) {
                            processingTasks.remove(at: idx)
                        }
                    }
                }
            }
        }
    }

    private func showProcessingNotification(for imageId: String) async {
        // Processing notifications handled by UI layer
    }
}

// MARK: - Supporting Types

struct ProcessedImageResult {
    let originalImage: UIImage
    let finalImage: UIImage
    let thumbnailImage: UIImage
    let boundingBox: CGRect
}

enum ProcessingError: LocalizedError {
    case invalidImage
    case noHumanDetected
    case cropFailed
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Invalid image format"
        case .noHumanDetected:
            return "No person detected in image"
        case .cropFailed:
            return "Failed to crop image"
        case .processingFailed:
            return "Image processing failed"
        }
    }
}
