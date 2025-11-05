//
// DashboardView+Helpers.swift
// LogYourBody
//
import Foundation
import SwiftUI
import PhotosUI

extension DashboardView {
    // MARK: - Data Loading

    func loadData() {
        guard let userId = authManager.currentUser?.id else {
            hasLoadedInitialData = true
            return
        }

        // Load body metrics from CoreData
        let fetchedMetrics = CoreDataManager.shared.fetchBodyMetrics(for: userId)
        bodyMetrics = fetchedMetrics
            .compactMap { $0.toBodyMetrics() }
            .sorted { $0.date ?? Date.distantPast > $1.date ?? Date.distantPast }

        // Load today's daily metrics
        if let todayMetrics = CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date()) {
            dailyMetrics = todayMetrics.toDailyMetrics()
        }

        hasLoadedInitialData = true
    }

    func refreshData() async {
        // Sync steps from HealthKit if authorized
        if healthKitManager.isAuthorized {
            await syncStepsFromHealthKit()
        }

        // Sync with remote
        syncManager.syncAll()

        // Wait a bit for sync
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Reload from cache
        await MainActor.run {
            loadData()
        }
    }

    // MARK: - HealthKit Integration

    func syncStepsFromHealthKit() async {
        do {
            let stepCount = try await healthKitManager.fetchTodayStepCount()
            await updateStepCount(stepCount)
        } catch {
            // Silently fail - HealthKit sync is optional
        }
    }

    func updateStepCount(_ steps: Int) async {
        guard let userId = authManager.currentUser?.id else { return }

        let today = Date()

        if let existingMetrics = CoreDataManager.shared.fetchDailyMetrics(for: userId, date: today) {
            // Update existing metrics
            existingMetrics.steps = Int32(steps)
            existingMetrics.updatedAt = Date()

            let dailyMetrics = existingMetrics.toDailyMetrics()
            await MainActor.run {
                self.dailyMetrics = dailyMetrics
            }
        } else {
            // Create new daily metrics
            let newMetrics = DailyMetrics(
                id: UUID().uuidString,
                userId: userId,
                date: today,
                steps: steps,
                notes: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            CoreDataManager.shared.saveDailyMetrics(newMetrics, userId: userId)

            await MainActor.run {
                self.dailyMetrics = newMetrics
            }
        }

        await MainActor.run {
            // Trigger sync to upload to remote
            syncManager.syncIfNeeded()
        }
    }

    // MARK: - Body Metrics

    func loadBodyMetrics() async {
        guard let userId = authManager.currentUser?.id else { return }

        let fetchedMetrics = CoreDataManager.shared.fetchBodyMetrics(for: userId)

        await MainActor.run {
            bodyMetrics = fetchedMetrics
                .compactMap { $0.toBodyMetrics() }
                .sorted { $0.date ?? Date.distantPast > $1.date ?? Date.distantPast }
        }
    }

    // MARK: - Photo Management

    func handlePhotoCapture(_ image: UIImage) async {
        guard let currentMetric = currentMetric else {
            return
        }

        guard let userId = authManager.currentUser?.id else {
            return
        }

        await MainActor.run {
            isUploadingPhoto = true
        }

        do {
            // Note: uploadProgressPhoto already updates CoreData with the photo URL
            let photoUrl = try await PhotoUploadManager.shared.uploadProgressPhoto(
                for: currentMetric,
                image: image
            )

            // Manually update the bodyMetrics array with the new photoUrl
            await MainActor.run {
                if let index = bodyMetrics.firstIndex(where: { $0.id == currentMetric.id }) {
                    let updatedMetric = bodyMetrics[index]

                    // Create a completely new array to trigger SwiftUI update
                    var newMetrics = bodyMetrics
                    newMetrics[index] = BodyMetrics(
                        id: updatedMetric.id,
                        userId: updatedMetric.userId,
                        date: updatedMetric.date,
                        weight: updatedMetric.weight,
                        weightUnit: updatedMetric.weightUnit,
                        bodyFatPercentage: updatedMetric.bodyFatPercentage,
                        bodyFatMethod: updatedMetric.bodyFatMethod,
                        muscleMass: updatedMetric.muscleMass,
                        boneMass: updatedMetric.boneMass,
                        notes: updatedMetric.notes,
                        photoUrl: photoUrl, // Set the new photo URL
                        dataSource: updatedMetric.dataSource,
                        createdAt: updatedMetric.createdAt,
                        updatedAt: Date()
                    )

                    // Replace entire array to trigger SwiftUI update
                    bodyMetrics = newMetrics
                }
                isUploadingPhoto = false
            }
        } catch {
            await MainActor.run {
                isUploadingPhoto = false
            }
        }
    }

    func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        await handlePhotoCapture(image)
    }
}
