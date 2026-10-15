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

    private let accountOwner: AuthManager
    private let metricsStore: CoreDataManager
    private let loadFullImage: (PHAsset) async -> UIImage?
    private let uploadPhoto: (BodyMetrics, UIImage) async throws -> String
    private let syncImportedPhoto: @MainActor () -> Void
    private let shouldDeleteAfterImport: () -> Bool
    private let deleteAssets: ([String]) async throws -> Void

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

    private convenience init() {
        self.init(
            accountOwner: .shared,
            metricsStore: .shared,
            loadFullImage: { asset in
                await PhotoLibraryScanner.shared.loadFullImage(for: asset)
            },
            uploadPhoto: { metrics, image in
                try await PhotoUploadManager.shared.uploadProgressPhoto(for: metrics, image: image)
            },
            syncImportedPhoto: { RealtimeSyncManager.shared.syncIfNeeded() },
            shouldDeleteAfterImport: {
                UserDefaults.standard.bool(forKey: Constants.deletePhotosAfterImportKey)
            },
            deleteAssets: { localIdentifiers in
                try await LivePhotoLibraryAdapter.shared.deleteAssets(localIdentifiers: localIdentifiers)
            }
        )
    }

    init(
        accountOwner: AuthManager,
        metricsStore: CoreDataManager,
        loadFullImage: @escaping (PHAsset) async -> UIImage?,
        uploadPhoto: @escaping (BodyMetrics, UIImage) async throws -> String,
        syncImportedPhoto: @escaping @MainActor () -> Void,
        shouldDeleteAfterImport: @escaping () -> Bool = { false },
        deleteAssets: @escaping ([String]) async throws -> Void = { _ in }
    ) {
        self.accountOwner = accountOwner
        self.metricsStore = metricsStore
        self.loadFullImage = loadFullImage
        self.uploadPhoto = uploadPhoto
        self.syncImportedPhoto = syncImportedPhoto
        self.shouldDeleteAfterImport = shouldDeleteAfterImport
        self.deleteAssets = deleteAssets
    }

    // MARK: - Public Methods

    func importPhotos(_ photos: [ScannedPhoto]) async {
        // One admission owns the entire selection, including later photos.
        let ownership = await MainActor.run { () -> AuthManager.ProfileSessionOwnership? in
            guard !isImporting, let ownership = accountOwner.captureAccountSession() else { return nil }
            isImporting = true
            importTasks = photos.map { ImportTask(photo: $0) }
            overallProgress = 0
            return ownership
        }
        guard let ownership else { return }

        let task = Task {
            for index in photos.indices {
                guard !Task.isCancelled,
                      await MainActor.run(body: { accountOwner.ownsAccountSession(ownership) }) else { break }

                await importPhoto(at: index, ownership: ownership)

                // Update overall progress
                let stillOwned = await MainActor.run {
                    guard accountOwner.ownsAccountSession(ownership) else { return false }
                    overallProgress = Double(completedCount) / Double(totalCount)
                    return true
                }
                guard stillOwned else { break }

                // Small delay between imports to prevent overwhelming the system
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }

            await deleteImportedAssetsIfNeeded(ownership: ownership)

            await MainActor.run {
                isImporting = false
                currentPhotoName = nil

                // Completion notification will be shown by the caller
            }
        }
        currentTask = task
        await task.value
    }

    /// Deletes camera-roll originals for tasks whose upload completed, batched
    /// into a single request so Photos shows one system confirmation and the
    /// assets land in Recently Deleted. Runs only when the opt-in setting is on.
    @MainActor
    private func deleteImportedAssetsIfNeeded(ownership: AuthManager.ProfileSessionOwnership) async {
        guard shouldDeleteAfterImport(), !Task.isCancelled,
              accountOwner.ownsAccountSession(ownership) else { return }

        let localIdentifiers = importTasks.compactMap { task -> String? in
            guard task.status == .completed else { return nil }
            let identifier = task.photo.asset.localIdentifier
            return identifier.isEmpty ? nil : identifier
        }
        guard !localIdentifiers.isEmpty else { return }

        do {
            try await deleteAssets(localIdentifiers)
        } catch {
            let context = ErrorContext(
                feature: "photos",
                operation: "deleteImportedPhotos",
                screen: "BulkPhotoImport",
                userId: nil
            )
            ErrorReporter.shared.captureNonFatal(error, context: context)
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

    /// Safely mutate the import task at `index`, guarding against `importTasks`
    /// being resized while an async import is still in flight. `importPhoto(at:)`
    /// bounds-checks only once before its first `await`; if the user cancels and
    /// starts a smaller import, the array shrinks and the still-suspended task
    /// would otherwise index out of range. No-ops when the index is stale.
    @MainActor
    func updateImportTask(at index: Int, _ mutate: (inout ImportTask) -> Void) {
        guard importTasks.indices.contains(index) else { return }
        mutate(&importTasks[index])
    }

    private func importPhoto(at index: Int, ownership: AuthManager.ProfileSessionOwnership) async {
        guard index < importTasks.count else { return }

        let photo = importTasks[index].photo
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium

        await MainActor.run {
            updateImportTask(at: index) { $0.status = .extracting }
            currentPhotoName = dateFormatter.string(from: photo.date)
        }

        do {
            guard await MainActor.run(body: { accountOwner.ownsAccountSession(ownership) }) else {
                throw ImportError.noUser
            }

            // Step 1: Extract full resolution image for the session that admitted the batch.
            guard let fullImage = await loadFullImage(photo.asset) else {
                throw ImportError.failedToLoadImage
            }
            guard await MainActor.run(body: { accountOwner.ownsAccountSession(ownership) }) else {
                throw ImportError.noUser
            }

            await MainActor.run {
                updateImportTask(at: index) {
                    $0.status = .processing
                    $0.progress = 0.3
                }
            }

            // Step 2: Create body metrics entry for the photo date
            let userId = ownership.subject

            // Check if we already have an entry for this date
            let existingMetrics = await metricsStore.fetchBodyMetrics(
                for: userId,
                localDate: BodyMetricLocalDate.key(for: photo.date)
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
                    localDate: BodyMetricLocalDate.key(for: photo.date),
                    weight: nil, // Will be estimated later
                    weightUnit: "kg",
                    bodyFatPercentage: nil, // Will be estimated later
                    bodyFatMethod: nil,
                    muscleMass: nil,
                    boneMass: nil,
                    notes: "Imported from photo library",
                    photoUrl: nil, // Will be set after upload
                    dataSource: BodyMetricSource.photo.rawValue,
                    createdAt: Date(),
                    updatedAt: Date()
                )

                let admission: CoreDataManager.WriteAdmission = { [accountOwner] in
                    guard accountOwner.ownsAccountSession(ownership) else {
                        throw ImportError.noUser
                    }
                }
                try await metricsStore.saveBodyMetricsAndWait(
                    bodyMetrics,
                    userId: userId,
                    markAsSynced: false,
                    writeAdmission: admission
                )
            }

            guard await MainActor.run(body: { accountOwner.ownsAccountSession(ownership) }) else {
                throw ImportError.noUser
            }

            await MainActor.run {
                updateImportTask(at: index) {
                    $0.status = .uploading
                    $0.progress = 0.6
                }
            }

            // Step 3: Upload photo
            _ = try await uploadPhoto(bodyMetrics, fullImage)
            guard await MainActor.run(body: { accountOwner.ownsAccountSession(ownership) }) else {
                return
            }

            await MainActor.run {
                updateImportTask(at: index) {
                    $0.status = .completed
                    $0.progress = 1.0
                }
            }

            // Trigger sync only for the session that still owns the import.
            await MainActor.run {
                guard accountOwner.ownsAccountSession(ownership) else { return }
                syncImportedPhoto()
            }
        } catch {
            // print("❌ Failed to import photo: \(error)")
            await MainActor.run {
                updateImportTask(at: index) {
                    $0.status = .failed
                    $0.error = error
                }
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
