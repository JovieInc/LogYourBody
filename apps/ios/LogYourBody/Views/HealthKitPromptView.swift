//
// HealthKitPromptView.swift
// LogYourBody
//
import SwiftUI

struct HealthKitPromptView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var healthKitManager = HealthKitManager.shared
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            Capsule()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 32) {
                    // Close button
                    HStack {
                        Spacer()
                        Button(
                            action: {
                                // Save dismissal date
                                UserDefaults.standard.set(Date(), forKey: "lastHealthKitPromptDate")
                                isPresented = false
                            },
                            label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.gray.opacity(0.6))
                            }
                        )
                    }
                    .padding(.horizontal)

                    // Content
                    VStack(spacing: 40) {
                        // Apple Health icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 30)
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 1.0, green: 0.2, blue: 0.4),
                                            Color(red: 1.0, green: 0.4, blue: 0.6)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)

                            Image(systemName: "heart.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        }

                        // Title and description
                        VStack(spacing: 16) {
                            Text("Connect Apple Health")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.appText)

                            Text("Automatically sync your weight and body fat percentage between LogYourBody and Apple Health")
                                .font(.appBody)
                                .foregroundColor(.appTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        // Benefits with icons
                        VStack(alignment: .leading, spacing: 20) {
                            HealthKitBenefitRow(
                                icon: "arrow.triangle.2.circlepath",
                                iconColor: Color(red: 1.0, green: 0.3, blue: 0.5),
                                title: "Automatic Syncing",
                                description: "Weight & body fat data syncs in both directions"
                            )

                            HealthKitBenefitRow(
                                icon: "clock.fill",
                                iconColor: Color(red: 1.0, green: 0.3, blue: 0.5),
                                title: "Save Time",
                                description: "No need to manually enter data"
                            )

                            HealthKitBenefitRow(
                                icon: "lock.shield.fill",
                                iconColor: Color(red: 1.0, green: 0.3, blue: 0.5),
                                title: "Private & Secure",
                                description: "Your health data stays on your device"
                            )
                        }
                        .padding(.horizontal, 40)
                    }

                    // Buttons
                    VStack(spacing: 12) {
                        Button(
                            action: {
                                connectHealthKit()
                            },
                            label: {
                                HStack {
                                    if isConnecting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 18))
                                        Text("Connect Apple Health")
                                            .font(.appBody)
                                            .fontWeight(.semibold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 1.0, green: 0.2, blue: 0.4),
                                            Color(red: 1.0, green: 0.4, blue: 0.6)
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(Constants.cornerRadius)
                            }
                        )
                        .disabled(isConnecting)

                        Button(
                            action: {
                                UserDefaults.standard.set(Date(), forKey: "lastHealthKitPromptDate")
                                isPresented = false
                            },
                            label: {
                                Text("Not Now")
                                    .font(.appBody)
                                    .foregroundColor(.appTextSecondary)
                            }
                        )
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color.appBackground)
        .preferredColorScheme(.dark)
    }

    private func connectHealthKit() {
        isConnecting = true

        Task {
            let authorized = await healthKitManager.requestAuthorization()

            await MainActor.run {
                isConnecting = false

                if authorized {
                    // Successfully connected
                    isPresented = false

                    // Try to sync immediately
                    Task {
                        do {
                            // Setup background delivery for weight and body fat
                            try await healthKitManager.setupBackgroundDelivery()

                            // Setup background delivery for step count
                            try await healthKitManager.setupStepCountBackgroundDelivery()

                            // Sync weight and body fat data from HealthKit
                            try await healthKitManager.syncWeightFromHealthKit()

                            // Fetch today's step count
                            _ = try await healthKitManager.fetchTodayStepCount()
                        } catch {
                            // print("Initial HealthKit sync failed: \(error)")
                        }
                    }
                }
            }
        }
    }
}

struct HealthKitBenefitRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appBody)
                    .fontWeight(.medium)
                    .foregroundColor(.appText)

                Text(description)
                    .font(.appCaption)
                    .foregroundColor(.appTextSecondary)
            }

            Spacer()
        }
    }
}

#Preview {
    HealthKitPromptView(isPresented: .constant(true))
        .environmentObject(AuthManager())
}
