//
// PreferencesView.swift
// LogYourBody
//
import SwiftUI
import Foundation
import LocalAuthentication
import PhotosUI
import UIKit

// MARK: - Measurement System Enum (Global)
enum MeasurementSystem: String, Codable, CaseIterable {
    case imperial = "Imperial"
    case metric = "Metric"

    var weightUnit: String {
        switch self {
        case .imperial: return "lbs"
        case .metric: return "kg"
        }
    }

    var heightUnit: String {
        switch self {
        case .imperial: return "ft"
        case .metric: return "cm"
        }
    }

    var heightDisplay: String {
        switch self {
        case .imperial: return "feet & inches"
        case .metric: return "centimeters"
        }
    }
}

struct PreferencesView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = true
    @AppStorage(Constants.deletePhotosAfterImportKey) private var deletePhotosAfterImport = false
    @State private var biometricType: LABiometryType = .none
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @State private var showingRestoreAlert = false
    @State private var restoreAlertMessage = ""

    // Goals - Optional values, nil means use gender-based default
    @AppStorage(Constants.goalWeightKey) private var customWeightGoal: Double?
    @AppStorage(Constants.goalBodyFatPercentageKey) private var customBodyFatGoal: Double?
    @AppStorage(Constants.goalFFMIKey) private var customFFMIGoal: Double?

    // Local state for editing goals
    @State private var editingWeightGoal: String = ""
    @State private var editingBodyFatGoal: String = ""
    @State private var editingFFMIGoal: String = ""

    // Local state for editing profile fields
    @State private var isEditingName = false
    @State private var isEditingBirthday = false
    @State private var isEditingHeight = false
    @State private var isSavingProfile = false

    // Photo picker state
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var profileImageURL: String?

    @State private var scrollOffset: CGFloat = 0
    @State private var showingLogoutConfirmation = false
    @State private var isQuickExporting = false
    @State private var isTriggeringHealthResync = false
    @State private var exportAlertTitle = ""
    @State private var exportAlertMessage = ""
    @State private var showingExportStatusAlert = false

    // Cached computed properties for performance
    @State private var cachedUserGender: String = ""
    @State private var cachedIsFemale: Bool = false
    @State private var cachedDefaultBodyFatGoal: Double = Constants.BodyComposition.BodyFat.maleIdealValue
    @State private var cachedDefaultFFMIGoal: Double = Constants.BodyComposition.FFMI.maleIdealValue

    private let context = LAContext()

    // Default to imperial as requested
    static var defaultMeasurementSystem: String {
        return MeasurementSystem.imperial.rawValue
    }

    var currentSystem: MeasurementSystem {
        MeasurementSystem(rawValue: measurementSystem) ?? .imperial
    }

    private func checkBiometricAvailability() {
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            biometricType = context.biometryType
        } else {
            biometricType = .none
        }
    }

    // MARK: - Goal Helpers

    private var userGender: String {
        cachedUserGender
    }

    private var isFemale: Bool {
        cachedIsFemale
    }

    private var defaultBodyFatGoal: Double {
        cachedDefaultBodyFatGoal
    }

    private var defaultFFMIGoal: Double {
        cachedDefaultFFMIGoal
    }

    private var currentBodyFatGoal: Double {
        customBodyFatGoal ?? defaultBodyFatGoal
    }

    private var currentFFMIGoal: Double {
        customFFMIGoal ?? defaultFFMIGoal
    }

    // Update cached values when user profile changes
    private func updateCachedValues() {
        cachedUserGender = authManager.currentUser?.profile?.gender?.lowercased() ?? ""
        cachedIsFemale = cachedUserGender.contains("female") || cachedUserGender.contains("woman")
        cachedDefaultBodyFatGoal = cachedIsFemale ? Constants.BodyComposition.BodyFat.femaleIdealValue :
            Constants.BodyComposition.BodyFat.maleIdealValue
        cachedDefaultFFMIGoal = cachedIsFemale ? Constants.BodyComposition.FFMI.femaleIdealValue :
            Constants.BodyComposition.FFMI.maleIdealValue
    }

    private func resetToDefaults() {
        customWeightGoal = nil
        customBodyFatGoal = nil
        customFFMIGoal = nil
    }

    private func showTextInputAlert(
        title: String,
        message: String,
        currentValue: String,
        keyboardType: UIKeyboardType,
        completion: @escaping (String) -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = currentValue
            textField.keyboardType = keyboardType
            textField.placeholder = "Enter value"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Set", style: .default) { _ in
            if let text = alert.textFields?.first?.text, !text.isEmpty {
                completion(text)
            }
        })

        // Present alert
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(alert, animated: true)
        }
    }

    // Removed showToast helper - use ToastManager.shared.show directly

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: SettingsDesign.sectionSpacing) {
                    heroHeader
                    accountSection
                    profileSection
                    trackingGoalsSection
                    integrationsSection
                    securitySection
                    subscriptionSection
                    photosSection
                    advancedSection
                    dangerSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("settingsScroll")).minY
                            )
                    }
                )
            }
            .coordinateSpace(name: "settingsScroll")
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
        .alert(exportAlertTitle, isPresented: $showingExportStatusAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportAlertMessage)
        }
        .confirmationDialog("Log out of LogYourBody?", isPresented: $showingLogoutConfirmation, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) {
                Task {
                    await authManager.logout()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            if let newItem {
                Task {
                    await handlePhotoSelection(newItem)
                }
            }
        }
        .onAppear {
            checkBiometricAvailability()
            updateCachedValues() // Cache computed properties for performance
        }
    }

    // MARK: - Sections

    private var heroHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                heroAvatar

                VStack(alignment: .leading, spacing: 4) {
                    Text(userDisplayName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.appText)

                    Text(userEmail)
                        .font(.subheadline)
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                statusBadge

                if let planName = subscriptionPlanDisplay {
                    Text(planName)
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                if revenueCatManager.isSubscribed, let renewal = subscriptionRenewalText {
                    Text(renewal)
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }
            }
        }
        .padding()
        .settingsCardStyle()
    }

    private var accountSection: some View {
        SettingsSection(header: "Account") {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "envelope.fill",
                    title: "Email",
                    value: userEmail,
                    showChevron: false,
                    tintColor: .appText
                )

                DSDivider().insetted(16)

                Button {
                    showingPhotoPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.appPrimary)
                            .frame(width: 30)

                        Text("Change profile photo")
                            .font(SettingsDesign.titleFont)
                            .foregroundColor(.appText)

                        Spacer()

                        if isUploadingPhoto {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                    }
                    .padding(.horizontal, SettingsDesign.horizontalPadding)
                    .padding(.vertical, SettingsDesign.verticalPadding)
                }
                .disabled(isUploadingPhoto)

                DSDivider().insetted(16)

                SettingsButtonRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Log out",
                    role: .destructive
                ) {
                    HapticManager.shared.notification(type: .warning)
                    showingLogoutConfirmation = true
                }
            }
        }
    }

    private var subscriptionSection: some View {
        SettingsSection(header: "Subscription") {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: revenueCatManager.isSubscribed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                    title: revenueCatManager.isSubscribed ? "Active" : "Inactive",
                    subtitle: subscriptionPlanDisplay,
                    showChevron: false,
                    tintColor: revenueCatManager.isSubscribed ? .appPrimary : .orange
                )

                if let renewal = subscriptionRenewalText {
                    DSDivider().insetted(16)

                    SettingsRow(
                        icon: "calendar",
                        title: revenueCatManager.isInTrialPeriod ? "Trial ends" : "Renews on",
                        value: renewal,
                        showChevron: false,
                        tintColor: .appText
                    )
                }

                DSDivider().insetted(16)

                Button {
                    HapticManager.shared.selection()
                    if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    SettingsRow(
                        icon: "arrow.up.right.square",
                        title: "Manage subscription",
                        subtitle: "Opens App Store",
                        showChevron: false,
                        tintColor: .appText
                    )
                }
            }
        }
    }

    private var profileSection: some View {
        SettingsSection(header: "Profile") {
            VStack(spacing: 0) {
                profileRow(
                    icon: "person.fill",
                    title: "Full name",
                    value: authManager.currentUser?.profile?.fullName ?? authManager.currentUser?.name ?? "Not set"
                ) {
                    let currentName = authManager.currentUser?.profile?.fullName ?? authManager.currentUser?.name ?? ""
                    showTextInputAlert(
                        title: "Full name",
                        message: "Enter your full name",
                        currentValue: currentName,
                        keyboardType: .default
                    ) { newValue in
                        Task {
                            isSavingProfile = true
                            await authManager.updateProfile(["name": newValue])
                            isSavingProfile = false
                        }
                    }
                }

                DSDivider().insetted(16)

                profileRow(
                    icon: "calendar",
                    title: "Date of birth",
                    value: dateOfBirthDisplay
                ) {
                    isEditingBirthday = true
                }

                DSDivider().insetted(16)

                profileRow(
                    icon: "ruler",
                    title: "Height",
                    value: heightDisplayText
                ) {
                    isEditingHeight = true
                }
            }
        }
    }

    private var trackingGoalsSection: some View {
        SettingsSection(
            header: "Tracking & goals",
            footer: "Set custom targets or keep LogYourBody defaults."
        ) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Measurement system")
                        .font(SettingsDesign.titleFont)
                        .foregroundColor(.appText)

                    Picker("Measurement System", selection: $measurementSystem) {
                        Text("Imperial").tag(MeasurementSystem.imperial.rawValue)
                        Text("Metric").tag(MeasurementSystem.metric.rawValue)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, SettingsDesign.horizontalPadding)
                .padding(.vertical, SettingsDesign.verticalPadding)

                DSDivider().insetted(16)

                SettingsRow(
                    icon: "scalemass",
                    title: "Units",
                    subtitle: "Weight in \(currentSystem.weightUnit) • Height in \(currentSystem.heightDisplay)",
                    showChevron: false,
                    tintColor: .appText
                )

                DSDivider().insetted(16)

                goalRow(
                    icon: "target",
                    title: "Weight goal",
                    value: customWeightGoal.map { "\(String(format: "%.1f", $0)) \(currentSystem.weightUnit)" } ?? "Not set"
                ) {
                    let currentValue = customWeightGoal.map { String(format: "%.1f", $0) } ?? ""
                    showTextInputAlert(
                        title: "Weight goal",
                        message: "Enter your target weight in \(currentSystem.weightUnit)",
                        currentValue: currentValue,
                        keyboardType: .decimalPad
                    ) { newValue in
                        if let value = Double(newValue), value > 0 {
                            customWeightGoal = value
                        }
                    }
                } resetAction: {
                    customWeightGoal = nil
                }

                DSDivider().insetted(16)

                goalRow(
                    icon: "percent",
                    title: "Body fat goal",
                    value: String(format: "%.1f%%", currentBodyFatGoal)
                        + (customBodyFatGoal == nil ? " (default)" : "")
                ) {
                    let currentValue = customBodyFatGoal.map { String(format: "%.1f", $0) } ?? String(format: "%.1f", defaultBodyFatGoal)
                    showTextInputAlert(
                        title: "Body fat goal",
                        message: "Enter a body fat percentage (0-40%)",
                        currentValue: currentValue,
                        keyboardType: .decimalPad
                    ) { newValue in
                        if let value = Double(newValue), value >= 0, value <= 40 {
                            customBodyFatGoal = value
                        }
                    }
                } resetAction: {
                    customBodyFatGoal = nil
                }

                DSDivider().insetted(16)

                goalRow(
                    icon: "figure.arms.open",
                    title: "FFMI goal",
                    value: String(format: "%.1f", currentFFMIGoal)
                        + (customFFMIGoal == nil ? " (default)" : "")
                ) {
                    let currentValue = customFFMIGoal.map { String(format: "%.1f", $0) } ?? String(format: "%.1f", defaultFFMIGoal)
                    showTextInputAlert(
                        title: "FFMI goal",
                        message: "Enter a Fat-Free Mass Index (10-30)",
                        currentValue: currentValue,
                        keyboardType: .decimalPad
                    ) { newValue in
                        if let value = Double(newValue), value >= 10, value <= 30 {
                            customFFMIGoal = value
                        }
                    }
                } resetAction: {
                    customFFMIGoal = nil
                }

                DSDivider().insetted(16)

                Button {
                    HapticManager.shared.selection()
                    resetToDefaults()
                } label: {
                    Text("Reset goals to defaults")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.appPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    private var integrationsSection: some View {
        SettingsSection(header: "Integrations") {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: "heart.fill",
                    title: "Sync with Apple Health",
                    isOn: $healthKitSyncEnabled,
                    subtitle: "Automatically sync weight and body metrics.",
                    onToggle: { newValue in
                        handleHealthSyncToggle(to: newValue)
                    }
                )

                if healthKitManager.isImporting {
                    DSDivider().insetted(16)

                    VStack(spacing: 12) {
                        HStack {
                            ProgressView(value: healthKitManager.importProgress)
                                .tint(Color.liquidAccent)

                            Text("\(Int(healthKitManager.importProgress * 100))%")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.appTextSecondary)
                                .frame(width: 45, alignment: .trailing)
                        }

                        if !healthKitManager.importStatus.isEmpty {
                            Text(healthKitManager.importStatus)
                                .font(.caption)
                                .foregroundColor(.appTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, SettingsDesign.horizontalPadding)
                    .padding(.vertical, SettingsDesign.verticalPadding)
                }

                DSDivider().insetted(16)

                Button {
                    guard !isTriggeringHealthResync else { return }
                    HapticManager.shared.impact(style: .light)
                    isTriggeringHealthResync = true
                    Task {
                        await healthKitManager.forceFullHealthKitSync()
                        await MainActor.run {
                            isTriggeringHealthResync = false
                        }
                    }
                } label: {
                    HStack {
                        if isTriggeringHealthResync || healthKitManager.isImporting {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .semibold))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Re-sync data from Apple Health")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.appText)

                            Text("Pull in all available measurements again.")
                                .font(.caption)
                                .foregroundColor(.appTextSecondary)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.appBorder, lineWidth: 1)
                            .background(Color.appCard)
                    )
                }
                .disabled(isTriggeringHealthResync)
                .padding(.horizontal, SettingsDesign.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
        }
    }

    private var securitySection: some View {
        SettingsSection(header: "Security & privacy") {
            VStack(spacing: 0) {
                SettingsToggleRow(
                    icon: biometricType == .faceID ? "faceid" : "touchid",
                    title: biometricType == .faceID ? "Face ID lock" : "Touch ID lock",
                    isOn: $biometricLockEnabled,
                    subtitle: "Require biometrics to open the app.",
                    onToggle: { newValue in
                        if biometricType != .none {
                            HapticManager.shared.selection()
                            biometricLockEnabled = newValue
                        }
                    }
                )
                .disabled(biometricType == .none)

                DSDivider().insetted(16)

                SettingsNavigationLink(
                    icon: "lock.rotation",
                    title: "Change password",
                    subtitle: "Update your LogYourBody password."
                ) {
                    ChangePasswordView()
                }

                DSDivider().insetted(16)

                SettingsNavigationLink(
                    icon: "desktopcomputer",
                    title: "Active sessions",
                    subtitle: "Review devices logged in with your account."
                ) {
                    SecuritySessionsView()
                }
            }
        }
    }

    private var photosSection: some View {
        SettingsSection(header: "Photos") {
            SettingsToggleRow(
                icon: "photo.on.rectangle.angled",
                title: "Remove from Camera Roll after import",
                isOn: $deletePhotosAfterImport,
                subtitle: "Automatically delete photos after importing them.",
                onToggle: { _ in
                    HapticManager.shared.selection()
                }
            )
        }
    }

    private var advancedSection: some View {
        SettingsSection(header: "Advanced") {
            VStack(spacing: 12) {
                Button {
                    HapticManager.shared.selection()
                    Task {
                        let success = await revenueCatManager.restorePurchases()
                        await MainActor.run {
                            restoreAlertMessage = success ? "Your subscription has been restored" : revenueCatManager.errorMessage ?? "No active subscription found"
                            showingRestoreAlert = true
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Restore purchases")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.appCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                    )
                }

                Button {
                    triggerQuickExport()
                } label: {
                    HStack {
                        if isQuickExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export data")
                                .fontWeight(.semibold)
                            Text("Download a copy of your data.")
                                .font(.caption)
                                .foregroundColor(.appTextSecondary)
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.appCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            )
                    )
                }
                .disabled(isQuickExporting)
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
            .padding(.horizontal, SettingsDesign.horizontalPadding)
        }
    }

    private var dangerSection: some View {
        SettingsSection(
            header: "Danger zone",
            footer: "This permanently deletes your account and all data. This can’t be undone."
        ) {
            Button(role: .destructive) {
                HapticManager.shared.notification(type: .error)
            } label: {
                Text("Delete account")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.red.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, SettingsDesign.horizontalPadding)
        }
    }

    private var advancedAndDangerSpacing: some View {
        Spacer().frame(height: 12)
    }

    private var compactHeader: some View {
        VStack {
            if scrollOffset < -40 {
                HStack(spacing: 12) {
                    heroAvatarSmall

                    VStack(alignment: .leading, spacing: 2) {
                        Text(userDisplayName)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        if let plan = subscriptionPlanDisplay {
                            Text(plan)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, topSafeArea + 4)
                .padding(.bottom, 8)
                .background(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.2), radius: 10, y: 5)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: scrollOffset < -40)
        .ignoresSafeArea()
    }

    // MARK: - Helper Views

    @ViewBuilder
    private var heroAvatar: some View {
        if let avatarUrl = profileImageURL ?? authManager.currentUser?.avatarUrl, !avatarUrl.isEmpty {
            CachedAsyncImage(urlString: avatarUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                avatarPlaceholder
            }
            .frame(width: 72, height: 72)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
        } else {
            avatarPlaceholder
        }
    }

    @ViewBuilder
    private var heroAvatarSmall: some View {
        if let avatarUrl = profileImageURL ?? authManager.currentUser?.avatarUrl, !avatarUrl.isEmpty {
            CachedAsyncImage(urlString: avatarUrl) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle()
                    .fill(Color.white.opacity(0.15))
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 36, height: 36)
                .overlay(
                    Text(userInitials)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                )
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if revenueCatManager.isSubscribed {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Active")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.metricAccent.opacity(0.2))
            .foregroundColor(.metricAccent)
            .clipShape(Capsule())
        } else {
            HStack(spacing: 6) {
                Image(systemName: "figure.arms.open")
                    .font(.system(size: 11, weight: .bold))
                Text("Free")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private func profileRow(
        icon: String,
        title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.appTextSecondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SettingsDesign.titleFont)
                        .foregroundColor(.appText)

                    Text(value)
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.appTextSecondary.opacity(0.5))
            }
            .padding(.horizontal, SettingsDesign.horizontalPadding)
            .padding(.vertical, SettingsDesign.verticalPadding)
            .background(Color.clear)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func goalRow(
        icon: String,
        title: String,
        value: String,
        action: @escaping () -> Void,
        resetAction: (() -> Void)? = nil
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.appTextSecondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SettingsDesign.titleFont)
                        .foregroundColor(.appText)

                    Text(value)
                        .font(.system(size: 13))
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                if let resetAction {
                    Button(action: resetAction) {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.appTextSecondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.appTextSecondary.opacity(0.5))
                }
            }
            .padding(.horizontal, SettingsDesign.horizontalPadding)
            .padding(.vertical, SettingsDesign.verticalPadding)
        }
        .buttonStyle(.plain)
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.1))
            .overlay(
                Text(userInitials)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            )
    }

    // MARK: - Helper Functions

    private var userDisplayName: String {
        authManager.currentUser?.profile?.fullName ??
            authManager.currentUser?.name ??
            authManager.currentUser?.email ??
            "User"
    }

    private var userEmail: String {
        authManager.currentUser?.email ?? "Not available"
    }

    private var userInitials: String {
        let nameSource = authManager.currentUser?.profile?.fullName ??
            authManager.currentUser?.name ??
            authManager.currentUser?.email ?? ""
        let components = nameSource.split(separator: " ")
        let first = components.first?.first.map(String.init) ?? ""
        let last = components.dropFirst().first?.first.map(String.init) ?? ""
        let combined = (first + last)
        return combined.isEmpty ? "U" : combined.uppercased()
    }

    private var subscriptionPlanDisplay: String? {
        guard revenueCatManager.isSubscribed else { return nil }
        let productId = revenueCatManager.customerInfo?.entitlements.active.values.first?.productIdentifier ?? ""
        let lowercased = productId.lowercased()

        if lowercased.contains("annual") {
            return "Pro Annual"
        } else if lowercased.contains("month") {
            return "Pro Monthly"
        }
        return "LogYourBody Pro"
    }

    private var subscriptionRenewalText: String? {
        guard let date = revenueCatManager.subscriptionExpirationDate else { return nil }
        return formatDate(date)
    }

    private var dateOfBirthDisplay: String {
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

    private var heightDisplayText: String {
        guard let height = authManager.currentUser?.profile?.height,
              let unit = authManager.currentUser?.profile?.heightUnit else {
            return "Not set"
        }
        return convertHeightToCurrentSystem(height: height, fromUnit: unit)
    }

    private var topSafeArea: CGFloat {
        UIApplication.shared.windows.first?.safeAreaInsets.top ?? 0
    }

    private func handleHealthSyncToggle(to newValue: Bool) {
        if newValue {
            Task {
                let authorized = await healthKitManager.requestAuthorization()
                await MainActor.run {
                    if !authorized {
                        healthKitSyncEnabled = false
                    }
                }

                if healthKitManager.isAuthorized {
                    healthKitManager.observeWeightChanges()
                    healthKitManager.observeStepChanges()
                    try? await healthKitManager.setupStepCountBackgroundDelivery()
                    try? await healthKitManager.syncWeightFromHealthKit()
                }
            }
        }
    }

    private func triggerQuickExport() {
        guard !isQuickExporting else { return }
        isQuickExporting = true
        exportAlertTitle = "Export"
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                isQuickExporting = false
                exportAlertMessage = "Full data export is moving here soon. For now, use Data & Privacy > Export Data."
                showingExportStatusAlert = true
            }
        }
    }

    private func convertHeightToCurrentSystem(height: Double, fromUnit: String) -> String {
        if currentSystem == .imperial && fromUnit == "in" {
            let feet = Int(height) / 12
            let inches = Int(height) % 12
            return "\(feet)' \(inches)\""
        } else if currentSystem == .metric && fromUnit == "cm" {
            return "\(Int(height)) cm"
        } else if currentSystem == .imperial && fromUnit == "cm" {
            // Convert cm to inches
            let totalInches = height / 2.54
            let feet = Int(totalInches) / 12
            let inches = Int(totalInches) % 12
            return "\(feet)' \(inches)\""
        } else if currentSystem == .metric && fromUnit == "in" {
            // Convert inches to cm
            let cm = height * 2.54
            return "\(Int(cm)) cm"
        }
        return "\(Int(height)) \(fromUnit)"
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        isUploadingPhoto = true

        do {
            // Load the image data
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                // Upload to Clerk
                if let newImageURL = try await authManager.uploadProfilePicture(image) {
                    await MainActor.run {
                        profileImageURL = newImageURL
                        isUploadingPhoto = false
                    }
                } else {
                    await MainActor.run {
                        isUploadingPhoto = false
                    }
                }
            } else {
                await MainActor.run {
                    isUploadingPhoto = false
                }
            }
        } catch {
            await MainActor.run {
                isUploadingPhoto = false
            }
        }

        // Clear selection
        await MainActor.run {
            selectedPhotoItem = nil
        }
    }

    // MARK: - Subscription Helpers

    private var subscriptionStatusText: String {
        if revenueCatManager.isSubscribed {
            if revenueCatManager.isInTrialPeriod {
                return "Active (Free Trial)"
            } else {
                return "Active"
            }
        } else {
            return "Inactive"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Birthday Edit Sheet

private struct BirthdayEditSheet: View {
    @Environment(\.dismiss) var dismiss
    let currentDate: Date
    let onSave: (Date) -> Void

    @State private var selectedDate: Date

    init(currentDate: Date, onSave: @escaping (Date) -> Void) {
        self.currentDate = currentDate
        self.onSave = onSave
        self._selectedDate = State(initialValue: currentDate)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Date of Birth",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Spacer()

                Button(action: {
                    onSave(selectedDate)
                    dismiss()
                }) {
                    Text("Save")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color(hex: "#111111").ignoresSafeArea())
            .navigationTitle("Date of Birth")
            .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Height Edit Sheet

private struct HeightEditSheet: View {
    @Environment(\.dismiss) var dismiss
    let currentHeight: Double?
    let currentUnit: String?
    let preferredSystem: MeasurementSystem
    let onSave: (Double, String) -> Void

    @State private var feet: Int = 5
    @State private var inches: Int = 8
    @State private var centimeters: Int = 170

    init(currentHeight: Double?, currentUnit: String?, preferredSystem: MeasurementSystem, onSave: @escaping (Double, String) -> Void) {
        self.currentHeight = currentHeight
        self.currentUnit = currentUnit
        self.preferredSystem = preferredSystem
        self.onSave = onSave

        // Initialize based on current height
        if let height = currentHeight {
            if currentUnit == "in" {
                let totalInches = Int(height)
                _feet = State(initialValue: totalInches / 12)
                _inches = State(initialValue: totalInches % 12)
                _centimeters = State(initialValue: Int(height * 2.54))
            } else if currentUnit == "cm" {
                _centimeters = State(initialValue: Int(height))
                let totalInches = height / 2.54
                _feet = State(initialValue: Int(totalInches) / 12)
                _inches = State(initialValue: Int(totalInches) % 12)
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                if preferredSystem == .imperial {
                    // Feet and inches pickers
                    VStack(spacing: 10) {
                        Text("Height")
                            .font(.headline)
                            .foregroundColor(Color(hex: "#F7F8F8"))

                        HStack(spacing: 20) {
                            // Feet picker
                            VStack {
                                Text("Feet")
                                    .font(.caption)
                                    .foregroundColor(.appTextSecondary)
                                Picker("Feet", selection: $feet) {
                                    ForEach(3..<9) { ft in
                                        Text("\(ft)").tag(ft)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(width: 100)
                            }

                            // Inches picker
                            VStack {
                                Text("Inches")
                                    .font(.caption)
                                    .foregroundColor(.appTextSecondary)
                                Picker("Inches", selection: $inches) {
                                    ForEach(0..<12) { inch in
                                        Text("\(inch)").tag(inch)
                                    }
                                }
                                .pickerStyle(.wheel)
                                .frame(width: 100)
                            }
                        }
                    }
                } else {
                    // Centimeters picker
                    VStack(spacing: 10) {
                        Text("Height")
                            .font(.headline)
                            .foregroundColor(Color(hex: "#F7F8F8"))

                        Picker("Centimeters", selection: $centimeters) {
                            ForEach(120..<220) { cm in
                                Text("\(cm) cm").tag(cm)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 200)
                    }
                }

                Spacer()

                Button(action: {
                    if preferredSystem == .imperial {
                        let totalInches = Double(feet * 12 + inches)
                        onSave(totalInches, "in")
                    } else {
                        onSave(Double(centimeters), "cm")
                    }
                    dismiss()
                }) {
                    Text("Save")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            .padding()
            .background(Color(hex: "#111111").ignoresSafeArea())
            .navigationTitle("Height")
            .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Custom label styles removed - use default SwiftUI label styles

#Preview {
    NavigationStack {
        PreferencesView()
            .environmentObject(AuthManager.shared)
    }
}
