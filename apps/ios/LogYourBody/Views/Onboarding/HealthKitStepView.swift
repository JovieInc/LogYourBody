//
// HealthKitStepView.swift
// LogYourBody
//
import SwiftUI
import HealthKit

struct HealthKitStepView: View {
    @EnvironmentObject var viewModel: OnboardingViewModel
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var isConnecting = false
    
    var body: some View {
        ZStack {
            // Edge-to-edge background
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
            // Header
            HStack {
                Button(
            action: {
                    viewModel.previousStep()
                    // HapticManager.shared.buttonTap() // TODO: Add HapticManager to Xcode project
                },
            label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
        )
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.1))
                )
                
                Spacer()
                
                Button("Skip") {
                    viewModel.nextStep()
                    // HapticManager.shared.buttonTap() // TODO: Add HapticManager to Xcode project
                }
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.appTextSecondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.appBorder.opacity(0.2))
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            
            Spacer()
            
            VStack(spacing: 40) {
                // Apple Health icon - minimalist
                Image(systemName: "heart")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.white)
                    .opacity(0.9)
                
                // Title and description
                VStack(spacing: 12) {
                    Text("Connect Apple Health")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.appText)
                    
                    Text("Sync weight data automatically")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.appTextSecondary)
                        .multilineTextAlignment(.center)
                }
                
                // Benefits
                VStack(alignment: .leading, spacing: 20) {
                    HealthBenefitRow(
                        icon: "arrow.triangle.2.circlepath",
                        text: "Auto log your weight"
                    )
                    
                    HealthBenefitRow(
                        icon: "chart.line.uptrend.xyaxis",
                        text: "Centralize your progress"
                    )
                    
                    HealthBenefitRow(
                        icon: "lock.shield",
                        text: "Data stays private"
                    )
                }
                .padding(.horizontal, 40)
            }
            
            Spacer()
            
            // Connect button
            VStack(spacing: 16) {
                Button(
            action: {
                    if !isConnecting {
                        connectHealthKit()
                        // HapticManager.shared.buttonTap() // TODO: Add HapticManager to Xcode project
                    }
                },
            label: {
                    HStack {
                        Text(isConnecting ? "Connecting..." : "Connect Apple Health")
                            .font(.system(size: 17, weight: .medium))
                        if !isConnecting {
                            Image(systemName: "heart")
                                .font(.system(size: 16))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .foregroundColor(.appText)
                }
        )
                .modernPrimaryButtonStyle()
                .disabled(isConnecting)
                
                Text("You can change this anytime in Settings")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.appTextTertiary)
                    .opacity(0.8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 50)
            }
        }
    }
    
    private func connectHealthKit() {
        isConnecting = true
        
        Task {
            let authorized = await healthKitManager.requestAuthorization()
            
            await MainActor.run {
                isConnecting = false
                viewModel.data.healthKitEnabled = authorized
                
                // If authorized, try to fetch data from HealthKit
                if authorized {
                    Task {
                        // Fetch all available data from HealthKit
                        
                        // Fetch date of birth
                        if let dateOfBirth = healthKitManager.fetchDateOfBirth() {
                            await MainActor.run {
                                viewModel.data.dateOfBirth = dateOfBirth
                            }
                        }
                        
                        // Fetch biological sex
                        if let biologicalSex = healthKitManager.fetchBiologicalSex() {
                            await MainActor.run {
                                viewModel.data.gender = OnboardingData.Gender(rawValue: biologicalSex)
                            }
                        }
                        
                        // Fetch height
                        if let heightInInches = try? await healthKitManager.fetchHeight() {
                            await MainActor.run {
                                let feet = Int(heightInInches) / 12
                                let inches = Int(heightInInches) % 12
                                viewModel.data.heightFeet = feet
                                viewModel.data.heightInches = inches
                            }
                        }
                    }
                }
                
                // Move to next step
                viewModel.nextStep()
            }
        }
    }
}

struct HealthBenefitRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .light))
                .foregroundColor(.appTextSecondary.opacity(0.8))
                .frame(width: 24)
            
            Text(text)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.appText)
            
            Spacer()
        }
    }
}

#Preview {
    HealthKitStepView()
        .environmentObject(OnboardingViewModel())
        .background(Color.appBackground)
}
