//
// PreferencesView+Helpers.swift
// LogYourBody
//
import PhotosUI
import SwiftUI
import UIKit

extension PreferencesView {
    var userDisplayName: String {
        authManager.currentUser?.profile?.fullName ??
            authManager.currentUser?.name ??
            authManager.currentUser?.email ??
            "User"
    }

    var userEmail: String {
        authManager.currentUser?.email ?? "Not available"
    }

    var memberSinceText: String? {
        guard let date = authManager.memberSinceDate else { return nil }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        return "Member since \(year)"
    }

    var userInitials: String {
        let nameSource = authManager.currentUser?.profile?.fullName ??
            authManager.currentUser?.name ??
            authManager.currentUser?.email ?? ""
        let components = nameSource.split(separator: " ")
        let first = components.first?.first.map(String.init) ?? ""
        let last = components.dropFirst().first?.first.map(String.init) ?? ""
        let combined = first + last
        return combined.isEmpty ? "U" : combined.uppercased()
    }

    var profileAvatarURLString: String? {
        profileImageURL ?? authManager.currentUser?.avatarUrl
    }

    var dateOfBirthDisplay: String {
        guard let dob = authManager.currentUser?.profile?.dateOfBirth else {
            return "Not set"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        var text = formatter.string(from: dob)
        if let age = authManager.currentUser?.profile?.age {
            text += "  (Age \(age))"
        }
        return text
    }

    var heightDisplayText: String {
        guard let height = authManager.currentUser?.profile?.height,
              let unit = authManager.currentUser?.profile?.heightUnit else {
            return "Not set"
        }
        return convertHeightToCurrentSystem(height: height, fromUnit: unit)
    }

    var topSafeArea: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }

    func handleHealthSyncToggle(to newValue: Bool) {
        if newValue {
            Task {
                await configureHealthSyncPipelineIfNeeded()
            }
        }
    }

    func configureHealthSyncPipelineIfNeeded() async {
        let isAlreadyConfiguring = await MainActor.run { isHealthSyncSetupInProgress }
        guard !isAlreadyConfiguring else { return }

        await MainActor.run {
            isHealthSyncSetupInProgress = true
        }

        defer {
            Task { @MainActor in
                isHealthSyncSetupInProgress = false
            }
        }

        if !healthKitManager.isAuthorized {
            let authorized = await healthKitManager.requestAuthorization()
            guard authorized else {
                await MainActor.run {
                    healthKitSyncEnabled = false
                }
                return
            }
        }

        await HealthSyncCoordinator.shared.configureSyncPipelineAfterAuthorizationAndRunInitialWeightSync()
    }

    func convertHeightToCurrentSystem(height: Double, fromUnit: String) -> String {
        let heightCm = height

        if currentSystem == .metric {
            let centimeters = Int(heightCm.rounded())
            return "\(centimeters) cm"
        }

        let totalInches = Int((heightCm / 2.54).rounded())
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet)' \(inches)\""
    }

    func handlePhotoSelection(_ item: PhotosPickerItem) async {
        await MainActor.run {
            isUploadingPhoto = true
            avatarUploadProgress = 0.15
        }

        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    avatarUploadProgress = 0.4
                }

                if let newImageURL = try await authManager.uploadProfilePicture(image) {
                    await MainActor.run {
                        profileImageURL = newImageURL
                        avatarUploadProgress = 1.0
                        isUploadingPhoto = false
                    }
                } else {
                    await MainActor.run {
                        avatarUploadProgress = 0.0
                        isUploadingPhoto = false
                    }
                }
            } else {
                await MainActor.run {
                    avatarUploadProgress = 0.0
                    isUploadingPhoto = false
                }
            }
        } catch {
            await MainActor.run {
                avatarUploadProgress = 0.0
                isUploadingPhoto = false
            }
        }

        await MainActor.run {
            selectedPhotoItem = nil
        }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
