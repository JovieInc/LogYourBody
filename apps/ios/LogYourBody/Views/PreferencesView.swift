//
// PreferencesView.swift
// LogYourBody
//
import SwiftUI
import Foundation
import LocalAuthentication
import PhotosUI

// MARK: - Measurement System Enum (Global)
enum MeasurementSystem: String, CaseIterable {
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

enum TimeFormatPreference: String, CaseIterable, Identifiable {
    case twelveHour = "12-hour"
    case twentyFourHour = "24-hour"

    static let defaultValue = TimeFormatPreference.twelveHour.rawValue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twelveHour:
            return "12-Hour"
        case .twentyFourHour:
            return "24-Hour"
        }
    }

    var descriptiveLabel: String {
        switch self {
        case .twelveHour:
            return "12-hour clock (6:30 PM)"
        case .twentyFourHour:
            return "24-hour clock (18:30)"
        }
    }

    var exampleDisplay: String {
        switch self {
        case .twelveHour:
            return "6:30 PM"
        case .twentyFourHour:
            return "18:30"
        }
    }

    func formattedString(for date: Date, includeDate: Bool = false) -> String {
        let formatter = DateFormatter()
        let template = formatTemplate(includeDate: includeDate)

        if let localizedFormat = DateFormatter.dateFormat(fromTemplate: template, options: 0, locale: Locale.current) {
            formatter.dateFormat = localizedFormat
        } else {
            formatter.dateStyle = includeDate ? .medium : .none
            formatter.timeStyle = .short
        }

        return formatter.string(from: date)
    }

    private func formatTemplate(includeDate: Bool) -> String {
        switch (self, includeDate) {
        case (.twentyFourHour, true):
            return "yMMMd HHmm"
        case (.twentyFourHour, false):
            return "HHmm"
        case (.twelveHour, true):
            return "yMMMd hmma"
        case (.twelveHour, false):
            return "hmma"
        }
    }
}

struct PreferencesView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var revenueCatManager = RevenueCatManager.shared
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem
    @AppStorage(Constants.preferredTimeFormatKey) private var timeFormatPreference = TimeFormatPreference.defaultValue
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

    private var currentTimeFormat: TimeFormatPreference {
        TimeFormatPreference(rawValue: timeFormatPreference) ?? .twelveHour
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
        ScrollView {
            VStack(spacing: SettingsDesign.sectionSpacing) {
                // User Profile Header
                VStack(spacing: 12) {
                    // Avatar - using cached image loader
                    if let avatarUrl = authManager.currentUser?.avatarUrl, !avatarUrl.isEmpty {
                        CachedAsyncImage(urlString: avatarUrl) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
                        } placeholder: {
                            avatarPlaceholder
                        }
                        .id(avatarUrl) // Stable ID prevents reload on view updates
                    } else {
                        avatarPlaceholder
                    }

                    // User Name
                    Text(authManager.currentUser?.profile?.fullName ?? authManager.currentUser?.name ?? "User")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.appText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

                // Account Section
                SettingsSection(header: "Account") {
                    VStack(spacing: 0) {
                        // Email (read-only)
                        DataInfoRow(
                            icon: "envelope.fill",
                            title: "Email",
                            description: authManager.currentUser?.email ?? "Not available",
                            iconColor: .appTextSecondary
                        )

                        Divider()
                            .padding(.leading, 46)

                        // Profile Photo
                        Button {
                            showingPhotoPicker = true
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(width: 30)

                                Text("Change Profile Photo")
                                    .font(SettingsDesign.titleFont)
                                    .foregroundColor(.appText)

                                Spacer()

                                // Show current avatar thumbnail - using cached image loader
                                if let avatarUrl = profileImageURL ?? authManager.currentUser?.avatarUrl, !avatarUrl.isEmpty {
                                    CachedAsyncImage(urlString: avatarUrl) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 32, height: 32)
                                            .clipShape(Circle())
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.appTextSecondary.opacity(0.3))
                                            .frame(width: 32, height: 32)
                                    }
                                    .id(avatarUrl) // Stable ID prevents reload
                                } else {
                                    Circle()
                                        .fill(Color.appPrimary)
                                        .frame(width: 32, height: 32)
                                        .overlay(
                                            Text(authManager.currentUser?.profile?.fullName?.prefix(1).uppercased() ?? "U")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.white)
                                        )
                                }

                                if isUploadingPhoto {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .padding(.leading, 8)
                                } else {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(Color(.tertiaryLabel))
                                        .padding(.leading, 8)
                                }
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                        }
                        .disabled(isUploadingPhoto)
                    }
                }

                // Subscription Section
                SettingsSection(header: "Subscription") {
                    VStack(spacing: 0) {
                        // Subscription Status
                        HStack {
                            Image(systemName: revenueCatManager.isSubscribed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(revenueCatManager.isSubscribed ? .green : .red)
                                .frame(width: 30)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Status")
                                    .font(SettingsDesign.titleFont)
                                    .foregroundColor(.appText)

                                Text(subscriptionStatusText)
                                    .font(.system(size: 14))
                                    .foregroundColor(.appTextSecondary)
                            }

                            Spacer()
                        }
                        .padding(.horizontal, SettingsDesign.horizontalPadding)
                        .padding(.vertical, SettingsDesign.verticalPadding)

                        // Expiration Date (if subscribed)
                        if revenueCatManager.isSubscribed, let expirationDate = revenueCatManager.subscriptionExpirationDate {
                            Divider()
                                .padding(.leading, 46)

                            HStack {
                                Image(systemName: "calendar")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(revenueCatManager.isInTrialPeriod ? "Trial Ends" : "Renews On")
                                        .font(SettingsDesign.titleFont)
                                        .foregroundColor(.appText)

                                    Text(formatDate(expirationDate))
                                        .font(.system(size: 14))
                                        .foregroundColor(.appTextSecondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                        }

                        // Restore Purchases Button
                        Divider()
                            .padding(.leading, 46)

                        Button {
                            Task {
                                let success = await revenueCatManager.restorePurchases()
                                await MainActor.run {
                                    if success {
                                        restoreAlertMessage = "Your subscription has been restored!"
                                    } else {
                                        restoreAlertMessage = revenueCatManager.errorMessage ?? "No active subscription found"
                                    }
                                    showingRestoreAlert = true
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appPrimary)
                                    .frame(width: 30)

                                Text("Restore Purchases")
                                    .font(SettingsDesign.titleFont)
                                    .foregroundColor(.appText)

                                Spacer()
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                        }
                        .disabled(revenueCatManager.isPurchasing)

                        // Manage Subscription (if subscribed)
                        if revenueCatManager.isSubscribed {
                            Divider()
                                .padding(.leading, 46)

                            Button {
                                // Open App Store subscription management
                                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "gear")
                                        .font(.system(size: 20))
                                        .foregroundColor(.appTextSecondary)
                                        .frame(width: 30)

                                    Text("Manage Subscription")
                                        .font(SettingsDesign.titleFont)
                                        .foregroundColor(.appText)

                                    Spacer()

                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(.appTextSecondary)
                                }
                                .padding(.horizontal, SettingsDesign.horizontalPadding)
                                .padding(.vertical, SettingsDesign.verticalPadding)
                            }
                        }
                    }
                }

                // Profile Section
                SettingsSection(header: "Profile") {
                    VStack(spacing: 0) {
                        // Full Name
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Full Name")
                                        .font(SettingsDesign.titleFont)
                                        .foregroundColor(.appText)

                                    Text(authManager.currentUser?.profile?.fullName ?? authManager.currentUser?.name ?? "Not set")
                                        .font(.system(size: 13))
                                        .foregroundColor(.appTextSecondary)
                                }

                                Spacer()

                                Image(systemName: "pencil")
                                    .foregroundColor(.appTextSecondary.opacity(0.5))
                                    .font(.system(size: 14))
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let currentName = authManager.currentUser?.profile?.fullName ?? authManager.currentUser?.name ?? ""
                                showTextInputAlert(
                                    title: "Full Name",
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
                        }

                        Divider()

                        // Date of Birth
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Date of Birth")
                                        .font(SettingsDesign.titleFont)
                                        .foregroundColor(.appText)

                                    if let dob = authManager.currentUser?.profile?.dateOfBirth {
                                        Text(dob, style: .date)
                                            .font(.system(size: 13))
                                            .foregroundColor(.appTextSecondary)
                                        if let age = authManager.currentUser?.profile?.age {
                                            Text(" (Age \(age))")
                                                .font(.system(size: 13))
                                                .foregroundColor(.appTextSecondary.opacity(0.7))
                                        }
                                    } else {
                                        Text("Not set")
                                            .font(.system(size: 13))
                                            .foregroundColor(.appTextSecondary.opacity(0.7))
                                    }
                                }

                                Spacer()

                                Image(systemName: "pencil")
                                    .foregroundColor(.appTextSecondary.opacity(0.5))
                                    .font(.system(size: 14))
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isEditingBirthday = true
                            }
                        }

                        Divider()

                        // Height
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "ruler")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Height")
                                        .font(SettingsDesign.titleFont)
                                        .foregroundColor(.appText)

                                    if let height = authManager.currentUser?.profile?.height,
                                       let unit = authManager.currentUser?.profile?.heightUnit {
                                        // Display height in user's preferred measurement system
                                        if currentSystem == .imperial && unit == "in" {
                                            // Height stored in inches, display as feet and inches
                                            let feet = Int(height) / 12
                                            let inches = Int(height) % 12
                                            Text("\(feet)' \(inches)\"")
                                                .font(.system(size: 13))
                                                .foregroundColor(.appTextSecondary)
                                        } else if currentSystem == .metric && unit == "cm" {
                                            // Height stored in cm
                                            Text("\(Int(height)) cm")
                                                .font(.system(size: 13))
                                                .foregroundColor(.appTextSecondary)
                                        } else {
                                            // Convert between units if needed
                                            let displayHeight = convertHeightToCurrentSystem(height: height, fromUnit: unit)
                                            Text(displayHeight)
                                                .font(.system(size: 13))
                                                .foregroundColor(.appTextSecondary)
                                        }
                                    } else {
                                        Text("Not set")
                                            .font(.system(size: 13))
                                            .foregroundColor(.appTextSecondary.opacity(0.7))
                                    }
                                }

                                Spacer()

                                Image(systemName: "pencil")
                                    .foregroundColor(.appTextSecondary.opacity(0.5))
                                    .font(.system(size: 14))
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isEditingHeight = true
                            }
                        }
                    }
                }
                .sheet(isPresented: $isEditingBirthday) {
                    BirthdayEditSheet(
                        currentDate: authManager.currentUser?.profile?.dateOfBirth ?? Date(),
                        onSave: { newDate in
                            Task {
                                isSavingProfile = true
                                await authManager.updateProfile(["dateOfBirth": newDate])
                                isSavingProfile = false
                            }
                        }
                    )
                }
                .sheet(isPresented: $isEditingHeight) {
                    HeightEditSheet(
                        currentHeight: authManager.currentUser?.profile?.height,
                        currentUnit: authManager.currentUser?.profile?.heightUnit,
                        preferredSystem: currentSystem,
                        onSave: { newHeight, newUnit in
                            Task {
                                isSavingProfile = true
                                // Convert to inches for storage (database stores in inches)
                                let heightInInches: Double
                                if newUnit == "cm" {
                                    heightInInches = newHeight / 2.54
                                } else {
                                    heightInInches = newHeight
                                }
                                await authManager.updateProfile([
                                    "height": heightInInches,
                                    "heightUnit": "in"
                                ])
                                isSavingProfile = false
                            }
                        }
                    )
                }

                // Units Section
                SettingsSection(header: "Units") {
                    VStack(spacing: 0) {
                        // Measurement System Picker
                        HStack {
                            Text("Measurement System")
                                .font(SettingsDesign.titleFont)
                            Spacer()
                            Picker("", selection: $measurementSystem) {
                                Text("Imperial").tag(MeasurementSystem.imperial.rawValue)
                                Text("Metric").tag(MeasurementSystem.metric.rawValue)
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .fixedSize()
                        }
                        .padding(.horizontal, SettingsDesign.horizontalPadding)
                        .padding(.vertical, SettingsDesign.verticalPadding)

                        Divider()

                        // Time Format Picker
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Time Format")
                                    .font(SettingsDesign.titleFont)

                                Spacer()

                                Picker("", selection: $timeFormatPreference) {
                                    Text(TimeFormatPreference.twelveHour.title)
                                        .tag(TimeFormatPreference.twelveHour.rawValue)
                                    Text(TimeFormatPreference.twentyFourHour.title)
                                        .tag(TimeFormatPreference.twentyFourHour.rawValue)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .fixedSize()
                            }

                            Text(currentTimeFormat.descriptiveLabel)
                                .font(.system(size: 13))
                                .foregroundColor(.appTextSecondary)
                        }
                        .padding(.horizontal, SettingsDesign.horizontalPadding)
                        .padding(.vertical, SettingsDesign.verticalPadding)

                        Divider()

                        // Weight Unit Display
                        DataInfoRow(
                            icon: "scalemass",
                            title: "Weight",
                            description: currentSystem.weightUnit,
                            iconColor: .appTextSecondary
                        )
                        
                        Divider()
                        
                        // Height Unit Display
                        DataInfoRow(
                            icon: "ruler",
                            title: "Height",
                            description: currentSystem.heightDisplay,
                            iconColor: .appTextSecondary
                        )
                    }
                }

                // Goals Section
                SettingsSection(
                    header: "Goals",
                    footer: "Set your target goals for each metric. Leave blank to use gender-based defaults."
                ) {
                    VStack(spacing: 0) {
                        // Weight Goal
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "scalemass")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Weight Goal")
                                        .font(SettingsDesign.titleFont)
                                        .foregroundColor(.appText)

                                    if let goal = customWeightGoal {
                                        Text("\(String(format: "%.1f", goal)) \(currentSystem.weightUnit)")
                                            .font(.system(size: 13))
                                            .foregroundColor(.appTextSecondary)
                                    } else {
                                        Text("Not set")
                                            .font(.system(size: 13))
                                            .foregroundColor(.appTextSecondary.opacity(0.7))
                                    }
                                }

                                Spacer()

                                // Clear button if set
                                if customWeightGoal != nil {
                                    Button(action: {
                                        customWeightGoal = nil
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.appTextSecondary.opacity(0.5))
                                            .font(.system(size: 18))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Show input alert for weight goal
                                let currentValue = customWeightGoal.map { String(format: "%.1f", $0) } ?? ""
                                showTextInputAlert(
                                    title: "Weight Goal",
                                    message: "Enter your target weight in \(currentSystem.weightUnit)",
                                    currentValue: currentValue,
                                    keyboardType: .decimalPad
                                ) { newValue in
                                    if let value = Double(newValue), value > 0 {
                                        customWeightGoal = value
                                    }
                                }
                            }
                        }

                        Divider()

                        // Body Fat % Goal
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "percent")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Body Fat % Goal")
                                        .font(SettingsDesign.titleFont)
                                        .foregroundColor(.appText)

                                    Text("\(String(format: "%.1f", currentBodyFatGoal))%")
                                        .font(.system(size: 13))
                                        .foregroundColor(.appTextSecondary)
                                        + Text(customBodyFatGoal == nil ? " (default)" : "")
                                            .font(.system(size: 13))
                                            .foregroundColor(.appTextSecondary.opacity(0.7))
                                }

                                Spacer()

                                // Reset button if custom
                                if customBodyFatGoal != nil {
                                    Button(action: {
                                        customBodyFatGoal = nil
                                    }) {
                                        Image(systemName: "arrow.counterclockwise.circle.fill")
                                            .foregroundColor(.appTextSecondary.opacity(0.5))
                                            .font(.system(size: 18))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let currentValue = customBodyFatGoal.map { String(format: "%.1f", $0) } ?? String(format: "%.1f", defaultBodyFatGoal)
                                showTextInputAlert(
                                    title: "Body Fat % Goal",
                                    message: "Enter your target body fat percentage (0-40%)",
                                    currentValue: currentValue,
                                    keyboardType: .decimalPad
                                ) { newValue in
                                    if let value = Double(newValue), value >= 0, value <= 40 {
                                        customBodyFatGoal = value
                                    }
                                }
                            }
                        }

                        Divider()

                        // FFMI Goal
                        VStack(spacing: 0) {
                            HStack {
                                Image(systemName: "figure.arms.open")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("FFMI Goal")
                                        .font(SettingsDesign.titleFont)
                                        .foregroundColor(.appText)

                                    Text(String(format: "%.1f", currentFFMIGoal))
                                        .font(.system(size: 13))
                                        .foregroundColor(.appTextSecondary)
                                        + Text(customFFMIGoal == nil ? " (default)" : "")
                                            .font(.system(size: 13))
                                            .foregroundColor(.appTextSecondary.opacity(0.7))
                                }

                                Spacer()

                                // Reset button if custom
                                if customFFMIGoal != nil {
                                    Button(action: {
                                        customFFMIGoal = nil
                                    }) {
                                        Image(systemName: "arrow.counterclockwise.circle.fill")
                                            .foregroundColor(.appTextSecondary.opacity(0.5))
                                            .font(.system(size: 18))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                let currentValue = customFFMIGoal.map { String(format: "%.1f", $0) } ?? String(format: "%.1f", defaultFFMIGoal)
                                showTextInputAlert(
                                    title: "FFMI Goal",
                                    message: "Enter your target Fat-Free Mass Index (10-30)",
                                    currentValue: currentValue,
                                    keyboardType: .decimalPad
                                ) { newValue in
                                    if let value = Double(newValue), value >= 10, value <= 30 {
                                        customFFMIGoal = value
                                    }
                                }
                            }
                        }

                        Divider()

                        // Reset All Button
                        Button(action: resetToDefaults) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 20))
                                    .foregroundColor(.appTextSecondary)
                                    .frame(width: 30)

                                Text("Reset All to Defaults")
                                    .font(SettingsDesign.titleFont)
                                    .foregroundColor(.appText)

                                Spacer()
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }

                // HealthKit Sync Section
                SettingsSection(
                    header: "Apple Health",
                    footer: healthKitSyncEnabled ?
                        "Automatically sync weight and body measurements with Apple Health" :
                        "Enable to sync with Apple Health"
                ) {
                    VStack(spacing: 0) {
                        SettingsToggleRow(
                            icon: "heart.fill",
                            title: "Sync with Apple Health",
                            isOn: $healthKitSyncEnabled
                        )
                        .onChange(of: healthKitSyncEnabled) { _, newValue in
                            if newValue {
                                // Request authorization when enabling
                                Task {
                                    await healthKitManager.requestAuthorization()

                                    // Start observers if authorized
                                    if healthKitManager.isAuthorized {
                                        healthKitManager.observeWeightChanges()
                                        healthKitManager.observeStepChanges()
                                        try? await healthKitManager.setupStepCountBackgroundDelivery()

                                        // Trigger initial sync
                                        try? await healthKitManager.syncWeightFromHealthKit()
                                    }
                                }
                            }
                        }

                        // Show progress during import
                        if healthKitManager.isImporting {
                            Divider()

                            VStack(spacing: 12) {
                                HStack {
                                    ProgressView(value: healthKitManager.importProgress)
                                        .accentColor(Color.liquidAccent)

                                    Text("\(Int(healthKitManager.importProgress * 100))%")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.appTextSecondary)
                                        .frame(width: 45, alignment: .trailing)
                                }

                                if !healthKitManager.importStatus.isEmpty {
                                    Text(healthKitManager.importStatus)
                                        .font(.system(size: 13))
                                        .foregroundColor(.appTextSecondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, SettingsDesign.horizontalPadding)
                            .padding(.vertical, SettingsDesign.verticalPadding)
                        }

                        // Re-import button (only show when sync is enabled and not currently importing)
                        if healthKitSyncEnabled && !healthKitManager.isImporting {
                            Divider()

                            Button(action: {
                                Task {
                                    await healthKitManager.forceFullHealthKitSync()
                                }
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "arrow.clockwise.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.appTextSecondary)

                                    Text("Re-import All Data")
                                        .font(SettingsDesign.titleFont)
                                        .foregroundColor(.appText)

                                    Spacer()
                                }
                                .padding(.horizontal, SettingsDesign.horizontalPadding)
                                .padding(.vertical, SettingsDesign.verticalPadding)
                            }
                        }
                    }
                }

                // Security Section
                SettingsSection(
                    header: "Security & Privacy",
                    footer: biometricType == .none ?
                        "Biometric authentication is not available on this device" :
                        biometricLockEnabled ?
                        "Require \(biometricType == .faceID ? "Face ID" : "Touch ID") to open the app" :
                        "App opens without authentication"
                ) {
                    VStack(spacing: 0) {
                        // Biometric Lock
                        SettingsToggleRow(
                            icon: biometricType == .faceID ? "faceid" : "touchid",
                            title: biometricType == .faceID ? "Face ID Lock" : "Touch ID Lock",
                            isOn: $biometricLockEnabled
                        )
                        .disabled(biometricType == .none)

                        Divider()
                            .padding(.leading, 46)

                        // Change Password
                        NavigationLink(destination: ChangePasswordView()) {
                            SettingsRow(
                                icon: "lock.rotation",
                                title: "Change Password",
                                showChevron: true
                            )
                        }

                        Divider()
                            .padding(.leading, 46)

                        // Active Sessions
                        NavigationLink(destination: SecuritySessionsView()) {
                            SettingsRow(
                                icon: "desktopcomputer",
                                title: "Active Sessions",
                                showChevron: true
                            )
                        }
                    }
                }

                // Photo Management Section
                SettingsSection(
                    header: "Photo Management",
                    footer: "Automatically delete photos from your camera roll after importing them into the app"
                ) {
                    SettingsToggleRow(
                        icon: "trash",
                        title: "Delete After Import",
                        isOn: $deletePhotosAfterImport
                    )
                }

                // Data & Privacy Section
                SettingsSection(header: "Data & Privacy") {
                    VStack(spacing: 0) {
                        SettingsNavigationLink(
                            icon: "square.and.arrow.up",
                            title: "Export Data"
                        ) {
                            ExportDataView()
                        }
                        
                        Divider()
                        
                        SettingsNavigationLink(
                            icon: "trash",
                            title: "Delete Account",
                            tintColor: .red
                        ) {
                            DeleteAccountView()
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .settingsBackground()
        .alert("Restore Purchases", isPresented: $showingRestoreAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreAlertMessage)
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

    // MARK: - Helper Views

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 80, height: 80)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.appTextSecondary)
            )
            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 2))
    }

    // MARK: - Helper Functions

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
