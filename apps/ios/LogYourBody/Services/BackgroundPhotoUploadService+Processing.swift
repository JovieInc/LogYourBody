//
// BackgroundPhotoUploadService+Processing.swift
// LogYourBody
//
import SwiftUI
import PhotosUI

extension BackgroundPhotoUploadService {
    /// Process and upload photos with advanced Vision framework processing
    func processAndUploadPhotos(_ items: [PhotosPickerItem]) async {
        // Convert PhotosPickerItems to UIImages
        var imagesToProcess: [(image: UIImage, id: String)] = []

        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let imageId = UUID().uuidString
                imagesToProcess.append((image, imageId))
            }
        }

        // Processing notification handled elsewhere

        // Process images in background
        await ImageProcessingService.shared.processBatchImages(imagesToProcess)

        // Upload processed images
        for (_, (_, imageId)) in imagesToProcess.enumerated() {
            // Get processed image from service
            if let task = ImageProcessingService.shared.processingTasks.first(where: { $0.imageId == imageId }),
               let processedImage = task.resultImage {
                // Upload using existing photo upload manager
                do {
                    // Create body metrics for today
                    let userId = AuthManager.shared.currentUser?.id ?? ""
                    let date = Date()

                    // Check if metrics already exist for today
                    let existingMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
                        .first { metrics in
                            guard let metricsDate = metrics.date else { return false }
                            return Calendar.current.isDate(metricsDate, inSameDayAs: date)
                        }

                    let metrics: BodyMetrics
                    if let existing = existingMetrics {
                        // Convert existing metrics
                        metrics = BodyMetrics(
                            id: existing.id ?? UUID().uuidString,
                            userId: existing.userId ?? userId,
                            date: existing.date ?? date,
                            weight: existing.weight > 0 ? existing.weight : nil,
                            weightUnit: existing.weightUnit,
                            bodyFatPercentage: existing.bodyFatPercentage > 0 ? existing.bodyFatPercentage : nil,
                            bodyFatMethod: existing.bodyFatMethod,
                            muscleMass: existing.muscleMass > 0 ? existing.muscleMass : nil,
                            boneMass: existing.boneMass > 0 ? existing.boneMass : nil,
                            notes: existing.notes,
                            photoUrl: existing.photoUrl,
                            dataSource: existing.dataSource,
                            createdAt: existing.createdAt ?? date,
                            updatedAt: existing.updatedAt ?? date
                        )
                    } else {
                        // Create new metrics
                        metrics = BodyMetrics(
                            id: UUID().uuidString,
                            userId: userId,
                            date: date,
                            weight: nil,
                            weightUnit: "lbs",
                            bodyFatPercentage: nil,
                            bodyFatMethod: nil,
                            muscleMass: nil,
                            boneMass: nil,
                            notes: nil,
                            photoUrl: nil,
                            dataSource: "manual",
                            createdAt: date,
                            updatedAt: date
                        )
                    }

                    // Upload photo with metrics
                    _ = try await PhotoUploadManager.shared.uploadProgressPhoto(
                        for: metrics,
                        image: processedImage
                    )

                    // Progress tracking handled by the processing service
                } catch {
                    // print("Failed to upload processed image: \(error)")
                }
            }
        }

        // Completion notification handled by the processing service
    }
}
