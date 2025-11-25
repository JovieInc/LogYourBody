//
// PreferencesView.swift
// LogYourBody
//
import SwiftUI
import Foundation
import LocalAuthentication
import PhotosUI
import UIKit

struct PreferencesView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @AppStorage("healthKitSyncEnabled") private var healthKitSyncEnabled = true
    @AppStorage(Constants.deletePhotosAfterImportKey) private var deletePhotosAfterImport = false
    @AppStorage("stepGoal") private var stepGoal: Int = 10_000
    @AppStorage(Constants.goalWeightKey) private var customWeightGoal: Double?
    @AppStorage(Constants.goalBodyFatPercentageKey) private var customBodyFatGoal: Double?
    @AppStorage(Constants.goalFFMIKey) private var customFFMIGoal: Double?
    @State private var biometricType: LABiometryType = .none
    @ObservedObject private var healthKitManager = HealthKitManager.shared
    @State private var showingRestoreAlert = false
    @State private var restoreAlertMessage = ""


    // Local state for editing goals
    @State private var editingWeightGoal: String = ""
    @State private var editingBodyFatGoal: String = ""
    @State private var editingFFMIGoal: String = ""

    // Local state for editing profile fields
    @State private var isShowingProfileSettings = false

    // Photo picker state
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var avatarUploadProgress: Double = 0.0
    @State private var profileImageURL: String?

    @State private var scrollOffset: CGFloat = 0
    @State private var stepGoalRepeatDelta: Int = 0
    @State private var showingLogoutConfirmation = false
    @State private var isTriggeringHealthResync = false
    @State private var isHealthSyncSetupInProgress = false

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
        MeasurementSystem.fromStored(rawValue: measurementSystem)
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

    private func changeStepGoal(by delta: Int) {
        let newValue = stepGoal + delta
        stepGoal = max(newValue, 0)
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
        .sheet(isPresented: $isShowingProfileSettings) {
            NavigationStack {
                ProfileSettingsViewV2()
                    .environmentObject(authManager)
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

                    if let memberSinceText {
                        Text(memberSinceText)
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)
                    }
                }

                Spacer()
            }

            HStack(spacing: 8) {
                statusBadge

                if let planName = subscriptionPlanDisplay {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(planName)
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)

                        if let renewal = subscriptionRenewalText {
                            Text("Valid to \(renewal)")
                                .font(.caption)
                                .foregroundColor(.appTextSecondary)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding()
        .settingsCardStyle()
    }

    private var accountSection: some View {
        SettingsSection(header: "Account") {
            VStack(spacing: 0) {
                accountEmailRow

                DSDivider().insetted(16)

                changeProfilePhotoRow

                DSDivider().insetted(16)

                logoutRow
            }
        }
    }

    private var accountEmailRow: some View {
        SettingsRow(
            icon: "envelope.fill",
            title: "Email",
            value: userEmail,
            showChevron: false,
            tintColor: .appText
        )
    }

    private var changeProfilePhotoRow: some View {
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
        .accessibilityLabel("Change profile photo")
        .accessibilityHint("Choose a new photo for your profile.")
    }

    private var logoutRow: some View {
        SettingsButtonRow(
            icon: "rectangle.portrait.and.arrow.right",
            title: "Log out",
            role: .destructive
        ) {
            HapticManager.shared.notification(type: .warning)
            showingLogoutConfirmation = true
        }
        .accessibilityLabel("Log out")
        .accessibilityHint("Signs you out of LogYourBody on this device.")
    }

    private var subscriptionSection: some View {
        SettingsSection(header: "Subscription") {
            VStack(spacing: 0) {
                subscriptionStatusRow

                if let renewal = subscriptionRenewalText {
                    DSDivider().insetted(16)
                    subscriptionRenewalRow(renewal: renewal)
                }

                DSDivider().insetted(16)

                manageSubscriptionRow
            }
        }
    }

    private var subscriptionStatusRow: some View {
        SettingsRow(
            icon: revenueCatManager.isSubscribed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
            title: revenueCatManager.isSubscribed ? "Active" : "Inactive",
            subtitle: subscriptionPlanDisplay,
            showChevron: false,
            tintColor: revenueCatManager.isSubscribed ? .appPrimary : .orange
        )
    }

    private func subscriptionRenewalRow(renewal: String) -> some View {
        SettingsRow(
            icon: "calendar",
            title: revenueCatManager.isInTrialPeriod ? "Trial ends" : "Renews on",
            value: renewal,
            showChevron: false,
            tintColor: .appText
        )
    }

    private var manageSubscriptionRow: some View {
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
        .accessibilityLabel("Manage subscription")
        .accessibilityHint("Opens the App Store to manage your subscription.")
    }

    private var profileSection: some View {
        SettingsSection(header: "Profile") {
            VStack(spacing: 0) {
                profileFullNameRow

                DSDivider().insetted(16)

                profileDateOfBirthRow

                DSDivider().insetted(16)

                profileHeightRow
            }
        }
    }

    private var profileFullNameRow: some View {
        profileRow(
            icon: "person.fill",
            title: "Full name",
            value: authManager.currentUser?.profile?.fullName ?? authManager.currentUser?.name ?? "Not set"
        ) {
            isShowingProfileSettings = true
        }
    }

    private var profileDateOfBirthRow: some View {
        profileRow(
            icon: "calendar",
            title: "Date of birth",
            value: dateOfBirthDisplay
        ) {
            isShowingProfileSettings = true
        }
    }

    private var profileHeightRow: some View {
        profileRow(
            icon: "ruler",
            title: "Height",
            value: heightDisplayText
        ) {
            isShowingProfileSettings = true
        }
    }

    private var trackingGoalsSection: some View {
        SettingsSection(
            header: "Tracking & goals",
            footer: "Set custom targets or use defaults."
        ) {
            VStack(spacing: 0) {
                measurementSystemSection
                stepGoalRow

                DSDivider().insetted(16)

                goalRow(
                    icon: "target",
                    title: "Weight goal",
                    value: customWeightGoal.map {
                        "\(String(format: "%.1f", $0)) \(currentSystem.weightUnit)"
                    } ?? "Not set"
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
                        + (
                            customBodyFatGoal == nil
                                ? " (default)"
                                : ""
                        )
                ) {
                    let currentValue = customBodyFatGoal.map { String(format: "%.1f", $0) }
                        ?? String(format: "%.1f", defaultBodyFatGoal)
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
                        + (
                            customFFMIGoal == nil
                                ? " (default)"
                                : ""
                        )
                ) {
                    let currentValue = customFFMIGoal.map { String(format: "%.1f", $0) }
                        ?? String(format: "%.1f", defaultFFMIGoal)
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
            }
        }
    }

    private var measurementSystemSection: some View {
        SettingsRow(
            icon: "globe",
            title: "Units",
            subtitle: currentSystem == .metric ? "Metric (kg, cm)" : "Imperial (lbs, ft)",
            showChevron: false,
            tintColor: .appText
        )
        .overlay(
            HStack {
                Spacer()
                Picker("Units", selection: $measurementSystem) {
                    Text("Metric").tag(MeasurementSystem.metric.rawValue)
                    Text("Imperial").tag(MeasurementSystem.imperial.rawValue)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding(.trailing, SettingsDesign.horizontalPadding)
        )
    }

    private var stepGoalRow: some View {
        SettingsRow(
            icon: "figure.walk",
            title: "Daily step goal",
            subtitle: FormatterCache.stepsFormatter.string(from: NSNumber(value: stepGoal)) ?? "\(stepGoal) steps",
            showChevron: false,
            tintColor: .appText
        )
        .overlay(
            HStack(spacing: 12) {
                Spacer()
                Button {
                    changeStepGoal(by: -1_000)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.appTextSecondary)
                }
                Button {
                    changeStepGoal(by: 1_000)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.appPrimary)
                }
            }
            .padding(.trailing, SettingsDesign.horizontalPadding)
        )
    }

    private var integrationsSection: some View {
        SettingsSection(header: "Integrations") {
            SettingsNavigationLink(
                icon: "square.stack.3d.up.fill",
                title: "Integrations",
                subtitle: "Connect Apple Health and other services."
            ) {
                IntegrationsView()
            }
        }
    }

    private var securitySection: some View {
        SettingsSection(header: "Security") {
            VStack(spacing: 0) {
                changePasswordRow

                DSDivider().insetted(16)

                activeSessionsRow
            }
        }
    }

    private var changePasswordRow: some View {
        SettingsNavigationLink(
            icon: "lock.rotation",
            title: "Change password",
            subtitle: "Update your password."
        ) {
            ChangePasswordView()
        }
    }

    private var activeSessionsRow: some View {
        SettingsNavigationLink(
            icon: "desktopcomputer",
            title: "Active sessions",
            subtitle: "Review devices signed in to your account."
        ) {
            SecuritySessionsView()
        }
    }

    private var photosSection: some View {
        SettingsSection(header: "Photos") {
            SettingsToggleRow(
                icon: "photo.on.rectangle.angled",
                title: "Remove from Photos after import",
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
                            restoreAlertMessage = success
                                ? "Your subscription has been restored"
                                : (
                                    revenueCatManager.errorMessage
                                        ?? "No active subscription found"
                                )
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
                .accessibilityLabel("Restore purchases")
                .accessibilityHint("Attempts to restore your active subscription.")
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
            NavigationLink {
                DeleteAccountView()
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
            .accessibilityLabel("Delete account")
            .accessibilityHint("Permanently deletes your account and all data.")
            .simultaneousGesture(
                TapGesture().onEnded {
                    HapticManager.shared.notification(type: .error)
                }
            )
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
        let avatarSize: CGFloat = 72
        let ringSize: CGFloat = 84

        ZStack {
            ProgressRing(
                progress: avatarUploadProgress,
                size: ringSize,
                lineWidth: 4,
                accentColor: .metricAccent,
                showPercentage: false
            )
            .opacity(isUploadingPhoto ? 1 : 0)

            Group {
                if let avatarUrl = profileImageURL ?? authManager.currentUser?.avatarUrl, !avatarUrl.isEmpty {
                    CachedAsyncImage(urlString: avatarUrl) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        avatarPlaceholder
                    }
                    .frame(width: avatarSize, height: avatarSize)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 2)
                    )
                } else {
                    avatarPlaceholder
                        .frame(width: avatarSize, height: avatarSize)
                }
            }
        }
        .frame(width: ringSize, height: ringSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Profile photo")
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

    private var memberSinceText: String? {
        guard let date = authManager.memberSinceDate else { return nil }
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        return "Member since \(year)"
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
                await configureHealthSyncPipelineIfNeeded()
            }
        }
    }

    private func configureHealthSyncPipelineIfNeeded() async {
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

    private func convertHeightToCurrentSystem(height: Double, fromUnit: String) -> String {
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

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        await MainActor.run {
            isUploadingPhoto = true
            avatarUploadProgress = 0.15
        }

        do {
            // Load the image data
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    avatarUploadProgress = 0.4
                }

                // Upload to Clerk
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
// Custom label styles removed - use default SwiftUI label styles

#Preview {
    NavigationStack {
        PreferencesView()
            .environmentObject(AuthManager.shared)
    }
}
