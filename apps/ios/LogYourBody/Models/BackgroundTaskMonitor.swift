//
// BackgroundTaskMonitor.swift
// LogYourBody
//
import SwiftUI
import Combine

// MARK: - Background Task Monitor

/// Centralized service that monitors all background tasks and provides unified state
@MainActor
class BackgroundTaskMonitor: ObservableObject {
    static let shared = BackgroundTaskMonitor()

    // MARK: - Published Properties

    /// All currently active background tasks
    @Published private(set) var activeTasks: [BackgroundTaskInfo] = []

    /// Whether any background task is currently running
    @Published private(set) var isAnyTaskActive: Bool = false

    /// The primary task to display (highest priority)
    @Published private(set) var primaryTask: BackgroundTaskInfo?

    /// Count of additional tasks beyond the primary
    @Published private(set) var additionalTaskCount: Int = 0

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()

    // Service references
    private let photoLibraryScanner = PhotoLibraryScanner.shared
    private let bulkImportManager = BulkImportManager.shared
    private let backgroundUploadService = BackgroundPhotoUploadService.shared
    private let imageProcessingService = ImageProcessingService.shared

    // MARK: - Initialization

    private init() {
        setupObservers()
    }

    // MARK: - Setup

    private func setupObservers() {
        // Observe PhotoLibraryScanner
        photoLibraryScanner.$isScanning
            .combineLatest(photoLibraryScanner.$scanProgress)
            .sink { [weak self] isScanning, progress in
                self?.updateScanningTask(isScanning: isScanning, progress: progress)
            }
            .store(in: &cancellables)

        // Observe BulkImportManager
        bulkImportManager.$isImporting
            .combineLatest(
                bulkImportManager.$overallProgress,
                bulkImportManager.$importTasks,
                bulkImportManager.$currentPhotoName
            )
            .sink { [weak self] isImporting, progress, tasks, photoName in
                guard let self = self else { return }
                let completed = tasks.filter { $0.status == .completed || $0.status == .failed }.count
                let total = tasks.count
                self.updateImportingTask(
                    isImporting: isImporting,
                    progress: progress,
                    completed: completed,
                    total: total,
                    photoName: photoName
                )
            }
            .store(in: &cancellables)

        // Observe BackgroundPhotoUploadService
        backgroundUploadService.$isUploading
            .combineLatest(
                backgroundUploadService.$totalProgress,
                backgroundUploadService.$currentUploadingPhoto,
                backgroundUploadService.$uploadQueue
            )
            .sink { [weak self] isUploading, progress, currentPhoto, queue in
                self?.updateUploadingTask(
                    isUploading: isUploading,
                    progress: progress,
                    currentPhoto: currentPhoto,
                    queueCount: queue.count
                )
            }
            .store(in: &cancellables)

        // Observe ImageProcessingService
        imageProcessingService.$activeProcessingCount
            .combineLatest(imageProcessingService.$processingTasks)
            .sink { [weak self] activeCount, tasks in
                self?.updateProcessingTask(activeCount: activeCount, tasks: tasks)
            }
            .store(in: &cancellables)
    }

    // MARK: - Task Update Methods

    private func updateScanningTask(isScanning: Bool, progress: Double) {
        removeTask(ofType: .scanning)

        if isScanning {
            let task = BackgroundTaskInfo(
                type: .scanning,
                title: "Scanning photo library",
                subtitle: "Looking for progress photos",
                progress: progress,
                canCancel: true
            )
            addTask(task)
        }
    }

    private func updateImportingTask(
        isImporting: Bool,
        progress: Double,
        completed: Int,
        total: Int,
        photoName: String?
    ) {
        removeTask(ofType: .importing)

        if isImporting && total > 0 {
            let subtitle = photoName ?? "Processing photos"
            let task = BackgroundTaskInfo(
                type: .importing,
                title: "Importing photos",
                subtitle: subtitle,
                progress: progress,
                itemCount: (current: completed, total: total),
                canCancel: true
            )
            addTask(task)
        }
    }

    private func updateUploadingTask(
        isUploading: Bool,
        progress: Double,
        currentPhoto: BackgroundPhotoUploadService.PhotoUploadTask?,
        queueCount: Int
    ) {
        removeTask(ofType: .uploading)

        if isUploading, let photo = currentPhoto {
            let fileName = extractFileName(from: photo.photoUrl)
            let task = BackgroundTaskInfo(
                type: .uploading,
                title: "Uploading photo",
                subtitle: fileName,
                progress: progress,
                itemCount: queueCount > 1 ? (current: 1, total: queueCount) : nil,
                canCancel: true
            )
            addTask(task)
        }
    }

    private func updateProcessingTask(activeCount: Int, tasks: [ImageProcessingService.ProcessingTask]) {
        removeTask(ofType: .processing)

        if activeCount > 0 {
            let title = activeCount == 1 ? "Processing photo" : "Processing \(activeCount) photos"
            let task = BackgroundTaskInfo(
                type: .processing,
                title: title,
                subtitle: "Optimizing images",
                canCancel: false  // Processing usually can't be safely canceled
            )
            addTask(task)
        }
    }

    // MARK: - Task Management

    private func addTask(_ task: BackgroundTaskInfo) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeTasks.append(task)
            self.updateComputedProperties()
        }
    }

    private func removeTask(ofType type: BackgroundTaskType) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeTasks.removeAll { $0.type == type }
            self.updateComputedProperties()
        }
    }

    private func updateComputedProperties() {
        isAnyTaskActive = !activeTasks.isEmpty

        // Get highest priority task
        primaryTask = activeTasks.max { $0.type.priority < $1.type.priority }

        additionalTaskCount = max(0, activeTasks.count - 1)
    }

    // MARK: - Public Actions

    /// Cancel a specific task
    func cancelTask(_ task: BackgroundTaskInfo) {
        guard task.canCancel else { return }

        switch task.type {
        case .scanning:
            photoLibraryScanner.cancelScan()
        case .importing:
            bulkImportManager.cancelImport()
        case .uploading:
            backgroundUploadService.cancelAllUploads()
        case .processing:
            break  // Processing can't be canceled
        }
    }

    /// Cancel all active tasks
    func cancelAllTasks() {
        photoLibraryScanner.cancelScan()
        bulkImportManager.cancelImport()
        backgroundUploadService.cancelAllUploads()
    }

    // MARK: - Helper Methods

    private func extractFileName(from url: String?) -> String {
        guard let url = url,
              let fileName = URL(string: url)?.lastPathComponent else {
            return "Photo"
        }
        return fileName
    }
}
