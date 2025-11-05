//
// PreferencesView.swift
// LogYourBody
//
import SwiftUI
import Foundation
import LocalAuthentication

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

struct PreferencesView: View {
    @AppStorage(Constants.preferredMeasurementSystemKey) private var measurementSystem = PreferencesView.defaultMeasurementSystem
    @AppStorage("biometricLockEnabled") private var biometricLockEnabled = false
    @State private var biometricType: LABiometryType = .none

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
    
    // Removed showToast helper - use ToastManager.shared.show directly
    
    var body: some View {
        ScrollView {
            VStack(spacing: SettingsDesign.sectionSpacing) {
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
                
                
                // Security Section
                SettingsSection(
                    header: "Security",
                    footer: biometricType == .none ?
                        "Biometric authentication is not available on this device" :
                        biometricLockEnabled ?
                        "Require \(biometricType == .faceID ? "Face ID" : "Touch ID") to open the app" :
                        "App opens without authentication"
                ) {
                    SettingsToggleRow(
                        icon: biometricType == .faceID ? "faceid" : "touchid",
                        title: biometricType == .faceID ? "Face ID Lock" : "Touch ID Lock",
                        isOn: $biometricLockEnabled
                    )
                    .disabled(biometricType == .none)
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
        .navigationTitle("Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            checkBiometricAvailability()
        }
    }
}

// Custom label styles removed - use default SwiftUI label styles

#Preview {
    NavigationView {
        PreferencesView()
    }
}
