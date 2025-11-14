//
// BackgroundPhotoUploadService.swift
// LogYourBody
//
import SwiftUI
import PhotosUI
import Combine

@MainActor
class BackgroundPhotoUploadService: ObservableObject {
    static let shared = BackgroundPhotoUploadService()
    
    @Published var uploadQueue: [PhotoUploadTask] = []
    @Published var completedUploads: [PhotoUploadTask] = []
    @Published var failedUploads: [PhotoUploadTask] = []
    @Published var totalProgress: Double = 0.0
    @Published var isUploading = false
    @Published var currentUploadingPhoto: PhotoUploadTask?
    
    private let authManager = AuthManager.shared
    private let supabaseManager = SupabaseManager.shared
    private let coreDataManager = CoreDataManager.shared
    private let photoMetadataService = PhotoMetadataService.shared
    private var uploadCancellables = Set<AnyCancellable>()
    private var uploadTask: Task<Void, Never>?
    
    struct PhotoUploadTask: Identifiable {
        let id = UUID()
        let photoItem: PhotosPickerItem
        let date: Date
        var status: UploadStatus = .pending
        var metricsId: String?
        var photoUrl: String?
        var error: String?
        var progress: Double = 0.0
    }
    
    enum UploadStatus {
        case pending
        case extracting
        case uploading
        case processing
        case completed
        case failed
    }
    
    private init() {}
    
    // MARK: - Public Methods
    
    func queuePhotosForUpload(_ photos: [PhotosPickerItem]) async {
        // print("📸 BackgroundUploadService: Queuing \(photos.count) photos for upload")
        
        // Extract dates and create tasks
        for photo in photos {
            // Load the photo data first
            if let data = try? await photo.loadTransferable(type: Data.self),
               let date = photoMetadataService.extractDate(from: data) {
                let task = PhotoUploadTask(photoItem: photo, date: date)
                uploadQueue.append(task)
            } else {
                // If no date metadata, use current date
                let task = PhotoUploadTask(photoItem: photo, date: Date())
                uploadQueue.append(task)
            }
        }
        
        // Start processing if not already running
        if !isUploading {
            startProcessingQueue()
        }
    }
    
    func startProcessingQueue() {
        guard !isUploading && !uploadQueue.isEmpty else { return }
        
        isUploading = true
        
        uploadTask = Task {
            while !uploadQueue.isEmpty {
                if Task.isCancelled { break }
                
                // Get next task
                var task = uploadQueue.removeFirst()
                currentUploadingPhoto = task
                
                do {
                    // Update status
                    task.status = .extracting
                    updateTaskInQueue(task)
                    
                    // Extract image data
                    guard let imageData = try await task.photoItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: imageData) else {
                        throw PhotoUploadManager.PhotoError.imageConversionFailed
                    }
                    
                    // Create body metrics entry
                    task.status = .uploading
                    updateTaskInQueue(task)
                    
                    let metrics = await createBodyMetrics(for: task.date)
                    task.metricsId = metrics.id
                    
                    // Upload photo using PhotoUploadManager
                    let photoUrl = try await PhotoUploadManager.shared.uploadProgressPhoto(
                        for: metrics,
                        image: image
                    )
                    
                    task.status = .completed
                    task.photoUrl = photoUrl
                    task.progress = 1.0
                    
                    completedUploads.append(task)
                } catch {
                    // print("❌ BackgroundUploadService: Failed to upload photo: \(error)")
                    task.status = .failed
                    task.error = error.localizedDescription
                    failedUploads.append(task)
                }
                
                updateOverallProgress()
            }
            
            currentUploadingPhoto = nil
            isUploading = false
            // print("✅ BackgroundUploadService: Queue processing complete")
        }
    }
    
    func cancelAllUploads() {
        uploadTask?.cancel()
        uploadQueue.removeAll()
        isUploading = false
        currentUploadingPhoto = nil
        totalProgress = 0.0
    }
    
    // MARK: - Private Methods
    
    private func createBodyMetrics(for date: Date) async -> BodyMetrics {
        let userId = authManager.currentUser?.id ?? ""
        
        // Check if metrics already exist for this date
        let existingMetrics = await coreDataManager.fetchBodyMetrics(for: userId)
            .first { metrics in
                guard let metricsDate = metrics.date else { return false }
                return Calendar.current.isDate(metricsDate, inSameDayAs: date)
            }
        
        if let existing = existingMetrics {
            // Convert CachedBodyMetrics to BodyMetrics
            return BodyMetrics(
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
                createdAt: existing.createdAt ?? Date(),
                updatedAt: existing.updatedAt ?? Date()
            )
        }
        
        // Create new metrics
        let metricsId = UUID().uuidString
        let newMetrics = BodyMetrics(
            id: metricsId,
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
            dataSource: "Manual",
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Save to CoreData
        coreDataManager.saveBodyMetrics(newMetrics, userId: userId, markAsSynced: false)
        
        return newMetrics
    }
    
    private func updateTaskInQueue(_ task: PhotoUploadTask) {
        // Update current task if it matches
        if currentUploadingPhoto?.id == task.id {
            currentUploadingPhoto = task
        }
    }
    
    private func updateOverallProgress() {
        let total = Double(uploadQueue.count + completedUploads.count + failedUploads.count)
        let completed = Double(completedUploads.count)
        
        if total > 0 {
            totalProgress = completed / total
        } else {
            totalProgress = 0
        }
    }
    
    // MARK: - Status Helpers
    
    var pendingCount: Int {
        uploadQueue.count
    }
    
    var completedCount: Int {
        completedUploads.count
    }
    
    var failedCount: Int {
        failedUploads.count
    }
    
    var totalCount: Int {
        pendingCount + completedCount + failedCount
    }
    
    var uploadSummary: String {
        if isUploading {
            return "Uploading \(completedCount + 1) of \(totalCount) photos..."
        } else if completedCount > 0 {
            return "\(completedCount) photos uploaded successfully"
        } else {
            return "Ready to upload photos"
        }
    }
    
    func reset() {
        uploadQueue.removeAll()
        completedUploads.removeAll()
        failedUploads.removeAll()
        totalProgress = 0.0
        isUploading = false
        currentUploadingPhoto = nil
    }
}
