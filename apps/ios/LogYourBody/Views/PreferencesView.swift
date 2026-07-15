//
// PreferencesView.swift
// LogYourBody
//
import SwiftUI
import Foundation

struct PreferencesView: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.openURL) var openURL
    @Environment(\.theme) var theme
    @StateObject var subscriptionManager = SubscriptionManager.shared
    @StateObject var notificationManager = NotificationManager.shared
    @AppStorage(Constants.preferredMeasurementSystemKey) var measurementSystem = PreferencesView.defaultMeasurementSystem
    @AppStorage("biometricLockEnabled") var biometricLockEnabled = false
    @AppStorage("healthKitSyncEnabled") var healthKitSyncEnabled = true
    @AppStorage(Constants.deletePhotosAfterImportKey) var deletePhotosAfterImport = false
    @AppStorage("stepGoal") var stepGoal = 10_000
    @AppStorage(Constants.goalWeightKey) var customWeightGoal: Double?
    @AppStorage(Constants.goalBodyFatPercentageKey) var customBodyFatGoal: Double?
    @AppStorage(Constants.goalFFMIKey) var customFFMIGoal: Double?

    @State var biometricType: AppBiometryType = .none
    @ObservedObject var healthKitManager = HealthKitManager.shared
    @State var showingRestoreAlert = false
    @State var restoreAlertMessage = ""
    @State var activeGoalEditor: PreferenceGoalKind?
    @State var isShowingProfileSettings = false
    @State var isUploadingPhoto = false
    @State var avatarUploadProgress = 0.0
    @State var profileImageURL: String?
    @State var scrollOffset: CGFloat = 0
    @State var showingLogoutConfirmation = false
    @State var isTriggeringHealthResync = false
    @State var isHealthSyncSetupInProgress = false
    @State var dailyReminderDate = Date()
    @State var cachedUserGender = ""
    @State var cachedIsFemale = false
    @State var cachedLegacyBodyFatReference = Constants.BodyComposition.BodyFat.maleReferenceMidpoint
    @State var cachedLegacyFFMIReference = Constants.BodyComposition.FFMI.maleReferenceMidpoint
    @State var featureGateRefreshToken = UUID()

    static var defaultMeasurementSystem: String {
        MeasurementSystem.imperial.rawValue
    }

    var currentSystem: MeasurementSystem {
        MeasurementSystem.fromStored(rawValue: measurementSystem)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: theme.spacing.sectionSpacing) {
                    heroHeader
                    accountSection
                    profileSection
                    trackingGoalsSection
                    remindersSection
                    integrationsSection
                    securitySection
                    subscriptionSection
                    photosSection
                    advancedSection
                    dangerSection
                }
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
                scrollOffset = value
            }

            compactHeader
        }
        .settingsBackground()
        .alert("Restore Purchases", isPresented: $showingRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreAlertMessage)
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
            checkBiometricAvailability()
            updateCachedValues()
            dailyReminderDate = notificationManager.dailyWeighInReminderDate
            Task {
                await notificationManager.refreshAuthorizationStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .featureGatesDidChange)) { _ in
            featureGateRefreshToken = UUID()
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
