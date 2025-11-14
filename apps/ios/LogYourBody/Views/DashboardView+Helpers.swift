//
// DashboardView+Helpers.swift
// LogYourBody
//
import Foundation
import SwiftUI
import PhotosUI

extension DashboardView {
    // MARK: - Data Loading

    /// Async version - does NOT block the main thread
    func loadData() async {
        guard let userId = authManager.currentUser?.id else {
            await MainActor.run {
                hasLoadedInitialData = true
            }
            return
        }

        // Load body metrics from CoreData (async - won't block UI)
        let fetchedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)
        let metrics = fetchedMetrics
            .compactMap { $0.toBodyMetrics() }
            .sorted { $0.date ?? Date.distantPast > $1.date ?? Date.distantPast }

        // Load today's daily metrics (async - won't block UI)
        let todayMetrics = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: Date())

        // Update UI on main thread
        await MainActor.run {
            bodyMetrics = metrics
            if let todayMetrics = todayMetrics {
                dailyMetrics = todayMetrics.toDailyMetrics()
            }
            hasLoadedInitialData = true
        }
    }

    /// Legacy synchronous version - blocks the main thread (use async version instead)
    func loadDataSync() {
        guard let userId = authManager.currentUser?.id else {
            hasLoadedInitialData = true
            return
        }

        // Load body metrics from CoreData
        let fetchedMetrics = CoreDataManager.shared.fetchBodyMetricsSync(for: userId)
        bodyMetrics = fetchedMetrics
            .compactMap { $0.toBodyMetrics() }
            .sorted { $0.date ?? Date.distantPast > $1.date ?? Date.distantPast }

        // Load today's daily metrics
        if let todayMetrics = CoreDataManager.shared.fetchDailyMetricsSync(for: userId, date: Date()) {
            dailyMetrics = todayMetrics.toDailyMetrics()
        }

        hasLoadedInitialData = true
    }

    func refreshData() async {
        // Debouncing: Skip refresh if last refresh was within 3 minutes
        if let lastRefresh = lastRefreshDate {
            let timeSinceLastRefresh = Date().timeIntervalSince(lastRefresh)
            if timeSinceLastRefresh < 180 { // 3 minutes in seconds
                // Just reload from cache for quick refresh (async - won't block UI)
                await loadData()

                // Subtle haptic for quick refresh
                await MainActor.run {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                return
            }
        }

        var hasErrors = false

        // Sync from HealthKit if authorized
        if healthKitManager.isAuthorized {
            do {
                // Sync weight and body fat data from HealthKit (last 30 days)
                try await healthKitManager.syncWeightFromHealthKit()

                // Sync today's steps
                await syncStepsFromHealthKit()
            } catch {
                // Log error but continue with sync
                print("HealthKit sync error during refresh: \(error)")
                hasErrors = true
            }
        }

        // Upload local changes to Supabase
        syncManager.syncAll()

        // Download remote changes from Supabase (cross-device sync)
        await syncManager.downloadRemoteChanges()

        // Wait for sync operations to complete
        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

        // Reload from local cache (async - won't block UI)
        await loadData()

        // Update last refresh timestamp and provide haptic feedback
        await MainActor.run {
            lastRefreshDate = Date()

            // Provide haptic feedback based on result
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()

            if hasErrors {
                generator.notificationOccurred(.warning)
            } else {
                generator.notificationOccurred(.success)
            }
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

        // Fetch existing metrics (async - won't block UI)
        if let existingMetrics = await CoreDataManager.shared.fetchDailyMetrics(for: userId, date: today) {
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

        // Fetch metrics (async - won't block UI)
        let fetchedMetrics = await CoreDataManager.shared.fetchBodyMetrics(for: userId)

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
