//
// PreferencesView.swift
// LogYourBody
//
import SwiftUI
import Foundation
import UIKit

enum PreferencesProfileEditor: String, Identifiable {
    case fullName
    case dateOfBirth
    case height

    var id: String { rawValue }
}

struct PreferencesView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.openURL) var openURL
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @StateObject var subscriptionManager = SubscriptionManager.shared
    @StateObject var notificationManager = NotificationManager.shared
    @AppStorage(Constants.preferredMeasurementSystemKey) var measurementSystem = PreferencesView.defaultMeasurementSystem
    @AppStorage("biometricLockEnabled") var biometricLockEnabled = false
    @AppStorage(Constants.healthKitSyncEnabledKey) var healthKitSyncEnabled = true
    @AppStorage(Constants.deletePhotosAfterImportKey) var deletePhotosAfterImport = false
    @AppStorage("stepGoal") var stepGoal = 10_000
    @AppStorage(Constants.goalWeightKilogramsKey) var customWeightGoalKilograms: Double?
    @AppStorage(Constants.goalWeightKey) var legacyCustomWeightGoal: Double?
    @AppStorage(Constants.goalBodyFatPercentageKey) var customBodyFatGoal: Double?
    @AppStorage(Constants.goalFFMIKey) var customFFMIGoal: Double?

    @State var biometricType: AppBiometryType = .none
    @ObservedObject var healthKitManager = HealthKitManager.shared
    @State var showingRestoreAlert = false
    @State var restoreAlertMessage = ""
    @State var isRestoringPurchases = false
    @State var activeGoalEditor: PreferenceGoalKind?
    @State var activeProfileEditor: PreferencesProfileEditor?
    @State var profileEditorName = ""
    @State var profileEditorDateOfBirth = Date()
    @State var profileEditorHeightCm = 170
    @State var profileEditorUsesMetricHeight = false
    @State var profileEditorHasChanges = false
    @State var profileEditorErrorMessage: String?
    @State var isUploadingPhoto = false
    @State var avatarUploadProgress = 0.0
    @State var profileImageURL: String?
    @State var profilePhotoErrorMessage = ""
    @State var showingProfilePhotoError = false
    @State var showingLogoutConfirmation = false
    @State var showingNotificationSettingsAlert = false
    @State var isTriggeringHealthResync = false
    @State var isHealthSyncSetupInProgress = false
    @State var dailyReminderDate = Date()

    static var defaultMeasurementSystem: String {
        MeasurementSystem.localeDefault.rawValue
    }

    var currentSystem: MeasurementSystem {
        MeasurementSystem.fromStored(rawValue: measurementSystem)
    }

    var body: some View {
        List {
            settingsLauncher
        }
        .listStyle(.insetGrouped)
        .scrollBounceBehavior(.basedOnSize)
        .alert("Restore Purchases", isPresented: $showingRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreAlertMessage)
        }
        .alert("Profile photo couldn’t be updated", isPresented: $showingProfilePhotoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(profilePhotoErrorMessage)
        }
        .alert("Notifications are off", isPresented: $showingNotificationSettingsAlert) {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Allow notifications in iOS Settings to receive your daily weigh-in reminder.")
        }
        .confirmationDialog("Log out of LogYourBody?", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                Task {
                    await authManager.logout()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $activeProfileEditor) { editor in
            profileEditorSheet(for: editor)
                .presentationDetents(editor == .height ? [.large] : [.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $activeGoalEditor) { goal in
            goalEditorSheet(for: goal)
        }
        .alert(
            "Couldn’t save profile field",
            isPresented: Binding(
                get: { profileEditorErrorMessage != nil },
                set: { if !$0 { profileEditorErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                profileEditorErrorMessage = nil
            }
        } message: {
            Text(profileEditorErrorMessage ?? "Check your connection and try again.")
        }
        .onAppear {
            migrateLegacyWeightGoalIfNeeded()
            checkBiometricAvailability()
            dailyReminderDate = notificationManager.dailyWeighInReminderDate
            Task {
                await notificationManager.refreshAuthorizationStatus()
            }
        }
        .worldClassScreen(.settings)
    }

    @ViewBuilder
    private func profileEditorSheet(for editor: PreferencesProfileEditor) -> some View {
        switch editor {
        case .fullName:
            ProfileNameEditorSheet(
                name: $profileEditorName,
                hasChanges: $profileEditorHasChanges,
                onCommit: saveProfileName
            )
        case .dateOfBirth:
            DatePickerSheet(
                date: $profileEditorDateOfBirth,
                hasChanges: $profileEditorHasChanges,
                onCommit: saveProfileDateOfBirth
            )
        case .height:
            ProfileHeightPickerSheet(
                heightCm: $profileEditorHeightCm,
                useMetric: $profileEditorUsesMetricHeight,
                hasChanges: $profileEditorHasChanges,
                onCommit: saveProfileHeight
            )
        }
    }

    func checkBiometricAvailability() {
        biometricType = LocalBiometricAuthenticationAdapter.shared.availableBiometryType()
    }
}

#Preview {
    NavigationStack {
        PreferencesView()
            .environmentObject(AuthManager.shared)
    }
}
