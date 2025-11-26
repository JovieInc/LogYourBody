//
// BulkImportManager.swift
// LogYourBody
//
import SwiftUI
import Photos

// MARK: - Import Task

struct ImportTask: Identifiable {
    let id = UUID()
    let photo: ScannedPhoto
    var status: ImportStatus = .pending
    var progress: Double = 0
    var error: Error?

    enum ImportStatus {
        case pending
        case extracting
        case processing
        case uploading
        case completed
        case failed
    }
}

// MARK: - Bulk Import Manager

class BulkImportManager: ObservableObject {
    static let shared = BulkImportManager()

    @Published var importTasks: [ImportTask] = []
    @Published var isImporting = false
    @Published var currentPhotoName: String?
    @Published var overallProgress: Double = 0

    var totalCount: Int {
        importTasks.count
    }

    var completedCount: Int {
        importTasks.filter { $0.status == .completed || $0.status == .failed }.count
    }

    var failedCount: Int {
        importTasks.filter { $0.status == .failed }.count
    }

    private var importQueue = DispatchQueue(label: "com.logyourbody.import", qos: .background)
    private var currentTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public Methods

    func importPhotos(_ photos: [ScannedPhoto]) async {
        // Prevent multiple concurrent imports
        guard await MainActor.run(body: { !isImporting }) else {
            // print("⚠️ Import already in progress")
            return
        }

        await MainActor.run {
            isImporting = true
            importTasks = photos.map { ImportTask(photo: $0) }
            overallProgress = 0
        }

        currentTask = Task {
            for index in photos.indices {
                if Task.isCancelled { break }

                await importPhoto(at: index)

                // Update overall progress
                await MainActor.run {
                    overallProgress = Double(completedCount) / Double(totalCount)
                }

                // Small delay between imports to prevent overwhelming the system
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }

            await MainActor.run {
                isImporting = false
                currentPhotoName = nil

                // Completion notification will be shown by the caller
            }
        }
    }

    func cancelImport() {
        currentTask?.cancel()
        currentTask = nil
        Task { @MainActor in
            isImporting = false
            currentPhotoName = nil
        }
    }

    // MARK: - Private Methods

    private func importPhoto(at index: Int) async {
        guard index < importTasks.count else { return }

        let photo = importTasks[index].photo
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        await MainActor.run {
            importTasks[index].status = .extracting
            currentPhotoName = dateFormatter.string(from: photo.date)
        }

        do {
            // Step 1: Extract full resolution image
            guard let fullImage = await PhotoLibraryScanner.shared.loadFullImage(for: photo.asset) else {
                throw ImportError.failedToLoadImage
            }

            await MainActor.run {
                importTasks[index].status = .processing
                importTasks[index].progress = 0.3
            }

            // Step 2: Create body metrics entry for the photo date
            guard let userId = await MainActor.run(body: { AuthManager.shared.currentUser?.id }) else {
                throw ImportError.noUser
            }

            // Check if we already have an entry for this date
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: photo.date)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

            let existingMetrics = await CoreDataManager.shared.fetchBodyMetrics(
                for: userId,
                from: startOfDay,
                to: endOfDay
            ).first?.toBodyMetrics()

            let bodyMetrics: BodyMetrics
            if let existing = existingMetrics {
                bodyMetrics = existing
            } else {
                // Create new metrics entry for this date
                bodyMetrics = BodyMetrics(
                    id: UUID().uuidString,
                    userId: userId,
                    date: photo.date,
                    weight: nil, // Will be estimated later
                    weightUnit: "kg",
                    bodyFatPercentage: nil, // Will be estimated later
                    bodyFatMethod: nil,
                    muscleMass: nil,
                    boneMass: nil,
                    notes: "Imported from photo library",
                    photoUrl: nil, // Will be set after upload
                    dataSource: "Photo Import",
                    createdAt: Date(),
                    updatedAt: Date()
                )

                // Save to Core Data
                CoreDataManager.shared.saveBodyMetrics(
                    bodyMetrics,
                    userId: userId,
                    markAsSynced: false
                )
            }

            await MainActor.run {
                importTasks[index].status = .uploading
                importTasks[index].progress = 0.6
            }

            // Step 3: Upload photo
            _ = try await PhotoUploadManager.shared.uploadProgressPhoto(
                for: bodyMetrics,
                image: fullImage
            )

            await MainActor.run {
                importTasks[index].status = .completed
                importTasks[index].progress = 1.0
            }

            // Trigger sync
            await MainActor.run {
                RealtimeSyncManager.shared.syncIfNeeded()
            }
        } catch {
            // print("❌ Failed to import photo: \(error)")
            await MainActor.run {
                importTasks[index].status = .failed
                importTasks[index].error = error
            }
        }
    }
}

// MARK: - Import Errors

enum ImportError: LocalizedError {
    case failedToLoadImage
    case noUser
    case uploadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .failedToLoadImage:
            return "Failed to load image from photo library"
        case .noUser:
            return "No authenticated user found"
        case .uploadFailed(let error):
            return "Upload failed: \(error.localizedDescription)"
        }
    }
}
