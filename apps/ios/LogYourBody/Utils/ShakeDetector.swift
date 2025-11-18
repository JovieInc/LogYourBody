//
// ShakeDetector.swift
// LogYourBody
//
import SwiftUI
import UIKit

// MARK: - Shake Detection

extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name(rawValue: "deviceDidShakeNotification")
}

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
        }
    }
}

// MARK: - View Modifier

struct ShakeDetector: ViewModifier {
    let onShake: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
                onShake()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(ShakeDetector(onShake: action))
    }
}

// MARK: - Debug Reset Manager

class DebugResetManager {
    static let shared = DebugResetManager()

    private init() {}

    @MainActor
    func performCompleteReset() async {
        // print("🔴 DEBUG: Performing complete app reset...")

        // Show alert first
        guard await showResetConfirmation() else { return }

        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()

        // 1. Clear all UserDefaults
        clearUserDefaults()

        // 2. Clear Core Data
        clearCoreData()

        // 3. Clear Keychain
        clearKeychain()

        // 4. Clear image cache
        clearImageCache()

        // 5. Sign out from Clerk
        await signOutFromClerk()

        // 6. Clear derived data cache
        clearDerivedDataCache()

        // print("✅ DEBUG: Complete reset finished")

        // Success message removed - app will restart

        // Force app restart by crashing (only in DEBUG)
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            fatalError("DEBUG: Intentional crash to restart app after reset")
        }
        #endif
    }

    @MainActor
    private func showResetConfirmation() async -> Bool {
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Debug Reset",
                message: "This will logout and clear ALL local data. Continue?",
                preferredStyle: .alert
            )

            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: false)
            })

            alert.addAction(UIAlertAction(title: "Reset Everything", style: .destructive) { _ in
                continuation.resume(returning: true)
            })

            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                rootViewController.present(alert, animated: true)
            } else {
                continuation.resume(returning: false)
            }
        }
    }

    private func clearUserDefaults() {
        // print("🗑️ Clearing UserDefaults...")
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }

        // Also clear specific keys
        let keysToRemove = [
            Constants.hasCompletedOnboardingKey,
            Constants.preferredMeasurementSystemKey,
            "healthKitSyncEnabled",
            "biometricLockEnabled",
            "appleSignInName",
            "HasSyncedHistoricalSteps",
            "lastSyncDate",
            "hasSeenWhatsNew"
        ]

        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key)
        }

        UserDefaults.standard.synchronize()
    }

    private func clearCoreData() {
        // print("🗑️ Clearing Core Data...")
        CoreDataManager.shared.deleteAllData()
    }

    private func clearKeychain() {
        // print("🗑️ Clearing Keychain...")
        // Clear Clerk session data
        // This will be handled by the Clerk SDK when we sign out
    }

    private func clearImageCache() {
        // print("🗑️ Clearing image cache...")
        // Clear URLCache
        URLCache.shared.removeAllCachedResponses()

        // Clear temp directory
        let tempDirectory = FileManager.default.temporaryDirectory
        do {
            let tempContents = try FileManager.default.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: nil
            )
            for file in tempContents {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            // print("❌ Failed to clear temp directory: \(error)")
        }
    }

    private func signOutFromClerk() async {
        // print("🗑️ Signing out from Clerk...")
        await AuthManager.shared.logout()
    }

    private func clearDerivedDataCache() {
        // print("🗑️ Clearing derived data cache...")
        // Clear any app-specific caches
        if let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            do {
                let cacheContents = try FileManager.default.contentsOfDirectory(
                    at: cacheDirectory,
                    includingPropertiesForKeys: nil
                )
                for file in cacheContents {
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                // print("❌ Failed to clear cache directory: \(error)")
            }
        }
    }
}

// MARK: - Debug Overlay View

struct DebugResetOverlay: View {
    @State private var showingDebugMenu = false

    var body: some View {
        EmptyView()
            .onShake {
                showingDebugMenu = true
            }
            .alert("Debug Menu", isPresented: $showingDebugMenu) {
                Button("Reset Everything", role: .destructive) {
                    Task {
                        await DebugResetManager.shared.performCompleteReset()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will logout and clear all local data.")
            }
    }
}

// MARK: - Extension for Easy Integration

extension View {
    func debugResetEnabled() -> some View {
        #if DEBUG
        return self.overlay(DebugResetOverlay())
        #else
        return self
        #endif
    }
}
