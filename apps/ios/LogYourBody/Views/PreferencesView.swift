//
// PreferencesView.swift
// LogYourBody
//
import SwiftUI
import Foundation
import UIKit

struct PreferencesView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.openURL) var openURL
    @Environment(\.theme) var theme
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
    @State var isShowingProfileSettings = false
    @State var isUploadingPhoto = false
    @State var avatarUploadProgress = 0.0
    @State var profileImageURL: String?
    @State var profilePhotoErrorMessage = ""
    @State var showingProfilePhotoError = false
    @State var isCompactHeaderVisible = false
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
        ZStack(alignment: .top) {
            ScrollView {
                settingsLauncher
                .padding(.horizontal, theme.spacing.screenPadding)
                .padding(.vertical, theme.spacing.md)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: geo.frame(in: .named("settingsScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "settingsScroll")
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                let shouldShowCompactHeader = value < -60
                guard shouldShowCompactHeader != isCompactHeaderVisible else { return }
                isCompactHeaderVisible = shouldShowCompactHeader
            }

            compactHeader
        }
        .settingsBackground()
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $isShowingProfileSettings) {
            NavigationStack {
                ProfileSettingsViewV2()
                    .environmentObject(authManager)
            }
        }
        .sheet(item: $activeGoalEditor) { goal in
            goalEditorSheet(for: goal)
        }
        .onAppear {
            migrateLegacyWeightGoalIfNeeded()
            checkBiometricAvailability()
            dailyReminderDate = notificationManager.dailyWeighInReminderDate
            Task {
                await notificationManager.refreshAuthorizationStatus()
            }
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
